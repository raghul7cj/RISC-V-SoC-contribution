`ifndef LSU_COVERAGE_SV
`define LSU_COVERAGE_SV

// lsu_coverage.sv
// Coverage class for LSU Subsystem
// Tracks which operation types and address alignments are exercised.

import lsu_pkg::*;

class lsu_coverage;

    mailbox #(lsu_transaction) cov_mbx;
    int total_samples;

    covergroup lsu_cg with function sample(lsu_transaction txn);
        cp_op: coverpoint txn.lsunit {
            bins lb  = {LSU_LB};
            bins lh  = {LSU_LH};
            bins lw  = {LSU_LW};
            bins lbu = {LSU_LBU};
            bins lhu = {LSU_LHU};
            bins sb  = {LSU_SB};
            bins sh  = {LSU_SH};
            bins sw  = {LSU_SW};
            illegal_bins other = default;
        }
        cp_alignment: coverpoint txn.addr[1:0] {
            bins byte_aligned  = {2'b00};
            bins byte_offset_1 = {2'b01};
            bins byte_offset_2 = {2'b10};
            bins byte_offset_3 = {2'b11};
        }
        cp_op_x_alignment: cross cp_op, cp_alignment {
            ignore_bins sw_unaligned = binsof(cp_op.sw) && 
                                    binsof(cp_alignment) intersect {2'b01, 2'b10, 2'b11};
            ignore_bins lw_unaligned = binsof(cp_op.lw) && 
                                    binsof(cp_alignment) intersect {2'b01, 2'b10, 2'b11};
            ignore_bins sh_unaligned = binsof(cp_op.sh) && 
                                    binsof(cp_alignment) intersect {2'b01, 2'b11};
            ignore_bins lh_unaligned = binsof(cp_op.lh) && 
                                    binsof(cp_alignment) intersect {2'b01, 2'b11};
            ignore_bins lhu_unaligned = binsof(cp_op.lhu) &&
                                        binsof(cp_alignment) intersect {2'b01, 2'b11};
        }
        // ── Data pattern coverage ────────────────────────────────────────
        cp_wdata: coverpoint txn.wdata {
            bins zero     = {32'h0};
            bins ones     = {32'hFFFF_FFFF};
            bins aa55     = {32'hA5A5_A5A5};
            bins five5aa  = {32'h5A5A_5A5A};
            bins f00f     = {32'hF0F0_0F0F};
            bins deadbeef = {32'hDEAD_BEEF};
        }
        // ── Address region ──────────────────────────────────────────────
        cp_region: coverpoint txn.region {
            bins sram = {SRAM_REGION};
            bins mmio = {MMIO_REGION};
            bins oor  = {OOR_REGION};
        }
        // ── Error output ────────────────────────────────────────────────
        cp_err: coverpoint txn.err {
            bins no_err = {0};
            bins err    = {1};
        }
        // ── Region × op cross ───────────────────────────────────────────
        cp_op_x_region: cross cp_op, cp_region;
        // ── Address space corners ───────────────────────────────────────
        cp_addr: coverpoint txn.addr {
            bins sram_first = {SRAM_BASE};
            bins sram_last  = {SRAM_LIMIT - 3};
            bins mmio_first = {MMIO_BASE};
            bins mmio_last  = {MMIO_BASE + 12};
            bins oor_sample = {OOR_ADDR, 32'hF000_0000};
        }
    endgroup

    function new(mailbox #(lsu_transaction) cov_mbx);
        this.cov_mbx = cov_mbx;
        lsu_cg = new();
        total_samples = 0;
    endfunction

    task run();
        forever begin
            lsu_transaction txn;
            cov_mbx.get(txn);
            lsu_cg.sample(txn);
            total_samples++;
        end
    endtask

    function void print_report();
        $display("");
        $display("================================================");
        $display("        LSU COVERAGE REPORT");
        $display("================================================");
        $display("  Total samples : %0d", total_samples);
        $display("  Coverage      : %0.2f%%", lsu_cg.get_coverage());
        $display("================================================");
    endfunction

endclass

`endif
