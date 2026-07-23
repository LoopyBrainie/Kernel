/* kernel/hal/c/uart0.c — 16550 UART (D137 IER=0 关中断, dev://uart0)
 *
 * 0x10000000 是 QEMU -machine virt 的 16550 物理基址 (D137 锁定).
 * IER=0 关闭 UART 中断, 写字符不触发中断 (D137 红线).
 * Phase 0 不实现接收, 仅输出 (D88 SBI 已被 D76 panic 冗余覆盖).
 */

#include <stdint.h>

#define UART0_BASE 0x10000000UL
#define UART_THR  (*(volatile uint8_t *)(UART0_BASE + 0))    /* Transmit Holding */
#define UART_IER  (*(volatile uint8_t *)(UART0_BASE + 1))    /* Interrupt Enable */

void uart0_init(void) {
    /* D137: IER=0 关闭 UART 中断 (PLIC 桩退役, D67 严禁通用 PLIC) */
    UART_IER = 0x00;
}

void uart0_putc(char c) {
    UART_THR = (uint8_t)c;
}

void uart0_puts(const char *s) {
    if (!s) return;
    while (*s) uart0_putc(*s++);
}
