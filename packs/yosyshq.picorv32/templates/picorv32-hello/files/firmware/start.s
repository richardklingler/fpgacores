# Start-up code: a stack at the top of the 4 KB RAM, then main().
    .section .text.start
    .global _start
_start:
    li   sp, 0x1000
    call main
hang:
    j    hang
