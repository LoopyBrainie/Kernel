# kernel/arch/riscv64/call_gate/entry_call_gate.S — Call Gate (D56/D62/D73/D82)
#
# D73 (R21 勘误): Call Gate 不碰 sscratch, 走函数指针 __cosmo_dispatcher_ptr.
# R49-F1 勘误: 必须 `jr t0` 尾调用 (not `jalr ra, t0`), 不要保存 ra,
#              否则编译器把 ra 推到栈上 → 跨 FFI 栈指针 leak (D103 红线).
#
# 工作流:
#   1. Shell (Rust) 调 cosmo_call_gate(a7=nr, a0..a5=args)
#   2. Call Gate 取全局函数指针 __cosmo_dispatcher_ptr (C 链接 extern)
#   3. `jr t0` 尾调用 — 不存 ra, 不推栈
#   4. dispatcher 走 Zig syscall_dispatch (a7→switch), 返回 sys_result_t
#      经 a0/a1 寄存器对

# .option arch removed — clang integrated assembler (D-IMPL-01)

.section .text.call_gate, "ax", @progbits
.global cosmo_call_gate
.type cosmo_call_gate, @function
cosmo_call_gate:
    # 取全局函数指针 (D73: 不碰 sscratch)
    la      t0, __cosmo_dispatcher_ptr
    ld      t0, 0(t0)
    # R49-F1: 尾调用 jr t0 (not jalr ra, t0 — 推栈泄漏 ra)
    jr      t0
.size cosmo_call_gate, .-cosmo_call_gate

# 强符号 stub: __cosmo_dispatcher_ptr 在 .bss 段 (D155 锚点, var = .{})
# linker.ld 把此符号放到 .bss, zig dispatcher_init() 写实地址
.section .bss.cosmo_dispatch, "aw", @nobits
.global __cosmo_dispatcher_ptr
.type __cosmo_dispatcher_ptr, @object
__cosmo_dispatcher_ptr:
    .skip 8
.size __cosmo_dispatcher_ptr, .-__cosmo_dispatcher_ptr

.section .note.GNU-stack, "", @progbits
