# Ethernet UDP stack

Everything a design needs to be on the network through a 10/100 PHY on RMII (the Tang Primer 20K Dock's
RTL8201F), in one core — `eth_rmii_phy` and `eth_udp_core` (for an MII PHY: `eth_udp_stack_mii`):

- `eth_rmii_phy` and `eth_mac` (FCS, padding, the inter-frame gap) on the PHY's 50 MHz reference clock;
- `eth_mdio`: after `SETTLE_MS` it advertises 100BASE-TX full duplex and restarts auto-negotiation, then watches
  the link (`link_up`);
- `eth_arp` and `eth_icmp_echo`: other hosts find the design and can `ping` it, without any logic of yours;
- `eth_udp` on port `PORT`: datagrams to it are handed to the design with their sender, and the design sends
  datagrams to any MAC, IP and port (see `eth_udp`'s README for the handshakes).

The three senders share the MAC through a multiplexer that keeps one frame to its last byte (ARP replies first,
then echo replies, then the design's datagrams). `frame_good`, `frame_bad`, `arp_replied` and `ping_replied` pulse
for LEDs or counters. About three block RAMs (the echo's frame buffer and UDP's receive buffer, 2 KB each).

```verilog
localparam [47:0] MAC = 48'h02_47_4C_00_00_01;          // locally administered
localparam [31:0] IP  = {8'd10, 8'd0, 8'd100, 8'd222};
wire mdio_out, mdio_oe;
assign eth_mdio = mdio_oe ? mdio_out : 1'bz;
eth_udp_stack #(.PORT(16'd1234)) u_net (
    .clk(eth_clk), .mac(MAC), .ip(IP),
    .rmii_rxd(eth_rxd), .rmii_crs_dv(eth_crs_dv), .rmii_rx_er(eth_rx_er), .rmii_txd(eth_txd), .rmii_tx_en(eth_tx_en),
    .mdc(eth_mdc), .mdio_out(mdio_out), .mdio_oe(mdio_oe), .mdio_in(eth_mdio),
    .link_up(link_up), .frame_good(), .frame_bad(), .arp_replied(), .ping_replied(),
    // an echo: what arrives goes back to its sender
    .rx_data(udp_data), .rx_valid(udp_valid), .rx_last(), .rx_ready(payload_ready), .rx_length(udp_length),
    .peer_mac(peer_mac), .peer_ip(peer_ip), .peer_port(peer_port), .rx_new(udp_new), .rx_dropped(),
    .send(udp_new), .send_length(udp_length), .dst_mac(peer_mac), .dst_ip(peer_ip), .dst_port(peer_port),
    .send_ready(), .payload_data(udp_data), .payload_valid(udp_valid), .payload_ready(payload_ready)
);
```

The PHY's reset is the design's: hold it low for 10 ms from a clock that runs without the PHY (on the Dock the
50 MHz comes from the PHY, so its reset runs on the board's 27 MHz `clk`).
