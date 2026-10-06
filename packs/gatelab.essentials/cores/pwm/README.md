# PWM generator

`out` is high for `duty` cycles of every `2^WIDTH`. With WIDTH 8 and a 12 MHz clock the period
is 256 cycles (about 47 kHz), fine for dimming LEDs without flicker. `duty` is read at the start
of each period, so it may change at any time. For servos (50 Hz, 1–2 ms pulses) use a larger
WIDTH or a slower clock enable.

```verilog
pwm #(.WIDTH(8)) u_dim (.clk(clk), .duty(brightness), .out(led_pwm));
```
