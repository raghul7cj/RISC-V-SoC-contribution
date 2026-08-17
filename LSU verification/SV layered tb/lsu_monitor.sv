`ifndef LSU_MONITOR_SV
`define LSU_MONITOR_SV

// lsu_monitor.sv
// Monitor Class for LSU Subsystem

class lsu_monitor;

    virtual lsu_if             vif;
    mailbox #(lsu_transaction) mon_mbx;
    mailbox #(lsu_transaction) cov_mbx;

    integer tmp_stall_cnt = 0;
    int fd;

    function new(virtual lsu_if vif, mailbox #(lsu_transaction) mon_mbx, mailbox #(lsu_transaction) cov_mbx);
        this.vif     = vif;
        this.mon_mbx = mon_mbx;
        this.cov_mbx = cov_mbx;
    endfunction

    // ── Main run task ────────────────────────────────────────────────────
    task run();
        $display("[LSU_MONITOR] started.");
        
        fd = $fopen("logfiles/monitor.log", "w");
        if (fd == 0) begin
            $display("[LSU_MONITOR] ERROR: Could not open logfiles/monitor.log for writing.");
        end

        forever begin
            @(vif.mon_cb);
            sample();
        end
    endtask

    // ── TODO: implement sample() ─────────────────────────────────────────
    // Hints:
    //   Trigger condition: lsunit[4]==1 (active request) AND core_stall==0
    //   (stall just cleared — transaction is complete this cycle).
    //
    //   Filter: skip idle cycles where lsunit[4]==0 to avoid sending
    //   spurious NOP transactions to the scoreboard.
    //
    //   SRAM rdata timing: Data_Memory has 1-cycle registered read latency.
    //   For loads (lsunit[3]==0), core_rdata is valid on the cycle AFTER
    //   core_stall deasserts. Sample it one cycle later:
    //     @(posedge vif.clk);
    //     txn.rdata = vif.core_rdata;
    //
    //   stall_cycles: count how many consecutive cycles core_stall was
    //   high before it cleared. Store in txn.stall_cycles.
    //
    //   Once the transaction object is complete, call mon_mbx.put(txn).
    task sample();
        lsu_transaction txn;
        if( vif.mon_cb.lsunit[4] && vif.mon_cb.core_stall)
        begin
            tmp_stall_cnt++;
            if (tmp_stall_cnt > 10000)
                $fatal(1, "[LSU_MONITOR] Infinite stall (>10000 cycles) detected at monitor. Simulation aborted");
        end
        
        else if ( vif.mon_cb.lsunit[4] && !vif.mon_cb.core_stall)
        begin
            txn = new();
            txn.addr = vif.mon_cb.core_addr;
            txn.lsunit = vif.mon_cb.lsunit;
            
            if (txn.addr >= SRAM_BASE && txn.addr <= SRAM_LIMIT)
                txn.region = SRAM_REGION;
            else if (txn.addr >= MMIO_BASE && txn.addr <= MMIO_LIMIT)
                txn.region = MMIO_REGION;
            else
                txn.region = OOR_REGION;
            
            txn.err = vif.mon_cb.core_err;
            txn.stall_cycles = tmp_stall_cnt;

            tmp_stall_cnt = 0; // reset after puting value in tx class
            
            txn.wdata = vif.mon_cb.core_wdata;

            if (!vif.mon_cb.lsunit[3]) //load op
                txn.rdata = vif.mon_cb.core_rdata;
            else //store op
                txn.rdata = 'bx; // Unused for stores

            // Dump transaction to log (two-line format per industry convention)
            if (fd != 0) begin
                $fdisplay(fd, "[LSU_MON] ====== Transaction Start ======");
                if (txn.lsunit[3])
                    $fdisplay(fd, "[LSU_MON] op=%s addr=0x%08h wdata=0x%08h err=%b stall=%0d time=%0t",
                              lsunit_to_string(txn.lsunit), txn.addr, txn.wdata, txn.err, txn.stall_cycles, $time);
                else
                    $fdisplay(fd, "[LSU_MON] op=%s addr=0x%08h rdata=0x%08h err=%b stall=%0d time=%0t",
                              lsunit_to_string(txn.lsunit), txn.addr, txn.rdata, txn.err, txn.stall_cycles, $time);
                $fdisplay(fd, "[LSU_MON] ====== Transaction End ======");
                $fflush(fd);
            end

            // Each consumer gets an independent copy (industry standard
            // for thread safety — prevents shared-object corruption if
            // a consumer later modifies the transaction).
            mon_mbx.put(txn.copy());
            cov_mbx.put(txn.copy());
        end
        else if (!vif.mon_cb.lsunit[4] && tmp_stall_cnt>0) //resetting measure
        begin
            tmp_stall_cnt = 0;
        end
    endtask

endclass

`endif
