`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : imem_controller
// Description : 1-Cycle Latency Pipelined Fetch Controller for RV32I.
//
//  SRAM Contract (Instruction_Memory.v):
//    Cycle T   : sram_en=1, sram_addr presented → raddr_q latched by SRAM
//    Cycle T+1 : sram_rdata = mem[raddr_q]  (combinational on latched addr)
//
// ── KEY FIX: sram_addr uses PC_next, not PC ──────────────────────────────────
//
//  Root cause of the OLD bug (sram_addr = PC[31:2]):
//    When the pipeline stalls (PC frozen at A), the SRAM keeps receiving A.
//    On stall RELEASE the PC register still holds A at combinatorial time
//    (it will only advance to A+4 at posedge). So the SRAM latches A for one
//    EXTRA cycle, causing instr@A to appear twice in the IF/ID register.
//
//  Fix: sram_addr = stall_in ? PC[31:2] : PC_next[31:2]
//    • During stall : send PC    (same address → SRAM output stays valid)
//    • Not stalled  : send PC_next (pre-fetch the next address)
//    At stall RELEASE stall_in drops to 0 BEFORE posedge, so the SRAM
//    receives PC_next = PC+4 (or branch target) and latches it. Next cycle
//    sram_rdata = instr@(PC+4) — no duplicate.
//
//  Startup correctness:
//    During reset, raddr_q is held at 0, which maps to the first instruction
//    (IMEM_BASE + 0). After reset, cycle 1: stall_in=0, PC_next=PC_RESET+4,
//    so sram_addr → local_addr 1. But sram_rdata is still mem[raddr_q=0] =
//    instr@PC_RESET (from the reset-held raddr_q), which is immediately
//    correct for the first IF/ID latch. No startup bubble needed.
//
// ── Branch / Redirect Flush ──────────────────────────────────────────────────
//
//  Cycle T   (PCSrcE=1, instruction_is_branch=1):
//    stall_in = 0 (spec_tag still 0, external StallF=0)
//    PC_next  = PCTargetE  →  sram_addr pre-fetches PCTargetE ✓
//    FlushD (from hazard unit) flushes IF/ID to NOP.
//    At posedge T: PC ← PCTargetE, spec_tag ← 1.
//
//  Cycle T+1 (spec_tag=1, imem_stall=1):
//    stall_in = 1  →  sram_addr = PC[31:2] = PCTargetE[31:2] (resend)
//    sram_rdata = instr@PCTargetE (from T's pre-fetch latch) — gated → NOP
//    At posedge T+1: PC held, spec_tag ← 0, SRAM latches PCTargetE again.
//
//  Cycle T+2 (spec_tag=0, imem_stall=0):
//    stall_in = 0  →  sram_addr = PC_next = PCTargetE+4 (pre-fetch next)
//    sram_rdata = instr@PCTargetE ✓ — passed through to pipeline.
//    IF/ID ← instr@PCTargetE, PCD = PCTargetE ✓.
//    At posedge T+2: PC ← PCTargetE+4, SRAM latches PCTargetE+4.
//
//  Net branch penalty: 2 cycles (bubble at T+1, correct instr at T+2).
//  No duplicate instruction at or after T+2. ✓
//////////////////////////////////////////////////////////////////////////////////

module imem_controller (
    input             clk,
    input             rst_n,               // Active-low reset

    // --- From PC / Control ---
    input      [31:0] PC,                  // Registered fetch PC (PCF)
    input      [31:0] PC_next,             // Mux output: next PC (combinational)
    input             instruction_is_branch,// 1 = branch/jump/trap redirect this cycle
    input             stall_in,            // Combined stall: StallF | imem_stall
                                           //   (fed back from this module's stall output
                                           //    OR'd with external StallF)

    // --- To Instruction_Memory ---
    output            sram_en,             // Chip enable (always 1 in run mode)
    output            sram_we,             // Tied 0 — fetch path is read-only
    output     [3:0]  sram_wmask,          // Tied 0
    output     [29:0] sram_addr,           // Word address sent to SRAM
    output     [31:0] sram_wdata,          // Tied 0

    // --- From Instruction_Memory ---
    input      [31:0] sram_rdata,          // Raw SRAM output, valid T+1 after addr

    // --- To Pipeline ---
    output     [31:0] instruction,         // COMBINATIONAL: real instruction or NOP
    output            stall                // HIGH during spec/drain window (1 cycle)
);

    localparam NOP = 32'h0000_0013;        // ADDI x0, x0, 0

    // =========================================================================
    // SRAM WRITE SIDE — always inactive from the fetch path
    // =========================================================================
    assign sram_en    = rst_n;             // Disabled only during reset
    assign sram_we    = 1'b0;
    assign sram_wmask = 4'b0000;
    assign sram_wdata = 32'd0;

    // =========================================================================
    // SRAM ADDRESS — pre-fetch / stall-safe
    //
    //  NOT stalled : send PC_next[31:2]
    //    • Normal    : PC_next = PCF + 4  (sequential pre-fetch)
    //    • Branch    : PC_next = PCTargetE (pre-fetch target; same cycle FlushD fires)
    //    • Trap      : PC_next = trap_target
    //
    //  Stalled      : send PC[31:2]
    //    • Hazard stall  : PC frozen → resend same addr; SRAM output stays valid
    //    • Drain window  : PC frozen at PCTargetE → resend to hold SRAM in sync
    //      (stall_in includes imem_stall fed back from spec_tag below)
    // =========================================================================
    assign sram_addr = (stall_in && !instruction_is_branch) ? PC[31:2] : PC_next[31:2];

    // =========================================================================
    // SPECULATIVE TAG
    //
    //  A redirect (instruction_is_branch=1) means the fetch that was just
    //  sent to the SRAM (at cycle T) is wrong-path. spec_tag goes HIGH
    //  for exactly one cycle (T+1) to mark that drain cycle.
    //
    //  It is SET  by registering instruction_is_branch.
    //  It is CLEARED the next cycle (instruction_is_branch is a 1-cycle pulse).
    // =========================================================================
    reg spec_tag;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            spec_tag <= 1'b0;
        else
            spec_tag <= instruction_is_branch;  // 1-cycle registered delay
    end

    // =========================================================================
    // STALL OUTPUT — combinational on spec_tag (registered)
    //
    //  HIGH during the 1-cycle drain window (T+1).
    //  Tells the hazard unit and fetch_cycle to freeze PC and hold IF/ID.
    //  Falls LOW at T+2 when spec_tag clears.
    // =========================================================================
    assign stall = spec_tag;

    // =========================================================================
    // INSTRUCTION GATE — combinational
    //
    //  Passes sram_rdata to the pipeline except when:
    //    • In reset  (!rst_n)  → output NOP
    //    • Drain window        → output NOP  (wrong-path data from SRAM)
    //
    //  In all other cases: sram_rdata is the correct instruction
    //  (because sram_addr was PC_next last cycle, so the SRAM has the
    //   right word ready).
    // =========================================================================
    assign instruction = (!rst_n || spec_tag) ? NOP : sram_rdata;

endmodule