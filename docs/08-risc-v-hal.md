# 08 · RISC-V HAL (Hardware Abstraction Layer)

**Plan section**: §八
**Key decisions**: D21, D32, D38, D67, D80, D83, D87, D94, D104
**Status**: Frozen; multi-tier fallbacks locked

---

## Overview

The RISC-V HAL provides a uniform interface to hardware features that vary across the embedded ↔ server spectrum. Each feature has a 2-3 tier fallback so that a single binary runs on Allwinner D1s (RV64IMAC) and SiFive HiFive Unmatched (RV64GC) without recompilation.

**R53 D166 回链 (basal_ 分批范式)**: 本节涉及 C HAL `cosmo_*` 前缀向 `basal_*` 的迁移 (R54 panic 族 / R55 call_gate 族 / R56 hal_ 族 / R57 ABI 过滤 / R59 basal_node_id), 共 23 个符号分 5 批迁移, 每批独立 R## 收口全量门禁, 单批变更不得跨多个 D# 撤销 (D166 范式)。详见 `docs/00-naming-taxonomy.md` § 4 (D166 basal_ 分批迁移范式)。

## Feature matrix and fallback tiers

| Feature | Tier 1 (Server) | Tier 2 (Embedded) | Tier 3 (Fallback) | Decision |
|---------|-----------------|-------------------|-------------------|----------|
| **Clock** | `csrr time` (D21) | `csrr time` (D21) | SBI ecall legacy | D21 + D80 |
| **Timer interrupt** | Sstc `stimecmp` (D80) | SBI SetTimer | SBI SetTimer | D80 |
| **Atomic CAS** | `lr.d / sc.d` (D9.2) | `csrc sstatus, SIE` (D94) | `csrc sstatus, SIE` (D87) | D9.2 + D87 + D94 |
| **Cross-Hart IPI** | AIA IMSIC MSI (D83) | SBI IPI | SBI IPI (single Hart if no multi) | D32 + D38 + D83 |
| **PLIC** | D67 retired (no driver) | D67 retired | D67 retired | D67 |
| **A extension** | Native `lr/sc` | Soft fallback (D87) | Soft fallback | D87 |
| **F/D extension** | `csrr fcsr` (D104 Lazy) | Disabled | Disabled | D20 + D104 |
| **V extension** | `csrr vcsr` (D104 Lazy) | Disabled | Disabled | D14 + D104 |

## D21: zero-firmware-tax clock

```c
// Read time without SBI ecall (50-100 cycle tax)
static inline uint64_t cosmo_read_time(void) {
    uint64_t t;
    asm volatile ("csrr %0, time" : "=r"(t));
    return t;
}
```

Used for: scheduler tick, timestamp fields in RpcUnit, performance counters. Always Tier 1 on any RISC-V Hart with the `time` CSR (which is standard in all profiles).

## D80: Sstc detection + SBI fallback (P1-4 S-Mode 勘误后)

**P1-4 修复**: `csrr menvcfg` 在 S-Mode 是 **illegal instruction** (RISC-V Privileged Spec §3.1.7: menvcfg 是 M-Mode CSR, S-Mode 读它必然 trap; senvcfg 不含 STCE 位, 无法代理)。R36 D80 原案直接 exec 会 `IllegalInstruction` 然后 D118 三条件消歧误判。

**新 D80**: 通过 DTB `riscv,isa-extensions` 解析 "sstc" 字符串; 或 trap-and-probe 写 `stimecmp` (写入成功 = Sstc 可用, 写入 trap = 降级)。`menvcfg` 字面量列入禁词门 (R29 同款反杜撰)。

```c
// Probe Sstc extension at boot (P1-4: 禁 menvcfg 读)
static bool has_sstc = false;

void cosmo_hal_clock_init(void) {
    // 路径 1: DTB 解析 (M-Mode OpenSBI 通常已写 riscv,isa-extensions 节点)
    has_sstc = dtb_has_isa_extension(dtb, "sstc");

    // 路径 2 (fallback): trap-and-probe 写 stimecmp — 写入成功 = Sstc 可用
    if (!has_sstc) {
        uint64_t probe_deadline = cosmo_read_time() + 1;  // 1 tick 触发未来中断
        sbi_set_timer(probe_deadline);  // 先 SBI 写入防丢失
        uint64_t before = cosmo_read_time();
        asm volatile ("csrw stimecmp, %0" : : "r"(probe_deadline));   // 如 trap 走 D118/三条件
        // 若未 trap, Sstc 可用, has_sstc = true
        // 注: OpenSBI 默认 medeleg 不会拦截 illegal instruction (拦截需显式设 bit)
        //     写 stimecmp 在 S-Mode 下 Sstc 可用时是合法的
        if (cosmo_read_time() >= probe_deadline || /* 写未 trap */ 1) {
            has_sstc = true;
        }
    }

    if (!has_sstc) {
        sbi_set_timer(cosmo_read_time() + TICK_INTERVAL);  // SBI 降级
    }
}

void cosmo_hal_set_next_timer(uint64_t next_deadline) {
    if (has_sstc) {
        asm volatile ("csrw stimecmp, %0" : : "r"(next_deadline));
    } else {
        sbi_set_timer(next_deadline);
    }
}
```

**P1-4 测例** (替代 R36 无脑 menvcfg 测):
- `make test-no-sstc` — QEMU `-cpu rv64,no-sstc` 启动, 验证 SBI 降级路径使用
- `make test-sstc-via-dtb` — QEMU `-dtb /path/fdt-with-sstc.dtb` 启动, 验证 DTB 路径
- `make test-trap-probe` — QEMU Sstc 未启用, 验证 trap-and-probe 失败 → SBI 降级

## D94 + D108: 3-tier atomic fallback

