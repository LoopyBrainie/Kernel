//! kernel/src/kmain.zig — Step 1 (D33/D77/D88/D92/D99/D141)
//!
//! entry.S 以 a0 = hartid, a1 = dtb_phys 跳入 (RISC-V boot protocol, D141 权威)

const std = @import("std");
const abi = @import("abi");
const HLCB_MOD = @import("hlcb");
const dtb = @import("dtb.zig");
const dispatch = @import("dispatch");

// ── C HAL FFI ──
extern fn early_console_init() void;
extern fn early_console_puts(s: [*:0]const u8) void;
extern fn uart0_init() void;
extern fn cosmo_panic_abort(file: [*:0]const u8, line: i32, msg: [*:0]const u8) noreturn;

// ── Zig Shell 模块 (D-ENV-04 改 Rust → Zig) ──
const shell = @import("shell");

// ── 链接器符号 ──
extern var __hart_stack_base: u8;
extern var __hart0_stack_top: u8;
extern var __bss_end: u8;

// ── L5 (D101/D113) ELF size gate 锚点符号: 白名单 5 struct 具名导出 ──
// D155 (R51-M2): 锚点变量必须 var = .{} (非 const), 落在 .bss
// 5 struct 锚点让 llvm-readobj --syms 能读到 size
export var sys_result_t: abi.sys_result_t = .{ .header = 0, .reserved = 0, .payload = .{ .value = 0 } };
export var sys_result_payload_t: abi.sys_result_payload_t = .{ .value = 0 };
export var rpc_unit_t: abi.rpc_unit_t = .{ .header = 0, .payload = [_]u8{0} ** 1528 };
export var network_frame_t: abi.network_frame_t = .{ .header = 0, .payload = [_]u8{0} ** 1528 };
export var block_t: abi.block_t = .{ .bytes = [_]u8{0} ** 1536 };

export fn kmain(hart_id: u64, dtb_phys: u64) callconv(.c) void {
    // D88: early console (SBI stub) 先行, DTB-less 可用
    early_console_init();

    // D141: a0 权威 + DTB num_harts 断言兜底
    const info = dtb.parse(dtb_phys) orelse
        cosmo_panic_abort("kmain.zig", @intCast(@src().line), "D141: DTB parse failed");
    if (hart_id >= info.num_harts)
        cosmo_panic_abort("kmain.zig", @intCast(@src().line), "D141: hart_id >= num_harts (DTB)");

    // D33/D107: 填 HLCB per-Hart 栈区间 (单 Hart: 链接符号拓扑)
    const stack_base = @intFromPtr(&__hart_stack_base);
    const stack_top = @intFromPtr(&__hart0_stack_top);
    HLCB_MOD.hlcb_table[hart_id] = .{
        ._reserved0 = .{ 0, 0, 0 },
        .hart_id = @intCast(hart_id),
        ._reserved1 = .{0} ** 6,
        .kernel_stack_base = @ptrFromInt(stack_base),
        .kernel_stack_top = @ptrFromInt(stack_top),
        .user_stack_top = @ptrFromInt(stack_top),
        .sscratch_initialized = 0,
        ._pad_end = .{0} ** 7,
    };

    // D92 Step 1: sscratch 刷新为 Hart-Local 栈顶
    asm volatile ("csrw sscratch, %[t]"
        :
        : [t] "r" (stack_top),
    );
    // D136: HLCB 就绪后落旗
    HLCB_MOD.hlcb_table[hart_id].sscratch_initialized = 1;

    // R51-M5: 托管 in_kernel 1-bit (替代旧 HLCB.in_kernel_space)
    HLCB_MOD.hart_local_control[hart_id].in_kernel = 1;

    // D88 → dev://uart0 切换 (D137: IER=0)
    uart0_init();

    // D73: 初始化 call gate 函数指针
    dispatch.cosmo_dispatcher_init();

    // D15: fd 表 (0/1/2 = dev://uart0)
    dispatch.init_fds();

    // GOAL marker (C4): OpenSBI banner 之后内核就绪标记
    early_console_puts("COSMO BOOT OK\n");

    // Step 2: application ready → Zig Shell (D97 容器化内核态, 0 unsafe)
    shell.shell_main();
}
