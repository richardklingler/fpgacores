# 4017 — decade counter with decoded outputs

The count advances on the rising edge of `CLK AND NOT INH`: `INH` (the clock inhibit; KiCad calls
it CKEN) gates the clock, so a falling `INH` while `CLK` is high counts too. `RST` high clears to 0
at once. Exactly one of `Q0`–`Q9` is high; `COUT` is high for counts 0–4. CMOS 4000 series
(CD4017B, HEF4017B …). The real part is a Johnson counter with the same outputs. Used by GateLab's
KiCad import (package pin table in `core.json`).
