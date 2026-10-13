# TMDS encoder (DVI/HDMI)

One channel of the TMDS code DVI and HDMI send: while `de` is high, a colour byte becomes a
10-bit word with few transitions and a running DC balance; while it is low, the control word for
`{c1, c0}`. A DVI/HDMI link uses three: blue (with `hsync` on `c0` and `vsync` on `c1`), green
and red (control bits 0).

```verilog
tmds_encoder u_blue (.clk(pixel_clk), .de(de), .d(blue), .c0(hsync), .c1(vsync), .q(tmds_blue));
```

`q` is registered (one clock of latency) and goes out bit 0 first, ten bits per pixel. The
serialiser that sends it is family-specific: on AMD Xilinx 7-series use `hdmi_out`, which has
the encoders, serialisers and differential outputs in one core.

HDMI's smallest modes (720p60, 1080p30) need a 74.25 MHz pixel clock: the measured speeds (Add Core ▸ Measured)
show which families reach it (AMD Xilinx 7-series, ECP5 and Gowin do; on iCE40 and GateMate it
suits 640×480 at 25 MHz).
