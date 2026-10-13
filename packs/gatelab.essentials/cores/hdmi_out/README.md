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
MHz). 1080p60 needs 148.5 and 742.5 MHz: the serial clock is over a BUFG's limit, so drive the
serialisers from a BUFIO and the pixel clock from a BUFR dividing the same MMCM output by 5, both
in the clock region of the TMDS pins. That runs about 20 % over the HR banks' specified data rate;
it worked on GateLab's test board and monitor, but isn't guaranteed.

**Reset** is synchronous to `pixel_clk`: hold it until the MMCM has locked.

**Pins.** Each lane is a P/N pair of one bank (3.3 V), `IOSTANDARD TMDS_33` on both. Lane 0 is
blue, 1 green, 2 red. Video timing (`video_timing`) delivers `de` and the syncs; send the colour
of the same pixel in the same cycle.

**Simulation** uses a behavioural model of the serialiser (no `SYNTHESIS` define): the testbench
decodes the four lanes like a monitor.
