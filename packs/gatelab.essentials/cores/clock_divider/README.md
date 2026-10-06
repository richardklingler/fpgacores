# Clock divider

`tick` pulses for one cycle `HZ` times per second; `square` is high for the first half of each
period. Both stay in the `clk` domain: drive slower logic with `if (tick) …` instead of using a
divided signal as a clock, which FPGA tools route badly and time wrongly.

```verilog
clock_divider #(.CLK_HZ(CLK_HZ), .HZ(2)) u_blink (.clk(clk), .tick(), .square(led_on));
```
