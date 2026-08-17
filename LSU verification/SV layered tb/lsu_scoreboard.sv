`ifndef LSU_SCOREBOARD_SV
`define LSU_SCOREBOARD_SV

// lsu_scoreboard.sv
// =========================================================================
// Scoreboard for LSU Subsystem
// =========================================================================

class lsu_scoreboard;

    // Mailbox receiving captured transactions from monitor
    mailbox #(lsu_transaction) scb_mbx;

    // Reference model instance
    lsu_ref_model ref_model;

    // Statistics
    int unsigned total_txns;
    int unsigned pass_count;
    int unsigned fail_count;

    // Breakdown statistics
    int unsigned sram_txns;
    int unsigned sram_pass;
    int unsigned sram_fail;

    int unsigned mmio_txns;
    int unsigned mmio_pass;
    int unsigned mmio_fail;

    int unsigned oor_txns;
    int unsigned oor_pass;
    int unsigned oor_fail;

    // Log file handles
    int scb_fd;
    int err_fd;

    // Constructor
    function new(mailbox #(lsu_transaction) scb_mbx);
        this.scb_mbx   = scb_mbx;
        this.ref_model = new();
        total_txns     = 0;
        pass_count     = 0;
        fail_count     = 0;
        
        sram_txns      = 0;
        sram_pass      = 0;
        sram_fail      = 0;
        
        mmio_txns      = 0;
        mmio_pass      = 0;
        mmio_fail      = 0;
        
        oor_txns       = 0;
        oor_pass       = 0;
        oor_fail       = 0;

        scb_fd         = 0;
        err_fd         = 0;
    endfunction

    // =====================================================================
    // Main run task — gets transactions from monitor and checks them
    // =====================================================================
    task run();
        lsu_transaction txn;
        bit err_ok;
        bit rdata_ok;
        bit txn_ok;

        $display("[LSU_SCB] Scoreboard started.");

        scb_fd = $fopen("logfiles/scoreboard.log", "w");
        if (scb_fd == 0) begin
            $display("[LSU_SCB] ERROR: Could not open logfiles/scoreboard.log for writing.");
        end
        err_fd = $fopen("logfiles/errors.log", "w");
        if (err_fd == 0) begin
            $display("[LSU_SCB] ERROR: Could not open logfiles/errors.log for writing.");
        end

        forever begin
            scb_mbx.get(txn);
            total_txns++;
            rdata_ok = 1'b1;

            // Update ref model memory on valid store operations
            if ((txn.lsunit inside {LSU_SB, LSU_SH, LSU_SW}) && !ref_model.predict_err(txn.addr)) begin
                ref_model.do_write(txn.addr, txn.wdata, txn.lsunit);
            end

            // Check core_err output
            err_ok = check_err(txn);

            // Check core_rdata output on valid load operations
            if ((txn.lsunit inside {LSU_LB, LSU_LH, LSU_LW, LSU_LBU, LSU_LHU}) && !ref_model.predict_err(txn.addr) && !txn.err) begin
                rdata_ok = check_rdata(txn);
            end

            // Transaction is successful only if all checks pass
            txn_ok = err_ok && rdata_ok;

            // Log pass/fail result to scoreboard.log and issue $error on failure
            if (scb_fd != 0) begin
                if (txn_ok)
                    $fdisplay(scb_fd, "[LSU_SCB] [PASS] op=%s addr=0x%08h rdata=0x%08h err=%b",
                              lsunit_to_string(txn.lsunit), txn.addr, txn.rdata, txn.err);
                else begin
                    $fdisplay(scb_fd, "[LSU_SCB] [FAIL] op=%s addr=0x%08h rdata=0x%08h err=%b",
                              lsunit_to_string(txn.lsunit), txn.addr, txn.rdata, txn.err);
                    if (err_fd != 0)
                        $fdisplay(err_fd, "[FAIL] op=%s addr=0x%08h rdata=0x%08h err=%b",
                                  lsunit_to_string(txn.lsunit), txn.addr, txn.rdata, txn.err);
                    $error("[LSU_SCB] FAIL op=%s addr=0x%08h rdata=0x%08h err=%b",
                           lsunit_to_string(txn.lsunit), txn.addr, txn.rdata, txn.err);
                end
                $fflush(scb_fd);
            end

            // Increment region breakdown counters
            case (txn.region)
                SRAM_REGION: begin
                    sram_txns++;
                    if (txn_ok) sram_pass++; else sram_fail++;
                end
                MMIO_REGION: begin
                    mmio_txns++;
                    if (txn_ok) mmio_pass++; else mmio_fail++;
                end
                OOR_REGION: begin
                    oor_txns++;
                    if (txn_ok) oor_pass++; else oor_fail++;
                end
            endcase

            if (txn_ok) pass_count++; else fail_count++;
        end
    endtask

    // =====================================================================
    // Compare core_rdata against ref model predicted value
    // =====================================================================
    function automatic bit check_rdata(lsu_transaction txn);
        logic [31:0] predicted;
        predicted = ref_model.predict_read(txn.addr, txn.lsunit);

        if (predicted !== txn.rdata) begin
            if (scb_fd != 0)
                $fdisplay(scb_fd, "[LSU_SCB] FAIL rdata | Addr: 0x%h | Expected: 0x%h | Got: 0x%h",
                          txn.addr, predicted, txn.rdata);
            if (err_fd != 0)
                $fdisplay(err_fd, "[FAIL rdata] addr=0x%08h expected=0x%08h got=0x%08h",
                          txn.addr, predicted, txn.rdata);
            $error("[LSU_SCB] FAIL rdata addr=0x%08h expected=0x%08h got=0x%08h",
                   txn.addr, predicted, txn.rdata);
            return 1'b0;
        end else begin
            if (scb_fd != 0)
                $fdisplay(scb_fd, "[LSU_SCB] PASS rdata | Addr: 0x%h | Data: 0x%h", txn.addr, txn.rdata);
            return 1'b1;
        end
    endfunction

    // =====================================================================
    // Compare core_err against ref model predicted error
    // =====================================================================
    function automatic bit check_err(lsu_transaction txn);
        logic predicted_err;
        predicted_err = ref_model.predict_err(txn.addr);

        if (predicted_err !== txn.err) begin
            if (scb_fd != 0)
                $fdisplay(scb_fd, "[LSU_SCB] FAIL err | Addr: 0x%h | Expected: %b | Got: %b",
                          txn.addr, predicted_err, txn.err);
            if (err_fd != 0)
                $fdisplay(err_fd, "[FAIL err] addr=0x%08h expected=%b got=%b",
                          txn.addr, predicted_err, txn.err);
            $error("[LSU_SCB] FAIL err addr=0x%08h expected=%b got=%b",
                   txn.addr, predicted_err, txn.err);
            return 1'b0;
        end else begin
            if (scb_fd != 0)
                $fdisplay(scb_fd, "[LSU_SCB] PASS err | Addr: 0x%h | err: %b", txn.addr, txn.err);
            return 1'b1;
        end
    endfunction

    // =====================================================================
    // Print final summary after all tests complete
    // =====================================================================
    function void print_summary();
        if (scb_fd != 0) begin
            $fdisplay(scb_fd, "=================================================");
            $fdisplay(scb_fd, "             LSU SCOREBOARD SUMMARY              ");
            $fdisplay(scb_fd, "=================================================");
            $fdisplay(scb_fd, "  Total Transactions : %0d", total_txns);
            $fdisplay(scb_fd, "  Overall Passed     : %0d", pass_count);
            $fdisplay(scb_fd, "  Overall Failed     : %0d", fail_count);
            $fdisplay(scb_fd, "-------------------------------------------------");
            $fdisplay(scb_fd, "  REGION      |  TOTAL  |   PASS  |   FAIL  ");
            $fdisplay(scb_fd, "-------------------------------------------------");
            $fdisplay(scb_fd, "  SRAM        |  %5d  |  %5d  |  %5d", sram_txns, sram_pass, sram_fail);
            $fdisplay(scb_fd, "  MMIO        |  %5d  |  %5d  |  %5d", mmio_txns, mmio_pass, mmio_fail);
            $fdisplay(scb_fd, "  OOR (Error) |  %5d  |  %5d  |  %5d", oor_txns, oor_pass, oor_fail);
            $fdisplay(scb_fd, "=================================================");
            $fclose(scb_fd);
        end
        if (err_fd != 0) begin
            $fdisplay(err_fd, "==============================================");
            $fdisplay(err_fd, "  ERROR SUMMARY - %0d total failure(s)", fail_count);
            $fdisplay(err_fd, "  SRAM fails: %0d / %0d", sram_fail, sram_txns);
            $fdisplay(err_fd, "  MMIO fails: %0d / %0d", mmio_fail, mmio_txns);
            $fdisplay(err_fd, "  OOR  fails: %0d / %0d", oor_fail, oor_txns);
            $fdisplay(err_fd, "==============================================");
            $fclose(err_fd);
        end
        $display("=================================================");
        $display("             LSU SCOREBOARD SUMMARY              ");
        $display("=================================================");
        $display("  Total Transactions : %0d", total_txns);
        $display("  Overall Passed     : %0d", pass_count);
        $display("  Overall Failed     : %0d", fail_count);
        $display("-------------------------------------------------");
        $display("  REGION      |  TOTAL  |   PASS  |   FAIL  ");
        $display("-------------------------------------------------");
        $display("  SRAM        |  %5d  |  %5d  |  %5d", sram_txns, sram_pass, sram_fail);
        $display("  MMIO        |  %5d  |  %5d  |  %5d", mmio_txns, mmio_pass, mmio_fail);
        $display("  OOR (Error) |  %5d  |  %5d  |  %5d", oor_txns, oor_pass, oor_fail);
        $display("=================================================");
    endfunction

endclass

`endif