```c
// HAL-level atomic CAS for service hot-reload
// D9.2 + D94: Tier 1 (server, has A + cross-Hart Coherence)
// D94 + D108 R31 fix: Tier 2 (has A but no cross-Hart Coherence) MUST use SBI IPI
// D87 Tier 3: no A extension → soft fallback
static inline bool cosmo_atomic_cas_ptr(
    void **dest, void *old_val, void *new_val, hart_mask_t peer_mask)
{
    if (has_a_extension && has_global_coherence) {
        // Tier 1: native lr.d / sc.d (D9.2)
        void *cur;
        asm volatile (
            "1: lr.d  %0, (%2)\n"
            "   bne    %0, %3, 2f\n"
            "   sc.d   t0, %4, (%2)\n"
            "   bnez    t0, 1b\n"
            "2:"
            : "=&r"(cur)
            : "r"(cur), "r"(dest), "r"(old_val), "r"(new_val)
            : "t0", "memory"
        );
        return cur == old_val;
    } else if (has_a_extension && !has_global_coherence) {
        // D108 R31 fix: Tier 2 MUST pair csrc sstatus, SIE with SBI IPI sync.
        // Single-Hart SIE disable cannot block remote Hart writes.
        if (!has_ipi_capability) {
            cosmo_panic_abort("Tier 2 requires SBI IPI (D108)");
        }
        register_t prev = csr_read_clear(sstatus, SSTATUS_SIE);
        sbi_send_ipi(peer_mask);                          // notify peer Harts
        while (!ipi_acked(peer_mask)) { }                  // wait for ACK
        bool match = (*dest == old_val);
        if (match) *dest = new_val;
        csr_write(sstatus, prev);
        ipi_release(peer_mask);
        return match;
    } else {
        // D87 Tier 3: no A extension, single Hart soft critical section
        register_t prev = csr_read_clear(sstatus, SSTATUS_SIE);
        bool match = (*dest == old_val);
        if (match) *dest = new_val;
        csr_write(sstatus, prev);
        return match;
    }
}
```

## D104: FS/VS Lazy Save

```c
// Read current sstatus to check dirty bits
// FS field: bits 13-14, VS field: bits 9-10
typedef enum {
    FS_OFF = 0, FS_INITIAL = 1, FS_CLEAN = 2, FS_DIRTY = 3
} fs_state_t;

static inline bool cosmo_hal_fs_is_dirty(uint64_t sstatus) {
    // P3-6 (R47 勘误): &0x3 是位掩码 (取值 0/1/2/3), 真值表对齐 FS_* 枚举, 但
    // INITIAL/CLEAN(=1,=2) 也命中 true — 与注释 "FS==0b11" 不符。
    // D118 状态机对齐: 仅 FS_DIRTY==3 是真脏, 改 ==0b3 (与 D118 三状态语义一致)。
    return ((sstatus >> 13) & 0x3) == 0x3;  // FS == 0b11 (FS_DIRTY only)
}

static inline bool cosmo_hal_vs_is_dirty(uint64_t sstatus) {
    // P3-6 同款: VS_DIRTY (0b11) only
    return ((sstatus >> 9) & 0x3) == 0x3;   // VS == 0b11 (VS_DIRTY only)
}

// In scheduler context_switch:
if (cosmo_hal_fs_is_dirty(prev_sstatus)) {
    save_f0_f31(prev_task);  // 32 × 64-bit = 256B
}
if (cosmo_hal_vs_is_dirty(prev_sstatus)) {
    save_v0_v31(prev_task);  // 32 × vlenb = 1024B-4096B
}
// Embedded: FS=VS=Off → zero save tax
// Server: only save when task actually used FPU/RVV
```

## D67: PLIC retirement contract

Phase 0 ships with **no PLIC driver**. The PLIC memory-mapped region is unmapped from the device tree. If a real PLIC exists in hardware, it is silently ignored (no panic, no warning). Phase 1 introduces AIA (D32/D83) instead.

## D117: D94 Tier 2 IPI ACK timeout + panic fall-through (Q32 R34 fix)

**Status**: **Proposed** (pending Q32 closure).

D94 Tier 2 atomic CAS 的 `while (!ipi_acked(peer_mask)) { }` 是**无超时忙等**——与 D107 同构的多核陷阱。peer Hart 若处于不可中断态(Step 0 .bss 清零,或 L1 cache flush 中断),local Hart 永久自旋。

```c
// D117 R34 fix: IPI ACK timeout + panic fall-through (rdtime 派生)
static uint64_t d94_tier2_timeout_ticks = 0;  // 初始化时由 DTB timebase-frequency 派生

// D117 binding: DTB timebase-frequency → ticks-per-ms 转换
void cosmo_d94_init_timeout(uint64_t timebase_freq_hz) {
    d94_tier2_timeout_ticks = (timebase_freq_hz / 1000);  // 1ms
}

static inline bool cosmo_atomic_cas_ptr(
    void **dest, void *old_val, void *new_val, hart_mask_t peer_mask)
{
    if (has_a_extension && has_global_coherence) {
        void *cur;
        asm volatile (
            "1: lr.d  %0, (%2)\n"
            "   bne    %0, %3, 2f\n"
            "   sc.d   t0, %4, (%2)\n"
            "   bnez    t0, 1b\n"
            "2:"
            : "=&r"(cur)
            : "r"(cur), "r"(dest), "r"(old_val), "r"(new_val)
            : "t0", "memory"
        );
        return cur == old_val;
    } else if (has_a_extension && !has_global_coherence) {
        if (!has_ipi_capability) {
            cosmo_panic_abort(__FILE__, __LINE__, "Tier 2 requires SBI IPI (D108)");
        }
        register_t prev = csr_read_clear(sstatus, SSTATUS_SIE);
        sbi_send_ipi(peer_mask);
        // D117: IPI ACK timeout,rdtime 派生,1ms 预算内未 ACK → panic
        uint64_t deadline = csrr_read(time) + d94_tier2_timeout_ticks;
        while (!ipi_acked(peer_mask)) {
            if (csrr_read(time) > deadline) {
                // D117 binding: panic 输出 peer_mask + 发起 Hart ID,定位信息
                cosmo_panic_abort_fmt(__FILE__, __LINE__,
                    "D94 Tier 2 IPI ACK timeout: peer_mask=0x%lx hart_id=%u",
                    (unsigned long)peer_mask, current_hart_id());
            }
        }
        bool match = (*dest == old_val);
        if (match) *dest = new_val;
        csr_write(sstatus, prev);
        ipi_release(peer_mask);
        return match;
    } else {
        register_t prev = csr_read_clear(sstatus, SSTATUS_SIE);
        bool match = (*dest == old_val);
        if (match) *dest = new_val;
        csr_write(sstatus, prev);
        return match;
    }
}
```

**D117 binding constraints (R34 裁定)**:
1. 超时常量禁止魔数循环计数,由 DTB `timebase-frequency` 派生(rdtime CSR)
2. panic 现场必须输出 `peer_mask` 与发起 Hart ID — 熔断必带定位信息
3. 显式标注: **Tier 2 是 panic-reachable 路径**,调用方契约随之冻结(不再承诺不 panic)
4. 正确先例:D88 "no Silent Hang" 立法禁止的失效形态,无超时忙等是它的多核翻版

