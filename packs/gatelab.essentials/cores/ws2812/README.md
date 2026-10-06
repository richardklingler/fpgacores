# WS2812 LED driver

Sends colours to a chain of WS2812 or WS2812B LEDs ("NeoPixels"). Give it one pixel per
handshake — `rgb` is `{red, green, blue}`, the core sends it in the green-red-blue order the
LEDs expect — the first pixel goes to the LED nearest to the FPGA. Stop handing pixels over and,
`RESET_US` later, `idle` rises: the LEDs show the new frame, and the next pixel starts at the
first LED again.

```verilog
ws2812 #(.CLK_HZ(CLK_HZ)) u_leds (
    .clk(clk), .rgb(pixel), .valid(pixel_valid), .ready(pixel_ready), .dout(led_data), .idle(frame_shown)
);
```

Timing: 0.4 / 0.8 µs high for 0 / 1, 1.25 µs per bit, rounded to the clock — use 8 MHz or
more. The LEDs run at 5 V; most accept the FPGA's 3.3 V data line when the first LED is close,
otherwise add a level shifter.
