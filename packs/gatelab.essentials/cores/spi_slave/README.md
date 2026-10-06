# SPI slave

Lets a microcontroller talk to your design over SPI (mode 0, MSB first). Everything runs in
your `clk`; SCLK, CS and MOSI are synchronised, so `clk` must be at least 8 times the SPI clock
(e.g. 12 MHz handles SPI up to 1.5 MHz).

Every byte from the master pulses `rx_valid`. The answer for the *next* byte is read from
`tx_data` when CS falls and right after each `rx_valid` — a register-read protocol therefore
answers with one byte of delay, as most SPI devices do.

```verilog
spi_slave u_spi (
    .clk(clk), .sclk(spi_sck), .cs_n(spi_cs_n), .mosi(spi_mosi), .miso(spi_miso),
    .rx_data(command), .rx_valid(command_valid), .tx_data(status)
);
```
