# Neur-Aegis: RISC-V Tri-Lingual Microkernel (R53 顶层改名)

**Date**: 2026-07-23
**Status**: D1-D174 frozen (R31-R62 RATIFIED); 0 open questions
**Owner**: Brra1n0
**Branch**: dev
**Supersedes**: —

---

## How to read this spec (D120 全量重写, R35 裁定)

```txt
Read first (current truth in 1 minute):
  ① 这一段 (Headline) →  数字带权威源标注, doc-gate 自动比对
  ② 00-ffi-pillars.md →  4 个 pillar 红线 (D125 唯一入口)
  ③ D-tag 索引 (Phase 1+ 自动化)

Read for the model (5 minutes):
  Architecture (18-box) →  01-system-overview.md (D120 重写后)
  Design Decisions (D1-D125) →  03-design-decisions.md (status 列完整)
  4 Pillars →  00-ffi-pillars.md

Read for execution (15 minutes):
  20-documentation-gate.md (63 forbidden words) →  Q30 元禁词生效
  per-subsystem docs (01-15) →  各 pillar 传染面清单
  15-phase0-mvp.md (T1.1-T1.20) →  D114 升级后实施计划
```

> **D120 落地约束 ②**: 本节"派生数字"(D 范围 1-125、任务 1.1-1.20、禁词 63、审计 R1-R36)全部从 ledger/census 自动读取, doc-gate `make audit-derive-numbers` 不等即熔断。手写摘要永久退役。

---

## One Sentence

A S-Mode tri-lingual (Zig + C HAL + Rust no_std) microkernel that holds **one** non-negotiable invariant — `Block == RpcUnit == NetworkFrame == 1536 B` — and uses that single scale to bridge 16 KB-stack embedded SoCs to thousands-of-cores NUMA servers without ever violating the 16-byte RISC-V C-ABI red line.

---

## Overview

Wriggly-Octopus is a Phase 0 (MVP) S-Mode logical-isolation microkernel that compiles a single binary footprint deployable from a 16 KB-stack RV64IMAC development board to a hypothetical multi-socket RVV server. Phase 1 (U-Mode + Sv39 MMU) is fully scoped but not implemented. The architecture is locked to 125 decisions across 36 audit rounds; no open questions remain.

> **D49 量纲标注 (D123 落地约束 ②)**: V2.2 644KB 是**净数据预算** (capacity planning),非物理占用。物理总预算 = 净 622KB + NOLOAD 132KB = 754KB (Embedded Sparse, 详见 D123 reconciliation 台账)。低端 Profile 加载预算红线按物理口径定义。

---

## Motivation

### Current State (today)

- No tri-lingual microkernel exists that holds 1536 B invariant across storage, IPC, and wire formats.
- Existing systems (Linux, seL4, Zephyr) trade off either embedded simplicity for server throughput, or server correctness for embedded footprint.
- Multi-language FFI ABI drift is the dominant source of cross-platform kernel bugs; no widely deployed microkernel enforces post-build ELF physical-size melt-down (D113 jq 升级)。

### Problems (today's pain)

1. **Jumbo Frame 1536 B ecological rift** (D108 — `SHIM_PAYLOAD_MAX` 按 `-Dip_family` 派生)
2. **S-Mode co-residency "compiler safety illusion"** (D31 — opaque barriers depend on build-time audit + D116 `--all-targets` 覆盖)
3. **Server-grade DTB trampling risk** (D95 — multi-MB DTBs adjacent to .boot_meta)
4. **Cross-language FFI ownership vacuum** (D103 + D121 — 白名单 5 struct + 手写必须内嵌三端断言)
5. **Vector/Float context tax in scheduler** (D118 — FS=Off 懒切换 + 三条件消歧)

### Desired State (target)

- One binary footprint, one ABI, one static-pool topology, one scheduler pluggable interface.
- Phase 0: 16 KB Hart-Local stack + Zig opaque types + 132 KB NodePool placeholder = 644 KB 净数据 (754 KB 物理), deployable on `0x8020_0000`.
- Phase 1: Sv39 PTE isolation activates without user-facing API change (D55); Server Profile switches to Page-Aggregation compact storage (D102 Compact 384KB 物理)。
- 63 forbidden words in `20-documentation-gate.md` mechanically block known traps (D115).

---

## 4 Pillars (D125 — 唯一入口: `00-ffi-pillars.md`)

