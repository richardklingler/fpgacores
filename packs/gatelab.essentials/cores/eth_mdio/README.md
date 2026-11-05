# Ethernet MDIO

An MDIO master (IEEE 802.3 clause 22) that also sets the PHY up and watches the link.

- After `SETTLE_MS` (a PHY answers about 150 ms after its reset) it writes `ADVERTISE` into register 4 — by default
  0x0101, 100BASE-TX full duplex only, which is what `eth_rmii_phy` speaks — and restarts auto-negotiation
  (register 0 = 0x1200). `ADVERTISE = 0` leaves the PHY's own setting.
- Then it reads register 1 `POLL_HZ` times a second: `link_up` is its bit 2. `setup_done` is high after the first read.
- Between polls the design runs its own transactions: with `ready` high, `go` starts a read (into `rdata`) or a
  write (`write`, `wdata`) of register `reg_addr`; `done` pulses when it's over.

MDC runs at `MDC_HZ` or slower (2 MHz by default; the standard allows 2.5). MDIO is push-pull and the core lets go of
it for the PHY's answer; it needs a pull-up — the Tang Primer 20K Dock has none on the board, so its `eth_mdio` pin
asks for the FPGA's.

```verilog
wire mdio_out, mdio_oe, link_up;
assign eth_mdio = mdio_oe ? mdio_out : 1'bz;
eth_mdio #(.CLK_HZ(50_000_000), .PHY_ADDR(5'd1)) u_mdio (
    .clk(eth_clk), .mdc(eth_mdc), .mdio_out(mdio_out), .mdio_oe(mdio_oe), .mdio_in(eth_mdio),
    .link_up(link_up), .setup_done(),
    .go(1'b0), .write(1'b0), .reg_addr(5'd0), .wdata(16'd0), .ready(), .done(), .rdata()
);
```
