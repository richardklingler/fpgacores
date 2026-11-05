# Ethernet MII PHY

The MII side of a 10/100 Ethernet PHY at 100 Mbit/s (TI DP83848J on the Arty A7, Microchip KSZ8081 in MII mode …),
with the same byte interface as `eth_rmii_phy`, so `eth_mac` and the protocol cores work on it unchanged.

MII has two clocks of its own from the PHY — `mii_rx_clk` and `mii_tx_clk`, 25 MHz at 100 Mbit/s — and a byte every
second clock, faster than the cores' pace. So the core runs the byte side on a system clock `clk` of at least four
times that (100 MHz) and crosses to the nibble clocks through `async_fifo`:

- **Receive (rx_clk):** after RX_DV rises, nibbles 5 … 5 then D start the frame; two nibbles make a byte, the low one
  first. Bytes and the frame's end come out on `clk` as `rx_valid` and `rx_end` (with `rx_error` when RX_ER was seen
  or the frame ended on a stray nibble).
- **Send (clk):** `tx_ready` comes at most every fourth clock — `eth_mac` and the cores in front of it rely on that
  pace — while the FIFO has room; `tx_valid` falling after a frame queues its end. On `tx_clk` a frame starts once
  bytes are queued (it waits 8 nibble clocks so the FIFO fills first), its nibbles go out low first, and TX_EN stays
  low for at least 24 nibble clocks between frames (the 96-bit gap).

The PHY usually needs a 25 MHz reference from the FPGA (the Arty's `eth_ref_clk`: the 100 MHz clock divided by 4 is
enough). `eth_udp_stack_mii` puts it together with the MAC, MDIO and the protocols.

```verilog
eth_mii_phy u_phy (
    .clk(clk), .mii_rx_clk(eth_rx_clk), .mii_rxd(eth_rxd), .mii_rx_dv(eth_rx_dv), .mii_rx_er(eth_rxerr),
    .mii_tx_clk(eth_tx_clk), .mii_txd(eth_txd), .mii_tx_en(eth_tx_en),
    .rx_data(rx_data), .rx_valid(rx_valid), .rx_end(rx_end), .rx_error(rx_error),
    .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready)
);
```
