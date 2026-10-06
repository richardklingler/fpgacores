# UART receiver

Receives 8N1 bytes on `rx`. The input is synchronised to `clk`, so it can come straight from a
pin. Each byte arrives with a one-cycle `valid` pulse; `data` keeps the byte until the next one.

```verilog
uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(115200)) u_rx (
    .clk(clk), .rx(uart_rx), .data(rx_byte), .valid(rx_valid), .frame_error()
);
```

A byte whose stop bit is low is dropped and reported on `frame_error`. After a break (the line
held low) the receiver waits for the line to go high before it accepts the next start bit. The
testbench shows it works with a sender 2 % off the nominal baud rate.
