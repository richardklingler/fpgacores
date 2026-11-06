# Ethernet RGMII PHY

The RGMII side of a Gigabit Ethernet PHY at 1000 Mbit/s (Realtek RTL8211E on the Kintex-7 Eco R5 …), with the same
byte interface as `eth_rmii_phy` and `eth_mii_phy`, so `eth_mac` and the protocol cores work on it unchanged — at a
byte a clock. AMD Xilinx 7-series only: it uses IDDR, ODDR and a BUFG.

RGMII carries a nibble on each edge of a 125 MHz clock. The PHY must add both RGMII delays itself (the RTL8211E's
RXDLY and TXDLY straps, or its registers over MDIO): the core samples and sends edge-aligned.

- **Receive (`rgmii_rx_clk`, a clock-capable pin):** IDDR on a BUFG from that pin takes RXD and RX_CTL on both edges
  and the bytes are put together on the same clock. (BUFIO and BUFR would be the usual choice; openXC7's Kintex
  database has no route from a clock pin to a BUFR.) After the preamble D5 starts the frame; bytes and the frame's end cross to
  `clk` through `async_fifo` and come out as `rx_valid` and `rx_end` (with `rx_error` when the PHY flagged an error).
- **Send (`clk`):** `tx_ready` is always high — a byte a clock. Bits 3:0 go out on the rising half, 7:4 on the
  falling, TX_CTL = `tx_valid` on both, and TX_CLK is forwarded from `clk` through an ODDR. `eth_mac` keeps the gap
  between frames (`GAP_CLOCKS` 12 at this speed).

`RX_LATE` says which edge starts a received byte: 1 (the default) a falling edge and the next rising one, 0 a rising
edge and the falling one after it. The BUFG's insertion delay is about half a 125 MHz period, so the nibbles reach the
IDDR half a clock late and 1 is right (both PHYs of the Kintex-7 Eco R5); with the wrong one no frame passes its FCS.

`clk` is 125 MHz from an MMCM or PLL; it doesn't need to be locked to the PHY's clock. `eth_udp_stack_rgmii` puts it
together with the MAC, MDIO and the protocols.

```verilog
eth_rgmii_phy u_phy (
    .clk(clk125), .rgmii_rx_clk(eth_rx_clk), .rgmii_rxd(eth_rxd), .rgmii_rx_ctl(eth_rx_ctl),
    .rgmii_tx_clk(eth_tx_clk), .rgmii_txd(eth_txd), .rgmii_tx_ctl(eth_tx_ctl),
    .rx_data(rx_data), .rx_valid(rx_valid), .rx_end(rx_end), .rx_error(rx_error),
    .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready)
);
```
