# 09 · Memory Subsystem (Static Pool + Page-Aggregation)

**Plan section**: §九
**Key decisions**: D29, D31, D61, D78, D79, D84, D102, D105
**Status**: Frozen; runtime APIs stable, D102 Phase 1+ deferred

---

## Overview

The memory subsystem manages the 644 KB static pool (BlockPool + NodePool) with compile-time fixed allocation policies. There is no heap, no `malloc`, no `free`. Phase 0 uses sparse 4KB pages; Phase 1 adds Page-Aggregation compact mode (D102) for server-side 0% padding waste.

## Pool architecture (D29)

```zig
// Pool descriptors (compile-time constants) — P1-3 强制: 128 pages / 256 blocks / 512 KB 物理
pub const BlockPool = struct {
    base: [*]align(4096) u8,    // D29, D45
    page_count: usize = 128,    // P1-3: 512 KB / 4 KB = 128 pages (R36 错算为 64 pages, 勘误)
    block_per_page: usize = 2,  // D45: 2 blocks per page (R36 正确)
    used: [128 * 2]AtomicBool,  // P1-3: 256 blocks total (R36 错算为 128, 勘误)
};

pub const NodePool = struct {
    base: [*]align(4096) u8,    // D61: 132 KB NOLOAD placeholder
    size: usize,                // 132 * 1024
    used: AtomicUsize,          // Phase 1+ only
};

// P1-3 + D45 sparse reverse: index ↔ byte offset (替代 R36 `(block-base)/1536` 误算)
fn block_index_to_byte_offset(idx: usize) usize {
    std.debug.assert(idx < 256);
    return (idx / 2) * 4096 + (idx % 2) * 1536 + 512;  // 512B 起头 padding (P1-3 § [Pad 512])
}
fn byte_offset_to_block_index(off: usize) usize {
    const page = off / 4096;
    const rem = off % 4096;
    std.debug.assert(rem == 512 or rem == 512 + 1536);  // 必须在 padding 后, 不能落在 padding 内部
    return page * 2 + (rem - 512) / 1536;
}
```

## Page-Aggregation (D102, Phase 1+)

```zig
pub const PageAggregationMode = enum {
    Compact,    // Phase 1 internal: 1528B blocks contiguous, 0% padding
    Sparse,     // Communication pages: 2 blocks + 1024B padding, PTE alignment
    Auto,       // Server: Compact; Embedded: Sparse
};
```

| Mode | Use case | Padding | PTE alignment |
|------|----------|---------|-------------|
| Compact | S-Mode internal data flow (BlockPool hot path) | 0% | No PTE (single contiguous region) |
| Sparse | U-Mode shell communication pages | 25% | Yes (4KB page-aligned; block isolation by D31/D84 SATP/PMP) |
| **Auto (default)** | **Server Profile** (D135 R40): Compact for BlockPool internal data flow; Sparse for IPC pages | **per-region** | **per-region** (D135 修正自相矛盾: Compact region = No PTE; Sparse region = Yes) |

## D135: Auto 模式 per-region 解耦 (Q50 R40)

R40 Q50 立项前, Auto 行写 "mixed / Yes" — 同一字段两种语义并存, 触发 `enable_page_aggregation=Auto` 时 PTE alignment 检测失判。D135 per-region 拆解: Auto 模式下, BlockPool 内部数据流走 Compact (0% Padding, 无 PTE), IPC pages 走 Sparse (25% Padding, 4KB PTE alignment)。两个 region 各报各的 Padding + PTE alignment, 不再统一为 single-line description。

**传染面清单** (R40 元规则四):
- `build.zig` § PageAggregationMode 编译器分支 (D109 + D135 联动)
- `15-phase0-mvp.md` § PageAggregation T1.13 升级 D135 (Auto 模式双 region reporting)
- `20-documentation-gate.md` 新增禁词: `Auto 模式 mixed padding` / `BlockPool 内部混合 layout` (已入册, R40)

`build.zig` switches: `-Denable_page_aggregation=true/false` (default `true` for Server, `false` for Embedded).

## D109: Sparse 模式 "PTE alignment" 语义降级 (Q25 R31 fix)

**Status**: **RATIFIED** (Q25 → D109, R31).

