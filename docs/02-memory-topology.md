# 02 · Memory Topology (V2.2 644 KB Static Pool)

**Plan section**: §九 + §1.13 (R13)
**Key decisions**: D29, D31, D36, D45, D49, D51, D53, D61, D75
**Status**: Frozen

---

## Overview

Wriggly-Octopus Phase 0 uses a deterministic, zero-heap memory topology totaling 644 KB. The layout is locked at compile time, address-stable across embedded and server profiles, and obeys the 4 KB physical page alignment protocol required by SPI Flash (D75). There is no malloc, no free, no dynamic resizing.

## V2.2 physical memory layout (linker-enforced)

> **R50 索引注 (D160)**: 下方 ledger 表按 profile 列出 V2.2 物理布局, 但 mabi (D138) / stride (D126) / cache line (D48, D146) / RpcUnit align (D71) 的**跨 profile 对照** (embedded / qemu_virt / server_compact) 见 [`16-profile-matrix.md`](16-profile-matrix.md). 矩阵为索引, 本 doc 为 source of truth.

```
0x8020_0000 ┌─────────────────────────────────────┐  ← _start (D93 fixed base)
            │ .text (Zig kernel + RpcUnit)        │  ~80 KB
            ├─────────────────────────────────────┤
            │ .rodata (FILE_TABLE, D78)           │  ~10 KB
            ├─────────────────────────────────────┤
            │ .data (initialized globals)         │  ~4 KB
            ├─────────────────────────────────────┤
            │ .bss (HLCB, freelists)              │  ~8 KB
            ├─────────────────────────────────────┤
0x802?_???? │ .boot_meta (4KB page, D63 decoupled)│  4 KB
            ├─────────────────────────────────────┤
            │ ─── static pool (D29) ───           │
            │ BlockPool (256 × 1536B = 384 KB)   │  384 KB
            │   ↳ 2 blocks per 4KB page (D45)    │
            │   ↳ 25% Padding 1024B per page      │
            ├─────────────────────────────────────┤
            │ NodePool (132 KB NOLOAD placeholder)│  132 KB
            │   ↳ Phase 0: 占位不读 (D61)        │
            │   ↳ Phase 1: 未来 mesh node lookup 空间   │
            ├─────────────────────────────────────┤
            │ Guard Page (3584B, 防止 overflow)    │  ~4 KB
0x802?_????
            └─────────────────────────────────────┘
```

Total kernel image: **644 KB** (D29 + D49 + D51 + D52)

