# HDMI/DVI encoder

The words of an HDMI or DVI link, one 10-bit word per lane per pixel clock, for the family cores `hdmi_out` (AMD
Xilinx 7-series), `hdmi_out_gowin`, `hdmi_out_ecp5` and `hdmi_out_gatemate` to serialise. They use it with their
`HDMI` parameter; a design rarely instantiates it on its own.

- **`HDMI = 0`** — DVI: three TMDS encoders with hsync and vsync on blue's control bits, exactly what the `hdmi_out`
  cores sent before. `audio_ready` stays low.
- **`HDMI = 1`** — HDMI 1.4 with sound:
  - the video preamble and guard band before every active line (the stream runs 12 clocks behind its inputs);
  - a data island in every line's blanking, also during vertical blanking. It needs 66 characters of blanking for one
    packet and 98 for two, which every CEA timing has;
  - Audio Clock Regeneration once a millisecond (N = 6144, CTS = `PIXEL_HZ` / 1000, so give the real pixel clock);
  - audio samples: 48 kHz, two channels, 16 bits, with IEC 60958 channel status saying so;
  - the AVI InfoFrame (RGB, full range, `VIC`, `ASPECT`) and the Audio InfoFrame (two channels).

Audio: `audio_ready` pulses at 48 kHz on average once the encoder has measured the line (after three lines), and the
encoder takes `audio_l`/`audio_r` (signed) in that clock. Hold the next pair on the inputs and step when you see the
pulse; up to eight pairs wait for a packet.

```verilog
hdmi_out #(.HDMI(1), .PIXEL_HZ(74_250_000), .VIC(7'd4), .ASPECT(2'b10)) u_hdmi (
    .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset),
    .red(red), .green(green), .blue(blue), .de(de), .hsync(hsync), .vsync(vsync),
    .audio_l(left), .audio_r(right), .audio_ready(audio_ready),
    .tmds_clk_p(hdmi_clk_p), .tmds_clk_n(hdmi_clk_n), .tmds_d_p(hdmi_d_p), .tmds_d_n(hdmi_d_n));

always @(posedge pixel_clk) if (audio_ready) begin
    left <= next_left;          // whatever makes the sound, one step per request
    right <= next_right;
end
```
