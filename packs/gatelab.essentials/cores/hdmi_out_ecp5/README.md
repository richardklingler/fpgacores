# HDMI/DVI output (ECP5)

Pixels and syncs to an HDMI or DVI monitor from a Lattice ECP5: three TMDS encoders
(`tmds_encoder`) and four lanes, plus the clock lane. DVI signalling — no audio or info frames —
which every HDMI monitor shows. The same module (`hdmi_out`) and ports as the 7-series core, so a
design moves between them.

```verilog
hdmi_out u_hdmi (
    .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset),
    .red(red), .green(green), .blue(blue), .de(de), .hsync(hsync), .vsync(vsync),
    .tmds_clk_p(hdmi_clk_p), .tmds_clk_n(hdmi_clk_n), .tmds_d_p(hdmi_d_p), .tmds_d_n(hdmi_d_n)
);
```

**Lanes.** ECP5 has no 10:1 serialiser. Each lane is a shift register on `serial_clk` that takes
a word every fifth clock and hands two bits per clock to an `ODDRX1F`. The load comes from a
free-running one-hot ring of five, straight from a flip-flop, so each bit is one 2:1 choice: on
a -6 part the serial clock closes at about 410 MHz.

**Clocks.** `serial_clk` is five times `pixel_clk` (DDR: ten bits per pixel), both from one
EHXPLLL. From 25 MHz the PLL can't make 74.25 MHz; GateLab's Add Clock asks for the nearest pair
one VCO reaches exactly, 74 and 370 MHz (0.34 % under, within HDMI's 0.5 %).

**Reset** is synchronous to `pixel_clk` (the encoders); the lanes need none.

**Pins.** P and N are two single-ended `LVCMOS33` outputs, N driven with the inverted bits by its
own `ODDRX1F`, so any two pins of a 3.3 V bank serve, as on the Colorlight i5/i9 extension board.
Lane 0 is blue, 1 green, 2 red.
