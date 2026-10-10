# 74x74 — dual D flip-flop

Two positive-edge D flip-flops, each with an asynchronous preset and clear (active low), as in the
74LS74 and 74HC74. Preset and clear low together drive both outputs high, like the real part.
Used by GateLab's KiCad import (package pin table in `core.json`).

On an FPGA, asynchronous preset/clear and flip-flops clocked by logic signals are fragile: the import
report points them out.