> **D123 落地约束 ① (R36) 净/物理双口径 reconciliation 台账**:
>
> | Pool | net (净数据) | physical (物理占用) | NOLOAD 占位 | 备注 |
> |------|--------------|---------------------|-------------|------|
> | .text | 80 KB | 80 KB | — | D29 |
> | .rodata | 10 KB | 10 KB | — | D29/D78 (含 FILE_TABLE 4 KB, D46 50×80B, R47 勘误: D151 84B/4.2KB 已被 ctypes 实测撤销, 自然布局 sizeof=80B) |
> | .data | 4 KB | 4 KB | — | D29 |
> | .bss | 8 KB | 8 KB | — | D29/D52 |
> | .boot_meta | 4 KB | 4 KB | — | D63 |
> | **BlockPool** | **384 KB** (256×1536B) | **512 KB** (128 pages × 4096B) | — | D45 25% padding |
> | **NodePool** | 0 KB (Phase 0 不读) | 0 KB (占位) | **132 KB NOLOAD** | D61 |
> | MacDmaPool | 3584 B (256×14B) | 4 KB (1 page) | — | D79 |
> | Guard Page | — | 4 KB | — | D49 |
> | **Σ ledger (net)** | **497.5 KB** | — | — | 主段 9 行 ledger net 列逐项求和: 80+10+4+8+4+384+0+3.5+4 = **497.5 KB** ✓ |
> | **Σ ledger (physical)** | — | **626 KB** | + 132 KB NOLOAD = **758 KB 虚拟** | 主段 9 行 ledger physical 列逐项求和: 80+10+4+8+4+512+0+4+4 = **626 KB** ✓ (R48 勘误: 原 '622 KB' 系笔误, 实际求和 = 626 KB) |
> | **D49 双行制 (R48 立法)** | ceiling **644 KB** = named **581.5 KB** + headroom **62.5 KB** | — | — | D49 ceiling + 已命名子段 Σ + 未分配余量 = ceiling (581.5 + 62.5 = 644 算术恒等) |
>
> **P3-11 子段划分 (R48 重做, 删除 R47 伪闭合恒等式)**: D49 双行制在文, 不再写 "=644 ✓" 伪闭合.
>
> | 子段 | 大小 | D# | 备注 |
> |------|------|-----|------|
> | 早期栈池 (Hart-Local × 4) | 64 KB | D92/D107/P3-1 | 4 Hart × 16 KB stack top-aligned |
> | SBI stub 区 | 8 KB | D88 | early_console_putchar 静态 trampoline |
> | D139 panic log 环形 | 2 KB | D139 | 512 entry × 4B, 持久化到 .boot_meta |
> | DTB 转储预留 | 2 KB | D77 | QEMU virt DTB 通常 ≤ 8 KB, 留 2 KB 缓冲 |
> | Step 0 trampoline | 2 KB | D92/D95 | Anti-Trampling + sscratch 设置代码 |
> | HLCB 表 | 4 KB | D107 | 64 Hart × 64 B (含 P1-1 HLCB extern) — **已含于 .bss 8 KB, 不重复计入 ledger** |
> | scheme 路径池 | 2 KB | D103 | Pin static pool, ~256 个 scheme handle — **已含于 .bss 8 KB, 不重复计入 ledger** |
> | **Σ 子段** | **84 KB** | — | 子段总额 84 KB; 其中 HLCB 4 + scheme 2 共 6 KB 已含于 .bss, 净子段增量 = 84 − 6 = 78 KB |
>
> **D49 双行制 (R48 立法, 替换 R47 伪闭合恒等式)**:
>
> | 量纲 | 数值 | 派生 | 语义 |
> |------|------|------|------|
> | D49 预算上限 (ceiling) | **644 KB** | D49 立法 (Phase 0 任何时刻 footprint 不得越此线) | ceiling |
> | Σ 已命名子段 (named) | **581.5 KB** | 主段 net ledger 497.5 KB + 子段总额 84 KB | named (按 ledger 逐项可复算) |
> | 未分配余量 (headroom) | **62.5 KB** | ceiling − named = 644 − 581.5 | 留头 (ELF overhead, 链接 padding, .got/.plt 等) |
>
> **复算留证 (R48 收官节引用)**:
> - 主段 ledger net: 80 + 10 + 4 + 8 + 4 + 384 + 0 + 3.5 + 4 = **497.5 KB** (按 ledger 9 行 net 列逐项)
> - 子段 Σ: 64 + 8 + 2 + 2 + 2 + 4 + 2 = **84 KB** (按子段 7 行)
> - ledger + 子段 总: 497.5 + 84 = **581.5 KB**
> - 未分配余量: 644 − 581.5 = **62.5 KB**
> - D49 双行制 验证: 581.5 + 62.5 = **644 KB** ✓ (算术恒等)
> - **R47 伪闭合删除**: 原 "主段 497.5 + 子段新增 (64+8+2+2+2+0+0) = 640 KB, 再 +4 KB 对齐 padding = 644" 系算术伪造 (497.5 + 78 ≠ 640); R48 改用子段总额 84 KB (含已含于 .bss 部分, 不二次扣减) + 未分配余量 62.5 KB, 与 ceiling 644 KB 算术严格相等.
>
> **D123 落地约束 ②**: spec 中一切内存数字禁止裸写, 必须带量纲标签 (net / physical / NOLOAD / ceiling / named / headroom), doc-gate `make audit-derive-numbers` 机检双行制, 不闭合即熔断.

## Decision trace (audit history)

