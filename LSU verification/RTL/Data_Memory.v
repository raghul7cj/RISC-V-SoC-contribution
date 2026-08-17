`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : Data_Memory
// Description : Synchronous 1-cycle Native SRAM Data Memory for RV32I.
//               Retains base-subtraction logic with standardized naming.
//////////////////////////////////////////////////////////////////////////////////

module Data_Memory (
    input             clk,
    input             rst_n,          // Standardized active-low reset
    input             sram_en,        // Standard Chip Enable / Request signal
    input             sram_we,        // Standard Write Enable (1=Write, 0=Read)
    input      [3:0]  sram_wmask,     // Standard Byte-write strobes (formerly WSTRB)
    input      [29:0] sram_addr,      // Word address input (core_addr[31:2])
    input      [31:0] sram_wdata,     // Aligned write data input
    
    output     [31:0] sram_rdata      // Read data output available at Cycle T+1
);

    // DMEM base address (word-aligned): 0x8000_1000 >> 2 = 0x2000_0400
    localparam DMEM_BASE = 30'h20000000;

    // Address offset calculation
    wire [29:0] local_addr_full = sram_addr - DMEM_BASE;

`ifdef SYNTHESIS
    wire [11:0] local_addr = local_addr_full[11:0];
    reg  [31:0] mem_array [4095:0];
`else
    wire [19:0] local_addr = local_addr_full[19:0];
    reg  [31:0] mem_array [1048575:0];
`endif

    // Internal register to achieve the required 1-cycle predictable read latency
`ifdef SYNTHESIS
    reg  [11:0] raddr_q;
`else
    reg  [19:0] raddr_q;
`endif

    // ==================================================
    // SYNCHRONOUS WRITE & ADDRESS LATCHING - 1 CYCLE READ LATENCY
    // - causes RAW hazard when READ after WRITE to same memory address (fix in hazard unit - forward or stall)
    // ==================================================
    //the input is held stable always
    reg  [31:0] wdata_r;
    reg  [19:0] addr_r ; 
    reg  [3:0] wmask_r ;
    reg  sram_en_r , sram_we_r   ;
    
    always@(posedge clk)
    begin
        if (!rst_n) begin
            wdata_r <= 0;
            addr_r <= 0;
            wmask_r <= 0;
            sram_en_r <= 0;
            sram_we_r <= 0;
        end else begin
            wdata_r <= sram_wdata;
            addr_r <= local_addr_full;
            wmask_r <= sram_wmask;
            sram_en_r <= sram_en;
            sram_we_r <= sram_we;
        end
    end

    always @(posedge clk) begin
        if(sram_en_r && sram_we_r )
        begin
            if(wmask_r[0] == 1)
                mem_array[addr_r][7:0]   <= wdata_r[7:0];
            if(wmask_r[1] == 1)
                mem_array[addr_r][15:8]  <= wdata_r[15:8];
            if(wmask_r[2] == 1)
                mem_array[addr_r][23:16] <= wdata_r[23:16];
            if(wmask_r[3] == 1)
                mem_array[addr_r][31:24] <= wdata_r[31:24];
        end
    end 
    // ==================================================
    // 1 cycle delayed READ - completed - here the read os delayed read is due to registered enables and addr
    // ==================================================
    assign sram_rdata = (sram_en_r && !sram_we_r) ? mem_array[addr_r] : 32'bx;


    // ==================================================
    // BEHAVIORAL INITIALIZATION (Simulation Only)
    // ==================================================
`ifndef SYNTHESIS
    initial begin : init_block
        integer i;
        for (i = 0; i < 1048576; i = i + 1) begin
            mem_array[i] = 32'h0;
        end
        $readmemh("dmem.hex", mem_array);
    end
`endif

endmodule