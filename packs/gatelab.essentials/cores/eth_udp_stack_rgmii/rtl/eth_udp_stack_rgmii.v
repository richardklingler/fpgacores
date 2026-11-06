// A small IPv4 stack for a Gigabit PHY on RGMII at 1000 Mbit/s (the Kintex-7 Eco R5's RTL8211E, both RGMII delays in
// the PHY): eth_rgmii_phy and eth_udp_core (eth_mac and eth_mdio, with eth_arp and eth_icmp_echo answering ARP and ping on
// their own, and eth_udp on port PORT for the design), every part a byte a clock. AMD Xilinx 7-series only. The byte side
// runs on `clk`, 125 MHz (an MMCM from the board's clock); eth_rgmii_phy crosses from rgmii_rx_clk. MDIO advertises no
// 10/100 mode (register 4 = 0001): the link comes up at 1000 with the PHY's own register 9.
//
// The design's side is eth_udp's (see there), the same as eth_udp_stack's: received datagrams on rx_*/peer_*, datagrams to
// send on send_*/payload_*. Pulses for LEDs and counters: `frame_good`, `frame_bad`, `arp_replied`, `ping_replied`.

module eth_udp_stack_rgmii #(
    parameter [15:0]  PORT = 16'd1234,
    parameter integer CLK_HZ = 125_000_000,
    parameter [4:0]   PHY_ADDR = 5'd1,
    parameter integer SETTLE_MS = 200,
    parameter         RX_LATE = 1          // eth_rgmii_phy's: which edge starts a received byte
) (
    input  wire        clk,          // 125 MHz
    input  wire [47:0] mac,
    input  wire [31:0] ip,
    // The PHY's pins
    input  wire        rgmii_rx_clk,
    input  wire [3:0]  rgmii_rxd,
    input  wire        rgmii_rx_ctl,
    output wire        rgmii_tx_clk,
    output wire [3:0]  rgmii_txd,
    output wire        rgmii_tx_ctl,
    output wire        mdc,
    output wire        mdio_out,
    output wire        mdio_oe,
    input  wire        mdio_in,
    // Status
    output wire        link_up,
    output wire        frame_good,
    output wire        frame_bad,
    output wire        arp_replied,
    output wire        ping_replied,
    // UDP: received datagrams
    output wire [7:0]  rx_data,
    output wire        rx_valid,
    output wire        rx_last,
    input  wire        rx_ready,
    output wire [10:0] rx_length,
    output wire [47:0] peer_mac,
    output wire [31:0] peer_ip,
    output wire [15:0] peer_port,
    output wire        rx_new,
    output wire        rx_dropped,
    // UDP: datagrams to send
    input  wire        send,
    input  wire [10:0] send_length,
    input  wire [47:0] dst_mac,
    input  wire [31:0] dst_ip,
    input  wire [15:0] dst_port,
    output wire        send_ready,
    input  wire [7:0]  payload_data,
    input  wire        payload_valid,
    output wire        payload_ready
);

    // ---- The PHY ------------------------------------------------------------------------------------------------
    wire [7:0] phy_rx_data, phy_tx_data;
    wire       phy_rx_valid, phy_rx_end, phy_rx_error, phy_tx_valid, phy_tx_ready;
    eth_rgmii_phy #(.RX_LATE(RX_LATE)) u_phy (
        .clk(clk), .rgmii_rx_clk(rgmii_rx_clk), .rgmii_rxd(rgmii_rxd), .rgmii_rx_ctl(rgmii_rx_ctl),
        .rgmii_tx_clk(rgmii_tx_clk), .rgmii_txd(rgmii_txd), .rgmii_tx_ctl(rgmii_tx_ctl),
        .rx_data(phy_rx_data), .rx_valid(phy_rx_valid), .rx_end(phy_rx_end), .rx_error(phy_rx_error),
        .tx_data(phy_tx_data), .tx_valid(phy_tx_valid), .tx_ready(phy_tx_ready));

    // ---- MAC, MDIO, ARP, ping, UDP ------------------------------------------------------------------------------
    eth_udp_core #(.PORT(PORT), .CLK_HZ(CLK_HZ), .PHY_ADDR(PHY_ADDR), .SETTLE_MS(SETTLE_MS),
        .ADVERTISE(16'h0001), .GAP_CLOCKS(12)) u_core (
        .clk(clk), .mac(mac), .ip(ip),
        .phy_rx_data(phy_rx_data), .phy_rx_valid(phy_rx_valid), .phy_rx_end(phy_rx_end), .phy_rx_error(phy_rx_error),
        .phy_tx_data(phy_tx_data), .phy_tx_valid(phy_tx_valid), .phy_tx_ready(phy_tx_ready),
        .mdc(mdc),
        .mdio_out(mdio_out),
        .mdio_oe(mdio_oe),
        .mdio_in(mdio_in),
        .link_up(link_up),
        .frame_good(frame_good),
        .frame_bad(frame_bad),
        .arp_replied(arp_replied),
        .ping_replied(ping_replied),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_last(rx_last),
        .rx_ready(rx_ready),
        .rx_length(rx_length),
        .peer_mac(peer_mac),
        .peer_ip(peer_ip),
        .peer_port(peer_port),
        .rx_new(rx_new),
        .rx_dropped(rx_dropped),
        .send(send),
        .send_length(send_length),
        .dst_mac(dst_mac),
        .dst_ip(dst_ip),
        .dst_port(dst_port),
        .send_ready(send_ready),
        .payload_data(payload_data),
        .payload_valid(payload_valid),
        .payload_ready(payload_ready));
endmodule
