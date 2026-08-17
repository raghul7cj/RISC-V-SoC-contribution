`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : axi_lite_dummy_slave
// Description : Dummy AXI4-Lite Slave to respond to peripheral accesses
//               during simulation. 
//               
//               PRACTICE EXERCISE: 
//               Implement the FSMs for Read/Write AXI transactions, 
//               handle handshakes (awready/wready/bvalid, arready/rvalid),
//               and mock a small memory array.
//////////////////////////////////////////////////////////////////////////////////

module axi_lite_dummy_slave (
    input             clk,
    input             rst_n,

    // Write Address Channel
    input      [31:0] s_axi_awaddr,
    input             s_axi_awvalid,
    output reg        s_axi_awready,

    // Write Data Channel
    input      [31:0] s_axi_wdata,
    input      [3:0]  s_axi_wstrb,
    input             s_axi_wvalid,
    output reg        s_axi_wready,

    // Write Response Channel
    output reg [1:0]  s_axi_bresp,
    output reg        s_axi_bvalid,
    input             s_axi_bready,

    // Read Address Channel
    input      [31:0] s_axi_araddr,
    input             s_axi_arvalid,
    output reg        s_axi_arready,

    // Read Data Channel
    output reg [31:0] s_axi_rdata,
    output reg [1:0]  s_axi_rresp,
    output reg        s_axi_rvalid,
    input             s_axi_rready
);

    // Delay cycles before asserting ready/valid signals (to test pipeline stalls)
    parameter DELAY_CYCLES = 2;

    // TODO: Define FSM states, registers, and memory array mapping.

    // TODO: Write FSM to handle Write Address, Data, and Response channels.

    // TODO: Write FSM to handle Read Address and Data channels.

endmodule
