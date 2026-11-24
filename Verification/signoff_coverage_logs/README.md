# RISCFORGE Digital Verification — Sign-Off Coverage Proof Logs

> **Scope**: Official Cadence IMC 24.09 & Vivado Simulator (XCRG) Code and Functional Coverage Reports  
> **Sign-Off Authority**: CJ Verification Deliverables (G4 Core Verification, G5 Architectural Verification, G6 SoC Integration)  
> **Repository Target**: `raghul7cj/RISC-V-SoC-contribution` (Branch: `1TOPS_review`)

---

## 📊 Coverage Summary Matrix

| Log File | Tool / Engine | Target Subsystem / DUT | Coverage Type | Score / Bins | Sign-Off Gate |
|:---|:---|:---|:---|:---|:---|
| [`01_functional_coverage_csr_unit_cadence_imc.txt`](01_functional_coverage_csr_unit_cadence_imc.txt) | Cadence IMC 24.09 | `tb_csr_corner_unit` (`csr_regfile`) | Functional (Covergroups) | **100.00%** (236/236 bins) | **G5!row12 (5.8)** |
| [`02_code_coverage_csr_unit_cadence_imc.txt`](02_code_coverage_csr_unit_cadence_imc.txt) | Cadence IMC 24.09 | `csr_regfile.v` + `csr_if` | Code (Block, Expression, Toggle) | **99.09%** TB / **72.13%** DUT | **G4!row19 (4.14)** |
| [`03_metrics_coverage_csr_unit_cadence_imc.txt`](03_metrics_coverage_csr_unit_cadence_imc.txt) | Cadence IMC 24.09 | `csr_regfile.v` | Instance Metrics Table | Grade 100% Metric | **G4!row19 (4.14)** |
| [`04_functional_coverage_irq_unit_cadence_imc.txt`](04_functional_coverage_irq_unit_cadence_imc.txt) | Cadence IMC 24.09 | `tb_irq_restructure` | Functional (Covergroups) | **100.00%** (471/471 bins) | **G5!row12 (5.8)** |
| [`05_code_coverage_irq_unit_cadence_imc.txt`](05_code_coverage_irq_unit_cadence_imc.txt) | Cadence IMC 24.09 | IRQ Gateway + Arbiter + WB | Code Coverage Hierarchy | **97.99%** Arbiter / **85.38%** Gateway | **G4!row19 (4.14)** |
| [`06_metrics_coverage_irq_unit_cadence_imc.txt`](06_metrics_coverage_irq_unit_cadence_imc.txt) | Cadence IMC 24.09 | `irq_unit` modules | Instance Metrics Breakdown | Detailed Module Sign-Off | **G4!row19 (4.14)** |
| [`07_functional_coverage_csr_regfile_vivado_xcrg.txt`](07_functional_coverage_csr_regfile_vivado_xcrg.txt) | Vivado XCRG 2022.2 | `csr_regfile` Covergroups | Functional (13 Covergroups) | **100% Score** (5 Instances) | **G5!row12 (5.8)** |
| [`08_functional_coverage_irq_unit_vivado_xcrg.txt`](08_functional_coverage_irq_unit_vivado_xcrg.txt) | Vivado XCRG 2022.2 | `irq_unit` Covergroups | Functional (12 Covergroups) | **100% Score** (12 Instances) | **G5!row12 (5.8)** |
| [`09_code_coverage_operations_cadence_imc.txt`](09_code_coverage_operations_cadence_imc.txt) | Cadence IMC 24.09 | Full Core Pipeline (ALU, MDU, LSU) | Code Coverage Hierarchy | Complete Datapath Coverage | **G4!row16/18 (4.12/4.13)** |
| [`10_code_coverage_exceptions_cadence_imc.txt`](10_code_coverage_exceptions_cadence_imc.txt) | Cadence IMC 24.09 | Core Exception Controller | Code Coverage Hierarchy | Trap Commit & Flush Logic | **G5!row7 (5.3)** |
| [`11_code_coverage_interrupts_cadence_imc.txt`](11_code_coverage_interrupts_cadence_imc.txt) | Cadence IMC 24.09 | Core Interrupt & Handler Vectoring | Code Coverage Hierarchy | Vectoring & MRET Logic | **G4!row16 (4.12)** |
| [`12_coverage_aon_timer_bark_cadence_imc.txt`](12_coverage_aon_timer_bark_cadence_imc.txt) | Cadence IMC 24.09 | AON Timer Watchdog / Bark | Code Coverage Hierarchy | Watchdog Timeout & Bark Logic | **G3!row10 (3.6)** |
| [`13_coverage_trap_stress_multicycle_cadence_imc.txt`](13_coverage_trap_stress_multicycle_cadence_imc.txt) | Cadence IMC 24.09 | Full Core Under Multi-Burst Traps | Code Coverage Hierarchy | Robustness Under Load | **G6!row17 (6.13)** |
| [`14_cadence_imc_master_campaign_summary.json`](14_cadence_imc_master_campaign_summary.json) | Cadence Xcelium + IMC | Entire Testbench Campaign | Campaign JSON Audit | 16/16 Test Suites Passed | **All Gates (G1–G6)** |

---

## 🎯 Coverage Verification Highlights

1. **100.00% Functional Coverage on Privileged CSRs & Traps (`tb_csr_corner_unit`)**:
   - Cadence IMC: 236 out of 236 covergroup bins fully hit (100.00%).
   - Vivado XCRG: 13 covergroups (status, metadata, collision, counter, reset, etc.) scored 100%.
2. **100.00% Functional Coverage on Interrupt Arbitration (`tb_irq_restructure`)**:
   - Cadence IMC: 471 out of 471 covergroup bins fully hit (100.00%).
   - Vivado XCRG: 12 covergroups (eligibility, round-robin, stream choice, fixed pair, etc.) scored 100%.
3. **Multi-Cycle Stress & Robustness Signed Off**:
   - High-stress back-to-back trap injection (`core-trap-stress-multi-burst`) and watchdog bark timeout (`aon-core-bark`) evaluated with zero hung pipeline stages, zero invalid commits, and complete branch/toggle accounting.
