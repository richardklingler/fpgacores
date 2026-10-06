// PicoRV32 Hello: prints a line over the UART, counts on the LEDs, and does it again.
// Memory map (src/top.v): RAM 0x0000_0000 (4 KB), UART 0x1000_0000, LEDs 0x2000_0000.

#define UART_DATA   (*(volatile unsigned int *)0x10000000)  // write: send a byte
#define UART_STATUS (*(volatile unsigned int *)0x10000004)  // bit 0: ready for a byte
#define LEDS        (*(volatile unsigned int *)0x20000000)  // bit n: LED n lit

static void put_char(char c)
{
    while ((UART_STATUS & 1) == 0)
        ;
    UART_DATA = (unsigned char)c;
}

static void put_string(const char *s)
{
    while (*s)
        put_char(*s++);
}

int main(void)
{
    unsigned int count = 0;
    for (;;) {
        put_string("Hello from PicoRV32 on GateLab!\r\n");
        LEDS = ++count;
        for (volatile unsigned int i = 0; i < 200000; i++)
            ;
    }
}
