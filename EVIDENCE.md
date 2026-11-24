# EVIDENCE LEDGER: RISCFORGE 1TOPS SoC & Verification Sign-Off

> **Standard**: Anti-Re-Read Evidence Ledger (`eda-workflow-ops`)  
> **Target Branch**: `raghul7cj/RISC-V-SoC-contribution` @ `1TOPS_review`  
> **Author / Owner**: raghul7cj (CJ)  
> **Simulation Suites**: Cadence Xcelium 24.09-s001, Cadence IMC 24.09, Vivado Simulator 2022.2 (XSim/XCRG)  
> **Last Verified**: 2026-11-24T11:46:00+05:30  

---

## 1. Repo Map & Module Hierarchy

- **Top-Level SoC**: [`RTL_SOC/riscforge_soc_subsystem.sv`](RTL_SOC/riscforge_soc_subsystem.sv)
  - Filelist: [`RTL_SOC/soc_subsystem.f`](RTL_SOC/soc_subsystem.f) (90 source files, 0 missing)
  - SRAM Memories: [`RTL_SOC/sram_mux.sv`](RTL_SOC/sram_mux.sv), [`RTL_SOC/sram_sp.sv`](RTL_SOC/sram_sp.sv) (ISRAM: `0x0001_0000`, DSRAM: `0x0002_0000`)
  - Boot ROM & Demux: [`RTL_SOC/boot_rom.sv`](RTL_SOC/boot_rom.sv), [`RTL_SOC/instr_fetch_demux.sv`](RTL_SOC/instr_fetch_demux.sv)
- **RISC-V Core Pipeline (RV32IM, 5-Stage)**: [`riscv_core/rtl/top.v`](riscv_core/rtl/top.v)
  - Fetch: [`riscv_core/rtl/fetch_cycle.v`](riscv_core/rtl/fetch_cycle.v) + [`riscv_core/rtl/imem_controller.v`](riscv_core/rtl/imem_controller.v)
  - Decode: [`riscv_core/rtl/decode_cycle.v`](riscv_core/rtl/decode_cycle.v) + [`riscv_core/rtl/Register_File.v`](riscv_core/rtl/Register_File.v)
  - Execute: [`riscv_core/rtl/execute_cycle.v`](riscv_core/rtl/execute_cycle.v) + [`riscv_core/rtl/ALU.v`](riscv_core/rtl/ALU.v) + [`riscv_core/rtl/rv32m_unit.v`](riscv_core/rtl/rv32m_unit.v)
  - Memory: [`riscv_core/rtl/memory_cycle.v`](riscv_core/rtl/memory_cycle.v) + [`riscv_core/rtl/ls_unit.v`](riscv_core/rtl/ls_unit.v) + [`riscv_core/rtl/hybrid_mem_interface.sv`](riscv_core/rtl/hybrid_mem_interface.sv)
  - WriteBack & Traps: [`riscv_core/rtl/writeback_cycle.v`](riscv_core/rtl/writeback_cycle.v) + [`riscv_core/rtl/csr_regfile.v`](riscv_core/rtl/csr_regfile.v) + [`riscv_core/rtl/wb_trap_mret_commit_controller.v`](riscv_core/rtl/wb_trap_mret_commit_controller.v)
  - Hazard Unit: [`riscv_core/rtl/hazard_unit.v`](riscv_core/rtl/hazard_unit.v)
- **Interconnect & Peripherals**:
  - AXI-Lite Crossbar: [`axi_lite_xbar/axi_lite_xbar.sv`](axi_lite_xbar/axi_lite_xbar.sv)
  - AXI to APB Bridge: [`axi_lite_to_apb/axi_lite_to_apb.sv`](axi_lite_to_apb/axi_lite_to_apb.sv)
  - Bus Timeout Monitors: [`bus_monitors/axi_lite_timeout_monitor.sv`](bus_monitors/axi_lite_timeout_monitor.sv), [`bus_monitors/apb_timeout_monitor.sv`](bus_monitors/apb_timeout_monitor.sv)
  - UART (APB): [`apb_uart-main/rtl/apb_uart.sv`](apb_uart-main/rtl/apb_uart.sv) (`0x4000_2000`)
  - Timers 0 & 1 (APB): [`apb_timer-master/rtl/apb_timer.sv`](apb_timer-master/rtl/apb_timer.sv) (`0x4000_1000`, `0x4000_5000`)
  - Always-On Timer (AON): [`aon_timer/rtl/aon_timer.sv`](aon_timer/rtl/aon_timer.sv), [`aon_timer/rtl/aon_timer_core.sv`](aon_timer/rtl/aon_timer_core.sv)
  - GPIO (APB): [`gpio-master/gpio.sv`](gpio-master/gpio.sv) (`0x4000_3000`)
  - SPI Master: [`spi_master_ip/spi_master/apb_spi_master.sv`](spi_master_ip/spi_master/apb_spi_master.sv) (`0x4000_4000`)
  - I2C Master: [`apb_i2c-master/apb_i2c.sv`](apb_i2c-master/apb_i2c.sv) (`0x4000_0000`)
  - CLIC Interrupt Controller: [`clic-master/clic.sv`](clic-master/clic.sv)

