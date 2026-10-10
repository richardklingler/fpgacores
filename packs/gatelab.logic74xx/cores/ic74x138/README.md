# 74x138 — 3-to-8 decoder

The selected output `Y{A2 A1 A0}_n` goes low while `E1_n` and `E2_n` are low and `E3` is high;
otherwise all outputs are high. As in the 74LS138 and 74HC138 (KiCad names the pins A0–A2,
E1–E3, O0–O7). Used by GateLab's KiCad import (package pin table in `core.json`).
