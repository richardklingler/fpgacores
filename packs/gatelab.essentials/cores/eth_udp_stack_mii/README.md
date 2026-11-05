# Ethernet UDP stack (MII)

`eth_udp_stack` for a 10/100 PHY on MII (the Arty A7-35T's TI DP83848J): `eth_mii_phy` and `eth_udp_core` — MAC, MDIO
setup and link watch, ARP and ping on their own, and UDP on port `PORT` for the design, with the same design-side ports
as `eth_udp_stack` (see `eth_udp`'s README for the handshakes).

The byte side runs on `clk`, at least four times the PHY's 25 MHz nibble clocks — the Arty's 100 MHz clock; the MII
adapter crosses to `mii_rx_clk` and `mii_tx_clk` through FIFOs. The PHY's own 25 MHz reference is the design's to
make (on the Arty: `eth_ref_clk`, the 100 MHz clock divided by 4), and so is its reset.

```verilog
reg [1:0] ref_div = 0;
always @(posedge clk) ref_div <= ref_div + 1'b1;
assign eth_ref_clk = ref_div[1];                         // 100 MHz / 4
wire mdio_out, mdio_oe;
assign eth_mdio = mdio_oe ? mdio_out : 1'bz;
eth_udp_stack_mii #(.PORT(16'd1234), .CLK_HZ(100_000_000)) u_net (
    .clk(clk), .mac(MAC), .ip(IP),
    .mii_rx_clk(eth_rx_clk), .mii_rxd(eth_rxd), .mii_rx_dv(eth_rx_dv), .mii_rx_er(eth_rxerr),
    .mii_tx_clk(eth_tx_clk), .mii_txd(eth_txd), .mii_tx_en(eth_tx_en),
    .mdc(eth_mdc), .mdio_out(mdio_out), .mdio_oe(mdio_oe), .mdio_in(eth_mdio),
    /* status and UDP as eth_udp_stack's */ ...
);
```