D102 Sparse 模式声称 "PTE support: Yes (each 4KB page is one PTE)",但物理布局仍是 "2 blocks + 1024B padding" per page。**一个 PTE 覆盖 2 个 block ⇒ PTE 隔离粒度 ≠ block 隔离粒度**。D109 降级语义为 4KB page alignment + D31/D84 SATP/PMP 二级隔离,避免内存膨胀 2.67×。

**核心矛盾**:

```
D102 Sparse (R30, 语义矛盾):
  - 物理布局: [Pad 1024B][Block A][Block B][Pad 1024B] = 4096B
  - PTE 声称: "each 4KB page is one PTE"
  - 真相: 一个 PTE 覆盖 2 个 block, 无法单点隔离 1 个 block

内存预算对比:
  D102 Sparse 严格 PTE 隔离: 256 blocks × 4096B = 1 MB  ← 超出 644KB V2.2 预算 (×2.67)
  D102 Sparse 4KB alignment: 256 blocks × 1536B = 384 KB ← 当前布局, 内存预算不变
```

**D109 修正**:

```zig
// D109 R31 fix: Sparse 模式语义降级为 4KB page alignment + D31/D84 二级隔离
pub const PageAggregationMode = enum {
    Compact,    // 不变: S-Mode internal hot path
    Sparse,     // 语义降级: 4KB page-aligned, 2 blocks share PTE
    Auto,
};

// 内存预算不变: Sparse 物理仍 2 blocks/4KB page (D45)
// block 隔离改由 D31/D84 在 PTE 之外提供第二级防线

// D31: No PMP isolation (Phase 0 软边界)
// D84: Phase 1+ SATP VMA dynamic isolation
// D109: 二者协同保证 "单 block 隔离" 语义

pub const IsolationMechanism = union(enum) {
    pte_alignment: void,           // D102/D109: 4KB page-aligned (D45 默认)
    pmp_region: PmpConfig,         // D31: Phase 0 soft boundary
    satp_vma: SatpVmaConfig,       // D84: Phase 1+ dynamic VMA
};
```

**Sparse 模式隔离的完整链路** (D109 + D31 + D84):

| Profile | U-Mode 请求 1 block | 隔离机制 |
|---------|---------------------|----------|
| Phase 0 Embedded | ❌ 不支持 U-Mode | N/A (D31 软隔离足够) |
| Phase 0 Server | 1 block request | **D31 PMP 区域裁剪** (2 block 区域内仅暴露目标 block) |
| Phase 1+ Embedded | 1 block request | **D84 SATP VMA** (PTE + VMA 双重映射) |
| Phase 1+ Server | 1 block request | **D84 SATP VMA** + **D31 PMP** (纵深防御) |

**U-Mode mmap 路径** (D109 协同, D174 后缀命名漏网补漏):

```rust
// D109: U-Mode 申请 1 个 block 时, 由 D31/D84 提供二级隔离
pub fn neura_mmap(fd: u32, offset: u64, len: usize) -> MmapResult {
    let block_count = (len + 1535) / 1536;  // D57 1536B ceil
    let page_count = (block_count + 1) / 2;  // D45 2 blocks/page

    match build_options.profile {
        .embedded => {
            // Phase 0: 软隔离, 由 D31 PMP 在 2-block 区域内暴露目标 block
            pmp_grant_region(target_block_page, target_block_offset, 1536);
        },
        .server_phase1 => {
            // Phase 1+: SATP VMA 隔离, 1 block 单独映射
            satp_map_single_block(target_block_phys, target_vma, 1536);
        },
    }
    // PTE (D102/D109) 仅保证 4KB alignment, 不保证单 block 隔离
}
```

**Cost / Benefit**:

| Dimension | D102 Sparse (R30, 语义矛盾) | D109 Sparse (R31, 语义降级) |
|-----------|-------------------------------|-------------------------------|
| 内存预算 | 不变 (384KB) | 不变 (384KB) ✓ |
| 单 block 隔离 | ❌ 语义虚假 | ✓ D31/D84 协同 |
| 编译期闸门 | 无 | D86 `_Static_assert` 强制路径选择 |
| API 影响 | mmap 返回 4KB PTE | mmap 返回 D31/D84 sub-region |

**Verification**:

```bash
# R30 测试 (单 block 越界, R31 应当 FAIL)
make test-umode-single-block  # 申请 1 block, 访问相邻 block → 触发 D31/D84 trap

# R31 新增
make test-umode-sparse-pmp    # D31 PMP 二级隔离验证
make test-umode-sparse-satp   # D84 SATP VMA 二级隔离验证
make test-umode-sparse-cross   # 同时启用 D31 + D84 纵深防御
```

