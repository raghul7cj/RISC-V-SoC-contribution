# 00 — Overview: RISCFORGE RV32IM_Zicsr 5-Stage Core

This is the architecture-level overview of the RISC-V core in
`rv32im_zicsr_5stage_exc_nointr/`. It is a flat, synthesizable Verilog delivery
folder. It is the entry document in the `design_spec/` set; sibling documents
(01–05) dive deeper into CSR/hazards, exception & interrupt handling, the
LSU/memory system, fetch/branch microarchitecture, and verification.

The hierarchy below (`top.v` and its cycle partitions) is the primary,
drift-correct view; the `5_stage/` refactored tree is a sibling copy.

---

## 1. What this core is

A 5-stage, in-order RISC-V CPU implementing **RV32IM + Zicsr** in **M-mode**.
No user mode, no MMU, no virtual memory. Control and hazard management all
reside at the top level (`top.v`). Resets are **active-low** (`rst=0` resets);
the PC boots to `0x8000_0000`.

### Feature status

| Feature | Status |
|---|---|
| RV32I base ISA (pipeline, hazard, forwarding, load/store) | Validated |
| M-Extension (Booth–Dadda mult, non-restoring div) | Validated |
| Zicsr machine-mode CSRs | Validated |
| Precise exceptions (ecall, ebreak, illegal_instr, misaligned, access-fault) | Validated |
| Load/Store unit | Validated (standalone TB) |
| Interrupts | Stubbed — CLIC is a dummy stub (`clic.sv`); the interrupt path is exercised through the `timer_intr_i` mechanism (`timer_intr=1`, `ext_intr=0`, `msft_intr=0`) |

The interrupt plumbing (priority, IRQ flush of the frontend, WB commit) is
implemented in RTL, but the external interrupt source is bypassed: only the
timer interrupt input is driven high in the top level. See doc 02.

---

## 2. Pipeline architecture

The core is a five-stage in-order pipeline. Each stage is one cycle module plus
the inter-stage pipeline register it owns:

```
  IF      ID       EX        MEM        WB
 clk ───▶ │ clk ───▶│ clk ───▶│ clk ───▶│  (combinational WB mux)
 ─────────┼─────────┼─────────┼─────────┼──────────
  PC       RF read   operand   ls_unit    ResultW mux
  imem     decode    ALU       hybrid     (no register)
  ctrl     sign-ext  JB/M     dmem/AXI
           RF        m_ext
────────────────────────────────────────
    hazard_unit: forwarding + stalls + flushes
```

### What each stage produces

| Stage | Module | Produces / responsible for |
|---|---|---|
| IF | `fetch_cycle.v` | PC update, instruction fetch from IMEM, IF/ID register → `InstrD`, `PCD`, `PCPlus4D`, `valid_D`; detects misaligned-PC exception on `PC_next[1:0]!=00` |
| ID | `decode_cycle.v` | Control signals (Main/ALU decoders), register-file read, immediate extension, ID/EX register; detects `illegal_instr`, `ecall`, `ebreak`; emits CSR decode fields (`csr_valid_E`, `csr_raddr_E`, `csr_op_E`, `is_mret_E`) |
| EX | `execute_cycle.v` | Forwarding muxes, ALU operand select, ALU, branch/jump target computation, M-extension, CSR read-address drive and CSR read data; produces EX/MEM register; computes `PCSrcE`/`PCTargetE` (with `irq` acceptance); detects misaligned branch/jump |
| MEM | `memory_cycle.v` | Load/store alignment (`ls_unit`), load/store access, **hybrid** SRAM + AXI4-Lite interface, MEM/WB register; produces the CSR write sideband (`csr_write_en_W`…`old_csr_W`); mem stall output |
| WB | `writeback_cycle.v` | Combinational writeback mux (selects result source: ALU / data / PC+4 / old-CSR) |

All stage connections, hazard/forwarding wiring and the trap/MRET/CSR support
blocks are instantiated at the top (`top.v`), not inside the stage modules.

---

## 3. Module map

Exact module file names in the flat RTL directory (`.v` unless noted):

