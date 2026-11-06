// RGMII interface to a Gigabit Ethernet PHY at 1000 Mbit/s (Realtek RTL8211E, as on the Kintex-7 Eco R5), with the
// same byte interface as eth_rmii_phy and eth_mii_phy, on a 125 MHz system clock of its own. AMD Xilinx 7-series only
// (IDDR, ODDR, BUFG). The PHY must add both RGMII delays itself (RXDLY and TXDLY strapped or set over MDIO).
//
// Receive (the PHY's rx_clk, 125 MHz): IDDR on a BUFG from the pin takes a nibble on each edge (RX_CTL: DV on the
// first, DV ^ ER on the second), and the bytes are put together on the same BUFG. (BUFIO and BUFR would be the usual
// choice; openXC7's Kintex database has no route from a clock pin to a BUFR, 2026-11-05.) RX_LATE says which edge
// starts a byte: 1 a falling edge and the next rising one — the BUFG's insertion delay is about half a 125 MHz period,
// so the nibbles reach the IDDR half a clock late (checked on the Kintex's two PHYs, 2026-11-05); 0 the rising edge
// (bits 3:0) and the falling one after it. After the preamble, D5 starts the frame; its bytes and its end (DV low; an
// error when ER was seen) cross to `clk` through async_fifo and come out as `rx_valid` and `rx_end` / `rx_error`
// pulses, a byte a clock at most (with gaps when `clk` runs faster).
//
// Send (clk): `tx_ready` is always high — a byte a clock, as eth_mac sends it (preamble, FCS and the gap are eth_mac's:
// GAP_CLOCKS 12). Each byte goes out through ODDR, bits 3:0 on the rising half and 7:4 on the falling, TX_CTL = tx_valid
// on both halves, and TX_CLK is an ODDR of 1/0 on `clk` (the PHY's TXDLY centres it).

module eth_rgmii_phy #(
    parameter RX_LATE = 1
) (
    input  wire       clk,             // 125 MHz
    // The PHY's pins
    input  wire       rgmii_rx_clk,
    input  wire [3:0] rgmii_rxd,
    input  wire       rgmii_rx_ctl,
    output wire       rgmii_tx_clk,
    output wire [3:0] rgmii_txd,
    output wire       rgmii_tx_ctl,
    // Bytes on clk, as eth_rmii_phy's
    output reg  [7:0] rx_data = 8'd0,
    output reg        rx_valid = 1'b0,
    output reg        rx_end = 1'b0,
    output reg        rx_error = 1'b0,
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output wire       tx_ready
);
    // ---- Receive: the pins ----------------------------------------------------------------------------------
    wire       rclk;                   // rx_clk on a BUFG
    wire [4:0] rise, fall;             // {ctl, rxd} at the rising and the falling edge, both on the rising edge after
`ifdef SYNTHESIS
    BUFG u_bufg (.I(rgmii_rx_clk), .O(rclk));
    genvar i;
    generate for (i = 0; i < 5; i = i + 1) begin : lane
        IDDR #(.DDR_CLK_EDGE("SAME_EDGE_PIPELINED")) u_iddr (.C(rclk), .CE(1'b1), .R(1'b0), .S(1'b0),
            .D(i < 4 ? rgmii_rxd[i] : rgmii_rx_ctl), .Q1(rise[i]), .Q2(fall[i]));
    end endgenerate
`else
    // Behaviour of IDDR SAME_EDGE_PIPELINED: the rising edge's sample and the falling one after it, on the next edge.
    assign rclk = rgmii_rx_clk;
    reg [4:0] r_rise = 5'd0, r_fall = 5'd0, s_rise = 5'd0, s_fall = 5'd0;
    always @(posedge rgmii_rx_clk) begin r_rise <= {rgmii_rx_ctl, rgmii_rxd}; s_rise <= r_rise; s_fall <= r_fall; end
    always @(negedge rgmii_rx_clk) r_fall <= {rgmii_rx_ctl, rgmii_rxd};
    assign rise = s_rise;
    assign fall = s_fall;