| Pillar | 红线 | 权威文件 |
|--------|------|----------|
| 1. ABI & FFI | D86 + D90 + D103 + D119 + D121 | `00-ffi-pillars.md` § Pillar 1 |
| 2. sys_result_t 16B a0/a1 | D86 + D101 + D113 + D119 | `00-ffi-pillars.md` § Pillar 2 |
| 3. sscratch + in_kernel_space | D82 + D92 + D106 + D107 | `00-ffi-pillars.md` § Pillar 3 |
| 4. Graceful degradation | D87 + D94 + D104→D118 + D117 | `00-ffi-pillars.md` § Pillar 4 |

> **D125 落地约束 ②**: 子系统文档复述 pillar 红线必须回链 `00-ffi-pillars.md` 锚点, 无回链视为私自立法(熔断)。

---

## Design Decisions (D1-D125 Full Table)

详细 ledger 见 `03-design-decisions.md`,含 status 列 (ACTIVE / DEPRECATED / SUPERSEDED) 与 supersede 链:

- **DEPRECATED (1)**: D62 superseded by D73 (R21)
- **SUPERSEDED (5)**: D91→D110, D96→D108, D101→D113, D104→D118, D106→D107
- **R31-R36 18 GAPs RATIFIED**: D107-D125

Class follows `[specification-writing/decision-hygiene.md]`:
- **Class 1 (evidence)**: RISC-V spec citations, off-the-shelf library versions, git history
- **Class 2 (coherence)**: Decisions that follow the spec thesis
- **Class 3 (taste)**: Picked deliberately with constraint; revisit triggers logged

**Headline decisions** (full table at `03-design-decisions.md`):

| # | Class | Status | Decision |
|---|-------|--------|----------|
| D57 | 2 | ACTIVE | 1536B three-layer same-structure invariant |
| D86 | 1 | ACTIVE | RISC-V C ABI 16B red line |
| D89 | 1 | ACTIVE | Q22 closure: 8B payload three-segment bitfield |
| D90 | 1 | ACTIVE | Cross-language ABI: only u8/u16/u32/u64 + u8[N] |
| D100 | 1 | ACTIVE | UKI Loader ELF Program Header scan |
| D107 | 1 | ACTIVE | Trap entry sscratch HLCB per-Hart (R31 替代 D106) |
| D108 | 1 | ACTIVE | Shim Layer `-Dip_family` 派生 (R31 替代 D96) |
| D109 | 2 | ACTIVE | Sparse PTE alignment + D31/D84 二级隔离 |
| D110 | 1 | ACTIVE | Bit 30 + 解码次序 (R32 替代 D91) |
| D112 | 1 | ACTIVE | ex_table `ld` (R32 替代 D116) |
| D113 | 1 | ACTIVE | check_elf_sizes.sh jq (R32 替代 D101) |
| D114 | 1 | ACTIVE | MVP 任务表与 RATIFIED 强同步 (R33) |
| D115 | 1 | ACTIVE | doc-gate 59→63 + 元禁词 (R33) |
| D116 | 1 | ACTIVE | geiger `--all-targets` (R33) |
| D117 | 1 | ACTIVE | Tier 2 IPI ACK timeout rdtime 派生 (R34) |
| D118 | 1 | ACTIVE | FS=Off 懒切换 + 三条件消歧 (R34 纠正 D104) |
| D119 | 1 | ACTIVE | syscall6 6-arg XLEN + arity 表 (R34) |
| D120 | 1 | ACTIVE | SPEC.md 全量重写 + 派生数字机检 (R35) |
| D121 | 1 | ACTIVE | D74 SSOT 白名单 + 手写+断言 (R35) |
| D122 | 1 | ACTIVE | D62 DEPRECATED + status 全表回填 (R35) |
| D123 | 1 | ACTIVE | 净/物理双口径 + 22KB 定位 (R36) |
| D124 | 1 | ACTIVE | stride gate 派生常量 (R36) |
| D125 | 1 | ACTIVE | 00-ffi-pillars.md 聚合红线 (R36) |

**Open questions: 0.** (Q22 closed in R25; Q23-Q40 closed in R31-R36.)

---

## Architecture (18-box)

Full architecture detail: `01-system-overview.md` (D120 重写后)。

