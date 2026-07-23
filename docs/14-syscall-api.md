# 14 · Syscall API (16B sys_result_t + FFI Ownership)

**Plan section**: §十四
**Key decisions**: D9, D22, D55, D56, D86, D89, D103
**Status**: Frozen; Phase 0/1 API identical (D55)

---

## Overview

The syscall API uses the 16-byte `sys_result_t` register pair (a0/a1) as the **only** return shape. All subsystems — file, device, scheme, IPC — return the same wire format. Cross-FFI calls obey D103 ownership rules: pointers must be pinned in static pools, never on caller stack. The API is **identical** between Phase 0 and Phase 1 (D55), so Shell code does not change when the kernel upgrades.

## sys_call register convention

```
┌──── syscall6 RISC-V C ABI ────┐
│ a7 = syscall number            │
│ a0..a5 = up to 6 args          │
│ return: a0/a1 = sys_result_t   │  (16B, locked to register pair)
└────────────────────────────────┘
```

The 16B `sys_result_t` MUST be passed via `a0`/`a1` register pair (RISC-V C ABI). If the struct grows beyond 16B, the compiler falls back to stack-passed pointer in `a0` and silently breaks D56's `lateout("a0"/"a1")` capture. This is why D86 enforces `@sizeOf == 16` as a hard melt-down.

## Syscall number map (D9)

| a7 | Subsystem | Notes |
|----|-----------|-------|
| 0x00 | `cosmo_open` | D22 v2.1 file open |
| 0x01 | `cosmo_read` | fd + buf + len |
| 0x02 | `cosmo_write` | fd + buf + len |
| 0x03 | `cosmo_close` | fd |
| 0x04 | `cosmo_seek` | fd + offset + whence |
| 0x05 | `cosmo_stat` | fd + stat buf |
| 0x10 | `cosmo_yield` | scheduler hint |
| 0x20 | `cosmo_ping` | D76 panic check |
| 0x30..0x3F | Reserved (Phase 1+) | PTE / IPC |

## FFI ownership (D103 + P2-4 放宽 source 例外)

```c
// CORRECT: path 来自 .rodata 字面量 (D86 16B 兼容: 字面量在 .rodata, 跨 FFI 安全)
sys_result_t res = cosmo_open("scheme://0/initrd/motd", O_RDONLY);

// P2-4: path 来自静态 path_pool 块 (放宽 D103, 允许 Shell 用户键入文件路径)
// 不再要求 caller 把 path 固定为 .rodata 字面量 (否则 Shell 无法打开用户键入的文件名, cat 不可实现)
char path_pool[1536];  // 静态池块 (如 BlockPool 划分出 path_pool)
strcpy(path_pool, user_input_path);  // Shell 侧 std::strcpy no_alloc
sys_result_t res = cosmo_open(path_pool, O_RDONLY);

// CORRECT: buf 来自 BlockPool (P2-4 与表 #3/#4 一致, 不再允许 caller stack buf)
char io_buf[1536];  // 静态池 (Shell 在 boot 时从 BlockPool 划出一块)
sys_result_t read_res = cosmo_read(fd, io_buf, sizeof(io_buf));

// WRONG (历史错例, P2-4 移除): "char buf[512]; // local stack for READ, OK"
// sink-only 栈缓冲在 D103 严格版本下争议大, P2-4 统一堵漏, 所有 buf 一律来自静态池

// WRONG (compiles but runtime panic):
RpcUnit *local_rpc = alloca(sizeof(RpcUnit));  // stack allocated
cosmo_rpc_send(local_rpc);  // kernel will dereference after caller returns → STACK USE AFTER RETURN
```

D103 forbids the third pattern at compile time:

```zig
comptime {
    // D103: cross-FFI signature must not allow &[u8] (stack slice)
    const open_sig = @typeInfo(@TypeOf(cosmo_open));
    for (open_sig.@"fn".params) |param| {
        if (param.type == []const u8) {
            @compileError("cross-FFI signature uses stack slice; " ++
                "use *const RpcUnit (D103) or pass by value");
        }
    }
}
```

## Scheme Router (D9)

