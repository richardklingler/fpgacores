# Ethernet RMII PHY

The RMII side of a 10/100 Ethernet PHY at 100 Mbit/s (Realtek RTL8201F on the Tang Primer 20K Dock, Microchip
LAN8720, TI DP83848 in RMII mode): bytes to and from di-bits on the PHY's 50 MHz reference clock, the low di-bit
first. Everything runs on that clock, so connect the PHY's REF_CLK (on the Dock: `eth_clk`) to `clk`.

- **Receive:** the bytes after the SFD, the frame's FCS included, each with a one-clock `rx_valid`; `rx_end`
  pulses when the frame is over, with `rx_error` if RX_ER was seen or the frame ended inside a byte. CRS_DV
  toggling at a frame's end (the PHY's FIFO still emptying) is handled.
- **Send:** hold `tx_valid` high for every byte of a frame — preamble, SFD and FCS included; a byte is taken when
  `tx_valid` and `tx_ready` are both high (every fourth clock). `tx_valid` low at a byte's end ends the frame.

`eth_mac` adds and checks preamble, FCS, padding and the inter-frame gap; `eth_udp_stack` puts it all together.

```verilog
wire [7:0] rx_data, tx_data;
wire rx_valid, rx_end, rx_error, tx_valid, tx_ready;
eth_rmii_phy u_phy (
    .clk(eth_clk), .rmii_rxd(eth_rxd), .rmii_crs_dv(eth_crs_dv), .rmii_rx_er(eth_rx_er),
    .rmii_txd(eth_txd), .rmii_tx_en(eth_tx_en),
    .rx_data(rx_data), .rx_valid(rx_valid), .rx_end(rx_end), .rx_error(rx_error),
    .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready)
);
```

100 Mbit/s only: at 10 Mbit/s RMII repeats each di-bit ten times. Advertise 100 full duplex with `eth_mdio`.
