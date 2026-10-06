# UART (Forencich, AXI-Stream)

Alex Forencich's `uart` from [verilog-uart](https://github.com/alexforencich/verilog-uart),
unchanged (MIT, see LICENSE.txt; the notice stays in every file). Transmitter and receiver with
AXI-Stream handshakes: a byte moves when `tvalid` and `tready` are both high.

The baud rate is an input: `prescale = clock / (baud × 8)` — 12 MHz at 115200 baud is 13.

```verilog
uart u_uart (
    .clk(clk), .rst(1'b0),
    .s_axis_tdata(tx_byte), .s_axis_tvalid(tx_valid), .s_axis_tready(tx_ready),
    .m_axis_tdata(rx_byte), .m_axis_tvalid(rx_valid), .m_axis_tready(1'b1),
    .rxd(uart_rx), .txd(uart_tx),
    .tx_busy(), .rx_busy(), .rx_overrun_error(), .rx_frame_error(),
    .prescale(16'd13)
);
```

The modules are called `uart`, `uart_tx` and `uart_rx`: a project can't have this core and
GateLab Essentials' `uart_tx` / `uart_rx` at the same time. The testbench is GateLab's.