| Module | Role |
|---|---|
| `top.v` | Top-level integration: stage interconnection, hazard unit, CSR regfile, WB trap/MRET commit controller; defines IRQ qualification/priority and gated write signals |
| `fetch_cycle.v` | IF stage + IF/ID append register; next-PC and misaligned-PC detect (IMEM control) |
| `decode_cycle.v` | ID stage + ID/EX register; control decode, RF read, sign-extension, CSR decode fields |
| `execute_cycle.v` | EX stage + EX/MEM register; forwarding mux, ALU, branch/jump unit, M-extension, CSR read-format, IRQ+redirect |
| `memory_cycle.v` | MEM stage + MEM/WB register; LSU + hybrid AXI-SRAM instance, mem stall output, CSR sideband for W stage |
| `writeback_cycle.v` | WB stage (combinational result mux) |
| `hazard_unit.v` | Forwarding, stall/flush generation; load-use, CSR-to-CSR, CSR-to-GPR, M, mem, branch/wb-redirect flushes |
| `csr_regfile.v` | Machine-mode CSR storage + counters; Port A read / Port B normal write / Port C trap-mret write (priority) |
| `wb_trap_mret_commit_controller.v` | WB trap/MRET/IRQ commit controller; redirect to `mtvec`/`mepc`, pipeline flush, mstatus restore |
| `clic.sv` (SV) | **Dummy stub** — preserved CLIC ports/params, dummy outputs (interrupts stubbed) |
| `imem_controller.v` | Instruction SRAM address select; branch `spec_tag` gating of wrong-path data (NOP), branch penalty 2 |
| `Instruction_Memory.v`\* | IMEM array (4 MB sim / 16 KB synth), `$readmemh` |
| `Data_Memory.v`\* | DMEM array (word-addressed, `DMEM_BASE` subtract), `$readmemh` |
| `hybrid_mem_interface.v` | Decodes SRAM (native) versus AXI4-Lite window; SRAM/AXI read/write FSM; `mem_err` access-fault |
| `ls_unit.v` | Load-store alignment/byte replication |
| `axi_lite_dummy_slave.v` | AXI4-Lite dummy slave for MMIO transactions (test/simulation) |
| `Control_Unit_Top.v` | Wraps Main_Decoder + ALU_Decoder; assembles `lsunit`, `Branch`, `Jump` buses |
| `Main_Decoder.v` | Opcode-level decode (RegWrite, ImmSrc, ALUSrc, MemWrite, ResultSrc, Branch, Jump, LUISrcE, CSR valid) |
| `ALU_Decoder.v` | Decodes ALUControl from ALUOp + funct3 + funct7 + op5 |
| `opcode_check.v` | Valid-opcode detection → `illegal_instr` |
| `Register_File.v` | 32×32, async read, sync write, x0=0, same-cycle write-forward |
| `Sign_Extend.v` | I/S/B/J/U/shift immediate generation |
| `ALU.v` | 32-bit ALU (ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU/JALR) |
| `Mux_3_by_1.v` | 3:1 forwarding mux (2+1) |
| `Mux2.v` | 2:1 mux (e.g. ALUSrc operand select) |
| `PC.v` | PC register, reset `0x8000_0000`, stalls on `StallF` |
| `PC_Adder.v` | (PC+4) and branch-target adder |
| `JB_unit.v` | Branch condition evaluation (BEQ/BNE/BLT/BGE/BLTU/GEU) |
| `rv32m_unit.v` | M-extension multiplexer + stall arbitration |
| `rv32m_mul.v` | Booth-encoded multiplier, 3-cycle |
| `booth_enc.v` | Booth encoding for multiplier |
| `pp_gen.v` | Partial-product generation |
| `csa.v` | Carry-save adder |
| `rv32m_div.v` | Non-restoring divider, 32-cycle |

`tb_riscof.v` and `tb_imem_ctrl.v` are RTL-simulating test harnesses, not part
of the core.

`\*` Large-mem modules are gated by `ifndef SYNTHESIS` (4 MB sim / 16 KB synth).

---

## 4. Key support subsystems

Six subsystems work together to make the simple-stage pipeline behave like a
precise, machine-mode RISC-V core:

1. **CSR register file** (`csr_regfile.v`) — machine CSRs + performance
   counters (`mcycle`/`minstret` and halves). Three ports: A combinational read,
   B synchronous normal-instruction write, C synchronous trap/MRET write that
   overrides B. `minstret` increments on retirement (`valid_W & ~exc_valid_W`).

2. **CSR instruction micro-architecture** (through decode + execute) — CSR ops
   (CSRRW / CSRRS / CSRRC, imm and reg forms) are decoded in ID, have their CSR
   read address/op carried to EX, and the RMW is performed at EX (Port A read +
   ALU RMW). The write sideband is pipelined through EX/MEM and MEM/WB to Port B
   of the regfile, with hazard-unit CSR stalls to avoid WAW/RAW hazards.

3. **Precise exceptions + IRQ injection at EX** — an exception sideband
   (`exc_valid/D/E/M/W`, `exc_cause`, `exc_tval`, `exc_pc`) propagates beside
   each stage so the oldest exception is tracked; precise traps commit at WB
   (`wb_trap_mret_commit_controller`) which redirects to mtvec, writes
   mepc/mcause/mtval and flushes. IRQ is qualified/prioritized at the top
   (`MEIP > MTIP > MSIP`) and injected into the **EX** stage (`irq_pending`,
   `irq_id`, `irq_flush_frontend`) rather than WB, but is only committed into
   architectural state at WB.

