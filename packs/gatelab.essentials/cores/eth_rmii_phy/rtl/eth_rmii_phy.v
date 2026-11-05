// RMII interface to an Ethernet PHY at 100 Mbit/s (Realtek RTL8201F, Microchip LAN8720, TI DP83848 in RMII mode):
// bytes to and from di-bits on the 50 MHz reference clock, the low di-bit first.
//
// Receive: after CRS_DV rises, the bytes after the SFD (the preamble's last di-bit 11) come out one at a time with a
// one-clock `rx_valid` — the frame as sent, its FCS included (eth_mac checks and removes it). CRS_DV may toggle at a
// frame's end while the PHY still has data (low on a nibble's first di-bit, high on its second): the frame ends when
// CRS_DV is low on two clocks in a row, and `rx_end` pulses then. `rx_error` comes with `rx_end`: RX_ER was seen
// during the frame, or it ended inside a byte.
//
// Send: `tx_valid` up for every byte of a frame — preamble, SFD and FCS included (eth_mac adds them). A byte is
// taken when `tx_valid` and `tx_ready` are both high, every fourth clock while a frame goes out; when `tx_valid` is
// low at a byte's end, TX_EN falls and the frame is over. The PHY needs its inter-frame gap from the sender.

module eth_rmii_phy (
    input  wire       clk,          // the 50 MHz reference (RMII REF_CLK)
    input  wire [1:0] rmii_rxd,
    input  wire       rmii_crs_dv,
    input  wire       rmii_rx_er,
    output reg  [1:0] rmii_txd = 2'b00,
    output reg        rmii_tx_en = 1'b0,
    output reg  [7:0] rx_data = 8'd0,
    output reg        rx_valid = 1'b0,
    output reg        rx_end = 1'b0,
    output reg        rx_error = 1'b0,
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output wire       tx_ready
);
    // ---- Receive --------------------------------------------------------------------------------------------
    reg [1:0] rxd = 2'b00;
    reg       crs = 1'b0, crs_last = 1'b0, er = 1'b0;
    localparam IDLE = 2'd0, PREAMBLE = 2'd1, DATA = 2'd2;
    reg [1:0] state = IDLE;
    reg [1:0] dibit = 2'd0;
    reg [5:0] shift = 6'd0;
    reg       er_seen = 1'b0;

    always @(posedge clk) begin
        rxd <= rmii_rxd;
        crs <= rmii_crs_dv;
        er <= rmii_rx_er;
        crs_last <= crs;
        rx_valid <= 1'b0;
        rx_end <= 1'b0;
        case (state)
            IDLE:
                if (crs) state <= PREAMBLE;
            PREAMBLE:
                if (!crs && !crs_last) state <= IDLE;
                else if (crs && rxd == 2'b11) begin   // the SFD's last di-bit
                    state <= DATA;
                    dibit <= 2'd0;
                    er_seen <= 1'b0;
                end
            default:
                if (!crs && !crs_last) begin
                    // The first low sample was shifted in as a di-bit: a frame that ended on a byte has one.
                    state <= IDLE;
                    rx_end <= 1'b1;
                    rx_error <= er_seen || dibit != 2'd1;
                end else begin
                    if (er) er_seen <= 1'b1;
                    dibit <= dibit + 2'd1;
                    shift <= {rxd, shift[5:2]};
                    if (dibit == 2'd3) begin
                        rx_data <= {rxd, shift};
                        rx_valid <= 1'b1;
                    end
                end
        endcase
    end

    // ---- Send -----------------------------------------------------------------------------------------------
    // A byte goes out over four clocks: its first di-bit on the clock that takes it, then the other three.
    reg [1:0] tx_dibit = 2'd0;
    reg [5:0] tx_shift = 6'd0;
    assign tx_ready = tx_valid && tx_dibit == 2'd0;

    always @(posedge clk) begin
        if (tx_dibit != 2'd0) begin
            rmii_txd <= tx_shift[1:0];
            tx_shift <= {2'b00, tx_shift[5:2]};
            tx_dibit <= tx_dibit + 2'd1;
        end else if (tx_ready) begin
            rmii_txd <= tx_data[1:0];
            tx_shift <= tx_data[7:2];
            tx_dibit <= 2'd1;
            rmii_tx_en <= 1'b1;
        end else begin
            rmii_txd <= 2'b00;
            rmii_tx_en <= 1'b0;
        end
    end
endmodule
