// A small IPv4 stack for a 10/100 PHY on RMII: eth_rmii_phy and eth_udp_core (eth_mac and eth_mdio, with eth_arp and
// eth_icmp_echo answering ARP and ping on their own, and eth_udp on port PORT for the design). Everything on the PHY's
// 50 MHz reference clock. eth_udp_stack_mii is the same for MII PHYs.
//
// The three senders share the MAC through a multiplexer that takes one frame at a time and keeps it until its last
// byte: ARP replies first, then echo replies, then the design's datagrams. MDIO advertises 100 full duplex
// (eth_mdio's ADVERTISE) and reports `link_up`. `mac` and `ip` are inputs (constants, switches or a register).
//
// The design's side is eth_udp's (see there): received datagrams on rx_*/peer_*, datagrams to send on send_*/
// payload_*. Pulses for LEDs and counters: `frame_good` (a frame with a good FCS, to anyone), `frame_bad` (a bad FCS
// or RX_ER), `arp_replied`, `ping_replied`.

module eth_udp_stack #(
    parameter [15:0]  PORT = 16'd1234,
    parameter integer CLK_HZ = 50_000_000,
    parameter [4:0]   PHY_ADDR = 5'd1,
    parameter integer SETTLE_MS = 200
) (
    input  wire        clk,          // the PHY's 50 MHz reference
    input  wire [47:0] mac,
    input  wire [31:0] ip,
    // The PHY's pins
    input  wire [1:0]  rmii_rxd,
    input  wire        rmii_crs_dv,
    input  wire        rmii_rx_er,
    output wire [1:0]  rmii_txd,
    output wire        rmii_tx_en,
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
    eth_rmii_phy u_phy (
        .clk(clk), .rmii_rxd(rmii_rxd), .rmii_crs_dv(rmii_crs_dv), .rmii_rx_er(rmii_rx_er),
        .rmii_txd(rmii_txd), .rmii_tx_en(rmii_tx_en),
        .rx_data(phy_rx_data), .rx_valid(phy_rx_valid), .rx_end(phy_rx_end), .rx_error(phy_rx_error),
        .tx_data(phy_tx_data), .tx_valid(phy_tx_valid), .tx_ready(phy_tx_ready));

    // ---- MAC, MDIO, ARP, ping, UDP ------------------------------------------------------------------------------
    eth_udp_core #(.PORT(PORT), .CLK_HZ(CLK_HZ), .PHY_ADDR(PHY_ADDR), .SETTLE_MS(SETTLE_MS)) u_core (
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
