# HDMI/DVI output (GateMate)

Pixels and syncs to an HDMI or DVI monitor from a Cologne Chip GateMate: three TMDS encoders
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

**Lanes.** Each lane is a shift register on `serial_clk` that takes a word every fifth clock and
hands two bits per clock to a `CC_ODDR`. GateMate's `CC_ODDR` sends D1 before D0 (found on the
GateMate EVB; Yosys' simulation model of the primitive says the opposite), so bit 0 goes into D1.

**Clocks.** `serial_clk` is five times `pixel_clk` (DDR: ten bits per pixel). GateMate's PLL gives
one frequency, so GateLab's Add Clock makes the serial clock with the PLL and the pixel clock with a
counter ÷ 5 through a `CC_BUFG`: from the EVB's 10 MHz, 125 and 25 MHz for 640×480 (0.7 % under
25.175 MHz; monitors take it). The pixel clock therefore arrives a little after its serial edge.
The lanes don't count on their own: they watch a bit that toggles with every pixel clock and take
the word three serial clocks after the pixel edge, two before the next one, whatever the
divider's delay. The load comes from a flip-flop per lane, and each pin's two bits sit in a register
next to its `CC_ODDR` (it takes D1 on the falling edge, so that hop has half a clock). In a full
design the serial clock then closes at 150–180 MHz in nextpnr's worst case for speed mode (126
needed for 640×480) and about 110 MHz in economy mode, the GateMate EVB's factory setting (JP12) —
640×480 ran there on the user's monitor anyway, but move JP12 to speed for the guarantee. The
encoders at 25 MHz have room to spare.

**Reset** is synchronous to `pixel_clk` (the encoders); the lanes need none.

**Pins.** P and N are two single-ended outputs, N driven with the inverted bits by its own
`CC_ODDR`, so any two pins of a bank serve: on the GateMate EVB a passive HDMI Pmod on PMODB, whose
pairs aren't the chip's (those sit on Pmod pins 1 and 7). Set `DRIVE=12` and `SLEW=fast` on the
pins (the EVB + HDMI Pmod board does). Lane 0 is blue, 1 green, 2 red.
