`ifndef LSU_ENV_SV
`define LSU_ENV_SV

// lsu_env.sv
// =========================================================================
// Environment — wires driver, monitor, scoreboard and sequencer together.
// Pure structural boilerplate. Nothing to implement here.
// =========================================================================

// ── Dependency order: base classes first, then consumers ────────────────
`include "lsu_transaction.sv"   // transaction class (used by all)
`include "lsu_ref_model.sv"     // reference model (used by scoreboard)
`include "lsu_driver.sv"        // drives DUT
`include "lsu_monitor.sv"       // samples DUT outputs
`include "lsu_scoreboard.sv"    // checks DUT vs ref model
`include "lsu_sequencer.sv"     // generates stimulus
`include "lsu_coverage.sv"      // functional coverage
`include "lsu_assertions.sv"   // SVA load assertions

class lsu_env;

    // Components
    lsu_driver     driver;
    lsu_monitor    monitor;
    lsu_scoreboard scoreboard;
    lsu_sequencer  sequencer;
    lsu_coverage   coverage;

    // Mailboxes
    mailbox #(lsu_transaction) drv_mbx; // sequencer → driver
    mailbox #(lsu_transaction) scb_mbx; // monitor   → scoreboard
    mailbox #(lsu_transaction) cov_mbx; // monitor   → coverage

    // Virtual interface handle
    virtual lsu_if vif;

    function new(virtual lsu_if vif);
        this.vif    = vif;
        drv_mbx     = new(1);
        scb_mbx     = new(1);
        cov_mbx     = new(1);

        driver      = new(vif, drv_mbx);
        monitor     = new(vif, scb_mbx, cov_mbx);
        scoreboard  = new(scb_mbx);
        sequencer   = new(drv_mbx);
        coverage    = new(cov_mbx);
    endfunction

    task run();
        // Launch all components in parallel background threads
        fork
            driver.run();
            monitor.run();
            scoreboard.run();
            coverage.run();
        join_none

        // Run directed test sequences (blocks until done)
        sequencer.run_directed();

        // Wait a few cycles for final transactions to flush
        repeat(20) @(posedge vif.clk);

        // Print scoreboard summary
        scoreboard.print_summary();
        coverage.print_report();
    endtask

endclass

`endif