| Round | Decision | Choice | Why |
|-------|----------|--------|-----|
| R12 | D12 | Migrate base from 0x801F_F000 to 0x8020_0000 | QEMU virt default |
| R13 | D49 | V2.2 layout: 644 KB total | Server profile + NodePool + Guard |
| R14 | D51 | No PMP isolation for static pool | D31 soft isolation sufficient |
| R14 | D52 | `.bss` size 56KB → 8KB | Shrink to fit V2.2 |
| R16 | D57 | 1536B three-layer invariant | 12 × 128B cache line alignment |
| R17 | D61 | 132KB NodePool preserved as NOLOAD | Future PTE alignment ready |
| R21 | D75 | 4KB physical page alignment for SPI Flash | Flash sector size |

## Why 1536 B (D57 deep dive)

1536 B = 12 × 128 B = 6 × 256 B. The 128 B number is the SiFive HiFive cache line; 12 lines per RpcUnit = exactly 4 KB per 2-RpcUnit page. The 14 B Ethernet MAC header is **external** (D60) — counted in 3 SG-DMA descriptors, not in 1536 B.

```
┌───────────────── 4 KB physical page (P1-3 算术闭合重画) ─────────────────┐
│  Padding   │   Block 1   │   Block 2   │   Padding  │
│  (512B)    │   (1536B)   │   (1536B)   │   (512B)   │
└──────────────────────────────────────────────────────┘
   ↑                  ↑                ↑
   D45 sparse      RpcUnit/Block    RpcUnit/Block
   formula         (D57)            (D57)
   (各端 12.5%, 合计 25%)
```

**P1-3 算术闭合 (替代 R36 5120≠4096 错误图)**:
- 单页布局: `[Pad 512][Block 1536][Block 1536][Pad 512]` = 1024B padding total, 单页 = 4096B ✓
- **总 padding / 页**: 512 + 512 = 1024B (R30 D102 "25% padding" 立法采用各端 12.5%, 与合计 25% 等价)
- **4 KB 页 / 256 块**: 128 页 × 4096B = 524288B = 512 KB 物理 (D45 + D133 ceiling/measured 双轨)
- **稀疏 layout** = block 在每页内不连续, 而是 page_idx × 2 + slot 反解 (D45 sparse reverse 公式, 见 09 § D155 后处理):

```c
// kernel/src/mem.zig (D45 sparse reverse 公式, P1-3 锁死)
fn block_index_to_byte_offset(idx: usize) usize {
    std.debug.assert(idx < 256);  // 256 blocks total
    return (idx / 2) * 4096 + (idx % 2) * 1536 + 512;  // 512B 起头 padding
}
fn byte_offset_to_block_index(off: usize) usize {
    const page = off / 4096;
    const rem = off % 4096;
    std.debug.assert(rem == 512 or rem == 512 + 1536);  // 必须落在 padding 后
    return page * 2 + (rem - 512) / 1536;
}
```

## Two-tier static pool (D29)

| Pool | Size | Block size | Count | Phase 0 use | Phase 1 use |
|------|------|------------|-------|-------------|-------------|
| BlockPool | 384 KB | 1536 B | 256 | Storage + RpcUnit | Same + U-Mode comm page |
| NodePool | 132 KB | N/A (placeholder) | 0 | 占位 (D61) | mesh node lookup / HashMap |

BlockPool is split in 4KB pages per D45 sparse formula. NodePool is `NOLOAD` in linker script — virtual address space is reserved but no physical pages are committed in Phase 0.

## Why 132 KB NodePool (D61 deep dive)

Phase 0 does not need a node table, but the 132 KB placeholder:
- **Formats the address space** uniformly across embedded/server
- **Enables binary identity** between 16 KB-stack SoC and NUMA server builds
- **Reserves the range** for future `basal_node_id → fd` translation tables
- Costs zero (no physical pages, no runtime reads)

## Cross-references

- **Memory Subsystem** (09): runtime APIs (compact_alloc, sparse_alloc, D102)
- **ABI Contract** (04): `RpcUnit` 1536B offsetof constraints (D85)
- **Error Handling** (10): `SYS_ENOSPC` returned on BlockPool exhaustion
- **Documentation Gate** §二十.7: see gate catalog for all forbidden phrases (R12-R30)
