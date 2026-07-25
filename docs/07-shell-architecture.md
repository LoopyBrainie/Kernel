# 07 · Shell Architecture (Phase 0 Containerized Kernel-Mode Shell)

**Plan section**: §七
**Key decisions**: D31, D50, D55, D97
**Status**: Frozen

---

## Overview

The Phase 0 Shell is a Rust no_std application that runs in **S-Mode co-residency** with the Zig kernel — there is no MMU, no U-Mode, no hardware privilege boundary between Shell and Kernel. This is fundamentally a **"kernel-mode containerized shell"** (D97): the Shell has full S-Mode privileges and is therefore bounded by compile-time audit, not by hardware. Phase 1 separates them via Sv39 PTE alignment while keeping the user-facing API identical (D55).

## Why "containerized kernel-mode shell" (D97)

Because Phase 0 has no MMU, Rust Shell and Zig Kernel share the same address space and privilege level. A `unsafe` block in Shell can directly mutate kernel `.data` or `.service_pools` — there is no hardware stop. The defense is entirely:

- **Compile-time audit** (D97): `cargo-geiger` 0 unsafe blocks required
- **Zig opaque types**: Rust cannot construct a Zig `extern struct` that wasn't auto-generated
- **Linker segment isolation** (D31): Shell in `.text.shell` segment, isolated from `.data` and `.service_pools`
- **No third-party direct loading** (D97): Shell modules are all first-party compiled

This is a **gentleman's agreement enforced by build-time tooling**, not a hardware boundary.

## Audit checklist (D97 + **D116 R33 fix**, in `make audit-shell`)

```bash
# 1. cargo-geiger: 0 unsafe blocks in Shell crate (D97 + D116 R33 fix)
# D116: --all-targets 替代 --lib, 覆盖 bin target (Phase 0 Shell 是 no_std bin)
cargo geiger --all-targets --format json | jq '.unsafe_used' | grep -q false || {
    echo "FATAL: Shell has unsafe blocks (D116: --all-targets)"; exit 1;
}

# 2. Zig pub var audit: only documented globals
zig build audit-globals  # checks against whitelist

# 3. C HAL function pointer audit
ctags -R kernel/hal/c | grep -E '^[a-z_]+ +.*\(\*\)' | diff - audits/allowed_fn_ptrs.txt

# 4. Cross-language FFI: only D74-generated symbols
nm kernel.elf | grep ' U ' | grep -v '__basal_abi_' | grep -q . || {
    echo "FATAL: Shell links non-SSOT symbol"; exit 1;
}
```

> **D116 binding**: 第 1 条 `cargo geiger --lib` 在 Phase 0 Shell 上下文是 broken audit——`#[no_std] #[no_main] fn shell_main()` 是 `bin` target,`--lib` 跳过它,unsafe 块零审计。`--all-targets` 与 `cargo build --all-targets` 语义一致,覆盖 lib + bin + integration tests。CI 时间增量 < 30s。

