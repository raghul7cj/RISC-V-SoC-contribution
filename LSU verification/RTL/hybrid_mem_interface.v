`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : hybrid_mem_interface
// Description : Address-decoder and Bus Router mapping an incoming LSU memory 
//               request transaction to either native SRAM or an AXI4-Lite bus.
//////////////////////////////////////////////////////////////////////////////////

module hybrid_mem_interface (
    input             clk,
    input             rst_n,

    // =========================================================================
    // 1. INPUT FROM LOAD/STORE UNIT (LSU Memory Access Bus)
    // =========================================================================
    input             mem_req,        // Valid memory transaction request
    input             mem_we,         // Write Enable (1=Write, 0=Read)
    input      [31:0] mem_addr,       // Target byte address
    input      [31:0] mem_wdata,      // Aligned data to be written
    input      [3:0]  mem_be,         // Byte enables / Write strobes
    
    output reg [31:0] mem_rdata,      // Routed read data back to LSU
    output reg        mem_stall,      // Aggregated stall signal back to LSU
    output reg        mem_err,        // Aggregated error fault signal back to LSU

    // =========================================================================
    // 2. OUTPUT TO NATIVE SRAM INTERFACE (DMEM Block)
    // =========================================================================
    output reg        sram_en,        // SRAM Chip Enable
    output reg        sram_we,        // SRAM Write Enable
    output reg [3:0]  sram_wmask,     // SRAM Byte write mask
    output reg [29:0] sram_addr,      // SRAM Word Address (Truncated [31:2])
    output reg [31:0] sram_wdata,     // SRAM Write Data
    
    input      [31:0] sram_rdata,     // SRAM Read Data input (2-cycle latency)

    // =========================================================================
    // 3. OUTPUT TO AXI4-LITE BUS INTERFACE (Peripheral Interconnect)
    // =========================================================================
    // Write Address Channel
    output reg [31:0] m_axi_awaddr,
    output reg        m_axi_awvalid,
    input             m_axi_awready,

    // Write Data Channel
    output reg [31:0] m_axi_wdata,
    output reg [3:0]  m_axi_wstrb,
    output reg        m_axi_wvalid,
    input             m_axi_wready,

    // Write Response Channel
    input      [1:0]  m_axi_bresp,
    input             m_axi_bvalid,
    output reg        m_axi_bready,

    // Read Address Channel
    output reg [31:0] m_axi_araddr,
    output reg        m_axi_arvalid,
    input             m_axi_arready,

    // Read Data Channel
    input      [31:0] m_axi_rdata,
    input      [1:0]  m_axi_rresp,
    input             m_axi_rvalid,
    output reg        m_axi_rready
);

    // =========================================================================
    // LOCAL PARAMETERS (Memory Map Boundaries)
    // =========================================================================
    localparam SRAM_BASE  = 32'h8000_0000;
    localparam SRAM_LIMIT = 32'h8040_0000; 
    
    localparam MMIO_BASE  = 32'h4000_0000; 
    localparam MMIO_LIMIT = 32'h4000_FFFF;

    // Helper signal for Reads
    wire mem_re = ~mem_we;

    // =========================================================================
    // INTERNAL ROUTING WIRES AND REGISTERS
    // =========================================================================
    // Address Decoding Status Flags
    wire addr_in_sram_range = (mem_addr >= SRAM_BASE) && (mem_addr <= SRAM_LIMIT);
    wire addr_in_mmio_range = (mem_addr >= MMIO_BASE) && (mem_addr <= MMIO_LIMIT);
    wire addr_fault         = mem_req && !(addr_in_sram_range || addr_in_mmio_range);

    // Route Decoupled Internal Requests
    wire sram_req_active = mem_req & addr_in_sram_range;
    wire axi_req_active  = mem_req & addr_in_mmio_range;

    // Decoupled Stall and Error signals to prevent multiple drivers
    wire sram_stall_needed;
    reg  axi_w_stall, axi_r_stall;
    reg  axi_w_err, axi_r_err;
    reg [31:0] axi_rdata_reg;

    // =========================================================================
    // 1. SRAM ROUTING & 2-CYCLE LATENCY CONTROLLER - 2 always blocks
    // =========================================================================

    always @(*) begin
        sram_en    = sram_req_active;
        sram_we    = mem_we;
        sram_wmask = mem_be;
        sram_addr  = mem_addr[31:2]; 
        sram_wdata = mem_wdata;
    end

    // 2-State FSM to handle fixed 2-cycle read latency for SRAM
    reg sram_rd_state, next_sram_rd_state;
    localparam SRAM_IDLE = 1'b0;
    localparam SRAM_WAIT = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sram_rd_state <= SRAM_IDLE;
        else        sram_rd_state <= next_sram_rd_state;
    end

    always @(*) begin
        case (sram_rd_state)
            SRAM_IDLE: begin
                // Trigger only on a new SRAM read request
                if (sram_req_active && !mem_we) 
                    next_sram_rd_state = SRAM_WAIT;
                else
                    next_sram_rd_state = SRAM_IDLE;
            end
            SRAM_WAIT: begin
                // Data will be valid at the end of this cycle; return to IDLE
                next_sram_rd_state = SRAM_IDLE;
            end
        endcase
    end

    // Stall LSU while waiting for SRAM read to complete (no stalls for SRAM write)
    assign sram_stall_needed = (sram_rd_state == SRAM_IDLE && sram_req_active && !mem_we);

    // =========================================================================
    // 2. AXI LITE - WRITE FSM
    // =========================================================================
    reg [1:0] axi_write_state, next_axi_write_state;
    localparam AXI_WRITE_IDLE = 2'b00;
    localparam AXI_WAIT_ADDR  = 2'b01;
    localparam AXI_WAIT_DATA  = 2'b10;
    localparam AXI_WAIT_RESP  = 2'b11;

    always @(*) begin
        case (axi_write_state)
            AXI_WRITE_IDLE: begin
                if (axi_req_active && mem_we) begin
                    case ({m_axi_awready, m_axi_wready})
                        2'b11: next_axi_write_state = AXI_WAIT_RESP; 
                        2'b10: next_axi_write_state = AXI_WAIT_DATA; 
                        2'b01: next_axi_write_state = AXI_WAIT_ADDR; 
                        default: next_axi_write_state = AXI_WRITE_IDLE;
                    endcase
                end else begin
                    next_axi_write_state = AXI_WRITE_IDLE;
                end
            end
            AXI_WAIT_ADDR: begin
                if (m_axi_wready) next_axi_write_state = AXI_WAIT_DATA;
                else              next_axi_write_state = AXI_WAIT_ADDR;
            end
            AXI_WAIT_DATA: begin
                if (m_axi_awready) next_axi_write_state = AXI_WAIT_RESP;
                else               next_axi_write_state = AXI_WAIT_DATA;
            end
            AXI_WAIT_RESP: begin
                if (m_axi_bvalid) next_axi_write_state = AXI_WRITE_IDLE;
                else              next_axi_write_state = AXI_WAIT_RESP;
            end
            default: next_axi_write_state = AXI_WRITE_IDLE;
        endcase
    end

    always @(*) begin
        m_axi_awvalid = (axi_write_state == AXI_WRITE_IDLE && axi_req_active && mem_we) || (axi_write_state == AXI_WAIT_ADDR);
        m_axi_wvalid  = (axi_write_state == AXI_WRITE_IDLE && axi_req_active && mem_we) || (axi_write_state == AXI_WAIT_DATA);
        m_axi_bready  = (axi_write_state == AXI_WAIT_RESP);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_write_state <= AXI_WRITE_IDLE;
            axi_w_stall     <= 0;
            axi_w_err       <= 0;
            m_axi_awaddr    <= 0;
            m_axi_wdata     <= 0;
            m_axi_wstrb     <= 0;
        end else begin
            axi_write_state <= next_axi_write_state;

            case (axi_write_state)
                AXI_WRITE_IDLE: begin
                    axi_w_err    <= 0;
                    if (axi_req_active && mem_we) begin
                        m_axi_wstrb  <= mem_be;
                        m_axi_awaddr <= mem_addr;
                        m_axi_wdata  <= mem_wdata;
                        axi_w_stall  <= 1;
                    end else begin
                        axi_w_stall  <= 0;
                        m_axi_wstrb  <= 0;
                        m_axi_awaddr <= 0;
                        m_axi_wdata  <= 0;
                    end
                end
                AXI_WAIT_ADDR, AXI_WAIT_DATA: begin
                    axi_w_stall <= 1;
                    axi_w_err   <= 0;
                end
                AXI_WAIT_RESP: begin
                    if (m_axi_bvalid) begin
                        axi_w_stall <= 0;
                        axi_w_err   <= (m_axi_bresp != 2'b00);
                        m_axi_awaddr<= 0;
                        m_axi_wdata <= 0;
                        m_axi_wstrb <= 0;
                    end else begin
                        axi_w_stall <= 1;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // 3. AXI LITE - READ FSM
    // =========================================================================
    reg [1:0] axi_read_state, next_axi_read_state;
    localparam AXI_READ_IDLE = 2'b00;
    localparam AXI_WAIT_READ = 2'b01;

    always @(*) begin
        case (axi_read_state)
            AXI_READ_IDLE: begin
                if (axi_req_active && mem_re && m_axi_arready) 
                    next_axi_read_state = AXI_WAIT_READ;
                else
                    next_axi_read_state = AXI_READ_IDLE;
            end
            AXI_WAIT_READ: begin
                if (m_axi_rvalid) next_axi_read_state = AXI_READ_IDLE;
                else              next_axi_read_state = AXI_WAIT_READ;
            end
            default: next_axi_read_state = AXI_READ_IDLE;
        endcase
    end

    always @(*) begin
        m_axi_arvalid = (axi_read_state == AXI_READ_IDLE) && axi_req_active && mem_re;
        m_axi_rready  = (axi_read_state == AXI_WAIT_READ);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_read_state <= AXI_READ_IDLE;
            axi_r_stall    <= 0;
            axi_r_err      <= 0;
            axi_rdata_reg  <= 0;
            m_axi_araddr   <= 0;
        end else begin
            axi_read_state <= next_axi_read_state;

            case (axi_read_state)
                AXI_READ_IDLE: begin
                    axi_r_err <= 0;
                    if (axi_req_active && mem_re) begin
                        axi_r_stall  <= 1;
                        m_axi_araddr <= mem_addr;
                    end else begin
                        axi_r_stall  <= 0;
                    end
                end
                AXI_WAIT_READ: begin
                    if (m_axi_rvalid) begin
                        axi_r_stall   <= 0;
                        axi_rdata_reg <= m_axi_rdata;           
                        axi_r_err     <= (m_axi_rresp != 2'b00); 
                    end else begin
                        axi_r_stall   <= 1;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // 4. AGGREGATION & MULTIPLEXING LAYER (Back to LSU)
    // =========================================================================
    always @(*) begin
        // Aggregated Stall: Core must stall if ANY interface needs it
        mem_stall = sram_stall_needed | axi_w_stall | axi_r_stall;

        // Aggregated Error: Out of bounds OR bus errors
        mem_err = addr_fault | axi_w_err | axi_r_err;

        // Route Read Data based on who just completed a transaction
        if (sram_rd_state == SRAM_WAIT) begin
            // If we are in WAIT, the SRAM read data will be valid at the upcoming clock edge
            mem_rdata = sram_rdata;       
        end else begin
            // Defaults to holding the last AXI read
            mem_rdata = axi_rdata_reg;    
        end
    end

endmodule