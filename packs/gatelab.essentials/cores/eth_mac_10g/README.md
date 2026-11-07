# 10 Gigabit Ethernet MAC

A MAC for 10 Gigabit Ethernet on 64-bit XGMII blocks — the other side of `eth_10gbase_r_pcs`, a block a cycle at
161.13 MHz. Logic only: it builds on every family; the line rate needs a transceiver (`gtx_10g` on the Kintex-7).

- **Transmit (`tx_clk`):** a frame is `tx_data` words (destination MAC first, lane 0 = bits 7:0 first) with `tx_valid`
  high from the first word to `tx_last`; `tx_keep` marks the last word's bytes (1, 3, 7 … FF). `tx_ready` follows the
  PCS's pauses (connect `xgmii_tx_ready` to the PCS's) and doesn't depend on `tx_valid`. The MAC sends start and preamble
  as one block, pads to 60 bytes, appends the FCS (CRC-32) and the terminate, and leaves at least 12 bytes before the
  next start. 10G can't pause a frame: a missing word (an underrun) sends an error block and a terminate, and the
  frame's remaining words are taken and dropped up to `tx_last`.
- **Receive (`rx_clk`):** frames starting in lane 0 or lane 4 (a switch starts in either), down to IEEE's 5-byte gap.
  The FCS is checked and taken off; `rx_data` words come with `rx_valid`, `rx_last` on the last (`rx_keep` its bytes)
  and `rx_error` there when the FCS was wrong, the frame was shorter than 64 bytes or held an error character.
  `rx_frames` and `rx_bad_frames` count them.

On the Kintex-7 Eco R5 with a fibre between SFP1 and SFP2: frames of 64 to 1514 bytes back to back, 1.54 million a
second each way, no bad frame in two minutes.

```verilog
eth_mac_10g u_mac (
    .tx_clk(tx_clk), .tx_data(tx_data), .tx_keep(tx_keep), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready),
    .xgmii_tx_ready(xgmii_ready), .xgmii_txd(txd), .xgmii_txc(txc),
    .rx_clk(rx_clk[0]), .xgmii_rxd(rxd), .xgmii_rxc(rxc), .xgmii_rx_valid(rx_valid),
    .rx_data(rx_data), .rx_keep(rx_keep), .rx_valid(rx_valid_out), .rx_last(rx_last), .rx_error(rx_error),
    .rx_frames(rx_frames), .rx_bad_frames(rx_bad_frames)
);
```