```c
// D4: scheme://[node]/path position-transparent
sys_result_t res = cosmo_open("scheme://0/initrd/motd", O_RDONLY);
if (res.header & (1U << 31)) {  // P1-2: is_error 在 bit 31; 旧 res.is_error 已废除
    // D89 + D103: subsystem_id identifies the source
    sys_error_descriptor_t desc;
    int32_t basic = sys_error_decode(res.payload.error_pack.error_code, &desc);
    printf("Error: subsystem=0x%x code=%d partition=0x%x\n",
        res.payload.error_pack.subsystem_id,
        basic,
        desc.partition_id);  // Bit 31 = 1: see descriptor
}
```

`scheme://` is the only filesystem prefix; everything else is dev://, file://, or initrd://. The node ID in `scheme://0/` is the Mesh position (D4 = position transparency), `0xFFFF` meaning local.

## Phase 0/1 API stability (D55)

| Call | Phase 0 ABI | Phase 1 ABI | Source change? |
|------|-------------|-------------|----------------|
| `cosmo_open` | `a0=path, a1=flags, ret a0/a1` | same | No |
| `cosmo_read` | `a0=fd, a1=buf, a2=len, ret` | same | No |
| `cosmo_write` | `a0=fd, a1=buf, a2=len, ret` | same | No |
| `cosmo_close` | `a0=fd, ret` | same | No |
| `cosmo_yield` | `ret` | same | No |

Phase 1 adds new syscalls (0x30..0x3F) but does **not** change existing ones. Shell source compiles unchanged across phases.

## D119: syscall6 6-arg 寄存器红线 (Q34 R34 fix)

**Status**: **Proposed** (pending Q34 closure).

D55 Phase 0/1 API stability 列出的 5 个 syscall 均 ≤3 参数,但 syscall6 标题暗含 RISC-V C ABI a0-a5 6 寄存器。0x30..0x3F Reserved (Phase 1+ PTE/IPC) 范围**没有任何 syscall 真的用满 6 寄存器**——6-arg 跨 Phase ABI 红线未被规范。

```c
// D119 R34 fix: syscall6 6-arg 寄存器全裸整型红线
// 继承 D86 (sys_result_t 16B 返回) + D90 (全裸整型) + D103 (静态池红线)

// 允许的 6-arg syscall 签名示例:
sys_result_t cosmo_pte_map_6arg(
    u64 vaddr,           // a0  - u64 原生整型
    u64 paddr,           // a1  - u64 原生整型
    u64 flags,           // a2  - u64 原生整型
    u64 pte_perm,        // a3  - u64 原生整型
    u64 cookie,          // a4  - u64 原生整型
    u64 reserved         // a5  - u64 原生整型
);
// ret: a0/a1 = sys_result_t (D86 16B red line 锁定)

// D119 binding constraint: 编译期闸门
comptime {
    // D119 + D90: 禁止 Option<T>/enum/嵌套 struct 出现在 a0-a5 类型
    const sig = @typeInfo(@TypeOf(cosmo_pte_map_6arg));
    for (sig.@"fn".params) |param| {
        const T = param.type;
        if (T == []const u8 or T == ?*anyopaque) {
            @compileError("D119: 6-arg syscall 禁止 stack slice/optional 跨 FFI; " ++
                "用 u32/u64 整型或 *const RpcUnit 静态池 (D103)");
        }
    }
}

// D119 复杂结构体参数强制走静态池 (D103 延伸)
sys_result_t cosmo_ipc_send_6arg(
    u32 scheme_id,                  // a0  - u32
    u32 node_id,                    // a1  - u32
    u32 msg_id,                     // a2  - u32
    u32 flags,                      // a3  - u32
    *const RpcUnit payload,         // a4  - *const RpcUnit 静态池 (D103)
    u32 timeout_ms                  // a5  - u32
);
```

**Cost / Benefit**:

| Dimension | D55 R30 (无 6-arg 规范) | D119 R34 (6-arg 红线) |
|-----------|------------------------|------------------------|
| Phase 1 PTE/IPC syscall 设计 | ❌ 重新设计 6-arg ABI,易与 D86/D90/D103 冲突 | ✓ 沿用 D86/D90/D103 红线,无新概念 |
| 跨语言 FFI 一致性 | ❌ Phase 1 Rust/Zig/C 三端可能漂移 | ✓ D74 SSOT 自动生成,三端一致 |
| 寄存器宽度假设 | ❌ Phase 0 RV32 → Phase 1 RV64 漂移 | ✓ 全裸整型自然承载 u32/u64 |

