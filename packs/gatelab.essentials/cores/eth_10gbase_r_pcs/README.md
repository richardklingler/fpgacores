# 10GBASE-R PCS

The physical coding sublayer of 10 Gigabit Ethernet over fibre (IEEE 802.3 clause 49), between 64-bit XGMII blocks and
a transceiver's 64B/66B gearbox — made for `gtx_10g`, a block a cycle at 161.13 MHz. Logic only: it builds on every
family, but 10.3125 Gb/s needs a transceiver (in GateLab the Kintex-7's GTX).

- **Transmit (`tx_clk`):** an XGMII block (eight lanes, `xgmii_txc` marks control characters) whenever
  `xgmii_tx_ready` is high — every cycle but the gearbox's pause, one in 33; `xgmii_tx_ready_next` says it a cycle ahead.
  Each block is encoded into its 66-bit format (data; idle and error; start in lane 0 or 4; terminate in any lane;
  anything else becomes an error block), scrambled with x⁵⁸ + x³⁹ + 1 and handed to the gearbox three blocks later.
- **Receive (`rx_clk`):** block lock from the sync headers (64 valid in a row; 16 invalid within 64 lose it), `rx_slip`
  moves the boundary while unlocked. Blocks are descrambled and decoded — also start in lane 4 and ordered sets (as XGMII
  sequence `0x9C`) — and come out a block a cycle with `xgmii_rx_valid`. Invalid headers, block types and control codes
  give an error block (all lanes `/E/`), counted in `rx_error_blocks`. `high_ber`: 16 invalid headers within 125 µs.
- **Receiver restart:** when block lock stays lost for `RESTART_BLOCKS` blocks (13 ms), `rx_restart` pulses — connect it
  to `gtx_10g`'s `rx_restart`. A pulled fibre doesn't stop the transceiver's recovered clock, so nothing else would reset
  the receiver.
- **Bit order:** `BIT_REVERSE` 1 (default) for `gtx_10g`, which sends a port's most significant bit first.

On the Kintex-7 Eco R5 with a fibre between SFP1 and SFP2: block lock at once, 1.54 million frames a second each way
through `eth_mac_10g` with no error block in two minutes; after a pulled fibre block lock returned within a second.

```verilog
eth_10gbase_r_pcs u_pcs (
    .tx_clk(tx_clk), .tx_sequence(tx_sequence), .xgmii_txd(txd), .xgmii_txc(txc),
    .xgmii_tx_ready(xgmii_ready), .xgmii_tx_ready_next(), .tx_data(tx_data[63:0]), .tx_header(tx_header[1:0]),
    .rx_clk(rx_clk[0]), .rx_reset(!rx_ready[0]), .rx_data(rx_data[63:0]), .rx_header(rx_header[1:0]),
    .rx_data_valid(rx_data_valid[0]), .rx_header_valid(rx_header_valid[0]),
    .rx_slip(rx_slip[0]), .rx_restart(rx_restart[0]),
    .xgmii_rxd(rxd), .xgmii_rxc(rxc), .xgmii_rx_valid(rx_valid),
    .block_lock(block_lock), .high_ber(high_ber), .rx_error_blocks(error_blocks)
);
```
