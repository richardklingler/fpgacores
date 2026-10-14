# HDMI/DVI output (Gowin)

Pixels and syncs to an HDMI or DVI monitor from a Gowin GW1N or GW2A: three TMDS encoders
(`tmds_encoder`), a 10:1 `OSER10` serialiser per lane and true-LVDS outputs (`TLVDS_OBUF`),
plus the clock lane. DVI signalling — no audio or info frames — which every HDMI monitor shows.
The same module (`hdmi_out`) and ports as the 7-series core, so a design moves between them.

```verilog
hdmi_out u_hdmi (
    .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset),
    .red(red), .green(green), .blue(blue), .de(de), .hsync(hsync), .vsync(vsync),
    .tmds_clk_p(hdmi_clk_p), .tmds_clk_n(hdmi_clk_n), .tmds_d_p(hdmi_d_p), .tmds_d_n(hdmi_d_n)
);
```

**Clocks.** `serial_clk` (the OSER10's FCLK) is five times `pixel_clk` (its PCLK): an rPLL for
the serial clock and a `CLKDIV` with `DIV_MODE "5"` on it for the pixel clock. GateLab's Add
Clock makes that pair when the second output is the first ÷ 5: from the Tang Primer 20K's
27 MHz, 371.25 and 74.25 MHz exactly (720p60, 1080p30).

**Reset** is synchronous to `pixel_clk`: hold it until the PLL has locked.

**Pins.** Each lane is a true-LVDS pair: P on the pair's A site, N on its B site. nextpnr reads
each pin on its own `IO_LOC` line (the Gowin IDE's `"x" P,N` form leaves N unconstrained). Lane 0
is blue, 1 green, 2 red.

Shown on a monitor through the Tang Primer 20K Dock's HDMI connector (2026-10-14).
