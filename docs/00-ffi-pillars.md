# 00 · FFI Pillars (D125 跨切面前置阅读层)

**Status**: Frozen; aggregated red lines, not implementation details.
**Authority**: 唯一权威红线条目源;子系统文档是实现细节的权威,互不越界。

---

## Overview

本文件聚合 R1-R36 全部 4 个 FFI/Syscall/HAL pillar 的**红线陈述** + D# 锚 + 指针,禁止复制实现细节。子系统文档中复述 pillar 红线必须回链本文件锚点,无回链视为私自立法(熔断)。

**R53 D164 回链 (Naming Taxonomy SSOT)**: 系统级命名( `Neur-Aegis` 全称 / `neura` 命名空间 / Basal / Synapse / Cortix 三组件代号 / `neura_` syscall 前缀) 的权威源是同级 0X 跨切面文档 `docs/00-naming-taxonomy.md` (D164)。本文件红线规则与命名 SSOT 互不冲突 — FFI 规则决定 *什么能跨语言传 / 怎么传*, 命名 SSOT 决定 *类型/函数叫什么 / 目录怎么摆*。子系统文档复述命名规则必须回链 `00-naming-taxonomy.md` 锚点 (D167 纪律)。

## Pillar 索引

| Pillar | 红线 | 决策锚 | 传染面 |
|--------|------|--------|--------|
| 1. ABI & FFI | D86 + D90 + D103 + D119 + D121 | `04-abi-contract.md` § 5-Layer Defense |
| 2. sys_result_t 16B a0/a1 | D86 + D101 + D119 | `14-syscall-api.md` § sys_call register convention |
| 3. sscratch + in_kernel_space | D82 + D92 + D106 + D107 | `05-call-gate.md` § sscratch 状态机 |
| 4. Graceful degradation | D21 + D32 + D38 + D67 + D80 + D87 + D94 + D104 + D118 | `08-risc-v-hal.md` § feature matrix |

## Pillar 1: ABI & FFI 红线 (D86 + D90 + D103 + D119 + D121 + **P2-1 D90 carve-out**)

### 红线陈述
1. **D86**: `sys_result_t` 严格 16B = 2×XLEN,@sizeOf == 16 编译期熔断
2. **D90**: 跨语言结构体仅 `u8/u16/u32/u64 + [u8; N]`,禁止 `Option<T>` / `enum` / 嵌套 struct
3. **D103**: 跨 FFI 签名禁 `&[u8]` (caller stack);所有内存流动锚定静态池 (BlockPool/RpcUnit) 或 VMA
4. **D119**: syscall6 6-arg 寄存器 (a0-a5) 全部约束为 XLEN 原生整型,结构体按值传永久禁止
5. **D121** (R35 补强): Phase 0 SSOT 白名单仅 5 struct — `sys_result_t` / `sys_result_payload_t` / `RpcUnit` / `NetworkFrame` / `block_t`,**白名单外类型必须手写 + 内嵌三端编译期断言块 (size/align/offset)**,两者必居其一,手写 + 无断言 = 熔断

### D90 carve-out (P2-1 豁免)
D90 主条款"禁止嵌套 struct"不变。**唯一例外**:`sys_result_payload_t` 中的 `error_pack` 分支,可声明单层、定长 (8B)、纯标量 (`u16/u16/i32`) 成员的 struct,且该 struct 必须:
- 显式 `extern`/`__attribute__((packed))` 锁死布局;
- 内嵌三端 offsetof/sizeof 断言 (compile-time 必失败则熔断);
- 总宽 8B `== sizeof(uint64_t)` (D86 16B / 2 = 8B);
- 字段名加入 D121 whitelist;
- **任何非 error_pack 的嵌套 struct 仍被永久禁止**

```c
/* D90 carve-out: error_pack 是 union 内单层 scalar-only struct, 唯一豁免 */
typedef union {
    uint64_t value;
    struct __attribute__((packed)) {
        uint16_t remote_node_id;             // 0xFFFF = local
        uint16_t subsystem_id;
        int32_t  error_code;                 // P2-2 errno always negative
    } error_pack;                            /* D89 + P2-1 carve-out */
} sys_result_payload_t;
_Static_assert(sizeof(sys_result_payload_t) == 8, "D86 + P2-1 8B payload");
_Static_assert(sizeof(((sys_result_payload_t*)0)->error_pack) == 8,
              "P2-1 error_pack carve-out 8B width"); <!-- gate-exempt: D86 -->
```

### 传染面清单
- 4-abi-contract.md: 5-Layer Defense L1 描述改写 (SSOT diff whitelist ∪ compile-time assert all)
- 5-call-gate.md: HLCB 64B 编译期断言
- 8-risc-v-hal.md: basal_atomic_cas_ptr / try_fs_lazy_init 类型签名
- 14-syscall-api.md: 17 个跨 FFI 签名 + per-syscall arity 表
- call_gate.h 等手写文件: 头部加 `/* HANDWRITTEN: tri-end asserts embedded */` marker

## Pillar 2: sys_result_t 16B a0/a1 全 Profile 命中 (D86 + D101 + D119)

