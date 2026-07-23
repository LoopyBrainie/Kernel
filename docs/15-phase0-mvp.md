# 15 · Phase 0 MVP (Day 4 Implementation Plan)

**Plan section**: §十五
**Key decisions**: All Phase 0-relevant (D1-D101 except Phase 1+ deferred)
**Status**: Single-sprint plan; 15 atomic tasks

---

## Overview

Phase 0 MVP is a single-sprint plan with 15 atomic tasks. Each task has a 1-2 day budget, an explicit verification gate, and a single decision dependency. The plan is the **executable spine** that converts the locked spec into a working QEMU image.

## Task dependency graph

```
T1.1 build pipeline ──┬── T1.2 C abi.h
                      ├── T1.3 Rust abi.rs (auto-gen by T1.1)
                      └── T1.4 entry.S Step 0 (Anti-Trampling + Early Boot Stack)

T1.4 entry.S ──────────┬── T1.5 S-Mode Hart ID FFI
                      ├── T1.6 UKI Loader ELF scan
                      └── T1.7 basal_panic_abort C HAL (D168, D76 SUPERSEDED)

T1.7 panic + T1.2 abi ┬── T1.8 early_console_init SBI Stub
                      ├── T1.9 Call Gate 5-file stub
                      ├── T1.10 sys_atomic_cas_ptr 3-tier
                      └── T1.11 check_elf_sizes.sh gate

T1.1 + T1.2 ──────────┬── T1.12 initrd ≤ 50 build.zig gate
                      ├── T1.13 Network Shim Layer
                      ├── T1.14 Shell compile-time audit
                      └── T1.15 Trap entry sscratch 二次交换 防御
```

## Tasks

**R51-F1 (D-01)**: Host Zig version is `Zig ≥0.15`, locked by `toolchain.lock`. Any `Zig 0.16` literal is forbidden. Back-link: `05-call-gate.md:193`.

**R51-F5 (D-13)**: `rev8` (RISC-V Zbb byte-reverse) is **forbidden** in spec_lab frozen code. rv64imac target (D138) has no B extension; `rev8` illegal at link time. Byte-reverse must be explicit `slli+srli+or` sequence. See `06-boot-sequence.md` § rev8 sequence anchor for explicit form. spec_lab assertion `R51-F5-rev8.sh` enforces: forward = explicit `slli.*srli` form; reverse = `rev8` must NOT appear in non-audit lines.

### T1.1: build.zig SSOT translate-abi (D74)

```zig
// build.zig: Stage 2 emit FFI bindings
const translate_abi = b.addSystemCommand(&.{
    "python3", "tools/translate_abi.py",
    "--input", "basal/include/sys/abi.zig",
    "--rust-out", "arch/riscv64/abi.rs",
    "--c-out", "basal/include/sys/abi.h",
});
```

**Verify**: `zig build` succeeds; `arch/riscv64/abi.rs` regenerated, no manual edits.

### T1.2: C `sys_result_t` 16B + payload 8B (D86/D89, R48 勘误增补: 恢复 payload union)

```c
// R48: 原形态 {header, reserved, value: u64} 丢失 payload union,
//      错误路径的 remote_node_id/subsystem_id/error_code 无处安放。
//      改回 04 § Three-end assert templates frozen 形态。
typedef union {
    uint64_t value;
    struct __attribute__((packed)) {
        uint16_t remote_node_id;   /* D4 position transparency (0xFFFF = local) */
        uint16_t subsystem_id;
        int32_t  error_code;       /* D89 + P2-2: errno always negative */
    } error_pack;
} sys_result_payload_t;
_Static_assert(sizeof(sys_result_payload_t) == 8, "D86 8B payload");

typedef struct {
    uint32_t header;     /* P1-2: bit 31 = is_error, bits 0-30 = flags/subsystem_hint */
    uint32_t reserved;
    sys_result_payload_t payload;
} alignas(8) sys_result_t;
_Static_assert(sizeof(sys_result_t) == 16, "FATAL: 16B red line (D86)");
_Static_assert(alignof(sys_result_t) == 8,  "FATAL: 8B align");
```

**Verify**: `zig build` succeeds; C-side `static_assert` passes; ABI smoke test.

### T1.3: Rust `#[repr(C, align(8))] sys_result_t` (D74 auto-gen, R48 勘误增补: 全改 canonical 形态)

