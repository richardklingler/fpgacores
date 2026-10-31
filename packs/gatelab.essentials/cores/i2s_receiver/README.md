# I2S receiver

Receives 24-bit stereo samples from an I2S ADC (the CS5343 on the Pmod I2S2's line in) with `i2s_clocks`.
The data pin goes through two flip-flops; each bit is taken just before SCLK rises (the ADC changes it
after the rising edge). `valid` pulses when a frame's left and right samples are complete; both outputs then
hold that frame.

```verilog
wire [23:0] in_left, in_right;
wire in_valid;
i2s_receiver u_adc (
    .clk(clk), .bit_sample(bit_sample), .slot(slot), .sdout(adc_sdout),
    .left(in_left), .right(in_right), .valid(in_valid)
);
```

The ADC must be the clock slave (on the Pmod I2S2: jumper JP1 on SLV), with MCLK, SCLK and LRCK from
`i2s_clocks`.