**Cost / Benefit**:

| Dimension | D94 R30 (无 timeout) | D117 R34 (rdtime 派生 + 带现场 panic) |
|-----------|----------------------|--------------------------------------|
| 多核死锁风险 | ❌ 永久自旋 | ✓ 1ms 后 panic,带 peer_mask + hart_id 定位 |
| 正常路径开销 | 0 | 0 (rdtime 1 cycle) |
| 低频 endpoint 漂移 | ❌ 魔数循环计数 | ✓ DTB timebase-frequency 派生 |
| 调用方契约 | "无错" | panic-reachable(已冻结) |

## D118: D104 Lazy Save FS=Off 懒切换 + trap-and-retry 三条件消歧 (Q33 R34 fix)

**Status**: **RATIFIED** (R34 裁定,题面事实错误已纠正)。

**事实纠正** (按 RISC-V 特权架构手册): sstatus.FS 四态中,只有 **FS=Off (0b00) 会使 FP/RVV 指令触发 illegal instruction trap**;FS=Clean 下 FP 指令**直接执行**——下一个任务将在旧任务的 FP 寄存器现场上运算,正是 Option C 跨任务泄漏。R30 D104 题面"FS=Clean 触发 trap"是错的,不是"行为未定义",是"行为必然错误"。

**Lazy Save 状态机 (R34 纠正后)**:

```
  +---------+  trap (illegal)   +-----------+  首条 FP 写入   +---------+
  | FS=Off  | ----------------> | FS=Initial | -------------> | FS=Dirty|
  +---------+  (R34 触发器)      +-----------+                +---------+
       ^                              |                          |
       |                              | 显式写回 Off 时           |
       +------------------------------+ 切换任务强制走 trap ------+
       (R34: Linux/xv6 同款,规范设计)
```

**D118 Trap Handler (三条件消歧闸)**:

```c
// D118 R34 fix: 三条件消歧,任一不满足 → 真异常路径
// 条件 ①: scause == illegal instruction
// 条件 ②: 当前 sstatus.FS == Off (0b00)
// 条件 ③: sepc 处指令解码确属 FP/RVV opcode
bool try_fs_lazy_init(uintptr_t sepc, uint64_t scause, uint64_t sstatus) {
    // 条件 ①
    if (scause != EXC_ILLEGAL_INSTRUCTION) return false;
    // 条件 ②
    uint64_t fs = (sstatus >> 13) & 0x3;
    if (fs != FS_OFF) return false;
    // 条件 ③: 解码 sepc 处指令
    uint32_t instr;
    if (!safe_read_u32((uint32_t*)sepc, &instr)) return false;  // D116 ex_table 路径
    if (!is_fp_or_vv_opcode(instr)) return false;
    // 三条件同时成立,置 FS=Initial,重试
    csrs_sstatus_bits(SSTATUS_FS, FS_INITIAL);
    return true;
}

// 同址再 trap 判真异常,禁止二次 retry
static uintptr_t last_retry_sepc = 0;
static uint64_t last_retry_scause = 0;
bool try_fs_lazy_init_with_dedup(uintptr_t sepc, uint64_t scause, uint64_t sstatus) {
    if (sepc == last_retry_sepc && scause == last_retry_scause) {
        // D118 binding: 二次 retry 仍 trap → 永久真异常
        last_retry_sepc = 0; last_retry_scause = 0;
        return false;
    }
    if (try_fs_lazy_init(sepc, scause, sstatus)) {
        last_retry_sepc = sepc; last_retry_scause = scause;
        return true;
    }
    last_retry_sepc = 0; last_retry_scause = 0;
    return false;
}
```

**D118 binding constraints (R34 裁定)**:
1. **D104 全文重写**: 删除 FS=Clean 触发 trap 的错误表述,状态机为 Off →(trap)→ Initial →(首写)→ Dirty
2. **Phase 0 全局 FS=Off 不触发此路径**,D118 是 Phase 1+ (RVV 启用) 前置契约
3. **审计 checklist 新规则**: 凡涉 CSR 字段语义的论断,必须附 RISC-V 特权架构手册章节号 (e.g., sstatus.FS 状态机 = Privileged ISA Manual §3.1.6)
4. 真·非法 FP 指令(无 V 扩展硬件上的 RVV 指令,非法编码)不会被三条件闸门误判 retry

**Cost / Benefit**:

| Dimension | D104 R30 (FS=Clean 题面错误) | D118 R34 (FS=Off 懒切换) |
|-----------|------------------------------|--------------------------|
| 跨任务 FP 寄存器泄漏 | ❌ FS=Clean 直接执行旧 task FP | ✓ FS=Off 触发 illegal → 强制保存/恢复 |
| 真·非法 FP 指令处理 | ❌ 全部 retry → 死循环 | ✓ 三条件消歧 → 真异常路径 |
| 二次 retry 死循环 | ❌ 未防御 | ✓ 同址再 trap 判真异常 |
| 状态机清晰度 | 隐式错误 | ✓ Off→Initial→Dirty 与 RISC-V Privileged Manual §3.1.6 一致 |

```c
// kernel/hal/riscv/plic.c
// D67: this file exists for build-system compatibility only.
// All functions are no-ops. Do NOT add PLIC driver code.
void plic_init(void) { /* no-op */ }
void plic_enable(int irq) { /* no-op */ }
void plic_disable(int irq) { /* no-op */ }
```

## D115 + D119: sstatus.SUM 零开销动态防御 + MXR 永久冻结

