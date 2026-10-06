# SPI master

Transfers one byte at a time: raise `start` with `tx_data` while `ready`; `done` pulses with the
answer on `rx_data`. Choose the mode with `CPOL` and `CPHA` (mode 0 = both 0, the most common).

Chip select is not part of the core, so a transaction can be as many bytes as the device
needs: pull your CS pin low, transfer the bytes, release it.

```verilog
spi_master #(.CLK_HZ(CLK_HZ), .SPI_HZ(1000000)) u_spi (
    .clk(clk), .tx_data(cmd), .start(go), .ready(spi_ready), .rx_data(answer), .done(spi_done),
    .sclk(flash_sck), .mosi(flash_mosi), .miso(flash_miso)
);
```

`SPI_HZ` is rounded down so that half a period is a whole number of clock cycles.