```rust
// R48: 原 Rust 三字段形态 (P1-2 前的旧 C 风格 code/status/value) 已被废弃,
//      改回与 04 C/Rust frozen 一致, 引入 sys_result_payload_t 与 error_pack。
#[repr(C, align(8))]
pub struct sys_error_pack_t {
    pub remote_node_id: u16,
    pub subsystem_id:   u16,
    pub error_code:     i32,
}
const _: () = { assert!(size_of::<sys_error_pack_t>() == 8); };

#[repr(C, align(8))]
pub union sys_result_payload_t {
    pub value:      u64,
    pub error_pack: sys_error_pack_t,
}
const _: () = { assert!(size_of::<sys_result_payload_t>() == 8); };

#[repr(C, align(8))]
pub struct sys_result_t { pub header: u32, pub reserved: u32, pub payload: sys_result_payload_t }
const _: () = {
    assert!(size_of::<sys_result_t>() == 16);
    assert!(align_of::<sys_result_t>() == 8);
};
```

**Verify**: `cargo build` succeeds; `cargo test` ABI tests pass.

### T1.4: entry.S Step 0 (D92/D95)

```asm
_start:
    # D95: Anti-Trampling DTB magic + size + overlap
    lw t0, 0(a1); li t1, 0xedfe0dd0; bne t0, t1, .L_fatal_dtb_magic
    # ... overlap check ...
    la t0, __early_boot_stack_top; csrw sscratch, t0  # D92
    # .bss 清零
    j kmain
```

**Verify**: QEMU boots with corrupt DTB → SBI SRST halt (R52 D163: cold_reboot 路径, a0=1); valid DTB → reaches kmain.

### T1.5: S-Mode Hart ID OpenSBI FFI (D99)

```asm
mv tp, a0  # a0 = hartid from OpenSBI (NOT csrr mhartid)
```

**Verify**: `-smp 4` QEMU boots 4 harts without `Illegal Instruction`.

### T1.6: UKI Loader ELF scan (D100)

```c
// uki_loader.c: ~2KB ELF PH scanner
const Elf64_Phdr *phdr = (const Elf64_Phdr *)(uki_base + ehdr->e_phoff);
for (int i = 0; i < ehdr->e_phnum; i++) {
    if (phdr[i].p_type != PT_LOAD) continue;
    if (__boot_meta_start in phdr[i] range) {
        // Write BOOT_META_MAGIC + slot_id
    }
}
```

**Verify**: UKI Loader locates `__boot_meta_start` for elastic `.text` size.

### T1.7: basal_panic_abort C HAL (D168, D76 SUPERSEDED)

```c
// basal/c/basal_panic.c
__attribute__((noreturn)) void basal_panic_abort(const char *file, int line, const char *msg) {
    // D76: single panic entry
    early_console_puts("[PANIC] ");
    early_console_puts(file); early_console_puts(":");
    early_console_put_uint(line);
    early_console_puts(" "); early_console_puts(msg);
    sbi_srst_system_reset(SBI_SRST_SYSTEM_RESET, 0, 1);  // 物理停机
    __builtin_unreachable();
}
```

**Verify**: `panic!("test")` halts via SBI SRST, no zombie reboot.

### T1.8: early_console_init SBI Stub (D88)

```c
void early_console_init(void) {
    // D88: do NOT depend on DTB
    // Always available: OpenSBI sbi_console_putchar
    early_console_putchar = sbi_console_putchar;
}
```

**Verify**: Boot with corrupted DTB, panic still produces UART output via SBI.

### T1.9: Call Gate 5-file stub (D56/D62/D73/D82)

**R51 D153 命名锚**: Rust dispatcher 重命名 `cosmo_core_syscall_dispatcher.rs` → `syscall_stubs.rs`(D129 stub 角色明示). Zig 侧 `syscall_dispatch.zig` 不改名.

```
kernel/arch/riscv64/call_gate/
├── syscall_dispatch.zig
├── syscall_stubs.rs
├── call_gate.h
├── entry_call_gate.S
└── HLCB.zig
```

**Verify**: Shell `cosmo_open("scheme://0/...")` reaches kernel dispatcher; cargo-geiger 0 unsafe.

### T1.10: sys_atomic_cas_ptr 3-tier (D94)

```c
// HAL: has_a_extension + has_global_coherence → 3-tier
// Tier 1: lr.d / sc.d
// Tier 2/3: csrc sstatus, SIE
```

**Verify**: `make test-no-a-ext` works on RV64IMAC; `make test-no-coherence` works on multi-Hart without reservation set.

### T1.11: check_elf_sizes.sh Post-Build gate (D101 → **D113 R32 fix**)

```bash
# D113: llvm-readobj --syms --json + jq + set -euo pipefail
# Verifies 5 struct sizes in final ELF, robust against LLVM version drift + substring clash
```

