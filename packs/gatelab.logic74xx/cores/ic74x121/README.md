# 74x121 — one-shot (simulation model)

Starts a pulse of `PULSE_NS` nanoseconds when `(A1 or A2 low) and B high` becomes true, and
ignores further triggers until it ends. On the real part the length comes from Rext/Cext
(about 0.7 · R · C; pins 9–11, not modelled).

This model only simulates: the delay doesn't synthesize. On an FPGA, replace the one-shot with a
counter that runs for the same time on the design's clock — GateLab's KiCad import points this out
and computes the time from the schematic's resistor and capacitor.
