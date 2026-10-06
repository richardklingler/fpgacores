# Edge detector

Turns level changes into one-cycle pulses: `rise` after `in` goes high, `fall` after it goes
low. Use it to do something once per button press (after a `debouncer`) or once per change of a
status line. `in` must be synchronous to `clk`; put a synchroniser or a `debouncer` in front of
a raw pin.
