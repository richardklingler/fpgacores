# 4040 — 12-stage binary counter

The count (`Q0` is bit 0) advances on each **falling** edge of `CP`; `MR` high clears it at once.
CMOS 4000 series (CD4040B, HEF4040B …; KiCad names the pins CLK, Reset, Q0–Q11). The real part is a
ripple counter — its outputs settle one stage after another, which is why decoding them glitches —
while the model changes them together. On an FPGA, a synchronous counter replaces it. Used by
GateLab's KiCad import (package pin table in `core.json`).