**Phase 0/1 ABI 完整约束表 (D86 + D90 + D103 + D119)**:

| 维度 | 约束 | 来源 |
|------|------|------|
| 返回值 | `sys_result_t` 严格 16B,a0/a1 寄存器对 | D86 |
| 参数类型 | 仅 `u32`/`u64` 原生整型 | D90 |
| 指针参数 | 仅 `*const RpcUnit` 静态池,禁止 `&[u8]`/`*T` caller stack | D103 |
| 参数数量 | 0..6,a0..a5 寄存器 | D119 |
| Phase 跨阶段 | Phase 0/1 5 个 syscall 签名不变 | D55 |

## D119 per-syscall arity 表 (Q34 R34 落地约束 ②)

每个 syscall 的 arity 在编译期冻结,0x30..0x3F Reserved 段的预期 arity 同时声明:

| a7 (hex) | Syscall | Arity | 参数列表 (a0..a5) | 阶段 |
|----------|---------|-------|------------------|------|
| 0x00 | `cosmo_open` | 2 | path, flags | Phase 0 |
| 0x01 | `cosmo_read` | 3 | fd, buf, len | Phase 0 |
| 0x02 | `cosmo_write` | 3 | fd, buf, len | Phase 0 |
| 0x03 | `cosmo_close` | 1 | fd | Phase 0 |
| 0x04 | `cosmo_seek` | 3 | fd, offset, whence | Phase 0 |
| 0x05 | `cosmo_stat` | 2 | fd, stat_buf | Phase 0 |
| 0x10 | `cosmo_yield` | 0 | — | Phase 0 |
| 0x20 | `cosmo_ping` | 0 | — | Phase 0 |
| 0x28 | `SYS_SHUTDOWN` | 0 | — | Phase 0 不实现; Phase 1 立法; 调用必须走 typed-syscall 路径 (D154) |
| 0x29 | `SYS_FD_RESERVE` | 1 | fd | Phase 1+ 立法 (Q72 挂账); fd 0/1/2 预开 dev://uart0 |
| 0x30 | (Reserved) PTE map | 6 | vaddr, paddr, flags, pte_perm, cookie, reserved | Phase 1+ |
| 0x31 | (Reserved) PTE unmap | 4 | vaddr, len, flags, cookie | Phase 1+ |
| 0x32 | (Reserved) IPC send | 6 | scheme_id, node_id, msg_id, flags, *RpcUnit, timeout_ms | Phase 1+ |
| 0x33 | (Reserved) IPC recv | 5 | scheme_id, node_id, *RpcUnit, timeout_ms, flags | Phase 1+ |
| 0x3F | (Reserved) Last | TBD | TBD | Phase 1+ |

## D119 编译期双端断言 (Q34 R34 落地约束 ③)

```c
// D119 binding: 双端 arity ≤6 且每 arg ≤8B 编译期闸门
// Zig 端:
comptime {
    const sig = @typeInfo(@TypeOf(cosmo_pte_map_6arg));
    if (sig.@"fn".params.len > 6)
        @compileError("D119: arity > 6, syscall6 已达上限");
    for (sig.@"fn".params) |param| {
        const sz = @sizeOf(param.type);
        if (sz > 8)
            @compileError("D119: arg '" ++ @typeName(param.type) ++
                "' size > 8B (XLEN), 结构体按值传寄存器永久禁止");
    }
}

// C 端:
#define D119_ARITY_CHECK(name, n)  _Static_assert( \
    sizeof(((struct { typeof(name) __dummy; }).__dummy) == 0 ? 0 : n) <= 6, \
    "D119: arity > 6")
#define D119_ARG_SIZE_CHECK(arg)  _Static_assert(sizeof(arg) <= 8, \
    "D119: arg > 8B (XLEN), 结构体按值传寄存器永久禁止")

D119_ARITY_CHECK(cosmo_pte_map_6arg, 6);
D119_ARG_SIZE_CHECK(((cosmo_pte_map_6arg_fn)0)(0,0,0,0,0,0));  // 类型检查
```

