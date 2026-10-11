# 74x153 — dual 4-to-1 multiplexer

Each half's `Y` is its input `C{B A}` while its strobe is low, else low; `A` and `B` select for
both halves. The datasheet's `1C0` is `C1_0` (half 1, input 0), `1G` is `G1_n`, `1Y` is `Y1`. As
in the 74LS153 and 74HC153 (KiCad names the pins I0a–I3b, S0, S1, Ea, Eb, Za, Zb). Used by
GateLab's KiCad import (package pin table in `core.json`).
