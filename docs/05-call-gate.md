# 05 · Call Gate (Phase 0 S-Mode Co-Residency Stub)

**Plan section**: §五 + §1.15-1.30 (R15-R30 evolution)
**Key decisions**: D56, D62, D70, D73, D82, D92, D106
**Status**: Frozen after 6 evolution rounds (R15-R21 + R24 + R26 + R30)

---

## Overview

Phase 0 has no MMU, so Shell and Kernel share S-Mode. The Call Gate is a 5-file assembly stub that simulates a user-kernel transition without `ecall` (which would trap to M-Mode and pay a 50-100 cycle firmware tax). It is the **only** entry point from Shell into the Zig dispatcher, and is defended by 6 layers of sscratch / stack separation.

## Evolution history (audit trace)

| Round | Decision | Approach | Why it changed |
|-------|----------|----------|----------------|
| R15 | D56 | `ecall` first → cost 50-100 cycles on every syscall | D21 zero-firmware tax |
| R17 | D62 | `csrrw sp, sscratch, sp` switch | Hack — overlaps with Trap Handler |
| R20 | D70 | `csrc sstatus, SIE` before `csrrw` | Nested interrupt hazard |
| R21 | D73 | `call` to global var (NOT sscratch) | sscratch reserved for Trap Handler only |
| R24 | D82 | HLCB `in_kernel_space` AtomicBool | Defense-in-depth against D73 corner cases |
| R26 | D92 | Early Boot Stack before Hart-Local | sscratch undefined pre-DTB |
| R30 | D106 | Trap entry sscratch 二次交换 防御 | Nested interrupt double fault |

## 6-layer sscratch defense

| Layer | Decision | What it defends |
|-------|----------|-----------------|
| **1** | D56 | No `ecall` (M-Mode trap cost) |
| **2** | D62/D73 | Call Gate uses **global var** (NOT sscratch) |
| **3** | D70/D82 | Trap Handler uses sscratch; HLCB `in_kernel_space` flag tracks ownership |
| **4** | D92 | Step 0: `__early_boot_stack_top` written to sscratch before DTB |
| **5** | D92 | Step 1+: kmain refreshes sscratch to `__hart{N}_stack_top` |
| **6** | D106 | Trap entry reads sscratch, skips `csrrw` if already in kernel range |

## 5-file implementation (D56 + D62 + D73 + D82)

**R51 D153 命名锚**: Rust 侧 `cosmo_core_syscall_dispatcher.rs` 重命名为 `syscall_stubs.rs` (D129 stub asm! 块角色明示); Zig 侧 `syscall_dispatch.zig` 是 call gate 入口唯一合法名, **不改名**. 文档中裸名 `dispatcher`(无角色前缀) 视为未锚命名.

```
kernel/arch/riscv64/call_gate/
├── syscall_dispatch.zig     # Zig call gate entry (D56, 不改名)
├── syscall_stubs.rs         # Rust per-syscall stubs (D129 asm! 块, D153 重命名裁决)
├── call_gate.h              # C HAL: register convention + C-ABI assertions
├── entry_call_gate.S        # Assembly stub: call + global var
└── HLCB.zig                 # Hart-Local Control Block (D82)
```

### `entry_call_gate.S` (skeleton)

```asm
# D56 + D62 + D73: NO sscratch, NO ecall
# Use `call` to dispatcher via global function pointer

.section .text
.global cosmo_call_gate
cosmo_call_gate:
    # D82: HLCB.in_kernel_space.store(true) — see C wrapper
    la      t0, __cosmo_dispatcher_ptr
    ld      t0, 0(t0)
    jr      t0                     # R49-F1 勘误: 改回 jr t0 尾调用, 删 P3-4 错误归因
                                   #   - Phase 0 单 Hart 无上下文切换, ra 全程 = Rust 调用点
                                   #   - jr 尾调用后 dispatcher ret 直接回到 Rust 调用点, 天然可返回
                                   #   - RISC-V ABI §18.2: ra 是 caller-saved, jr 不承诺保留,
                                   #     但 Phase 0 单 Hart 下没有任何调用方会读 ra, 安全
                                   #   - Phase 1+ 多 Hart 调度介入后才需 jalr ra, t0 + context_save
                                   # P3-4 (R47 增补, 已废) 的 "原 jr t0 丢弃 ra → panic"
                                   #   系错误归因: 实测单 Hart 下 jr 不死循环, jalr+ret 才死循环
                                   #   (沙箱二 2026-07-19 O1 排障记录复现), 此处勘误归因
                                   #   (Brra1n0 再次认领: R47 注释依据事实读反)
```

### HLCB (D82)