**D119 字节序与扩展规则 (Q34 R34 落地约束 ①)**:
- 寄存器承载恰好一个 XLEN 字(8B on RV64, 4B on RV32)
- **结构体按值传寄存器永久禁止** — 大于 8B 强制 `*const RpcUnit` 静态池
- `u32` 参数零扩展至 64 位 (RISC-V ABI: a0..a5 的 32-bit 写入高 32 位为 0)
- 字节序约定: **little-endian** (RISC-V 原生, LE 特权模式默认)
- caller/callee 不得各自解释字节序,统一 D74 SSOT 生成

## Cross-references

- **Call Gate** (05): the only entry from Shell to kernel
- **ABI Contract** (04): 16B red line enforcement
- **Error Handling** (10): `sys_result_t.is_error` + `error_pack` decoding
- **Memory Subsystem** (09): BlockPool is the only legal FFI target

## D103: 17 个跨 FFI 签名表 (D125 Pillar 1 完整覆盖)

**回链**: 本节为 4 Pillars 之 Pillar 1 完整实现, 红线条目权威入口 `00-ffi-pillars.md` § Pillar 1 (D86+D90+D103+D119+D121)。

| # | 跨 FFI 签名 | D# | stack 指针? | 类型 |
|---|------------|-----|------------|------|
| 1 | `sys_call(a7, a0..a5) -> sys_result_t` | D55/D86/D90/D103/D119/D129 | ✗ | a7 由 stub asm! 块写入 (D129), 防 clobber |
| 2 | `cosmo_open(path, flags) -> sys_result_t` | D86/D90/D103/P2-4 | ✗ | path 来自 `.rodata` 字面量 **或** 静态 path_pool 块 (P2-4 放宽; 否则 Shell 无法打开用户键入文件名, cat 不可实现) |
| 3 | `cosmo_read(fd, buf, len)` | D90/D103 | ✗ | buf 来自 BlockPool (sink — kernel 写入) |
| 4 | `cosmo_write(fd, buf, len)` | D90/D103 | ✗ | buf 来自 BlockPool (source — kernel 读取) |
| 5 | `cosmo_close(fd)` | D90 | ✗ | fd 整数 |
| 6 | `cosmo_yield()` | D86 | ✗ | 无参 |
| 7 | `cosmo_ping()` | D86 | ✗ | 无参 |
| 8 | `cosmo_pte_map_6arg(vaddr, paddr, flags, pte_perm, cookie, reserved)` | D86/D90/D119 | ✗ | 全 u64 ≤ 8B |
| 9 | `cosmo_ipc_send_6arg(scheme_id, node_id, msg_id, flags, *RpcUnit, timeout_ms)` | D86/D90/D103/D119 | ✗ | *RpcUnit 静态池 |
| 10 | `basal_panic_abort(file, line, msg)` (D168, D76 SUPERSEDED) | D90 | ✗ | msg 来自 .rodata |
| 11 | `cosmo_copy_from_user(kernel_dst, user_src, len)` | D90/D103 | ✗ | kernel_dst 必须 BlockPool |
| 12 | `cosmo_copy_to_user(user_dst, kernel_src, len)` | D90/D103 | ✗ | kernel_src 必须 BlockPool |
| 13 | `cosmo_atomic_cas_ptr(dest, old, new, peer_mask) -> bool` | D90/D117 | ✗ | dest 静态池 |
| 14 | `cosmo_hal_set_next_timer(next_deadline)` | D90 | ✗ | u64 整数 |
| 15 | `cosmo_hal_fs_is_dirty(sstatus) -> bool` | D90 | ✗ | u64 整数 |
| 16 | `try_fs_lazy_init_with_dedup(sepc, scause, sstatus) -> bool` | D118/D90/D130 | ✗ | u64 + uintptr_t, D130 decoder 覆盖 0x07/0x27/0x43-0x4F 主码 |
| 17 | `basal_do_user_fault_fixup(ctx_ptr, fixup_addr)` (R54 改名, D148 锁) | D90/D112/D148 | ✗ | uintptr_t 整数, D148 SUM=0 嵌套触发 panic |

## D129: a7 syscall 号由 stub asm! 块写入 (Q44 R38)

D119 立法 a7 = syscall number, a0..a5 = up to 6 args。但 D119 没说 a7 必须**在 stub 内部**写入; 当前默认 `call basal_call_gate` 由编译器生成, 编译器可在 prologue 自由分配 a7 给临时变量, dispatcher 收到错的 syscall #。

