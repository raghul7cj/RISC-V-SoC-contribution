`ifndef LSU_TRANSACTION_SV
`define LSU_TRANSACTION_SV

// lsu_transaction.sv
// Transaction Class for LSU Subsystem

import lsu_pkg::*;

class lsu_transaction;

    // ── Stimulus (driven by driver) ──────────────────────────────────────
    rand logic [31:0] addr;
    rand logic [31:0] wdata;
    rand logic [4:0]  lsunit;   // [4]=en, [3]=is_store, [2:0]=funct3
    rand region_t     region;

    // ── Response (captured by monitor) ───────────────────────────────────
    logic [31:0]     rdata;
    int unsigned     stall_cycles; // How many cycles core_stall was held high
    logic            err;

    // Constraints
    constraint c_lsunit_valid {
        lsunit inside {LSU_LB, LSU_LH, LSU_LW, LSU_LBU, LSU_LHU, LSU_SB, LSU_SH, LSU_SW};
    }

    // ── SRAM-only: ON by default (disable with txn.c_sram_only.constraint_mode(0)) ─
    constraint c_sram_only {
        region == SRAM_REGION;
        addr inside {[SRAM_BASE : SRAM_LIMIT]};
    }

    // ── MMIO/OOR address ranges: OFF by default (enable when switching off c_sram_only) ─
    constraint c_addr_ranges {
        if (region == MMIO_REGION) addr inside {MMIO_BASE, MMIO_BASE + 4, MMIO_BASE + 8, MMIO_BASE + 12};
        if (region == OOR_REGION)  !(addr inside {[SRAM_BASE : SRAM_LIMIT]} || addr inside {[MMIO_BASE : MMIO_LIMIT]});
    }

    constraint c_alignment {
        // Word accesses (LW, SW) must be 4-byte aligned
        (lsunit[2:0] == 3'b010) -> (addr[1:0] == 2'b00);
        
        // Halfword accesses (LH, LHU, SH) must be 2-byte aligned
        (lsunit[2:0] == 3'b001 || lsunit[2:0] == 3'b101) -> (addr[0] == 1'b0);
        
        // Byte accesses (LB, LBU, SB) have no constraints (can be any offset)
    }

    function new();
        c_addr_ranges.constraint_mode(0); // OFF by default — SRAM-only mode
    endfunction

    // Copy
    function lsu_transaction copy();
        lsu_transaction cpy = new();
        cpy.addr        = this.addr;
        cpy.wdata       = this.wdata;
        cpy.lsunit      = this.lsunit;
        cpy.region      = this.region;
        cpy.rdata       = this.rdata;
        cpy.stall_cycles = this.stall_cycles;
        cpy.err         = this.err;
        return cpy;
    endfunction

    // Display helper
    function void display(string tag = "LSU_TXN");
        $display("[%s] addr=0x%h wdata=0x%h lsunit=5'b%b region=%s | rdata=0x%h stall_cycles=%0d err=%b",
                 tag, addr, wdata, lsunit, region.name(), rdata, stall_cycles, err);
    endfunction

endclass

`endif
