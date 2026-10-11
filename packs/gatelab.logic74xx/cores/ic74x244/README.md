# 74x244 — octal three-state buffer

Two sections of four buffers: each `Y` follows its `A` while the section's `OE_n` is low and floats
otherwise. Ports as TI names them: `1A1` is `A1_1` (section 1, bit 1), `1Y1` is `Y1_1`, `1OE` is
`OE1_n`. As in the 74LS244 and 74HC244 (KiCad numbers the LS and HC symbols' pins differently —
I0a/O0a and 1A0/1Y0 — but both pair pin 2 with 18, 11 with 9 and so on, as the datasheet does).
Used by GateLab's KiCad import (package pin table in `core.json`).