<!-- R31 题面: superseded by P1-1 extern struct + 24B padding header. 保留供审计比对; 当下生效形态见下方 "HLCB layout — extern struct + 显式 padding (P1-1 修复)" 段。 -->
```zig
// Hart-Local Control Block: per-Hart state (R31 题面, SUPERSEDED by P1-1 extern struct)
//   - sizeof == 40B (自然布局, 无 padding header)
//   - kernel_stack_base 字段在 R31 题面中本不存在; D107 立法要求 per-Hart range check,
//     但 R31 题面无法表达 kernel_stack_base @32, 必须扩字段, 故触发 P1-1 重做布局
//   - sscratch_initialized @32 (R31 题面), P1-1 extern struct 后迁移到 @56
pub const HLCB = struct {
    hart_id: u16,
    in_kernel_space: AtomicBool,  // D82: defense-in-depth
    kernel_stack_top: [*]u8,
    user_stack_top: [*]u8,
    sscratch_initialized: AtomicBool,  // D92, @offsetOf=32 in R31; @offsetOf=56 in P1-1
};

pub var hlcb_table: [HLCB_SIZE]HLCB = undefined;
```

## Trap Handler sscratch flow (D70 + D106)

```asm
# §六 trap_entry (D106, nested interrupt defense)
trap_entry:
    csrr    t0, sscratch
    la      t1, __kernel_stack_base
    la      t2, __kernel_stack_top
    bltu    t0, t1, .L_user_mode_trap
    bgeu    t0, t2, .L_user_mode_trap

    # D106: t0 ∈ kernel range → already in kernel (nested interrupt)
    # DO NOT swap sscratch; use current sp
    j       .L_trap_push_context

.L_user_mode_trap:
    csrrw   sp, sscratch, sp     # D70: only swap on user→kernel edge
    j       .L_trap_push_context
```

## Why no `csrc sstatus, SIE` (R20-D70 superseded)

D70 originally required disabling SIE before `csrrw` to prevent the swap itself from being interrupted. D73 / D106 removed the need: Call Gate never touches sscratch, so the swap is never interruptible from Call Gate. Trap entry (the only swap site) is gated by D106's in-kernel-range check, so nested interrupts can't re-enter the swap.

## D107: per-Hart range check (Q23 R31 fix)

**Status**: **RATIFIED** (Q23 → D107, R31).

D106 uses **global** `__kernel_stack_base/__kernel_stack_top` symbols. On `num_harts > 1`, any non-zero-Hart sp falls outside the global range → false user→kernel classification → stack tearing. D107 anchors the range check to HLCB per-Hart intervals.

```asm
# §六 trap_entry (D107 R31 fix + P1-1 layout lock)
# Reads sscratch, then loads THIS Hart's kernel stack range from HLCB.
# All offsets derived from build/link.zig constants (single source of truth).
trap_entry:
    csrr    t0, sscratch
    # D99: hart_id was stashed in tp by SBI FFI in Step 0 / DTB in Step 1+
    la      t3, __hlcb_table
    slli    t4, tp, HLCB_STRIDE_SHIFT     # HLCB entry stride = 64B (P1-1 extern)
    add     t3, t3, t4
    ld      t1, HLCB_KERNEL_STACK_BASE(t3)  # offset 32
    ld      t2, HLCB_KERNEL_STACK_TOP(t3)   # offset 40
    bltu    t0, t1, .L_user_mode_trap
    bgeu    t0, t2, .L_user_mode_trap

    # t0 ∈ this Hart's kernel range → already in kernel (nested interrupt)
    # DO NOT swap sscratch; use current sp
    j       .L_trap_push_context

.L_user_mode_trap:
    csrrw   sp, sscratch, sp     # D70: only swap on user→kernel edge
    j       .L_trap_push_context
```

**HLCB layout — extern struct + 显式 padding (P1-1 修复)**:

```zig
// P1-1: 改 extern struct 锁死字段序与 offset, 与 D107 期望的 64B 一致。
// 显式 padding 在前 3 个 64-bit slots, 3 个指针字段强制 @offsetOf=32/40/48。
// asm 端常量 (HLCB_KERNEL_STACK_BASE 等) 与 comptime offsetOf 由 build/link.zig
// 共同派生 (单一真相源), 任一侧偏移变化都会在编译期被捕捉。
pub const HLCB = extern struct {
    _reserved0: [3]u64,                              // @offsetOf=0, 24B padding
    hart_id: u16,                                   // @offsetOf=24
    _reserved1: [6]u8,                              // @offsetOf=26, pad to 32
    kernel_stack_base: [*]u8,                       // @offsetOf=32 (D107)
    kernel_stack_top: [*]u8,                        // @offsetOf=40 (D107/D64)
    user_stack_top: [*]u8,                          // @offsetOf=48 (D64)
    sscratch_initialized: AtomicBool,                // @offsetOf=56 (D136)
    _pad_end: [7]u8,                                // pad to 64, align 8B

    comptime {
        assert(@sizeOf(@This()) == 64);             // P1-1 size gate
        assert(@alignOf(@This()) == 8);             // P1-1 align gate
        assert(@offsetOf(@This(), "kernel_stack_base") == 32);
        assert(@offsetOf(@This(), "kernel_stack_top") == 40);
        assert(@offsetOf(@This(), "user_stack_top") == 48);
        assert(@offsetOf(@This(), "sscratch_initialized") == 56);
    }
};

// build/link.zig (P1-1 asm 端常量派生)
pub const HLCB_STRIDE_SHIFT: u8 = 6;                 // 2^6 = 64B/HLCB entry
pub const HLCB_KERNEL_STACK_BASE = asm {
    "@offsetOf(HLCB, 'kernel_stack_base')"          // emits 32 (32 位偏移)
};
pub const HLCB_KERNEL_STACK_TOP = asm {
    "@offsetOf(HLCB, 'kernel_stack_top')"           // emits 40
};
pub const HLCB_USER_STACK_TOP = asm {
    "@offsetOf(HLCB, 'user_stack_top')"             // emits 48
};
pub const HLCB_SSCRATCH_INIT = asm {
    "@offsetOf(HLCB, 'sscratch_initialized')"       // emits 56 (P1-1 迁移; R31 题面 @32)
};
// (asm-side offsets 必须与 comptime offsetOf 在 build 时一致, 任一不匹配 = build ABORT)
```

