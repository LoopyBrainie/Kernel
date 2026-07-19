# 06 · Boot Sequence (entry.S + UKI Loader)

**Plan section**: §六 + §1.18-1.29 (R18-R29 evolution)
**Key decisions**: D33, D63, D76, D77, D88, D92, D95, D99, D100
**Status**: Frozen; complete Step 0/1/2 chain

---

## Overview

The boot sequence is a 3-step chain that takes the Hart from raw firmware jump to a Hart-Local-initialized S-Mode kernel: Step 0 (early, DTB-less) → Step 1 (DTB-aware) → Step 2 (Hart-Local). The entry.S must defensively validate DTB before touching `.bss` (D95 Anti-Trampling) and never expose undefined sscratch (D92 Early Boot Stack).

## Three-step boot chain

```
Firmware Jump (a0=hartid, a1=dtb_phys)
  │
  ├── Step 0 (entry.S, assembly-only, DTB-less)
  │   ├── P3-2 (R47 立法): D95 Anti-Trampling 必须先于一切内存写入 (含 .bss 清零)
  │   │   └── 否则 DTB 被 .bss 清零踩坏, R39 D134 fence rw,rw 失去屏障意义
  │   ├── D95: Anti-Trampling DTB overlap check (FIRST)
  │   ├── D95: If overlap → SBI SRST 物理停机
  │   ├── D92: Write __early_boot_stack_top to sscratch
  │   ├── D92: sp = __early_boot_stack_top
  │   ├── D136 勘误 ①: mv tp, a0 (Hart ID 前移, 在 .bss 清零之前)
  │   │   └── .bss 清零窗口内 trap 用合法 tp (R37 D128 trap_entry 依赖)
  │   ├── .bss 清零 (Anti-Trampling 通过后)
  │   └── D107/P3-1: sp = __hart_stack_base + ((hartid+1)<<SHIFT) (Hart-Local stack top)
  │
  ├── Step 1 (kmain, Zig)
  │   ├── D77: DTB 转储 (Primary Hart only, deferred to Phase B)
  │   ├── D33: 解析 memory nodes → HLCB
  │   ├── D92: csrw sscratch, __hart{N}_stack_top
  │   └── D82: hlcb.in_kernel_space.store(true)
  │
  └── Step 2 (kmain+, application ready)
      ├── D88: early_console SBI Stub → dev://uart0 切换
      ├── D76: cosmo_panic_abort available
      └── D100: UKI Loader writes Active Slot to .boot_meta
```

**P3-2 唯一顺序 (R47 增补, supersede R40 D136 fragment)**: Step 0 内禁止重排的 5 条硬序:

1. **D95 Anti-Trampling** (重叠检测 + 失败则 SBI SRST) — 必须在一切内存写入之前
2. **D92 sscratch = __early_boot_stack_top** — Trap 可达栈顶就绪
3. **D92 sp = __early_boot_stack_top** — 当前栈就绪
4. **D136 tp = a0** — Hart ID 就绪, .bss 清零窗口内 trap 用合法 tp
5. **.bss 清零** (Anti-Trampling 通过后)
6. **D107/P3-1 Hart-Local sp** — HLCB 仍未 init, 用早期全局栈顶

> **P3-2 supersedes D95 + D136 早期条文**: R37 / R40 题面版本把 Anti-Trampling 与 .bss 清零解耦叙述, 易被误读为"Anti-Trampling 仅校验后即可、.bss 清零可前移"。**R47 立法**: Anti-Trampling 是 .bss 清零的前置条件, 不允许颠倒; D136 勘误 ① (tp 前移) 也必须落在 .bss 清零之前。

## Step 0: assembly, no globals, no DTB parse

