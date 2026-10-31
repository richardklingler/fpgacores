# I2S clocks

MCLK, SCLK and LRCK for an I2S codec that takes its clocks from the FPGA, such as the Cirrus CS4344 (DAC)
and CS5343 (ADC) on the Digilent Pmod I2S2. Counters only, no PLL: the sample rate is
`Fs = clock / (MCLK_DIV · RATIO)`.

| Board clock | MCLK_DIV | RATIO | MCLK | Fs |
|---|---|---|---|---|
| 27 MHz | 2 | 512 | 13.5 MHz | 26.37 kHz |
| 100 MHz | 8 | 256 | 12.5 MHz | 48.83 kHz |
| 12 MHz | 2 | 256 | 6 MHz | 23.44 kHz |

SCLK is 64 Fs (32 bit slots a channel, 24 data bits). The two strobes keep transmitters and receivers in
step with the pins: `bit_start` (the outputs start slot `slot_next` at the next edge) and `bit_sample` (an
input through two flip-flops now shows its bit as it was just before SCLK rose: I2S ADCs change their data
after the rising edge).

```verilog
wire mclk, sclk, lrck, bit_start, bit_sample, frame_start;
wire [5:0] slot_next, slot;
i2s_clocks #(.MCLK_DIV(2), .RATIO(512)) u_clocks (
    .clk(clk), .mclk(mclk), .sclk(sclk), .lrck(lrck),
    .bit_start(bit_start), .slot_next(slot_next), .bit_sample(bit_sample), .slot(slot),
    .frame_start(frame_start)
);
```

Drive the codec's MCLK, SCLK and LRCK pins from `mclk`, `sclk` and `lrck`; a DAC and an ADC on separate pins
(as on the Pmod I2S2) can share them. Check the codec's data sheet for the MCLK/LRCK ratios and sample
rates it accepts.
