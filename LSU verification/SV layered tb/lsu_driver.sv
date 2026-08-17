`ifndef LSU_DRIVER_SV
`define LSU_DRIVER_SV

// lsu_driver.sv
// Driver Class for LSU Subsystem

class lsu_driver;

    virtual lsu_if             vif;
    mailbox #(lsu_transaction) drv_mbx;

    int local_stall_cycles;
    int fd;

    function new(virtual lsu_if vif, mailbox #(lsu_transaction) drv_mbx);
        this.vif     = vif;
        this.drv_mbx = drv_mbx;
    endfunction

    // ── Main run task ────────────────────────────────────────────────────
    task run();
        $display("[LSU_DRIVER] started.");

        fd = $fopen("logfiles/driver.log", "w");
        if (fd == 0) begin
            $display("[LSU_DRIVER] ERROR: Could not open logfiles/driver.log for writing.");
        end

        // Idle the bus cleanly at first clock edge
        @(vif.drv_cb);
        vif.drv_cb.core_addr  <= 32'h0;
        vif.drv_cb.core_wdata <= 32'h0;
        vif.drv_cb.lsunit     <= 5'b0;
        local_stall_cycles = 0;

        forever begin
            lsu_transaction txn;
            drv_mbx.get(txn); // Blocks when idle (bus is already safe and 0)
            drive_txn(txn);   // Drives, waits for completion, idles
        end

    endtask

    task drive_txn(lsu_transaction txn);
        int stall;
        // Dump transaction to log (industry standard: [COMPONENT] key=value pairs)
        if (fd != 0) begin
            $fdisplay(fd, "[LSU_DRV] ====== Driving Transaction ======");
            if (txn.lsunit[3])
                $fdisplay(fd, "[LSU_DRV] op=%s addr=0x%08h wdata=0x%08h time=%0t",
                          lsunit_to_string(txn.lsunit), txn.addr, txn.wdata, $time);
            else
                $fdisplay(fd, "[LSU_DRV] op=%s addr=0x%08h time=%0t",
                          lsunit_to_string(txn.lsunit), txn.addr, $time);
            $fflush(fd);
        end

        // 1. Start: Drive stimulus onto the interface
        vif.drv_cb.core_addr  <= txn.addr;
        vif.drv_cb.core_wdata <= txn.wdata;
        vif.drv_cb.lsunit     <= txn.lsunit;
        // 2. Wait: Hold inputs stable as long as core_stall is high
        // Check stall count before starting the wait loop
        if (local_stall_cycles > 10000)
            $fatal(1, "[LSU_DRIVER] nfinite stall (>10000 cycles) detected before starting. Simulation aborted");

        do begin
            @(vif.drv_cb);
            local_stall_cycles++;
            // Check stall count inside the loop (redundant but safe)
            if (local_stall_cycles > 10000)
                $fatal(1, "[LSU_DRIVER] nfinite stall (>10000 cycles) detected. Simulation aborted");
        end while (vif.drv_cb.core_stall);
        
        // 3. Capture stall count before resetting
        stall = local_stall_cycles;

        // Idle: De-assert the request for 1 cycle
        vif.drv_cb.lsunit     <= 5'b0;
        vif.drv_cb.core_addr  <= 32'h0;
        vif.drv_cb.core_wdata <= 32'h0;
        local_stall_cycles = 0;
        @(vif.drv_cb);

        // Log completion
        if (fd != 0) begin
            $fdisplay(fd, "[LSU_DRV] ====== Complete (stall=%0d) ======", stall);
            $fflush(fd);
        end
    endtask

endclass

`endif