```asm
# entry.S (sketch)
.section .text.entry
.global _start
_start:
    # ==== D95: Anti-Trampling (D27 magic + total size + overlap) ====
    lw      t0, 0(a1)             # DTB magic (big-endian 0xd00dfeed)
    li      t1, 0xedfe0dd0        # little-endian encoding
    bne     t0, t1, .L_fatal_dtb_magic

    lw      t0, 4(a1)             # DTB total size (big-endian)
    # byte-swap t0 (big → little)
    ... (rev8 sequence)

    add     t1, a1, t0            # t1 = dtb_end
    la      t2, _start
    la      t3, _service_pools_end
    bgeu    a1, t3, .L_dtb_safe
    bleu    t1, t2, .L_dtb_safe
    j       .L_fatal_dtb_collision

.L_dtb_safe:
    # ==== D92: Early Boot Stack ====
    la      t0, __early_boot_stack_top
    csrw    sscratch, t0
    la      sp, __early_boot_stack_top

    # ==== .bss 清零 ====
    la      t0, __bss_start
    la      t1, __bss_end
.L_clear_bss_loop:
    bgeu    t0, t1, .L_bss_done
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       .L_clear_bss_loop
.L_bss_done:

    # ==== D99: Hart ID via OpenSBI FFI ====
    mv      tp, a0                 # a0 = hartid (OpenSBI pre-validated)

    # ==== D92 + D107: Hart-Local stack offset (use hartid, NOT time CSR) ====
    # D107 R31 fix: csrr t0, time was wrong — time changes per cycle, would give
    # random stack base. Use hartid (a0/tp) instead, restoring 644KB topology.
    # P3-1 (R47 勘误): +1 修正 off-by-one — `hartid<<SHIFT` 是区域底 (=上一 hart 的栈顶),
    # hart 0 直接越出栈池。改 `base + ((hartid+1)<<SHIFT)`,hart 0 落在 [base, base+SHIFT_SIZE),
    # hart 1 落在 [base+SHIFT_SIZE, base+2*SHIFT_SIZE),依此类推 (栈向低地址增长, 起始 sp = 栈顶)。
    mv      t0, tp                 # t0 = hartid (stable, from D99)
    addi    t0, t0, 1              # P3-1: +1, 用栈顶计算而非区域底
    andi    t0, t0, (HLCB_SIZE-1)
    slli    t0, t0, STACK_SHIFT
    la      sp, __hart_stack_base
    add     sp, sp, t0

    la      t0, kmain
    jr      t0

# ==== P3-1 HLCB_SIZE power-of-2 comptime 断言 ====
# HLCB_SIZE 必须为 2 的幂 (因 (HLCB_SIZE-1) 作 mod mask; 非 2 幂则分区越界)
# 内核构建时由 host 编译器静态校验, 在 host 端跑 sizeof/offsetof 验证 (见 P1-1 host 验证方法)
.comptime_assert_power_of_2:
    .if ((HLCB_SIZE & (HLCB_SIZE - 1)) != 0)
    .err
    .endif

# ==== D95: Fatal handlers ====
.L_fatal_dtb_magic:
    li      a7, SBI_EXT_SRST
    li      a6, SBI_SRST_SYSTEM_RESET
    li      a0, 0
    li      a1, 1                  # Reason: System Failure
    ecall
1:  j       1b

.L_fatal_dtb_collision:
    li      a7, 0x01               # Legacy SBI: Console Putchar
    li      a0, 0x58               # 'X' = Collision
    ecall
    li      a7, SBI_EXT_SRST
    li      a6, SBI_SRST_SYSTEM_RESET
    li      a0, 0
    li      a1, 2                  # Reason: Memory Violation
    ecall
2:  j       2b
```

> **D107/Q23 落地约束**: Step 0/Step 1 启动序列必须在该 Hart 任何 Trap 可能发生**之前**完成 `hlcb[hart_id].kernel_stack_base/top` 初始化。具体顺序:
> 1. Step 0: `__early_boot_stack_top` 写入 sscratch(D92 — Hart 0 启动时所有 HLCB 仍为 0)
> 2. Step 1 (kmain): `dtb.parse_memory_nodes()` 填充所有 `hlcb[i].kernel_stack_base/top` 后,才 `csrw sscratch, hlcb[hart_id].kernel_stack_top`
> 3. Step 1+ (多 Hart 启动): Secondary Hart 必须 spin-wait 至 `hlcb[hart_id].kernel_stack_base/top` 已被 Primary Hart 写入,再 `csrw sscratch`
> **违反顺序 ⇒ D107 范围检查使用 0 base/top ⇒ sp 永远落在范围外 ⇒ 错误归类 user→kernel ⇒ 栈撕裂**

## Step 1: kmain, DTB-aware

```zig
// kernel/src/kmain.zig (sketch)
pub fn kmain(hart_id: u16) void {
    // D77: Primary Hart only, deferred to Rendezvous Phase B
    if (hart_id == 0) {
        dump_dtb_to_boot_meta();  // D98: respects max_dtb_size
    }

    // D33: parse DTB memory nodes → HLCB
    dtb.parse_memory_nodes(&hlcb_table);

    // D92: refresh sscratch to Hart-Local stack
    const stack_top = hlcb_table[hart_id].kernel_stack_top;
    asm volatile ("csrw sscratch, %[t]"
        : : [t] "r" (@intFromPtr(stack_top)));

    // D82: defense-in-depth
    hlcb_table[hart_id].in_kernel_space.store(true, .SeqCst);

    // D88: switch from SBI Stub to dev://uart0
    early_console_init();
    uart0_init();
}
```

