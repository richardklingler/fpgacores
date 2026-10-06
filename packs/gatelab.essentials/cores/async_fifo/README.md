# FIFO (two clocks)

Moves words from one clock domain to another. Each side only uses its own clock and signals:
the writer `wr_en`/`full`, the reader `rd_en`/`empty`/`rd_data` (one `rd_clk` cycle after
`rd_en`). The pointers cross as Gray code through two flip-flops, so no multi-bit value is ever
sampled mid-change.

`full` and `empty` are pessimistic by a few cycles of the other clock — the FIFO never
overflows or underflows, but it may report full or empty briefly after room or data appeared.
Hold both resets together for a few cycles of the slower clock.

Timing: tell the place-and-route tool the two clocks are unrelated (separate clock constraints)
so it doesn't try to time the synchroniser paths.