**Verify**: Hand-edit one struct size in source → gate aborts; revert → gate passes. Add `sys_result_aux_t` symbol → still passes (D113 substring-immune).

### T1.11b: cflag 编译期防线 (R52 D161/D162 收口)

```bash
# D161: C HAL 栈保护器必启 (-fstack-protector-strong)
# D162: 单函数栈帧警告阀 (-Wstack-usage=2048, warning-as-error)
zig build -Dcflags_c_hal="-fstack-protector-strong -Wstack-usage=2048 -Werror=stack-usage"
```

**Verify**:
- D161: `nm kernel.elf | grep __stack_chk_guard` 必须单一实例 (`.rodata` 链接期唯一); 故意写一个越界数组函数 → build ABORT (`-fstack-protector-strong` 触发 `__stack_chk_fail` 链接)
- D162: 故意写一个 3KB 栈帧函数 → build ABORT (`-Werror=stack-usage` 升级 warning)
- D161 + D162 联防: 16KB Hart-Local 栈 (D107) + 2048B 单帧上限 → ≥8 帧安全余量

### T1.12: initrd ≤ 50 build.zig gate (D105)

```zig
if (initrd_files.len > MAX_FILES) @compileError(...);
```

**Verify**: Pack 51 files into initrd → compile error; pack 50 → build succeeds.

### T1.13: Network Shim Layer (D96 → **D108 R31 fix**)

```rust
// D108: SHIM_PAYLOAD_MAX 按 -Dip_family=v4|v6 编译期派生
// IPv4 → 1464, IPv6 → 1444
// network_frame_t 加 ip_family: u8 字段 (Phase 0 冻结)
const SHIM_PAYLOAD_MAX: usize = 1500 - L3_HDR_SIZE - UDP_HDR_SIZE - SHIM_HDR_SIZE;
```

**Verify**: `make test-jumbo-on` works against 1500B MTU simulator; `make test-shim-v6` validates IPv6 1444B 切片; roundtrip byte-identical.

### T1.14: Phase 0 Shell compile-time audit (D97 → **D116 R33 fix**)

```bash
# D116: --all-targets 替代 --lib, 覆盖 bin target
# 1. cargo geiger --all-targets (覆盖 lib + bin)
# 2. Zig pub var audit
# 3. C function pointer audit
# 4. Cross-language FFI symbol audit
```

**Verify**: All 4 checks pass on default Shell. Inject `unsafe { ... }` in `shell_main` → D116 第 1 条 FATAL.

### T1.15: Trap entry sscratch 二次交换 防御 (D106 → **D107 R31 fix**)

```asm
# D107: 从 HLCB 加载 per-Hart 区间, 替代全局 __kernel_stack_base/top 单例符号
trap_entry:
    csrr t0, sscratch
    la t3, __hlcb_table
    slli t4, tp, 6              # HLCB entry size = 64B
    add t3, t3, t4
    ld t1, 32(t3)               # HLCB.kernel_stack_base
    ld t2, 40(t3)               # HLCB.kernel_stack_top
    bltu t0, t1, .L_user_mode_trap
    bgeu t0, t2, .L_user_mode_trap
    j .L_trap_push_context
.L_user_mode_trap:
    csrrw sp, sscratch, sp
    j .L_trap_push_context
```

**Verify**: `make test-nested-trap` injects timer interrupt mid-syscall, no double fault. `make test-multi-hart` (QEMU `-smp 4`) 验证 Hart 2 sp 落在 `hlcb[2]` 范围,正确归类。

### T1.16: HLCB per-Hart 区间 Step 0/1 顺序 (D107 R31 binding)

```c
// D107 binding constraint: 启动序列必须先于任何 Trap 完成 hlcb[i] 初始化
void kmain(hart_id_t hart_id) {
    dtb.parse_memory_nodes(&hlcb_table);  // 填所有 hart 的 kernel_stack_base/top
    asm volatile("csrw sscratch, %0" :: "r"(hlcb_table[hart_id].kernel_stack_top));
    hlcb_table[hart_id].in_kernel_space.store(true, .SeqCst);
}
```

**Verify**: `make test-dtb-late` — 注入 DTB 在 kmain 后到达,验证 HLCB 已就绪,Trap 不撕裂。

### T1.17: build.zig -Dip_family 编译期熔断 (D108 R31 binding)

