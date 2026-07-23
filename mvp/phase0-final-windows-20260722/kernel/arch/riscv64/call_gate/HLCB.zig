//! kernel/arch/riscv64/call_gate/HLCB.zig — Hart-Local Control Block (D107 per-Hart)
//!
//! R51-M5 (D-16) 勘误: 旧 HLCB.in_kernel_space 字段已删除, 改 .bss 8B
//! HartLocalControl.in_kernel (1-bit) 托管.
//!
//! 字段偏移由 build/link.zig 派生 (P1-1 binding, D107):
//!   HLCB_KERNEL_STACK_BASE = 32
//!   HLCB_KERNEL_STACK_TOP  = 40
//!   HLCB_USER_STACK_TOP    = 48
//!   HLCB_SSCRATCH_INIT     = 56 (P1-1 迁移自 R31 @32, R48 消除硬编码)

const std = @import("std");
const abi = @import("abi");

pub const HLCB_SIZE: u16 = 1;  // 单 Hart, R49-F3 边界

/// P1-1 extern struct 锁 64B layout (D107)
pub const HLCB = extern struct {
    _reserved0: [3]u64,                // 0..24 (24B padding header)
    hart_id: u16,                      // 24
    _reserved1: [6]u8,                 // 26..32 (6B pad)
    kernel_stack_base: *anyopaque,     // 32
    kernel_stack_top:  *anyopaque,     // 40
    user_stack_top:    *anyopaque,     // 48
    sscratch_initialized: u8,          // 56 (R48 迁移自 R31 @32)
    _pad_end: [7]u8,                   // 57..64

    comptime {
        const S = @sizeOf(HLCB);
        if (S != 64) @compileError("D107: HLCB must be 64B, got " ++ @as(u16, S));
        // 字段偏移断言 (与 build/link.zig asm 端同源派生)
        if (@offsetOf(HLCB, "hart_id") != 24) @compileError("D107: hart_id @24");
        if (@offsetOf(HLCB, "kernel_stack_base") != 32) @compileError("D107: kernel_stack_base @32");
        if (@offsetOf(HLCB, "kernel_stack_top")  != 40) @compileError("D107: kernel_stack_top @40");
        if (@offsetOf(HLCB, "user_stack_top")    != 48) @compileError("D107: user_stack_top @48");
        if (@offsetOf(HLCB, "sscratch_initialized") != 56) @compileError("D107: sscratch_initialized @56");
    }
};

/// HLCB 表 (单 Hart = 1 entry, D107 per-Hart 64B)
pub var hlcb_table: [HLCB_SIZE]HLCB = [_]HLCB{std.mem.zeroes(HLCB)} ** HLCB_SIZE;

/// R51-M5: HartLocalControl (.bss 8B, in_kernel 1-bit) — 替代旧 HLCB.in_kernel_space
pub const HartLocalControl = packed struct(u64) {
    in_kernel: u1,           // R51-M5: 与 R37 D128 一致, 不进 trap 热路径
    reserved: u63 = 0,
};
pub var hart_local_control: [HLCB_SIZE]HartLocalControl =
    [_]HartLocalControl{.{ .in_kernel = 0 }} ** HLCB_SIZE;
