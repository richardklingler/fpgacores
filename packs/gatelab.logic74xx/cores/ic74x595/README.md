# 74x595 — 8-bit shift register with output latches

`SRCLK` rising shifts the register on (stage A takes `SER`); `SRCLR_n` low clears it, the latches
keep theirs. `RCLK` rising copies the shift register into the latches, which drive `QA`–`QH` while
`OE_n` is low and float otherwise. `QH_prime` (the datasheet's `QH'`) is the shift register's last
stage for cascading, never three-state. As in the 74HC595 (KiCad names the pins SER, SRCLK, ~SRCLR,
RCLK, ~OE, QA–QH and QH'). Used by GateLab's KiCad import (package pin table in `core.json`).
