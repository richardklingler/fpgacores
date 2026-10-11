# 74x164 — 8-bit serial-in shift register

On each rising `CP` edge `Q0` takes `DSA AND DSB` and every stage moves one on; `MR_n` low clears
all outputs at once. As in the 74LS164 and 74HC164 (KiCad names the pins DSA, DSB, CP, ~MR,
Q0–Q7; TI calls them A, B, CLK, ~CLR, QA–QH). Used by GateLab's KiCad import (package pin table
in `core.json`).
