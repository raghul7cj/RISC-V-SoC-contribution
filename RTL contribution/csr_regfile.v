`timescale 1ns / 1ps

module csr_regfile #(
  parameter integer XLEN = 32
) (
  // ============================================================================
  // Clock & Reset (SoC integration)
  // ============================================================================
  input  wire        clk_i,
  input  wire        rst_n_i,
  output wire        csr_valid_o,

  // ============================================================================
  // PORT A: Combinational Read (for Execute stage CSR reads)
  // ============================================================================
  input  wire [11:0] csr_raddr_i,
  output reg  [31:0] csr_rdata_o,

  // ============================================================================
  // PORT B: Synchronous Write (from Writeback - CSR instruction commits)
  // ============================================================================
  input  wire [11:0] csr_waddr_normal_i,
  input  wire [31:0] csr_wdata_normal_i,
  input  wire        csr_write_en_normal_i,

  // ============================================================================
  // PORT C: Sync Write (from Exception Controller - trap/exception path)
  // Port C has priority over Port B if both assert in same cycle
  // ============================================================================
  input  wire [11:0] csr_waddr_mret_i,
  input  wire [31:0] csr_wdata_mret_i,
  input  wire        csr_write_en_mret_i,

  // ============================================================================
  // Trap Inputs (from pipeline & trap controller for trap handling)
  // ============================================================================
  input  wire        trap_valid_i,           // Trap detected this cycle
  input  wire [30:0] trap_cause_i,           // Trap cause (0-11 for exc, IRQ ID for intr)
  input  wire [31:0] trap_pc_i,              // PC of faulting instruction (for mepc)
  input  wire [31:0] trap_addr_i,            // Fault address (for mtval on misalign/access-fault)
  input  wire        trap_addr_valid_i,      // Indicates if trap_addr_i is valid (e.g., for load/store faults)
  input  wire        trap_is_interrupt_i,    // 1=interrupt, 0=exception

  input  wire        instr_retired_i,        // Instruction retired (for minstret)

  input  wire        timer_intr_i,           // Timer interrupt pending (for mip)
  input  wire        ext_intr_i,             // External interrupt pending (for mip)
  input  wire        msft_intr_i,            // Software interrupt pending (for mip, set by writes to mip MSIP bit)
  // ============================================================================
  // Control Outputs (for PC module - driven by exception controller, not CSR file)
  // NOTE: CSR file is passive storage only. PC control decisions belong in 
  // exception_ctrl.v, which reads mtvec/mepc via sideband and outputs branch signals.
  // These ports are listed for reference but should be driven by exception controller.
  // ============================================================================
  // output wire        csr_branch_o,           // (Unused in CSR file - driven by exception controller)
  // output wire [31:0] csr_target_o,           // (Unused in CSR file - driven by exception controller)

  // ============================================================================
  // Sideband Outputs (for exception controller combinational decisions)
  // ============================================================================
  output wire [31:0] mtvec_out_o,            // Trap vector base address
  output wire [31:0] mie_out_o,              // Interrupt enable mask
  output wire [31:0] mip_out_o,              // Interrupt pending bits
  output wire        mstatus_mie_out_o,      // Global interrupt enable bit (mstatus.MIE)
  output wire [31:0] mepc_out_o,             // Exception PC (for visibility / debug)
  output wire [31:0] mcause_out_o,           // Exception cause (for visibility / debug)
  output wire [31:0] mstatus_out_o           // Full mstatus register (for MRET logic in trap controller)
);

  // ============================================================================
  // CSR Storage Registers (minimal set per RISC-V spec)
  // ============================================================================
  reg [31:0] mstatus_r;    // [3]=MIE, [7]=MPIE, [12:11]=MPP, rest read-as-zero
  reg [31:0] mie_r;        // [3]=MSIE, [7]=MTIE, [11]=MEIE
  reg [31:0] mtvec_r;      // [31:2]=BASE, [1:0]=MODE
  reg [31:0] mepc_r;       // Machine exception PC
  reg [31:0] mcause_r;     // Machine cause [31]=interrupt, [30:0]=code
  reg [31:0] mtval_r;      // Machine trap value (fault address or x0)
  reg [31:0] mscratch_r;   // Machine scratch register

  // Performance Counters (64-bit)
  reg [63:0] mcycle_r;
  reg [63:0] minstret_r;

  // Forward declaration (assigned in PHASE 4)
  wire [31:0] mip_w;


  // ============================================================================
  // CSR Address Decode Constants (12-bit addresses per RISC-V spec)
  // ============================================================================
  localparam [11:0] MSTATUS_ADDR   = 12'h300;
  localparam [11:0] MIE_ADDR       = 12'h304;
  localparam [11:0] MTVEC_ADDR     = 12'h305;
  localparam [11:0] MSCRATCH_ADDR  = 12'h340;
  localparam [11:0] MEPC_ADDR      = 12'h341;
  localparam [11:0] MCAUSE_ADDR    = 12'h342;
  localparam [11:0] MTVAL_ADDR      = 12'h343;
  localparam [11:0] MIP_ADDR        = 12'h344;

  // Performance Counter Addresses
  localparam [11:0] MCYCLE_ADDR     = 12'hB00;
  localparam [11:0] MINSTRET_ADDR   = 12'hB02;
  localparam [11:0] MCYCLEH_ADDR    = 12'hB80;
  localparam [11:0] MINSTRETH_ADDR  = 12'hB82;

  // ============================================================================
  // PHASE 1: RESET - Initialize all CSR registers to zero on rst_n_i
  // ============================================================================
  //Initialize: mstatus_r, mie_r, mtvec_r, mepc_r, mcause_r, mtval_r, mscratch_r, mip_r to 32'h0

  // ============================================================================
  // PHASE 2: PORT A - Combinational Read Multiplexer
  // Decode csr_raddr_i and return corresponding CSR value via csr_rdata_o
  // ============================================================================
  //       Add always_comb block with case on csr_raddr_i:
  //       12'h300 (mstatus)   → return mstatus_r
  //       12'h304 (mie)       → return mie_r
  //       12'h305 (mtvec)     → return mtvec_r
  //       12'h340 (mscratch)  → return mscratch_r
  //       12'h341 (mepc)      → return mepc_r
  //       12'h342 (mcause)    → return mcause_r
  //       12'h343 (mtval)     → return mtval_r
  //       12'h344 (mip)       → return mip_r (combine software bits with interrupt inputs)
  //       default             → return 32'h0

  always @(*) begin : read_mux
    case (csr_raddr_i)
      MSTATUS_ADDR:   csr_rdata_o = mstatus_r;
      MIE_ADDR:       csr_rdata_o = mie_r;
      MTVEC_ADDR:     csr_rdata_o = mtvec_r;
      MSCRATCH_ADDR:  csr_rdata_o = mscratch_r;
      MEPC_ADDR:      csr_rdata_o = mepc_r;
      MCAUSE_ADDR:    csr_rdata_o = mcause_r;
      MTVAL_ADDR:     csr_rdata_o = mtval_r;
      MIP_ADDR:       csr_rdata_o = mip_w;
      MCYCLE_ADDR:    csr_rdata_o = mcycle_r[31:0];
      MCYCLEH_ADDR:   csr_rdata_o = mcycle_r[63:32];
      MINSTRET_ADDR:  csr_rdata_o = minstret_r[31:0];
      MINSTRETH_ADDR: csr_rdata_o = minstret_r[63:32];
      default:        csr_rdata_o = 32'h0;
    endcase
  end

  // ============================================================================
  // PHASE 3: PORT B & C - Synchronous Write with Priority Arbitration
  // Port C (exception writes) has priority over Port B (instruction writes)
  // Exception writes: mepc, mcause, mtval on trap entry
  // Instruction writes: normal CSR instructions from Writeback
  // ============================================================================
  //   Add always_ff block with dual-source arbitration:
  //
  //   Priority Order:
  //   1. If exception_valid_i: atomically write mepc, mcause, mtval
  //      mepc   ← exception_pc_i
  //      mcause ← {1'b0, exception_code_i}  (interrupt bit = 0 for exceptions)
  //      mtval  ← exception_addr_i
  //
  //   2. Else if csr_write_en_mret: Port C write (from exception controller, e.g., MRET, mcause updates)
  //      Decode csr_waddr_mret_i and write csr_wdata_mret_i to target CSR
  //      Handle read-only CSRs (mip timer/ext bits): ignore writes to these fields
  //
  //   3. Else if csr_write_en_normal: Port B write (from Writeback, normal CSR instructions)
  //      Decode csr_waddr_normal_i and write csr_wdata_normal_i to target CSR
  //      Handle read-only CSRs: ignore writes
  //
  //   Write Masking for Each CSR:
  //   - mstatus: only [3]=MIE, [7]=MPIE, [12:11]=MPP writable
  //   - mie:     [3], [7], [11] writable (software, timer, external enables)
  //   - mtvec:   [31:2]=BASE, [1:0]=MODE writable
  //   - mip:     only [3]=MSIE writable (timer [7], external [11] read-only, driven by inputs)
  //   - mpc, mcause, mtval, mscratch: fully writable

  always @(posedge clk_i or negedge rst_n_i) begin : write_ports_bc
    if (!rst_n_i) begin
      mstatus_r   <= 32'h0;
      mie_r       <= 32'h0;
      mtvec_r     <= 32'h0;
      mepc_r      <= 32'h0;
      mcause_r    <= 32'h0;
      mtval_r     <= 32'h0;
      mscratch_r  <= 32'h0;
      mcycle_r    <= 64'h0;
      minstret_r  <= 64'h0;
    end
    else begin
      // ====================================================================
      // COUNTER INCREMENTS (Lowest priority, overwritten by writes)
      // ====================================================================
      mcycle_r <= mcycle_r + 1'b1;
      if (instr_retired_i) minstret_r <= minstret_r + 1'b1;

      // ====================================================================
      // PRIORITY 1: Trap entry (atomic mepc/mcause/mtval + mstatus update)
      // ====================================================================
      if (trap_valid_i) begin
        mepc_r   <= trap_pc_i;
        mcause_r <= {trap_is_interrupt_i, trap_cause_i}; // Set MSB to 1 for interrupts, 0 for exceptions
        mtval_r  <= (trap_addr_valid_i) ? trap_addr_i : 32'h0;

        mstatus_r[3]      <= 1'b0;       // Clear MIE on trap entry
        mstatus_r[7]      <= mstatus_r[3]; // Save previous MIE to MPIE
        mstatus_r[12:11]  <= 2'b11;      // Set MPP to Machine mode (11) on trap entry
      end
      // ====================================================================
      // PRIORITY 2: Port C writes (from MRET or other exception controller logic)
      // MRET updates only mstatus[3], mstatus[7], mstatus[12:11]
      // ====================================================================
      else if (csr_write_en_mret_i) begin
        case (csr_waddr_mret_i)
          MSTATUS_ADDR:  begin
            // WARL mask 0x188A: sie[1], mie[3], mpie[7], mpp[12:11]
            // (uie/upie/spie/spp not writable in this M-mode config per SAIL test results)
            mstatus_r[1]      <= csr_wdata_mret_i[1];       // Write SIE
            mstatus_r[3]      <= csr_wdata_mret_i[3];       // Write MIE
            mstatus_r[7]      <= csr_wdata_mret_i[7];       // Write MPIE
            mstatus_r[12:11]  <= csr_wdata_mret_i[12:11];   // Write MPP
          end
          // MIE_ADDR:      mie_r      <= (csr_wdata_mret_i & 32'h00000888) | (mie_r & ~32'h00000888);         // Mask to writable bits and retain values of non writable bits
          // MTVEC_ADDR:    mtvec_r    <= (csr_wdata_mret_i & 32'hFFFFFFFC) | (mtvec_r & ~32'hFFFFFFFC);       // Mask to writable bits and retain values of non writable bits
          // MSCRATCH_ADDR: mscratch_r <= csr_wdata_mret_i; // Fully writable
          // MEPC_ADDR:     mepc_r     <= csr_wdata_mret_i; // Fully writable
          // MCAUSE_ADDR:   mcause_r   <= csr_wdata_mret_i; // Fully writable
          // MTVAL_ADDR:    mtval_r    <= csr_wdata_mret_i; // Fully writable
          // MCYCLE_ADDR:    mcycle_r[31:0]  <= csr_wdata_mret_i;
          // MCYCLEH_ADDR:   mcycle_r[63:32] <= csr_wdata_mret_i;
          // MINSTRET_ADDR:  minstret_r[31:0] <= csr_wdata_mret_i;
          // MINSTRETH_ADDR: minstret_r[63:32] <= csr_wdata_mret_i;
          default: // Ignore writes to read-only or non-existent CSRs
            ;
        endcase
      end
      else if (csr_write_en_normal_i) begin
        case (csr_waddr_normal_i)
          // WARL mask 0x0000188A: sie[1], mie[3], mpie[7], mpp[12:11]
          // Verified: 0x1F & 0x188A = 0xA (matches SAIL reference)
          MSTATUS_ADDR:  mstatus_r  <= (csr_wdata_normal_i & 32'h0000188A) | (mstatus_r & ~32'h0000188A);  // SAIL-verified WARL mask
          MIE_ADDR:      mie_r      <= (csr_wdata_normal_i & 32'h00000888) | (mie_r & ~32'h00000888);      // Mask to writable bits and retain values of non writable bits
          MTVEC_ADDR:    mtvec_r    <= (csr_wdata_normal_i & 32'hFFFFFFFC) | (mtvec_r & ~32'hFFFFFFFC);    // Mask to writable bits and retain values of non writable bits
          MSCRATCH_ADDR: mscratch_r <= csr_wdata_normal_i; // Fully writable
          MEPC_ADDR:     mepc_r     <= csr_wdata_normal_i; // Fully writable
          MCAUSE_ADDR:   mcause_r   <= csr_wdata_normal_i; // Fully writable
          MTVAL_ADDR:    mtval_r    <= csr_wdata_normal_i; // Fully writable
          MCYCLE_ADDR:    mcycle_r[31:0]  <= csr_wdata_normal_i;
          MCYCLEH_ADDR:   mcycle_r[63:32] <= csr_wdata_normal_i;
          MINSTRET_ADDR:  minstret_r[31:0] <= csr_wdata_normal_i;
          MINSTRETH_ADDR: minstret_r[63:32] <= csr_wdata_normal_i;
          default: // Ignore writes to read-only or non-existent CSRs
            ;
        endcase
      end
    end
  end

  // ============================================================================
  // PHASE 4: Interrupt Pending Update (mip_r)
  // Combine software interrupt bit (mip_r[3]) with hardware inputs (timer, external)
  // ============================================================================
  //   In the write block or combinationally, update mip_r:
  //   mip_r[3]  ← always updated by write logic (software controlled)
  //   mip_r[7]  ← timer_intr_i (read-only, driven by MTI)
  //   mip_r[11] ← ext_intr_i   (read-only, driven by PLIC)
  // Only MSIP is a real register — needs to survive across cycles
  reg msip_r;

  always @(posedge clk_i or negedge rst_n_i) begin : msip_storage
    if (!rst_n_i)
      msip_r <= 1'b0;
    else if (csr_write_en_mret_i && (csr_waddr_mret_i == MIP_ADDR))
      msip_r <= csr_wdata_mret_i[3];
    else if (csr_write_en_normal_i && (csr_waddr_normal_i == MIP_ADDR))
      msip_r <= csr_wdata_normal_i[3];
  end

  // mip_r is just a wire — single driver, no storage, no latch
  assign mip_w = {20'b0, ext_intr_i, 3'b0, timer_intr_i, 3'b0, (msip_r || msft_intr_i), 3'b0};

  // csr_branch is handled in trap handler

  // ============================================================================
  // PHASE 7: Sideband Outputs (combinational reads for exception controller)
  // ============================================================================
  
  // CSR sideband reads for exception controller combinational decisions
  assign mtvec_out_o       = mtvec_r;
  assign mie_out_o         = mie_r;
  assign mip_out_o         = mip_w;
  assign mstatus_mie_out_o = mstatus_r[3];  // Extract MIE bit
  assign mepc_out_o        = mepc_r;
  assign mcause_out_o      = mcause_r;
  assign mstatus_out_o     = mstatus_r;     // Full mstatus for MRET logic in trap controller

  // Combinational validity check of the CSR access address
  assign csr_valid_o = (csr_raddr_i == MSTATUS_ADDR)   ||
                       (csr_raddr_i == MIE_ADDR)       ||
                       (csr_raddr_i == MTVEC_ADDR)     ||
                       (csr_raddr_i == MSCRATCH_ADDR)  ||
                       (csr_raddr_i == MEPC_ADDR)      ||
                       (csr_raddr_i == MCAUSE_ADDR)    ||
                       (csr_raddr_i == MTVAL_ADDR)     ||
                       (csr_raddr_i == MIP_ADDR)       ||
                       (csr_raddr_i == MCYCLE_ADDR)    ||
                       (csr_raddr_i == MINSTRET_ADDR)  ||
                       (csr_raddr_i == MCYCLEH_ADDR)   ||
                       (csr_raddr_i == MINSTRETH_ADDR);

endmodule