`endif

    // ---- Receive: bytes, on rclk ----------------------------------------------------------------------------
    reg  [4:0] fall_was = 5'd0;
    always @(posedge rclk) fall_was <= fall;
    // A byte and its two control halves: DV, then DV ^ ER.
    wire [7:0] r_byte = RX_LATE ? {rise[3:0], fall_was[3:0]} : {fall[3:0], rise[3:0]};
    wire       r_dv   = RX_LATE ? fall_was[4] : rise[4];
    wire       r_er   = RX_LATE ? fall_was[4] ^ rise[4] : rise[4] ^ fall[4];

    localparam R_IDLE = 2'd0, R_PREAMBLE = 2'd1, R_DATA = 2'd2;
    reg [1:0] r_state = R_IDLE;
    reg       r_er_seen = 1'b0;
    reg       r_write = 1'b0;
    reg [9:0] r_word = 10'd0;          // {end, error, byte}

    always @(posedge rclk) begin
        r_write <= 1'b0;
        case (r_state)
            R_IDLE:
                if (r_dv) r_state <= r_byte == 8'hD5 ? R_DATA : R_PREAMBLE;
            R_PREAMBLE:
                if (!r_dv) r_state <= R_IDLE;
                else if (r_byte == 8'hD5) r_state <= R_DATA;
            default:
                if (!r_dv) begin
                    r_state <= R_IDLE;
                    r_write <= 1'b1;
                    r_word <= {1'b1, r_er_seen, 8'd0};
                end else begin
                    if (r_er) r_er_seen <= 1'b1;
                    r_write <= 1'b1;
                    r_word <= {2'b00, r_byte};
                end
        endcase
        if (r_state != R_DATA) r_er_seen <= 1'b0;
    end

    wire [9:0] rx_word;
    wire       rx_empty;
    reg        rx_pending = 1'b0;
    wire       rx_read = !rx_empty;
    async_fifo #(.WIDTH(10), .DEPTH_LOG2(5)) u_rx_fifo (
        .wr_clk(rclk), .wr_rst(1'b0), .wr_data(r_word), .wr_en(r_write), .full(),
        .rd_clk(clk), .rd_rst(1'b0), .rd_en(rx_read), .rd_data(rx_word), .empty(rx_empty));

    always @(posedge clk) begin
        rx_valid <= 1'b0;
        rx_end <= 1'b0;
        rx_pending <= rx_read;
        if (rx_pending) begin
            if (rx_word[9]) begin
                rx_end <= 1'b1;
                rx_error <= rx_word[8];
            end else begin
                rx_valid <= 1'b1;
                rx_data <= rx_word[7:0];
            end
        end
    end

    // ---- Send, on clk ---------------------------------------------------------------------------------------
    assign tx_ready = 1'b1;
    reg [7:0] t_byte = 8'd0;
    reg       t_en = 1'b0;
    always @(posedge clk) begin
        t_byte <= tx_valid ? tx_data : 8'd0;
        t_en <= tx_valid;
    end
`ifdef SYNTHESIS
    genvar k;
    generate for (k = 0; k < 4; k = k + 1) begin : out
        ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) u_oddr (.C(clk), .CE(1'b1), .R(1'b0), .S(1'b0),
            .D1(t_byte[k]), .D2(t_byte[k + 4]), .Q(rgmii_txd[k]));
    end endgenerate
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) u_ctl (.C(clk), .CE(1'b1), .R(1'b0), .S(1'b0), .D1(t_en), .D2(t_en), .Q(rgmii_tx_ctl));
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) u_clk (.C(clk), .CE(1'b1), .R(1'b0), .S(1'b0), .D1(1'b1), .D2(1'b0), .Q(rgmii_tx_clk));
`else
    // Behaviour of ODDR SAME_EDGE: what was taken at a rising edge, D1 while clk is high and D2 while it is low.
    reg [7:0] o_byte = 8'd0;
    reg       o_en = 1'b0;
    always @(posedge clk) begin o_byte <= t_byte; o_en <= t_en; end
    assign rgmii_txd = clk ? o_byte[3:0] : o_byte[7:4];
    assign rgmii_tx_ctl = o_en;
    assign rgmii_tx_clk = clk;
`endif
endmodule
