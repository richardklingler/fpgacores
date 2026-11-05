// MII interface to an Ethernet PHY at 100 Mbit/s (TI DP83848, Microchip KSZ8081 in MII mode …), with the same byte
// interface as eth_rmii_phy, on a system clock of its own: the PHY's rx_clk and tx_clk (25 MHz) are crossed through
// async_fifo. The system clock must be at least four times the nibble clock (100 MHz for 25).
//
// Receive (rx_clk): after RX_DV rises, nibbles 5 … 5 then D (the SFD's high nibble) start the frame; two nibbles make a
// byte, the low one first. Bytes and the frame's end (RX_DV low; with an error when RX_ER was seen or a nibble was left
// over) cross to `clk`, where they come out as `rx_valid` and `rx_end` / `rx_error` pulses.
//
// Send (clk): `tx_ready` comes at most every fourth clock (eth_mac and the cores in front of it need that pace) while
// the FIFO has room; bytes go into the FIFO, and `tx_valid` falling after a frame marks its end. On tx_clk a frame
// starts 8 nibble clocks after its first byte is queued (the FIFO fills meanwhile), its nibbles go out low first with TX_EN, and TX_EN stays low for at least 24 nibble
// clocks after it (the 96-bit gap).

module eth_mii_phy (
    input  wire       clk,
    // The PHY's pins
    input  wire       mii_rx_clk,
    input  wire [3:0] mii_rxd,
    input  wire       mii_rx_dv,
    input  wire       mii_rx_er,
    input  wire       mii_tx_clk,
    output reg  [3:0] mii_txd = 4'd0,
    output reg        mii_tx_en = 1'b0,
    // Bytes on clk, as eth_rmii_phy's
    output reg  [7:0] rx_data = 8'd0,
    output reg        rx_valid = 1'b0,
    output reg        rx_end = 1'b0,
    output reg        rx_error = 1'b0,
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output wire       tx_ready
);
    // ---- Receive, on rx_clk ---------------------------------------------------------------------------------
    reg [3:0] rxd = 4'd0;
    reg       dv = 1'b0, er = 1'b0;
    localparam R_IDLE = 2'd0, R_PREAMBLE = 2'd1, R_DATA = 2'd2;
    reg [1:0] r_state = R_IDLE;
    reg       r_high = 1'b0;       // the next nibble is a byte's high one
    reg [3:0] r_low = 4'd0;
    reg       r_er_seen = 1'b0;
    reg       r_write = 1'b0;
    reg [9:0] r_word = 10'd0;      // {end, error, byte} or a byte

    always @(posedge mii_rx_clk) begin
        rxd <= mii_rxd;
        dv <= mii_rx_dv;
        er <= mii_rx_er;
        r_write <= 1'b0;
        case (r_state)
            R_IDLE:
                if (dv) r_state <= rxd == 4'hD ? R_DATA : R_PREAMBLE;
            R_PREAMBLE:
                if (!dv) r_state <= R_IDLE;
                else if (rxd == 4'hD) begin
                    r_state <= R_DATA;
                    r_high <= 1'b0;
                    r_er_seen <= 1'b0;
                end
            default:
                if (!dv) begin
                    r_state <= R_IDLE;
                    r_write <= 1'b1;
                    r_word <= {1'b1, r_er_seen || r_high, 8'd0};
                end else begin
                    if (er) r_er_seen <= 1'b1;
                    r_high <= !r_high;
                    if (!r_high) r_low <= rxd;
                    else begin
                        r_write <= 1'b1;
                        r_word <= {2'b00, rxd, r_low};
                    end
                end
        endcase
        if (r_state == R_IDLE && dv) begin
            r_high <= 1'b0;
            r_er_seen <= 1'b0;
        end
    end

    wire [9:0] rx_word;
    wire       rx_empty;
    reg        rx_read = 1'b0, rx_pending = 1'b0;
    async_fifo #(.WIDTH(10), .DEPTH_LOG2(4)) u_rx_fifo (
        .wr_clk(mii_rx_clk), .wr_rst(1'b0), .wr_data(r_word), .wr_en(r_write), .full(),
        .rd_clk(clk), .rd_rst(1'b0), .rd_en(rx_read), .rd_data(rx_word), .empty(rx_empty));

    always @(posedge clk) begin
        rx_valid <= 1'b0;
        rx_end <= 1'b0;
        rx_read <= !rx_empty && !rx_read && !rx_pending;
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

    // ---- Send: into the FIFO, on clk --------------------------------------------------------------------------
    // A frame's end: tx_valid falling after a byte was taken. It is latched (the FIFO may be full just then) and queued
    // as an end marker before the next frame's first byte is taken.
    wire       tx_full;
    reg [1:0]  pace = 2'd0;
    reg        in_frame = 1'b0;      // bytes of a frame have been taken
    reg        end_pending = 1'b0;   // its end waits for room in the FIFO
    wire       ending = end_pending && !tx_full;
    assign tx_ready = tx_valid && !tx_full && pace == 2'd0 && !end_pending;

    always @(posedge clk) begin
        if (pace != 2'd0) pace <= pace + 2'd1;
        else if (tx_ready) pace <= 2'd1;
        if (tx_ready) in_frame <= 1'b1;
        if (in_frame && !tx_valid && !end_pending) begin
            end_pending <= 1'b1;
            in_frame <= 1'b0;
        end
        if (ending) end_pending <= 1'b0;
    end

    wire [8:0] tx_word;
    wire       tx_empty;
    reg        t_read = 1'b0;
    async_fifo #(.WIDTH(9), .DEPTH_LOG2(4)) u_tx_fifo (
        .wr_clk(clk), .wr_rst(1'b0), .wr_data(ending ? 9'h100 : {1'b0, tx_data}), .wr_en(tx_ready || ending),
        .full(tx_full), .rd_clk(mii_tx_clk), .rd_rst(1'b0), .rd_en(t_read), .rd_data(tx_word), .empty(tx_empty));

    // ---- Send: out of the FIFO, on tx_clk ---------------------------------------------------------------------
    // A word is read one clock ahead (rd_data follows rd_en a clock later): `t_have` says tx_word holds the next one.
    reg [3:0]  t_high = 4'd0;
    reg        t_second = 1'b0;    // the byte's high nibble goes out next
    reg        t_have = 1'b0;
    reg        t_sending = 1'b0;
    reg [4:0]  t_gap = 5'd24;      // nibble clocks since the last frame (stops at 24)
    reg [3:0]  t_fill = 4'd0;      // nibble clocks a frame's first byte has waited (the FIFO fills meanwhile)

    always @(posedge mii_tx_clk) begin
        t_read <= 1'b0;
        if (t_read) t_have <= 1'b1;
        if (!t_sending) begin
            mii_tx_en <= 1'b0;
            mii_txd <= 4'd0;
            if (t_gap != 5'd24) t_gap <= t_gap + 5'd1;
            if (!t_have) t_fill <= 4'd0;
            if (!t_have && !t_read && !tx_empty) t_read <= 1'b1;
            else if (t_have && tx_word[8]) t_have <= 1'b0;   // an end with no frame: drop it
            else if (t_have) begin
                // The FIFO's `empty` reaches tx_clk a few clocks late: let it fill before the first nibble, so a
                // byte written meanwhile is never taken for the frame's end.
                if (t_fill != 4'd8) t_fill <= t_fill + 4'd1;
                else if (t_gap == 5'd24) t_sending <= 1'b1;
            end
        end else if (!t_second) begin
            // A byte's low nibble, or the frame's end.
            if (!t_have || tx_word[8]) begin
                t_sending <= 1'b0;
                t_have <= 1'b0;
                t_gap <= 5'd0;
                mii_tx_en <= 1'b0;
                mii_txd <= 4'd0;
            end else begin
                mii_tx_en <= 1'b1;
                mii_txd <= tx_word[3:0];
                t_high <= tx_word[7:4];
                t_second <= 1'b1;
                t_have <= 1'b0;
                if (!tx_empty) t_read <= 1'b1;
            end
        end else begin
            mii_txd <= t_high;
            t_second <= 1'b0;
        end
    end
endmodule