```
①  Rust no_std Shell (Phase 0 S-Mode 共址, D97 容器化审计 + D116 --all-targets)
   ↓  Call Gate (D73 call + global var, D62 DEPRECATED, D107 per-Hart HLCB)
②  Zig Kernel Dispatcher (D89 sys_result_t 16B)
   ↓
③  Scheme Router (D9.2 / D87 / D94 / D117 IPI timeout)
   │
   ├── ④ file:// service (D22 + D36 Flat File Table)
   ├── ⑤ dev://uart0 (D25 + D88 Early Console SBI Stub)
   ├── ⑥ dev:// network (D79 14B MAC DMA + D108 -Dip_family 派生)
   └── ⑦ scheme:// router (D9.2 + D85 RpcUnit)

⑧  C HAL (cosmo_panic_abort D76 + D117 panic fall-through)
⑨  RISC-V HAL (csrr time D21 + D80 Sstc + D118 FS=Off 懒切换)

═══ Unified 1536B Invariant (D57) ═══
⑩  BlockPool (D29/D45 净 384KB 物理 512KB Embedded Sparse, D123 量纲标注)
⑪  NodePool (D29/D61 132KB NOLOAD 占位, Phase 0 不读)
⑫  RpcUnit (D57 1536B = 8B header + 1528B payload + D108 ip_family 1B + 7B reserved)
⑬  NetworkFrame (D57 1536B external + 14B MAC internal D60)
⑭  block_t / RpcUnit / NetworkFrame 同构 (D57/D85 offsetof)

═══ Phase 0/1 同构演进 (D26/D31) ═══
⑮  Phase 0 软边界 (Zig opaque + 链接段隔离)
⑯  Phase 1 PTE 强隔离 (Sv39 Sv48, D109 PTE alignment + D31/D84 二级)

⑰  Static Profile (RR Scheduler, 16KB Hart-Local Stack)
⑱  Server Profile (Work-Stealing, D118 FS=Off 懒切换)
```

---

## Implementation Plan (Phase 0: T1.1-T1.20, D114 升级后)

详细 plan: `15-phase0-mvp.md` (D114 已升级)。

### Phase 0: MVP S-Mode Logical Isolation (Day 4)

- [ ] **T1.1** build.zig SSOT translate-abi (D74 + D121 白名单)
- [ ] **T1.2** C `sys_result_t` 16B + payload 8B (D86/D89)
- [ ] **T1.3** Rust `#[repr(C, align(8))] sys_result_t` (D74 auto-gen, D121 白名单)
- [ ] **T1.4** entry.S Step 0 (D95 + D92)
- [ ] **T1.5** S-Mode Hart ID OpenSBI FFI (D99)
- [ ] **T1.6** UKI Loader ELF scan (D100)
- [ ] **T1.7** `cosmo_panic_abort` C HAL (D76 + D117 panic-reachable)
- [ ] **T1.8** early_console_init SBI Stub (D88)
- [ ] **T1.9** Call Gate 5-file stub (D56 + D73 + D82)  ← D62 弃用
- [ ] **T1.10** sys_atomic_cas_ptr 3-tier (D94 + D117 timeout)
- [ ] **T1.11** check_elf_sizes.sh (D113 jq + --json) ← D101 弃用
- [ ] **T1.12** initrd ≤ 50 build.zig (D105)
- [ ] **T1.13** Network Shim Layer (D108 -Dip_family) ← D96 弃用
- [ ] **T1.14** Phase 0 Shell compile-time audit (D97 + D116 --all-targets)
- [ ] **T1.15** Trap entry sscratch (D107 HLCB per-Hart) ← D106 弃用
- [ ] **T1.16** HLCB per-Hart Step 0/1 顺序 (D107 binding)
- [ ] **T1.17** build.zig `-Dip_family` 编译期熔断 (D108 binding)
- [ ] **T1.18** sys_error_decode 解码次序钉死 (D110 binding)
- [ ] **T1.19** ex_table 16B size + insn 升序 (D112 binding)
- [ ] **T1.20** PMP region 预算编译期记账 (D109 binding)

### Wave ordering (Build → Prove → Remove)

```txt
Wave 1: Build Phase 0 (T1.1-T1.20)
Wave 2: Prove on QEMU rv64 + Allwinner D1s (RV64IMAC, no A-extension)
Wave 3: Prove on SiFive HiFive Unmatched (RV64GC, with A-extension)
Wave 4: Defer Phase 1 (D26/D31/D43/D83/D91→D110/D102/D104→D118)
```

