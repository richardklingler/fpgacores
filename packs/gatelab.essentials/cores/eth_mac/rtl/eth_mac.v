// Ethernet MAC for eth_rmii_phy (100 Mbit/s): frames to and from the PHY's byte stream, from the destination MAC
// to the end of the payload.
//
// Receive: the PHY's bytes are held back five deep, so the FCS (the last four) never comes out and the frame's last
// byte can carry `rx_last` and `rx_good`. `rx_good` (with `rx_last`) means the CRC-32 over the frame and its FCS
// left the residue DEBB20E3, no RX_ER, and 64 to 1522 bytes with the FCS. Bytes come out as they arrive, one every
// fourth clock at most — a frame with a bad FCS is only known to be bad at its last byte, so whatever stores it must
// drop it then. Frames shorter than five bytes give nothing.
//
// Send: offer a frame with `tx_valid`, `tx_last` on its last byte; a byte is taken when `tx_valid` and `tx_ready`
// are both high. The MAC sends 7 × 55 and D5 first, pads to 60 bytes with zeros, adds the FCS and keeps the line
// quiet for GAP_CLOCKS (the 96-bit inter-frame gap: 48 clocks at 50 MHz, plus the PHY's last byte). It asks for a
// byte every fourth clock and doesn't wait: the next byte must be valid when it's asked for. If it isn't (an
// underrun), a zero goes out instead and the FCS is sent inverted, so every receiver drops the frame; the rest of
// the frame is still taken.

module eth_mac #(
    parameter integer GAP_CLOCKS = 52
) (
    input  wire       clk,
    // From and to eth_rmii_phy
    input  wire [7:0] phy_rx_data,
    input  wire       phy_rx_valid,
    input  wire       phy_rx_end,
    input  wire       phy_rx_error,
    output reg  [7:0] phy_tx_data,
    output wire       phy_tx_valid,
    input  wire       phy_tx_ready,
    // Received frames
    output reg  [7:0] rx_data = 8'd0,
    output reg        rx_valid = 1'b0,
    output reg        rx_last = 1'b0,
    output reg        rx_good = 1'b0,
    // Frames to send
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    input  wire       tx_last,
    output wire       tx_ready,
    // An underrun happened in the frame being sent (cleared by the next frame)
    output reg        tx_underrun = 1'b0
);
    function [31:0] crc_byte(input [31:0] c, input [7:0] d);
        integer i;
        reg [31:0] x;
        begin
            x = c;
            for (i = 0; i < 8; i = i + 1)
                x = (x[0] ^ d[i]) ? ((x >> 1) ^ 32'hEDB8_8320) : (x >> 1);
            crc_byte = x;
        end
    endfunction

    // ---- Receive --------------------------------------------------------------------------------------------
    reg [39:0] held = 40'd0;      // the last five bytes, the oldest in [39:32]
    reg [2:0]  held_n = 3'd0;
    reg [10:0] rx_count = 11'd0;  // bytes with the FCS (stops at 2047)
    reg [31:0] rx_crc = 32'hFFFF_FFFF;

    always @(posedge clk) begin
        rx_valid <= 1'b0;
        rx_last <= 1'b0;
        rx_good <= 1'b0;
        if (phy_rx_valid) begin
            held <= {held[31:0], phy_rx_data};
            rx_crc <= crc_byte(rx_crc, phy_rx_data);
            if (rx_count != 11'd2047) rx_count <= rx_count + 11'd1;
            if (held_n == 3'd5) begin
                rx_data <= held[39:32];
                rx_valid <= 1'b1;
            end else held_n <= held_n + 3'd1;
        end
        if (phy_rx_end) begin
            if (held_n == 3'd5) begin
                rx_data <= held[39:32];
                rx_valid <= 1'b1;
                rx_last <= 1'b1;
                rx_good <= rx_crc == 32'hDEBB_20E3 && !phy_rx_error && rx_count >= 11'd64 && rx_count <= 11'd1522;
            end
            held_n <= 3'd0;
            rx_count <= 11'd0;
            rx_crc <= 32'hFFFF_FFFF;
        end
    end

    // ---- Send -----------------------------------------------------------------------------------------------
    localparam IDLE = 3'd0, PREAMBLE = 3'd1, DATA = 3'd2, PAD = 3'd3, FCS = 3'd4, GAP = 3'd5;
    reg [2:0]  state = IDLE;
    reg [2:0]  pre_n = 3'd0;      // preamble bytes sent
    reg [5:0]  count = 6'd0;      // frame bytes sent, up to 60
    reg [1:0]  fcs_n = 2'd0;
    reg [31:0] tx_crc = 32'hFFFF_FFFF;
    reg [6:0]  gap = 7'd0;

    assign phy_tx_valid = state == PREAMBLE || state == DATA || state == PAD || state == FCS;
    assign tx_ready = state == DATA && phy_tx_ready && tx_valid;
    wire [31:0] fcs = ~tx_crc ^ (tx_underrun ? 32'h0000_00FF : 32'd0);

    always @(*) begin
        case (state)
            PREAMBLE: phy_tx_data = pre_n == 3'd7 ? 8'hD5 : 8'h55;
            DATA:     phy_tx_data = tx_valid ? tx_data : 8'h00;
            FCS:      phy_tx_data = fcs[8 * fcs_n +: 8];
            default:  phy_tx_data = 8'h00;
        endcase
    end

    always @(posedge clk) begin
        case (state)
            IDLE:
                if (tx_valid) begin
                    state <= PREAMBLE;
                    pre_n <= 3'd0;
                    count <= 6'd0;
                    tx_crc <= 32'hFFFF_FFFF;
                    tx_underrun <= 1'b0;
                end
            PREAMBLE:
                if (phy_tx_ready) begin
                    pre_n <= pre_n + 3'd1;
                    if (pre_n == 3'd7) state <= DATA;
                end
            DATA:
                if (phy_tx_ready) begin
                    tx_crc <= crc_byte(tx_crc, phy_tx_data);
                    if (count != 6'd60) count <= count + 6'd1;
                    if (!tx_valid) tx_underrun <= 1'b1;
                    if (tx_valid && tx_last) begin
                        fcs_n <= 2'd0;
                        state <= count >= 6'd59 ? FCS : PAD;
                    end
                end
            PAD:
                if (phy_tx_ready) begin
                    tx_crc <= crc_byte(tx_crc, 8'h00);
                    count <= count + 6'd1;
                    if (count == 6'd59) state <= FCS;
                end
            FCS:
                if (phy_tx_ready) begin
                    fcs_n <= fcs_n + 2'd1;
                    if (fcs_n == 2'd3) begin
                        state <= GAP;
                        gap <= 7'd0;
                    end
                end
            default: begin
                gap <= gap + 7'd1;
                if (gap == GAP_CLOCKS - 1) state <= IDLE;
            end
        endcase
    end
endmodule
