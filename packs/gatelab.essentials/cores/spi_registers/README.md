# SPI registers

Lets a microcontroller (an ESP32, an Arduino, a Raspberry Pi) set values anywhere in your design
over one SPI link: text, numbers, bar heights, colours. Mode 0, most significant bit first. Built
on `spi_slave`, so `clk` must be at least 8 times the SPI clock (148.5 MHz → up to 18 MHz).

One transaction per chip select:

| Bytes from the controller | What happens |
|---|---|
| `01`, address high, address low, data, data, … | each data byte pulses `wr` with `wr_addr`/`wr_data`, then the address counts up |
| `02`, then any bytes | the replies are `ID`, `VERSION`, `status`, then `00` |

The reply to the first byte of every transaction is `ID`, so the controller sees the FPGA is
configured. `done` pulses after a write transaction ends — useful for taking a set of values at
once. Map the address space to your design's write ports, e.g. text cells below 0x800, bar values
above:

```verilog
spi_registers #(.ADDR_BITS(12)) u_link (
    .clk(pixel_clk), .sclk(link_sclk), .cs_n(link_cs_n), .mosi(link_mosi), .miso(miso),
    .wr(wr), .wr_addr(wr_addr), .wr_data(wr_data), .done(), .status(frame_count)
);
assign link_miso = link_cs_n ? 1'bz : miso;
```

From an ESP32 (Arduino): `SPI.transfer(0x01); SPI.transfer(addr >> 8); SPI.transfer(addr & 0xFF);`
then the data bytes, all with CS low.
