# 4013 — dual D flip-flop

Each flip-flop takes `D` on the rising `CLK`. Set `S` and reset `R` are asynchronous and active
**high** (the 74x74's are active low); with both high, `Q` and `Q_n` are both high. CMOS 4000 series
(CD4013B, HEF4013B …; KiCad names the pins D, C, S, R, Q, ~Q). Used by GateLab's KiCad import.