---

## Edge Cases (R31-R36 衍生)

| Scenario | First-hit mitigation | Long-term fix |
|----------|----------------------|---------------|
| A-extension absent | D87 soft fallback | D94 3-tier + D117 IPI timeout |
| Cache coherence absent (cross-Hart) | D94 Tier 2 fallback | D117 1ms timeout + panic fall-through |
| DTB 物理 corruption | D95 Anti-Trampling | D98 max size 64KB/8MB |
| Tier 2 IPI ACK wedge | **D117 1ms rdtime timeout** | (no further fallback, panic) |
| FS/VS Dirty Bit cross-task leak | **D118 FS=Off + 三条件消歧** | (D104 题面错误已纠正) |
| 6-arg syscall 设计 | **D119 XLEN 原生整型红线** | (继承 D86/D90/D103) |
| Multi-Hart Trap range check | **D107 HLCB per-Hart** | (D106 全局符号弃用) |
| 1536B ↔ IPv6 1520B 溢出 | **D108 -Dip_family 派生** | (D96 硬编码弃用) |
| sym_result_t Bit 31 vs i32 sign | **D110 Bit 30 重定位** | (D91 弃用) |
| ex_table lwu 读 4B uintptr_t | **D112 ld (8B) 统一** | (D116 弃用) |
| check_elf_sizes awk $5 漂移 | **D113 jq + --json** | (D101 弃用) |
| BlockPool 净/物理语义混 | **D123 双口径 + 量纲标签** | (R35 元规则四扩展) |
| D101 size 闸门盲点 stride | **D124 stride gate 派生** | (类型身份问题归 D121) |
| 4 pillars 失同步 | **D125 00-ffi-pillars.md 聚合** | (子系统复述回链锚点) |
| FFI stack pointer leak | D103 Pin static pool red line | D89 subsystem_id ownership |
| Jumbo Frame switch absent | D108 Shim Layer `-Dip_family` | D96 `-Denable_shim=false` 关闭 |

---

## Success Criteria

> **D120 落地约束 ②**: 本节数字 (`D1-D125` / `T1.1-T1.20` / `63 forbidden`) 由 `make audit-derive-numbers` 从 03-ledger / 15-phase0-mvp / 20-doc-gate 自动读取, 不等即构建错误。

### Phase 0 (single-sprint MVP)

- [ ] `make build` produces `kernel.elf` deployable on QEMU `-machine virt -cpu rv64`
- [ ] `kernel.elf` 物理 ≤ 754KB (D123 净 622KB + NOLOAD 132KB, Embedded Sparse)
- [ ] `make test` runs 5 ABI static asserts (D86) + 5 post-build ELF size checks (D113 jq) + 1 stride gate (D124)
- [ ] `make audit-shell` runs `cargo-geiger --all-targets` (D116) and reports 0 unsafe blocks (per allowlist)
- [ ] `make test-no-a-ext` runs on RV64IMAC (D87 + D94 Tier 3)
- [ ] `make test-dtb-corruption` injects 1-byte DTB error → SBI SRST halt (D95)
- [ ] `make test-jumbo-on` enables Shim Layer (D108 -Dip_family=v4) and verifies 1500B MTU
- [ ] `make test-shim-v6` enables D108 -Dip_family=v6 and verifies 1444B payload (no 1520B 溢出)
- [ ] `make test-multi-hart` QEMU `-smp 4` (D107 HLCB per-Hart + D117 IPI timeout)
- [ ] `make test-fs-clean-retry` task uses FPU first time, D118 three-condition gate retries
- [ ] Documentation gate `bash docs/ci/check-docs.sh` reports **0/63 forbidden words** (D115)
- [ ] `make audit-pillars` checks 14 subsystem docs back-link to `00-ffi-pillars.md` (D125)
- [ ] `make audit-status-column` checks 03-design-decisions.md status 列完整 (D122)
- [ ] `make audit-derive-numbers` checks SPEC.md numbers match ledger (D120)

### Phase 1 (deferred)

- [ ] `make test-sv39` boots with Sv39 page tables and Shell remains at user-mode stable for 60 s
- [ ] Page-Aggregation compact mode reports 0% Padding waste on Server Profile
- [ ] Work-Stealing scheduler on 8-Hart QEMU reports > RR scheduler throughput (target: 1.5x)
- [ ] D109 PTE alignment + D31/D84 SATP/PMP 二级隔离在 Phase 1 启用

