# 10 · Error Handling (D89 sys_result_payload_t + D91 Bit 31 Adaptive)

**Plan section**: §十 + §1.25-1.30 (R25-R30)
**Key decisions**: D28, D40, D89, D91, D103
**Status**: Q22 closed R25, D91 added R26

---

## Overview

All kernel returns use the 16-byte `sys_result_t` carrying an 8-byte `sys_result_payload_t`. Errors are encoded in the low 31 bits of `error_code` (POSIX-compatible negative integers) with an optional **adaptive mode** (D91) where the high bit indicates the value is a descriptor-table index instead of a raw errno. This gives Phase 0 embedded compatibility and Phase 1+ server diagnostic richness in a single wire format.

## `sys_result_t` 16-byte layout

```
┌─────────── 16 bytes ───────────┐
│  header (u32)   │ reserved (u32)│
├────────────────────────────────┤
│  payload (8 bytes, union)      │
└────────────────────────────────┘
```

**Header field bit-layout** (D86):
- bit 31: `is_error` (0 = success, 1 = failure)
- bits 16-30: `subsystem_hint`
- bits 0-15: `flags`

**Payload union** (D89):
- On success: `value: u64` (fd, block id, length)
- On failure: `error_pack: { remote_node_id u16, subsystem_id u16, error_code i32 }`

## Q22 closure: `error_pack` (D89)

```c
typedef union {
    uint64_t value;                                // D56 success
    struct __attribute__((packed)) {
        uint16_t remote_node_id;                   // 0xFFFF = local
        uint16_t subsystem_id;                     // SUB_KERNEL etc.
        int32_t  error_code;                       // POSIX negative
    } error_pack;                                  // Q22 (D89)
} sys_result_payload_t;

_Static_assert(sizeof(sys_result_payload_t) == 8, "Q22 closure: 8B payload");
```

**Three-segment bitfield rationale**:
- `remote_node_id` (u16, 2B): D4 position transparency — fault origin Mesh node
- `subsystem_id` (u16, 2B): D9.2 + D76 — which subsystem is at fault
- `error_code` (i32, 4B): standard POSIX negative errno

**Why i32 not i64**: respects D86 8B payload red line. The D91 Bit 31 adaptive mode gives extra diagnostic info without expanding the wire format.

## D91: Bit 31 adaptive mode

```c
typedef enum {
    // Phase 0 embedded mode (Bit 31 = 0): standard errno
    SYS_OK              =     0,   // 0 is special (not negative, not Bit31)
    SYS_EPERM           =    -1,
    SYS_ENOENT          =    -2,
    SYS_EIO             =    -5,
    SYS_EBADF           =    -9,
    SYS_ENOMEM          =   -12,
    SYS_EBUSY           =   -16,
    SYS_EEXIST          =   -17,
    SYS_ENODEV          =   -19,
    SYS_EINVAL          =   -22,
    SYS_ENFILE          =   -23,
    SYS_EMFILE          =   -24,
    SYS_ENOSPC          =   -28,
    SYS_ENAMETOOLONG    =   -36,
    SYS_ENOSYS          =   -38,
    SYS_SYMLOOP         =   -40,
    SYS_ETIMEDOUT       =  -110,
    SYS_EOPENAT         =  -100,   // D72
    SYS_ETABLEFULL      =   -46,   // D46 + P2-2: errors恒为负 (Phase 0 不与 POSIX 编号撞车)
} sys_error_basic_t;

// P2-2 错误码恒负立法 (compile-time + runtime 双闸):
//   - SYS_OK = 0 是唯一非负常量; SYS_ETABLEFULL = -46 (R47 撤销旧 0x1C = 28).
//   - 编码端 make_error(): @compileError if (code > 0 && (code & (1<<30)) == 0)
//   - 解码端 D110: ① sign (负值 → 原值), ② Bit30 (descriptor), ③ packed == 0 (SYS_OK)
//   - 任何 packed > 0 且 Bit 30 = 0 都不该出现 (D110 decoder ③ raw path 视为 SYS_OK 等价)
```