**D107 binding (P1-1 勘误增补)**: HLCB layout 现在是 `extern struct` 锁死, 字段偏移由 `@offsetOf` 与 asm-side constant **同一组**工具派生 (build/link.zig), 杜绝 layout 与 asm 偏移再次脱节。

**Host 验证方法** (P1-1 强制):
```bash
# 1. 用 host Zig ≥0.15 (由 toolchain.lock 锁定) 跑 @offsetOf 与 @sizeOf 自检
zig run -e 'const H = @import("kernel/include/sys/abi.zig").HLCB;
           std.debug.assert(@sizeOf(H) == 64);
           std.debug.assert(@offsetOf(H, "kernel_stack_base") == 32);
           ...'

# 2. 用 llvm-readobj 验证 HLCB 段符号实际地址偏移 (D113 jq 管线, R32 升级版)
make test-hlcb-layout
actual=$(llvm-readobj --symbols --json build/kernel.elf | \
         jq -r '.[]?.[]? | select(.Name? == "hlcb_kernel_stack_base") | .Value? // empty')
[ "$actual" -eq 32 ] || { echo "P1-1 FAIL: hlcb_kernel_stack_base offset $actual ≠ 32"; exit 1; }
```

**传染面清单** (P1-1 元规则, R48 勘误增补):
- `06-boot-sequence.md` § D107 trap_entry asm 同步 (kernel_stack_base/top 偏移 32/40, 步长 64B) + D136 sscratch_initialized 同步 (偏移 56, P1-1 extern 后从 R31 题面 @32 迁移, R48 消除硬编码)
- `08-risc-v-hal.md` § HLCB 访问代码同步
- `12-scheduler.md` § Hart-Local 引用同步
- `30-open-questions.md` R37 D127/D128 段同步 (trap_entry sp 判据 + RMW 约束)
- 旧题面(natural struct, sizeof=40, kernel_stack_base@16) **保留并显式标注** `<!-- R31 题面: superseded by P1-1 extern struct + 24B padding header -->` (R48 勘误增补: 该 HTML 注释现贴于 05 § HLCB (D82) 旧题面代码块正上方, 不再仅存于本传染面自述句)

**Cost / Benefit**:

| Dimension | D106 (R30, broken multi-Hart) | D107 (R31, per-Hart HLCB) |
|-----------|-------------------------------|----------------------------|
| Trap entry overhead | 4 instr | 8 instr (~8 cycles) |
| Multi-Hart correctness | ❌ False user-mode classification | ✓ Per-Hart anchored |
| HLCB size | ~32B | 64B |
| Boot complexity | Step 1+ writes 1 symbol | Step 1+ writes 2 symbols per Hart |

**Build-time guard** (`make test-multi-hart`):

```bash
# build.zig rejects D106 path on -smp > 1
if build_options.num_harts > 1 and not build_options.d107_enabled:
    @compileError("D107 required when num_harts > 1 (Q23)");
```

**Why Option A (Q23) was chosen over B/C**:

- **Option B** (single contiguous kernel block) violates D6 16KB Hart-Local stack + D64 NUMA affinity.
- **Option C** (delete D106, rely solely on `in_kernel_space`) is functionally equivalent to A but introduces a redundant classification flag without removing the sp-range check.

## Verification (per CI gate)

- `cargo-geiger 0 unsafe` (D97)
- `check_elf_sizes.sh` 5 struct sizes (D101)
- `make test-no-a-ext` boots on RV64IMAC (D87)
- `make test-nested-trap` injects a nested timer interrupt mid-syscall (D106)

## Cross-references

- **Boot Sequence** (D92/D95/D99): provides Step 0 Early Boot Stack + Hart ID
- **HAL** (D87/D94): provides atomic primitive + sstatus access
- **Syscall API** (D55): uses Call Gate as its only entry
- **Documentation Gate** §二十.7: R21 D73 forbids Call Gate touching sscratch (see gate catalog)