**Why Option B (Q25) was chosen over A/C**:

- **Option A** (严格 1 block/4KB page) 内存预算 1MB 超出 644KB V2.2 2.67×, 不可接受。
- **Option C** (禁用 U-Mode Sparse) 违背 D9.2 Scheme Router 必须支持 U-Mode comm 的设计前提, 拒绝。

D109 是 Q25 推荐选项 B 的实现, 接受 "PTE alignment" 命名诚实性 vs 原 "PTE isolation" 营销性的权衡。

## D109/Q25 落地约束: PMP region 预算编译期记账

**PMP region 预算是稀缺资源**: RISC-V 规范定义 PMP 槽位数量因 Hart 而异(典型 16 槽,低至 4 槽)。U-Mode comm 通道的 PMP 占用数必须**编译期记账**,超出 Hart 实际槽位即熔断,防止 Phase 1 通道数增长后悄悄耗尽。

```rust
// D109 binding constraint: PMP region budget 编译期记账
const PMP_MAX_REGIONS: usize = if (build_options.has_pmp_8) {
    8   // 低端 RV64IMAC 常见
} else if (build_options.has_pmp_16) {
    16  // 服务器常见
} else {
    @compileError("Hart has no PMP; U-Mode Sparse mode is FORBIDDEN (D109)");
};

// D109: U-Mode comm 通道 PMP 占用记账
const USED_PMP_REGIONS: usize = blk: {
    var count: usize = 0;
    // 每条 scheme:// IPC 通道消耗 1 个 PMP region
    for (build_options.umode_schemes) |_s| count += 1;
    // Boot ROM 1 region
    count += 1;
    // U-Mode text segment 1 region
    count += 1;
    break :blk count;
};

comptime {
    if (USED_PMP_REGIONS > PMP_MAX_REGIONS) {
        @compileError(
            "D109: U-Mode comm 通道 PMP 占用 " ++ @as(u32, @intCast(USED_PMP_REGIONS))
            ++ " 超出 Hart PMP 槽位 " ++ @as(u32, @intCast(PMP_MAX_REGIONS))
            ++ ". 减少 scheme:// 数量或启用 SATP 替代 PMP (D84)."
        );
    }
}
```

**前瞻备注 (不开新 question)**: Server Profile 内存充裕,Phase 1+ 可通过 `-Denable_strict_pte_isolation=true` opt-in build option 启用真 1 block/页严格隔离,绕过 D109。但**默认仍走 D109 选项 B 路径**。

## Block allocation API

```zig
// Compile-time fixed pool, atomic flags
pub fn block_alloc() ?[*]RpcUnit { ... }
pub fn block_free(block: [*]RpcUnit) void { ... }
pub fn block_owner(block: [*]RpcUnit) u16 { ... }  // D89 subsystem_id
```

**Allocation strategy** (D29):
- `block_alloc`: linear scan `used[]`, return first `false`, atomic set
- `block_free`: index = (block - base) / 1536, atomic clear
- No fragmentation (BlockPool is uniform size)

## FFI ownership (D103)

```zig
/// Cross-FFI ownership rule: Pin static pool only.
/// Stack pointer leak is forbidden (R30 C2).
pub const RpcUnitPtr = struct {
    block: [*]RpcUnit,
    owner_subsystem_id: u16,    // D89
    flags: AtomicU32,           // pinned / dirty / in-flight
};

/// Safety contract:
///   - block MUST be from BlockPool (not stack, not .bss)
///   - owner_subsystem_id MUST match the freeing subsystem
///   - cross-FFI transfers pin `flags |= PINNED`
```

## FFI ownership violation = compile error (D103 + D90)

```zig
comptime {
    // D90: forbid Option<T>, enum, nested struct
    // D103: forbid &[u8] (caller stack) in cross-FFI signatures
    std.debug.assert(@TypeOf(block_slice) != []u8);  // caller stack
    std.debug.assert(@TypeOf(block_slice) == *RpcUnit);  // must be static
}
```

## FILE_TABLE placement (D78)

