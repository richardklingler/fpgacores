# 74x151 — 8-to-1 multiplexer

`Y` is the data input `D{C B A}` while the strobe `G_n` is low; with `G_n` high, `Y` is low and
`Y_n` (the datasheet's `W`) high. As in the 74LS151 and 74HC151 (KiCad names the pins I0–I7,
S0–S2, ~E, Z and ~Z). Used by GateLab's KiCad import (package pin table in `core.json`).
