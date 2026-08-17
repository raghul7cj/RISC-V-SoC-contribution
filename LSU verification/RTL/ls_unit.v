`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : ls_unit
// Description : Load/Store Unit for RV32I. 
//               Variables refactored for clarity and standard RTL naming conventions.
//////////////////////////////////////////////////////////////////////////////////

module ls_unit(
    // ==========================================
    // 1. CORE PIPELINE INTERFACE (To/From EX & WB)
    // ==========================================
    input  [31:0] core_addr,  // Full 32-bit effective address from ALU
    input  [31:0] core_wdata, // Raw store data from RS2
    input  [4:0]  lsunit,     // Control bus: [4]=en, [3]=is_store, [2:0]=funct3
    
    output [31:0] core_rdata, // Formatted load result (routes to WB stage)
    output        core_stall, // Freeze signal (routes to IF, ID, EX registers)
    output        core_err,   // Access fault signal (routes to Zicsr trap logic)

    // ==========================================
    // 2. MEMORY BRIDGE INTERFACE (To native SRAM/AXI router)
    // ==========================================
    output        mem_req,    // Valid request this cycle
    output        mem_we,     // Write enable
    output [31:0] mem_addr,   // Byte address
    output [31:0] mem_wdata,  // Aligned write data
    output [3:0]  mem_be,     // Byte enables
    
    input  [31:0] mem_rdata,  // Read data returning from bridge
    input         mem_stall,  // Freeze pipeline request from bridge
    input         mem_err     // Access fault from bridge
);

    // Control signal unpacking
    wire        is_ls_valid = lsunit[4];
    wire        is_store_op = lsunit[4] & lsunit[3];
    wire        is_load_op  = lsunit[4] & !lsunit[3];
    wire [2:0]  ls_funct3   = lsunit[2:0];

    // ---------------------------------------------------------
    // LAYER 1: NEW INTERFACE ROUTING
    // ---------------------------------------------------------
    
    // Drive the standard memory request bus
    assign mem_req  = is_ls_valid;               // Request is valid if ls_en is high
    assign mem_we   = is_store_op;              // Write enable if valid AND is_store
    assign mem_addr = core_addr;               // Pass the full 32-bit address out

    // Pass stalls and errors back to the core safely
    assign core_stall = mem_req & mem_stall; 
    assign core_err   = mem_err;

    // ---------------------------------------------------------
    // DESCRIPTIVE INTERNAL SIGNALS
    // ---------------------------------------------------------
    wire [1:0]  byte_offset    = core_addr[1:0]; // Extract lowest 2 bits for alignment
    wire [31:0] raw_mem_rdata  = mem_rdata;      // Unformatted data arriving from memory
    wire [31:0] raw_core_wdata = core_wdata;     // Unformatted store data from core

    // Internal registers for behavioral blocks
    reg  [31:0] formatted_core_rdata;
    reg  [31:0] aligned_mem_wdata;
    reg  [3:0]  byte_en_mask;

    // Route formatted outputs to the respective external ports
    assign mem_wdata  = aligned_mem_wdata;       
    assign mem_be     = byte_en_mask;            
    assign core_rdata = formatted_core_rdata;    


    // ==================================================
    // LOAD DATA FORMATTING (Behavioral Mux)
    // ==================================================
    always @(*) begin
        if (is_load_op) begin
            case (ls_funct3)
                3'b000: begin // LB (Load Byte, Sign-Extended)
                    case (byte_offset)
                        2'b00:   formatted_core_rdata = {{24{raw_mem_rdata[7]}},  raw_mem_rdata[7:0]};
                        2'b01:   formatted_core_rdata = {{24{raw_mem_rdata[15]}}, raw_mem_rdata[15:8]};
                        2'b10:   formatted_core_rdata = {{24{raw_mem_rdata[23]}}, raw_mem_rdata[23:16]};
                        default: formatted_core_rdata = {{24{raw_mem_rdata[31]}}, raw_mem_rdata[31:24]};
                    endcase
                end
                
                3'b001: begin // LH (Load Halfword, Sign-Extended)
                    if (byte_offset[1] == 1'b0)
                        formatted_core_rdata = {{16{raw_mem_rdata[15]}}, raw_mem_rdata[15:0]};
                    else
                        formatted_core_rdata = {{16{raw_mem_rdata[31]}}, raw_mem_rdata[31:16]};
                end
                
                3'b010: begin // LW (Load Word)
                    formatted_core_rdata = raw_mem_rdata; 
                end
                
                3'b100: begin // LBU (Load Byte, Zero-Extended)
                    case (byte_offset)
                        2'b00:   formatted_core_rdata = {24'b0, raw_mem_rdata[7:0]};
                        2'b01:   formatted_core_rdata = {24'b0, raw_mem_rdata[15:8]};
                        2'b10:   formatted_core_rdata = {24'b0, raw_mem_rdata[23:16]};
                        default: formatted_core_rdata = {24'b0, raw_mem_rdata[31:24]};
                    endcase
                end
                
                3'b101: begin // LHU (Load Halfword, Zero-Extended)
                    if (byte_offset[1] == 1'b0)
                        formatted_core_rdata = {16'b0, raw_mem_rdata[15:0]};
                    else
                        formatted_core_rdata = {16'b0, raw_mem_rdata[31:16]};
                end
                
                default: formatted_core_rdata = 32'd0; // Safe fallback for undefined loads
            endcase
        end else begin
            formatted_core_rdata = 32'd0;
        end
    end

    // ==================================================
    // STORE DATA ALIGNMENT & STROBE GENERATION
    // ==================================================
    always @(*) begin
        if (is_store_op) begin
            case (ls_funct3)
                3'b000: begin // SB (Store Byte)
                    case (byte_offset)
                        2'b00:   begin byte_en_mask = 4'b0001; aligned_mem_wdata = raw_core_wdata;        end
                        2'b01:   begin byte_en_mask = 4'b0010; aligned_mem_wdata = raw_core_wdata << 8;   end
                        2'b10:   begin byte_en_mask = 4'b0100; aligned_mem_wdata = raw_core_wdata << 16;  end
                        default: begin byte_en_mask = 4'b1000; aligned_mem_wdata = raw_core_wdata << 24;  end
                    endcase
                end
                
                3'b001: begin // SH (Store Halfword)
                    if (byte_offset[1] == 1'b0) begin
                        byte_en_mask      = 4'b0011;
                        aligned_mem_wdata = raw_core_wdata;
                    end else begin
                        byte_en_mask      = 4'b1100;
                        aligned_mem_wdata = raw_core_wdata << 16;
                    end
                end
                
                3'b010: begin // SW (Store Word)
                    byte_en_mask      = 4'b1111;
                    aligned_mem_wdata = raw_core_wdata;
                end
                
                default: begin // Safe fallback if control bus is garbage/corrupted
                    byte_en_mask      = 4'b0000; 
                    aligned_mem_wdata = 32'd0;
                end
            endcase
        end else begin
            byte_en_mask      = 4'b0000;          // Force zero write enables when not executing a store
            aligned_mem_wdata = raw_core_wdata;   // Default pass-through
        end
    end

endmodule