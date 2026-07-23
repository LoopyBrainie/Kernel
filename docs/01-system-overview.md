# 01 · System Overview (18-Box Architecture)

**Plan section**: §二
**Key decisions**: D1, D2, D3, D4, D5, D6, D7, D8, D9, D10, D11, D12, D13, D14, D15, D16, D17, D18
**Status**: Frozen

---

## Overview

Wriggly-Octopus is a tri-lingual (Zig + C HAL + Rust no_std) S-Mode microkernel organized into three layers: (1) the **dispatch layer** that routes syscalls from Shell to subsystems, (2) the **subsystem layer** that provides file, device, and IPC services, and (3) the **unified invariant layer** that holds the 1536 B `Block == RpcUnit == NetworkFrame` contract. Phase 0 collapses layers 1-2 into S-Mode co-residency; Phase 1 separates them with Sv39 PTE alignment.

**R53 D164 系统层改名**: 系统全称 `Wriggly-Octopus` → **`Neur-Aegis`** (CLI 命名空间 `neura`)。三大组件代号 (Basal/Synapse/Cortix) 见 18-box 图中 ⑧ / ② / ① 标注。详见 `docs/00-naming-taxonomy.md` § 1 + § 2 (D164 系统级命名 + 三大组件代号)。

## 18-box architecture (top-level)

```
┌─────────────────── 18-box top-level architecture ───────────────────┐
│                                                                       │
│  ──── Layer 1: Dispatch ────                                         │
│  ① Rust no_std Shell — Cortix (R58 ✅, D173 豁免 Q69, 撤销 cosmo_kernel) │
│       ↓  Call Gate (D56/D62/D73 物理分治)                            │
│  ② Zig Kernel Dispatcher — Synapse (R55, D153 锁定 syscall_dispatch.zig) │
│       ↓                                                              │
│  ③ Scheme Router (D9.2 lr.d/sc.d or D87/D94 soft fallback)         │
│       │                                                              │
│  ──── Layer 2: Subsystems ────                                      │
│       ├── ④ file:// service (D22 v2.1 + D36 Flat File Table)       │
│       ├── ⑤ dev://uart0 (D25 + D88 Early Console SBI Stub)        │
│       ├── ⑥ dev:// network (D79 14B MAC DMA + D96 Shim Layer)     │
│       └── ⑦ scheme:// router (D9.2 + D79/D85 RpcUnit)             │
│                                                                       │
│  ──── Layer 3: HAL + C ABI ────                                     │
│  ⑧ C HAL — Basal (R54 收 cosmo_*→basal_*) (early_console_init D88) │
│  ⑨ RISC-V HAL (csrr time D21 + AIA/PLIC D32/D38/D67/D83)          │
│                                                                       │
│  ═════ Unified 1536B Invariant (D57) ═════                         │
│  ⑩ BlockPool (D29/D31, 512KB) ↔ ⑪ NodePool (D29/D61, 132KB)        │
│  ⑫ RpcUnit (D57, 1536B = 8B header + 1528B payload)                │
│  ⑬ NetworkFrame (D57, 1536B external + 14B MAC internal)           │
│  ⑭ block_t / RpcUnit / NetworkFrame 同构 (D57/D85 offsetof)       │
│                                                                       │
│  ═════ Phase 0/1 同构演进 (D26/D31) ═════                          │
│  ⑮ Phase 0 软边界 (Zig opaque + 链接段隔离)                         │
│  ⑯ Phase 1 PTE 强隔离 (Sv39 Sv48, D102 Page-Aggregation)          │
│                                                                       │
│  ⑰ Static Profile (RR Scheduler, 16KB Hart-Local Stack)           │
│  ⑱ Server Profile (Work-Stealing, FS/VS Lazy Save D104)           │
└───────────────────────────────────────────────────────────────────────┘
```

## Layer responsibilities

| Layer | Boxes | Privilege | Cross-language | Phase 0 → 1 |
|-------|-------|-----------|----------------|-------------|
| 1. Dispatch | ① ② ③ | S-Mode (both Shell + Kernel) | Rust → Zig | No change (D55) |
| 2. Subsystems | ④ ⑤ ⑥ ⑦ | S-Mode | Rust + Zig | U-Mode PTE alignment in Phase 1 |
| 3. HAL | ⑧ ⑨ | S-Mode | C + asm | No change |
| Invariant | ⑩ ⑪ ⑫ ⑬ ⑭ | Hardware-enforced (no MMU) | All three | Sv39 PTE in Phase 1 |
| Evolution | ⑮ ⑯ | Phase-differentiated | Zig opaque vs PTE | Switch at Phase 1 boot |
| Profile | ⑰ ⑱ | Build-time switch | All three | Profile switch via -Dtarget= |

## Cross-cutting concerns

| Concern | Where it lives | Decision(s) |
|---------|----------------|-------------|
| Cross-language ABI | ABI Contract doc | D74, D85, D86, D90, D101 |
| Stack separation | Call Gate doc | D56, D62, D70, D73, D82, D92, D106 |
| Atomicity | HAL doc | D9.2, D87, D94 |
| Static pool | Memory Subsystem doc | D29, D31, D61, D84, D102 |
| Error propagation | Error Handling doc | D28, D40, D89, D91, D103 |
| Build pipeline | Build Pipeline doc | D74, D93, D100, D101, D105 |
| Scheduler | Scheduler doc | D43, D104 |

## Phase 0 vs Phase 1 (key differences)

| Aspect | Phase 0 | Phase 1 |
|--------|---------|---------|
| Memory model | S-Mode co-residency + soft boundaries (D31) | Sv39 PTE alignment (D26) |
| Storage layout | Sparse 4KB pages (D45) | Compact (D102) + sparse comm pages |
| Shell privilege | S-Mode co-resident (D97 containerized) | U-Mode with PTE sandbox (D55 unchanged API) |
| Page table | None | Sv39 / Sv48 |
| Work-Stealing | Not active (RR) | Active when Server Profile |
| FS/VS save | N/A (no V extension) | Lazy save (D104) |

## Cross-references

- **Memory Topology** (02): detailed 644KB pool breakdown
- **Memory Subsystem** (09): runtime pool APIs
- **ABI Contract** (04): 5-layer defense for cross-language types
- **Phase 0 MVP** (15): Day 4 implementation plan
