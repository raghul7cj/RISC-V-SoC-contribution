`timescale 1ns / 1ps
// lsu_pkg.sv
// Package defining shared constants and types for the LSU verification environment.

package lsu_pkg;

    // Memory map constants (Single Source of Truth)
    parameter logic [31:0] SRAM_BASE  = 32'h8000_1000;
    parameter logic [31:0] SRAM_LIMIT = 32'h8010_0FFF;
    parameter logic [31:0] MMIO_BASE  = 32'h4000_0000;
    parameter logic [31:0] MMIO_LIMIT = 32'h4000_FFFF;
    parameter logic [31:0] OOR_ADDR   = 32'h0000_1000;

    // Address regions enum for transaction generation
    typedef enum {
        SRAM_REGION,
        MMIO_REGION,
        OOR_REGION
    } region_t;

    // lsunit control command encodings: [4]=en, [3]=is_store, [2:0]=funct3
    parameter logic [4:0] LSU_LB  = 5'b10000;
    parameter logic [4:0] LSU_LH  = 5'b10001;
    parameter logic [4:0] LSU_LW  = 5'b10010;
    parameter logic [4:0] LSU_LBU = 5'b10100;
    parameter logic [4:0] LSU_LHU = 5'b10101;
    parameter logic [4:0] LSU_SB  = 5'b11000;
    parameter logic [4:0] LSU_SH  = 5'b11001;
    parameter logic [4:0] LSU_SW  = 5'b11010;
    parameter logic [4:0] LSU_NOP = 5'b00000;

    // ── Helper: lsunit 5-bit control to human-readable string ──────────────
    function automatic string lsunit_to_string(logic [4:0] lsunit);
        case (lsunit)
            LSU_LB:  return "LB";
            LSU_LH:  return "LH";
            LSU_LW:  return "LW";
            LSU_LBU: return "LBU";
            LSU_LHU: return "LHU";
            LSU_SB:  return "SB";
            LSU_SH:  return "SH";
            LSU_SW:  return "SW";
            default: return "NOP";
        endcase
    endfunction

endpackage: lsu_pkg
