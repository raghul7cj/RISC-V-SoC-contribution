`ifndef LSU_ASSERTIONS_SV
`define LSU_ASSERTIONS_SV

// lsu_assertions.sv
// SVA assertions for load operations in the LSU subsystem.
// Clocked on negedge clk — signals are stable: driver outputs settled,
// FSM state from previous posedge, combo outputs quiescent.
// Bound to lsu_if via direct instantiation in lsu_tb_top.

module lsu_assertions (
    input logic       clk,
    input logic       rst_n,
    input logic [4:0] lsunit,
    input logic [31:0] core_addr,
    input logic [31:0] core_rdata,
    input logic        core_stall,
    input logic        core_err
);

    import lsu_pkg::*;

    // ── Load decode ─────────────────────────────────────────
    wire is_load  = lsunit[4] & ~lsunit[3];
    wire is_store = lsunit[4] &  lsunit[3];
    wire addr_in_sram = (core_addr >= SRAM_BASE) && (core_addr <  SRAM_LIMIT);
    wire addr_in_mmio = (core_addr >= MMIO_BASE) && (core_addr <  MMIO_LIMIT);

    // ════════════════════════════════════════════════════════════
    // LOAD ASSERTIONS  (all @(negedge clk) for stable sampling)
    // ════════════════════════════════════════════════════════════

    // A_LOAD_STALL_DUR_SRAM: SRAM load stall must be exactly 1 cycle
    A_LOAD_STALL_DUR_SRAM : assert property (@(negedge clk) disable iff (!rst_n)
        $rose(is_load) && addr_in_sram
        |-> core_stall ##1 !core_stall)
        else $error("[ASSERT] A_LOAD_STALL_DUR_SRAM: SRAM stall != 1 cycle");

    // A_LOAD_RDATA_GOOD: rdata has no X/Z on the negedge after stall drops
    A_LOAD_RDATA_GOOD : assert property (@(negedge clk) disable iff (!rst_n)
        $fell(core_stall) && $past(is_load, 1) |-> !$isunknown(core_rdata))
        else $error("[ASSERT] A_LOAD_RDATA_GOOD: X/Z on rdata after load");

    // A_LOAD_RDATA_STABLE: rdata stays glitch-free after stall drops
    A_LOAD_RDATA_STABLE : assert property (@(negedge clk) disable iff (!rst_n)
        $fell(core_stall) && $past(is_load, 1) && !is_load
        |-> $stable(core_rdata))
        else $error("[ASSERT] A_LOAD_RDATA_STABLE: rdata glitch after stall");

    // A_NO_ERR_ON_SRAM_LOAD: SRAM loads never produce core_err
    A_NO_ERR_ON_SRAM_LOAD : assert property (@(negedge clk) disable iff (!rst_n)
        is_load && addr_in_sram |-> !core_err)
        else $error("[ASSERT] A_NO_ERR_ON_SRAM_LOAD: error on SRAM load");

    // A_MISALIGNED_NO_HANG: misaligned loads must not hang (stall drops within 20)
    wire misaligned_lh  = (lsunit == LSU_LH)  && (core_addr[0] != 1'b0);
    wire misaligned_lw  = (lsunit == LSU_LW)  && (core_addr[1:0] != 2'b00);
    wire misaligned_lhu = (lsunit == LSU_LHU) && (core_addr[0] != 1'b0);
    wire misaligned = misaligned_lh | misaligned_lw | misaligned_lhu;

    A_MISALIGNED_NO_HANG : assert property (@(negedge clk) disable iff (!rst_n)
        $rose(is_load) && misaligned |-> ##[1:20] !core_stall)
        else $error("[ASSERT] A_MISALIGNED_NO_HANG: misaligned load hangs");

    // ════════════════════════════════════════════════════════════
    // LOAD COVERAGE
    // ════════════════════════════════════════════════════════════

    C_LOAD_LB  : cover property (@(negedge clk) $rose(is_load) && (lsunit == LSU_LB));
    C_LOAD_LH  : cover property (@(negedge clk) $rose(is_load) && (lsunit == LSU_LH));
    C_LOAD_LW  : cover property (@(negedge clk) $rose(is_load) && (lsunit == LSU_LW));
    C_LOAD_LBU : cover property (@(negedge clk) $rose(is_load) && (lsunit == LSU_LBU));
    C_LOAD_LHU : cover property (@(negedge clk) $rose(is_load) && (lsunit == LSU_LHU));

    C_LOAD_STALL   : cover property (@(negedge clk) is_load && core_stall);
    C_LOAD_NOSTALL : cover property (@(negedge clk) is_load && !core_stall);
    C_LOAD_SRAM    : cover property (@(negedge clk) is_load && addr_in_sram);
    C_LOAD_MMIO    : cover property (@(negedge clk) is_load && addr_in_mmio);

endmodule

`endif
