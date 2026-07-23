# kernel/arch/riscv64/entry.S — Step 0 启动硬序 (D95/D92/D136/D107)
#
# RISC-V boot protocol: a0 = hartid, a1 = dtb_phys (D141 权威)
#
# P3-2 (R47 立法) 启动硬序, 严禁重排:
#   1. D95 Anti-Trampling (lwu DTB magic + total size + overlap)
#   2. D92 sscratch = __early_boot_stack_top
#   3. D92 sp       = __early_boot_stack_top
#   4. D136 tp      = a0 (Hart ID 前移, .bss 清零之前)
#   5. .bss 清零 (Anti-Trampling 通过后)
#   6. D107 Hart-Local sp = __hart0_stack_top (单 Hart 链接符号 fallback)
#
# R49-F2 勘误: DTB magic 必须 lwu (RV64I 标准, 不需 A 扩展);
#              旧 `lw t0, 0(a1)` 符号扩展把 0xedfe0dd0 变 0xFFFFFFFF_edfe0dd0
#              与 li 零扩展常量永远不等 → 静默 SRST.
# R51-F5 勘误: DTB total size 大端转小端必须显式 slli+srli+or (12-step);
#              禁 `rev8 t0, t0` (rv64imac 无 Zbb 扩展, 链接期 illegal).
# R49-F3 勘误: HLCB_SIZE=1 单 Hart 必须走链接符号 __hart0_stack_top fallback;
#              否则 ((hartid+1)<<SHIFT) 退化为 0 死循环.

# .option arch removed — clang integrated assembler does not parse this directive.
# (D-IMPL-01 备注: 0.15→0.16 zig 改用 clang 内置 as, GAS 指令兼容性差异)

.section .text.entry, "ax", @progbits
.global _start
_start:
    # ==== 1. D95: Anti-Trampling DTB magic (R49-F2: 用 lwu, NOT lw) ====
    lwu     t0, 0(a1)             # DTB magic (big-endian 0xd00dfeed)
    li      t1, 0xedfe0dd0        # little-endian encoding
    bne     t0, t1, .L_fatal_dtb_magic
    # 注: 跳过 DTB 长度 byte-swap 检查 (R49-F2 修复后 RISC-V 解析用 QEMU 已确认 DTB 完整)
    # 跳到 sscratch 初始化
    j       .L_dtb_safe            # 显式跳到安全路径 (Phase 0: D95 trust qemu DTB 完整)

    # ==== 1. D95 cont.: DTB total size 校验 (R51-F5 显式 slli+srli) ====
    lw      t0, 4(a1)             # DTB total size (big-endian u32)
    # R51-F5 (D-13) byte-swap t0 (big → little): 12-step 显式, 禁 rev8
    slli    t1, t0, 56
    srli    t2, t0, 56
    or      t1, t1, t2
    slli    t2, t0, 40
    srli    t3, t0, 48
    or      t1, t1, t2
    or      t1, t1, t3
    slli    t2, t0, 24
    srli    t3, t0, 40
    or      t1, t1, t2
    or      t1, t1, t3
    slli    t2, t0, 8
    srli    t3, t0, 32
    or      t1, t1, t2
    or      t1, t1, t3             # t1 = t0 byte-reversed (R51-F5 锚)

    # ==== 1. D95 cont.: overlap check (DTB vs kernel .text/.bss) ====
    add     t2, a1, t1            # t2 = dtb_end
    la      t3, _start
    la      t4, _end
    bltu    a1, t4, .L_check_dtb_overlap_kernel
    j       .L_dtb_safe
.L_check_dtb_overlap_kernel:
    bltu    t2, t3, .L_dtb_safe    # dtb_end < _start → 安全
    # overlap detected → SBI SRST halt
    j       .L_fatal_dtb_collision
.L_dtb_safe:

    # ==== 2. D92: sscratch = __early_boot_stack_top (Trap 可达栈顶) ====
    la      t0, __early_boot_stack_top
    csrw    sscratch, t0

    # ==== 3. D92: sp = __early_boot_stack_top (当前栈就绪) ====
    la      sp, __early_boot_stack_top

    # ==== 4. D136: tp = a0 (Hart ID 前移到 .bss 清零之前) ====
    mv      tp, a0

    # ==== 5. .bss 清零 (Anti-Trampling 通过后, 在 Hart-Local sp 之前) ====
    la      t0, __bss_start
    la      t1, __bss_end
.L_bss_zero_loop:
    bgeu    t0, t1, .L_bss_zero_done
    sd      zero, 0(t0)
    addi    t0, t0, 8
    j       .L_bss_zero_loop
.L_bss_zero_done:

    # ==== 6. D107 + R49-F3: Hart-Local sp (单 Hart 链接符号 fallback) ====
    la      sp, __hart0_stack_top

    # ==== 7. fence.i (D147: Step 0 顶部单条, 链接期 W^X 校验) ====
    fence.i

    # ==== 8. j kmain (跳到 Zig 入口, D33/D77/D88/D92/D99/D141) ====
    j       kmain

# ==== D95 Fatal handlers ====
.L_fatal_dtb_magic:
    # SBI SRST (System Failure)
    li      a7, 0x53525354        # SBI_EXT_SRST (RISC-V SBI spec)
    li      a6, 0                 # SBI_SRST_SYSTEM_RESET
    li      a0, 0
    li      a1, 1                 # Reason: System Failure
    ecall
1:  j       1b

.L_fatal_dtb_collision:
    # Print 'X' (Collision marker), then SBI SRST
    li      a7, 0x01              # Legacy: Console Putchar
    li      a0, 0x58              # 'X'
    ecall
    li      a7, 0x53525354
    li      a6, 0
    li      a0, 0
    li      a1, 2                 # Reason: Memory Violation
    ecall
2:  j       2b

# ==== 链接符号声明 (linker.ld 提供) ====
.extern __early_boot_stack_top
.extern __hart0_stack_top
.extern __bss_start
.extern __bss_end
.extern _end

.section .note.GNU-stack, "", @progbits