### 红线陈述
1. **D86**: `sizeof(sys_result_t) == 2 * sizeof(uint64_t)` — RISC-V C ABI ≤ 2×XLEN 返回值在 a0/a1
2. **D101**: 链接后 ELF size gate 验证 16B/8B/1536B×3 五 struct
3. **D119**: per-syscall arity 表(0x00-0x3F)覆盖 Reserved 段,所有 syscall 0..6 arg,每 arg ≤ 8B

### Profile × sys_result_t 命中表
| Profile | XLEN | 2×XLEN | sys_result_t 16B | a0/a1 命中? |
|---------|------|--------|-----------------|-----------|
| RV32IMAC | 32-bit | 8B | 16B > 8B → stack-passed | **N/A — Phase 0 仅 RV64** |
| **RV64IMAC Embedded** | 64-bit | 16B | 16B = 16B ✓ | ✓ |
| **RV64GC Server** | 64-bit | 16B | 16B = 16B ✓ | ✓ |
| **RV64GC+RVV Server Phase 1+** | 64-bit | 16B | 16B = 16B ✓ | ✓ |

### 传染面清单
- 4-abi-contract.md: sys_result_t 16B red line + Zig/Rust/C 三端 _Static_assert
- 14-syscall-api.md: sys_call a0/a1 寄存器对 + per-syscall arity 表

## Pillar 3: sscratch + in_kernel_space 完整状态机 (D82 + D92 + D106 + D107)

### 红线陈述
1. **D82**: HLCB.in_kernel_space AtomicBool,SeqCst 序
2. **D92**: Step 0 `__early_boot_stack_top` → Step 1+ per-Hart `__hart{N}_kernel_stack_top`
3. **D106**: Trap entry 二次交换防御,nested interrupt skip csrrw
4. **D107**: per-Hart range 锚定 HLCB (替代 R30 废弃的全局 `__kernel_stack_base/top`)

### sscratch 状态机 + in_kernel_space 原子性
```
       sscratch 状态               in_kernel_space
       ┌─────────────────┐         ┌──────────────┐
       │ Step 0: early   │         │ Step 1+ init │
       │ Step 1+: per-Hart│        │ true on entry│
       │ range: [base,top)│        │ false on exit│
       └─────────────────┘         └──────────────┘
       转换:
       user→kernel: csrrw sp, sscratch, sp; in_kernel_space.store(true, SeqCst)
       kernel→user: sret; in_kernel_space.store(false, SeqCst)
       nested-kernel: use current sp (no swap); already true
```

### 传染面清单
- 5-call-gate.md: 6-layer sscratch defense + HLCB 64B assertion
- 6-boot-sequence.md: Step 0/1 HLCB init 顺序 (Trap 前必须完成)
- 12-scheduler.md: context_switch 只刷新当前 Hart HLCB 槽位

## Pillar 4: Graceful Degradation 8 种组合全路径 (D87 + D94 + D104 + D117 + D118)

### 红线陈述
| 组合 | A ext | Coherence | RVV | Tier | 路径 |
|------|-------|-----------|-----|------|------|
| 1 | ✓ | ✓ | ✓ | 1 | lr.d/sc.d + Lazy |
| 2 | ✓ | ✓ | ✗ | 1 | lr.d/sc.d + FS=Off |
| 3 | ✓ | ✗ | ✓ | 2 | D117 IPI timeout + Lazy |
| 4 | ✓ | ✗ | ✗ | 2 | D117 IPI timeout + FS=Off |
| 5 | ✗ | ✓ | ✓ | 3 | D87 csrc SIE + Lazy |
| 6 | ✗ | ✓ | ✗ | 3 | D87 csrc SIE + FS=Off |
| 7 | ✗ | ✗ | ✓ | 3 | D87 + Lazy (单 Hart) |
| 8 | ✗ | ✗ | ✗ | 3 | D87 + FS=Off (16KB stack, RR) |

### 关键不变量
- **D117**: IPI ACK timeout 1ms (rdtime 派生) + panic fall-through
- **D118**: FS=Off 懒切换 + trap-and-retry + 三条件消歧 (scause==illegal AND FS==Off AND 指令是 FP/RVV opcode)
- **D80**: Sstc 缺失 → SBI SetTimer fallback
- **D67**: PLIC 退役,AIA/IMSIC (D83) Phase 1+ 替代

### 传染面清单
- 8-risc-v-hal.md: feature matrix + 3-tier CAS + FS/VS Lazy
- 12-scheduler.md: context_switch FS/VS save
- 6-boot-sequence.md: Step 0 紧急栈 (D92) + UKI Loader (D100)

## 编号 00 语义 (D125 落地约束 ③)

`00-ffi-pillars.md` 定义为**跨切面前置阅读层**,目录序列语义写入 SPEC.md:
- 0X 跨切面 (00-09): pillars / overview / decisions
- 1X 子系统: (10-19) ABI/Memory/Boot/Error/Syscall
- 2X 工具与门禁: (20-29) documentation-gate / phase0-mvp

## Cross-references

- **SPEC.md** top-level summary 回链本文件 4 pillars
- **All 14 subsystem docs** 复述 pillar 红线必须回链本文件
- **20-documentation-gate.md** doc-gate 机检本文件 marker 共现

## Verification

- `make audit-pillars` — 检查 14 个 subsystem doc 是否回链 00 文件
- `make audit-status-column` — 03-design-decisions.md status 列完整性
- `make audit-derive-numbers` — SPEC.md 数字与 ledger 自动比对