```c
// FILE_TABLE lives in .rodata, NOT NodePool
// D36: MAX_FILES = 50, D78: physical placement = .rodata
typedef struct {
    uint32_t inode;
    uint64_t block_index;    // D29 BlockPool index
    uint8_t  flags;
    char     name[60];       // D72: max 60 chars
} file_entry_t;

_Static_assert(sizeof(file_entry_t) == 80, "FILE_TABLE entry size");
_Static_assert(MAX_FILES * 80 <= 10 * 1024, "FILE_TABLE in .rodata ≤ 10KB");
```

---

## D151 增补 (R45 Q66): FILE_TABLE .rodata 模板 + .bss mutable_table 双结构

> **回链**: R45 审计新增 D151, D78 FILE_TABLE .rodata 与运行时文件操作矛盾的语义。

### 问题与动机

D78 FILE_TABLE 在 .rodata (编译期常量, 运行时不可写), 但 file_entry_t 含 `block_index` (uint64_t), 文件操作后 block_index 应改变。Spec 当前**没区分 .rodata 模板与 .bss mutable table**。

### D151 立法

明确 .rodata 模板 + .bss mutable_table 双结构, 运行时文件操作写 mutable_table:

```c
// .rodata 模板 (D78, 编译期常量)
typedef struct {
    uint32_t inode;
    uint64_t block_index;  // 初始 block_index
    uint8_t  flags;
    char     name[60];
} file_entry_t;
_Static_assert(sizeof(file_entry_t) == 80, "D151 size");
file_entry_t FILE_TABLE[MAX_FILES] __attribute__((section(".rodata")));

// .bss mutable table (D151 运行时可变)
file_entry_t mutable_table[MAX_FILES] __attribute__((section(".bss")));

// D151 初始化: .bss mutable table 复制 .rodata 模板
void file_table_init(void) {
    for (int i = 0; i < MAX_FILES; i++) {
        mutable_table[i] = FILE_TABLE[i];
    }
}

// D151 运行时文件操作: 写 mutable_table
int neura_read(int fd, void *buf, size_t len) {
    // ... (不变) 但块索引更新写 mutable_table[fd].block_index
    if (new_block_index != mutable_table[fd].block_index) {
        mutable_table[fd].block_index = new_block_index;
    }
    return len;
}
```

**传染面**: `14-syscall-api.md` § neura_open/read/write 改写 mutable_table + `13-build-pipeline.md` § FILE_TABLE 编译期生成 + `20-documentation-gate.md` 新增禁词 "FILE_TABLE 单一不可变"。

## initrd file count gate (D105)

```zig
// build.zig comptime asset validation
const initrd_files = parse_cpio(initrd_path);
if (initrd_files.len > MAX_FILES) {
    @compileError("initrd file count exceeds MAX_FILES=50: " ++
        "remove " ++ @as(u32, @intCast(initrd_files.len - MAX_FILES)) ++ " files");
}
```

## 14B MAC DMA pool (D79)

Network MAC headers (14B per frame) live in a separate 14B-aligned DMA pool, NOT in BlockPool. This allows the SG-DMA driver to scatter 14B + 1536B chunks into a single NIC descriptor ring.

```zig
pub const MacDmaPool = struct {
    base: [*]align(64) u8,    // cache-line aligned
    size: usize,              // 256 × 14B = 3584B
    used: [256]AtomicBool,
};
```

## Cross-references

- **Memory Topology** (02): physical layout 644KB
- **ABI Contract** (04): RpcUnit 1536B constraints
- **Error Handling** (10): SYS_ENOSPC on pool exhaustion
- **Documentation Gate** §二十.7: FILE_TABLE placement phrase is forbidden

---

## D140 增补 (R41 Q55): BlockPool 5-step degradation Phase 1+ 步骤明确定义

> **回链**: 本节为 R41 审计新增 D140 提案, 是 D28/D40 "5-step degradation" 立法的**首次完整定义**。Phase 0 仍然 D65 只 comptime assert (不真正执行), Phase 1+ 按本节顺序执行。

### 问题与动机

D28 + D40 + D65 累计提到"5-step degradation" 3 处, **从未列出 5 个具体步骤**:

| 引用 | 文本 |
|------|------|
| D28 (R2) | "5-step degradation (Phase 1 runtime)" |
| D40 (R14) | "Pool exhaustion → 5-step degradation (Phase 1)" |
| D65 (R19) | "D28/D40 5-step: comptime assert only Phase 0" |

