# FIFO (one clock)

A queue of `2^DEPTH_LOG2` words. Write with `wr_en` while not `full`; read with `rd_en` while not
`empty` — the word appears on `rd_data` **one cycle after** `rd_en`, because the read is
registered (that's what lets the tools use block RAM). Writes when full and reads when empty are
ignored, so a simple producer and consumer can't corrupt it.

```verilog
sync_fifo #(.WIDTH(8), .DEPTH_LOG2(4)) u_fifo (
    .clk(clk), .rst(1'b0),
    .wr_data(rx_byte), .wr_en(rx_valid), .full(),
    .rd_en(tx_take), .rd_data(tx_byte), .empty(fifo_empty), .count()
);
```

For two clocks use `async_fifo`.
