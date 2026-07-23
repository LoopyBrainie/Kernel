/* kernel/linker.ld — 链接脚本 (D8 medany + D81 0x80200000 + D82 HLCB + R51-M2 .bss 锚)
 *
 * 段顺序: .text.entry 在最前, 链接器不重排 _start; .text.call_gate 紧跟;
 *         .text / .rodata / .data / .bss 按 ELF 段默认序.
 * D107 HLCB 表: __hlcb_table 64B entry × MAX_HARTS (本轮单 Hart = 1).
 * Hart-Local 栈: __hart0_stack_top 在 .bss 末尾 NOLOAD 区 (D6 16KB).
 *
 * R51-M7 (D-21): strip=false 是 build.zig 选项, 本脚本保留全部符号.
 */

OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80200000, LENGTH = 8M      /* D81 锁定 0x80200000 */
}

SECTIONS
{
    /* ==== .text.entry: _start 锁第一 (D107 binding) ==== */
    .text : ALIGN(4K)
    {
        KEEP(*(.text.entry))
        *(.text.call_gate)
        *(.text .text.*)
        *(.plt)
        *(.init)
        *(.fini)
        . = ALIGN(4);
    } > RAM

    /* ==== .rodata ==== */
    .rodata : ALIGN(4K)
    {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.gcc_except_table)
        . = ALIGN(4);
    } > RAM

    /* ==== .data ==== */
    .data : ALIGN(4K)
    {
        __global_pointer$ = . + 0x800;
        *(.data .data.*)
        *(.sdata .sdata.*)
        *(.got .got.*)
        . = ALIGN(8);
    } > RAM

    /* ==== .bss (R51-M4: ≤ 8KB 上限, D157 编译期熔断) ==== */
    .bss (NOLOAD) : ALIGN(4K)
    {
        __bss_start = .;
        KEEP(*(.bss.cosmo_dispatch))                  /* R51-M2 锚点 */
        *(.bss .bss.*)
        *(.sbss .sbss.*)
        *(COMMON)
        . = ALIGN(8);
        __bss_end = .;
    } > RAM

    /* ==== HLCB 表 + 早期栈 + Hart-Local 栈 (D107/D6: 一次排齐) ==== */
    .bss.hlcb (NOLOAD) : ALIGN(64)
    {
        __hlcb_table = .;
        . += 64 * 1;                                   /* 单 Hart = 1 entry */
        . = ALIGN(16);
    } > RAM

    /* ==== D107: Step 0 启动栈 (4KB NOLOAD) ==== */
    .bss.early_stack (NOLOAD) : ALIGN(16)
    {
        __early_boot_stack_bottom = .;
        . += 4096;
        __early_boot_stack_top = .;
    } > RAM

    /* ==== Hart-Local 栈 (D6: 16KB NOLOAD) ==== */
    .bss.hart_stack (NOLOAD) : ALIGN(16)
    {
        __hart_stack_base = .;
        . += 16384;                                    /* 16KB Hart-Local 栈 */
        . = ALIGN(16);
        __hart0_stack_top = .;
    } > RAM

    /* ==== 收尾 ==== */
    . = ALIGN(4K);
    _end = .;

    /* 段累计大小导出 (R51-M4 D157 编译期熔断基础) */
    .text_size     = SIZEOF(.text);
    .rodata_size   = SIZEOF(.rodata);
    .data_size     = SIZEOF(.data);
    .bss_size      = SIZEOF(.bss);

    /DISCARD/ :
    {
        *(.comment)
        *(.note.*)
    }
}