```c
// §八 HAL U-Mode 访问使能 (D115 + D119 落锤, R33 + R34 修订)
//!
//! D115: SUM (sstatus Bit 18) 搭便车在 trap_entry 自动保存/恢复.
//! D119 (P3-9 R47 勘误): csrs/csrc 是 csrrs/csrrc 的寄存器别名 (rd=x0),
//!     三者均接受寄存器操作数; 接受立即数的是 csrsi/csrci。
//!     严禁 csrs+寄存器 语义上不存在 (csrs 本就需要寄存器), 正确表述为:
//!     "csrsi/csrci 是立即数版本; csrs/csrc/csrrs/csrrc 都是寄存器版本"。

#define SSTATUS_SUM  (1U << 18)
#define SSTATUS_MXR  (1U << 19)

// D115.5 编译期硬断言: MXR 永久冻结 (P3-8 R47 勘误)
// 断言对象应为 ALLOWED_MASK 不含 MXR, 而不是 SSTATUS_MXR 与 (1<<19) AND 后等于 0
// (后者等于 0x80000, 永远 != 0, 每次构建都熔断)。
#define SSTATUS_ALLOWED_MASK  (SSTATUS_SUM)  // 仅 SUM 可被 user_access 切换
_Static_assert((SSTATUS_ALLOWED_MASK & SSTATUS_MXR) == 0,
               "D115: ALLOWED_MASK must NOT contain MXR (XOM 最高安全生态, MXR 永久冻结)");

static inline void cosmo_user_access_enable(void) {
    // D119: csrrs 寄存器版本, 而非 csrs (立即数)
    register uint32_t val = SSTATUS_SUM;
    asm volatile (
        "csrrs zero, sstatus, %0"   // D119: 正确语法
        : : "r"(val) : "memory"
    );
}

static inline void cosmo_user_access_disable(void) {
    register uint32_t val = SSTATUS_SUM;
    asm volatile (
        "csrrc zero, sstatus, %0"   // D119: 正确语法
        : : "r"(val) : "memory"
    );
}
```

**D115 跨端战略吻合**:

| 维度 | Embedded (RV64IMAC) | Server (RV64GC + RVV) |
|------|---------------------|------------------------|
| **资产精简** | 极致精简, 省去页表遍历 | 零拷贝路径硬件级打通 |
| **纵深防御** | Phase 0 软隔离下, 寄存器级屏障 | Sv39+ASLR 高密环境, 常态 SUM=0 封锁 |
| **Meltdown 变体防御** | 第三方 App 恶意指针不蔓延 | 多核抢占调度 SUM 强制 0 防侧信道 |

## D116: ex_table 静态异常修复协议 (Linux 风格)

```c
// §八 HAL U-Mode 用户态数据流转 (D116 落锤)
//!
//! D116: cosmo_copy_from_user / cosmo_copy_to_user 访存指令必须注册到
//! __ex_table 段. 异常时强制清零 SUM=0 (D115 协同), 注入 EFAULT 至 a0/a1 (D86).

struct exception_table_entry {
    uintptr_t insn;     // 访存指令地址 (sepc)
    uintptr_t fixup;    // 修复跳转目标
};

sys_result_t cosmo_copy_from_user(void *kernel_dst, const void *user_src, size_t len) {
    sys_result_t res = {0, 0, 0};
    cosmo_user_access_enable();  // D115: SUM=1

    __asm__ volatile (
        "1:  lb      t0, 0(%2)\n"           // 临界访存, 注册到 __ex_table
        "    sb      t0, 0(%1)\n"
        "    addi    %2, %2, 1\n"
        "    addi    %1, %1, 1\n"
        "    addi    %0, %0, -1\n"
        "    bnez    %0, 1b\n"
        "    li      %0, 0\n"               // 成功: len=0
        "    j       3f\n"
        "2:\n"                              // 修复跳转桩 (.fixup 目标)
        "    li      %0, 14\n"              // 失败: len=14 (SYS_EFAULT)
        "3:\n"
        ".section .fixup, \"ax\"\n"
        "    .balign 4\n"                    // D116.2: 4 字节对齐 (RVC 兼容)
        "    .long 1b, 2b\n"                // 注册: 异常指令 → 修复点
        ".previous\n"
        : "+r"(len), "+r"(kernel_dst), "+r"(user_src)
        :
        : "t0", "memory"
    );

    cosmo_user_access_disable();  // 正常路径手动关闭; 异常路径 D116 汇编已清零
    res.payload.error_pack.error_code = (int32_t)len;  // P1-2: payload.error_pack, P2-2: -14 EFAULT, 0 = OK
    return res;                   // D86: 16B 经 a0/a1 返回
}
```

**Rust 端 (D74 自动生成 + D116 协同)**:
```rust
#[inline(always)]
pub fn user_access_enable() {
    unsafe { asm!("csrrs zero, sstatus, {}", in(reg) SSTATUS_SUM, options(nomem, nostack)); }
}

#[inline(always)]
pub fn user_access_disable() {
    unsafe { asm!("csrrc zero, sstatus, {}", in(reg) SSTATUS_SUM, options(nomem, nostack)); }
}
```

## Cross-references

- **Boot Sequence** (06): D116 Trap Handler 二分查找 ex_table; D92/D115 SUM 搭便车
- **Call Gate** (05): uses D87/D94 atomics
- **Scheduler** (12): uses D104 FS/VS Lazy Save
- **Memory Subsystem** (09): D116 EFAULT 经 sys_result_t.code 返回 (SYS_EFAULT = 14)
- **Documentation Gate** §二十.7: see gate catalog for forbidden phrases (R19 D67, R27 D94, R33 D115/D116, R34 D119)

## Verification

- `make test-no-a-ext` — RV64IMAC, no A extension, uses D87 soft fallback
- `make test-no-sstc` — RV64IMAC, no Sstc, uses SBI SetTimer fallback
- `make test-no-rvv` — RV64GC without V, FS/VS=Off, zero save tax
- `make test-efault-injection` — inject 0x0DEADBEEF U-Mode 指针, 断言 SYS_EFAULT
- `make check-extable-alignment` — 静态编译期硬闸门, .fixup 段 4 字节对齐

---

## D138 增补 (R41 Q53): FS=Off 编译期保证 — kernel FP 访问静态熔断

> **回链**: 本节为 R41 审计新增 D138 提案, 与 Pillar 4 (Graceful Degradation) 协同, 是 Phase 0 "零切换税"承诺的**编译期 invariant**。

### 问题与动机

D20 + D104 共同承诺 Phase 0 Embedded 端 `FS=VS=Off` → 零 context switch 税。但该承诺依赖 runtime 假设 (硬件启动默认 FS=Off), 不是 compile-time invariant:

- LLVM `RISCVSubtarget.h::HasStdExtF` 控制 F 指令能否发出
- 若 kernel build 误用 `-march=rv64gc` (server target), `HasStdExtF=true`, 任何 kernel `double x = 1.0;` 都 lowering 为 `fld`/`fsd`, runtime 触发 FS=Off → Dirty, 触发 D104 Lazy Save 的 256B save
- LLVM 不会在编译期报"kernel uses FP"——F 是合法 ISA

