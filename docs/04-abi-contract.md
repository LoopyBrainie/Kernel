# 04 · ABI Contract

**Plan section**: §四 + §1.25-1.30 (R25-R29 cross-language defense)
**Key decisions**: D1, D56, D57, D62, D70, D74, D85, D86, D89, D90, D101
**Status**: Frozen; locked across 5 audit rounds (R25-R30)

---

## Overview

The Wriggly-Octopus ABI is a five-layer defense that guarantees a 16-byte `sys_result_t` and a 1536-byte `RpcUnit` survive all of: per-language compiler drift, post-build ELF drift, and host Profile switching. The layers are: (1) Zig SSOT auto-generates Rust/C, (2) per-end `offsetof` assertions, (3) end-entry size+align melt-down, (4) all-primitive-int red line, (5) Post-Build ELF physical-size gate.

## Five-layer defense (D74 → D101)

| Layer | Decision | Mechanism | When |
|-------|----------|-----------|------|
| **L1** | D74 SSOT | build.zig `translate-abi` step emits Rust/C from Zig | Compile-time (code generation) |
| **L2** | D85 offsetof | `offsetof(field) == constant` asserted in all three languages | Compile-time (per-end) |
| **L3** | D86 强化 | `_Static_assert` (C), `const _: () = assert!(...)` (Rust), `comptime assert` (Zig) at every ABI entry | Compile-time (entry file) |
| **L4** | D90 全裸整型 | Cross-language structs use only `u8/u16/u32/u64 + [u8; N]`; no `Option<T>`, no `enum`, no nested struct | Compile-time (type system) |
| **L5** | D101 链接后置 | `check_elf_sizes.sh` runs after `build install`; reads final ELF and verifies 5 critical struct sizes | Post-build (linker output) |

## Core data shapes (frozen)

### `sys_result_t` (16 B, 8-byte aligned)

```zig
// §四 Zig SSOT
pub const sys_result_t = extern struct {
    header: u32,    // is_error (bit 31) + flags (bits 0-30)
    reserved: u32,  // reserved for future flag expansion
    payload: sys_result_payload_t,  // 8 B
};
```

- **RISC-V C ABI red line**: size MUST equal 16, else the compiler falls back to stack-passed pointer in `a0` and breaks D56's `lateout("a0"/"a1")` capture. Enforced by L3 (`@sizeOf == 16`) and L5 (ELF size gate).

---

## D146 增补 (R43 Q61): RpcUnit align profile-aware — 修复 Server cache line 跨行

> **回链**: R43 审计新增 D146, D48 cache line 64B Embedded vs 128B Server 与 D71 RpcUnit align(64) 错配。

### 问题与动机

D48: Server Profile cache line = 128B, Embedded = 64B。
D71: RpcUnit align(64) 统一。

**数学复核** (R43 元规则五):
- 1536B = 12 × 128B (Server, 整除) = 24 × 64B (Embedded, 整除)
- RpcUnit 起始地址 mod 64 = 0 (D71 强制): Embedded Profile 64B cache line 命中 ✓
- **Server Profile**: 起始 mod 128 = 64 mod 128 = 64 ≠ 0 → RpcUnit 跨越两个 cache line → 命中率减半

### D146 立法

D71 拆为 profile-aware align, Server Profile 显式 align(128):

```zig
pub const rpc_align: u16 = switch (build_options.profile) {
    .embedded_sparse, .embedded_compact => 64,
    .server_sparse, .server_compact       => 128,
};
comptime {
    std.debug.assert(@sizeOf(rpc_unit_t) % rpc_align == 0);  // 1536 mod 128 = 0 ✓
}
```

**传染面**: `13-build-pipeline.md` build_options.rpc_align 派生 + `15-phase0-mvp.md` T1.2 升级 + `20-documentation-gate.md` 新增禁词 "RpcUnit align 统一 64B"。 <!-- gate-exempt: D146 -->
- `16-profile-matrix.md` (R50 D160 索引) — RpcUnit align (D71) / cache line profile (D48) 跨 profile 对照见矩阵 doc
- **Header field bit-layout** (R25 D86/D89):
  - bit 31: `is_error` (0 = success, 1 = failure)
  - bits 16-30: `subsystem_hint` (top subsystem for fast path)
  - bits 0-15: `flags` (e.g. blocking, retry)

### `sys_result_payload_t` (8 B, 8-byte aligned)

```zig
pub const sys_result_payload_t = extern union {
    value: u64,                 // D56 success: fd, block id, length
    error_pack: extern struct { // Q22 closure (D89)
        remote_node_id: u16,    // 0xFFFF = local
        subsystem_id: u16,      // SUB_KERNEL / SUB_FILE_SERVICE / ...
        error_code: i32,        // POSIX-compatible negative
    },
};
```

