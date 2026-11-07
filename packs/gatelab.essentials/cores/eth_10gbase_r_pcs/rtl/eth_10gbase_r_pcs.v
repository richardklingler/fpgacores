// eth_10gbase_r_pcs — the 10GBASE-R PCS (IEEE 802.3 clause 49) between 64-bit XGMII blocks and a transceiver's 64B/66B
// gearbox at a block a cycle (gtx_10g's tx_sequence / tx_data / tx_header and rx_data / rx_header / rx_data_valid /
// rx_header_valid / rx_slip, 161.13 MHz). CC0 1.0 (public domain).
//
// Transmit (tx_clk): xgmii_tx_ready says the PCS takes a block this cycle (every cycle but the gearbox's pause);
// xgmii_tx_ready_next says it a cycle ahead, for a client that registers its blocks (eth_mac_10g). Each block is encoded
// into a 66-bit block — data, idle/error, start in lane 0 or 4, terminate in any lane; anything else becomes an error
// block — scrambled (x^58 + x^39 + 1, self-synchronising) and sent three blocks later.
// Receive (rx_clk): block lock from the sync headers (64 valid in a row; 16 invalid in 64 lose it), rx_slip moves the
// block boundary while unlocked, the payload is descrambled and decoded — also start in lane 4, ordered sets (lane 0, 4
// or both, as XGMII sequence 0x9C) — and comes out a block a cycle (xgmii_rx_valid). Invalid headers, block types and
// control codes give an error block (all lanes /E/) and count in rx_error_blocks. high_ber: 16 invalid headers within
// BER_WINDOW blocks (125 us). rx_restart (high for 16 cycles) asks the transceiver to reset its receiver when block lock stays lost for
// RESTART_BLOCKS blocks: a pulled fibre doesn't stop the transceiver's recovered clock, so nothing else would.
//
// Bit order: the wire carries the sync header first, then payload bit 0 first. BIT_REVERSE 1: the transceiver sends a
// port's most significant bit first (header[1] then header[0], data[63] … data[0]); 0: the least significant first.
// Both ends of a link built with this core agree either way; a foreign partner (a switch) needs the transceiver's real
// order. SCRAMBLER 0 leaves the payload unscrambled (for tests only).
//
// XGMII lanes: lane n is bits 8n+7:8n of xgmii_txd / xgmii_rxd, lane 0 is sent first; xgmii_txc / xgmii_rxc bit n marks a
// control character (0x07 idle, 0xFB start, 0xFD terminate, 0xFE error, 0x9C sequence).
module eth_10gbase_r_pcs #(
    parameter BIT_REVERSE = 1,
    parameter SCRAMBLER = 1,
    // Blocks in 125 us at 10.3125 Gb/s.
    parameter BER_WINDOW = 19531,
    // rx_clk cycles after a slip before headers count again.
    parameter SLIP_WAIT = 64,
    // Blocks without block lock before rx_restart (2^21: 13 ms; a slip search takes well under 1 ms). 0: never.
    parameter RESTART_BLOCKS = 2097152
) (
    // Transmit, on tx_clk.
    input  wire        tx_clk,
    input  wire [5:0]  tx_sequence,
    input  wire [63:0] xgmii_txd,
    input  wire [7:0]  xgmii_txc,
    output wire        xgmii_tx_ready,
    output reg         xgmii_tx_ready_next = 1'b0,
    output wire [63:0] tx_data,
    output wire [1:0]  tx_header,

    // Receive, on rx_clk.
    input  wire        rx_clk,
    input  wire        rx_reset,
    input  wire [63:0] rx_data,
    input  wire [1:0]  rx_header,
    input  wire        rx_data_valid,
    input  wire        rx_header_valid,
    output reg         rx_slip = 1'b0,
    output reg         rx_restart = 1'b0,
    output reg  [63:0] xgmii_rxd = {8{8'h07}},
    output reg  [7:0]  xgmii_rxc = 8'hFF,
    output reg         xgmii_rx_valid = 1'b0,
    output reg         block_lock = 1'b0,
    output reg         high_ber = 1'b0,
    output reg  [31:0] rx_error_blocks = 32'd0
);
    localparam [7:0] IDLE = 8'h07, START = 8'hFB, TERM = 8'hFD, ERROR = 8'hFE, SEQ = 8'h9C;
    // Sync headers as {second bit, first bit}: data 01 on the wire, control 10.
    localparam [1:0] SYNC_DATA = 2'b10, SYNC_CTRL = 2'b01;

    // ---- Control characters ------------------------------------------------------------------------------------------
    function [6:0] code7(input [7:0] c);              // XGMII -> 64B/66B: idle 0x00, everything else an error 0x1E
        code7 = c == IDLE ? 7'h00 : 7'h1E;
    endfunction
    function bad7(input [6:0] c);
        bad7 = c != 7'h00 && c != 7'h1E;
    endfunction

    // ---- Scrambler, a block at a time: bit i takes the scrambled bits 39 and 58 earlier in the stream — from the last
    // block, or for the upper bits from this one ------------------------------------------------------------------------
    function [63:0] scramble(input [63:0] d, input [63:0] previous);
        reg [63:0] o;
        begin
            o[38:0] = d[38:0] ^ previous[63:25] ^ previous[44:6];
            o[57:39] = d[57:39] ^ o[18:0] ^ previous[63:45];
            o[63:58] = d[63:58] ^ o[24:19] ^ o[5:0];
            scramble = o;
        end
    endfunction
    function [63:0] descramble(input [63:0] d, input [63:0] previous);
        descramble = d ^ {d[24:0], previous[63:25]} ^ {d[5:0], previous[63:6]};
    endfunction
    function [63:0] reverse64(input [63:0] v);
        integer i;
        for (i = 0; i < 64; i = i + 1) reverse64[i] = v[63 - i];
    endfunction

    // ==== Transmit ======================================================================================================
    // Three steps, each moving when the gearbox takes a block (`take`), so all move in lockstep across the pause: the
    // block as it comes (`raw`), its format and lanes' 7-bit codes (`fmt`), the assembled block (`asm`); the scrambled
    // block (`out`) is what the gearbox takes this cycle. In every format lane k's code sits at bit 8 + 7k and its data
    // byte at 8k (8k + 8 after a terminate block's type), so the assembly is a small multiplexer per bit.
    // This cycle's and the next one's position in the gearbox, registered from the counter: no comparator in the way.
    wire [5:0] tx_next = tx_sequence == 6'd32 ? 6'd0 : tx_sequence + 6'd1;
    wire [5:0] tx_after = tx_next == 6'd32 ? 6'd0 : tx_next + 6'd1;
    reg take = 1'b0;
    always @(posedge tx_clk) begin take <= tx_next != 6'd32; xgmii_tx_ready_next <= tx_after != 6'd32; end
    assign xgmii_tx_ready = take;

    localparam F_DATA = 0, F_S0 = 1, F_S4 = 2, F_CTRL = 3, F_ERR = 4, F_T0 = 5;   // F_T0 + t: terminate in lane t
    reg [63:0] raw_d = {8{IDLE}};
    reg [7:0] raw_c = 8'hFF;
    always @(posedge tx_clk) if (take) begin raw_d <= xgmii_txd; raw_c <= xgmii_txc; end

    // The format, one-hot (12 kinds), and every lane's code.
    // Every condition against constants (one per terminate lane): no shifter, no comparator on a lane number.
    function [12:0] tx_format(input [63:0] d, input [7:0] c);
        integer t;
        reg any;
        begin
            tx_format = 13'd0;
            for (t = 0; t < 8; t = t + 1)
                tx_format[F_T0 + t] = c == (8'hFF << t) && d[8 * t +: 8] == TERM;
            tx_format[F_DATA] = c == 8'h00;
            tx_format[F_S0] = c == 8'h01 && d[7:0] == START;
            tx_format[F_S4] = c == 8'h1F && d[39:32] == START;
            tx_format[F_CTRL] = c == 8'hFF && d[7:0] != TERM;
            any = |tx_format;
            tx_format[F_ERR] = !any;
        end
    endfunction
    reg [12:0] fmt = 13'd1 << F_CTRL;
    reg [63:0] fmt_d = {8{IDLE}};
    reg [55:0] fmt_codes = 56'd0;                     // lane k's 7-bit code at 7k
    integer kc;
    always @(posedge tx_clk) if (take) begin
        fmt <= tx_format(raw_d, raw_c);
        fmt_d <= raw_d;
        for (kc = 0; kc < 8; kc = kc + 1) fmt_codes[7 * kc +: 7] <= code7(raw_d[8 * kc +: 8]);
    end

    function [7:0] term_type(input integer lane);
        case (lane)
            0: term_type = 8'h87; 1: term_type = 8'h99; 2: term_type = 8'hAA; 3: term_type = 8'hB4;
            4: term_type = 8'hCC; 5: term_type = 8'hD2; 6: term_type = 8'hE1; default: term_type = 8'hFF;
        endcase
    endfunction
    // The block from a format: type byte, data bytes, codes at 8 + 7k — an OR of each format's pattern (the format is
    // one-hot), so no priority chain.
    function [65:0] assemble(input [12:0] f, input [63:0] d, input [55:0] codes);
        reg [63:0] p, q;
        integer k, t;
        begin
            p = {64{f[F_DATA]}} & d;
            p = p | ({64{f[F_S0]}} & {d[63:8], 8'h78});
            p = p | ({64{f[F_S4]}} & {d[63:40], 4'h0, codes[27:0], 8'h33});
            p = p | ({64{f[F_CTRL]}} & {codes, 8'h1E});
            p = p | ({64{f[F_ERR]}} & {{8{7'h1E}}, 8'h1E});
            for (t = 0; t < 8; t = t + 1) begin
                q = {56'd0, term_type(t)};
                for (k = 0; k < t; k = k + 1) q[8 + 8 * k +: 8] = d[8 * k +: 8];
                for (k = t + 1; k < 8; k = k + 1) q[8 + 7 * k +: 7] = codes[7 * k +: 7];
                p = p | ({64{f[F_T0 + t]}} & q);
            end
            assemble = {p, f[F_DATA] ? SYNC_DATA : SYNC_CTRL};
        end
    endfunction
    // Assembled into `asm`, then scrambled into the block the gearbox takes.
    reg [65:0] asm = {64'h1E, SYNC_CTRL};
    reg [63:0] out_p = 64'd0;
    reg [1:0] out_h = SYNC_CTRL;
    always @(posedge tx_clk) if (take) begin
        asm <= assemble(fmt, fmt_d, fmt_codes);
        out_p <= SCRAMBLER ? scramble(asm[65:2], out_p) : asm[65:2];
        out_h <= asm[1:0];
    end
    assign tx_data = BIT_REVERSE ? reverse64(out_p) : out_p;
    assign tx_header = BIT_REVERSE ? {out_h[0], out_h[1]} : out_h;

    // ==== Receive =======================================================================================================
    // The transceiver's outputs registered once on entry: every path below starts at a register here.
    reg [63:0] rx_data_q = 64'd0;
    reg [1:0] rx_header_q = 2'b00;
    reg rx_data_valid_q = 1'b0, rx_header_valid_q = 1'b0;
    always @(posedge rx_clk) begin
        rx_data_q <= rx_data; rx_header_q <= rx_header;
        rx_data_valid_q <= rx_data_valid; rx_header_valid_q <= rx_header_valid;
    end
    wire [63:0] rx_wire = BIT_REVERSE ? reverse64(rx_data_q) : rx_data_q;
    wire [1:0] rx_sync = BIT_REVERSE ? {rx_header_q[0], rx_header_q[1]} : rx_header_q;
    reg [63:0] rx_previous = 64'd0;
    wire [63:0] rx_plain = SCRAMBLER ? descramble(rx_wire, rx_previous) : rx_wire;

    // The block (descrambled) with its type among the known ones and which lanes' code fields are neither idle nor
    // error, then every lane's kind, then the lanes. Lane k's code sits at bit 8 + 7k in every format, its data byte at
    // 8k (8k + 8 in a terminate block).
    localparam K_DATA = 3'd0, K_TDATA = 3'd1, K_CODE = 3'd2, K_START = 3'd3, K_TERM = 3'd4, K_SEQ = 3'd5;
    localparam [7:0] TYPES0 = 8'h1E, TYPES1 = 8'h78, TYPES2 = 8'h33, TYPES3 = 8'h66, TYPES4 = 8'h55, TYPES5 = 8'h4B,
                     TYPES6 = 8'h2D;
    reg [63:0] blk_p = 64'd0;
    reg blk_ready = 1'b0;
    reg [14:0] blk_type = 15'd0;                      // 0-6 as TYPES0-6, 7-14 terminate in lane 0-7
    reg blk_control = 1'b0, blk_invalid = 1'b0;       // the header: control, neither data nor control
    reg [7:0] blk_codes_bad = 8'd0;
    integer kb;
    always @(posedge rx_clk) begin
        blk_ready <= 1'b0;
        if (rx_data_valid_q) begin
            rx_previous <= rx_wire;
            blk_p <= rx_plain; blk_ready <= !rx_reset;
            blk_control <= rx_sync == SYNC_CTRL; blk_invalid <= rx_sync != SYNC_CTRL && rx_sync != SYNC_DATA;
            blk_type <= {rx_plain[7:0] == 8'hFF, rx_plain[7:0] == 8'hE1, rx_plain[7:0] == 8'hD2, rx_plain[7:0] == 8'hCC,
                         rx_plain[7:0] == 8'hB4, rx_plain[7:0] == 8'hAA, rx_plain[7:0] == 8'h99, rx_plain[7:0] == 8'h87,
                         rx_plain[7:0] == TYPES6, rx_plain[7:0] == TYPES5, rx_plain[7:0] == TYPES4,
                         rx_plain[7:0] == TYPES3, rx_plain[7:0] == TYPES2, rx_plain[7:0] == TYPES1,
                         rx_plain[7:0] == TYPES0};
            for (kb = 0; kb < 8; kb = kb + 1) blk_codes_bad[kb] <= bad7(rx_plain[8 + 7 * kb +: 7]);
        end
    end

    // {bad, control bits, 8 lane kinds} from the header, the type (one-hot) and the code checks: an OR of each type's
    // constant pattern (K_DATA is 0), so no priority chain.
    function [23:0] kinds_of(input integer type_index);
        integer k;
        begin
            case (type_index)
                0: kinds_of = {8{K_CODE}};
                1: kinds_of = {{7{K_DATA}}, K_START};
                2: kinds_of = {{3{K_DATA}}, K_START, {4{K_CODE}}};
                3: kinds_of = {{3{K_DATA}}, K_START, {3{K_DATA}}, K_SEQ};
                4: kinds_of = {{3{K_DATA}}, K_SEQ, {3{K_DATA}}, K_SEQ};
                5: kinds_of = {{4{K_CODE}}, {3{K_DATA}}, K_SEQ};
                6: kinds_of = {{3{K_DATA}}, K_SEQ, {4{K_CODE}}};
                default: for (k = 0; k < 8; k = k + 1)              // 7 + t: terminate in lane t
                    kinds_of[3 * k +: 3] = k < type_index - 7 ? K_TDATA : k == type_index - 7 ? K_TERM : K_CODE;
            endcase
        end
    endfunction
    function [7:0] controls_of(input integer type_index);
        case (type_index)
            0: controls_of = 8'hFF; 1: controls_of = 8'h01; 2: controls_of = 8'h1F; 3: controls_of = 8'h11;
            4: controls_of = 8'h11; 5: controls_of = 8'hF1; 6: controls_of = 8'h1F;
            default: controls_of = 8'hFF << (type_index - 7);
        endcase
    endfunction
    function [7:0] coded_lanes(input integer type_index);   // lanes whose code fields must be idle or error
        case (type_index)
            0: coded_lanes = 8'hFF; 2: coded_lanes = 8'h0F; 5: coded_lanes = 8'hF0; 6: coded_lanes = 8'h0F;
            1, 3, 4: coded_lanes = 8'h00;
            default: coded_lanes = 8'hFE << (type_index - 7);
        endcase
    endfunction
    function [32:0] classify(input [14:0] types, input control, input invalid, input [7:0] codes_bad);
        reg [23:0] kinds;
        reg [7:0] c;
        reg bad;
        integer i;
        begin
            kinds = 24'd0; c = 8'h00;
            bad = invalid || (control && types == 15'd0);
            for (i = 0; i < 15; i = i + 1) begin
                kinds = kinds | ({24{control && types[i]}} & kinds_of(i));
                c = c | ({8{control && types[i]}} & controls_of(i));
                bad = bad | (control && types[i] && |(codes_bad & coded_lanes(i)));
            end
            classify = {bad, c, kinds};             // a bad block's lanes become /E/ in the next step
        end
    endfunction
    reg [63:0] cls_p = 64'd0;
    reg [32:0] cls = 33'd0;
    reg [7:0] cls_idle = 8'd0;                        // lane k's code field is idle (0)
    reg cls_ready = 1'b0;
    integer ki;
    always @(posedge rx_clk) begin
        cls_ready <= blk_ready;
        if (blk_ready) begin
            cls <= classify(blk_type, blk_control, blk_invalid, blk_codes_bad); cls_p <= blk_p;
            for (ki = 0; ki < 8; ki = ki + 1) cls_idle[ki] <= blk_p[8 + 7 * ki +: 7] == 7'h00;
        end
    end

    // The lanes from their kinds; a bad block reads /E/ in every lane.
    function [63:0] lanes(input [63:0] p, input [23:0] kinds, input [7:0] idle, input bad);
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1)
                if (bad) lanes[8 * k +: 8] = ERROR;
                else case (kinds[3 * k +: 3])
                    K_DATA: lanes[8 * k +: 8] = p[8 * k +: 8];
                    K_TDATA: lanes[8 * k +: 8] = k < 7 ? p[8 * k + 8 +: 8] : 8'h00;
                    K_START: lanes[8 * k +: 8] = START;
                    K_TERM: lanes[8 * k +: 8] = TERM;
                    K_SEQ: lanes[8 * k +: 8] = SEQ;
                    default: lanes[8 * k +: 8] = idle[k] ? IDLE : ERROR;
                endcase
        end
    endfunction
    always @(posedge rx_clk) begin
        xgmii_rx_valid <= cls_ready;
        if (cls_ready) begin
            xgmii_rxd <= lanes(cls_p, cls[23:0], cls_idle, cls[32]);
            xgmii_rxc <= cls[32] ? 8'hFF : cls[31:24];
            if (cls[32] && block_lock) rx_error_blocks <= rx_error_blocks + 32'd1;
        end
    end

    // ---- Block lock (clause 49.2.13.2.2) and the BER monitor, per received header -------------------------------------
    wire sh_seen = rx_data_valid_q && rx_header_valid_q;
    wire sh_valid = rx_sync[0] ^ rx_sync[1];
    // Counters with registered "full" flags, so the decisions below see single bits: sh_count counts valid headers in a
    // row (unlocked) or blocks of the 64-block window (locked), sh_invalid the invalid ones in that window.
    reg [6:0] sh_count = 7'd0;
    reg [4:0] sh_invalid = 5'd0;
    reg count_full = 1'b0, invalid_full = 1'b0;       // sh_count == 63, sh_invalid == 15
    // The wait after a slip: a down-counter one bit wider than SLIP_WAIT that stops when its top bit sets (it passes
    // below zero), so "still waiting" is a register bit, not a comparator.
    localparam WAIT_BITS = $clog2(SLIP_WAIT + 1) + 1;
    reg [WAIT_BITS-1:0] slip_wait = {WAIT_BITS{1'b1}};
    wire waiting = !slip_wait[WAIT_BITS-1];
    always @(posedge rx_clk) begin
        rx_slip <= 1'b0;
        if (waiting) slip_wait <= slip_wait - 1'b1;
        if (rx_reset) begin
            block_lock <= 1'b0; sh_count <= 7'd0; sh_invalid <= 5'd0; count_full <= 1'b0; invalid_full <= 1'b0;
        end else if (sh_seen && !waiting) begin
            if (!block_lock) begin
                if (sh_valid) begin
                    if (count_full) begin
                        block_lock <= 1'b1; sh_count <= 7'd0; count_full <= 1'b0; sh_invalid <= 5'd0; invalid_full <= 1'b0;
                    end else begin sh_count <= sh_count + 7'd1; count_full <= sh_count == 7'd62; end
                end else begin
                    sh_count <= 7'd0; count_full <= 1'b0;
                    rx_slip <= 1'b1; slip_wait <= SLIP_WAIT - 1;
                end
            end else begin
                if (!sh_valid && invalid_full) begin
                    block_lock <= 1'b0; sh_count <= 7'd0; count_full <= 1'b0; sh_invalid <= 5'd0; invalid_full <= 1'b0;
                    rx_slip <= 1'b1; slip_wait <= SLIP_WAIT - 1;
                end else if (count_full) begin
                    sh_count <= 7'd0; count_full <= 1'b0; sh_invalid <= 5'd0; invalid_full <= 1'b0;
                end else begin
                    sh_count <= sh_count + 7'd1; count_full <= sh_count == 7'd62;
                    if (!sh_valid) begin sh_invalid <= sh_invalid + 5'd1; invalid_full <= sh_invalid == 5'd14; end
                end
            end
        end
    end

    reg [$clog2(BER_WINDOW + 1)-1:0] ber_blocks = 0;
    reg [4:0] ber_invalid = 5'd0;
    always @(posedge rx_clk) begin
        if (rx_reset || !block_lock) begin
            ber_blocks <= 0; ber_invalid <= 5'd0; high_ber <= 1'b0;
        end else if (sh_seen) begin
            if (!sh_valid && ber_invalid != 5'd16) ber_invalid <= ber_invalid + 5'd1;
            if (!sh_valid && ber_invalid == 5'd15) high_ber <= 1'b1;
            if (ber_blocks == BER_WINDOW - 1) begin
                ber_blocks <= 0; ber_invalid <= 5'd0;
                high_ber <= !sh_valid && ber_invalid == 5'd15;
            end else ber_blocks <= ber_blocks + 1'b1;
        end
    end

    // ---- Restart the receiver when block lock stays lost ----------------------------------------------------------------
    // The request is held 16 cycles, so the transceiver's slower control clock sees it (gtx_10g takes its rising edge).
    // This clock stops while the receiver restarts: the request may stay high until it runs again.
    localparam RESTART_BITS = RESTART_BLOCKS > 1 ? $clog2(RESTART_BLOCKS + 1) : 1;
    reg [RESTART_BITS-1:0] unlocked_blocks = 0;
    reg [3:0] restart_hold = 4'd0;
    always @(posedge rx_clk) begin
        if (restart_hold != 4'd0) restart_hold <= restart_hold - 4'd1;
        else rx_restart <= 1'b0;
        if (rx_reset || block_lock || RESTART_BLOCKS == 0) unlocked_blocks <= 0;
        else if (rx_data_valid_q && !rx_restart) begin
            if (unlocked_blocks == RESTART_BLOCKS - 1) begin unlocked_blocks <= 0; rx_restart <= 1'b1; restart_hold <= 4'd15; end
            else unlocked_blocks <= unlocked_blocks + 1'b1;
        end
    end
endmodule