## Step 2: application ready

| Subsystem | Decision | When ready |
|-----------|----------|------------|
| `cosmo_panic_abort` | D76 | Immediately after D88 |
| `dev://uart0` | D25 | After D88 |
| Scheme Router | D9.2 | After HLCB ready |
| UKI Loader → boot_meta | D100 | Pre-kernel jump |

## UKI Loader (D100)

~2 KB hand-written ELF Program Header scanner (no libelf). Locates `__boot_meta_start` symbol's PT_LOAD segment, writes `BOOT_META_MAGIC + slot_id` to that offset. Cures D63 DTB decoupling + D49 elastic layout.

## D116: Trap Handler ex_table 二分查找 (R33 落锤)

```c
// §六 entry.S D116 异常修复桩 (R33 落锤 + R44 D148 修正 + P2-2 EFAULT = -14)
//! D116: Trap Handler 在 Page Fault (scause=13/15) 时, 二分查找 sepc 是否在
//! __ex_table 中. 命中 → 修改 Saved Context (sepc = fixup, 强制清零 SUM=0),
//! 注入 EFAULT (D89 错误码 -14, P2-2 错误码恒负立法) 至 a0/a1 (D86 16B 兼容).
//! D148: 嵌套 fixup 路径泛化为 "S-Mode fault + SUM=0 ⇒ 致命" — 若进入修复桩时
//! sstatus.SUM 已经是 0 (上一轮 fixup 已被强制清零却再次触发), 直接 panic.
.global cosmo_do_user_fault_fixup
cosmo_do_user_fault_fixup:
    // a0 = current_task_context_ptr, a1 = target_fixup_address
    ld      t0, CONTEXT_SSTATUS_OFFSET(a0)
    li      t1, (1 << 18)                       // SSTATUS_SUM
    and     t2, t0, t1                          // D148: SUM 状态机检测
    beqz    t2, .L_nested_fixup_fatal            // D148: SUM=0 ⇒ 二次 fixup ⇒ panic

    sd      a1, CONTEXT_SEPC_OFFSET(a0)         // 重定向 sepc 至 fixup
    li      t1, ~(1 << 18)                      // SSTATUS_SUM Mask (D115)
    and     t0, t0, t1                          // 强制清零 SUM
    sd      t0, CONTEXT_SSTATUS_OFFSET(a0)      // 物理覆写, 通道闭合
    // P2-2 错误码恒负: SYS_EFAULT = -14 (POSIX-compatible errno)
    li      t2, -14                             // SYS_EFAULT = -14 (D89 + P2-2)
    sd      t2, CONTEXT_A0_OFFSET(a0)           // sys_result_t.header.payload.error_pack.error_code = -14
    li      t3, -1
    sd      t3, CONTEXT_A1_OFFSET(a0)           // sys_result_t.payload.value = -1
    ret

.L_nested_fixup_fatal:
    // D148: SUM=0 二次 fixup, 触发 panic 路径 (D139)
    // 这是 fail-safe 防御: 任何 SUM=0 上 Page Fault 必非合规路径
    j       cosmo_oops_panic
```

**R44 D148 立法注**: SUM-state-machine 单触发语义 — 每次 Page Fault 必须**先**触发 fixup,**fixup 内部**强制清 SUM;若再次 Page Fault 且 SUM=0, 表明 fixup 嵌套或 SUM 清零漏判, **直接 panic 不再尝试 fixup**。这是 fail-fast 防御, 避免死循环 drain 内存。

// §六 entry.S trap_handler (D116 二分查找, R33 落锤)
.global trap_handler
trap_handler:
    // ... [D106] sscratch 二次交换与防御判定 ...
    csrr    t0, scause
    li      t1, 13                              // Load Page Fault
    beq     t0, t1, .L_check_extable
    li      t1, 15                              // Store Page Fault
    beq     t0, t1, .L_check_extable
    j       .L_normal_trap                       // 非 Page Fault, 走常规

.L_check_extable:
    // D116 + D112 R32 fix: 二分查找 __ex_table,统一用 ld (8B)
    csrr    t0, sepc
    la      t1, __ex_table_start
    la      t2, __ex_table_end
