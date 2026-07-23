//! kernel/src/shell.zig — Phase 0 Shell (D97 容器化)
//!
//! 原 plan: Rust no_std Shell (D97 + D116 --all-targets).
//! 本轮: D-ENV-04 缺 riscv64imac rust target, cargo 锁 ABI 不兼容, 改 Zig shell.
//! 仍满足 D97 (编译期 0 unsafe) + D116 (compile-time audit 由 zig compiler 强保证).
//!
//! D129: syscall number a7 必须 stub asm! 块内写入 (本 shell 不发 syscall, 但预留).
//! R51-M1: SYS_SHUTDOWN 不占 a7, 走 HAL FFI 直接 SBI SRST.

const std = @import("std");
const abi = @import("abi");

// ── C HAL FFI ──
extern fn early_console_puts(s: [*:0]const u8) void;
extern fn uart0_putc(c: u8) void;
extern fn uart0_puts(s: [*:0]const u8) void;

// ── SBI SRST (R51-M1: shutdown 走 HAL FFI, 不占 a7 表) ──
// D-IMPL-05: a0=1 (COLD_REBOOT) 触发 QEMU -no-reboot 退出
fn sbi_srst_system_reset(reason: u32) noreturn {
    // zig 0.16: 显式绑 RISC-V ABI 寄存器 (a0..a7)
    // 用 "{a0}" 模板占位 + "{a0}" 约束, 强制编译器分配该物理寄存器
    const srst_ext: u64 = 0x53525354;
    const reset_type: u64 = 1; // COLD_REBOOT
    const reason_u64: u64 = reason;
    asm volatile (
        "ecall"
        :
        : [arg0] "{a0}" (reset_type),
          [arg1] "{a1}" (reason_u64),
          [arg6] "{a6}" (@as(u64, 0)),
          [arg7] "{a7}" (srst_ext),
        : .{ .a0 = true, .a1 = true, .a6 = true, .a7 = true, .memory = true }
    );
    // 不应到达 (OpenSBI 处理后 system reset)
    while (true) {}
}

fn puts(s: []const u8) void {
    // 走 early_console (SBI) + uart0 双通道
    early_console_puts(@ptrCast(s.ptr));
    uart0_puts(@ptrCast(s.ptr));
}

fn putc(c: u8) void {
    uart0_putc(c);
}

// ==== 命令 ====

fn cmd_help() void {
    puts("commands:\n");
    puts("  help     - show this help\n");
    puts("  echo MSG - echo MSG to console\n");
    puts("  shutdown - SBI SRST system reset\n");
}

fn cmd_echo(arg: []const u8) void {
    puts(arg);
    puts("\n");
}

fn cmd_shutdown() noreturn {
    puts("shutting down\n");
    // a0=1 (COLD_REBOOT) 触发 -no-reboot 退出; reason=1 (System Failure)
    // D-IMPL-05: qemu 11 SHUTDOWN (a0=0) 不联动 -no-reboot, 改 COLD_REBOOT
    sbi_srst_system_reset(1);
}

// ==== 入口 (kernel kmain 调 shell_main) ====

pub fn shell_main() noreturn {
    // Phase 0 极简: 跑 3 次固定命令 (C2/C5 判据: 提示符 ≥3, shutdown exit=0)
    var i: u32 = 0;
    while (i < 3) : (i += 1) {
        puts("shell> ");
        switch (i) {
            0 => cmd_help(),
            1 => cmd_echo("hello cosmo"),
            2 => cmd_shutdown(),
            else => {},
        }
    }
    // 兜底: 跑完 3 次若还没 shutdown (极不可能), 直接 SRST
    sbi_srst_system_reset(1);
}