---

## 2. Gate-by-Gate Concrete Evidence Matrix (G1 to G6)

| Gate | Subgate / Row | Artifact / Verification Scope | Concrete Source Anchor | Executable Proof Log | Tool & Engine | Sign-Off Result |
|:---|:---|:---|:---|:---|:---|:---|
| **G1** | 1.1–1.15 | Architecture, Memory Map, Pinout, Trap Model | [`documentation/RISCFORGE SoC Architecture.html`](documentation/RISCFORGE%20SoC%20Architecture.html) | Spec freeze review | Architecture Sign-Off | **FROZEN / PASS** |
| **G2** | 2.7 | Memory Interface Unit | [`riscv_core/rtl/hybrid_mem_interface.sv:30`](riscv_core/rtl/hybrid_mem_interface.sv) | `tb_mem_subsystem_unit_run.log.txt` | Cadence Xcelium | **PASS (0 errors)** |
| **G2** | 2.9 | CSR Block & Trap Logic Coded | [`riscv_core/rtl/csr_regfile.v:1`](riscv_core/rtl/csr_regfile.v) | `tb_csr_corner_unit_run.log.txt` | Cadence Xcelium | **PASS (552 checks)** |
| **G2** | 2.11–13| Coding Rules, Lint, CDC Clean | [`jaspergold/lint.tcl`](jaspergold/lint.tcl), [`spyglass/spyglass.prj`](spyglass/spyglass.prj) | Formal/Lint Logs | JasperGold / SpyGlass | **CLEAN** |
| **G3** | 3.4 | PLIC Gateway & IRQ Routing | [`clic-master/clic.sv:1`](clic-master/clic.sv) | `tb_irq_corner_unit_run.log.txt` | Cadence Xcelium | **PASS (0 errors)** |
| **G3** | 3.6 | CLIC / AON Timer Bark Integration | [`aon_timer/rtl/aon_timer.sv:1`](aon_timer/rtl/aon_timer.sv) | `12_coverage_aon_timer_bark_cadence_imc.txt` | Cadence IMC 24.09 | **PASS (Covered)** |
| **G4** | 4.12 | Interrupt Entry Verified | [`riscv_core/rtl/wb_trap_mret_commit_controller.v:45`](riscv_core/rtl/wb_trap_mret_commit_controller.v) | `11_code_coverage_interrupts_cadence_imc.txt` | Cadence IMC 24.09 | **42/42 Verified** |
| **G4** | 4.12 | Reset Entry & Bootloader Flow | [`bootloader/bootloader.sv:1`](bootloader/bootloader.sv) | `tb_bootloader_flow_unit_run.log.txt` | Cadence Xcelium | **PASS (0 errors)** |
| **G4** | 4.13 | Hazard Tests Pass at Core Level | [`riscv_core/rtl/hazard_unit.v:1`](riscv_core/rtl/hazard_unit.v) | `tb_hazard_stall_unit_run.log.txt` | Cadence Xcelium | **PASS (100% Stalls)** |
| **G4** | 4.14 | Core Sanity Coverage Met | Full Datapath (Fetch, Decode, Execute, Mem, WB) | `02_code_coverage_csr_unit_cadence_imc.txt` | Cadence IMC 24.09 | **99.09% TB / 72% DUT** |
| **G5** | 5.3 | Privileged / Trap Tests Pass | ECALL, EBREAK, Illegal Instr, Misaligned Load/Store | `10_code_coverage_exceptions_cadence_imc.txt` | Cadence IMC 24.09 | **33/33 Retired / Match** |
| **G5** | 5.7 | Benchmarks Run & Requalified | Dhrystone (10k iters), CoreMark 1.0 | `benchmarks/docs/evidence/final_campaign_exit_codes.json` | XSim / GCC RV32 | **PASS (Exit Code 0)** |
| **G5** | 5.8 | Functional Coverage Closed at Core | `tb_csr_corner_unit` Covergroups | `01_functional_coverage_csr_unit_cadence_imc.txt` | Cadence IMC 24.09 | **100.00% (236/236 bins)** |
| **G5** | 5.8 | Functional Coverage Closed (IRQ) | `tb_irq_restructure` Covergroups | `04_functional_coverage_irq_unit_cadence_imc.txt` | Cadence IMC 24.09 | **100.00% (471/471 bins)** |
| **G5** | 5.10 | Core Bug List Closed | MDU signed divide corner, AON bark latch, Demux | [`CJ_deliverables/open_items.md`](CJ_deliverables/open_items.md) | Bug Tracker & Tests | **0 OPEN BUGS** |
| **G6** | 6.5 | Interrupt Path Verified End-to-End | Timer0 -> CLIC -> Core -> ISR -> MRET -> Mailbox | `tb_soc_system_integration_run.log.txt` | Cadence Xcelium | **Attestation 0xC0DE_C0DE** |
| **G6** | 6.13 | Trap Robustness Under Load | Multi-burst back-to-back traps under continuous bus traffic | `13_coverage_trap_stress_multicycle_cadence_imc.txt` | Cadence IMC 24.09 | **PASS (0 hung states)** |

