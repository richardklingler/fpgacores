# Video timing (VGA/DVI)

Generates the timing of a video mode from the pixel clock: `hsync`, `vsync`, `active` (the
visible area, "data enable" for DVI) and the position `x`, `y` of the pixel being sent. Compute
the colour from `x`/`y` and output it while `active`, black otherwise:

```verilog
video_timing u_timing (.clk(pixel_clk), .hsync(vga_hs), .vsync(vga_vs), .active(de),
                       .frame_start(), .x(x), .y(y));
assign {vga_r, vga_g, vga_b} = de ? {x[7:4], y[7:4], 4'h8} : 12'h000;   // a colour gradient
```

The default is 640×480 at 60 Hz: pixel clock 25.175 MHz (a PLL making 25 MHz is fine for
most monitors). Other modes come from the parameters (e.g. 800×600 at 60 Hz: 800/40/128/88,
600/1/4/23, positive syncs, 40 MHz). For DVI or HDMI the outputs still need TMDS encoding and
serialisers, which are family-specific.