When `Bit 30 == 1` (R32 D110 corrected): low 30 bits are an index into `sys_error_descriptor_table`. **Bit 31 is reserved for the sign bit of negative POSIX errnos** (R32 D110 fix; R31's "Bit 31" was a sign-bit collision — see Q26).

```c
typedef struct {
    uint16_t partition_id;       // Mesh partition
    uint16_t branch_id;          // code path
    uint32_t trace_hash;         // fault trace
} sys_error_descriptor_t;

extern const sys_error_descriptor_t sys_error_descriptor_table[1024];

// D110 R32 fix: adaptive flag at Bit 30, NOT Bit 31
#define SYS_ERROR_DESCRIPTOR_FLAG  (1U << 30)

static inline int32_t sys_error_decode(
    int32_t packed,
    sys_error_descriptor_t *out_desc
) {
    // D110: Phase 0 errno path — any negative value is a direct errno
    if (packed < 0) {
        return packed;
    }
    // D110: Phase 1+ adaptive path — Bit 30 = 1 indicates descriptor
    if ((packed & SYS_ERROR_DESCRIPTOR_FLAG) != 0) {
        uint32_t idx = (uint32_t)packed & 0x3FFFFFFF;  // 30-bit index
        if (idx >= 1024) return SYS_EINVAL;
        *out_desc = sys_error_descriptor_table[idx];
        return 0;  // 0 means "see descriptor"
    }
    // packed == 0 = SYS_OK (D86 convention)
    return packed;
}

// D110: Phase 1 descriptor packer
static inline int32_t sys_error_pack_descriptor(uint32_t idx) {
    // idx range 0..1023, Bit 30 = 1 indicates descriptor path
    return (int32_t)(SYS_ERROR_DESCRIPTOR_FLAG | (idx & 0x3FFFFFFF));
}

// D110 binding constraint: 编码端范围断言
_Static_assert(SYS_ERROR_DESCRIPTOR_FLAG == (1U << 30), "D110: Bit 30 fixed");
_Static_assert(sizeof(sys_error_descriptor_t) == 8, "D110: descriptor entry size");
#define SYS_ERROR_DESCRIPTOR_TABLE_SIZE 1024
_Static_assert(SYS_ERROR_DESCRIPTOR_TABLE_SIZE <= (1U << 30),
               "D110: descriptor table size must fit 30-bit index");

// D110 binding constraint: 范围断言成双写入(编码端 + 解码端)
static inline int32_t sys_error_decode(
    int32_t packed,
    sys_error_descriptor_t *out_desc
) {
    // D110 binding decode order, 钉死次序:
    //  ① 先判符号 (bgez) — 负值一律走 errno 路径
    if (packed < 0) {
        return packed;   // direct errno
    }
    //  ② 非负再测 Bit 30 — 置位为 descriptor index
    if ((packed & SYS_ERROR_DESCRIPTOR_FLAG) != 0) {
        uint32_t idx = (uint32_t)packed & 0x3FFFFFFF;
        // D110: 解码端范围断言
        if (idx >= SYS_ERROR_DESCRIPTOR_TABLE_SIZE) return SYS_EINVAL;
        *out_desc = sys_error_descriptor_table[idx];
        return 0;
    }
    //  ③ 其余为普通值 (packed == 0 = SYS_OK)
    return packed;
}
```

**Phase 0/1 ABI compatibility** (D110 corrected):
- Phase 0 client receives `packed < 0` → direct errno (identical to old behavior)
- Phase 1+ client can carry `packed >= 0 && (packed & Bit30) != 0` descriptor for diagnostic richness
- Old `error_code` field remains 4 bytes; no header or payload expansion
- **D110**: Bit 31 fully released to sign bit; no negative-errno misclassification

## subsystem_id mapping (D89)

```c
typedef enum {
    SUB_KERNEL         = 0x0000,
    SUB_SCHEME_ROUTER  = 0x0001,
    SUB_FILE_SERVICE   = 0x0002,
    SUB_DEV_UART       = 0x0003,
    SUB_DEV_NETWORK    = 0x0004,
    SUB_RPC_RING       = 0x0005,
    SUB_PANIC_ABORT    = 0x00FF,
} subsystem_id_t;
```

## D103: FFI ownership red line

Cross-FFI error returns MUST include `owner_subsystem_id` so the receiving side can validate the source. A result without a valid subsystem_id is a protocol violation and triggers D76 `cosmo_panic_abort`.

```zig
// Error returns must include owner (D89 + D103)
pub fn make_error(code: i32, sub: subsystem_id_t) sys_result_t {
    return sys_result_t {
        .header = @bitCast(struct { u32 is_error: 1, subsystem_hint: 15, flags: 16 }{
            .is_error = 1, .subsystem_hint = @intCast(@as(u16, @intFromEnum(sub))),
            .flags = 0,
        }),
        .payload = .{ .error_pack = .{
            .remote_node_id = 0xFFFF,
            .subsystem_id = @intFromEnum(sub),
            .error_code = code,
        }},
    };
}
```

## D28/D40: 5-step degradation (Phase 1+)

D28/D40 define a 5-step fallback when BlockPool is exhausted:
1. **Free all unpinned blocks** (D89 subsystem_id == 0)
2. **Trigger file service GC** (close idle fd)
3. **Drop in-flight RpcUnits** (only if `Pinned == false`)
4. **IPC retry queue** (defer to next tick)
5. **Hard failure**: return `SYS_ENOSPC` (Phase 1) / `cosmo_panic_abort` (Phase 0, D65 comptime assert)

Phase 0 only runs steps 1-2 at compile time (D65), runtime branches removed.

## Cross-references

- **ABI Contract** (04): 5-layer defense, L2 = `offsetof` of `error_pack` fields
- **Memory Subsystem** (09): `SYS_ENOSPC` returned by `block_alloc()`
- **Shell Architecture** (07): `is_error` propagation back to Shell
- **Documentation Gate** §二十.7: see gate catalog for forbidden phrases (R26 D91)

## Verification

- `make test-q22` — generate error with `Bit 31 = 0` and verify Phase 0 compatibility
- `make test-bit31-1` — generate error with `Bit 31 = 1` and verify descriptor lookup
- `make test-bad-subsystem` — send error with invalid subsystem_id → D76 panic

## D110: Bit 31 adaptive → Bit 30 重定位 (Q26 R32 fix)

**Status**: **RATIFIED** (Q26 → D110, R32).

**致命度**: CRITICAL。R30/R31 spec 中 D91 Bit 31 adaptive mode 与 D89 `error_code: i32` 的符号位发生**位级冲突**——所有负数 errno 的最高位都是 1,被 D91 decoder 错误地当作 descriptor-index,`idx = 0x7FFF_FFFFxx` 远超表大小 1024,统一退化为 SYS_EINVAL。结果:**整个错误返回路径只剩一种错误**,所有 `cosmo_open`/`cosmo_read`/`cosmo_write` 的失败原因在用户态全部丢失。

**核心矛盾**:

```
D89: error_code = i32 (有符号 32 位)
  SYS_EPERM       = -1    = 0xFFFFFFFF  ← Bit 31 = 1
  SYS_ENOENT      = -2    = 0xFFFFFFFE  ← Bit 31 = 1
  SYS_EIO         = -5    = 0xFFFFFFFB  ← Bit 31 = 1
  ... 全部 errno 都是负数,Bit 31 都 = 1 ...

D91 (R30/R31, broken):
  if ((packed & 0x80000000) == 0) { return packed; }   // 直接 errno
  uint32_t idx = (uint32_t)packed & 0x7FFFFFFF;        // descriptor path
  if (idx >= 1024) return SYS_EINVAL;                  // ← 每次都命中
```

**D110 修正**:

- Adaptive 标志位移至 **Bit 30**,Bit 31 释放给符号位
- Descriptor 表容量 2^30 (足够 1024)
- 完整 decoder 重写(见前文)

**Cost / Benefit**:

| Dimension | D91 (R30/R31, 致命冲突) | D110 (R32, Bit 30 重定位) |
|-----------|-------------------------|----------------------------|
| 负数 errno 路径 | ❌ 全部误判为 descriptor | ✓ 走 `if (packed < 0)` 直接返回 |
| Descriptor 容量 | 2^31 | 2^30 (仍 ≥ 1024) |
| ABI 兼容性 | 否 (errno 全失效) | ✓ Phase 0 errno 路径完全保留 |
| shell 错误诊断 | ❌ 全是 SYS_EINVAL | ✓ 真实 errno 回到用户态 |
| Phase 1 descriptor | 已存在但被淹没 | ✓ Bit 30 显式标志,不与 errno 冲突 |

**Verification**:

```bash
# R31 测试 (在 D110 修复前应当 FAIL)
make test-errno-each    # 依次返回 SYS_EPERM/ENOENT/EIO/EBADF/ENOMEM, 验证用户态收到原始 errno

# R32 新增
make test-bit30-descriptor  # Phase 1 descriptor 路径走 Bit 30 = 1
make test-bit31-signbit    # Bit 31 = 1 的负数 errno 不触发 descriptor 路径
make test-descriptor-overflow  # idx >= 1024 仍正确返回 SYS_EINVAL
```

**Why Option A (Q26) was chosen over B/C**:

- **Option B** (`error_code` 改 u32) 破坏 D89 + D86 16B ABI 红线的向后兼容,旧 Shell 编译失败 → **拒绝**
- **Option C** (移除 D91,改用 `subsystem_id` 携带 diagnostic) 失去 Phase 1 descriptor-table 优势 → **可接受但 A 更优雅**

D110 是 Q26 推荐选项 A 的实现,接受 1 位 descriptor 容量损失的代价换取位级冲突的彻底消除。