### `RpcUnit` = `NetworkFrame` = `block_t` (1536 B)

| Field | Size | Notes |
|-------|------|-------|
| `header` | 8 B | magic + type + flags + sequence |
| `payload` | 1528 B | Zero-copy carrier |

D85 enforces `offsetof(header.magic) == 0`, etc.; D101 verifies `sizeOf == 1536` in final ELF.

## D108/Q24 落地约束: network_frame_t.ip_family 字段冻结

`network_frame_t` 在 D108 修复后增加 `ip_family: u8` 字段:

```zig
pub const network_frame_t = extern struct {
    header: frame_header_t,    // 8B
    ip_family: u8,             // 1B  D108: 1=v4, 2=v6 (Phase 0 起冻结编码)
    _reserved0: [7]u8,         // 7B  align padding
    payload: [u8; 1520],       // 1520B
};
comptime {
    std.debug.assert(@sizeOf(network_frame_t) == 1536);  // D74 + D85
    std.debug.assert(@offsetOf(network_frame_t, "ip_family") == 8);  // D85
}
```

**冻结条款 (Binding Freeze)**:
- `ip_family` 字段偏移 (`offsetOf == 8`) 从 Phase 0 起**永久冻结**
- 编码语义 `1 = IPv4, 2 = IPv6, 0 = 未指定` 永久冻结
- Phase 1+ 双栈实现可读取该字段决定 per-route `SHIM_PAYLOAD_MAX`,但**不得改动偏移与编码**
- 若 Phase 1+ 需要新协议族(如 IPsec),必须新增独立字段,不得复用 `ip_family`

`make audit-ip-family` 在 CI 静态扫描,确保 `network_frame_t.ip_family` 字段在 D74 SSOT 生成的 Rust/C/Zig 三端 ABI 完全一致。

## Three-end assert templates (D86 强化 + P1-2 sys_result_t 形态统一)

P1-2: 全库 sys_result_t 统一为 `{header: u32, reserved: u32, payload: union{value: u64 | error_pack}}` 形态 (04 "Core data shapes (frozen)"、10、14示例所用)。
**旧形态** `{code:u32, status:u32, value:u64}` **列为禁词** (D86 + P1-2), 任何文档残留字面量必须在 R47 勘误增补中消除。`res.code` / `res.status` 字段名一律改为 `res.header` (bit 31 = is_error), `res.is_error` 不存在 (改 `res.header & (1<<31)` 判定)。

```c
// basal/include/sys/abi.h (D86 + D89 + P1-2 canonical)
#include <stdint.h>

/* P2-1 D90 carve-out: error_pack 是 union 内单层 scalar-only struct, 唯一豁免 */
typedef union {
    uint64_t value;
    struct __attribute__((packed)) {
        uint16_t remote_node_id;   // D4 position transparency (0xFFFF = local)
        uint16_t subsystem_id;
        int32_t  error_code;       // D89 + P2-2: errno always negative
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

```rust
// arch/riscv64/abi.rs (D74 auto-generated)
#[repr(C, align(8))]
pub union sys_result_payload_t {
    pub value: u64,
    pub error_pack: sys_error_pack_t, // P1-2 + P2-1 D90 carve-out: 唯一豁免
}
#[repr(C, packed)]
pub struct sys_error_pack_t { pub remote_node_id: u16, pub subsystem_id: u16, pub error_code: i32 }
const _: () = {
    assert!(core::mem::size_of::<sys_result_payload_t>() == 8);
    assert!(core::mem::size_of::<sys_error_pack_t>() == 8);
};

#[repr(C, align(8))]
pub struct sys_result_t { pub header: u32, pub reserved: u32, pub payload: sys_result_payload_t }
const _: () = {
    assert!(core::mem::size_of::<sys_result_t>() == 16);
    assert!(core::mem::align_of::<sys_result_t>() == 8);
};
```

```zig
// basal/include/sys/abi.zig (SSOT, R48 勘误增补: 与同文件 C/Rust frozen 形态一致)
//   旧三字段 (code/status/value) 形态已被 P1-2 废弃, 详见 04 § "Three-end assert templates"
pub const sys_result_t = extern struct {
    header: u32,    // P1-2: bit 31 = is_error (D89), bits 0-30 = flags/subsystem_hint
    reserved: u32,  // P1-2: reserved for future flag expansion
    payload: sys_result_payload_t,  // 8B union{value: u64 | error_pack}
};