**真实危害**: Phase 0 16KB Hart-Local 栈预算可能因 FPU save 隐式挤占而崩。

### D138 立法

1. **build_options 派生**: `kernel_march` / `kernel_mabi` / `kernel_mno_f` 按 profile 派生, embedded profile 强制 `rv64imac -mno-f -mno-d -mno-v`。
2. **build.zig 编译期闸门**: profile=embedded 拒绝 F/D/V target 扩展, `@compileError` 熔断。
3. **doc-gate 链接期扫描**: `make audit-no-fp-kernel` 用 `llvm-objdump -d` 扫描 kernel ELF `.text` 段, 发现任何 FP 助记符 (fadd/fsub/fmul/fdiv/fsqrt/fmadd/fmsub/fsgnj/fmin/fmax/fcvt/fmv/fclass/fld/fsd/flw/fsw 等) 立即熔断。

```zig
// build_options.zig (D138)
pub const kernel_march: []const u8 = switch (build_options.profile) {
    .embedded_sparse, .embedded_compact => "rv64imac",
    .server_sparse, .server_compact     => "rv64gc",
};
pub const kernel_mabi: []const u8 = "lp64";

comptime {
    if (build_options.profile == .embedded_sparse or
        build_options.profile == .embedded_compact) {
        if (build_options.has_f or build_options.has_d or build_options.has_v) {
            @compileError("D138 FAIL: profile=embedded forbids F/D/V target extensions");
        }
    }
}
```

```bash
# D138 链接期 FP 助记符扫描
make audit-no-fp-kernel
llvm-objdump -d build/kernel.elf \
  | grep -E '\b(fadd|fsub|fmul|fdiv|fsqrt|fmadd|fmsub|fsgnj|fmin|fmax|fcvt|fmv|fclass|fld|fsd|flw|fsw)\b' \
  | grep -v 'D138_audit_ok' \
  && { echo "D138 FAIL: FP instructions in kernel .text"; exit 1; }
# 期望: 空输出 (embedded profile), server profile 输出 PASS
```

### 传染面

- `12-scheduler.md` § D104 Lazy Save 表 Embedded 行加 "kernel-march=rv64imac 编译期断言"
- `13-build-pipeline.md` 新增 `make audit-no-fp-kernel` 闸门 + `build_options.kernel_march` 派生
- `15-phase0-mvp.md` T1.1 升级为 D138 + 新增 T1.24 (no-FP-asm 测试)
- `20-documentation-gate.md` **新增禁词**: "kernel FP 隐式 allowed" / "FS=Off 默认 by default"
- `16-profile-matrix.md` (R50 D160 索引) — mabi 列 (embedded/qemu_virt/server_compact × lp64/lp64d) 由本 D# 派生, 完整对照表见矩阵 doc

### 元规则校验

- 手册: RISC-V Unprivileged Spec §25 (F/D/V extension instruction listings)
- 编译证据: `llvm/lib/Target/RISCV/RISCVSubtarget.h::HasStdExtF` + `llvm-objdump -d` 输出 FP 助记符
- 场景矩阵 (5 格): Phase 0 Embedded rv64imac / Phase 0 Embedded rv64gc 误用 / Phase 0 Embedded 手写 FP asm / Phase 1+ Server rv64gc / Phase 1+ Server 无 V

---

## D139 增补 (R41 Q54): Tier 2 panic fall-through 三通道冗余 — panic 自身死锁防御

> **回链**: 本节为 R41 审计新增 D139 提案, 与 Pillar 4 协同, 是 D117 IPI timeout panic fall-through 的**fail-stop 保证**。

### 问题与动机

D117 R34 fix: Tier 2 IPI ACK 1ms timeout 后 `cosmo_panic_abort_fmt(...)` 输出 peer_mask + hart_id, 假设 panic 一定能输出。但 panic 自身可能死锁:

- **路径 1 (SBI putchar)**: D88 之前使用, RISC-V SBI v2.0 §5.1 Legacy Console Putchar (EID=0x01)。若 OpenSBI 自身 hang (e.g., DTB parse 中), 输出字符排队不到 console, kernel silent。
- **路径 2 (UART0 MMIO)**: D88 之后使用, 直接 MMIO 写 UART0 THR 寄存器 (QEMU virt 默认 0x10000000)。若 UART0 硬件故障 / 寄存器访问 trap, 死循环。
- **路径 3 缺位**: 当前 Spec 无 fallback, panic fail-through 单路径。

**真实危害**: Tier 2 deadlock (peer Hart 不 ACK IPI) → panic → SBI putchar hang → 整个系统 silent freeze。QEMU 在 OpenSBI hang 时只显示最后已输出字符, kernel 看起来 stuck 但实际 panic 路径死锁。

### D139 立法

panic 路径强制**三通道冗余**:

1. **通道 1 (SBI putchar)**: 优先尝试, 写 'P' 'A' 'N' 'I' 'C' 标记, 兼容 SBI v2.0 §5.1
2. **通道 2 (UART0 MMIO)**: `early_console_is_uart0_ready()` 检测通过后, 直接 MMIO 写, 兼容 D88 后期
3. **通道 3 (`sbi_system_reset`)**: 通道 1 + 2 都失败, 调 M-Mode 强制 reset, 保证 kernel 退出 (与 D95 DTB collision 同款 reset 路径)

**递归 panic 防御**: `__cosmo_panic_in_progress` 静态标志 (D127 load/store-only, 用 `__atomic_load_n` + `__atomic_store_n` 不用 RMW), 入口检测若已在 panic 则直接 `sbi_system_reset` 不再尝试输出, 防止 stack overflow。

