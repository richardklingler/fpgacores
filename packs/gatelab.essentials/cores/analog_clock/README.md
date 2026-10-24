# Analogue clock layer

Draws a round clock over a video picture: an outer ring, hour ticks and (optionally) minute
ticks, hour, minute and second hands and a centre cap. Give it the time as `hour` (0–23),
`minute` and `second` (0–59), e.g. from a microcontroller through `spi_registers`; the hour hand
moves on with the minutes and the minute hand with the seconds.

It chains like `sprite_layer`, `text_layer` and `bar_graph`: pixel stream in, the same stream 20
clocks later with the clock on top.

```verilog
analog_clock #(.X_BITS(12), .Y_BITS(11), .CENTER_X(960), .CENTER_Y(480), .RADIUS(150),
               .HOUR_LENGTH(80), .HOUR_WIDTH(12), .MINUTE_LENGTH(120), .MINUTE_WIDTH(8),
               .SECOND_LENGTH(132), .SECOND_WIDTH(3), .CAP(9)) u_clock (
    .clk(pixel_clk), .x(x), .y(y), .de(de), .hsync(hsync), .vsync(vsync),
    .red(r0), .green(g0), .blue(b0),
    .enable(1'b1), .hour(hour), .minute(minute), .second(second),
    .x_out(x1), .y_out(y1), .de_out(de1), .hsync_out(hs1), .vsync_out(vs1),
    .red_out(r1), .green_out(g1), .blue_out(b1), .covered()
);
```

## How it draws

A pipelined CORDIC (13 stages of adders) gives every pixel's angle, clockwise from 12 o'clock in
1/16384 of a turn, and its distance from the centre. The ring, the ticks and the cap are tests
on those two. A hand covers a pixel within its length when the distance across the hand
(radius × angle difference) is at most half its width, so the hands are equally wide along their
whole length; that takes one small multiply per hand. Near the centre a hand's base is a short
wedge: a cap of at least 0.65 × the widest hand hides it.

Order from the top: cap, second hand, minute hand, hour hand, hour ticks, minute ticks, ring,
face (with `FILL = 1`), the picture below.

## Accuracy

Edges are within half a pixel of the exact geometry. The testbench compares every pixel of a
clock of radius 90 at four times with a reference computed in real numbers (`$sqrt`,
`$atan2`), skipping only pixels within half a pixel of an edge. Planted errors that move a
feature by more than that are caught, e.g. a CORDIC angle 0.75° off.

## Testbench

`tb/analog_clock_tb.v`: 10:10:30, 3:45:05, 23:59:59 and 12:00:00 (all hands up, so their order
shows), the picture below and the timing passed through unchanged; about 6 s in Icarus.