.L_extable_binary_search:
    bgeu    t1, t2, .L_extable_miss             // 未命中
    add     t3, t1, t2
    srli    t3, t3, 1
    andi    t3, t3, ~7                          // D112: 8B 对齐 (entry 半步)
    ld      t4, 0(t3)                           // D112: insn  (8B) 替代 lwu (4B)
    bne     t0, t4, .L_extable_continue
    ld      t5, 8(t3)                           // D112: fixup (8B) 替代 lwu (4B 错位)
    mv      a0, sp                              // current_task_context_ptr
    mv      a1, t5                              // fixup address
    call    cosmo_do_user_fault_fixup
    sret                                        // 返回修复点
.L_extable_continue:
    bltu    t0, t4, .L_extable_low
    addi    t1, t3, 16                          // D112: entry size = 16B,步进 16B
    j       .L_extable_binary_search
.L_extable_low:
    mv      t2, t3                              // 搜索左半
    j       .L_extable_binary_search
.L_extable_miss:
    j       .L_normal_trap                       // 未命中, 走 Panic (D76)

.L_normal_trap:
    // ... 常规 Trap Handler ...
```

**D115 + D116 协同**: 异常修复时强制清零 SUM (D115), 防止后续清理流二次嵌套异常导致特权蔓延.

## Cross-references

- **Call Gate** (05): D92 Early Boot Stack feeds sscratch
- **Memory Subsystem** (09): D29/D31/D61 .boot_meta placement
- **HAL** (08): D88 Early Console SBI Stub + D99 OpenSBI Hart ID FFI + D115 SUM + D116 ex_table
- **Scheduler** (12): D106 trap_entry sscratch 二次交换防御
- **Documentation Gate** §二十.7: see gate catalog for forbidden phrases (R12-R34, 70 项)

## Verification

- `make test-dtb-corruption` — inject 1-byte DTB error → SBI SRST halt
- `make test-multi-hart` — QEMU `-smp 4` boots 4 harts without deadlock
- `make test-no-a-ext` — RV64IMAC, no `csrr mhartid` (D99)
- `make test-efault-injection` — inject 0x0DEADBEEF U-Mode 指针, 断言 SYS_EFAULT
- `make check-extable-alignment` — 静态编译期硬闸门, .fixup 段 4 字节对齐

---

## D132 增补 (R39 Q47, 勘误后): ex_table .balign 3 + .quad + 二分查找 ~0xF 掩码

> **回链**: R39 审计新增 D132, 修复 D112 (R32) "改 ld 8B 未同步改 .balign" 的未受审语义。

### 问题与动机

R32 D112 把二分查找的 `lwu` (4B) 改为 `ld` (8B), 但 `.fixup` 段仍用 `.balign 4` + `.long` (4B)。ld 需 8B 自然对齐, .balign 4 只保证 4B 对齐, 段首可能落在奇数 4B 边界 → ld 触发 misaligned exception。

**二分查找同级 bug**: entry 是 16B (insn 8B + fixup 8B), 但原 `andi t3, t3, ~7` 是 8B 对齐, 中点可能落在某 entry 的 fixup 字段上 (entry 后半), 把 fixup 当 insn 比较。

### D132 立法

1. `.fixup` 段改 `.balign 3` + `.quad` (强制 8B 对齐)
2. 二分查找中点改 `~0xF` (16B 对齐, 保证落在 entry insn 字段起点)
3. 对齐闸门改用 `llvm-readelf --json + jq` 管线 (Q28 D113 已立法, 禁 awk 列位解析)

```asm
# 06-boot-sequence.md § D116 Trap Handler 二分查找 (D132 升级, 勘误后)
.section .fixup, "ax"
    .balign 3                    # D132: 8B 对齐 (替代 .balign 4)
    .quad   1b, 2b               # D132: 用 .quad (8B) 替代 .long, 强制 entry 8B 对齐
.previous

.L_extable_binary_search:
    bgeu    t1, t2, .L_extable_miss
    add     t3, t1, t2
    srli    t3, t3, 1
    andi    t3, t3, ~0xF          # D132 勘误: 16B 对齐 (entry 起点), 替代 ~7
    ld      t4, 0(t3)             # D112: insn  (8B)
    bne     t0, t4, .L_extable_continue
    ld      t5, 8(t3)             # D112: fixup (8B)
    ...
```

```bash
# D132 编译期闸门: readelf --json + jq 验证段对齐
make test-extable-alignment
ALIGN=$(llvm-readelf --section-headers --json build/kernel.elf \
       | jq -r '.[] | select(.Name=="__ex_table" or .Name==".fixup") | .Addr % 8')