**真实危害**: Phase 1+ pool exhaustion 时, 5 步不可预测, 退化策略不可测, 调度器无法做容量规划。MacDmaPool (256×14B=3584B 固定) / IPC channel (scheme:// 数上限) / PMP slot (D109 触发) 各有不同退化需求, 套用统一 5 步不合理。

### D140 立法

**BlockPool 5 步 (主路径, 仅适用于 BlockPool)**:

| 步 | 名 | 动作 | 触发条件 | 实现成本 |
|----|----|------|----------|----------|
| 1 | **RECLAIM_FREED** | linear scan 找已 free 块的孔洞, 复用 | `block_alloc_scan()` 返回 null | 0 (已有逻辑) |
| 2 | **COMPACT_DIRTY** | 迁移 dirty 块到低索引, 形成连续 free 区间 | step 1 失败 | ~50 行 (搬运 N 个 dirty 块) |
| 3 | **SPILL_TO_NODE** | 把 dirty 数据写到 NodePool (D61 NOLOAD 占位), 释放 BlockPool | step 2 失败 | ~80 行 (Phase 1 才实现 NodePool) |
| 4 | **REDUCE_FS_VS** | 强制所有 task FS=Off, 释放 `256B/task × N task` FPU 上下文 | step 3 失败 | ~30 行 (调度器配合) |
| 5 | **PANIC_FALLBACK** | `basal_panic_abort_fmt("D140: BlockPool exhausted after 5-step")` | step 4 失败 | 0 (D139 panic 路径复用) |

**Per-pool 短路径 (不套用 5 步)**:

| Pool | 退化 | 步数 |
|------|------|------|
| **MacDmaPool** | spill to BlockPool (借用前 14B) → panic | 1 步 |
| **IPC channel** | drop oldest pending IPC → panic | 1 步 |
| **PMP slot** (D109 runtime overflow, 罕见) | reduce SATP VMA 数 → panic | 1 步 |
| **FILE_TABLE** (.rodata) | 不可退化, Phase 1+ 不增加表项即可 | 0 步 |

```zig
// kernel/mm/blockpool_degrade.zig (D140 完整 5 步)
pub const BlockPoolDegradeStep = enum(u8) {
    RECLAIM_FREED  = 1,
    COMPACT_DIRTY  = 2,
    SPILL_TO_NODE  = 3,
    REDUCE_FS_VS   = 4,
    PANIC_FALLBACK = 5,
};

pub fn block_alloc_with_degrade() ?[*]RpcUnit {
    var step: BlockPoolDegradeStep = .RECLAIM_FREED;
    while (true) : (step = @enumFromInt(@intFromEnum(step) + 1)) {
        switch (step) {
            .RECLAIM_FREED => if (block_alloc_scan()) |b| return b,
            .COMPACT_DIRTY => if (block_alloc_compact()) |b| return b,
            .SPILL_TO_NODE => if (block_alloc_spill_to_nodepool()) |b| return b,
            .REDUCE_FS_VS => {
                force_all_tasks_fs_off();
                if (block_alloc_scan()) |b| return b;  // 重试 step 1
            },
            .PANIC_FALLBACK => {
                basal_panic_abort_fmt(@src(),
                    "D140: BlockPool exhausted after 5-step degradation");
                unreachable;
            },
        }
        if (@intFromEnum(step) >= 5) @unreachable;  // safety
    }
}

// MacDmaPool 短路径
pub fn mac_alloc_with_degrade() ?*MacHeader {
    if (mac_alloc_scan()) |m| return m;
    if (block_alloc()) |b| return @ptrCast(b);  // 借用 BlockPool 前 14B
    basal_panic_abort_fmt(@src(), "D140: MacDmaPool + BlockPool exhausted");
    unreachable;
}

// IPC 短路径
pub fn ipc_alloc_with_degrade() ?IpcChannel {
    if (ipc_alloc_after_drop_oldest()) |c| return c;
    basal_panic_abort_fmt(@src(), "D140: IPC channels exhausted");
    unreachable;
}
```

```bash
# D140 测试: 模拟 BlockPool 满, 跑 5 步退化
make test-d140-blockpool-degrade
# 期望日志:
#   step 1 RECLAIM_FREED → 0 free blocks
#   step 2 COMPACT_DIRTY → 0 free blocks
#   step 3 SPILL_TO_NODE → 0 free blocks
#   step 4 REDUCE_FS_VS → release 256B/task × 4 task = 1024B
#   step 1 重试 → 4 blocks 复用
# 期望: 4/4 PASS, step 5 PANIC_FALLBACK 在 1ms 内未触发
```

### 传染面

- `14-syscall-api.md` § `SYS_ENOSPC` 返回条件改写 (Phase 1+ 不立即返回, 先 5 步退化)
- `12-scheduler.md` § context_switch 加 D140 step 4 `force_all_tasks_fs_off()` 实现
- `15-phase0-mvp.md` T1.10 (sys_atomic_cas_ptr 3-tier) 升级为 D140 + 新增 T1.26 (BlockPool 退化测试)
- `20-documentation-gate.md` **新增禁词**: "5-step degradation 未定义" / "Pool 退化假定成功"

### 元规则校验

- 手册/规范: 不涉及 RISC-V 指令/CSR, 是 Phase 1 退化策略定义缺口
- 编译证据: Zig comptime `enum(u8)` 派生 + `while (true) : (step = ...)` 控制流
- 场景矩阵 (6 格): Phase 0 Embedded / Phase 1+ Server BlockPool 满 / MacDmaPool 满 / IPC channel 满 / PMP slot 满 (D109) / .bss 满 (不可能, 静态分配)

---

## D140 落地注释

D140 立法后, **D28/D40 文本需要补写具体步骤** (本节即是补写, 等待 ledger 升 PROPOSED → ACTIVE 时回填到 03-design-decisions.md D28/D40 行)。

---

## D143 增补 (R42 Q58): NodePool NOLOAD Phase 0→1 物理页 commit 机制

> **回链**: R42 审计新增 D143, D5 zero-heap × D61 NodePool NOLOAD 的 Phase 演进 commit 机制缺位。

### 问题与动机

D61 NodePool 在 Phase 0 是 VMA 占位 (linker script `NOLOAD`), 物理页 0, kernel 不能读。Phase 1+ NodePool 用于 mesh node lookup (D61 立法)。

**Phase 0 → Phase 1 过渡**: 谁 commit NodePool 的 132 KB 物理页? 何时 commit? Spec 当前用 "Phase 1+ 才实现 NodePool" 一笔带过, commit 机制未定。

### D143 立法

Phase 1+ 启动时 Step 1 kmain 解析 DTB 后, **显式 commit NodePool 132 KB 物理连续页**。失败时 Phase 1 退化 (Phase 0 行为不变, NOLOAD 占位 0 物理页)。

**不允许 lazy commit** (mmap 风格): 违反 D5 zero-heap, 物理页零碎化不可预测。

```zig
// kernel/mm/nodepool.zig (D143 Phase 1+ 启动 commit)
pub fn nodepool_init() void {
    if (build_options.profile == .embedded_sparse or
        build_options.profile == .embedded_compact) {
        return;  // Phase 0 NOLOAD 不 commit
    }
    // D143: Phase 1+ 启动时预 commit 132 KB 物理连续页
    const nodepool_phys = mmio_alloc_physical(132 * 1024);
    if (nodepool_phys == null) {
        basal_panic_abort_fmt(@src(),
            "D143: NodePool commit failed, Phase 1 degrade mode");
    }
    // 映射 nodepool_phys 到 NodePool VMA 范围
    satp_map(nodepool_phys, NODEPOOL_VMA_BASE, 132 * 1024);
}
```

```bash
make test-d143-nodepool-commit
SIZE_PHASE0=$(stat -c%s build/kernel-phase0.elf)
SIZE_PHASE1=$(stat -c%s build/kernel-phase1.elf)
# Phase 0: NodePool section 占位 132 KB 但 ELF 物理页 0
# Phase 1+: commit 后 ELF 略大
[ "$SIZE_PHASE1" -gt "$SIZE_PHASE0" ] || { echo "D143 FAIL: Phase 1+ commit 未生效"; exit 1; }
```

**传染面**: `02-memory-topology.md` § V2.2 ledger 表增 D143 commit 行; `14-syscall-api.md` § SYS_ENOSPC 返回条件增 NodePool commit 失败路径; `15-phase0-mvp.md` T1.20 升级为 D143 + 新增 T1.28 (NodePool commit 测试); `20-documentation-gate.md` 新增禁词 "NodePool 物理页按需 lazy commit"。

---

## D151 增补 (R45 Q66, R47 撤销 R46 勘误后 — OBSOLETED): FILE_TABLE .rodata + .bss mutable_table 双结构 (恢复到自然 80B 布局)

> **R47 撤销 R46 勘误**: R46 临时将字段重排为 `{uint32 _pad0; uint64 block_index; uint8 _pad1[7]; char name[60]}` 断言 sizeof==84, 同步 D46 4KB→4.2KB。**R47 ctypes 实测反驳**: 原 `{uint32 inode; uint64 block_index; uint8 flags; char name[60]}` 自然布局 sizeof=80B (inode@0, block_index@8, flags@16, name@17, tail 填充 80), `_Static_assert(==80)` 正确; 显式 padding 版本在 align(8) 下实际 sizeof=88B, 与 R46 4.2KB 记账无一致关系。本节删除 R46 84B 形式, 恢复 80B 形式 (D151 R45 原案), D46 ledger 回滚为 4 KB。

> **R47 勘误增补立此存照**: R46 "字段自然 sizeof=84B" 系判断错误, R47 撤销; D151 在 R47 后回到 R45 默认: FILE_TABLE .rodata 自然布局 80B, 双结构 (.rodata 模板 + .bss mutable_table) 保留 (R46 双结构立法不撤销, 仅 80B 形式回归)。

> **回链**: R45 审计新增 D151, D78 FILE_TABLE .rodata 与运行时文件操作矛盾。
> **R46 勘误**: 字段 `uint32 + uint64 + uint8 + char[60]` 自然 sizeof=84B, `_Static_assert(==80)` 当场编译失败, 50×84=4200B 也破 D46 4KB 记账。修正: 断言改 84B, 同步 D46 4KB→4.2KB 台账。

### 问题与动机

- `.rodata` 编译期常量, **运行时不可写**
- file_entry_t 含 `block_index` (uint64_t), **文件操作 (open/read/write/close) 后 block_index 应改变**
- 真解法: FILE_TABLE 是 .rodata **初始模板**, 运行时文件系统维护 .bss 段的 `mutable_table[]` (与 .rodata 模板一一对应, 初始值复制)
- Spec 当前**没区分 .rodata 模板与 .bss mutable table**, 让人误以为 FILE_TABLE 不可写就不可变
- R46 勘误关键: 字段自然布局 sizeof=84B, 不是 80B; 字段重排压 80B 增加代码复杂度, 改用 84B 自然布局 + D46 台账同步

### D151 立法 (R46 勘误后)

#### 字段自然布局与 sizeof 推导

```c
// [OBSOLETED-by-R47-撤销] (R51-FIX F-3 传染失败修补):
// 原 R46 84B 自然布局与显式 padding 已被 R47 ctypes 实测反驳 (自然布局 sizeof=80B).
// 本段历史代码保留作审计档案, 不参与本仓库当前实现.
// 正确形态见下方: `file_entry_t` 自然 80B (R47 撤销裁定).
typedef struct __attribute__((deprecated)) {  // 编译期 emit warning
    uint32_t inode;          // 4B @ offset 0
    uint32_t _pad0;          // 4B @ offset 4 (对齐 uint64)
    uint64_t block_index;    // 8B @ offset 8
    uint8_t  flags;          // 1B @ offset 16
    uint8_t  _pad1[7];       // 7B @ offset 17 (对齐 8 字节)
    char     name[60];       // 60B @ offset 24
} file_entry_t_r46;         // [OBSOLETED-by-R47-撤销]: sizeof = 24 + 60 = 84B (R46 误判)
// D151 R46 ledger 4KB→4.2KB: [OBSOLETED-by-R47-撤销]
// _Static_assert(sizeof(file_entry_t_r46) == 84, "R46 误判, R47 撤销")  // 不参与本仓库当前实现
```

#### .rodata 模板 + .bss mutable_table 双结构

```c
// D151 .rodata 模板 (D78, 编译期常量, 不可写) — section 属性必须配 const 限定
extern const file_entry_t FILE_TABLE[MAX_FILES] __attribute__((section(".rodata")));
const file_entry_t FILE_TABLE[MAX_FILES] __attribute__((section(".rodata"))) = {
    // 编译期从 initrd 派生 (D105/D149)
    // ...
};

// D151 R46: .bss mutable table (运行时可变, 与 .rodata 模板 mirror)
file_entry_t mutable_table[MAX_FILES] __attribute__((section(".bss")));

// D151 初始化: .bss mutable table 复制 .rodata 模板
void file_table_init(void) {
    for (int i = 0; i < MAX_FILES; i++) {
        mutable_table[i] = FILE_TABLE[i];
    }
}

// D151 运行时文件操作: 写 mutable_table, 不写 FILE_TABLE
int neura_read(int fd, void *buf, size_t len) {
    // ... (不变) 但块索引更新写 mutable_table[fd].block_index
    if (new_block_index != mutable_table[fd].block_index) {
        mutable_table[fd].block_index = new_block_index;  // D151: 写 .bss
    }
    return len;
}
```

#### D46 ledger 同步 (4KB → 4.2KB)  [OBSOLETED-by-R47]

| 项目 | 旧 (D78) | 新 (D151 R46) |
|------|----------|---------------|
| 单条 FILE_TABLE | 80B | **84B** (R46 勘误, R47 撤销) |
| 50 条 FILE_TABLE 总计 | 4 KB | **4.2 KB** |
| 段归属 | .rodata | .rodata (模板) + .bss (mutable mirror) |
| 运行时文件操作 | 写 .rodata illegal | 写 .bss mutable_table |

**D46 台账同步声明** (R46 落地): `make audit-derive-numbers` 必须将 FILE_TABLE 行的物理占用从 4KB 更新为 4.2KB, 与 D133 双轨制台账一致 (ceiling 上限仍为 4.2KB, 实测来自 D113 ELF json 管线)。

```bash
# D151 R46 编译期闸门: FILE_TABLE 段实测
make test-file-table-size
EXPECTED_FILE_TABLE_BYTES=$((50 * 84))     # D151 R46: 4200B
ACTUAL_BYTES=$(
  llvm-readelf --syms --json build/kernel.elf \
  | jq -r '.Symbols[] | select(.Name=="__file_table_start" or .Name=="__file_table_end") | .Value' \
  | paste -sd ' ' \
  | awk '{ printf "%d", $2 - $1 }'
)
[ "$ACTUAL_BYTES" -eq "$EXPECTED_FILE_TABLE_BYTES" ] || { echo "D151 R46 FAIL"; exit 1; }
# 期望: ACTUAL_BYTES == 4200 (50 × 84B)  // R46 勘误测例, R47 撤销

# D151 R46 闸门 ②: .rodata 段必须含 const 限定的 FILE_TABLE
make test-file-table-rodata
readelf -W -s build/kernel.elf | grep FILE_TABLE | grep -q "OBJECT" \
  || { echo "D151 R46 FAIL: FILE_TABLE 不是 OBJECT 类型"; exit 1; }
# 注: const 限定体现在源代码层, ELF symbol type 由 const 强制为 OBJECT
```

**场景矩阵 (4 格, 修复前后)**:

| 场景 | 修复前 (D78 现状) | 修复后 (D151 R46) |
|------|---------------------|-------------------|
| 编译期 initrd 50 文件 → FILE_TABLE .rodata | ✓ 静态, 不可变 | ✓ 同, 但 D151 明确"是初始模板" |
| 运行时 open() / read() / write() 更新 block_index | ❌ 写 .rodata illegal instruction (PTE r/o) | ✓ D151: 写 .bss 的 `mutable_table[]`, 与 .rodata 模板 mirror |
| Phase 1+ SATP 启用, FILE_TABLE PTE 仍 r/o | ✓ RISC-V PTE r-bit 强制 | ✓ 同, 但 mutable_table 在 .bss 段, PTE r/w |
| D121 SSOT whitelist 是否含 mutable_table | ❌ 没说, mutable_table 是 .bss 类型不在 SSOT 范围 | ✓ D151: mutable_table 是 file_entry_t 数组 (D121 whitelist 隐式允许) |

**新增禁词**: "FILE_TABLE 单一不可变" / "FILE_TABLE sizeof=80" / "FILE_TABLE 总计 4KB"

**传染面**: `09-memory-subsystem.md` § D151 本增补 + `14-syscall-api.md` § neura_open/read/write 改写 mutable_table + `13-build-pipeline.md` § FILE_TABLE 编译期生成 (84B 派生) + D46 台账 4KB→4.2KB + `20-documentation-gate.md` 新增禁词三条。

