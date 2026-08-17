`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : fetch_cycle
//
// Description : Instruction Fetch (IF) stage and IF→ID pipeline register.
//   Integrates imem_controller with Instruction_Memory (1-cycle SRAM latency).
//
// ── Fixes applied (see individual sections for detail) ───────────────────────
//
//  FIX 1  imem_controller now receives PC_next and combined stall_in.
//         sram_addr = stall ? PCF : PC_next  eliminates the duplicate-instruction
//         that the old  sram_addr = PCF  caused on every stall release.
//
//  FIX 2  IF/ID register priority reordered:
//         OLD (wrong) : FlushD | imem_stall_raw  →  FLUSH
//                       StallD                   →  HOLD
//         NEW (correct): FlushD                  →  FLUSH  (branch/trap bubble)
//                        StallD | imem_stall_raw →  HOLD   (freeze register)
//         imem_stall_raw must HOLD (not flush) because the register already
//         holds a NOP from the FlushD the cycle before, and flushing again
//         would corrupt the valid_D flag if another branch fires while a
//         data stall is active.
//
// ── Pipeline register priority (highest → lowest) ────────────────────────────
//   1. Reset  (!rst)              clear all fields, valid = 0
//   2. FlushD                     insert bubble (NOP, valid=0)
//   3. StallD | imem_stall_raw    freeze (hold all fields)
//   4. Normal                     latch InstrF, PCF, PCPlus4F, valid=1
//
// ── Branch / Redirect timing ─────────────────────────────────────────────────
//   Cycle T   : EX detects branch. PCSrcE=1, PCTargetE=target.
//               PC_next → PCTargetE (mux). sram_addr → PCTargetE (pre-fetch).
//               FlushD=1 → IF/ID ← NOP (wrong-path instr removed). spec_tag→1.
//               PC ← PCTargetE at posedge T.
//
//   Cycle T+1 : spec_tag=1, imem_stall=1. PC frozen at PCTargetE.
//               sram_rdata = instr@PCTargetE (from T's pre-fetch). Gated→NOP.
//               IF/ID HOLDS (already NOP). FlushD=0.
//               sram_addr = PCF = PCTargetE (stall mode, resend addr).
//               spec_tag→0 at posedge T+1.
//
//   Cycle T+2 : spec_tag=0, stall=0. PC_next = PCTargetE+4.
//               sram_rdata = instr@PCTargetE ✓. InstrF = instr@PCTargetE ✓.
//               IF/ID ← instr@PCTargetE, PCD = PCTargetE ✓.
//               sram_addr = PCTargetE+4 (pre-fetch next).
//
//   Net penalty: 2 cycles. No duplicates. ✓
//////////////////////////////////////////////////////////////////////////////////

module fetch_cycle (
    input  clk,
    input  rst,                   // Active-low reset

    // --- Hazard / Control Unit Inputs ---
    input  PCSrcE,                // 1 → take branch/jump target
    input  wb_trap_redirect,      // 1 → take trap/return target
    input  StallF,                // Freeze PC (from hazard unit)
    input  StallD,                // Freeze IF/ID register (from hazard unit)
    input  FlushD,                // Flush IF/ID register (branch taken)

    // --- Branch/Jump/Trap Targets ---
    input  [31:0] PCTargetE,      // Branch/jump resolved target
    input  [31:0] trap_target,    // Trap/return target

    // --- Decode Stage Outputs ---
    output [31:0] InstrD,         // Instruction word to decode stage
    output [31:0] PCD,            // PC of instruction in decode stage
    output [31:0] PCPlus4D,       // PCD + 4
    output        valid_D,        // IF/ID holds a valid (non-bubble) instruction

    // --- Exception Outputs ---
    output        exc_valid_D,
    output [5:0]  exc_cause_D,
    output [31:0] exc_pc_D,
    output [31:0] exc_tval_D,

    // --- Stall Export (to Hazard Unit) ---
    // Hazard unit must OR this into its own StallF and StallD:
    //   StallF_final = StallF_hazard | imem_stall
    //   StallD_final = StallD_hazard | imem_stall
    output        imem_stall      // HIGH during 1-cycle SRAM drain window
);

    // =========================================================================
    // INTERNAL FETCH WIRES
    // =========================================================================
    wire [31:0] PCF;              // Current registered PC
    wire [31:0] PCPlus4F;         // PCF + 4
    wire [31:0] PC_next;          // Next-PC mux output (combinational)
    wire [31:0] InstrF;           // Instruction from imem_controller (NOP-gated)

    // Fetch-stage exception signals
    wire        exc_valid_F;
    wire [5:0]  exc_cause_F;
    wire [31:0] exc_pc_F;
    wire [31:0] exc_tval_F;

    // =========================================================================
    // IMEM CONTROLLER WIRES
    // =========================================================================
    wire        sram_en;
    wire        sram_we;
    wire [3:0]  sram_wmask;
    wire [29:0] sram_addr;
    wire [31:0] sram_wdata;
    wire [31:0] sram_rdata;
    wire        imem_stall_raw;   // stall output from imem_controller

    // =========================================================================
    // NEXT-PC MUX
    //   Priority (high → low): trap > branch/jump > sequential
    //   PC_next is also fed to imem_controller so sram_addr can pre-fetch
    //   the correct next instruction without waiting an extra cycle.
    // =========================================================================
    assign PC_next = wb_trap_redirect ? trap_target  :
                     PCSrcE           ? PCTargetE    :
                                        PCPlus4F;

    // =========================================================================
    // PROGRAM COUNTER REGISTER
    //   Stall source 1 : hazard unit StallF (data hazard)
    //   Stall source 2 : imem_stall_raw (branch drain window, 1 cycle)
    // =========================================================================
    PC program_counter (
        .clk    (clk),
        .rst    (rst),
        .PC     (PCF),
        .PC_Next(PC_next),
        .StallF ((StallF | imem_stall_raw) && !PCSrcE && !wb_trap_redirect) 
    );

    // =========================================================================
    // PC + 4 ADDER
    // =========================================================================
    PC_Adder PC_adder (
        .a(PCF),
        .b(32'h00000004),
        .c(PCPlus4F)
    );

    // =========================================================================
    // IMEM CONTROLLER  (FIX 1)
    //
    //   Two new inputs vs. the old version:
    //     PC_next  : enables sram_addr = PC_next during normal/release cycles,
    //                eliminating the duplicate instruction on stall release.
    //     stall_in : combined stall (StallF | imem_stall_raw).  During either
    //                source of stall the SRAM resends PCF so its output stays
    //                valid; at release stall_in=0 so sram_addr switches to
    //                PC_next immediately (no extra hold cycle).
    //
    //   instruction_is_branch : PCSrcE | wb_trap_redirect tells the controller
    //     a redirect is in flight so it sets spec_tag and gates wrong-path data.
    // =========================================================================
    imem_controller u_imem_ctrl (
        .clk                  (clk),
        .rst_n                (rst),                         // active-low
        .PC                   (PCF),
        .PC_next              (PC_next),                     // FIX 1 (new)
        .instruction_is_branch(PCSrcE | wb_trap_redirect),
        .stall_in             (StallF | imem_stall_raw),     // FIX 1 (new)
        .sram_en              (sram_en),
        .sram_we              (sram_we),
        .sram_wmask           (sram_wmask),
        .sram_addr            (sram_addr),
        .sram_wdata           (sram_wdata),
        .sram_rdata           (sram_rdata),
        .instruction          (InstrF),
        .stall                (imem_stall_raw)
    );

    // =========================================================================
    // INSTRUCTION MEMORY — SRAM
    //   Write ports are driven by imem_controller (tied to 0 for fetch path).
    // =========================================================================
    Instruction_Memory_new u_imem (
        .clk       (clk),
        .rst_n     (rst),
        .sram_en   (sram_en),
        .sram_we   (sram_we),
        .sram_wmask(sram_wmask),
        .sram_addr (sram_addr),
        .sram_wdata(sram_wdata),
        .sram_rdata(sram_rdata)
    );

    // =========================================================================
    // FETCH-STAGE EXCEPTION DETECTION
    //   Misaligned PC → instruction-address-misaligned (cause = 0).
    //   Checked against PC_next (the address about to be committed).
    // =========================================================================
    assign exc_valid_F = (PC_next[1:0] != 2'b00);
    assign exc_cause_F = 6'd0;
    assign exc_pc_F    = PC_next;
    assign exc_tval_F  = PC_next;

    // =========================================================================
    // STALL EXPORT TO HAZARD UNIT
    // =========================================================================
    assign imem_stall = imem_stall_raw;

    // =========================================================================
    // IF → ID PIPELINE REGISTER  (FIX 2)
    //
    //  Priority (highest → lowest):
    //
    //  1. RESET (!rst)
    //       Clear all fields; valid = 0.
    //
    //  2. FLUSH (FlushD)
    //       Insert bubble: NOP instruction, valid=0, exception cleared.
    //       Triggered by hazard unit when PCSrcE=1 or wb_trap_redirect=1.
    //       The WRONG-PATH instruction that was in the decode stage is removed.
    //
    //  3. STALL (StallD | imem_stall_raw)         ← FIX vs. old code
    //       HOLD all register fields unchanged.
    //       imem_stall_raw belongs here (hold), NOT in the flush condition.
    //       Reason: during the drain cycle the register already holds a NOP
    //       (placed there by FlushD the cycle before). Flushing again is
    //       harmless in the simple branch case, but becomes wrong if a data
    //       stall is active simultaneously—it would clobber valid_D and
    //       the exception fields with zeros unnecessarily.
    //       Holding is always correct.
    //
    //  4. NORMAL
    //       Advance: latch InstrF (NOP-gated by imem_controller), PCF,
    //       PCPlus4F, and the fetch-stage exception bundle.
    //       valid_D=1 signals to decode that the register has live data.
    // =========================================================================
    reg [31:0] InstrF_reg;
    reg [31:0] PCF_reg;
    reg [31:0] PCPlus4F_reg;
    reg        valid_D_reg;
    reg        exc_valid_reg;
    reg [5:0]  exc_cause_reg;
    reg [31:0] exc_pc_reg;
    reg [31:0] exc_tval_reg;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            // ----------------------------------------------------------
            // RESET: clear pipeline register
            // ----------------------------------------------------------
            InstrF_reg    <= 32'h0000_0013;  // NOP
            PCF_reg       <= 32'h0000_0000;
            PCPlus4F_reg  <= 32'h0000_0000;
            valid_D_reg   <= 1'b0;
            exc_valid_reg <= 1'b0;
            exc_cause_reg <= 6'd0;
            exc_pc_reg    <= 32'h0000_0000;
            exc_tval_reg  <= 32'h0000_0000;
        end
        else if (FlushD) begin
            // ----------------------------------------------------------
            // FLUSH: branch taken or trap redirect
            //   Remove the wrong-path instruction from decode.
            //   imem_controller has already set sram_addr to the correct
            //   target (PC_next), so no extra action is needed here.
            // ----------------------------------------------------------
            InstrF_reg    <= 32'h0000_0013;  // canonical NOP bubble
            PCF_reg       <= 32'h0000_0000;
            PCPlus4F_reg  <= 32'h0000_0000;
            valid_D_reg   <= 1'b0;
            exc_valid_reg <= 1'b0;
            exc_cause_reg <= 6'd0;
            exc_pc_reg    <= 32'h0000_0000;
            exc_tval_reg  <= 32'h0000_0000;
        end
        else if (StallD | imem_stall_raw) begin
            // ----------------------------------------------------------
            // STALL: freeze register (FIX 2 — was incorrectly a flush)
            //
            //   Sources:
            //     StallD         : hazard unit (load-use or other data hazard)
            //     imem_stall_raw : SRAM drain window (1 cycle after redirect)
            //
            //   The register holds whatever it currently contains.
            //   In the branch case this is a NOP bubble (placed by FlushD
            //   the previous cycle) — holding a NOP is correct.
            //   In a pure data-hazard stall this preserves the valid
            //   instruction and its associated PC and exception state.
            // ----------------------------------------------------------
            InstrF_reg    <= InstrF_reg;
            PCF_reg       <= PCF_reg;
            PCPlus4F_reg  <= PCPlus4F_reg;
            valid_D_reg   <= valid_D_reg;
            exc_valid_reg <= exc_valid_reg;
            exc_cause_reg <= exc_cause_reg;
            exc_pc_reg    <= exc_pc_reg;
            exc_tval_reg  <= exc_tval_reg;
        end
        else begin
            // ----------------------------------------------------------
            // NORMAL: advance the pipeline register
            //
            //   InstrF is already NOP-gated by imem_controller:
            //     correct fetch  → real instruction
            //     wrong-path     → NOP (spec_tag=1 gate, should not reach
            //                      here because imem_stall_raw=1 above, but
            //                      the gate is a safety net)
            //   PCF_reg = PCF: the address of the instruction now in InstrF,
            //   which is what decode/EX/WB need as the instruction PC.
            // ----------------------------------------------------------
            InstrF_reg    <= InstrF;
            PCF_reg       <= PCF;
            PCPlus4F_reg  <= PCPlus4F;
            valid_D_reg   <= 1'b1;
            exc_valid_reg <= exc_valid_F;
            exc_cause_reg <= exc_cause_F;
            exc_pc_reg    <= exc_pc_F;
            exc_tval_reg  <= exc_tval_F;
        end
    end

    // =========================================================================
    // OUTPUTS TO DECODE STAGE
    // =========================================================================
    assign InstrD      = InstrF_reg;
    assign PCD         = PCF_reg;
    assign PCPlus4D    = PCPlus4F_reg;
    assign valid_D     = valid_D_reg;
    assign exc_valid_D = exc_valid_reg;
    assign exc_cause_D = exc_cause_reg;
    assign exc_pc_D    = exc_pc_reg;
    assign exc_tval_D  = exc_tval_reg;

endmodule