---

## References

### Per-subsystem docs (this directory)

- `docs/00-ffi-pillars.md` — **D125 4 pillars 聚合红线 (唯一入口)**
- `docs/01-system-overview.md` — 18-box architecture (D120 重写后)
- `docs/02-memory-topology.md` — V2.2 净 644KB / 物理 754KB (D123 双口径)
- `docs/03-design-decisions.md` — D1-D125 status 列 ledger
- `docs/04-abi-contract.md` — 5-Layer Defense (D86/D90/D103/D121)
- `docs/05-call-gate.md` — sscratch 6-layer (D73 + D107)
- `docs/06-boot-sequence.md` — entry.S Step 0-2 (D92/D95/D99/D100/D112)
- `docs/07-shell-architecture.md` — Phase 0 containerized shell (D97 + D116)
- `docs/08-risc-v-hal.md` — HAL (D21/D80/D87/D94/D104→D118/D117)
- `docs/09-memory-subsystem.md` — Static pool + Page-Aggregation (D102/D109)
- `docs/10-error-handling.md` — D89 sys_result_payload_t + D110 Bit 30
- `docs/11-network-driver.md` — D60/D79/D108 Shim Layer
- `docs/12-scheduler.md` — D43/D118 FS/VS Lazy Save + D107 HLCB 刷新
- `docs/13-build-pipeline.md` — D74/D93/D100/D113/D124 stride gate
- `docs/14-syscall-api.md` — D55/D103/D119 arity 表
- `docs/15-phase0-mvp.md` — T1.1-T1.20 (D114 升级后)
- `docs/20-documentation-gate.md` — 63 forbidden words (D115)
- `docs/30-open-questions.md` — slim stub, 0 open; closure history in `03-design-decisions.md`

### External standards cited

- RISC-V Calling Convention (C ABI): sys_result_t ≤ 16 B → a0/a1 register pair (D86)
- RISC-V Privileged Spec: mhartid M-Mode only (D99), sstatus.FS 四态 §3.1.6 (D118)
- RISC-V AIA/IMSIC: D32/D38/D67/D83
- POSIX errno: SYS_EPERM/ENOENT/EIO/... (D89)
- IEEE 802.3 Ethernet MTU 1500 B: D96/D108 Shim threshold
- OpenSBI: sbi_console_putchar (D88), SBI SRST (D95)

---

## Decisions Log (Class 3 keeps)

| Decision | Constraint | Revisit when |
|----------|------------|--------------|
| D11/D14 RVV Feature Flag (build.zig) | Embedded Phase 0 零向量税 | Server Profile 启用时检查 D118 Dirty 频率 |
| D36 Flat File Table (MAX_FILES=50) | 嵌入式端极简 | 任何文件服务需求 > 50 时 |
| D46 FILE_TABLE .rodata (D78) | 编译期零动态分配 | D105 initrd 门禁触发时 |
| D61 132KB NodePool NOLOAD (Phase 0 不读) | 拓扑零重构 | Phase 1+ 检查 D102 紧凑模式 |
| D67 PLIC 桩退役 (D67 R19) | 不实现通用 PLIC | 真实硬件需要时引入 D83 AIA |
| D78 FILE_TABLE .rodata | 避免 NodePool 槽位污染 | 任何 > 50 文件需求 |

---

## Adjacent Work

- **Phase 1 Sv39 PTE isolation** (D26/D31/D84/D102/D109) — deferred
- **AIA/IMSIC driver** (D83) — deferred; D67 PLIC stub satisfies Phase 0
- **Work-Stealing scheduler** (D43/D111) — deferred; RR satisfies Phase 0
- **Bit 30 = 1 descriptor table** (D110) — deferred to Phase 1+ server profile
- **D44 Zicboz cache zero** — opportunistic, may implement if Server Profile encountered
- **D37 4KB physical aggregation page** — opportunistic, deferred to Phase 1
- **D-tag 自动索引 (Phase 1+)** — 替换 03-design-decisions.md status 列手工回填,自动化 RATIFIED 传染面

---

**End of SPEC.md.** D120 全量重写,派生数字由 `make audit-derive-numbers` 自动比对 03-ledger。子系统红线条目权威入口 `00-ffi-pillars.md` (D125)。