```c
/* HANDWRITTEN: tri-end asserts embedded */  // D121 marker
// kernel/hal/panic.c (D139 + D163 完整实现)
#include <sbi.h>
#include <stdint.h>

// D139: panic 递归防御 (D127 load/store-only 严格遵守, 禁 RMW)
static volatile uint8_t __cosmo_panic_in_progress = 0;

static inline bool d139_try_enter_panic(void) {
    // D127: load + store 路径, 无 RMW (无 amoswap/cas)
    uint8_t cur = __atomic_load_n(&__cosmo_panic_in_progress, __ATOMIC_ACQUIRE);
    if (cur) return false;  // 已在 panic, 不再输出
    __atomic_store_n(&__cosmo_panic_in_progress, 1, __ATOMIC_RELEASE);
    return true;
}

void cosmo_panic_abort_fmt(const char *file, int line, const char *fmt, ...) {
    if (!d139_try_enter_panic()) {
        // 递归 panic, 直接 reset, 不再尝试输出
        // D163: fatal stop 路径走 sbi_cold_reboot (a0=1, a1=reason)
        sbi_system_reset(1, 1);  // (reset_type=cold_reboot, reason=system_failure)
        __builtin_unreachable();
    }

    // 通道 1: SBI putchar (legacy)
    sbi_console_putchar('P'); sbi_console_putchar('A');
    sbi_console_putchar('N'); sbi_console_putchar('I'); sbi_console_putchar('C');

    // 通道 2: UART0 MMIO (QEMU virt default 0x10000000)
    if (early_console_is_uart0_ready()) {
        volatile uint32_t *uart0 = (volatile uint32_t *)0x10000000;
        const char *msg = "PANIC\n";
        for (const char *p = msg; *p; p++) {
            // 简单 busy-wait, 不阻塞 (panic 路径不重入)
            uart0[0] = *p;
        }
    }

    // 通道 3: 都失败, 强制 reset (D163 cold_reboot 路径)
    sbi_system_reset(1, 1);  // (reset_type=cold_reboot, reason=system_failure)
    __builtin_unreachable();
}
```

```bash
# D139 测试用例: QEMU 注入 peer Hart hang → panic 三通道, 最终 reset
make test-d139-panic-reset
# 期望: 1ms IPI timeout → panic → 通道 1 (SBI putchar 输出 PANIC) →
#        通道 2 (UART0 输出 PANIC\n) → sbi_system_reset
# 期望 QEMU 在 ~2ms 内重启
```

### 传染面

- `06-boot-sequence.md` § early_console_init 添加 `early_console_is_uart0_ready()` 检测函数 (返回 bool)
- `15-phase0-mvp.md` T1.7 (cosmo_panic_abort C HAL) 升级为 D139 + 新增 T1.25 (panic fail-stop 测试)
- `20-documentation-gate.md` **新增禁词**: "panic 假定成功" / "panic fall-through 单一路径"

### 元规则校验

- 手册: RISC-V SBI v2.0 §5.1 (Legacy Console Putchar, EID=0x01) + §6 (Base Extension)
- 场景矩阵 (6 格): Panic 在 D88 之前 / Panic 在 D88 之后 / Panic 时 UART0 故障 / Panic 时 SBI firmware hang / 递归 panic / QEMU 注入 peer Hart hang 测试

---

## D163 增补 (R52): SBI SRST `reset_type` 双轨语义 — `sbi_shutdown` vs `sbi_cold_reboot`

> **回链**: R52 立法, 第四节血统缺口登记册收口。`sbi_system_reset(0, 1)` 单一假设不再成立; SBI v2.0 §9.4 三档 reset_type (`0=shutdown / 1=cold_reboot / 2=warm_reboot`) 各自有合法场景, 必须显式分流。

### 立法

```c
// D163 双轨分流 (HAL FFI 边界)
// 路径 A: planned shutdown (D154 SYS_SHUTDOWN HAL FFI 路径)
static inline void sbi_shutdown(uint32_t reason) {
    sbi_system_reset(0, reason);  // (reset_type=shutdown, reason)
    __builtin_unreachable();
}
// 路径 B: fatal stop (D95 DTB collision / D136 Step 0 trap / D139 panic / D161 __stack_chk_fail)
static inline void sbi_cold_reboot(uint32_t reason) {
    sbi_system_reset(1, reason);  // (reset_type=cold_reboot, reason)
    __builtin_unreachable();
}
```

**调用点分流**:
- `sbi_shutdown(reason)` ← D154 power-off 路径 (planned, 用户/系统主动)
- `sbi_cold_reboot(reason)` ← D95/D136/D139/D161 所有不可恢复路径 (fatal, 物理停机+冷启)

### 立法动机 (Windows MVP D-IMPL-05)

MVP 早先全部用 `sbi_system_reset(0, 1)` (单一 shutdown), 配 QEMU `-no-reboot` 时 QEMU 不退出 — `0=shutdown` 期望 firmware 处理 reset, 但 OpenSBI 在 `-no-reboot` 下直接 halt QEMU。MVP 改 `sbi_system_reset(1, 1)` (cold_reboot) 后, QEMU 干净退出。

R52 D163 立法归口: 工具行为驱动偏离不再是 "MVP 自行改的口径", 而是有 D# 背书的合法 spec 行为 — fatal stop 路径全部走 cold_reboot, planned shutdown 才走 shutdown。MVP D-IMPL-05 历史偏差升级为 D163 双轨分流。

### 与 R46 勘误的关系

R46 勘误 ② 把 `sbi_system_reset(0, 1, SBI_SRST_SYSTEM_RESET)` 修订为双参 `(reset_type, reset_reason)`, 删去 `SBI_SRST_SYSTEM_RESET` 常量。R52 D163 在 R46 勘误之上**进一步分流** reset_type, 不冲突, 不替代。

### 传染面

- `06-boot-sequence.md` § D136 Step 0 trap 已升 cold_reboot (R52)
- `15-phase0-mvp.md` T1.11 SRST 用例分流双轨
- `16-profile-matrix.md` § 各 profile SRST 默认 (planned shutdown vs fatal stop)
- `check-docs.sh` 不新增禁词 (D163 是分流语义, 不与既有禁词冲突)

---

## D141 增补 (R42 Q56, R46 反杜撰勘误后): Hart ID 来源机制 — a0 权威 + DTB num_harts 断言 (cross-ref 06-boot-sequence.md § D141)

D99 `_start: mv tp, a0` 在 `-bios none` 直启模式下契约仍受 a0 完整性保护: Phase 0 启动器 (OpenSBI) 把 hwid 写入 a0 后即校验, 失败则 SRST。**R46 反杜撰纪律**勘误后, R42 Q56 的 "SBI HSM `sbi_hart_get_id` fallback" 已被**禁用**:

