# I2S transmitter

Sends 24-bit stereo samples to an I2S DAC (the CS4344 on the Pmod I2S2's line out) with `i2s_clocks`. The
samples are taken at the start of each frame; `taken` pulses then, so the next samples can be prepared
during the frame.

```verilog
i2s_transmitter u_dac (
    .clk(clk), .bit_start(bit_start), .slot_next(slot_next),
    .left({tone, 8'h00}), .right({tone, 8'h00}),
    .taken(next_sample), .sdin(dac_sdin)
);
```

Samples are two's complement; a 16-bit source goes into the top bits. `sdin` changes with SCLK's falling
edge, the MSB one SCLK after LRCK changes (I2S).
