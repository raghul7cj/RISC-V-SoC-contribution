`ifndef LSU_REF_MODEL_SV
`define LSU_REF_MODEL_SV

// lsu_ref_model.sv
// =========================================================================
// Reference Model for LSU Subsystem
//
// Implements functional behavior, shadow memory state tracking, and
// output prediction for verification comparison in the scoreboard.
// =========================================================================

import lsu_pkg::*;

class lsu_ref_model;

    // Shadow memory for SRAM address range (associative array, byte-addressed)
    logic [7:0] shadow_mem [logic [31:0]];

    // AXI dummy slave mock registers (must mirror axi_lite_dummy_slave init)
    logic [31:0] axi_mock_reg [0:3];

    function new();
        // Mirror dummy slave initial state: all zeros (dmem.hex not loaded)
        axi_mock_reg[0] = 32'h0;
        axi_mock_reg[1] = 32'h0;
        axi_mock_reg[2] = 32'h0;
        axi_mock_reg[3] = 32'h0;
    endfunction

    // =====================================================================
    // Routing helpers
    // =====================================================================
    function automatic logic in_sram(logic [31:0] addr);
        return (addr >= SRAM_BASE && addr <= SRAM_LIMIT);
    endfunction

    function automatic logic in_mmio(logic [31:0] addr);
        return (addr >= MMIO_BASE && addr <= MMIO_LIMIT);
    endfunction

    // =====================================================================
    // Predict whether an access should raise core_err
    // =====================================================================
    function automatic logic predict_err(logic [31:0] addr);
        if (!(in_sram(addr) || in_mmio(addr))) begin
            predict_err = 1'b1;
        end
        else begin
            predict_err = 1'b0;
        end
    endfunction

    // =====================================================================
    // Perform a reference write to shadow memory
    // =====================================================================

    function automatic void do_write(logic [31:0] addr, logic [31:0] wdata, logic [4:0] lsunit);
        case (lsunit)
            LSU_SB: byte_write(addr, wdata[7:0]);
            LSU_SH: begin
                byte_write(addr, wdata[7:0]);
                byte_write(addr + 1, wdata[15:8]);
            end
            LSU_SW: begin
                byte_write(addr, wdata[7:0]);
                byte_write(addr + 1, wdata[15:8]);
                byte_write(addr + 2, wdata[23:16]);
                byte_write(addr + 3, wdata[31:24]);
            end
            default: ;
        endcase
    endfunction

    function automatic void byte_write(logic [31:0] addr, logic [7:0] wdata);
        if (in_sram(addr)) begin
            shadow_mem[addr] = wdata[7:0];
        end else if (in_mmio(addr)) begin
            axi_mock_reg[addr[3:2]][(addr[1:0]*8) +: 8] = wdata[7:0];
        end
        
    endfunction

    // =====================================================================
    // Predict load read data after ls_unit formatting
    // =====================================================================
    function automatic logic [7:0] read_byte(logic [31:0] addr);
        if (in_sram(addr)) begin
            return shadow_mem.exists(addr) ? shadow_mem[addr] : 8'h00;
        end else if (in_mmio(addr)) begin
            return axi_mock_reg[addr[3:2]][(addr[1:0]*8) +: 8];
        end else begin
            return 8'h0;
        end
    endfunction

    function automatic logic [31:0] predict_read(logic [31:0] addr, logic [4:0] lsunit);
        case (lsunit)
            LSU_LB: return 32'($signed(read_byte(addr)));

            LSU_LH: return 32'($signed({read_byte(addr + 1), 
                                        read_byte(addr)}));

            LSU_LW: return 32'($signed({read_byte(addr + 3), 
                                        read_byte(addr + 2), 
                                        read_byte(addr + 1), 
                                        read_byte(addr)}));

            LSU_LBU: return 32'($unsigned(read_byte(addr)));

            LSU_LHU: return 32'($unsigned({read_byte(addr + 1), 
                                            read_byte(addr)}));
            default: return 32'h0;
        endcase
    endfunction


endclass

`endif