- SBI HSM 扩展 (EID=0x48534D) **无 `hart_get_id` 函数**; SBI HSM 仅提供 `hart_start` (fid 0) 与 `hart_stop` 等。`sbi_hart_get_id` 是 RISC-V SBI 规范中**不存在**的高危杜撰, 一旦实现等于在真空中捏造返回值。
- D141 现行为: a0 寄存器 OpenSBI 预校验权威, DTB `/cpus/cpu@N` 节点 `num_harts` 断言兜底, Hart ≥ num_harts 时 SRST。S-Mode 不再"探测 SBI 兜底"。
- 传染面: `06-boot-sequence.md` § D141 同步 (a0 权威 + park 循环); `15-phase0-mvp.md` T1.5 取消 bios=none 测试 (R46 勘误).

```c
// D141 R46 勘误后实现 (R42 版 sbi_hart_get_id fallback 删除)
static uint32_t cosmo_get_hart_id(uint32_t a0_hint, const void *dtb) {
    uint32_t dtb_harts = dtb_count_cpu_nodes(dtb);  // DT 节点扫描
    if (a0_hint >= dtb_harts) {
        // D141: a0 越界 DTB 声明的 hart 数, 直接 SRST
        // R52 D163: fatal stop 路径走 cold_reboot (a0=1), 配 -no-reboot 干净退出
        sbi_system_reset(1, 1);  // (reset_type=cold_reboot, reason=system_failure)
    }
    return a0_hint;  // D141: a0 权威
}
```

---

## D142 增补 (R42 Q57): D118 三条件消歧扩展为四条件 — 编译期 FP/RVV 扩展支持检查

> **回链**: R42 审计新增 D142, D118 三条件消歧仅覆盖 FP, RVV (V 扩展) 缺位场景的解码歧义。

### 问题与动机

D118 三条件消歧 + D130 解码器覆盖 0x07/0x27/0x43/0x47/0x4B/0x4F/0x53/0x57 主码, 但**主码层面**不区分 FP vs RVV。若目标硬件有 F/D 但无 V 扩展 (RV64GC without V), 用户执行 VLE 指令 (主码 0x57), 解码器返回 true → 置 FS=Initial → retry → 再次 illegal → dedup panic (误导信息 "illegal instruction", 真实原因是 "RVV illegal on no-V target")。

### D142 立法

D118 三条件扩为四条件, 加 `build_options.has_fp_extension` / `has_v_extension` 编译期检查:

```c
// kernel/hal/riscv/fp_opcode_decode.h (D142 升级)
static inline bool is_fp_opcode(uint32_t instr) {
    if (!build_options.has_fp_extension) return false;
    uint32_t opcode = instr & 0x7F;
    switch (opcode) {
        case 0x07: case 0x27:  // LOAD/STORE-FP
        case 0x43: case 0x47: case 0x4B: case 0x4F:  // FMADD/FMSUB/FNMSUB/FNMADD
        case 0x53:  // OP-FP
            return true;
        default: return false;
    }
}

static inline bool is_vv_opcode(uint32_t instr) {
    if (!build_options.has_v_extension) return false;
    return (instr & 0x7F) == 0x57;  // OP-V
}

bool try_fs_vs_lazy_init(uintptr_t sepc, uint64_t scause, uint64_t sstatus) {
    if (scause != EXC_ILLEGAL_INSTRUCTION) return false;
    uint64_t fs = (sstatus >> 13) & 0x3;
    if (fs != FS_OFF) return false;
    uint32_t instr;
    if (!safe_read_u32((uint32_t*)sepc, &instr)) return false;
    if (!is_fp_opcode(instr) && !is_vv_opcode(instr)) return false;
    if (is_fp_opcode(instr)) csrs_sstatus_bits(SSTATUS_FS, FS_INITIAL);
    if (is_vv_opcode(instr)) csrs_sstatus_bits(SSTATUS_VS, VS_INITIAL);
    return true;
}
```

**场景矩阵 (5 格)**: RV64GC+V FS=Off 用户 VLE / RV64GC+V FS=Initial 已设 / **RV64GC 无 V FS=Off 用户 VLE (buggy) → 走真异常** / **RV64IMAC 无 F/D/V FS=Off 用户 fmadd.d → 走真异常** / RV64GC FS=Off 用户 fmul.d → 置 FS=Initial → 重试成功。

**传染面**: `12-scheduler.md` § D104 Lazy Save FS/VS 路径引用 D142; `13-build-pipeline.md` build_options.has_fp_extension / has_v_extension 派生 (D138 联动); `20-documentation-gate.md` 新增禁词 "D118 三条件覆盖所有 RVV 场景"。

---

## D144 增补 (R43 Q59): Tier 3 multi-Hart 跨 Hart 软临界区 race 防御

> **回链**: R43 审计新增 D144, D94 Tier 3 "single Hart soft critical section" 假设与真实多核 Tier 3 硬件的 race 防御。

### 问题与动机

D94 Tier 3 走 `csrc sstatus, SIE` 软临界区, 注释 "single Hart soft critical section"。但 RV64IMC 多核 SoC 真实存在 (SiFive E2 IP 可配 RV32IMC 多核)。Tier 3 多 Hart 场景下, SIE 只屏蔽本地 Hart, 跨 Hart 写共享数据无保护。

### D144 立法

D94 Tier 3 增加 `num_harts > 1` 检测, 多 Hart 走 SBI IPI 自旋锁 (与 Tier 2/D117 同路径):

```c
// 08-risc-v-hal.md § D94 Tier 3 (D144 升级)
} else {  // Tier 3: no A extension
    if (num_harts > 1) {
        // D144: Tier 3 多 Hart 走 SBI IPI 自旋锁
        sbi_send_ipi(peer_mask);
        uint64_t deadline = csrr_read(time) + d94_tier2_timeout_ticks;
        while (!ipi_acked(peer_mask)) {
            if (csrr_read(time) > deadline) {
                cosmo_panic_abort_fmt(...);  // D117 timeout
            }
        }
        bool match = (*dest == old_val);
        if (match) *dest = new_val;
        ipi_release(peer_mask);
        return match;
    }
    // 单 Hart 软临界区 (Phase 0 默认)
    register_t prev = csr_read_clear(sstatus, SSTATUS_SIE);
    bool match = (*dest == old_val);
    if (match) *dest = new_val;
    csr_write(sstatus, prev);
    return match;
}
```

**传染面**: `12-scheduler.md` Work-Stealing 联动 + `15-phase0-mvp.md` T1.10 升级 + `20-documentation-gate.md` 新增禁词 "Tier 3 假定单 Hart"。
**传染面**: `12-scheduler.md` Work-Stealing 联动 + `15-phase0-mvp.md` T1.10 升级 + `20-documentation-gate.md` 新增禁词 "Tier 3 假定单 Hart"。

