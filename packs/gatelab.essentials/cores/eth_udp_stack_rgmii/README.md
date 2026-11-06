# Ethernet UDP stack (RGMII)

`eth_udp_stack` for a Gigabit PHY on RGMII at 1000 Mbit/s (the Kintex-7 Eco R5's two Realtek RTL8211E): `eth_rgmii_phy`
and `eth_udp_core` — MAC, MDIO setup and link watch, ARP and ping on their own, and UDP on port `PORT` for the design,
with the same design-side ports as `eth_udp_stack` (see `eth_udp`'s README for the handshakes). AMD Xilinx 7-series only.

Every part runs a byte a clock on `clk`, 125 MHz from an MMCM or PLL. At this speed the MAC asks for a payload byte on
every clock, so a design that sends must have the next byte ready when `payload_ready` asks (a block RAM read a clock
ahead, or `eth_udp`'s own received datagram for an echo). MDIO advertises no 10/100 mode: the link comes up at 1000 or
not at all. The PHY's reset is the design's to drive (on the Eco R5: `eth_rst_n`, high to run).

```verilog
wire mdio_out, mdio_oe;
assign eth_mdio = mdio_oe ? mdio_out : 1'bz;
eth_udp_stack_rgmii #(.PORT(16'd1234)) u_net (
    .clk(clk125), .mac(MAC), .ip(IP),
    .rgmii_rx_clk(eth_rx_clk), .rgmii_rxd(eth_rxd), .rgmii_rx_ctl(eth_rx_ctl),
    .rgmii_tx_clk(eth_tx_clk), .rgmii_txd(eth_txd), .rgmii_tx_ctl(eth_tx_ctl),
    .mdc(eth_mdc), .mdio_out(mdio_out), .mdio_oe(mdio_oe), .mdio_in(eth_mdio),
    /* status and UDP as eth_udp_stack's */ ...
);
```
