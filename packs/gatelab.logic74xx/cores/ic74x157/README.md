# 74x157 — quad 2-to-1 multiplexer

Each section's `Y` is its `A` input with `S` low and its `B` input with `S` high (the datasheet's
`A/B` select), and low while the strobe `G_n` is high. As in the 74LS157 and 74HC157 (KiCad names
the pins I0a–I1d, S, E, Za–Zd). Used by GateLab's KiCad import (package pin table in
`core.json`).
