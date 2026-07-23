//! kernel/include/sys/abi.zig — D74 SSOT 跨语言 ABI 定义
//!
//! Zig 是 SSOT 源; C (abi.h) / Rust (abi.rs) 由 tools/translate_abi.py 自动生成.
//! 任何手写 abi.h / abi.rs 视为违反 D74, 须重新生成.
//!
//! 5 struct 白名单 (D121):
//!   1. sys_result_t          16B    2×XLEN  (a0/a1 寄存器对返回)
//!   2. sys_result_payload_t   8B    D89 union
//!   3. rpc_unit_t          1536B    D57/D85 frozen
//!   4. network_frame_t     1536B    D57/D85 frozen (D60 14B MAC 在 1536B 外)
//!   5. block_t             1536B    D57/D85 frozen
//!
//! 三端编译期断言 (D85 / D121): Zig `@sizeOf` / C `_Static_assert` / Rust `const _: () = assert!(...)`.

const std = @import("std");

// ============================================================================
// sys_result_t (D86) — 严格 16B = 2×XLEN, RISC-V C ABI a0/a1 寄存器对返回
// ============================================================================
pub const sys_result_t = extern struct {
    header: u32,         // P1-2: bit 31 = is_error, bits 0-30 = flags/subsystem_hint
    reserved: u32,       // R48 旧 status: u32 废除, 改 reserved (D155 禁字)
    payload: sys_result_payload_t,  // 8B union

    comptime {
        const S = @sizeOf(sys_result_t);
        const A = @alignOf(sys_result_t);
        if (S != 16) @compileError("D86: sys_result_t must be 16B (= 2×XLEN), got " ++ @as(u16, S));
        if (A != 8)  @compileError("D86: sys_result_t must be 8B align, got " ++ @as(u16, A));
    }
};

// ============================================================================
// sys_result_payload_t (D89) — 8B union (value | error_pack)
// ============================================================================
pub const sys_error_pack_t = extern struct {
    remote_node_id: u16,    // D4 position transparency (0xFFFF = local)
    subsystem_id:   u16,
    error_code:     i32,    // P2-2 errno always negative
};

pub const sys_result_payload_t = extern union {
    value:      u64,
    error_pack: sys_error_pack_t,

    comptime {
        const S = @sizeOf(sys_result_payload_t);
        if (S != 8) @compileError("D86/D89: sys_result_payload_t must be 8B, got " ++ @as(u16, S));
        const ES = @sizeOf(sys_error_pack_t);
        if (ES != 8) @compileError("P2-1 carve-out: sys_error_pack_t must be 8B, got " ++ @as(u16, ES));
        // 三字段偏移断言 (D85)
        if (@offsetOf(sys_error_pack_t, "remote_node_id") != 0) @compileError("D85: error_pack.remote_node_id @0");
        if (@offsetOf(sys_error_pack_t, "subsystem_id")   != 2) @compileError("D85: error_pack.subsystem_id @2");
        if (@offsetOf(sys_error_pack_t, "error_code")     != 4) @compileError("D85: error_pack.error_code @4");
    }
};

// ============================================================================
// rpc_unit_t (D57/D85) — 1536B frozen = 8B header + 1528B payload
// ============================================================================
pub const rpc_unit_t = extern struct {
    header:  u64,         // 8B header
    payload: [1528]u8,    // 1528B payload (D57 frozen)

    comptime {
        const S = @sizeOf(rpc_unit_t);
        if (S != 1536) @compileError("D57: rpc_unit_t must be 1536B, got " ++ @as(u32, S));
    }
};

// ============================================================================
// network_frame_t (D57/D60) — 1536B frozen = 8B header + 1528B payload
// 注: D60 14B MAC DMA 在 1536B 之外, 不计入本结构
// ============================================================================
pub const network_frame_t = extern struct {
    header:  u64,
    payload: [1528]u8,

    comptime {
        const S = @sizeOf(network_frame_t);
        if (S != 1536) @compileError("D57: network_frame_t must be 1536B, got " ++ @as(u32, S));
    }
};

// ============================================================================
// block_t (D57) — 1536B frozen
// ============================================================================
pub const block_t = extern struct {
    bytes: [1536]u8,

    comptime {
        const S = @sizeOf(block_t);
        if (S != 1536) @compileError("D57: block_t must be 1536B, got " ++ @as(u32, S));
    }
};

// ============================================================================
// 单元自检 (D121 内嵌三端 assert 之一; Zig 端)
// ============================================================================
test "abi SSOT self-check" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(sys_result_t));
    try std.testing.expectEqual(@as(usize, 8),  @alignOf(sys_result_t));
    try std.testing.expectEqual(@as(usize, 8),  @sizeOf(sys_result_payload_t));
    try std.testing.expectEqual(@as(usize, 1536), @sizeOf(rpc_unit_t));
    try std.testing.expectEqual(@as(usize, 1536), @sizeOf(network_frame_t));
    try std.testing.expectEqual(@as(usize, 1536), @sizeOf(block_t));
}