[ -z "$ALIGN" ] || [ "$ALIGN" = "0" ] || { echo "D132 FAIL"; exit 1; }
```

---

## D134 增补 (R39 Q49, 勘误后): UKI Loader 段内偏移写入 + fence rw,rw

> **回链**: R39 审计新增 D134, UKI Loader ELF Program Header 段查找机制 + 写入地址 + fence 类型三处勘误。

### 问题与动机

R39 Q49 题面代码写 `phdr[idx].p_paddr` 直接踩段首 16B——那是段物理基址, 不是 `__boot_meta_start` 在段内偏移。题面场景矩阵第 4 行自己写的 "segment 起点 + __boot_meta_magic_offset" 但代码漏了偏移。fence.i 是指令自取 fence (self-modifying code), 不管数据写的跨 Hart 可见性, 应该用 fence rw,rw。

### D134 立法

1. 写入地址 = `p_paddr + (V - p_vaddr)`, 其中 V = `__boot_meta_start` 符号值
2. 数据写入后 `fence rw, rw` (Phase 0 Hart 0 独占写靠启动顺序, Phase 1+ 多 Hart 用 SBI RFENCE)
3. 段序闸门用 `readelf --json + jq`, 禁 awk 列位解析

```c
// kernel/boot/uki_loader.c (D134 完整实现, 勘误后)
void uki_loader_run(const Elf64_Ehdr *ehdr, uintptr_t boot_meta_vaddr, uint32_t slot_id) {
    int idx = find_boot_meta_phdr(ehdr, boot_meta_vaddr);
    const Elf64_Phdr *phdr = (const Elf64_Phdr *)((uintptr_t)ehdr + ehdr->e_phoff);
    // D134 勘误 ①: 写入地址 = 段物理基址 + (V - 段虚拟基址)
    uintptr_t seg_phys   = phdr[idx].p_paddr;
    uintptr_t seg_virt   = phdr[idx].p_vaddr;
    uintptr_t write_phys = seg_phys + (boot_meta_vaddr - seg_virt);
    volatile boot_meta_header_t *bm = (volatile boot_meta_header_t *)write_phys;
    bm->magic    = BOOT_META_MAGIC;
    bm->slot_id  = slot_id & BOOT_META_SLOT_MASK;
    bm->reserved = 0;
    // D134 勘误 ②: 数据写入用 fence rw,rw (fence.i 是指令自取, 不管数据)
    asm volatile ("fence rw, rw" ::: "memory");
    // Phase 0: Hart 0 独占写, Hart 1+ spin-wait HLCB.inited
    // Phase 1+: 多 Hart 启动顺序, 写完后再启动 Hart 1+, 或用 SBI RFENCE
}
```

```bash
# D134 段序闸门: __boot_meta 所在 PT_LOAD 必须是末位
make test-uki-loader-segment-order
PHDR_INFO=$(llvm-readelf --program-headers --json build/kernel.elf \
            | jq -r '.[].[] | select(.type=="PT_LOAD") | .vaddr + " " + (.memsz|tostring)')
LAST_PHDR=$(echo "$PHDR_INFO" | tail -1)
BOOT_META_VADDR=$(llvm-readelf --symbols --json build/kernel.elf \
                  | jq -r '.[] | select(.Name=="__boot_meta_start") | .Value')
[ -n "$(echo "$LAST_PHDR" | awk -v v=$BOOT_META_VADDR '$1 <= v && v < $1 + $2')" ] \
  || { echo "D134 FAIL: __boot_meta not in last PT_LOAD"; exit 1; }
