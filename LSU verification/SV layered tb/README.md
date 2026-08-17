# RISCFORGE 1TOPS — Load/Store Unit (LSU) Verification Suite

An enterprise-grade, class-based **SystemVerilog Design Verification (DV)** environment for the **RISC-V (RV32I) Load/Store Unit (LSU) & Hybrid Memory Bus Interface**.

This testbench validates data alignment, byte-lane masking, sign-extension, dual-bus routing (SRAM vs. AXI4-Lite MMIO), out-of-range memory faults, pipeline stall protocol compliance, and SVA assertions.

---

## 🏛️ Verification Architecture

The environment is built using a modern, layered SystemVerilog OOP architecture:

```text
                               +-----------------------+
                               |     lsu_sequencer     |
                               +-----------+-----------+
                                           | (drv_mbx)
                                           v
+------------------+           +-----------+-----------+           +----------------------+
|  lsu_ref_model   |           |      lsu_driver       |           |   lsu_assertions     |
+--------+---------+           +-----------+-----------+           |    (SVA Module)      |
         |                         |       | (vif)                 +----------+-----------+
         | (predict)               v       v                                  ^
         |                    +------------+------------+                     |
         |                    |    Interface (lsu_if)   |---------------------+
         |                    +------------+------------+
         |                         |       ^
         v                         v       |
+--------+---------+          +------------+------------+          +----------------------+
|  lsu_scoreboard  | <------- |      lsu_monitor       | -------> |     lsu_coverage     |
|  (Pass/Fail Logs)| (scb_mbx)+-------------------------+ (cov_mbx)|  (Functional Cover) |
+------------------+                                               +----------------------+
```

---

## 📂 File Directory Structure

| File | Type | Description |
| :--- | :--- | :--- |
| `lsu_pkg.sv` | SV Package | **Single Source of Truth** for memory maps, address regions, and LSU operation encodings. |
| `lsu_transaction.sv` | SV Class | Transaction object representing load/store operations, address constraints, and responses. |
| `lsu_driver.sv` | SV Class | Receives transactions via mailbox and drives cycle-accurate signals to DUT via `lsu_if`. |
| `lsu_monitor.sv` | SV Class | Passively samples `lsu_if` bus activity on clock edges and broadcasts to scoreboard/coverage. |
| `lsu_ref_model.sv` | SV Class | Software shadow model predicting memory state, load data formatting, and exception flags. |
| `lsu_scoreboard.sv` | SV Class | Compares DUT outputs against reference model predictions with region-wise pass/fail metrics. |
| `lsu_sequencer.sv` | SV Class | Generates directed test sequences and constrained-random stimulus across all address regions. |
| `lsu_coverage.sv` | SV Class | Functional covergroups (`cp_op`, `cp_alignment`, `cp_op_x_alignment`, `cp_wdata`, `cp_region`, `cp_addr`). |
| `lsu_assertions.sv` | SVA Module | Concurrent SystemVerilog Assertions checking stall durations, `X/Z` data safety, and protocol rules. |
| `lsu_tb_top.sv` | SV Module | Top-level testbench module instantiating DUT (`ls_unit`, `hybrid_mem_interface`), interface, and assertions. |
| `run_lsu_tb.ps1` | PowerShell | Xilinx Vivado execution script (`xvlog`, `xelab`, `xsim`, `xcrg` coverage report). |
| `run_vcs.sh` / `Makefile` | Shell/Make | Synopsys VCS build script with UVM 1.2 support, code coverage, and URG HTML report generation. |

---

## 🎯 Verification Scope & Memory Map

The testbench validates routing across three distinct memory address regions:

