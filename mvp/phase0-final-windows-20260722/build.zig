//! build.zig — 单入口构建 (GOAL C2: zig build 直达 kernel.elf)
//!
//! 管线 (zig 0.16 API):
//!   Step 1: compile Zig kernel/kmain.zig + Zig HLCB.zig + Zig syscall_dispatch.zig
//!   Step 2: compile C HAL (3 files: cosmo_panic / early_console / uart0)
//!   Step 3: cargo build --release (Rust no_std Shell, riscv64gc + 软浮点)
//!   Step 4: link kernel.elf via kernel/linker.ld
//!
//! 约束: 本机 zig 0.16.0 (spec 0.15.2 — D-ENV-01 DIVERGENCE 记录)
//!       本机只装 riscv64gc rust target (D-ENV-04 走 .cargo/config.toml 软浮点)
//!       llvm 22.1.8 (D-ENV-05, R51-M6 --elf-output-style=JSON 兼容)
//!
//! 闸门: 5 个 spec gate (check-docs / check-d-backlinks / check_goal_manifest
//!        / spec_lab run_all / spec_lab run_negative) 由 bash 5.3.9 (Git Bash)
//!        跑, 见 RUNBOOK.md. 本 build.zig 仅做 elf 编译 + 段 size 软检查.

const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    // ============================================================
    // 目标: rv64imac (D138) + lp64 (软浮点), 链接基址 0x80200000 (D81)
    // zig 0.16: Abbi enum 删 lp64/lp64d; ABI 由 C flag -mabi= 控制
    // ============================================================
    const optimize: std.builtin.OptimizeMode = .ReleaseSmall;

    var query: std.Target.Query = .{
        .cpu_arch = .riscv64,
        .os_tag = .freestanding,
        .abi = .none,
    };
    query.cpu_features_add = std.Target.riscv.featureSet(&.{ .m, .a, .c });
    query.cpu_features_sub = std.Target.riscv.featureSet(&.{ .f, .d, .v });
    const target = b.resolveTargetQuery(query);

    // ============================================================
    // Step 1: SSOT 模块 (abi.zig) 编译, 供其他模块 import
    // ============================================================
    const abi_mod = b.createModule(.{
        .root_source_file = b.path("kernel/include/sys/abi.zig"),
        .target = target,
        .optimize = optimize,
    });

    const hlcb_mod = b.createModule(.{
        .root_source_file = b.path("kernel/arch/riscv64/call_gate/HLCB.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "abi", .module = abi_mod },
        },
    });

    const dtb_mod = b.createModule(.{
        .root_source_file = b.path("kernel/src/dtb.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "abi", .module = abi_mod },
            .{ .name = "hlcb", .module = hlcb_mod },
        },
    });

    const dispatch_mod = b.createModule(.{
        .root_source_file = b.path("kernel/arch/riscv64/call_gate/syscall_dispatch.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "abi", .module = abi_mod },
            .{ .name = "hlcb", .module = hlcb_mod },
        },
    });

    // ============================================================
    // Step 2: Shell (Zig 替代 Rust, D-ENV-04 处置)
    //   本机只装 riscv64gc rust target, 但 cargo 锁 ABI 跟 zig rv64imac/lp64 不兼容
    //   (rustc 忽略 target-abi override, 强制 hard-float 'd' ABI)
    //   改用 Zig shell 模块, ABI 100% 兼容, 仍过 D97 (0 unsafe) + D116 (compile-time audit)
    // ============================================================
    const shell_mod = b.createModule(.{
        .root_source_file = b.path("kernel/src/shell.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "abi", .module = abi_mod },
        },
    });

    // ============================================================
    // Step 3: kernel.elf
    // ============================================================
    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = b.createModule(.{
            .root_source_file = b.path("kernel/src/kmain.zig"),
            .target = target,
            .optimize = optimize,
            .code_model = .medium, // D8
        }),
    });
    kernel.root_module.addImport("abi", abi_mod);
    kernel.root_module.addImport("hlcb", hlcb_mod);
    kernel.root_module.addImport("dispatch", dispatch_mod);
    kernel.root_module.addImport("dtb", dtb_mod);
    kernel.root_module.addImport("shell", shell_mod);
    kernel.entry = .{ .symbol_name = "_start" };
    kernel.bundle_compiler_rt = true;
    kernel.root_module.strip = false; // R51-M7 (D-21): 保留符号供 nm/readobj

    // 汇编 (.S): 启动序 + call gate (zig 0.16: 在 root_module 上)
    kernel.root_module.addAssemblyFile(b.path("kernel/arch/riscv64/entry.S"));
    kernel.root_module.addAssemblyFile(b.path("kernel/arch/riscv64/call_gate/entry_call_gate.S"));

    // C HAL (3 文件)
    const cflags = [_][]const u8{
        "-std=gnu11",
        "-ffreestanding",
        "-fno-stack-protector",
        "-mcmodel=medany",     // D8
        "-mabi=lp64",          // D138: 软浮点
        "-march=rv64imac",     // D138: rv64imac target
        "-Wall",
        "-Wextra",
    };
    kernel.root_module.addCSourceFile(.{ .file = b.path("kernel/hal/c/early_console.c"), .flags = &cflags });
    kernel.root_module.addCSourceFile(.{ .file = b.path("kernel/hal/c/uart0.c"), .flags = &cflags });
    kernel.root_module.addCSourceFile(.{ .file = b.path("kernel/hal/c/cosmo_panic.c"), .flags = &cflags });
    kernel.root_module.addIncludePath(b.path("kernel/include"));

    // 链接脚本
    kernel.setLinkerScript(b.path("kernel/linker.ld"));

    // (D-ENV-04) Rust shell 路径已删除, 改用 Zig shell (shell_mod)

    // 安装 + 默认 install step
    const install = b.addInstallArtifact(kernel, .{});
    b.getInstallStep().dependOn(&install.step);
}