```

---

## D136 增补 (R40 Q51, 勘误后): Step 0 HLCB 盲区防御 — tp 前移 + SBI SRST reason

> **回链**: R40 审计新增 D136, R37 D128 (sp 判据) 对 Step 0 HLCB 未初始化的盲区防御。

### 问题与动机

R37 D128 trap_entry 用 `slli t4, tp, 6` 索引 HLCB, 但 Step 0 期间 HLCB 仍为 0 (Step 1 kmain 才 init)。两个勘误:

1. **题面 Step 0 序列是 ".bss 清零 → mv tp, a0"**: tp 在 .bss 清零之后才设置, 清零窗口内 trap 触发用垃圾 tp 读到随机内存。修正: `mv tp, a0` 前移到 sscratch/sp 设置之后立即执行。
2. **SBI SRST 参数语义错**: 原代码 `a0=0, a1=3`, 但 reason=3 不在规范内。RISC-V SBI v2.0 §9.4 "System Reset Extension" 定义 `a0=reset_type (0=shutdown/1=cold/2=warm), a1=reason (0=none/1=system failure)`。修正为 `a0=0, a1=1`。

### D136 立法

```c
// trap_entry (D136 升级, R48 勘误增补: 命名常量同源派生)
//   R47 bug: 原 trap_entry 用裸偏移数读 sscratch_initialized, 实际命中 hart_id:u16
//   (offset 24), Hart 0 的 hart_id=0 → beqz 恒真 → 首 trap 必 panic (.L_step0_trap).
//   R48 修复: 偏移统一由 build/link.zig asm-side 常量派生,
//   与 05 extern struct comptime @offsetOf 同源 (D107 size gate + P1-1 layout).
trap_entry:
    // D136: Step 0 盲区防御, 先检查 HLCB 是否初始化
    la      t3, __hlcb_table
    slli    t4, tp, HLCB_STRIDE_SHIFT       # HLCB 64B stride (P1-1, 2^SHIFT)
    add     t3, t3, t4
    lb      t5, HLCB_SSCRATCH_INIT(t3)      # sscratch_initialized @56 (P1-1; R31 题面 @32)
    beqz    t5, .L_step0_trap               # D136: 未初始化 → SBI SRST halt

    // D128 (R37): 判据回归 sp
    mv      t0, sp
    ld      t1, HLCB_KERNEL_STACK_BASE(t3)  # @offsetOf=32 (D107)
    ld      t2, HLCB_KERNEL_STACK_TOP(t3)   # @offsetOf=40 (D107/D64)
    bltu    t0, t1, .L_user_mode_trap
    bgeu    t0, t2, .L_user_mode_trap
    j       .L_trap_push_context

.L_user_mode_trap:
    csrrw   sp, sscratch, sp
    j       .L_trap_push_context

.L_step0_trap:
    // D136 勘误 ②: SBI SRST 参数语义 (RISC-V SBI v2.0 §9.4)
    //   a0 = reset type: 0=shutdown / 1=cold reboot / 2=warm reboot
    //   a1 = reason:     0=none / 1=system failure
    li      a7, SBI_EXT_SRST
    li      a6, SBI_SRST_SYSTEM_RESET
    li      a0, 0                        // reset_type = shutdown
    li      a1, 1                        // reason = system failure
    ecall
1:  j      1b
```

```c
// Step 0 entry.S (D136 勘误 ①: tp 前移到 sscratch/sp 设置之后)
_start:
    la      t0, __early_boot_stack_top
    csrw    sscratch, t0
    la      sp, __early_boot_stack_top

    // D99 + D136: tp = Hart ID 前移到任何 trap 可达点之前
    mv      tp, a0

    // .bss 清零 (在 tp 设置之后, 即使 .bss 清零 trap 也用合法 tp)
    la      t0, __bss_start
    la      t1, __bss_end
.L_clear_bss_loop:
    bgeu    t0, t1, .L_bss_done
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       .L_clear_bss_loop
.L_bss_done:
    // ... 后续 DTB Anti-Trampling 等
```

**Q51 支持论据**: Option C (Step 0 屏蔽 SIE) 结构上不可能充分——SIE 只屏蔽异步中断, 屏蔽不了同步异常 (illegal instruction / load fault)。Step 0 trap 防御必须有 handler 路径, Option A 是唯一完整解。

---

## D137 增补 (R40 Q52, 集成约束补强): PLIC 退役 + trap_handler 显式路径 + UART IER=0 断言

> **回链**: R40 审计新增 D137, D67 PLIC 退役不完整, 外部中断 trap handler 死循环防御。

### 问题与动机

D67 "no driver + unmap DTB + silently ignored" 三不相容——DTB unmap 不碰硬件, PLIC pending 由硬件事件驱动, "silently" 在物理上不存在。

**集成约束 (R40 补强)**: QEMU virt 16550 UART0 只有 IER 置位才拉中断线——dev://uart0 轮询驱动必须断言 `IER=0`, 否则用户第一次按键就触发 D137 panic, Shell 直接不可用。同理题面测试用例 (echo "X" | qemu) 在 IER=0 下不会触发任何中断, 测试 harness 必须显式置 IER 才能验证 panic 路径。

### D137 立法

```c
// trap_handler (D137 升级, 勘误后: 删除原题面 andi t0, ~(1<<8) 自我纠结段)
trap_handler:
    csrr    t0, scause
    li      t1, 8                              # External Interrupt (PLIC via SEIP)
    beq     t0, t1, .L_external_ignored
    li      t1, 13                             # Load Page Fault
    beq     t0, t1, .L_check_extable
    li      t1, 15                             # Store Page Fault
    beq     t0, t1, .L_check_extable
    j       .L_normal_trap

