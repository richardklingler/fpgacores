# Ethernet MAC

The MAC layer for `eth_rmii_phy` at 100 Mbit/s, on the PHY's 50 MHz clock. Frames go in and out from the
destination MAC address to the end of the payload.

- **Receive:** the FCS is checked and removed. Bytes come out as they arrive (one every fourth clock at most), and
  the frame's last byte carries `rx_last` and `rx_good`: the CRC-32 is right, RX_ER wasn't seen, and the frame was
  64 to 1522 bytes long with its FCS. A bad frame is only known at its last byte — whatever stores frames must
  drop the stored bytes then.
- **Send:** offer a frame with `tx_valid` and `tx_last` on its last byte; a byte is taken when `tx_valid` and
  `tx_ready` are both high. The MAC adds 7 × 55 and D5, pads to 60 bytes with zeros, adds the FCS and keeps the
  inter-frame gap. It asks for a byte every fourth clock and doesn't wait: have the next one ready (from registers
  or a block RAM read one clock ahead). A byte that isn't ready goes out as zero, and the FCS is inverted so every
  receiver drops the frame; `tx_underrun` says so.

```verilog
wire [7:0] rx_data;
wire rx_valid, rx_last, rx_good, tx_ready;
eth_mac u_mac (
    .clk(eth_clk),
    .phy_rx_data(phy_rx_data), .phy_rx_valid(phy_rx_valid), .phy_rx_end(phy_rx_end), .phy_rx_error(phy_rx_error),
    .phy_tx_data(phy_tx_data), .phy_tx_valid(phy_tx_valid), .phy_tx_ready(phy_tx_ready),
    .rx_data(rx_data), .rx_valid(rx_valid), .rx_last(rx_last), .rx_good(rx_good),
    .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready), .tx_underrun()
);
```
