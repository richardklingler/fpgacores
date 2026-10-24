# Bar graph layer

Draws a bar graph over a video picture — temperatures per hour, power per day, anything with a
row of values. Each bar has two values: series A in front (`INSET` pixels narrower on each side)
and series B behind it, e.g. today and yesterday. Values are heights in pixels, written at any
time through the write port (top bit of `write_address` = the series).

It chains like `text_layer` and `sprite_layer`: pixel stream in, the same stream 3 clocks later
with the graph on top. `x` must count up by one per clock (as `video_timing`'s does): the bar is
found by counting along the line, without a divider.

```verilog
bar_graph #(.BARS(24), .BAR_X(160), .BAR_Y(600), .BAR_WIDTH(48), .GAP(16), .HEIGHT(320),
            .VALUE_BITS(9), .INSET(8), .GRID_STEP(64)) u_hours (
    .clk(pixel_clk), .x(x), .y(y), .de(de), .hsync(hsync), .vsync(vsync),
    .red(r0), .green(g0), .blue(b0),
    .write(wr && wr_addr[11]), .write_address(wr_addr[5:0]), .write_value({1'b0, wr_data}),
    .x_out(x1), .y_out(y1), .de_out(de1), .hsync_out(hs1), .vsync_out(vs1),
    .red_out(r1), .green_out(g1), .blue_out(b1), .covered()
);
```
