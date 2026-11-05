# Ethernet UDP

UDP (RFC 768) over IPv4 and Ethernet on one port, `PORT`: receives datagrams sent to it and sends datagrams from it.

**Receive.** Every frame `eth_mac` receives is checked while it arrives: to `mac` or broadcast, IPv4 without options,
not a fragment, protocol 17, to `ip` or 255.255.255.255, a correct header checksum, destination port `PORT`, a UDP
length that matches, and the UDP checksum unless the sender left it 0. The payload goes into a buffer (2^`ADDR_BITS`
bytes). Once the frame's last byte comes with `rx_good`, the datagram is handed over: `rx_new` pulses, `rx_length`
says how long it is, `peer_mac`/`peer_ip`/`peer_port` say who sent it, and the bytes come on
`rx_data`/`rx_valid`/`rx_last` as fast as `rx_ready` takes them (`rx_valid` drops for two clocks after each while
the next is read). A datagram that arrives before the design has taken the last byte of the one before is dropped
(`rx_dropped`).

**Send.** While `send_ready` is high, `send` starts a datagram of `send_length` bytes (up to 1472) to
`dst_mac`/`dst_ip`/`dst_port`. The core builds the Ethernet, IP and UDP headers (UDP checksum 0) and then asks for
the payload with `payload_ready`. `eth_mac` doesn't wait, so each payload byte must be valid within three clocks of
the one before — a register, a block RAM read ahead, or this core's own receive side:

```verilog
// An echo: what arrives on port 1234 goes back to its sender.
eth_udp #(.PORT(16'd1234)) u_udp (
    .clk(eth_clk), .mac(MAC), .ip(IP),
    .frame_data(rx_data), .frame_valid(rx_valid), .frame_last(rx_last), .frame_good(rx_good),
    .rx_data(udp_data), .rx_valid(udp_valid), .rx_last(), .rx_ready(payload_ready), .rx_length(udp_length),
    .peer_mac(peer_mac), .peer_ip(peer_ip), .peer_port(peer_port), .rx_new(udp_new), .rx_dropped(),
    .send(udp_new), .send_length(udp_length), .dst_mac(peer_mac), .dst_ip(peer_ip), .dst_port(peer_port),
    .send_ready(), .payload_data(udp_data), .payload_valid(udp_valid), .payload_ready(payload_ready),
    .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready)
);
```

To send to a host that hasn't sent anything, use its MAC, or broadcast: `dst_mac` FF:FF:FF:FF:FF:FF and the
subnet's broadcast IP (10.0.255.255 in 10.0.0.0/16). There is no ARP lookup.
