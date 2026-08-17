// lsu_tb_top.sv
// =========================================================================
// Top-level testbench for LSU Subsystem
// Instantiates DUT modules, interface, and environment.
// =========================================================================

`timescale 1ns / 1ps

`include "lsu_if.sv"
`include "lsu_env.sv"

module lsu_tb_top;

    // Clock and Reset
    logic clk;
    logic rst_n;

    // Clock generation: 10 ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Reset sequence
    initial begin
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        $display("[TB_TOP] Reset deasserted at %t", $time);
    end

    // ==================================================
    // Interface instantiation
    // ==================================================
    lsu_if dut_if(.clk(clk));
    assign dut_if.rst_n = rst_n;

    // ==================================================
    // Internal wires connecting sub-modules
    // ==================================================

    // ls_unit <-> hybrid_mem_interface
    wire        lsu_mem_req;
    wire        lsu_mem_we;
    wire [31:0] lsu_mem_addr;
    wire [31:0] lsu_mem_wdata;
    wire [3:0]  lsu_mem_be;
    wire [31:0] lsu_mem_rdata;
    wire        lsu_mem_stall;
    wire        lsu_mem_err;

    // hybrid_mem_interface <-> Data_Memory (SRAM)
    wire        sram_en;
    wire        sram_we;
    wire [3:0]  sram_wmask;
    wire [29:0] sram_addr;
    wire [31:0] sram_wdata;
    wire [31:0] sram_rdata;

    // hybrid_mem_interface <-> axi_lite_dummy_slave (AXI)
    wire [31:0] m_axi_awaddr;
    wire        m_axi_awvalid;
    wire        m_axi_awready;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wvalid;
    wire        m_axi_wready;
    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    wire        m_axi_bready;
    wire [31:0] m_axi_araddr;
    wire        m_axi_arvalid;
    wire        m_axi_arready;
    wire [31:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rvalid;
    wire        m_axi_rready;

    // ==================================================
    // DUT — ls_unit
    // ==================================================
    ls_unit u_ls_unit (
        .core_addr  (dut_if.core_addr),
        .core_wdata (dut_if.core_wdata),
        .lsunit     (dut_if.lsunit),
        .core_rdata (dut_if.core_rdata),
        .core_stall (dut_if.core_stall),
        .core_err   (dut_if.core_err),
        .mem_req    (lsu_mem_req),
        .mem_we     (lsu_mem_we),
        .mem_addr   (lsu_mem_addr),
        .mem_wdata  (lsu_mem_wdata),
        .mem_be     (lsu_mem_be),
        .mem_rdata  (lsu_mem_rdata),
        .mem_stall  (lsu_mem_stall),
        .mem_err    (lsu_mem_err)
    );

    // ==================================================
    // DUT — hybrid_mem_interface
    // ==================================================
    hybrid_mem_interface u_hmif (
        .clk            (clk),
        .rst_n          (rst_n),
        .mem_req        (lsu_mem_req),
        .mem_we         (lsu_mem_we),
        .mem_addr       (lsu_mem_addr),
        .mem_wdata      (lsu_mem_wdata),
        .mem_be         (lsu_mem_be),
        .mem_rdata      (lsu_mem_rdata),
        .mem_stall      (lsu_mem_stall),
        .mem_err        (lsu_mem_err),
        .sram_en        (sram_en),
        .sram_we        (sram_we),
        .sram_wmask     (sram_wmask),
        .sram_addr      (sram_addr),
        .sram_wdata     (sram_wdata),
        .sram_rdata     (sram_rdata),
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
    // DUT — Data_Memory (SRAM)
    // ==================================================
    Data_Memory u_dmem (
        .clk        (clk),
        .rst_n      (rst_n),
        .sram_en    (sram_en),
        .sram_we    (sram_we),
        .sram_wmask (sram_wmask),
        .sram_addr  (sram_addr),
        .sram_wdata (sram_wdata),
        .sram_rdata (sram_rdata)
    );

    // ==================================================
    // DUT — AXI Dummy Slave (simulation peripheral)
    // ==================================================
    axi_lite_dummy_slave u_axi_slave (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_awaddr  (m_axi_awaddr),
        .s_axi_awvalid (m_axi_awvalid),
        .s_axi_awready (m_axi_awready),
        .s_axi_wdata   (m_axi_wdata),
        .s_axi_wstrb   (m_axi_wstrb),
        .s_axi_wvalid  (m_axi_wvalid),
        .s_axi_wready  (m_axi_wready),
        .s_axi_bresp   (m_axi_bresp),
        .s_axi_bvalid  (m_axi_bvalid),
        .s_axi_bready  (m_axi_bready),
        .s_axi_araddr  (m_axi_araddr),
        .s_axi_arvalid (m_axi_arvalid),
        .s_axi_arready (m_axi_arready),
        .s_axi_rdata   (m_axi_rdata),
        .s_axi_rresp   (m_axi_rresp),
        .s_axi_rvalid  (m_axi_rvalid),
        .s_axi_rready  (m_axi_rready)
    );

    // ==================================================
    // SVA Assertions (bound to DUT signals)
    // ==================================================
    lsu_assertions u_assertions (
        .clk        (clk),
        .rst_n      (rst_n),
        .lsunit     (dut_if.lsunit),
        .core_addr  (dut_if.core_addr),
        .core_rdata (dut_if.core_rdata),
        .core_stall (dut_if.core_stall),
        .core_err   (dut_if.core_err)
    );

    // ==================================================
    // Environment
    // ==================================================
    lsu_env env;

    initial begin
        env = new(dut_if);

        // Wait for reset to deassert
        @(posedge rst_n);
        @(posedge clk);

        // Run the environment
        env.run();

        $display("[TB_TOP] Simulation complete at %t", $time);
        $display("=== DMEM First 4 Words ===");
        $display("Word 0 (0x80001000): 0x%h", u_dmem.mem_array[0]);
        $display("Word 1 (0x80001004): 0x%h", u_dmem.mem_array[1]);
        $display("Word 2 (0x80001008): 0x%h", u_dmem.mem_array[2]);
        $display("Word 3 (0x8000100C): 0x%h", u_dmem.mem_array[3]);
        $display("==========================");

        // Write simulation summary
        write_sim_summary();
        $finish;
    end

    // Watchdog Timeout (100,000 ns / 10,000 clock cycles)
    initial begin
        #100000;
        $display("[TB_TOP] ERROR: Watchdog timeout reached! Simulation hung.");
        $finish;
    end

    // Write simulation summary log
    task write_sim_summary();
        int fd;
        fd = $fopen("logfiles/sim_summary.log", "w");
        if (fd != 0) begin
            $fdisplay(fd, "================================================");
            $fdisplay(fd, "         LSU SIMULATION SUMMARY");
            $fdisplay(fd, "================================================");
            $fdisplay(fd, "  End time  : %0t", $time);
            $fdisplay(fd, "  Test      : lsu_tb_top");
            $fdisplay(fd, "  Top       : lsu_tb_top");
            $fdisplay(fd, "  DMEM[0]   : 0x%08h", u_dmem.mem_array[0]);
            $fdisplay(fd, "  DMEM[1]   : 0x%08h", u_dmem.mem_array[1]);
            $fdisplay(fd, "  DMEM[2]   : 0x%08h", u_dmem.mem_array[2]);
            $fdisplay(fd, "  DMEM[3]   : 0x%08h", u_dmem.mem_array[3]);
            $fdisplay(fd, "================================================");
            $fclose(fd);
        end
    endtask

    // Task to print the first 4 words of the DMEM array
    task print_mem_array(string test_name);
        $display("=== DMEM First 4 Words after %s ===", test_name);
        $display("Word 0 (0x80001000): 0x%h", u_dmem.mem_array[0]);
        $display("Word 1 (0x80001004): 0x%h", u_dmem.mem_array[1]);
        $display("Word 2 (0x80001008): 0x%h", u_dmem.mem_array[2]);
        $display("Word 3 (0x8000100C): 0x%h", u_dmem.mem_array[3]);
        $display("============================================");
    endtask

endmodule
