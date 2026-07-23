/* kernel/hal/c/early_console.c — D88 early_console SBI Stub (DTB-less)
 *
 * 优先用 OpenSBI sbi_console_putchar (Legacy 0x01), 不依赖 DTB.
 * DTB 损坏时仍能输出 panic / boot 标记.
 */

#include <stdint.h>
#include <stddef.h>

/* SBI Legacy Console Putchar */
void sbi_console_putchar(int ch) {
    register uintptr_t a0 __asm__("a0") = (uintptr_t)(unsigned char)ch;
    register uintptr_t a7 __asm__("a7") = 0x01;        /* Legacy: Console Putchar */
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a7) : "memory");
}

void early_console_init(void) {
    /* D88: no-op, SBI 永远在 */
}

void early_console_puts(const char *s) {
    if (!s) return;
    while (*s) {
        sbi_console_putchar((unsigned char)*s);
        s++;
    }
}

void early_console_put_uint(uint32_t v) {
    char buf[11];
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