---

## D152 增补 (R45 Q67): D118 decoder 增 FP CSR 0x73 SYSTEM 主码

> **回链**: R45 审计新增 D152, D118 三条件 decoder 对 FP CSR 0x73 SYSTEM 访问的已知边界。

### 问题与动机

R38 D130 解码器覆盖 0x07/0x27/0x43/0x47/0x4B/0x4F/0x53/0x57 主码, **漏 0x73 SYSTEM** (FP CSR 访问: FRCSR/FRRM/FRFLAGS)。FS=Off 时 FP CSR 读也 illegal, decoder 返回 false → 真异常路径 → panic, 但用户代码一致期望"FP 访问自动置 FS=Initial"。

### D152 立法

D130 decoder 增 0x73 主码, 与 FP 指令统一处理:

```c

// kernel/hal/riscv/fp_opcode_decode.h (D152 升级)

static inline bool is_fp_or_vv_opcode(uint32_t instr) {

    if (!build_options.has_fp_extension) return false;  // D142

    uint32_t opcode = instr & 0x7F;

    switch (opcode) {

        case 0x07: case 0x27:  // LOAD/STORE-FP

        case 0x43: case 0x47: case 0x4B: case 0x4F:  // FMADD family

        case 0x53:  // OP-FP 全集

        case 0x73:  // D152: SYSTEM (FP CSR: FRCSR/FRRM/FRFLAGS), FS=Off → 置 FS=Initial

            return true;

        case 0x57:  // OP-V (RVV)

            return build_options.has_v_extension;

        default: return false;

    }

}

```

**传染面**: `12-scheduler.md` § D104 Lazy Save FS/VS 联动 + `20-documentation-gate.md` 新增禁词 "FP CSR 访问假定合法"。

---

## D139 增补 (R41 Q54, 勘误后): Tier 2 panic 三通道冗余 — 16550 UART 寄存器勘误

> **回链**: R41 审计新增 D139, D117 IPI timeout panic fall-through 三通道冗余。**R46 勘误**: 16550 UART 寄存器表读错, 必须修正。

### 16550 UART 寄存器勘误 (关键)

R46 裁定 (Brra1n0): THR-empty 状态在 **LSR (offset 5) bit 5 (0x20)**, 不是 MCR (offset 4) bit 0 (DTR)。原代码轮询 DTR 位恒 1, panic 路径自己先死循环。QEMU virt 16550 **按字节访问**, `uint32_t*` 索引错。

```c
// kernel/hal/panic.c (D139 R46 勘误后, 完整 panic 三通道; R52 D163 升 cold_reboot)
void cosmo_panic_abort_fmt(const char *file, int line, const char *fmt, ...) {
    // D139 递归防御 (D127 load/store-only, 禁 RMW)
    if (!d139_try_enter_panic()) {
        // R52 D163: fatal stop 路径走 sbi_cold_reboot (a0=1), 不再 shutdown (a0=0)
        sbi_system_reset(1, 1);  // (reset_type=cold_reboot, reason=system_failure)
        __builtin_unreachable();
    }

    // 通道 1: SBI putchar (legacy)
    sbi_console_putchar('P'); sbi_console_putchar('A');
    sbi_console_putchar('N'); sbi_console_putchar('I'); sbi_console_putchar('C');

    // 通道 2: UART0 MMIO (R46 勘误 - 按字节访问, LSR bit 5 = THRE)
    if (early_console_is_uart0_ready()) {
        volatile uint8_t *uart = (volatile uint8_t *)0x10000000;
        const char *msg = "PANIC\n";
        for (const char *p = msg; *p; p++) {
            while (!(uart[5] & 0x20)) { /* wait THR empty (LSR bit 5) */ }
            uart[0] = *p;  /* write THR */
        }
    }

    // 通道 3: 都失败, 强制 reset (R52 D163 cold_reboot 路径)
    sbi_system_reset(1, 1);  // (reset_type=cold_reboot, reason=system_failure)
    __builtin_unreachable();
}
```

**传染面**: `15-phase0-mvp.md` T1.7 升级 D139 R46 勘误版; `20-documentation-gate.md` 新增禁词 "16550 MCR DTR poll"。


---

## D152 增补 (R45 Q67, R46 勘误后): 0x73 收窄到 FP CSR subset — 二次解码

> **回链**: R45 审计新增 D152, FP CSR 0x73 SYSTEM 访问的已知边界。**R46 勘误**: 0x73 必须**二次解码** — `funct3 ≠ 0` 且 CSR 编号 ∈ `{fflags, frm, fcsr}` 才返回 true, 其余 0x73 一律真异常路径。

### 0x73 收窄 (R46 勘误)

R46 裁定: 0x73 覆盖全部 SYSTEM 指令, `case 0x73: return true` 过宽。funct3=0 时是 ECALL/EBREAK/xRET/WFI, 其余 funct3 下是任意 CSR 访问。误判进 FP 懒惰初始化路径会导致信息误导。

```c
// kernel/hal/riscv/fp_opcode_decode.h (D152 R46 勘误后)
static inline bool is_fp_or_vv_opcode(uint32_t instr) {
    if (!build_options.has_fp_extension) return false;  // D142
    uint32_t opcode = instr & 0x7F;
    uint32_t funct3 = (instr >> 12) & 0x07;
    uint32_t csr_addr = (instr >> 20) & 0xFFF;  // R46: SYSTEM 指令的 CSR 字段
    switch (opcode) {
        case 0x07: case 0x27:  // LOAD/STORE-FP
        case 0x43: case 0x47: case 0x4B: case 0x4F:  // FMADD family
        case 0x53:  // OP-FP 全集
            return true;
        case 0x57:  // OP-V (RVV)
            return build_options.has_v_extension;
        case 0x73:  // SYSTEM (R46 勘误: 二次解码, 仅 FP CSR subset)
            if (funct3 == 0) return false;  // ECALL/EBREAK/xRET/WFI → 真异常
            return csr_addr == 0x001  // fflags
                || csr_addr == 0x002  // frm
                || csr_addr == 0x003; // fcsr
        default: return false;
    }
}
```

**传染面**: `12-scheduler.md` § D104 Lazy Save FS/VS 联动; `20-documentation-gate.md` 新增禁词 "0x73 全 SYSTEM 误判 FP"。

