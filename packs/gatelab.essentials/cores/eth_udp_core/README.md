# Ethernet UDP core

The PHY-independent part of GateLab's IPv4 stack, for designs that bring their own PHY adapter — usually you want
`eth_udp_stack` (RMII) or `eth_udp_stack_mii` (MII), which wrap it:

- `eth_mac` (FCS, padding, the gap) and `eth_mdio` (100 full duplex advertised, `link_up`);
- `eth_arp` and `eth_icmp_echo`, answering ARP and ping on their own;
- `eth_udp` on port `PORT` for the design;
- the multiplexer sharing the MAC among the three senders (one frame to its last byte; ARP, then ping, then UDP).

Its `phy_*` ports take `eth_rmii_phy`'s or `eth_mii_phy`'s byte interface: received bytes after the SFD with
`rx_end`, and bytes to send with valid/ready at most every fourth clock. `clk` is the RMII reference (50 MHz) or the
MII adapter's system clock (100 MHz).
