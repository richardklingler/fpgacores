# Debouncer

Mechanical buttons bounce for a few milliseconds when pressed or released. `out` follows `in`
only once it has kept its new level for `MS` milliseconds (10 ms is enough for most buttons).
The input is synchronised, so it can come straight from a pin. For an active-low button, invert
`out` (or the pin).

To act once per press, follow it with `edge_detect`:

```verilog
wire pressed;
debouncer #(.CLK_HZ(CLK_HZ)) u_debounce (.clk(clk), .in(~btn), .out(pressed));
edge_detect u_edge (.clk(clk), .in(pressed), .rise(press), .fall());
```