4. **LSU / hybrid memory** — loads/stores leave the pipeline in MEM via
   `ls_unit` and `hybrid_mem_interface`, which decodes the SRAM window vs the
   AXI4-Lite MMIO window. Accesses outside both windows raise an access-fault
   (`mem_err`). Native SRAM is a 2-cycle registered access (stall; writes 1
   cycle, no stall); AXI is variable-cycle with its own FSMs. A nonzero SRAM/AXI
   stall is fed back into the hazard unit (`mem_stall_out`) to freeze the front.

5. **Delayed instruction fetch + branch handling** (`imem_controller.v`,
   `fetch_cycle.v`) — the register PC / instruction memory output is delayed by
   one cycle (registered address) and the SRAM FSM idles with NOP insertion on
   the drain cycle; a `spec_tag` tracks the branch for pc-redirected drain.
   Branches/jumps are resolved in EX (`PCSrcE`/`PCTargetE`) with a **branch
   penalty of 2 cycles** (speculative drain + refetch). JALR and WB redirect
   (trap) also update the frontend PC.

6. **Retirement-directed commit controller** (`wb_trap_mret_commit_controller.v`) —
   the single place that gates architectural side effects. It uses `valid_W` +
   `exc_valid_W`/`is_mret_W` to decide true commit; the top then gates
   `RegWriteW_gated` and `csr_write_en_W_gated` on `valid_W & ~exc_valid_W &
   ~mret_commit`, and drives a `flush_pipeline_onehot`.

---

## 5. Memory map

The core is a single-hvas system with a hybrid data memory. Program/code, native
SRAM, and AXI4-Lite MMIO share the 32-bit address space.

| Window | Address range | Description |
|---|---|---|
| **Native SRAM (DMEM)** | `0x8000_0000 – 0x8040_0000` | On-chip SRAM that the `hybrid_mem_interface` identifies and routes to `Data_Memory` |
| **AXI4-Lite MMIO** | `0x4000_0000 – 0x4000_FFFF` | AXI bus window to peripherals via `axi_lite_dummy_slave` in sim |
| **Access fault** | any other address | `mem_err=1` → store/load access-fault |

**Word-address quirk.** `Data_Memory` is **word-addressed** (30-bit index): it
translates a byte address by `address >> 2` and then **subtracts a hardcoded
`DMEM_BASE`** from the incoming address before indexing the array. Thus the
"base after subtract" is `0x8000_1000 >> 2` = word address `0x2000_0400`, not
the byte base. (See `LSU_MEMORY_EXCEPTION_DEEP_DIVE.md` for the long-form note.)

| Region | Byte base | Word (`>>2`) index used by DMEM |
|---|---|---|
| IMEM | `0x8000_0000` | `0x2000_0000` |
| DMEM | `0x8000_1000` | `0x2000_0400` (after `DMEM_BASE` subtract 0x400) |

---

## 6. Key global parameters

| Parameter | Value | Description |
|---|---|---|
| XLEN | 32 | RISC-V data path width |
| PC reset | `0x8000_0000` | Boot address |
| SRAM_BASE | `0x8000_0000` | SRAM window base |
| SRAM_LIMIT | `0x8040_0000` | SRAM window end |
| MMIO_BASE | `0x4000_0000` | AXI-Lite base |
| MMIO_LIMIT | `0x4000_FFFF` | AXI-Lite end |
| mstatus WARL mask | `0x0000188A` | SAIL-verified WARL mask (sie[1], mie[3], mpie[7], mpp[12:11]) |
| NOP encoding | `0x00000013` | `ADDI x0, x0, 0` |
| IMEM size | 4 MB sim / 16 KB synth | gated by `ifndef SYNTHESIS` |
| DMEM size | 4 MB sim / 16 KB synth | gated by `ifndef SYNTHESIS` |
| SRAM read latency | 1 cycle | registered addr + registered en; hmif adds 1 = 2 total |
| Branch penalty | 2 cycles | speculative drain + refetch |

---

## 7. Pointer to sibling docs

- **01 `01_csr_regfile_and_hazards.md`** — CSR regfile ports, CSR instruction
  micro-architecture, **why CSR hazards exist**, stall/forwarding rules.
- **02 `02_exceptions_interrupts_stall_flush.md`** — per-stage exception
  detection, IRQ acceptance at EX, the propagation bus, stall/flush
  behaviour, WB commit.
- **03 `03_lsu_hybrid_memory.md`** — LSU, hybrid interface, mem stall,
  the 1-cycle delayed SRAM load/write, AXI path.
- **04 `04_fetch_branch_and_bugfixes.md`** — delayed instruction fetch, branch
  redirect timing, and resolved branch bugs.
- **05 `05_verification_architecture.md`** — verification plan/architecture under `verif/`.

Read the index (`README.md` in this folder) for the "how to read by task" mapping.

---

## 8. Point of control / hazard

The management of control/hazards — the origin of stalls, flushes, forwarding
and the CSR-side lock — lives at the top level in **`top.v`** (the
`hazard_unit` instance and the gated/wired control logic), not in the stage
partitions.