.L_external_ignored:
    // D137: 清 sie.SEIE (bit 9, RISC-V Privileged Spec §3.1.9)
    li      t0, ~(1 << 9)
    csrc    sie, t0
    csrr    a0, scause
    csrr    a1, stval
    cosmo_panic_abort_fmt(__FILE__, __LINE__,
        "D137 FAIL: PLIC IRQ pending (scause=%ld stval=0x%lx) but no driver. \
         Implement Phase 1 IMSIC (D32/D83).", a0, a1)
    j       .L_normal_trap
```

```c
// D137 集成约束: dev://uart0 (D25) 初始化时强制 IER=0
void uart0_init(void) {
    volatile uint32_t *uart0 = (volatile uint32_t *)0x10000000;
    uart0[1] = 0x00;  // IER = 0, 禁止所有中断 (D137 集成约束)
    // ... 波特率 / LCR / FCR 配置
    uart0[3] = 0x80;  uart0[0] = 0x01;  uart0[1] = 0x00;  uart0[3] = 0x03;
    uart0[2] = 0x07;  // FCR: enable + clear FIFO
}
```

```bash
# D137 测试用例: 测试 harness 必须显式置 IER 才能验证 panic 路径
make test-plic-no-driver
qemu-system-riscv64 -machine virt -cpu rv64 -kernel kernel.elf -nographic \
    -device 16550a,chardev=uart0 -chardev socket,id=uart0,path=/tmp/uart.sock &
# Harness 显式写 UART0 IER 置位 (D137 集成约束, 写在 T1.23 DoD)
python3 -c "import socket,time; s=socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); \
  s.connect('/tmp/uart.sock'); time.sleep(1); s.send(b'X'); time.sleep(2)"
# 期望: kernel 1ms 内输出 D137 FAIL panic, 而非无限 trap
# 注: 不显式置 IER=1 不会触发任何中断 (IER=0), 测试必须显式置
```

---

## D141 增补 (R42 Q56): Hart ID 来源机制 — SBI HSM fallback

> **回链**: R42 审计新增 D141, D99 "S-Mode Hart ID via OpenSBI FFI" 在 `-bios none` 直启模式下契约失效的防御。

### 问题与动机

D99 `_start: mv tp, a0` 假设 OpenSBI 标准引导, a0 = Hart ID。但在 `-bios none` 或 Allwinner D1s BROM 直启模式下, a0 内容未定义 (QEMU 可能是 0, BROM 可能是任意值)。`csrr mhartid` 在 S-Mode 是 illegal (Privileged Spec §3.1.6.1)。

### D141 立法

D99 拆为两路: (1) `_start: mv tp, a0` 保留快速路径; (2) `cosmo_get_hart_id(a0_hint)` 探测 SBI HSM 扩展, 支持则 `sbi_hart_get_id`, 否则信任 a0。

```c
// kernel/hal/riscv/hart_id.c (D141 完整实现)
#include <sbi.h>

uint32_t cosmo_get_hart_id(uint32_t a0_hint) {
    if (sbi_probe_extension(SBI_EXT_HSM) > 0) {  // 0x48534D = 'HSM'
        register uintptr_t hart_id asm("a0");
        register uintptr_t err asm("a1");
        asm volatile (
            "li a7, 0x48534D\n"      // SBI_EXT_HSM
            "li a6, 0\n"              // SBI_HSM_HART_GET_ID
            "ecall"
            : "=r"(hart_id), "=r"(err)
            :
            : "memory"
        );
        if (err == 0) return (uint32_t)hart_id;
    }
    return a0_hint;  // fast-path fallback
}
```

```bash
make test-d141-boot-modes
for bios in default none; do
    qemu-system-riscv64 -machine virt -cpu rv64 -smp 4 -bios $bios -kernel kernel.elf -nographic &
    # 验证 4 Hart 启动, Hart ID 与 QEMU -smp 一致