## Three layers of defense

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Compile-time (D97)                                  │
│   - cargo-geiger 0 unsafe                                    │
│   - Zig opaque types (cannot construct from Rust)           │
│   - #[repr(C)] only on D74-generated structs                 │
├─────────────────────────────────────────────────────────────┤
│ Layer 2: Linker (D31)                                        │
│   - .text.shell segment, NX on .rodata                       │
│   - Linker script enforces segment boundaries               │
│   - 4KB alignment for any cross-segment pointer             │
├─────────────────────────────────────────────────────────────┤
│ Layer 3: Runtime (D82)                                       │
│   - HLCB.in_kernel_space flag (Shell = false initially)     │
│   - Call Gate flips the flag on entry, clears on exit       │
│   - Panic handler (D76) checks flag to decide panic source  │
└─────────────────────────────────────────────────────────────┘
```

## Phase 0 vs Phase 1 (D55 API stability)

| Aspect | Phase 0 (Shell) | Phase 1 (Shell) |
|--------|-----------------|-----------------|
| Privilege | S-Mode co-resident | U-Mode (PTE sandbox) |
| Audit | D97 compile-time | D97 + hardware PTE |
| Unsafe blocks | 0 (D97 hard constraint) | 0 (D97 still applies) |
| Call Gate | D62/D73 (no sscratch) | ecall → OpenSBI medeleg → S-Mode 直接 (不经 M-Mode) |
| Stack | Shared 16KB Hart-Local | Separate per Hart + U-Mode trap stack |
| API | `syscall6` register ABI | `syscall6` register ABI (identical) |

The user-facing API is **unchanged across phases** (D55). The implementation underneath changes, but the C/Rust source code in Shell does not.

> **P3-10 (R47 勘误)**: Phase 1 "ecall → M-Mode → S-Mode" 表述错误。OpenSBI 默认 `medeleg` 把 U-Mode ecall 委托给 S-Mode 直接处理 (RISC-V Privileged Spec §3.1.8), 不经 M-Mode。Phase 1 实际路径: <!-- gate-exempt: D168 -->
> `U-Mode ecall` → `medeleg[bit 8]` 命中 → `scause=8` 落到 S-Mode trap_entry → Call Gate 派发。无需绕 M-Mode, 也省 50–100 cycle SBI tax (D21)。

## Shell example (skeleton)

```rust
// arch/riscv64/shell/src/main.rs
#![no_std]
#![no_main]

// D97: 0 unsafe (除必要的 FFI 桥接)
use cortix_kernel::{
    abi::{sys_result_t, sys_call},
    scheme::{open, read, write, close},
};

// R48 勘误增补: shell_io_pool 由 build/link.zig 在 boot 期从 BlockPool
//   划分 (1 BlockPool 块 = 1536B, D57 三层不变式锁定), 符号由链接脚本导出.
//   P2-4 已显式标注 caller 栈缓冲跨 FFI 是错例 (典型形态即 512B 栈数组),
//   见 14 § "FFI ownership (D103 + P2-4 放宽 source 例外)" WRONG 历史错例.
extern "C" {
    static mut __shell_io_pool: [u8; 1536];  // build/link.zig 派生, 1 BlockPool 块
}

#[no_mangle]
pub extern "C" fn shell_main() -> ! {
    // D4: scheme://[node]/path position-transparent request (path 来自 .rodata 字面量)
    let fd = open(b"scheme://0/initrd/motd\0", 0);
    // D103 + P2-4: buf 必须来自静态池, 禁止 caller 栈缓冲
    let buf: &mut [u8] = unsafe { &mut __shell_io_pool };
    let n = read(fd, buf);
    write(1, &buf[..n as usize]);  // stdout
    close(fd);

    loop { syscall_yield(); }
}
```

### Shell I/O pool 划分说明 (R48 勘误增补)

`__shell_io_pool` 由 build/link.zig 在 boot 期从 BlockPool (D29 + D45 sparse) 划分出 **1 块 (1536 B)** 作为 Shell 全局 I/O 缓冲。该符号在链接脚本中导出 `.bss.shell_io_pool` 段, Shell 在编译期看到的是零大小 extern 声明, 由链接器在最终 ELF 中补全物理地址与容量。Shell 单线程使用, 无并发安全顾虑; 若 Phase 1+ Shell 改多线程, 需进一步按 fd 划分 pool (D103 红线, 详见 14 § FFI ownership 表)。

## Forbidden third-party loading (D97)

Phase 0 strictly forbids:
- `dlopen` of any `.so` file at runtime
- JIT compilation of user code
- `mmap` of file-backed executable pages
- Inline assembly that bypasses Call Gate

All Shell code must be statically linked at build time.

## Cross-references

- **Call Gate** (05): the only entry Shell uses to invoke kernel
- **ABI Contract** (04): the 16B `sys_result_t` returned to Shell
- **Documentation Gate** §二十.7: see gate catalog for forbidden phrases (R28 D97)
- **Error Handling** (10): `sys_result_t.is_error` propagation back to Shell

## Verification

- `make audit-shell` — runs all 4 audit checks above
- `make test-phase0-shell` — boots a minimal Shell in QEMU, prints motd, halts
- `make test-no-a-ext` — Shell works on RV64IMAC (D87)
