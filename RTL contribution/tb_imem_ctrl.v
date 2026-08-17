`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////
// tb_fetch_cycle.v  — self-checking testbench for fetch pipeline
//
// Three scenarios:
//   1. Normal sequential fetch  — PCD = +4 each cycle, no gaps
//   2. Branch redirect          — 2-cycle penalty, correct target, no dup
//   3. Data-hazard stall        — hold during stall, clean +4 on release
//
// Sampling rule: all checks are at @(posedge clk) #1
//   i.e. reading the newly-committed register state right after each edge.
//   imem_stall is checked at the SAME posedge where the branch fires
//   (that is when spec_tag transitions 0→1 and stall goes HIGH).
//////////////////////////////////////////////////////////////////////////


// ----------------------------------------------------------------
module tb_fetch_cycle;

    reg         clk, rst;
    reg         PCSrcE, wb_trap_redirect;
    reg         StallF, StallD, FlushD;
    reg  [31:0] PCTargetE, trap_target;

    wire [31:0] InstrD, PCD, PCPlus4D;
    wire        valid_D, imem_stall;
    wire        exc_valid_D;
    wire [4:0]  exc_cause_D;
    wire [31:0] exc_pc_D, exc_tval_D;

    fetch_cycle dut (
        .clk             (clk),
        .rst             (rst),
        .PCSrcE          (PCSrcE),
        .wb_trap_redirect(wb_trap_redirect),
        .StallF          (StallF),
        .StallD          (StallD),
        .FlushD          (FlushD),
        .PCTargetE       (PCTargetE),
        .trap_target     (trap_target),
        .InstrD          (InstrD),
        .PCD             (PCD),
        .PCPlus4D        (PCPlus4D),
        .valid_D         (valid_D),
        .exc_valid_D     (exc_valid_D),
        .exc_cause_D     (exc_cause_D),
        .exc_pc_D        (exc_pc_D),
        .exc_tval_D      (exc_tval_D),
        .imem_stall      (imem_stall)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors;

    // ── helpers ────────────────────────────────────────────────────
    task idle;
        begin
            PCSrcE=0; wb_trap_redirect=0;
            StallF=0;  StallD=0; FlushD=0;
            PCTargetE=0; trap_target=0;
        end
    endtask

    task do_reset;
        begin idle; rst=0; repeat(3) @(posedge clk);
              @(negedge clk); rst=1; end
    endtask

    task expect_eq;
        input [255:0] tag;
        input [31:0]  got, exp;
        begin
            if (got !== exp) begin
                $display("  FAIL [%0s]  got=%08h  exp=%08h", tag, got, exp);
                errors = errors + 1;
            end else
                $display("  PASS [%0s]  = %08h", tag, got);
            end

    endtask

    task expect_bit;
        input [255:0] tag;
        input         got, exp;
        begin
            if (got !== exp) begin
                $display("  FAIL [%0s]  got=%b  exp=%b", tag, got, exp);
                errors = errors + 1;
            end else
                $display("  PASS [%0s]  = %b", tag, got);
        end
    endtask

    // ================================================================
    initial begin
        errors = 0;
        $dumpfile("tb_fetch_cycle.vcd");
        $dumpvars(0, tb_fetch_cycle);

        // ============================================================
        // SCENARIO 1 — Normal sequential fetch
        //   PCD must advance by exactly +4 every valid cycle.
        //   PCPlus4D must always equal PCD + 4.
        // ============================================================
        $display("\n=== S1: Normal sequential fetch ===");
        do_reset;
        begin : seq
            reg [31:0] prev_pcd;
            integer i;
            prev_pcd = 32'hFFFF_FFFF;
            for (i = 0; i < 8; i = i + 1) begin
                @(posedge clk); #1;
                if (valid_D) begin
                    if (prev_pcd !== 32'hFFFF_FFFF) begin
                        // Check sequential +4
                        if (PCD !== prev_pcd + 4) begin
                            $display("  FAIL [seq %0d] PCD=%08h expected prev+4=%08h",
                                     i, PCD, prev_pcd+4);
                            errors = errors + 1;
                        end else
                            $display("  PASS [seq %0d] PCD=%08h (prev+4)", i, PCD);
                        // Check PCPlus4D = PCD + 4
                        if (PCPlus4D !== PCD + 4) begin
                            $display("  FAIL [seq %0d PCPlus4] PCPlus4D=%08h PCD=%08h",
                                     i, PCPlus4D, PCD);
                            errors = errors + 1;
                        end
                    end
                    prev_pcd = PCD;
                end
            end
        end

        // ============================================================
        // SCENARIO 2 — Branch redirect
        //
        //  Timeline (all checks at posedge + 1ps):
        //    Negedge before T : assert PCSrcE=1, FlushD=1, PCTargetE=0x8000_0100
        //    Posedge T        : branch fires. spec_tag→1. IF/ID flushed.
        //                       imem_stall=1 (spec_tag just SET).
        //                       valid_D=0, InstrD=NOP.
        //                       De-assert PCSrcE / FlushD immediately after.
        //    Posedge T+1      : drain cycle drains. spec_tag→0.
        //                       imem_stall=0 (spec_tag just CLEARED).
        //                       IF/ID still NOP (held via imem_stall stall path).
        //    Posedge T+2      : correct instruction at PCTargetE in decode.
        //                       PCD=0x8000_0100, valid_D=1.
        //    Posedge T+3      : next instruction, PCD=0x8000_0104. NO DUPLICATE.
        // ============================================================
        $display("\n=== S2: Branch redirect ===");
        do_reset;
        repeat(4) @(posedge clk);   // let pipeline fill

        // Fire branch at negedge → evaluated at posedge T
        @(negedge clk);
        PCSrcE=1; FlushD=1; PCTargetE=32'h8000_0100;

        // Posedge T: branch fires, spec_tag goes 0→1 HERE
        @(posedge clk); #1;
        expect_bit("T  imem_stall", imem_stall, 1'b1);
        expect_bit("T  valid_D",    valid_D,    1'b0);
        expect_eq ("T  InstrD",     InstrD,     32'h0000_0013);
        PCSrcE=0; FlushD=0;

        // Posedge T+1: spec_tag goes 1→0 HERE (drain window ends)
        @(posedge clk); #1;
        expect_bit("T+1 imem_stall", imem_stall, 1'b0);
        expect_bit("T+1 valid_D",    valid_D,    1'b0);
        expect_eq ("T+1 InstrD",     InstrD,     32'h0000_0013);

        // Posedge T+2: first instruction from branch target
        @(posedge clk); #1;
        expect_eq ("T+2 PCD",    PCD,    32'h8000_0100);
        expect_bit("T+2 valid_D", valid_D, 1'b1);

        // Posedge T+3: second instruction — NOT a duplicate
        @(posedge clk); #1;
        expect_eq ("T+3 PCD (no dup)", PCD, 32'h8000_0104);

        // Posedge T+4: third — still no duplicate
        @(posedge clk); #1;
        expect_eq ("T+4 PCD", PCD, 32'h8000_0108);

        // ============================================================
        // SCENARIO 3 — Data-hazard stall (2 cycles)
        //
        //  The ID-stage instruction (PCD=X) must be held for the stall
        //  duration.  When the stall clears, PCD must advance to X+4 —
        //  NOT repeat X (which would be the old duplicate-instruction bug).
        //
        //  Timeline:
        //    posedge M   : pre_stall captured, PCD=X
        //    negedge M   : StallF=StallD=1
        //    posedge M+1 : stall[1] — PCD still X
        //    posedge M+2 : stall[2] — PCD still X
        //    negedge M+2 : StallF=StallD=0  (release)
        //    posedge M+3 : PCD = X+4  (IF instruction flows into ID)
        //    posedge M+4 : PCD = X+8  (next, no dup)
        // ============================================================
        $display("\n=== S3: Data-hazard stall ===");
        do_reset;
        repeat(5) @(posedge clk);   // let pipeline fill

        begin : stall_chk
            reg [31:0] pre_pcd;

            // posedge M — capture baseline
            @(posedge clk); #1;
            pre_pcd = PCD;
            $display("  INFO pre-stall  PCD=%08h", pre_pcd);

            // Assert stall
            @(negedge clk); StallF=1; StallD=1;

            // posedge M+1 — must hold
            @(posedge clk); #1;
            expect_eq ("stall[1] PCD held", PCD, pre_pcd);

            // posedge M+2 — must hold
            @(posedge clk); #1;
            expect_eq ("stall[2] PCD held", PCD, pre_pcd);

            // Release stall
            @(negedge clk); StallF=0; StallD=0;

            // posedge M+3 — PCD must advance to pre_pcd+4, NOT repeat pre_pcd
            @(posedge clk); #1;
            expect_eq ("release+1 PCD=pre+4 (no dup)", PCD, pre_pcd + 4);

            // posedge M+4 — normal +4 again
            @(posedge clk); #1;
            expect_eq ("release+2 PCD=pre+8", PCD, pre_pcd + 8);

            // posedge M+5 — still clean
            @(posedge clk); #1;
            expect_eq ("release+3 PCD=pre+12", PCD, pre_pcd + 12);
        end

        // ============================================================
        // Summary
        // ============================================================
        #20;
        if (errors == 0)
            $display("\n*** ALL %0d CHECKS PASSED ***", 0);
        else
            $display("\n*** %0d CHECK(S) FAILED ***", errors);
        $finish;
    end
endmodule

    // VCD info: dumpfile tb_fetch_cycle.vcd opened for output.

    // === S1: Normal sequential fetch ===
    // PASS [seq 1] PCD=80000004 (prev+4)
    // PASS [seq 2] PCD=80000008 (prev+4)
    // PASS [seq 3] PCD=8000000c (prev+4)
    // PASS [seq 4] PCD=80000010 (prev+4)
    // PASS [seq 5] PCD=80000014 (prev+4)
    // PASS [seq 6] PCD=80000018 (prev+4)
    // PASS [seq 7] PCD=8000001c (prev+4)

    // === S2: Branch redirect ===
    // PASS [T  imem_stall]  = 1
    // PASS [T  valid_D]  = 0
    // PASS [T  InstrD]  = 00000013
    // PASS [T+1 imem_stall]  = 0
    // PASS [T+1 valid_D]  = 0
    // PASS [T+1 InstrD]  = 00000013
    // PASS [T+2 PCD]  = 80000100
    // PASS [T+2 valid_D]  = 1
    // PASS [T+3 PCD (no dup)]  = 80000104
    // PASS [T+4 PCD]  = 80000108

    // === S3: Data-hazard stall ===
    // INFO pre-stall  PCD=80000014
    // PASS [stall[1] PCD held]  = 80000014
    // PASS [stall[2] PCD held]  = 80000014
    // PASS [release+1 PCD=pre+4 (no dup)]  = 80000018
    // PASS [release+2 PCD=pre+8]  = 8000001c
    // PASS [release+3 PCD=pre+12]  = 80000020

    // *** ALL 0 CHECKS PASSED ***
    // tb_fetch_cycle.v:266: $finish called at 386000 (1ps)
    // Done