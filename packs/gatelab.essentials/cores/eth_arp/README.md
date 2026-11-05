# Ethernet ARP

Answers ARP requests (RFC 826) for the design's IPv4 address, so other hosts can find its MAC address: "who has
`ip`?" — "`ip` is at `mac`".

It watches every frame `eth_mac` receives and checks a request while it arrives: to the broadcast address or to
`mac`, EtherType 0806, hardware type 1, protocol 0800, lengths 6 and 4, operation 1, target `ip`. When the frame's
last byte comes with `rx_good`, the reply is queued: 42 bytes on a valid/ready/last stream for `eth_mac` (which pads
it to 60), or for a multiplexer when other cores send too (`eth_udp_stack` has one). `replied` pulses when a reply
is queued. One reply waits at a time; a request that arrives meanwhile isn't answered (the requester asks again).

```verilog
eth_arp u_arp (
    .clk(eth_clk), .mac(48'h02_47_4C_00_00_01), .ip({8'd10, 8'd0, 8'd100, 8'd222}),
    .rx_data(rx_data), .rx_valid(rx_valid), .rx_last(rx_last), .rx_good(rx_good),
    .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready), .replied()
);
```

`mac` should be a locally administered address (the second-lowest bit of the first byte set: 02:…) unless you own
a block of addresses.
