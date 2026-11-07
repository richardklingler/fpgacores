// eth_mac_10g — a 10 Gigabit Ethernet MAC on 64-bit XGMII blocks (eth_10gbase_r_pcs), a block a cycle on the
// transceiver's clocks (161.13 MHz). CC0 1.0 (public domain).
//
// Transmit (tx_clk): connect xgmii_tx_ready to the PCS's xgmii_tx_ready; the MAC's block register moves when the PCS
// takes it. A frame is tx_data words (destination MAC first, lane 0 = bits 7:0 first) with tx_valid high from the first
// word to tx_last; tx_ready follows the PCS's pauses (one cycle in 33) and doesn't depend on tx_valid. 10G can't pause a
// frame: tx_keep marks the last word's bytes (1, 3, 7 … FF). The MAC sends start and preamble as a block, pads to 60
// bytes, appends the FCS (CRC-32), the terminate, and at least 12 bytes of idle before the next start (lane 0). A missing
// word (an underrun) sends an error block and a terminate; the frame's remaining words are taken and dropped up to
// tx_last.
// Receive (rx_clk): frames starting in lane 0 or lane 4 (a switch starts in either), at least 5 bytes apart, as IEEE asks
// of a receiver; the FCS is checked and taken off. rx_data words come with rx_valid, rx_last on the last (rx_keep its
// bytes) and rx_error there when the FCS was wrong, the frame was shorter than 64 bytes or held an error character.
// rx_frames and rx_bad_frames count them.
module eth_mac_10g (
    // Transmit, on tx_clk.
    input  wire        tx_clk,
    input  wire [63:0] tx_data,
    input  wire [7:0]  tx_keep,
    input  wire        tx_valid,
    input  wire        tx_last,
    output wire        tx_ready,
    input  wire        xgmii_tx_ready,
    output reg  [63:0] xgmii_txd = {8{8'h07}},
    output reg  [7:0]  xgmii_txc = 8'hFF,

    // Receive, on rx_clk.
    input  wire        rx_clk,
    input  wire [63:0] xgmii_rxd,
    input  wire [7:0]  xgmii_rxc,
    input  wire        xgmii_rx_valid,
    output reg  [63:0] rx_data = 64'd0,
    output reg  [7:0]  rx_keep = 8'd0,
    output reg         rx_valid = 1'b0,
    output reg         rx_last = 1'b0,
    output reg         rx_error = 1'b0,
    output reg  [31:0] rx_frames = 32'd0,
    output reg  [31:0] rx_bad_frames = 32'd0
);
    localparam [7:0] IDLE = 8'h07, START = 8'hFB, TERM = 8'hFD, ERROR = 8'hFE;
    localparam [63:0] PREAMBLE = 64'hD5555555555555FB;
    localparam [31:0] RESIDUE = 32'hDEBB20E3;          // the CRC register after a frame and its own FCS

    // Bytes in a keep mask (contiguous from lane 0): 1 … 8.
    function [3:0] count_of(input [7:0] keep);
        count_of = keep[7] ? 4'd8 : keep[6] ? 4'd7 : keep[5] ? 4'd6 : keep[4] ? 4'd5 :
                   keep[3] ? 4'd4 : keep[2] ? 4'd3 : keep[1] ? 4'd2 : 4'd1;
    endfunction
    function [7:0] mask_of(input [3:0] n);           // the first n lanes
        mask_of = 8'hFF >> (4'd8 - n);
    endfunction

    // ==== Transmit ======================================================================================================
    // Every step moves when the PCS takes a block (`adv`). Tokens go through two registers to the block register: `h`
    // (a word taken from the user or padding, with its CRC data shares), `c` (the CRC through that word, and for a last
    // word the CRC after its bytes, so the block can carry the FCS).
    wire adv = xgmii_tx_ready;
    localparam K_IDLE = 3'd0, K_PRE = 3'd1, K_WORD = 3'd2, K_TAIL = 3'd3, K_TERM = 3'd4;
    localparam S_IDLE = 3'd0, S_DATA = 3'd1, S_PAD = 3'd2, S_TAIL = 3'd3, S_GAP = 3'd4, S_DROP = 3'd5;
    reg [2:0] state = S_IDLE;
    reg [3:0] words = 4'd0;                            // words of the frame so far, up to 8 (64 bytes)
    reg [1:0] gap = 2'd0;                              // idle blocks still due
    reg [3:0] last_n = 4'd8;

    // The user's word now, padded: a frame shorter than 60 bytes gets zero words up to the 8th, which holds 4 bytes.
    wire [3:0] keep_n = count_of(tx_keep);
    wire want = state == S_DATA;
    assign tx_ready = adv && (want || (state == S_DROP && tx_valid));
    wire [63:0] user_word = tx_data & {{8{tx_keep[7]}}, {8{tx_keep[6]}}, {8{tx_keep[5]}}, {8{tx_keep[4]}},
                                       {8{tx_keep[3]}}, {8{tx_keep[2]}}, {8{tx_keep[1]}}, {8{tx_keep[0]}}};
    // A last word before the 8th is sent whole (padding follows); as the 8th it holds at least 4 bytes.
    wire user_short = tx_last && words < 4'd7;
    wire [3:0] user_n = !tx_last ? 4'd8 : user_short ? 4'd8 : words == 4'd7 && keep_n < 4'd4 ? 4'd4 : keep_n;

    reg [2:0] h_kind = K_IDLE;
    reg [63:0] h_word = 64'd0;
    reg [3:0] h_n = 4'd8;
    reg h_last = 1'b0, h_error = 1'b0;
    wire [255:0] h_shares_in;                          // the data's CRC share after 1 … 8 bytes of the word entering h
    reg [31:0] h_share8 = 32'd0, h_share_n = 32'd0;
    wire [63:0] h_in = state == S_PAD ? 64'd0 : user_word;
    wire [3:0] h_in_n = state == S_PAD ? (words == 4'd7 ? 4'd4 : 4'd8) : user_n;
    eth_mac_10g_crc u_tx_data (.crc(32'd0), .data(h_in), .crcs(h_shares_in));
    function [31:0] share(input [255:0] s, input [3:0] n);
        share = s[32 * (n - 1) +: 32];
    endfunction

    always @(posedge tx_clk) if (adv) begin
        h_kind <= K_IDLE; h_last <= 1'b0; h_error <= 1'b0;
        h_word <= h_in; h_n <= h_in_n; h_share8 <= h_shares_in[255:224]; h_share_n <= share(h_shares_in, h_in_n);
        case (state)
            S_IDLE: if (tx_valid) begin h_kind <= K_PRE; state <= S_DATA; words <= 4'd0; end
            S_DATA: begin
                h_kind <= K_WORD;
                if (!tx_valid) begin
                    // An underrun: an error block, a terminate, then the rest of the frame is dropped.
                    h_last <= 1'b1; h_error <= 1'b1; state <= S_DROP; last_n <= 4'd8;
                end else begin
                    if (words != 4'd8) words <= words + 4'd1;
                    if (tx_last) begin
                        if (user_short) state <= S_PAD;
                        else begin h_last <= 1'b1; last_n <= user_n; state <= user_n >= 4'd4 ? S_TAIL : S_GAP; end
                        gap <= user_n >= 4'd4 ? 2'd1 : 2'd2;
                    end
                end
            end
            S_PAD: begin
                h_kind <= K_WORD;
                words <= words + 4'd1;
                if (words == 4'd7) begin h_last <= 1'b1; last_n <= 4'd4; state <= S_TAIL; gap <= 2'd1; end
            end
            S_TAIL: begin h_kind <= K_TAIL; state <= S_GAP; end
            S_GAP: begin gap <= gap - 2'd1; if (gap == 2'd1) state <= S_IDLE; end
            default: begin                              // S_DROP: the terminate goes out now, the user's words are dropped
                if (words != 4'd15) begin h_kind <= K_TERM; words <= 4'd15; end
                if (tx_valid && tx_last) begin state <= S_GAP; gap <= 2'd1; end
            end
        endcase
    end

    // The CRC in two shares (it's linear): the data's (from h), the state's (from the CRC register).
    wire [255:0] state_shares;
    reg [31:0] crc = 32'hFFFFFFFF, c_fcs = 32'd0;
    eth_mac_10g_crc u_tx_state (.crc(crc), .data(64'd0), .crcs(state_shares));
    reg [2:0] c_kind = K_IDLE;
    reg [63:0] c_word = 64'd0;
    reg [3:0] c_n = 4'd8, tail_n = 4'd8;
    reg c_last = 1'b0, c_error = 1'b0;
    reg [31:0] tail_fcs = 32'd0;
    always @(posedge tx_clk) if (adv) begin
        c_kind <= h_kind; c_word <= h_word; c_n <= h_n; c_last <= h_last; c_error <= h_error;
        if (h_kind == K_PRE) crc <= 32'hFFFFFFFF;
        else if (h_kind == K_WORD) crc <= share(state_shares, 4'd8) ^ h_share8;
        c_fcs <= ~(share(state_shares, h_n) ^ h_share_n);
    end

    // The block: a last word of n bytes, then the FCS (low byte first), the terminate and idles as far as they fit;
    // the FCS bytes left over (a last word of 4 or more bytes) go in the tail block.
    function [71:0] last_block(input [63:0] w, input [3:0] n, input [31:0] f);     // {control, data}
        reg [159:0] seq;
        reg [15:0] ctrl;
        begin
            seq = {64'd0, {7{IDLE}}, TERM, f} << (8 * n);
            ctrl = 16'hFFF0 << n;
            last_block = {ctrl[7:0], seq[63:0] | (w & ({64{1'b1}} >> (8 * (8 - n))))};
        end
    endfunction
    function [71:0] tail_block(input [3:0] n, input [31:0] f);
        reg [95:0] seq;
        reg [7:0] ctrl;
        begin
            seq = {{7{IDLE}}, TERM, f} >> (8 * (8 - n));               // the 8 - n bytes already sent go
            ctrl = 8'hFF << (n - 4'd4);
            tail_block = {ctrl, seq[63:0]};
        end
    endfunction
    always @(posedge tx_clk) if (adv) begin
        tail_n <= c_n; if (c_kind == K_WORD && c_last) tail_fcs <= c_fcs;
        case (c_kind)
            K_PRE: {xgmii_txc, xgmii_txd} <= {8'h01, PREAMBLE};
            K_WORD: {xgmii_txc, xgmii_txd} <= c_error ? {8'hFF, {8{ERROR}}} : c_last ? last_block(c_word, c_n, c_fcs) :
                                                         {8'h00, c_word};
            K_TAIL: {xgmii_txc, xgmii_txd} <= tail_block(tail_n, tail_fcs);
            K_TERM: {xgmii_txc, xgmii_txd} <= {8'hFF, {7{IDLE}}, TERM};
            default: {xgmii_txc, xgmii_txd} <= {8'hFF, {8{IDLE}}};
        endcase
    end

    // ==== Receive =======================================================================================================
    // Steps: the block is registered with its start flags (`p`: the start check is a 72-bit compare — kept out of the
    // realignment's select); a frame starting in lane 4 is realigned so every frame's preamble fills a word (`a`); its
    // flags and the data's CRC shares are registered (`in`); the frame's state and CRC (`r`); its end checked a cycle
    // later (`done`).
    reg [63:0] p_d = {8{IDLE}}, prev_d = {8{IDLE}};
    reg [7:0] p_c = 8'hFF, prev_c = 8'hFF;
    reg p_v = 1'b0, p_start0 = 1'b0, p_start4 = 1'b0;
    reg lane4 = 1'b0;
    always @(posedge rx_clk) begin
        p_v <= xgmii_rx_valid;
        if (xgmii_rx_valid) begin
            p_d <= xgmii_rxd; p_c <= xgmii_rxc;
            p_start0 <= xgmii_rxc == 8'h01 && xgmii_rxd == PREAMBLE;
            p_start4 <= xgmii_rxc[7:4] == 4'b0001 && xgmii_rxd[63:32] == 32'h555555FB;   // after idles or an ordered set
        end
    end
    wire [63:0] a_d = p_start0 || !lane4 ? p_d : {p_d[31:0], prev_d[63:32]};
    wire [7:0] a_c = p_start0 || !lane4 ? p_c : {p_c[3:0], prev_c[7:4]};
    always @(posedge rx_clk) if (p_v) begin
        prev_d <= p_d; prev_c <= p_c;
        if (p_start0) lane4 <= 1'b0; else if (p_start4) lane4 <= 1'b1;
    end

    // The first control lane (8 = none) and whether it's a terminate.
    function [3:0] first_control(input [7:0] c);
        first_control = c[0] ? 4'd0 : c[1] ? 4'd1 : c[2] ? 4'd2 : c[3] ? 4'd3 : c[4] ? 4'd4 : c[5] ? 4'd5 :
                        c[6] ? 4'd6 : c[7] ? 4'd7 : 4'd8;
    endfunction
    wire [255:0] a_shares;
    eth_mac_10g_crc u_rx_data (.crc(32'd0), .data(a_d), .crcs(a_shares));
    reg [63:0] in_d = 64'd0;
    reg [255:0] in_shares = 256'd0;
    reg in_v = 1'b0, in_data = 1'b0, in_pre = 1'b0, in_term = 1'b0;
    reg [3:0] in_lane = 4'd8;
    wire [3:0] a_lane = first_control(a_c);
    always @(posedge rx_clk) begin
        in_v <= p_v;
        if (p_v) begin
            in_d <= a_d; in_shares <= a_shares;
            in_data <= a_c == 8'h00;
            in_pre <= a_c == 8'h01 && a_d == PREAMBLE;
            in_lane <= a_lane;
            in_term <= a_lane != 4'd8 && a_d[8 * a_lane[2:0] +: 8] == TERM;
        end
    end

    localparam R_IDLE = 1'b0, R_DATA = 1'b1;
    reg r_state = R_IDLE;
    reg [31:0] r_crc = 32'hFFFFFFFF;
    reg [3:0] r_words = 4'd0;                          // whole data words, up to 8: 64 bytes with the FCS
    wire [255:0] r_state_shares;
    eth_mac_10g_crc u_rx_state (.crc(r_crc), .data(64'd0), .crcs(r_state_shares));
    // The last word held back: the FCS is in it (or in it and the terminate's word) when the terminate comes.
    reg [63:0] w1 = 64'd0;
    reg w1_ok = 1'b0;
    reg fin = 1'b0, fin_term = 1'b0, fin_long = 1'b0;
    reg [3:0] fin_k = 4'd0;
    reg [63:0] fin_d = 64'd0;
    reg [255:0] fin_crcs = 256'd0;                     // the CRC after 1 … 8 of the terminate word's bytes
    reg [31:0] fin_crc0 = 32'd0;
    integer kf;
    always @(posedge rx_clk) begin
        fin <= 1'b0;
        if (in_v) case (r_state)
            R_IDLE: if (in_pre) begin r_state <= R_DATA; r_crc <= 32'hFFFFFFFF; r_words <= 4'd0; w1_ok <= 1'b0; end
            default: begin
                if (in_data) begin
                    r_crc <= share(r_state_shares, 4'd8) ^ in_shares[255:224];
                    if (r_words != 4'd8) r_words <= r_words + 4'd1;
                    w1 <= in_d; w1_ok <= 1'b1;
                end else begin
                    r_state <= in_pre ? R_DATA : R_IDLE;
                    if (in_pre) begin r_crc <= 32'hFFFFFFFF; r_words <= 4'd0; end
                    fin <= 1'b1; fin_k <= in_lane; fin_term <= in_term; fin_long <= r_words == 4'd8; fin_d <= in_d;
                    fin_crc0 <= r_crc;
                    for (kf = 0; kf < 8; kf = kf + 1) fin_crcs[32 * kf +: 32] <= r_state_shares[32 * kf +: 32] ^ in_shares[32 * kf +: 32];
                end
            end
        endcase
    end

    // Compared with the residue a cycle later; then the words go out: a terminate in lane k means the frame's last k
    // bytes are in that word, the FCS the last four of the frame.
    wire [8:0] fin_match;
    assign fin_match[0] = fin_crc0 == RESIDUE;
    genvar gm;
    generate for (gm = 1; gm <= 8; gm = gm + 1) begin : g_match
        assign fin_match[gm] = fin_crcs[32 * (gm - 1) +: 32] == RESIDUE;
    end endgenerate
    reg done = 1'b0, done_good = 1'b0, done_had = 1'b0;
    reg [3:0] done_k = 4'd0;
    reg [63:0] done_w1 = 64'd0, done_d = 64'd0;
    // A word that's out of the hold before the frame ends: emitted as the next one replaces it.
    reg [63:0] pend_data = 64'd0;
    reg [7:0] pend_keep = 8'd0;
    reg pend = 1'b0, pend_error = 1'b0;
    reg was_data = 1'b0, was_ok = 1'b0;
    reg [63:0] was_w1 = 64'd0;
    always @(posedge rx_clk) begin
        rx_valid <= 1'b0; rx_last <= 1'b0; rx_error <= 1'b0;
        // While data words arrive, the word before the held one goes out.
        was_data <= in_v && r_state == R_DATA && in_data; was_ok <= w1_ok; was_w1 <= w1;
        if (was_data && was_ok) begin rx_data <= was_w1; rx_keep <= 8'hFF; rx_valid <= 1'b1; end
        done <= fin; done_good <= fin_term && fin_long && fin_match[fin_k]; done_k <= fin_k; done_d <= fin_d;
        done_w1 <= w1; done_had <= w1_ok;
        if (pend) begin
            rx_data <= pend_data; rx_keep <= pend_keep; rx_valid <= 1'b1; rx_last <= 1'b1; rx_error <= pend_error;
            pend <= 1'b0;
        end
        if (done) begin
            if (done_good) rx_frames <= rx_frames + 32'd1; else rx_bad_frames <= rx_bad_frames + 32'd1;
            if (done_had) begin
                if (done_k >= 4'd5) begin            // the held word whole, then k - 4 bytes of the terminate's word
                    rx_data <= done_w1; rx_keep <= 8'hFF; rx_valid <= 1'b1;
                    pend <= 1'b1; pend_data <= done_d; pend_keep <= mask_of(done_k - 4'd4); pend_error <= !done_good;
                end else begin                       // the held word's first k + 4 bytes are the last
                    rx_data <= done_w1; rx_keep <= mask_of(done_k + 4'd4); rx_valid <= 1'b1; rx_last <= 1'b1;
                    rx_error <= !done_good;
                end
            end
        end
    end
endmodule

// The CRC-32 (IEEE 802.3, reflected, 0xEDB88320, lane 0 first) after one to eight bytes, as a flat XOR per bit: bit i
// is the XOR of the state and data bits these masks pick (the CRC is linear in both), computed at elaboration from the
// byte-wise definition. crcs holds the CRC after n bytes at 32 (n - 1).
module eth_mac_10g_crc (
    input  wire [31:0]  crc,
    input  wire [63:0]  data,
    output wire [255:0] crcs
);
    function [31:0] serial(input [31:0] c, input [63:0] d, input integer n);
        integer i, k;
        reg [31:0] x;
        begin
            x = c;
            for (k = 0; k < 8; k = k + 1)
                if (k < n) for (i = 0; i < 8; i = i + 1) x = (x >> 1) ^ ((x[0] ^ d[8 * k + i]) ? 32'hEDB88320 : 32'd0);
            serial = x;
        end
    endfunction
    function [31:0] state_mask(input integer n, input integer which);
        integer j;
        reg [31:0] x;
        begin
            for (j = 0; j < 32; j = j + 1) begin x = serial(32'd1 << j, 64'd0, n); state_mask[j] = x[which]; end
        end
    endfunction
    function [63:0] data_mask(input integer n, input integer which);
        integer j;
        reg [31:0] x;
        begin
            for (j = 0; j < 64; j = j + 1) begin x = serial(32'd0, 64'd1 << j, n); data_mask[j] = x[which]; end
        end
    endfunction
    genvar n, b;
    generate for (n = 1; n <= 8; n = n + 1) begin : g_n
        for (b = 0; b < 32; b = b + 1) begin : g_b
            localparam [31:0] SM = state_mask(n, b);
            localparam [63:0] DM = data_mask(n, b);
            assign crcs[32 * (n - 1) + b] = ^(crc & SM) ^ ^(data & DM);
        end
    end endgenerate
endmodule
