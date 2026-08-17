`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : axi_lite_dummy_slave_ref
// Description : Reference implementation of the Dummy AXI4-Lite Slave.
//////////////////////////////////////////////////////////////////////////////////

module axi_lite_dummy_slave_ref (
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

    // Latency controls
    parameter DELAY_CYCLES = 2; // Number of wait cycles before responding

    // Internal mock registers
    reg [31:0] mock_reg [0:3];
    reg [31:0] write_addr;
    reg [31:0] read_addr;
    reg [7:0]  w_delay_cnt;
    reg [7:0]  r_delay_cnt;

    // FSM States
    reg [1:0] w_state;
    reg [1:0] r_state;

    localparam W_IDLE  = 2'b00;
    localparam W_WAIT  = 2'b01;
    localparam W_RESP  = 2'b10;

    localparam R_IDLE  = 2'b00;
    localparam R_WAIT  = 2'b01;
    localparam R_DATA  = 2'b10;

    // Initialize mock registers
    integer i;
    initial begin
        for (i = 0; i < 4; i = i + 1) begin
            mock_reg[i] = 32'hdead0000 + i;
        end
    end

    // Write Handling
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            w_delay_cnt   <= 8'd0;
            write_addr    <= 32'h0;
            w_state       <= W_IDLE;
        end else begin
            case (w_state)
                W_IDLE: begin
                    s_axi_bvalid <= 1'b0;
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        write_addr  <= s_axi_awaddr;
                        w_delay_cnt <= 8'd0;
                        w_state     <= W_WAIT;
                    end
                end

                W_WAIT: begin
                    if (w_delay_cnt >= DELAY_CYCLES) begin
                        s_axi_awready <= 1'b1;
                        s_axi_wready  <= 1'b1;
                        
                        // Perform Write mapping
                        // Limit mapping to 4 registers (offset address[3:2])
                        mock_reg[write_addr[3:2]] <= s_axi_wdata;
                        
                        $display("[AXI_DUMMY_WRITE] Address: 0x%h, Data: 0x%h, Strobe: %b, Time: %t", 
                                 write_addr, s_axi_wdata, s_axi_wstrb, $time);
                        
                        w_state <= W_RESP;
                    end else begin
                        w_delay_cnt <= w_delay_cnt + 1;
                    end
                end

                W_RESP: begin
                    s_axi_awready <= 1'b0;
                    s_axi_wready  <= 1'b0;
                    s_axi_bvalid  <= 1'b1;
                    s_axi_bresp   <= 2'b00; // OKAY response
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        w_state      <= W_IDLE;
                    end
                end
            endcase
        end
    end

    // Read Handling
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= 32'h0;
            r_delay_cnt   <= 8'd0;
            read_addr     <= 32'h0;
            r_state       <= R_IDLE;
        end else begin
            case (r_state)
                R_IDLE: begin
                    s_axi_rvalid <= 1'b0;
                    if (s_axi_arvalid) begin
                        read_addr   <= s_axi_araddr;
                        r_delay_cnt <= 8'd0;
                        r_state     <= R_WAIT;
                    end
                end

                R_WAIT: begin
                    if (r_delay_cnt >= DELAY_CYCLES) begin
                        s_axi_arready <= 1'b1;
                        r_state       <= R_DATA;
                    end else begin
                        r_delay_cnt <= r_delay_cnt + 1;
                    end
                end

                R_DATA: begin
                    s_axi_arready <= 1'b0;
                    s_axi_rvalid  <= 1'b1;
                    s_axi_rresp   <= 2'b00; // OKAY response
                    s_axi_rdata   <= mock_reg[read_addr[3:2]];
                    
                    $display("[AXI_DUMMY_READ] Address: 0x%h, Data: 0x%h, Time: %t", 
                             read_addr, mock_reg[read_addr[3:2]], $time);

                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        r_state      <= R_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