| Region | Address Range | Interface Bus | Expected Behavior |
| :--- | :--- | :--- | :--- |
| **SRAM Region** | `0x8000_1000` – `0x8010_0FFF` (1 MB) | Native SRAM Controller | 2-cycle read latency, 0-cycle write, `core_err = 0`. |
| **MMIO Region** | `0x4000_0000` – `0x4000_FFFF` (64 KB) | AXI4-Lite Bus | AXI handshakes (`AW`/`W`/`B` and `AR`/`R`), `core_err = 0`. |
| **Out-of-Range (OOR)**| Unmapped addresses | Blocked | Access rejected immediately, `core_err = 1`. |

---

## 🔍 Features & Instructions Tested

1. **Load Instructions:**
   - `LB` (Load Byte, Sign-Extended)
   - `LH` (Load Halfword, Sign-Extended)
   - `LW` (Load Word)
   - `LBU` (Load Byte Unsigned, Zero-Extended)
   - `LHU` (Load Halfword Unsigned, Zero-Extended)
2. **Store Instructions:**
   - `SB` (Store Byte) — Verifies 4-bit byte enables (`0001`, `0010`, `0100`, `1000`)
   - `SH` (Store Halfword) — Verifies byte enables (`0011`, `1100`)
   - `SW` (Store Word) — Verifies full enable (`1111`)
3. **Data Pattern Variety:**
   - Walking ones/zeros (`0x00000000`, `0xFFFFFFFF`), alternating patterns (`0xA5A5A5A5`, `0x5A5A5A5A`), `0xDEADBEEF`.

---

## 🛡️ SystemVerilog Assertions (SVA) Summary

Assertions are bound to `lsu_if` and sampled on `@(negedge clk)` to avoid combinational sampling races:

| Property Name | Severity | Description |
| :--- | :--- | :--- |
| `A_LOAD_STALL_DUR_SRAM` | `Fatal/Error` | Asserts that SRAM load stall stays asserted for exactly 1 cycle. |
| `A_LOAD_RDATA_GOOD` | `Error` | Ensures `core_rdata` has no unknown `X`/`Z` bits when `core_stall` drops. |
| `A_LOAD_RDATA_STABLE` | `Error` | Ensures load data remains stable and glitch-free after stall completion. |
| `A_NO_ERR_ON_SRAM_LOAD`| `Error` | Asserts that valid SRAM accesses never raise `core_err`. |
| `A_MISALIGNED_NO_HANG` | `Error` | Bounded property (`##[1:20] !core_stall`) verifying misaligned requests never hang the pipeline. |

---

## 📊 Coverage Goals & Results

Functional coverage is measured across 7 coverpoints and cross-coverages:

- **`cp_op`**: 100% coverage of all 8 RV32I load/store instructions.
- **`cp_alignment`**: 100% coverage of byte offsets (`00`, `01`, `10`, `11`).
- **`cp_op_x_alignment`**: Cross coverage ignoring invalid unaligned combinations.
- **`cp_region`**: 100% coverage across `SRAM`, `MMIO`, and `OOR` regions.
- **`cp_op_x_region`**: Cross of every operation type in every address space.
- **`cp_addr`**: Boundary address testing (`SRAM_BASE`, `SRAM_LIMIT`, `MMIO_BASE`, `MMIO_LIMIT`, `OOR_ADDR`).

---

## 🚀 How to Run Simulation

### Option A: Using Xilinx Vivado (`xsim`) on Windows/Linux

Run the automated PowerShell script:
```powershell
powershell -ExecutionPolicy Bypass -File .\run_lsu_tb.ps1
```
*Outputs generated:*
- Logs: `logfiles/scoreboard.log`, `logfiles/errors.log`
- Coverage Report: `logfiles/coverage_report/dashboard.html`

### Option B: Using Synopsys VCS (`vcs` & `urg`)

Run via Bash script or Makefile:
```bash
# Using Shell Script
chmod +x run_vcs.sh
./run_vcs.sh

# Or using Makefile
make          # Build, simulate, and generate URG coverage report
make verdi    # Launch Verdi GUI waveform debugger
make dve      # Launch DVE coverage analyzer
make clean    # Clean build artifacts
```