pub const sys_result_payload_t = extern union {
    value: u64,                 // D56 success: fd, block id, length
    error_pack: extern struct { // Q22 closure (D89)
        remote_node_id: u16,    // 0xFFFF = local
        subsystem_id: u16,      // SUB_KERNEL / SUB_FILE_SERVICE / ...
        error_code: i32,        // POSIX-compatible negative
    },
};

comptime {
    std.debug.assert(@sizeOf(sys_result_t) == 16);
    std.debug.assert(@alignOf(sys_result_t) == 8);
    std.debug.assert(@offsetOf(sys_result_t, "payload") == 8);
    std.debug.assert(@sizeOf(sys_result_payload_t) == 8);
    std.debug.assert(@alignOf(sys_result_payload_t) == 8);
}
```

## Cross-references

- **Call Gate** (D56): uses `a0`/`a1` register pair assuming 16 B — 16B red line is non-negotiable
- **Q22 closure** (D89): error_pack is the only legal way to extend error info; cannot add fields to header
- **Bit 31 adaptive** (D91): orthogonal — operates on `error_code` within payload, not on header
- **D74 SSOT** (this is L1 of the five-layer defense)

## D121: SSOT 白名单 5 struct (R35 补强, D125 落地约束 ② 回链)

**回链**: 本节为 4 Pillars 之 Pillar 1 实现细节, 红线条目权威入口 `00-ffi-pillars.md` § Pillar 1。

D74 SSOT 白名单 Phase 0 冻结, 仅 5 struct 由 `translate-abi.py` 自动生成:

| 白名单 struct | size | SSOT 文件 |
|---------------|------|-----------|
| `sys_result_t` | 16B | `basal/include/sys/abi.zig` |
| `sys_result_payload_t` | 8B | `basal/include/sys/abi.zig` |
| `RpcUnit` | 1536B | `basal/include/sys/abi.zig` |
| `NetworkFrame` | 1536B | `basal/include/sys/abi.zig` |
| `block_t` | 1536B | `basal/include/sys/abi.zig` |

**D121 落地约束 ② (R35 补强)**: 白名单外类型必须手写 + 内嵌三端编译期断言块 (size/align/offset)。手写 + 无断言 = 熔断。

**D121 落地约束 ①**: 白名单 Phase 0 冻结, 新增条目必须挂决策号, 禁止静默扩展。

**R53 D165 回链 (命名法 SSOT 互不冲突)**: 本节 D121 5 struct (`sys_result_t` / `sys_result_payload_t` / `RpcUnit` / `NetworkFrame` / `block_t`) 在 `docs/` 任何位置出现时不得携带 `neura_` / `basal_` / `cortix_` / `synapse_` 任一前缀字面串 (D165 反向锚定, Linux 内核惯例)。FFI 规则决定 *什么能跨语言传*, 命名 SSOT 决定 *类型/函数叫什么*, 两者正交。详见 `docs/00-naming-taxonomy.md` § 3 (D165 跨语言无前缀规则)。

**5-Layer Defense L1 描述重写** (D121 补强):
- 旧 L1: "SSOT auto-generation" — 有 L1 漏检风险 (手写文件未覆盖)
- 新 L1: "SSOT diff (白名单 5 struct) ∪ compile-time assert (全体跨三端类型)" — 双道防御网, 消除「L1 有洞」模糊表述

**Handwritten 头文件 marker** (D121 落地约束 ②): call_gate.h / `basal_atomic_cas_ptr.h` 等手写文件头部加 `/* HANDWRITTEN: tri-end asserts embedded */`, doc-gate `make audit-marker-assert-cooccur` 机检 marker 与三端 assert 块共现。

## Build pipeline integration

```bash
# zig build install → check_elf_sizes.sh
build/host/bin/check_elf_sizes.sh  # L5 硬熔断
# expected: 5 struct sizes verified
#   sys_result_t:16, sys_result_payload_t:8, rpc_unit_t:1536,
#   network_frame_t:1536, block_t:1536
```

## Failure modes

| Trigger | Layer that catches it | Failure scenario |
|---------|----------------------|------------------|
| Rust `Option<NonZeroU32>` replaces `u32` | L4 | `sizeOf != 16` → L3熔断 |
| Zig field reordering by `@optimizeMode` | L2 | `offsetof(magic) != 0` → L3熔断 |
| Host Profile 64 B → 128 B Cache Line | L5 | ELF size == 1536 unchanged (size-equal, only align-equal) |
| Cross-language `union` size drift | L4+L5 | size mismatch → 编译期 + 链接后双重熔断 |
