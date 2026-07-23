/* kernel/hal/c/sbi.h — SBI 接口声明 (D76/D88/D117) */
#ifndef KERNEL_HAL_C_SBI_H
#define KERNEL_HAL_C_SBI_H

#include <stdint.h>

/* D88: SBI Legacy Console Putchar */
void sbi_console_putchar(int ch);
void early_console_init(void);
void early_console_puts(const char *s);
void early_console_put_uint(uint32_t v);

/* D137: 16550 UART (dev://uart0) */
void uart0_init(void);
void uart0_putc(char c);
void uart0_puts(const char *s);

/* D76: panic 唯一入口 */
void cosmo_panic_abort(const char *file, int line, const char *msg) __attribute__((noreturn));

#endif /* KERNEL_HAL_C_SBI_H */