```zig
// D108 binding: 非法值编译期熔断,严禁静默 fallback
pub fn parse_ip_family(s: []const u8) IpFamily {
    if (std.mem.eql(u8, s, "v4")) return .v4;
    if (std.mem.eql(u8, s, "v6")) return .v6;
    @compileError("Invalid -Dip_family: '" ++ s ++ "'. Allowed: v4, v6.");
}
```

**Verify**: `zig build -Dip_family=v5` → compile error; `-Dip_family=ipv4` → compile error; `-Dip_family=v4` 或 `v6` → build OK.

### T1.18: sys_error_decode 钉死解码次序 (D110 R32 binding)

```c
// D110 binding decode order: ① sign ② Bit30 ③ normal
static inline int32_t sys_error_decode(int32_t packed, sys_error_descriptor_t *out_desc) {
    if (packed < 0) return packed;                              // ①
    if ((packed & (1U << 30)) != 0) {                           // ②
        uint32_t idx = (uint32_t)packed & 0x3FFFFFFF;
        if (idx >= 1024) return SYS_EINVAL;
        *out_desc = sys_error_descriptor_table[idx];
        return 0;
    }
    return packed;                                              // ③
}
```

**Verify**: `make test-errno-each` 跑遍 `SYS_EPERM/ENOENT/EIO/EBADF/ENOMEM`,验证用户态收到原始 errno (而非 SYS_EINVAL)。`make test-bit30-descriptor` 验证 Bit 30 = 1 走 descriptor 路径。

### T1.19: ex_table 16B size + 链接后 insn 升序 (D112 R32 binding)

```c
// D112: exception_table_entry 16B 编译期 size 断言
_Static_assert(sizeof(struct exception_table_entry) == 16, "D112: 16B entry");
_Static_assert(sizeof(((struct exception_table_entry*)0)->insn) == 8, "D112: 8B insn");
_Static_assert(sizeof(((struct exception_table_entry*)0)->fixup) == 8, "D112: 8B fixup");

// D112: __ex_table 链接后按 insn 升序 — nm/symbol build gate
```

**Verify**: `make check-exception-table-sort` 验证 `nm kernel.elf | grep __ex_table` 输出按 insn 升序。

### T1.20: PMP region 预算编译期记账 (D109 R31 binding)

```rust
// D109 binding: PMP region 预算稀缺 (典型 16 槽), U-Mode comm 通道编译期记账
const USED_PMP_REGIONS: usize = blk: { /* 累加 scheme 通道数 + boot ROM + U-Mode text */ };
comptime {
    if (USED_PMP_REGIONS > PMP_MAX_REGIONS) @compileError("D109: PMP budget exceeded");
}
```

**Verify**: 添加第 17 个 scheme:// 通道 → compile error;减少到 14 → build OK。

## Wave ordering (Build → Prove → Remove)

```txt
Wave 1: Build (T1.1-T1.15)
Wave 2: Prove on QEMU rv64 + Allwinner D1s (RV64IMAC)
Wave 3: Prove on SiFive HiFive Unmatched (RV64GC)
Wave 4: Defer Phase 1 (D26/D31/D43/D83/D91/D102/D104)
```

## Exit criteria

- [ ] `zig build` produces `kernel.elf` ≤ 700KB **(R51-F4 (D-10): 指 ELF 文件大小 = `readelf -S` 累计. 物理跨度由 02 § D49 ledger 双轨制闸门 (D112/D57/D126) 覆盖, 不可混用. Back-link: 02-memory-topology.md § V2.2 ceiling 644KB)**
- [ ] `make audit-shell` passes 4 checks
- [ ] `make test-no-a-ext` boots on RV64IMAC
- [ ] `make test-dtb-corruption` halts via SBI SRST
- [ ] `make test-jumbo-on` 1500B MTU roundtrip byte-identical
- [ ] Documentation gate `bash docs/ci/check-docs.sh` 0/N forbidden words (N = `${#FORBIDDEN[@]}` 派生; D115 R33, R37-R46 入册, R47 D151 撤销)
- [ ] **R49-C7 证据补丁: harness verdict 必须落盘 artifacts/** — 任何 Exit criteria 触发的 smoke / shutdown / boot 检查, 必须把 `verdict=PASS|FAIL` 与关键 marker (如 `shutting down` / `COSMO BOOT OK` / `error: code=`) 写到 `artifacts/<test>.verdict` 与 `artifacts/<test>.log` 双文件. 沙箱二 C7 缺口 (verdict 仅 echo, 未落盘) 起, 证据从此受规矩管. 验收: `tools/check_artifacts_on_disk.sh` 扫描所有 `artifacts/*.verdict`, 缺失 → gate 熔断
