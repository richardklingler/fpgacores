# Sine tone generator

A sine tone at any frequency for audio tests and beeps: a phase accumulator and a 256-point sine table
(16-bit signed, ±32767). Each `advance` adds `step` to the phase; `sample` follows one clock later.

```
frequency = step · sample_rate / 2^PHASE_BITS
step      = frequency · 2^24 / sample_rate     (1 kHz at 48 kHz: 349525)
```

```verilog
wire signed [15:0] tone;
tone_generator u_tone (.clk(clk), .advance(next_sample), .step(24'd349525), .sample(tone));
```

Give it `i2s_transmitter`'s `taken` as `advance`, and shift the sample down for a quieter tone
(`tone >>> 2` is −12 dBFS).
