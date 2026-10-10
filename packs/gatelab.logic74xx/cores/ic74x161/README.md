# 74x161 — synchronous 4-bit binary counter

Counts on the rising edge of `CP` while `CEP` and `CET` are high, loads `D3…D0` while `PE_n` is
low, and clears while `MR_n` is low — at once, without a clock (asynchronous clear, the difference to the 74x163).
`TC` is high at count 15 while `CET` is high, for cascading. As in the 74LS161 and 74HC161. Used by
GateLab's KiCad import (package pin table in `core.json`).