D129 机制: stub 函数由 **纯汇编全局符号** (不导出 C/Rust 原型) 实现, asm! 块在同一函数内 `mv a7, <syscall_id>` 后 `call basal_call_gate`。这样编译器无法重排, a7 写入发生在 `call` 之前。

```rust
// D129 example: stub for cosmo_open (syscall 0x00)
// 纯汇编全局符号, 不导出 C/Rust 原型, nm 属性必须 T
#[no_mangle]
pub extern "C" fn cosmo_open_stub(path: *const u8, flags: u32) -> sys_result_t {
    let mut res: sys_result_t;
    // D129: a7 与 path/flags/res 在同一 asm! 块, 编译器不能重排
    unsafe {
        core::arch::asm!(
            "mv a7, {syscall_id}",
            "mv a0, {path}",
            "mv a1, {flags}",
            "call {dispatcher}",
            "mv {res}, a0",
            syscall_id = const 0x00,
            path = in(reg) path,
            flags = in(reg) flags,
            dispatcher = sym basal_call_gate,
            res = out(reg) res,
            clobber_abi("C"),
        );
    }
    res
}
```

**传染面清单** (R38 元规则四):
- `04-abi-contract.md` § D119 arity 表 + D129 注释 (a7 stub asm! 块保证)
- `15-phase0-mvp.md` T1.2 stub 实现升级 D129
- `20-documentation-gate.md` 新增禁词: `syscall number 隐式 a7 约定` / `7 参数 C 签名落 a7` (已入册, R38)

**编译期闸门** (R38 D129):
- `nm build/kernel.elf | awk '$3=="cosmo_open_stub" {print $2}' | grep -q '^T$'` (符号表属性必须 T)
- `objdump -d build/kernel.elf | grep -B1 'call.*basal_call_gate'` 必须前一指令为 `mv a7, ...`

**D103 binding**: 所有 17 个签名满足"参数仅 `u8/u16/u32/u64 + [u8; N]` 或 `*const T` 指向静态池", **无任何签名泄漏 caller stack 指针**。

## D119 arity 表 (回链 Pillar 2)

**回链**: 本节为 4 Pillars 之 Pillar 2 完整实现, 红线条目权威入口 `00-ffi-pillars.md` § Pillar 2 (D86+D101+D113+D119)。

| a7 (hex) | Syscall | Arity | 参数列表 (a0..a5) | 阶段 |
|----------|---------|-------|------------------|------|
| 0x00 | `cosmo_open` | 2 | path, flags | Phase 0 |
| 0x01 | `cosmo_read` | 3 | fd, buf, len | Phase 0 |
| 0x02 | `cosmo_write` | 3 | fd, buf, len | Phase 0 |
| 0x03 | `cosmo_close` | 1 | fd | Phase 0 |
| 0x04 | `cosmo_seek` | 3 | fd, offset, whence | Phase 0 |
| 0x05 | `cosmo_stat` | 2 | fd, stat_buf | Phase 0 |
| 0x10 | `cosmo_yield` | 0 | — | Phase 0 |
| 0x20 | `cosmo_ping` | 0 | — | Phase 0 |
| 0x28 | `SYS_SHUTDOWN` | 0 | — | Phase 0 不实现; Phase 1 立法; 调用必须走 typed-syscall 路径 (D154) |
| 0x29 | `SYS_FD_RESERVE` | 1 | fd | Phase 1+ 立法 (Q72 挂账); fd 0/1/2 预开 dev://uart0 |
| 0x30 | (Reserved) PTE map | 6 | vaddr, paddr, flags, pte_perm, cookie, reserved | Phase 1+ |
| 0x31 | (Reserved) PTE unmap | 4 | vaddr, len, flags, cookie | Phase 1+ |
| 0x32 | (Reserved) IPC send | 6 | scheme_id, node_id, msg_id, flags, *RpcUnit, timeout_ms | Phase 1+ |
| 0x33 | (Reserved) IPC recv | 5 | scheme_id, node_id, *RpcUnit, timeout_ms, flags | Phase 1+ |
| 0x3F | (Reserved) Last | TBD | TBD | Phase 1+ |

## Verification

- `make test-syscall-abi` — 3-end ABI gate passes for all 5 syscalls
- `make test-cross-ffi` — generate `&[u8]` argument → D103 compile error
- `make test-stack-leak` — runtime: pass stack pointer as RpcUnit → D76 panic