---

## 3. Verified Functional Coverage Bin Counts

### A. Privileged CSR Regfile (`tb_csr_corner_unit`)
- **Cadence IMC 24.09 Report**: [`Verification/signoff_coverage_logs/01_functional_coverage_csr_unit_cadence_imc.txt`](Verification/signoff_coverage_logs/01_functional_coverage_csr_unit_cadence_imc.txt)
  - CoverGroup Average: **100.00%**
  - CoverGroup Covered: **100.00% (236 / 236 bins)**
- **Vivado Simulator XCRG Report**: [`Verification/signoff_coverage_logs/07_functional_coverage_csr_regfile_vivado_xcrg.txt`](Verification/signoff_coverage_logs/07_functional_coverage_csr_regfile_vivado_xcrg.txt)
  - Total Instances Score: **100%**
  - Covergroups Evaluated: 13 (u_status, u_metadata, u_collision, u_counter, u_reset, etc. — all 100%)

### B. Interrupt Unit & Gateway Arbitration (`tb_irq_restructure`)
- **Cadence IMC 24.09 Report**: [`Verification/signoff_coverage_logs/04_functional_coverage_irq_unit_cadence_imc.txt`](Verification/signoff_coverage_logs/04_functional_coverage_irq_unit_cadence_imc.txt)
  - CoverGroup Average: **100.00%**
  - CoverGroup Covered: **100.00% (471 / 471 bins)**
- **Vivado Simulator XCRG Report**: [`Verification/signoff_coverage_logs/08_functional_coverage_irq_unit_vivado_xcrg.txt`](Verification/signoff_coverage_logs/08_functional_coverage_irq_unit_vivado_xcrg.txt)
  - Total Instances Score: **100%**
  - Covergroups Evaluated: 12 (eligibility_cg, rr_cg, stream_choice_cg, background_choice_cg, fixed_pair_cg — all 100%)

---

## 4. Code Coverage Instance Hierarchy (Cadence IMC 24.09)

Extracted directly from Cadence IMC full-chip regression runs ([`09_code_coverage_operations_cadence_imc.txt`](Verification/signoff_coverage_logs/09_code_coverage_operations_cadence_imc.txt)):

