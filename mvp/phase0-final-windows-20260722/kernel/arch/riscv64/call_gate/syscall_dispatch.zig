//! kernel/arch/riscv64/call_gate/syscall_dispatch.zig — Zig 侧 dispatcher
//!
//! 流程: cosmo_call_gate (asm) → jr t0 → __cosmo_dispatcher_ptr
//!       → 此 dispatcher → 按 a7 跳到对应 syscall handler
//!       → 返回 sys_result_t 经 a0/a1 寄存器对 (D86)
//!
//! D73: Call Gate 不碰 sscratch; D129: a7 必须 stub asm! 块内写入 (Shell 侧).
//! D103: 跨 FFI 内存流动必须锚定静态池 (Phase 0 极简: cosmo_yield + cosmo_panic 占位).
//!
//! R51-M2 (D-07) 锚点: var shim_state: ShimState = .{} 显式 .bss 零构造.

const std = @import("std");
const abi = @import("abi");
const HLCB_MOD = @import("hlcb");

/// R51-M2 ShimState 锚 (D155: 锚点变量必须 var = .{}, 禁 const)
pub const ShimState = extern struct {
    cross_driver: u32 = 0,
    padding: u32 = 0,
};
pub var shim_state: ShimState = .{};  // .bss 零构造锚点

/// D73: 全局函数指针 stub (asm 侧 cosmo_call_gate 调此)
/// 编译期不确定具体类型, 用 *allowzero opaque fn
export fn cosmo_dispatcher_trampoline() void {
    // 占位: 不应直接调, 通过 __cosmo_dispatcher_ptr 间接
    @panic("cosmo_dispatcher_trampoline called directly");
}

/// 真实 dispatcher (Shell 经 cosmo_call_gate → 此函数)
/// 注意: a0..a5 = args, a7 = syscall number, 返回 a0/a1 = sys_result_t
export fn cosmo_dispatcher(
    a0: u64, a1: u64, a2: u64, a3: u64, a4: u64, a5: u64, nr: u64,
) callconv(.c) abi.sys_result_t {
    _ = a0; _ = a1; _ = a2; _ = a3; _ = a4; _ = a5;

    // a7 / nr 解码 (D110: ① sign ② Bit30 ③ normal)
    // Phase 0 极简: 仅支持 cosmo_yield(0x10), 其余返回 ENOSYS
    if (nr == 0x10) {
        // cosmo_yield: 空操作, 返回 OK (value=0)
        return .{ .header = 0, .reserved = 0, .payload = .{ .value = 0 } };
    }

    // 默认: 错误 (header bit 31 set, error_code = -ENOSYS = -38)
    return .{
        .header   = 0x80000000,        // bit 31 = is_error
        .reserved = 0,
        .payload = .{
            .error_pack = .{
                .remote_node_id = 0xFFFF,
                .subsystem_id   = 0x0000,
                .error_code     = -38,   // -ENOSYS
            },
        },
    };
}

/// 初始化 dispatcher 函数指针 (D73: 写入 .bss __cosmo_dispatcher_ptr)
pub export fn cosmo_dispatcher_init() void {
    const ptr: *allowzero const fn (
        u64, u64, u64, u64, u64, u64, u64,
    ) callconv(.c) abi.sys_result_t = cosmo_dispatcher;
    const raw_ptr: u64 = @intFromPtr(ptr);

    // asm 侧符号 .bss.cosmo_dispatch, 写 8B
    // zig 0.16: @extern builtin 声明单变量
    const ptr_ptr = @extern(*u64, .{ .name = "__cosmo_dispatcher_ptr", .linkage = .strong });
    ptr_ptr.* = raw_ptr;
}

/// fd 表初始化 (D15: fd 0/1/2 = dev://uart0 预开)
pub export fn init_fds() void {
    // Phase 0 极简: 不维护 fd 表, 写直接走 early_console_puts / uart0_puts
}
