/* kernel/hal/c/cosmo_panic.c — D76 panic 唯一入口 (fail-stop)
 *
 * R39 D139: 多通道冗余 (UART + SBI console) + 物理停机 (SBI SRST).
 * 一旦进入, 不返回, 不重试.
 */

#include <stdint.h>

#include "sys/abi.h"

/* D88: SBI Console Putchar (Legacy 0x01) — 即使 DTB 损坏仍可用 */
static inline void sbi_console_putchar(int ch) {
    register uintptr_t a0 __asm__("a0") = (uintptr_t)ch;
    register uintptr_t a7 __asm__("a7") = 0x01;       /* Legacy: Console Putchar */
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a7) : "memory");
}

/* D117: SBI System Reset (Extension 0x53525354 "SRST") */
static inline void sbi_srst_system_reset(uint32_t type, uint32_t reason) {
    register uintptr_t a0 __asm__("a0") = type;
    register uintptr_t a1 __asm__("a1") = reason;
    register uintptr_t a6 __asm__("a6") = 0;          /* SBI_SRST_SYSTEM_RESET */
    register uintptr_t a7 __asm__("a7") = 0x53525354; /* SBI_EXT_SRST */
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a1), "r"(a6), "r"(a7) : "memory");
}

static void panic_puts(const char *s) {
    while (*s) {
        sbi_console_putchar((unsigned char)*s);
        s++;
    }
}

static void panic_put_u32(uint32_t v) {
    char buf[10];
    int i = 10;
    buf[--i] = 0;
    if (v == 0) {
        sbi_console_putchar('0');
        return;
    }
    while (v > 0 && i > 0) {
        buf[--i] = '0' + (v % 10);
        v /= 10;
    }
    while (buf[i]) sbi_console_putchar(buf[i++]);
}

__attribute__((noreturn))
void cosmo_panic_abort(const char *file, int line, const char *msg) {
    /* D76: 唯一 panic 入口, 多通道冗余 */
    panic_puts("[PANIC] ");
    if (file) panic_puts(file);
    panic_puts(":");
    panic_put_u32((uint32_t)line);
    panic_puts(" ");
    if (msg) panic_puts(msg);
    panic_puts("\n");

    /* D117: 物理停机 (fail-stop) */
    sbi_srst_system_reset(0, 1);   /* type=system_reset, reason=System Failure */
    __builtin_unreachable();
}
