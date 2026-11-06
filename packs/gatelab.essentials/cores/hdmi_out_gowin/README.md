# HDMI/DVI output (Gowin)

Pixels and syncs to an HDMI or DVI monitor from a Gowin GW1N or GW2A: three TMDS encoders
(`tmds_encoder`), a 10:1 `OSER10` serialiser per lane and true-LVDS outputs (`TLVDS_OBUF`),
plus the clock lane. DVI signalling by default, which every HDMI monitor shows.
The same module (`hdmi_out`) and ports as the 7-series core, so a design moves between them.

```verilog
hdmi_out u_hdmi (
    .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset),
    .red(red), .green(green), .blue(blue), .de(de), .hsync(hsync), .vsync(vsync),
    .tmds_clk_p(hdmi_clk_p), .tmds_clk_n(hdmi_clk_n), .tmds_d_p(hdmi_d_p), .tmds_d_n(hdmi_d_n)
);
```

**Sound.** `HDMI = 1` sends HDMI instead (`hdmi_encoder`): the AVI and Audio InfoFrames, and 48 kHz stereo when you
instantiate `hdmi_out_audio` — the same ports plus `audio_l`, `audio_r` (signed 16-bit) and `audio_ready`, which
pulses when the core takes the next pair. `PIXEL_HZ` must be the pixel clock the PLL makes (it sets HDMI's audio clock).

```verilog
hdmi_out_audio #(.HDMI(1), .PIXEL_HZ(74250000), .VIC(7'd4), .ASPECT(2'b10)) u_hdmi (
    .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset),
    .red(red), .green(green), .blue(blue), .de(de), .hsync(hsync), .vsync(vsync),
    .audio_l(left), .audio_r(right), .audio_ready(audio_ready),
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
