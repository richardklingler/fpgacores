# GTX 10G transceivers

AMD Kintex-7 GTX transceivers at 10.3125 Gb/s, the line rate of 10GBASE-R (10 Gigabit Ethernet on SFP+), from a
156.25 MHz reference clock. One quad: the reference through an `IBUFDS_GTE2`, the quad's QPLL (×66) and one to four
`GTXE2_CHANNEL`s. Kintex-7 only (XC7K325T in GateLab): Artix-7 has GTP transceivers, the Spartan-7s none.

The attribute values are the free Vivado's GT wizard 10GBASE-R preset (its 64-bit fabric width), and every input the wizard
ties is tied the same. The core brings the transceivers up by itself and keeps them up:

- **Reset sequence (on `clk`, a free-running clock of `CLK_HZ`):** 1 ms after configuration the QPLL is reset, then
  locks; the transmitters are released, their MMCM locks (`tx_ready`), then each receiver and its MMCM (`rx_ready[n]`).
  `reset` starts it all again.
- **Receivers:** a rising edge of `rx_restart[n]` resets one receiver (a PCS that lost block lock asks for it; about 60 µs
  on the board). It may come from the receive clock, which stops while the receiver restarts: a request left high then
  restarts it once, not for good.
  Its MMCM losing lock resets it too. A pulled fibre doesn't do that: without a signal the clock recovery keeps running
  near the reference, so a pull shows as lost block lock — and an open fibre end can reflect the cage's own light back
  into its receiver, so check what arrives, not only that blocks arrive. With `prbs` on, 100 milliseconds with PRBS errors in a row
  (`RETRY_MS`) reset it too; `rx_retries` counts every retry. Changing `lpm` or `near_loopback` resets every receiver.
- **Equaliser:** DFE (`lpm` 0, the wizard's choice) holds its AGC and low-frequency loops after four good milliseconds;
  LPM (`lpm` 1) for short, clean links.
- **PRBS31:** `prbs` 1 replaces the transmitted data with the GTX's own PRBS31 generator and counts the checker's error
  words per channel (`prbs_errors`, on `clk`; `prbs_clear` starts them from 0). A link test needs nothing else.
- **`near_loopback`:** each channel's transmitter feeds its own receiver inside the chip (near-end PMA loopback).

**Clocks.** The GTX converts 64 ↔ 32 bits itself (a 64-bit fabric width on its 32-bit internal width), so the fabric
sees a block a cycle at 161.13 MHz — the same 10.3125 Gb/s. As in the wizard's example, an MMCM per direction makes the user
clocks from the transceiver's 322.27 MHz output: 322.27 MHz for TXUSRCLK/RXUSRCLK (only the transceiver sees it) and
161.13 MHz for TXUSRCLK2/RXUSRCLK2. `tx_clk` (from channel 0's TXOUTCLK) drives every transmitter; `rx_clk[n]` comes from
channel n's recovered clock through its own MMCM: the gearbox mode has no clock correction, so a link partner's own
±100 ppm must stay on its channel's clock. Two channels use three MMCMs and nine BUFGs.

**Gearbox (UG476, 64B/66B with the external sequence counter, 8-byte interface).** `tx_sequence` counts 0 … 32 on
`tx_clk`, a block a cycle: `tx_header` (2 bits) and `tx_data` (64 bits); the cycle at 32 carries none. On the receive side
`rx_data_valid` is low one cycle in 33, `rx_header_valid` comes with each block, and a pulse on `rx_slip` moves the block
boundary by one bit while a PCS looks for block lock. The PCS (scrambler, block lock) isn't part of this core.

**Pins.** `refclk_p/n` go on the quad's MGTREFCLK0 balls, `txp/txn/rxp/rxn[n]` on its channel n (on the Kintex-7 Eco R5
the board's `sfp_refclk_p/n`, `sfp_txp[0]` … for SFP1, `[1]` for SFP2). Transceiver balls take a location only. An SFP+
module's TX_DISABLE is an ordinary pin of the design: drive it low to switch the laser on.

**openXC7.** nextpnr-xilinx sets the QPLL's lower-band bit (`QPLL_CFG[6]`) whatever the design gives; GateLab writes
the design's `QPLL_CFG` back into the FASM after place-and-route, or the QPLL wouldn't lock at 10.3125 GHz.

**Simulation.** Icarus can't run AMD's transceiver models (they're encrypted), so without `SYNTHESIS` a stand-in takes
their place and the MMCMs': it locks, runs the clocks at 161.13 MHz, finishes the resets (refusing a USERRDY raised before
its MMCM locked, like the transceiver) and hands channel n's receiver what its partner sent (`SIM_CROSS` 1: channel 0 ↔ 1,
a fibre between two cages; `near_loopback`: its own blocks), already block-aligned. A testbench sets
`g_ch[n].sim_errors` (error words to report) and `g_ch[n].sim_no_link` (no signal: random words, PRBS errors all the
time). `MS_CYCLES` shortens the milliseconds.

```verilog
gtx_10g #(.CLK_HZ(50000000), .CHANNELS(2)) u_gtx (
    .clk(clk), .reset(1'b0), .refclk_p(sfp_refclk_p), .refclk_n(sfp_refclk_n),
    .txp(sfp_txp), .txn(sfp_txn), .rxp(sfp_rxp), .rxn(sfp_rxn),
    .qpll_lock(qpll_lock), .tx_ready(tx_ready), .rx_ready(rx_ready), .rx_retries(rx_retries),
    .rx_restart(2'b00), .prbs(1'b1), .near_loopback(1'b0), .lpm(1'b0), .rx_invert(2'b00),
    .prbs_errors(prbs_errors), .prbs_clear(1'b0),
    .tx_clk(tx_clk), .tx_sequence(tx_sequence), .tx_data(128'd0), .tx_header(4'b0101),
    .rx_clk(rx_clk), .rx_data(rx_data), .rx_header(rx_header), .rx_data_valid(rx_data_valid),
    .rx_header_valid(rx_header_valid), .rx_slip(2'b00)
);
```