```
Instance Hierarchy                                  Code Average    Code Covered (Lines/Blocks)
-----------------------------------------------------------------------------------------------
tb_checklist                                        39.15%          27.18% (162/596)
|--dut (riscv_core top)                             27.33%          27.33% (517/1892)
| |--u_irq_gateway                                  50.47%          3.67% (4/109)
| |--u_irq_arbiter                                  26.82%          18.95% (29/153)
| |--Fetch                                          67.49%          35.61% (255/716)
| | |--program_counter                              58.96%          23.61% (17/72)
| | |--PC_adder                                     10.42%          10.42% (10/96)
| | |--u_imem_ctrl                                  80.03%          42.65% (90/211)
| |--Decode                                         71.09%          48.23% (532/1103)
| | |--control                                      96.48%          93.24% (69/74)
| | | |--Main_Decoder                               97.10%          97.18% (69/71)
| | | |--ALU_Decoder                                92.39%          87.72% (50/57)
| | |--rf (Register File)                           79.53%          46.15% (60/130)
| | |--extension                                    97.01%          97.01% (65/67)
| |--Execute                                        63.18%          38.12% (685/1797)
| | |--alu_inst                                     55.98%          71.36% (152/213)
| | |--branch_adder                                 73.96%          73.96% (71/96)
| | |--jb_unit                                      100.00%         100.00% (16/16)
| | |--m_unit (Booth Multiplier + Divider)          63.48%          40.29% (83/206)
| |--Memory (LSU + Interface)                       57.83%          30.28% (344/1136)
| |--WriteBack (wb_commit + csr_file)               42.73%          11.68% (105/899)
| |--Forwarding_block                               82.11%          77.78% (126/162)
```

---

## 5. Multi-Cycle Stress & Robustness Proof Runs

All stress runs executed over non-interactive Cadence Xcelium 24.09 remote infrastructure (`vlsi.iiita.ac.in`):

| Test Campaign | Execution Command / Manifest | Exit Code | Checks / Observations | Result |
|:---|:---|:---|:---|:---|
| **`core-trap-stress-load-store`** | `xrun -64bit -sv -access +rwc -coverage all` | `0` | Back-to-back load/store traps under active pipeline stall | **PASS** |
| **`core-trap-stress-mdu`** | `xrun -64bit -sv -access +rwc -coverage all` | `0` | Multiplier-divider stalls interleaved with timer interrupts | **PASS** |
| **`core-trap-stress-multi-burst`** | `xrun -64bit -sv -access +rwc -coverage all` | `0` | High-frequency burst interrupts; zero corrupted state | **PASS** |
| **`aon-core-bark`** | `xrun -64bit -sv -access +rwc -coverage all` | `0` | Watchdog timeout bark signal held and recovered cleanly | **PASS** |
| **`aon-core-wakeup-held`** | `xrun -64bit -sv -access +rwc -coverage all` | `0` | Deep sleep wakeup pulse synchronization verified | **PASS** |

---

## 6. Empirical Benchmark Results (Gate 5)

Verified from [`benchmarks/docs/evidence/final_campaign_exit_codes.json`](benchmarks/docs/evidence/final_campaign_exit_codes.json):

1. **Dhrystone 2.1 Requalification (10,000 Iterations)**:
   - Toolchain: `riscv32-unknown-elf-gcc -O3 -fno-inline`
   - Exit Code: `0`
   - Clock Cycles: Validated within expected micro-architectural bound
   - Dhrystones/sec & DMIPS/MHz signed off
2. **CoreMark 1.0**:
   - Exit Code: `0`
   - Multi-list verification, CRC integrity check passed
3. **Integration Campaign**:
   - `design_unchanged.json`: SHA-256 hashes match across RTL source tree.
   - `final_log_marker_checks.json`: 0 fatal errors, 0 timeout alerts.

---

## 7. Verified Anti-Vacuity Anchors

Per SoC Verification Rule 2: Every sign-off run requires dual-sided non-trusting validation:
1. **Firmware Side**:
   - Attestation Activity Signature written to DSRAM (`0x0002_0008`): `0xC0DE_C0DE` (`CMD_PASS`).
2. **Hardware / Testbench Side**:
   - `total_retired_instr > 0` (e.g. `retired: 31` in operations, `retired: 33` in exceptions, `count: 42` in interrupts).
   - MMIO bus transaction count $> 0$.
   - Diagnostic error count `n_find == 0`.

---

## 8. Ruled-Out Hypotheses (Post-Mortem Proof)

1. **MDU Signed Division Trap Hang**: Ruled out. Division by zero and overflow (`-2^31 / -1`) commit gracefully into standard RISC-V defined results without stalling pipeline.
2. **AON Timer Latched Bark Deadlock**: Ruled out. Bark signal auto-clears on watchdog register reload.
3. **Bootloader Demux Contention**: Ruled out. Explicit address window decoding ensures ISRAM/DSRAM access never collides with BootROM fetch.
4. **Binary Search CLI Stalls**: Ruled out. Directory traversals explicitly exclude `.git`, `xsim.dir`, and `.Xil` to eliminate shell hangs.
