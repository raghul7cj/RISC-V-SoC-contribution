`ifndef LSU_SEQUENCER_SV
`define LSU_SEQUENCER_SV

// lsu_sequencer.sv
// =========================================================================
// Sequencer / Test Generator for LSU Subsystem
// =========================================================================

import lsu_pkg::*;

class lsu_sequencer;

    // Mailbox to send generated transactions to driver
    mailbox #(lsu_transaction) drv_mbx;

    function new(mailbox #(lsu_transaction) drv_mbx);
        this.drv_mbx = drv_mbx;
    endfunction

    // =====================================================================
    // Helper: build and send a single transaction
    // =====================================================================
    task send(logic [31:0] addr, logic [31:0] wdata, logic [4:0] lsunit_ctrl);
        lsu_transaction txn = new();
        txn.addr   = addr;
        txn.wdata  = wdata;
        txn.lsunit = lsunit_ctrl;
        drv_mbx.put(txn);
    endtask

    // =====================================================================
    // Test 1 — SRAM word write then read back
    // SW to an SRAM address, then LW from same address.
    // =====================================================================
    task test_sram_word_rw();
        $display("[SEQ] Running test_sram_word_rw");
        send(SRAM_BASE, 32'hA5A55A5A, LSU_SW);
        send(SRAM_BASE, 32'h0,        LSU_LW);
    endtask

    // =====================================================================
    // Test 2 — SRAM byte lane write / LBU readback
    // Write a byte to each of the 4 byte offsets.
    // Read back each byte with LBU and verify.
    // =====================================================================
    task test_sram_byte_lanes();
        $display("[SEQ] Running test_sram_byte_lanes");
        // Write bytes to offsets 0, 1, 2, and 3
        // Note: wdata must keep the byte in the lowest 8 bits as it would be in a CPU register (unaligned).
        // The ls_unit is responsible for alignment (shifting).
        send(SRAM_BASE + 0, 32'h0000_00AA, LSU_SB); // SB to offset 0
        send(SRAM_BASE + 1, 32'h0000_00BB, LSU_SB); // SB to offset 1
        send(SRAM_BASE + 2, 32'h0000_00CC, LSU_SB); // SB to offset 2
        send(SRAM_BASE + 3, 32'h0000_00DD, LSU_SB); // SB to offset 3

        // Read back using LBU
        send(SRAM_BASE + 0, 32'h0, LSU_LBU); // LBU from offset 0
        send(SRAM_BASE + 1, 32'h0, LSU_LBU); // LBU from offset 1
        send(SRAM_BASE + 2, 32'h0, LSU_LBU); // LBU from offset 2
        send(SRAM_BASE + 3, 32'h0, LSU_LBU); // LBU from offset 3
    endtask

    // =====================================================================
    // Test 3 — SRAM halfword lane write / LHU readback
    // Write a halfword to lower and upper halfword offsets.
    // Read back with LHU.
    // =====================================================================
    task test_sram_half_lanes();
        $display("[SEQ] Running test_sram_half_lanes");
        send(SRAM_BASE + 0, 32'h0000_5566, LSU_SH); // SH to offset 0 
        send(SRAM_BASE + 2, 32'h0000_7788, LSU_SH); // SH to offset 2

        send(SRAM_BASE + 0, 32'h0, LSU_LHU); // LHU from offset 0
        send(SRAM_BASE + 2, 32'h0, LSU_LHU); // LHU from offset 2
    endtask

    // =====================================================================
    // Test 4 — Sign extension check
    // Store a negative byte/halfword value, load with LB/LH.
    // Verify that bit [31:8] or [31:16] are sign-extended.
    // =====================================================================
    task test_sram_sign_extend();
        $display("[SEQ] Running test_sram_sign_extend");
        // Store negative byte 0x8F, read back with LB (expecting 0xFFFFFFFF8F)
        send(SRAM_BASE, 32'h0000_008F, LSU_SB);
        send(SRAM_BASE, 32'h0,        LSU_LB);

        // Store negative halfword 0x8000, read back with LH (expecting 0xFFFF8000)
        send(SRAM_BASE + 4, 32'h0000_8000, LSU_SH);
        send(SRAM_BASE + 4, 32'h0,        LSU_LH);
    endtask

    // =====================================================================
    // Test 5 — MMIO write (AXI path)
    // SW to a MMIO address. Verify no core_err.
    // =====================================================================
    task test_mmio_write();
        $display("[SEQ] Running test_mmio_write");
        send(MMIO_BASE, 32'hCAFEFADE, LSU_SW); // SW to MMIO
    endtask

    // =====================================================================
    // Test 6 — MMIO read (AXI path)
    // LW from a MMIO address.
    // Verify returned data matches axi_lite_dummy_slave mock_reg init.
    // =====================================================================
    task test_mmio_read();
        $display("[SEQ] Running test_mmio_read");
        // LW from MMIO_BASE + 4 (axi_mock_reg[1] = 32'hdead0001)
        send(MMIO_BASE + 4, 32'h0, LSU_LW);
    endtask

    // =====================================================================
    // Test 7 — Out-of-range access (negative test)
    // Access an address that is not in SRAM or MMIO range.
    // Verify core_err is asserted.
    // =====================================================================
    task test_oor_access();
        $display("[SEQ] Running test_oor_access");
        send(32'hF000_0000, 32'h0, LSU_LW); // LW from OOR address
    endtask

    // =====================================================================
    // Test 8 — Fullword data pattern write/readback
    // Write each key data pattern, then read back with LW.
    // =====================================================================
    task test_sram_word_data_patterns();
        $display("[SEQ] Running test_sram_word_data_patterns");
        send(SRAM_BASE + 32'h100, 32'h0,          LSU_SW);
        send(SRAM_BASE + 32'h100, 32'h0,          LSU_LW);
        send(SRAM_BASE + 32'h104, 32'hFFFF_FFFF,  LSU_SW);
        send(SRAM_BASE + 32'h104, 32'h0,          LSU_LW);
        send(SRAM_BASE + 32'h108, 32'hA5A5_A5A5,  LSU_SW);
        send(SRAM_BASE + 32'h108, 32'h0,          LSU_LW);
        send(SRAM_BASE + 32'h10C, 32'h5A5A_5A5A,  LSU_SW);
        send(SRAM_BASE + 32'h10C, 32'h0,          LSU_LW);
        send(SRAM_BASE + 32'h110, 32'hF0F0_0F0F,  LSU_SW);
        send(SRAM_BASE + 32'h110, 32'h0,          LSU_LW);
        send(SRAM_BASE + 32'h114, 32'hDEAD_BEEF,  LSU_SW);
        send(SRAM_BASE + 32'h114, 32'h0,          LSU_LW);
    endtask

    // =====================================================================
    // Test 9 — Address-space boundary corner cases
    // =====================================================================
    task test_addr_boundary();
        $display("[SEQ] Running test_addr_boundary");
        // SRAM first and last writable words
        send(SRAM_BASE,       32'hA5A5_5A5A, LSU_SW);
        send(SRAM_BASE,       32'h0,         LSU_LW);
        send(SRAM_LIMIT - 3, 32'h5A5A_A5A5, LSU_SW);
        send(SRAM_LIMIT - 3, 32'h0,         LSU_LW);
        // Just below SRAM → OOR
        send(SRAM_BASE - 4,  32'h0, LSU_LW);
        // Just above SRAM → OOR
        send(SRAM_LIMIT + 1, 32'h0, LSU_LW);
    endtask

    // =====================================================================
    // Run all directed tests in sequence
    // =====================================================================
    task run_directed();
        test_sram_word_rw();
        test_sram_byte_lanes();
        test_sram_half_lanes();
        test_sram_sign_extend();
        test_sram_word_data_patterns();
        test_addr_boundary();
        test_mmio_write();
        test_mmio_read();
        test_oor_access();
        run_random(500, 0); // 500 SRAM-only transactions
        run_random(500, 1); // 500 ALL-regions transactions (SRAM + MMIO + OOR)
    endtask

    // ── Random phase ──────────────────────────────────────────────────────
    // all_regions=0 (default): SRAM only   |   all_regions=1: SRAM + MMIO + OOR
    task run_random(int unsigned n = 1000, bit all_regions = 0);
        string mode = all_regions ? "ALL regions" : "SRAM only";
        $display("[SEQ] Running random phase with %0d transactions (%s)", n, mode);
        repeat (n) begin
            lsu_transaction txn = new();
            if (all_regions) begin
                txn.c_sram_only.constraint_mode(0);
                txn.c_addr_ranges.constraint_mode(1);
            end
            if (!txn.randomize()) begin
                $error("[SEQ] Randomization failed for txn");
            end
            drv_mbx.put(txn);
        end
    endtask

endclass

`endif
