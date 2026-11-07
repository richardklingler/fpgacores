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
// is the XOR of the state and data bits these masks pick (the CRC is linear in both). crcs holds the CRC after n bytes
// at 32 (n - 1). The masks are constants written by FPGALab's tools/eth-mac-10g-crc-masks.py from the byte-wise
// definition (computing them in Verilog functions cost Yosys minutes at elaboration); the testbench checks the result
// against its own bit-by-bit CRC.
module eth_mac_10g_crc (
    input  wire [31:0]  crc,
    input  wire [63:0]  data,
    output wire [255:0] crcs
);
    // Mask of output bit b after n bytes at 32 (n - 1) + b: 32 state bits each, 64 data bits each.
    localparam [8191:0] STATE_MASKS = {
        32'ha40da72d, 32'h760b74bb, 32'h9f081d70, 32'hcf840eb8, 32'h43cfa071, 32'h05ea7715, 32'h02f53b8a, 32'ha5773ae8,
        32'hf6b63a59, 32'hfb5b1d2c, 32'hd9a029bb, 32'h48ddb3f0, 32'h00637ed5, 32'h8031bf6a, 32'hc018dfb5, 32'h600c6fda,
        32'h940b90c0, 32'h4a05c860, 32'ha502e430, 32'hd2817218, 32'h6940b90c, 32'h34a05c86, 32'h3e5d896e, 32'h3b23639a,
        32'h9d91b1cd, 32'h4ec8d8e6, 32'h0369cb5e, 32'h81b4e5af, 32'h40da72d7, 32'h206d396b, 32'h90369cb5, 32'h481b4e5a,
        32'hefa40da7, 32'h98760b74, 32'ha39f081d, 32'h51cf840e, 32'hc743cfa0, 32'h8c05ea77, 32'h4602f53b, 32'hcca5773a,
        32'h09f6b63a, 32'h84fb5b1d, 32'h2dd9a029, 32'hf948ddb3, 32'h9300637e, 32'h498031bf, 32'h24c018df, 32'h92600c6f,
        32'ha6940b90, 32'h534a05c8, 32'ha9a502e4, 32'hd4d28172, 32'h6a6940b9, 32'hb534a05c, 32'hb53e5d89, 32'h353b2363,
        32'h1a9d91b1, 32'h0d4ec8d8, 32'he90369cb, 32'hf481b4e5, 32'hfa40da72, 32'h7d206d39, 32'hbe90369c, 32'hdf481b4e,
        32'h80efa40d, 32'hc098760b, 32'he0a39f08, 32'h7051cf84, 32'h38c743cf, 32'h1c8c05ea, 32'h0e4602f5, 32'h87cca577,
        32'h4309f6b6, 32'h2184fb5b, 32'h902dd9a0, 32'hc8f948dd, 32'h64930063, 32'hb2498031, 32'h5924c018, 32'hac92600c,
        32'h56a6940b, 32'h2b534a05, 32'h15a9a502, 32'h8ad4d281, 32'hc56a6940, 32'h62b534a0, 32'hb1b53e5d, 32'hd8353b23,
        32'hec1a9d91, 32'h760d4ec8, 32'h3be90369, 32'h1df481b4, 32'h0efa40da, 32'h077d206d, 32'h03be9036, 32'h01df481b,
        32'h6880efa4, 32'h5cc09876, 32'hc6e0a39f, 32'he37051cf, 32'h9938c743, 32'h241c8c05, 32'h920e4602, 32'ha187cca5,
        32'hb84309f6, 32'h5c2184fb, 32'h46902dd9, 32'h4bc8f948, 32'h4d649300, 32'h26b24980, 32'h935924c0, 32'hc9ac9260,
        32'h8c56a694, 32'h462b534a, 32'h2315a9a5, 32'h918ad4d2, 32'hc8c56a69, 32'h6462b534, 32'h5ab1b53e, 32'h45d8353b,
        32'h22ec1a9d, 32'h91760d4e, 32'h203be903, 32'h101df481, 32'h880efa40, 32'h44077d20, 32'ha203be90, 32'hd101df48,
        32'h826880ef, 32'hc35cc098, 32'he3c6e0a3, 32'h71e37051, 32'hba9938c7, 32'hdf241c8c, 32'h6f920e46, 32'hb5a187cc,
        32'hd8b84309, 32'h6c5c2184, 32'hb446902d, 32'hd84bc8f9, 32'hee4d6493, 32'h7726b249, 32'h3b935924, 32'h1dc9ac92,
        32'h8c8c56a6, 32'h46462b53, 32'h232315a9, 32'h11918ad4, 32'h08c8c56a, 32'h046462b5, 32'h805ab1b5, 32'hc245d835,
        32'h6122ec1a, 32'h3091760d, 32'h9a203be9, 32'h4d101df4, 32'h26880efa, 32'h1344077d, 32'h09a203be, 32'h04d101df,
        32'h00826880, 32'h00c35cc0, 32'h00e3c6e0, 32'h0071e370, 32'h00ba9938, 32'h00df241c, 32'h006f920e, 32'h00b5a187,
        32'h00d8b843, 32'h006c5c21, 32'h00b44690, 32'h00d84bc8, 32'h00ee4d64, 32'h007726b2, 32'h003b9359, 32'h001dc9ac,
        32'h008c8c56, 32'h0046462b, 32'h00232315, 32'h0011918a, 32'h0008c8c5, 32'h00046462, 32'h00805ab1, 32'h00c245d8,
        32'h806122ec, 32'h40309176, 32'h209a203b, 32'h104d101d, 32'h0826880e, 32'h04134407, 32'h0209a203, 32'h0104d101,
        32'h00008268, 32'h0000c35c, 32'h0000e3c6, 32'h000071e3, 32'h0000ba99, 32'h0000df24, 32'h00006f92, 32'h0000b5a1,
        32'h0000d8b8, 32'h00006c5c, 32'h0000b446, 32'h0000d84b, 32'h0000ee4d, 32'h00007726, 32'h00003b93, 32'h00001dc9,
        32'h80008c8c, 32'h40004646, 32'h20002323, 32'h10001191, 32'h080008c8, 32'h04000464, 32'h0200805a, 32'h0100c245,
        32'h00806122, 32'h00403091, 32'h00209a20, 32'h00104d10, 32'h00082688, 32'h00041344, 32'h000209a2, 32'h000104d1,
        32'h00000082, 32'h000000c3, 32'h000000e3, 32'h00000071, 32'h000000ba, 32'h000000df, 32'h0000006f, 32'h000000b5,
        32'h800000d8, 32'h4000006c, 32'h200000b4, 32'h100000d8, 32'h080000ee, 32'h04000077, 32'h0200003b, 32'h0100001d,
        32'h0080008c, 32'h00400046, 32'h00200023, 32'h00100011, 32'h00080008, 32'h00040004, 32'h00020080, 32'h000100c2,
        32'h00008061, 32'h00004030, 32'h0000209a, 32'h0000104d, 32'h00000826, 32'h00000413, 32'h00000209, 32'h00000104
    };
    localparam [16383:0] DATA_MASKS = {
        64'h826880efa40da72d, 64'hc35cc098760b74bb, 64'he3c6e0a39f081d70, 64'h71e37051cf840eb8, 64'hba9938c743cfa071, 64'hdf241c8c05ea7715, 64'h6f920e4602f53b8a, 64'hb5a187cca5773ae8,
        64'hd8b84309f6b63a59, 64'h6c5c2184fb5b1d2c, 64'hb446902dd9a029bb, 64'hd84bc8f948ddb3f0, 64'hee4d649300637ed5, 64'h7726b2498031bf6a, 64'h3b935924c018dfb5, 64'h1dc9ac92600c6fda,
        64'h8c8c56a6940b90c0, 64'h46462b534a05c860, 64'h232315a9a502e430, 64'h11918ad4d2817218, 64'h08c8c56a6940b90c, 64'h046462b534a05c86, 64'h805ab1b53e5d896e, 64'hc245d8353b23639a,
        64'h6122ec1a9d91b1cd, 64'h3091760d4ec8d8e6, 64'h9a203be90369cb5e, 64'h4d101df481b4e5af, 64'h26880efa40da72d7, 64'h1344077d206d396b, 64'h09a203be90369cb5, 64'h04d101df481b4e5a,
        64'h00826880efa40da7, 64'h00c35cc098760b74, 64'h00e3c6e0a39f081d, 64'h0071e37051cf840e, 64'h00ba9938c743cfa0, 64'h00df241c8c05ea77, 64'h006f920e4602f53b, 64'h00b5a187cca5773a,
        64'h00d8b84309f6b63a, 64'h006c5c2184fb5b1d, 64'h00b446902dd9a029, 64'h00d84bc8f948ddb3, 64'h00ee4d649300637e, 64'h007726b2498031bf, 64'h003b935924c018df, 64'h001dc9ac92600c6f,
        64'h008c8c56a6940b90, 64'h0046462b534a05c8, 64'h00232315a9a502e4, 64'h0011918ad4d28172, 64'h0008c8c56a6940b9, 64'h00046462b534a05c, 64'h00805ab1b53e5d89, 64'h00c245d8353b2363,
        64'h006122ec1a9d91b1, 64'h003091760d4ec8d8, 64'h009a203be90369cb, 64'h004d101df481b4e5, 64'h0026880efa40da72, 64'h001344077d206d39, 64'h0009a203be90369c, 64'h0004d101df481b4e,
        64'h0000826880efa40d, 64'h0000c35cc098760b, 64'h0000e3c6e0a39f08, 64'h000071e37051cf84, 64'h0000ba9938c743cf, 64'h0000df241c8c05ea, 64'h00006f920e4602f5, 64'h0000b5a187cca577,
        64'h0000d8b84309f6b6, 64'h00006c5c2184fb5b, 64'h0000b446902dd9a0, 64'h0000d84bc8f948dd, 64'h0000ee4d64930063, 64'h00007726b2498031, 64'h00003b935924c018, 64'h00001dc9ac92600c,
        64'h00008c8c56a6940b, 64'h000046462b534a05, 64'h0000232315a9a502, 64'h000011918ad4d281, 64'h000008c8c56a6940, 64'h0000046462b534a0, 64'h0000805ab1b53e5d, 64'h0000c245d8353b23,
        64'h00006122ec1a9d91, 64'h00003091760d4ec8, 64'h00009a203be90369, 64'h00004d101df481b4, 64'h000026880efa40da, 64'h00001344077d206d, 64'h000009a203be9036, 64'h000004d101df481b,
        64'h000000826880efa4, 64'h000000c35cc09876, 64'h000000e3c6e0a39f, 64'h00000071e37051cf, 64'h000000ba9938c743, 64'h000000df241c8c05, 64'h0000006f920e4602, 64'h000000b5a187cca5,
        64'h000000d8b84309f6, 64'h0000006c5c2184fb, 64'h000000b446902dd9, 64'h000000d84bc8f948, 64'h000000ee4d649300, 64'h0000007726b24980, 64'h0000003b935924c0, 64'h0000001dc9ac9260,
        64'h0000008c8c56a694, 64'h00000046462b534a, 64'h000000232315a9a5, 64'h00000011918ad4d2, 64'h00000008c8c56a69, 64'h000000046462b534, 64'h000000805ab1b53e, 64'h000000c245d8353b,
        64'h0000006122ec1a9d, 64'h0000003091760d4e, 64'h0000009a203be903, 64'h0000004d101df481, 64'h00000026880efa40, 64'h0000001344077d20, 64'h00000009a203be90, 64'h00000004d101df48,
        64'h00000000826880ef, 64'h00000000c35cc098, 64'h00000000e3c6e0a3, 64'h0000000071e37051, 64'h00000000ba9938c7, 64'h00000000df241c8c, 64'h000000006f920e46, 64'h00000000b5a187cc,
        64'h00000000d8b84309, 64'h000000006c5c2184, 64'h00000000b446902d, 64'h00000000d84bc8f9, 64'h00000000ee4d6493, 64'h000000007726b249, 64'h000000003b935924, 64'h000000001dc9ac92,
        64'h000000008c8c56a6, 64'h0000000046462b53, 64'h00000000232315a9, 64'h0000000011918ad4, 64'h0000000008c8c56a, 64'h00000000046462b5, 64'h00000000805ab1b5, 64'h00000000c245d835,
        64'h000000006122ec1a, 64'h000000003091760d, 64'h000000009a203be9, 64'h000000004d101df4, 64'h0000000026880efa, 64'h000000001344077d, 64'h0000000009a203be, 64'h0000000004d101df,
        64'h0000000000826880, 64'h0000000000c35cc0, 64'h0000000000e3c6e0, 64'h000000000071e370, 64'h0000000000ba9938, 64'h0000000000df241c, 64'h00000000006f920e, 64'h0000000000b5a187,
        64'h0000000000d8b843, 64'h00000000006c5c21, 64'h0000000000b44690, 64'h0000000000d84bc8, 64'h0000000000ee4d64, 64'h00000000007726b2, 64'h00000000003b9359, 64'h00000000001dc9ac,
        64'h00000000008c8c56, 64'h000000000046462b, 64'h0000000000232315, 64'h000000000011918a, 64'h000000000008c8c5, 64'h0000000000046462, 64'h0000000000805ab1, 64'h0000000000c245d8,
        64'h00000000006122ec, 64'h0000000000309176, 64'h00000000009a203b, 64'h00000000004d101d, 64'h000000000026880e, 64'h0000000000134407, 64'h000000000009a203, 64'h000000000004d101,
        64'h0000000000008268, 64'h000000000000c35c, 64'h000000000000e3c6, 64'h00000000000071e3, 64'h000000000000ba99, 64'h000000000000df24, 64'h0000000000006f92, 64'h000000000000b5a1,
        64'h000000000000d8b8, 64'h0000000000006c5c, 64'h000000000000b446, 64'h000000000000d84b, 64'h000000000000ee4d, 64'h0000000000007726, 64'h0000000000003b93, 64'h0000000000001dc9,
        64'h0000000000008c8c, 64'h0000000000004646, 64'h0000000000002323, 64'h0000000000001191, 64'h00000000000008c8, 64'h0000000000000464, 64'h000000000000805a, 64'h000000000000c245,
        64'h0000000000006122, 64'h0000000000003091, 64'h0000000000009a20, 64'h0000000000004d10, 64'h0000000000002688, 64'h0000000000001344, 64'h00000000000009a2, 64'h00000000000004d1,
        64'h0000000000000082, 64'h00000000000000c3, 64'h00000000000000e3, 64'h0000000000000071, 64'h00000000000000ba, 64'h00000000000000df, 64'h000000000000006f, 64'h00000000000000b5,
        64'h00000000000000d8, 64'h000000000000006c, 64'h00000000000000b4, 64'h00000000000000d8, 64'h00000000000000ee, 64'h0000000000000077, 64'h000000000000003b, 64'h000000000000001d,
        64'h000000000000008c, 64'h0000000000000046, 64'h0000000000000023, 64'h0000000000000011, 64'h0000000000000008, 64'h0000000000000004, 64'h0000000000000080, 64'h00000000000000c2,
        64'h0000000000000061, 64'h0000000000000030, 64'h000000000000009a, 64'h000000000000004d, 64'h0000000000000026, 64'h0000000000000013, 64'h0000000000000009, 64'h0000000000000004
    };
    genvar i;
    generate for (i = 0; i < 256; i = i + 1) begin : g_bit
        assign crcs[i] = ^(crc & STATE_MASKS[32 * i +: 32]) ^ ^(data & DATA_MASKS[64 * i +: 64]);
    end endgenerate
endmodule
