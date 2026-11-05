# Ethernet ping (ICMP echo)

Answers `ping`: an ICMP echo request (RFC 792) to the design's MAC and IPv4 address gets an echo reply with the
same identifier, sequence number and data.

Every frame `eth_mac` receives is kept in a buffer (2^`ADDR_BITS` bytes, one block RAM at the default 11) while it is
checked: to `mac` (a broadcast ping isn't answered), EtherType 0800, IPv4 without options, **not a fragment** (a
fragmented ping's first piece looks like a whole request), protocol 1, destination `ip`, a correct header checksum,
type 8, code 0, and an IP total length that fits the frame and the buffer. When the frame's last byte comes with
`rx_good`, the reply goes out from the buffer: the Ethernet and IP addresses swapped, type 0, the ICMP checksum
adjusted for the new type (RFC 1624) — the IP header's checksum doesn't change.

The reply is a valid/ready/last stream for `eth_mac`; `tx_valid` drops for two clocks after each byte while the
next one is read from the buffer, well within the MAC's four clocks a byte. One reply waits at a time; frames that
arrive meanwhile aren't kept.

```verilog
eth_icmp_echo u_ping (
    .clk(eth_clk), .mac(48'h02_47_4C_00_00_01), .ip({8'd10, 8'd0, 8'd100, 8'd222}),
    .rx_data(rx_data), .rx_valid(rx_valid), .rx_last(rx_last), .rx_good(rx_good),
    .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready), .replied()
);
```
