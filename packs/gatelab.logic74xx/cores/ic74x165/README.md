# 74x165 — 8-bit parallel-load shift register

`PL_n` low loads `D0`–`D7` at once (asynchronously: `Q7` follows `D7` while it stays low). Otherwise
the stages shift on the rising edge of `CP` OR `CE_n` — the clock is a gated OR, so `CE_n` low
enables `CP`, and the two pins are interchangeable: `Q0` takes `DS`, `Q7`/`Q7_n` show the last
stage. Change `CE_n` only while `CP` is high, as the datasheet asks. As in the 74LS165 and 74HC165
(KiCad names the pins ~PL, CP, ~CE, DS, D0–D7, Q7, ~Q7). Used by GateLab's KiCad import.
