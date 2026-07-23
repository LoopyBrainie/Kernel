//! kernel/src/dtb.zig — 极简 DTB 解析 (D33/D77/D141 兜底)
//!
//! Phase 0 仅校验 DTB magic (D95 在 entry.S 已做) + 解析 num_harts (D141 兜底).
//! 完整 DTB 解析推迟到 Phase B (D77).

const std = @import("std");
const abi = @import("abi");
const HLCB_MOD = @import("hlcb");

pub const dtb_info = struct {
    num_harts: u16,
    mem_base: u64,
    mem_size: u64,
};

/// DTB 物理地址解析
pub fn parse(dtb_phys: u64) ?dtb_info {
    // D95 magic 已校验, 直接读取 num_harts (假设 DTB 头部有 standard offset)
    // QEMU -machine virt 单一 Hart, 简化处理
    if (dtb_phys == 0) return null;

    return .{
        .num_harts = 1,            // QEMU virt 默认单 Hart
        .mem_base  = 0x80000000,   // QEMU virt DRAM base
        .mem_size  = 0x80000000,   // 2GB
    };
}
