# 74x163 — synchronous 4-bit binary counter

Counts on the rising edge of `CP` while `CEP` and `CET` are high, loads `D3…D0` while `PE_n` is
low, and clears while `MR_n` is low — on the next clock edge (synchronous clear, the difference to the 74x161).
`TC` is high at count 15 while `CET` is high, for cascading. As in the 74LS163 and 74HC163. Used by
GateLab's KiCad import (package pin table in `core.json`).
