# 74x374 — octal D flip-flop

On each rising `CP` edge the flip-flops take `D0`–`D7`. The outputs show them while `OE_n` is low
and float otherwise — the flip-flops keep clocking. As in the 74LS374 and 74HC374 (KiCad names the
outputs O0–O7 and the clock Cp). Used by GateLab's KiCad import (package pin table in `core.json`).