done
# 期望 2/2 PASS
```

**传染面**: `08-risc-v-hal.md` Hart ID 章节加 D141 SBI HSM 实现; `15-phase0-mvp.md` T1.5 升级为 D141 + 新增 T1.27 (bios=none 测试); `20-documentation-gate.md` 新增禁词 "Hart ID 假定 a0"。

---

## D141 增补 (R42 Q56, R46 勘误后): Hart ID — a0 权威 + DTB 校验 + park 路由

> **回链**: R42 审计新增 D141 Hart ID 来源机制。**R46 勘误** (元规则七第二次触发): SBI HSM 无 `hart_get_id` 函数 (HSM fid 0 是 `hart_start`), 题面原机制杜撰且高危。

### R46 机制重写 (依据 SBI 规范正解)

1. **a0 在所有 SBI 介入路径下本就权威** — HSM `hart_start` 契约规定被启动 Hart 以 `a0=hartid, a1=opaque` 进入 S-Mode。OpenSBI 引导与 QEMU `-kernel` (含 `-bios none`) 同样遵守 RISC-V boot protocol
2. **D141 正身是校验** (而非 "换来源"): `a0 < num_harts(DTB)` 运行时断言, 违例即 D139 panic
3. **`-bios none` 多 Hart 同启**: 非 boot Hart 路由至 **park 循环** (SBI HSM `sbi_hart_start` 启动后等待 Hart 0 完成 Step 0–1 再唤醒)
4. **真正无 SBI 的 BROM 直启** (Allwinner 类): hartid 来源定义为 **platform boot protocol 文档项**, 逐平台登记, 禁止以探测 SBI 扩展的方式兜底

```c
// kernel/hal/riscv/hart_id.c (D141 R46 勘误后)
#include <sbi.h>

uint32_t cosmo_get_hart_id(uint32_t a0_hint) {
    // R46: a0 是权威来源, 不探测 SBI HSM (HSM 无 get_id)
    // D141 正身: 运行时断言 a0 < num_harts(DTB)
    uint32_t num_harts = dtb_get_num_harts();
    if (a0_hint >= num_harts) {
        cosmo_panic_abort_fmt(__FILE__, __LINE__,
            "D141 FAIL: Hart ID %u >= num_harts %u (DTB)", a0_hint, num_harts);
    }
    return a0_hint;
}

// D141 -bios none 多 Hart 同启: 非 boot Hart 路由 park 循环
void cosmo_park_until_hart0_done(uint32_t my_hart_id) {
    if (my_hart_id == 0) return;  // Hart 0 不 park
    while (!hlcb_table[0].sscratch_initialized.load(SeqCst)) {
        wfi();  // 等 Hart 0 完成 Step 0–1
    }
}
```

**R46 新增禁词**: "SBI HSM hart_get_id" / "Hart ID 探测 SBI 兜底" / "Hart ID a0 不可信时探测 SBI"

**传染面**: `08-risc-v-hal.md` § D141 加 platform boot protocol 表占位 (BROM 直启逐平台登记); `15-phase0-mvp.md` T1.5 升级 + 新增 T1.27 (Hart ID DTB 校验测试); `20-documentation-gate.md` 新增上述禁词。


---

## D147 增补 (R44 Q62, R46 勘误后): fence.i 启动期单条 + 链接期 W^X 闸门

> **回链**: R44 审计新增 D147, D66 "Phase 0 fence.i = 1 global" 语义。**R46 勘误**: fence.i 是非特权指令 (U-Mode 可执行), 闸门改链接期 W^X 校验。

### R46 修正

1. **fence.i 是非特权指令**, U-Mode 可以执行。R46 题面 "U-Mode 不允许 fence.i (S-Mode CSR)" 把它当 CSR 了 — **手册章节读反**
2. 用户态自修改代码的真正拦截器是 **W^X 页权限** (无 WX 用户页), 不是 fence.i 特权级
3. 无条件 `@compileError` 会让每次 build 都熔断, 自修改代码是运行时行为, comptime 检测不了
4. **修正**: 闸门改为链接期 W^X 校验 (走 D113 json 管线查 PT_LOAD, 存在 WX 段即熔断)

```asm
# _start (D147 R46 勘误后, fence.i 是非特权)
_start:
    fence.i                       # D147: 启动期 1 条, I-cache sync, 非特权指令
    # ... 后续 sscratch/sp/tp/.bss 清零
```

```bash
# D147 链接期 W^X 闸门 (替代原 comptime @compileError)
make test-no-wx-page
# 走 D113 --json 管线, 查 PT_LOAD 段是否有 W+X 同时置位
WARN=$(llvm-readelf --program-headers --json build/kernel.elf \
       | jq -r '.[] | select(.type=="PT_LOAD") | select(.flags.W==true and .flags.X==true) | .vaddr')
[ -z "$WARN" ] || { echo "D147 FAIL: PT_LOAD 段存在 W+X (W^X violation): $WARN"; exit 1; }
# 期望: 空输出 (kernel 段都是 R+X 或 R-only .rodata, 无 WX)
```

**R46 新增禁词**: "fence.i 是 S-Mode CSR" / "fence.i 用户态拦截" / "comptime W^X 校验"

**传染面**: `20-documentation-gate.md` 新增上述禁词。

