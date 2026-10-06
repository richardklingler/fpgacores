# UART transmitter

Sends one byte per handshake over `tx`: start bit, eight data bits (least significant first),
stop bit. Set `CLK_HZ` to your clock and `BAUD` to the rate; the bit time is rounded to whole
clock cycles, so keep `CLK_HZ / BAUD` large (12 MHz / 115200 ≈ 104, an error of 0.2 %).

```verilog
uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(115200)) u_tx (
    .clk(clk), .data(byte), .valid(send), .ready(tx_ready), .tx(uart_tx)
);
```

A byte is taken in the cycle where `valid` and `ready` are both high. To send a string, step to
the next character on that cycle.
