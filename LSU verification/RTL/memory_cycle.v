`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : memory_cycle
//
// Description:
//  Implements the Memory (MEM) stage and the MEM → WB pipeline register.
//
//  Responsibilities:
//      - Interface with data memory via hybrid_mem_interface bus router
//      - Perform load data formatting (via ls_unit)
//      - Perform store data alignment and strobe generation (via ls_unit)
//      - Register MEM outputs into WB stage
//
//  Sub-module hierarchy:
//      memory_cycle
//          ├── ls_unit            (load/store formatting + mem-request bus)
//          ├── hybrid_mem_interface (address decode → SRAM / AXI4-Lite router)
//          └── Data_Memory        (native synchronous SRAM, 1-cycle read latency)
//
//  Pipeline Flow:
//      EX stage → memory_cycle → WB stage
//
//  Control Flow:
//      - RegWriteM propagated to WB
//      - ResultSrc determines WB mux selection
//
//  Reset convention:
//      - memory_cycle pipeline registers : active-low  (negedge rst)
//      - Data_Memory / hybrid_mem_interface: active-low rst_n
//      All driven from the same `rst` input which is treated as active-low
//      throughout this design (rst = 0 → reset).
//
//////////////////////////////////////////////////////////////////////////////////

module memory_cycle(
    clk, rst,
    FlushW,
    RegWriteM, MemWriteM,
    ResultSrcM,
    RD_M, lsunitM,
    PC_M,
    PCPlus4M,
    valid_M,
    exc_valid_M,
    exc_cause_M,
    exc_tval_M,
    exc_pc_M,
    is_mret_M,
    WriteDataM,
    ALU_ResultM,
    csr_write_en_M,
    csr_addr_M,
    new_csr_M,
    old_csr_M,
    // Stall output to pipeline controller
    mem_stall_out,
    // AXI4-Lite master bus (routed straight to top level)
    m_axi_awaddr,
    m_axi_awvalid,
    m_axi_awready,
    m_axi_wdata,
    m_axi_wstrb,
    m_axi_wvalid,
    m_axi_wready,
    m_axi_bresp,
    m_axi_bvalid,
    m_axi_bready,
    m_axi_araddr,
    m_axi_arvalid,
    m_axi_arready,
    m_axi_rdata,
    m_axi_rresp,
    m_axi_rvalid,
    m_axi_rready,
    // WB outputs
    RegWriteW,
    ResultSrcW,
    RD_W,
    PC_W,
    PCPlus4W,
    ALU_ResultW,
    ReadDataW,
    valid_W,
    exc_valid_W,
    exc_cause_W,
    exc_tval_W,
    exc_pc_W,
    is_mret_W,
    csr_write_en_W,
    csr_addr_W,
    new_csr_W,
    old_csr_W
);

    // ==================================================
    // Inputs from Execute stage
    // ==================================================

    input clk;
    input rst;           // Active-low reset (rst = 0 → reset asserted)
    input FlushW;

    input RegWriteM;          // Register write enable
    input MemWriteM;          // Memory write enable

    input [1:0] ResultSrcM;   // Writeback source select
    input [4:0] RD_M;         // Destination register
    input [4:0] lsunitM;      // Load/store control bus: [4]=en,[3]=is_store,[2:0]=funct3

    input [31:0] PC_M;        // PC propagated from EX/MEM
    input [31:0] PCPlus4M;    // PC + 4
    input valid_M;
    input exc_valid_M;
    input [4:0] exc_cause_M;
    input [31:0] exc_tval_M;
    input [31:0] exc_pc_M;
    input is_mret_M;
    input [31:0] WriteDataM;  // Store data (raw RS2 value, alignment done in ls_unit)
    input [31:0] ALU_ResultM; // Effective address / ALU result

    // CSR write request (from EX/MEM pipeline register)
    input        csr_write_en_M;
    input [11:0] csr_addr_M;
    input [31:0] new_csr_M;
    input [31:0] old_csr_M;

    // ==================================================
    // Stall output
    // ==================================================
    output mem_stall_out;     // Routed to hazard/pipeline controller

    // ==================================================
    // AXI4-Lite master ports (pass-through to top level)
    // ==================================================
    output [31:0] m_axi_awaddr;
    output        m_axi_awvalid;
    input         m_axi_awready;
    output [31:0] m_axi_wdata;
    output [3:0]  m_axi_wstrb;
    output        m_axi_wvalid;
    input         m_axi_wready;
    input  [1:0]  m_axi_bresp;
    input         m_axi_bvalid;
    output        m_axi_bready;
    output [31:0] m_axi_araddr;
    output        m_axi_arvalid;
    input         m_axi_arready;
    input  [31:0] m_axi_rdata;
    input  [1:0]  m_axi_rresp;
    input         m_axi_rvalid;
    output        m_axi_rready;

    // ==================================================
    // Outputs to Writeback stage
    // ==================================================

    output RegWriteW;
    output [1:0] ResultSrcW;
    output [4:0] RD_W;
    output [31:0] PC_W;
    output [31:0] PCPlus4W;
    output [31:0] ALU_ResultW;
    output [31:0] ReadDataW;
    output valid_W;
    output exc_valid_W;
    output [4:0] exc_cause_W;
    output [31:0] exc_tval_W;
    output [31:0] exc_pc_W;
    output is_mret_W;

    // CSR write request (to WB stage / retirement)
    output        csr_write_en_W;
    output [11:0] csr_addr_W;
    output [31:0] new_csr_W;
    output [31:0] old_csr_W;

    // ==================================================
    // MEM-Stage Exception Detection (Misalignment)
    // ==================================================

    wire is_load  = (lsunitM[4:3] == 2'b10);
    wire is_store = (lsunitM[4:3] == 2'b11);

    // Basic misalignment check:
    // LW/SW must be 4-byte aligned (addr[1:0] == 00)
    // LH/SH must be 2-byte aligned (addr[0] == 0)
    wire misaligned_load  = is_load  && (
        (lsunitM[2:0] == 3'b010 && ALU_ResultM[1:0] != 2'b00) || // LW (010)
        (lsunitM[2:0] == 3'b001 && ALU_ResultM[0]   != 1'b0)  || // LH (001)
        (lsunitM[2:0] == 3'b101 && ALU_ResultM[0]   != 1'b0)     // LHU (101)
    );

    wire misaligned_store = is_store && (
        (lsunitM[2:0] == 3'b010 && ALU_ResultM[1:0] != 2'b00) || // SW (010)
        (lsunitM[2:0] == 3'b001 && ALU_ResultM[0]   != 1'b0)     // SH (001)
    );

    wire exc_valid_mem_local = (misaligned_load | misaligned_store) & valid_M;

    wire [4:0] exc_cause_mem_local =
        misaligned_load  ? 5'd4 :
        misaligned_store ? 5'd6 :
                           5'd0; // 4: Load misalign, 6: Store misalign

    wire [31:0] exc_tval_mem_local = ALU_ResultM; // Faulting address

    // Merge with propagated exception (first wins)
    wire exc_valid_mem_final = exc_valid_M | exc_valid_mem_local;
    wire [4:0] exc_cause_mem_final = exc_valid_M ? exc_cause_M : exc_cause_mem_local;
    wire [31:0] exc_tval_mem_final = exc_valid_M ? exc_tval_M  : exc_tval_mem_local;

    // ==================================================
    // ls_unit ↔ hybrid_mem_interface wires
    // ==================================================

    // ls_unit → hybrid_mem_interface
    wire        lsu_mem_req;
    wire        lsu_mem_we;
    wire [31:0] lsu_mem_addr;
    wire [31:0] lsu_mem_wdata;
    wire [3:0]  lsu_mem_be;

    // hybrid_mem_interface → ls_unit
    wire [31:0] lsu_mem_rdata;
    wire        lsu_mem_stall;
    wire        lsu_mem_err;

    // hybrid_mem_interface → Data_Memory (SRAM port)
    wire        sram_en;
    wire        sram_we;
    wire [3:0]  sram_wmask;
    wire [29:0] sram_addr;
    wire [31:0] sram_wdata;
    wire [31:0] sram_rdata;

    // ls_unit formatted load result
    wire [31:0] lsu_core_rdata;
    wire        lsu_core_stall;   // same as mem_stall_out ultimately
    wire        lsu_core_err;     // access fault from bridge

    // ==================================================
    // 1. ls_unit instantiation
    //    Handles:
    //      - Request generation (mem_req, mem_we)
    //      - Load data formatting per funct3 / byte offset
    //      - Store data alignment + byte-enable generation
    // ==================================================

    ls_unit lsunit (
        // Core pipeline interface
        .core_addr  (ALU_ResultM),   // Full 32-bit effective address
        .core_wdata (WriteDataM),    // Raw RS2 store data (ls_unit aligns internally)
        .lsunit     (lsunitM),       // Control bus [4]=en,[3]=is_store,[2:0]=funct3
        .core_rdata (lsu_core_rdata),// Formatted load result → WB
        .core_stall (lsu_core_stall),// Pipeline freeze (also routed to mem_stall_out)
        .core_err   (lsu_core_err),  // Access fault

        // Memory bridge interface
        .mem_req    (lsu_mem_req),
        .mem_we     (lsu_mem_we),
        .mem_addr   (lsu_mem_addr),
        .mem_wdata  (lsu_mem_wdata),
        .mem_be     (lsu_mem_be),
        .mem_rdata  (lsu_mem_rdata),
        .mem_stall  (lsu_mem_stall),
        .mem_err    (lsu_mem_err)
    );

    // Gate memory request with valid_M and absence of a prior exception
    // (suppress spurious accesses from flushed/faulted instructions)
    wire gated_mem_req = lsu_mem_req & valid_M & ~exc_valid_mem_final;
    wire gated_mem_we  = lsu_mem_we  & valid_M & ~exc_valid_mem_final;

    // ==================================================
    // 2. hybrid_mem_interface instantiation
    //    Routes requests to native SRAM or AXI4-Lite bus
    // ==================================================

    hybrid_mem_interface hmif (
        .clk            (clk),
        .rst_n          (rst),         // rst is active-low throughout this design

        // From ls_unit
        .mem_req        (gated_mem_req),
        .mem_we         (gated_mem_we),
        .mem_addr       (lsu_mem_addr),
        .mem_wdata      (lsu_mem_wdata),
        .mem_be         (lsu_mem_be),

        // Back to ls_unit
        .mem_rdata      (lsu_mem_rdata),
        .mem_stall      (lsu_mem_stall),
        .mem_err        (lsu_mem_err),

        // Native SRAM port
        .sram_en        (sram_en),
        .sram_we        (sram_we),
        .sram_wmask     (sram_wmask),
        .sram_addr      (sram_addr),
        .sram_wdata     (sram_wdata),
        .sram_rdata     (sram_rdata),

        // AXI4-Lite master
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready)
    );

    // ==================================================
    // 3. Data_Memory instantiation (native SRAM)
    //    Synchronous write, 1-cycle latency read
    // ==================================================

    Data_Memory dmem (
        .clk        (clk),
        .rst_n      (rst),        // rst is active-low

        .sram_en    (sram_en),
        .sram_we    (sram_we),
        .sram_wmask (sram_wmask),
        .sram_addr  (sram_addr),  // 30-bit word address from hybrid_mem_interface
        .sram_wdata (sram_wdata),
        .sram_rdata (sram_rdata)
    );

    // ==================================================
    // Stall / error pass-through to pipeline controller
    // ==================================================
    assign mem_stall_out = lsu_core_stall;

    // ==================================================
    // MEM → WB Pipeline Registers
    // ==================================================

    reg RegWriteM_r;
    reg [1:0] ResultSrcM_r;
    reg [4:0] RD_M_r;
    reg [31:0] PC_M_r;
    reg [31:0] PCPlus4M_r;
    reg [31:0] ALU_ResultM_r;
    reg [31:0] ReadDataM_r;
    reg valid_W_r;
    reg exc_valid_r;
    reg [4:0] exc_cause_r;
    reg [31:0] exc_tval_r;
    reg [31:0] exc_pc_r;
    reg is_mret_r;

    reg        csr_write_en_M_r;
    reg [11:0] csr_addr_M_r;
    reg [31:0] new_csr_M_r;
    reg [31:0] old_csr_M_r;

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            RegWriteM_r      <= 1'b0;
            ResultSrcM_r     <= 2'b00;
            RD_M_r           <= 5'd0;
            PC_M_r           <= 32'd0;
            PCPlus4M_r       <= 32'd0;
            ALU_ResultM_r    <= 32'd0;
            ReadDataM_r      <= 32'd0;
            valid_W_r        <= 1'b0;
            exc_valid_r      <= 1'b0;
            exc_cause_r      <= 5'd0;
            exc_tval_r       <= 32'd0;
            exc_pc_r         <= 32'd0;
            is_mret_r        <= 1'b0;
            csr_write_en_M_r <= 1'b0;
            csr_addr_M_r     <= 12'h000;
            new_csr_M_r      <= 32'h00000000;
            old_csr_M_r      <= 32'h00000000;
        end
        else if (FlushW) begin
            RegWriteM_r      <= 1'b0;
            ResultSrcM_r     <= 2'b00;
            RD_M_r           <= 5'd0;
            PC_M_r           <= 32'd0;
            PCPlus4M_r       <= 32'd0;
            ALU_ResultM_r    <= 32'd0;
            ReadDataM_r      <= 32'd0;
            valid_W_r        <= 1'b0;
            exc_valid_r      <= 1'b0;
            exc_cause_r      <= 5'd0;
            exc_tval_r       <= 32'd0;
            exc_pc_r         <= 32'd0;
            is_mret_r        <= 1'b0;
            csr_write_en_M_r <= 1'b0;
            csr_addr_M_r     <= 12'h000;
            new_csr_M_r      <= 32'h00000000;
            old_csr_M_r      <= 32'h00000000;
        end
        else begin
            RegWriteM_r      <= RegWriteM;
            ResultSrcM_r     <= ResultSrcM;
            RD_M_r           <= RD_M;
            PC_M_r           <= PC_M;
            PCPlus4M_r       <= PCPlus4M;
            ALU_ResultM_r    <= ALU_ResultM;
            // lsu_core_rdata is already formatted by ls_unit (sign/zero extended, byte selected)
            ReadDataM_r      <= lsu_core_rdata;
            valid_W_r        <= valid_M;
            exc_valid_r      <= exc_valid_mem_final;
            exc_cause_r      <= exc_cause_mem_final;
            exc_tval_r       <= exc_tval_mem_final;
            exc_pc_r         <= exc_pc_M;
            is_mret_r        <= is_mret_M;
            csr_write_en_M_r <= csr_write_en_M;
            csr_addr_M_r     <= csr_addr_M;
            new_csr_M_r      <= new_csr_M;
            old_csr_M_r      <= old_csr_M;
        end
    end

    // ==================================================
    // Outputs to Writeback stage
    // ==================================================

    assign RegWriteW      = RegWriteM_r;
    assign ResultSrcW     = ResultSrcM_r;
    assign RD_W           = RD_M_r;
    assign PC_W           = PC_M_r;
    assign PCPlus4W       = PCPlus4M_r;
    assign ALU_ResultW    = ALU_ResultM_r;
    assign ReadDataW      = ReadDataM_r;
    assign valid_W        = valid_W_r;
    assign exc_valid_W    = exc_valid_r;
    assign exc_cause_W    = exc_cause_r;
    assign exc_tval_W     = exc_tval_r;
    assign exc_pc_W       = exc_pc_r;
    assign is_mret_W      = is_mret_r;

    assign csr_write_en_W = csr_write_en_M_r;
    assign csr_addr_W     = csr_addr_M_r;
    assign new_csr_W      = new_csr_M_r;
    assign old_csr_W      = old_csr_M_r;

endmodule
