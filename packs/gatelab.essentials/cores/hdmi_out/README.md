# HDMI/DVI output (7-series)

Pixels and syncs to an HDMI or DVI monitor from an AMD Xilinx 7-series FPGA: three TMDS
encoders (`tmds_encoder`), a 10:1 OSERDESE2 serialiser per lane and differential TMDS_33
outputs, plus the clock lane. DVI signalling — no audio or info frames — which every HDMI
monitor shows.

```verilog
hdmi_out u_hdmi (
    .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset),
    .red(red), .green(green), .blue(blue), .de(de), .hsync(hsync), .vsync(vsync),
    .tmds_clk_p(hdmi_clk_p), .tmds_clk_n(hdmi_clk_n), .tmds_d_p(hdmi_d_p), .tmds_d_n(hdmi_d_n)
);
```

**Clocks.** `serial_clk` is five times `pixel_clk` (DDR: ten bits per pixel), both from one
MMCM or PLL so they stay in phase — GateLab's Add Clock keeps outputs that are whole multiples
at that exact ratio. On the global buffers that covers 720p60 and 1080p30 (74.25 and 371.25
MHz). For 1080p60 use `hdmi_out_bufr` (below).

**Reset** is synchronous to `pixel_clk`: hold it until the MMCM has locked.

**Pins.** Each lane is a P/N pair of one bank (3.3 V), `IOSTANDARD TMDS_33` on both. Lane 0 is
blue, 1 green, 2 red. Video timing (`video_timing`) delivers `de` and the syncs; send the colour
of the same pixel in the same cycle.

## 1080p60: `hdmi_out_bufr`

1080p60 needs 148.5 and 742.5 MHz. The serial clock is over a BUFG's limit, so the serialisers
take it from a BUFIO and their word clock from a BUFR dividing the same MMCM output by 5, in the
clock region of the TMDS pins. A BUFR reaches only that region, and nextpnr-xilinx doesn't know
it: logic on the BUFR's clock may be placed in the next region and get its clock over ordinary
wires (GateLab warns after place-and-route). `hdmi_out_bufr` therefore keeps everything but the
serialisers on a global clock:

```verilog
hdmi_out_bufr u_hdmi (
    .pixel_clk(pixel_clk),    // BUFG, 148.5 MHz: the MMCM's CLKOUT1 (VCO ÷ 5)
    .lane_clk(lane_clk),      // BUFR dividing the serial clock by 5: the same frequency
    .serial_clk(serial_clk),  // BUFIO, 742.5 MHz: CLKOUT0 (VCO ÷ 1)
    .reset(reset),
    .red(red), .green(green), .blue(blue), .de(de), .hsync(hsync), .vsync(vsync),
    .tmds_clk_p(hdmi_clk_p), .tmds_clk_n(hdmi_clk_n), .tmds_d_p(hdmi_d_p), .tmds_d_n(hdmi_d_n)
);
```

The encoded words cross from `pixel_clk` to `lane_clk` through a ring of eight, read half the
ring behind the writer: the clocks have the same frequency and any phase. Keep your own logic
on `pixel_clk`, never on `lane_clk`. The 1080p60 starter template shows the whole clocking.

**The last pixel of a line.** 1080p60 runs about 20 % over the HR banks' specified data rate. It
worked on GateLab's test board and monitor, with one catch: a line whose last pixel was white came
out one pixel to the side of the others (lines ending in black were fine; HDMI's video guard band
didn't help). `BLACK_LAST_PIXEL` (default 1) therefore sends each line's last pixel black; set it to 0
for the picture unchanged. Other boards and monitors may behave differently.

**Simulation** uses a behavioural model of the serialiser (no `SYNTHESIS` define): the testbench
decodes the four lanes like a monitor.
