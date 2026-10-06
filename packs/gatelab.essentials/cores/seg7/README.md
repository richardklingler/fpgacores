# Seven-segment display

Shows `value` as hexadecimal digits on a multiplexed display (the common kind on boards and
PMODs: shared segment lines, one enable per digit). Digit 0 shows `value[3:0]`. Each digit is lit
`REFRESH_HZ` times a second — 250 Hz per digit doesn't flicker.

```verilog
seg7 #(.CLK_HZ(CLK_HZ), .DIGITS(4), .SEGMENTS_ACTIVE_LOW(1), .DIGITS_ACTIVE_LOW(1)) u_display (
    .clk(clk), .value(counter[15:0]), .dots(4'b0000),
    .segments(seg), .dp(seg_dp), .digit_enable(digit)
);
```

`segments` is `{g, f, e, d, c, b, a}`; map each bit to the right pin in the constraints. For
decimal numbers, convert to BCD first (one digit per four bits). Check the board's schematic
for the polarities: common-anode displays with PNP digit drivers usually need both active low.
