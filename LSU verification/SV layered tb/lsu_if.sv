`ifndef LSU_IF_SV
`define LSU_IF_SV

// lsu_if.sv
// Simple Interface Boilerplate for LSU Subsystem

interface lsu_if(input logic clk);
    logic        rst_n;

    // Inputs to DUT (driven by testbench/driver)
    logic [31:0] core_addr;
    logic [31:0] core_wdata;
    logic [4:0]  lsunit;

    // Outputs from DUT (sampled by testbench/monitor)
    logic [31:0] core_rdata;
    logic        core_stall;
    logic        core_err;


    clocking drv_cb @(posedge clk);
        default input #0.5 output #0.5;
        output core_addr, core_wdata, lsunit;
        input  core_stall;
    endclocking
    
    clocking mon_cb @(posedge clk);
        default input #0.5 output #0.5;
        input core_addr, core_wdata, lsunit;
        input core_rdata, core_stall, core_err;
    endclocking

    modport DRV (
    clocking drv_cb,
    input rst_n // input is used here because the driver is in need for rst from top to goto valid state
    );
    
    modport MON (
    clocking mon_cb,
    input rst_n
    );
    
endinterface: lsu_if

`endif
