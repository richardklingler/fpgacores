// HDMI or DVI encoding for one pixel clock: the three 10-bit lane words (blue, green, red; bit 0 is sent first) that
// the family cores hdmi_out (7-series), hdmi_out_gowin, hdmi_out_ecp5 and hdmi_out_gatemate serialise.
//
// HDMI = 0: DVI, three TMDS encoders (tmds_encoder) with hsync/vsync on blue's control bits: exactly the words the
//   hdmi_out cores sent before this core existed. audio_ready stays low and the audio inputs are unused.
// HDMI = 1: HDMI 1.4 with audio:
//   - the video preamble and video guard band before every active line (the stream runs 12 clocks behind the inputs
//     so they can come before `de` rises);
//   - a data island in each line's blanking, also in the vertical blanking: preamble, guard band, one or two
//     32-character packets in TERC4 with BCH error correction, guard band. It starts 4 characters after the blanking
//     starts and needs 66 characters of blanking for one packet, 98 for two (every CEA timing has more);
//   - packets: Audio Clock Regeneration (N = 6144, CTS = PIXEL_HZ / 1000, once a millisecond), audio samples (two
//     channels, 16 bits, 48 kHz, IEC 60958 channel status saying 48 kHz and 16 bits), the AVI InfoFrame (RGB, full
//     range, VIC, picture aspect) and the Audio InfoFrame (two channels), the InfoFrames at every vsync edge.
// Audio: audio_ready pulses at 48 kHz on average (from PIXEL_HZ); the core takes audio_l/audio_r (signed) in that clock,
//   so a design holds the next pair on its inputs and steps when it sees the pulse. Up to 8 pairs wait for a packet.
// Latency: 3 clocks with HDMI = 0 (the encoders), 16 with HDMI = 1 (12 + 3 + one output register).

module hdmi_encoder #(
    parameter HDMI = 1,
    parameter integer PIXEL_HZ = 74250000,
    parameter [6:0] VIC = 7'd4,            // CEA-861 video code: 1 = 640x480p60, 4 = 1280x720p60, 16 = 1920x1080p60
    parameter [1:0] ASPECT = 2'b10         // picture aspect: 01 = 4:3, 10 = 16:9
) (
    input  wire        clk,
    input  wire [7:0]  red,
    input  wire [7:0]  green,
    input  wire [7:0]  blue,
    input  wire        de,
    input  wire        hsync,
    input  wire        vsync,
    input  wire [15:0] audio_l,
    input  wire [15:0] audio_r,
    output wire        audio_ready,
    output wire [9:0]  word_blue,
    output wire [9:0]  word_green,
    output wire [9:0]  word_red
);
generate if (HDMI == 0) begin : dvi
    assign audio_ready = 1'b0;
    tmds_encoder u_blue  (.clk(clk), .de(de), .d(blue),  .c0(hsync), .c1(vsync), .q(word_blue));
    tmds_encoder u_green (.clk(clk), .de(de), .d(green), .c0(1'b0),  .c1(1'b0),  .q(word_green));
    tmds_encoder u_red   (.clk(clk), .de(de), .d(red),   .c0(1'b0),  .c1(1'b0),  .q(word_red));
end else begin : hdmi
    localparam integer DELAY = 12;
    localparam integer CTS_HZ = PIXEL_HZ / 1000;       // N / (128 * 48 kHz) = 1 / 1000 with N = 6144
    localparam [19:0]  CTS = CTS_HZ;
    localparam [19:0]  N_VALUE = 20'd6144;

    // ---- the delayed stream and what `de` does next ----------------------------------------------------------
    reg [27*DELAY-1:0] pipe = 0;                       // the inputs, DELAY clocks deep (27 bits each)
    reg [DELAY:0] de_seen = 0;
    always @(posedge clk) begin
        pipe <= {pipe[27*(DELAY-1)-1:0], red, green, blue, hsync, vsync, de};
        de_seen <= {de_seen[DELAY-1:0], de};
    end
    wire [26:0] s = pipe[27*DELAY-1 -: 27];
    wire [7:0] s_red = s[26:19], s_green = s[18:11], s_blue = s[10:3];
    wire s_hsync = s[2], s_vsync = s[1], s_de = s[0];
    // de_seen[j] is the input delayed j + 1 clocks: de_seen[DELAY-1] is s_de, de_seen[DELAY-1-j] the stream's de j clocks later.
    wire video_guard    = !s_de && (de_seen[DELAY-2] || de_seen[DELAY-3]);
    wire video_preamble = !s_de && !de_seen[DELAY-2] && !de_seen[DELAY-3] && (|de_seen[DELAY-4:DELAY-11]);

    // ---- the line: blanking length and line length, measured on the stream ---------------------------------------
    reg s_de_was = 1'b0;
    reg [12:0] pos = 0, line_len = 0, blank_len = 0, blank_count = 0;
    reg [1:0] falls = 0;
    always @(posedge clk) begin
        s_de_was <= s_de;
        if (s_de_was && !s_de) begin                      // blanking starts
            if (falls != 2'd3) falls <= falls + 2'd1;
            line_len <= pos + 13'd1;
            pos <= 0;
        end else if (falls == 2'd3 && pos == line_len - 13'd1) pos <= 0;   // vertical blanking: the same rhythm
        else pos <= pos + 13'd1;
        if (s_de) begin if (blank_count != 0) blank_len <= blank_count; blank_count <= 0; end
        else blank_count <= blank_count + 13'd1;
    end
    // Room for packets: 4 control + 8 preamble + 2 guard + 32 n + 2 guard + 12 control (with the video preamble) + 2.
    wire [12:0] room = (blank_len > 13'd34) ? blank_len - 13'd34 : 13'd0;
    wire [1:0]  slots = (falls != 2'd3) ? 2'd0 : (room >= 13'd64) ? 2'd2 : (room >= 13'd32) ? 2'd1 : 2'd0;

    // ---- audio at 48 kHz ---------------------------------------------------------------------------------------
    reg [31:0] sample_acc = 0;
    reg ready = 1'b0;
    assign audio_ready = ready;
    always @(posedge clk) begin
        ready <= 1'b0;
        if (slots == 2'd0) sample_acc <= 0;             // no requests before islands can carry them (power-up)
        else if (sample_acc + 32'd48000 >= PIXEL_HZ) begin sample_acc <= sample_acc + 32'd48000 - PIXEL_HZ; ready <= 1'b1; end
        else sample_acc <= sample_acc + 32'd48000;
    end
    reg [31:0] fifo [0:7];
    reg [3:0] wp = 0, rp = 0;
    wire [3:0] fill = wp - rp;

    // ---- what's due ----------------------------------------------------------------------------------------------
    reg [19:0] acr_count = 0;
    reg acr_due = 1'b0, avi_due = 1'b0, aif_due = 1'b0, s_vsync_was = 1'b0;

    // ---- the island --------------------------------------------------------------------------------------------
    localparam [12:0] ISLAND_AT = 13'd4;                 // preamble at 4..11, guard 12..13, packets from 14
    reg in_island = 1'b0, island_first = 1'b0;
    reg [1:0] n_packets = 0, slot = 0;
    reg [4:0] k = 0;                                     // character within the packet
    reg [2:0] kind0 = 0, kind1 = 0;                      // 1 ACR, 2 audio, 3 AVI, 4 audio InfoFrame
    reg [23:0] header = 0;
    reg [55:0] sub0 = 0, sub1 = 0, sub2 = 0, sub3 = 0;
    reg [7:0] ecc_h = 0, ecc_0 = 0, ecc_1 = 0, ecc_2 = 0, ecc_3 = 0;
    reg [7:0] frame = 0;                                 // IEC 60958 frame, 0 … 191

    function [7:0] next_ecc(input [7:0] ecc, input b);
        next_ecc = (ecc >> 1) ^ ((ecc[0] ^ b) ? 8'b10000011 : 8'd0);
    endfunction
    function [7:0] sum8(input [23:0] h, input [55:0] a, input [55:0] b);   // checksum over header, PB1…PB13
        integer j;
        reg [7:0] t;
        begin
            t = h[7:0] + h[15:8] + h[23:16];
            for (j = 1; j < 7; j = j + 1) t = t + a[8*j +: 8];
            for (j = 0; j < 7; j = j + 1) t = t + b[8*j +: 8];
            sum8 = t;
        end
    endfunction
    // Channel status bit `f` of the 192-bit block: 48 kHz (bit 25), 16-bit words (bit 33).
    function cs_bit(input [7:0] f);
        cs_bit = (f == 8'd25) || (f == 8'd33);
    endfunction
    function [55:0] sample_sub(input [31:0] lr, input [7:0] f);
        reg [23:0] l, r;
        reg c, pl, pr;
        begin
            l = {lr[31:16], 8'h00}; r = {lr[15:0], 8'h00}; c = cs_bit(f);
            pl = ^{l, c}; pr = ^{r, c};                  // even parity over the sample and V U C (V = U = 0)
            sample_sub = {pr, c, 1'b0, 1'b0, pl, c, 1'b0, 1'b0, r, l};
        end
    endfunction

    // The packet for a slot, built when the slot starts.
    reg [55:0] avi_a, avi_b, aif_a;
    reg [55:0] p0, p1, p2, p3;
    reg [23:0] h;
    reg [2:0] take;
    reg [3:0] present, bflag;
    integer m;
    task load(input [2:0] what);
        begin
            p0 = 0; p1 = 0; p2 = 0; p3 = 0;
            case (what)
                3'd1: begin
                    h = 24'h000001;
                    p0 = {N_VALUE[7:0], N_VALUE[15:8], 4'h0, N_VALUE[19:16], CTS[7:0], CTS[15:8], 4'h0, CTS[19:16], 8'h00};
                    p1 = p0; p2 = p0; p3 = p0;
                end
                3'd2: begin
                    take = (fill > 4) ? 3'd4 : fill[2:0];
                    present = 0; bflag = 0;
                    for (m = 0; m < 4; m = m + 1) if (m < take) begin
                        present[m] = 1'b1;
                        if (frame + m == 8'd0 || frame + m == 8'd192) bflag[m] = 1'b1;
                    end
                    if (take > 0) p0 = sample_sub(fifo[rp[2:0]], frame);
                    if (take > 1) p1 = sample_sub(fifo[rp[2:0] + 3'd1], (frame + 8'd1 >= 8'd192) ? frame + 8'd1 - 8'd192 : frame + 8'd1);
                    if (take > 2) p2 = sample_sub(fifo[rp[2:0] + 3'd2], (frame + 8'd2 >= 8'd192) ? frame + 8'd2 - 8'd192 : frame + 8'd2);
                    if (take > 3) p3 = sample_sub(fifo[rp[2:0] + 3'd3], (frame + 8'd3 >= 8'd192) ? frame + 8'd3 - 8'd192 : frame + 8'd3);
                    h = {bflag, 4'h0, 4'h0, present, 8'h02};
                end
                3'd3: begin
                    h = 24'h0D0282;
                    avi_a = {8'h00, 8'h00, {1'b0, VIC}, 8'h08, {2'b00, ASPECT, 4'b1000}, 8'h00, 8'h00};   // PB6 … PB0
                    avi_b = 56'd0;
                    avi_a[7:0] = 8'h00 - sum8(h, avi_a, avi_b);
                    p0 = avi_a; p1 = avi_b;
                end
                default: begin
                    h = 24'h0A0184;
                    aif_a = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01, 8'h00};                    // PB1: 2 channels
                    aif_a[7:0] = 8'h00 - sum8(h, aif_a, 56'd0);
                    p0 = aif_a;
                end
            endcase
        end
    endtask

    // The island's characters, for the stream's current position.
    reg [3:0] nib0, nib1, nib2;
    reg [1:0] mode;                                     // 0 TMDS, 1 video guard, 2 island guard, 3 island data
    reg ctl0, ctl1, ctl2, ctl3;
    wire island_start = (pos == ISLAND_AT) && slots != 0 && (acr_due || avi_due || aif_due || fill != 0);
    reg [12:0] island_end = 0;                          // the first position after the trailing guard band
    reg in_pre = 1'b0, in_lead = 1'b0, in_trail = 1'b0;
    reg [2:0] next0, next1;

    always @(posedge clk) begin
        if (ready && fill != 4'd8) begin fifo[wp[2:0]] <= {audio_l, audio_r}; wp <= wp + 4'd1; end
        if (acr_count + 20'd1 >= CTS_HZ) begin acr_count <= 0; acr_due <= 1'b1; end else acr_count <= acr_count + 20'd1;
        s_vsync_was <= s_vsync;
        if (s_vsync != s_vsync_was) begin avi_due <= 1'b1; aif_due <= 1'b1; end

        if (island_start) begin
            // Up to two packets, most urgent first.
            next0 = acr_due ? 3'd1 : avi_due ? 3'd3 : aif_due ? 3'd4 : 3'd2;
            next1 = 3'd0;
            if (slots == 2'd2) begin
                if (next0 != 3'd2 && fill != 0) next1 = 3'd2;
                else if (next0 == 3'd2 && fill > 4'd4) next1 = 3'd2;      // a backlog: two audio packets
                else if (next0 == 3'd1 && avi_due) next1 = 3'd3;
                else if (next0 != 3'd4 && aif_due && next0 != 3'd2) next1 = 3'd4;
            end
            kind0 <= next0; kind1 <= next1;
            n_packets <= (next1 != 3'd0) ? 2'd2 : 2'd1;
            island_end <= ISLAND_AT + 13'd8 + 13'd2 + ((next1 != 3'd0) ? 13'd64 : 13'd32) + 13'd2;
            in_pre <= 1'b1;
        end
        // Preamble 4..11, guard 12..13, packets, guard.
        if (pos == ISLAND_AT + 13'd8 && in_pre) begin in_pre <= 1'b0; in_lead <= 1'b1; end
        if (pos == ISLAND_AT + 13'd10 && in_lead) begin
            in_lead <= 1'b0; in_island <= 1'b1; island_first <= 1'b1; slot <= 0; k <= 0;
            load(kind0);
            header <= h; sub0 <= p0; sub1 <= p1; sub2 <= p2; sub3 <= p3;
            ecc_h <= 0; ecc_0 <= 0; ecc_1 <= 0; ecc_2 <= 0; ecc_3 <= 0;
            case (kind0) 3'd1: acr_due <= 1'b0; 3'd3: avi_due <= 1'b0; 3'd4: aif_due <= 1'b0;
                default: begin rp <= rp + {1'b0, take}; frame <= (frame + take >= 8'd192) ? frame + take - 8'd192 : frame + take; end endcase
        end else if (in_island) begin
            island_first <= 1'b0;
            if (k < 5'd24) ecc_h <= next_ecc(ecc_h, header[k]);
            if (k < 5'd28) begin
                ecc_0 <= next_ecc(next_ecc(ecc_0, sub0[2*k]), sub0[2*k+1]);
                ecc_1 <= next_ecc(next_ecc(ecc_1, sub1[2*k]), sub1[2*k+1]);
                ecc_2 <= next_ecc(next_ecc(ecc_2, sub2[2*k]), sub2[2*k+1]);
                ecc_3 <= next_ecc(next_ecc(ecc_3, sub3[2*k]), sub3[2*k+1]);
            end
            k <= k + 5'd1;
            if (k == 5'd31) begin
                if (slot + 2'd1 < n_packets) begin
                    slot <= slot + 2'd1; k <= 0;
                    load(kind1);
                    header <= h; sub0 <= p0; sub1 <= p1; sub2 <= p2; sub3 <= p3;
                    ecc_h <= 0; ecc_0 <= 0; ecc_1 <= 0; ecc_2 <= 0; ecc_3 <= 0;
                    case (kind1) 3'd1: acr_due <= 1'b0; 3'd3: avi_due <= 1'b0; 3'd4: aif_due <= 1'b0;
                        default: begin rp <= rp + {1'b0, take}; frame <= (frame + take >= 8'd192) ? frame + take - 8'd192 : frame + take; end endcase
                end else begin
                    in_island <= 1'b0; in_trail <= 1'b1;
                end
            end
        end
        if (in_trail && pos == island_end) in_trail <= 1'b0;
    end

    // The bits of the current character (registered: they belong to the stream's position one clock later).
    function bit_of(input [55:0] p, input [7:0] e, input [5:0] b);    // bit b (0 … 63) of a subpacket with its ECC
        bit_of = (b < 6'd56) ? p[b] : e[b - 6'd56];
    endfunction
    always @(*) begin
        mode = 2'd0; nib0 = 0; nib1 = 0; nib2 = 0;
        ctl0 = 1'b0; ctl1 = 1'b0; ctl2 = 1'b0; ctl3 = 1'b0;
        if (s_de) mode = 2'd0;
        else if (video_guard) mode = 2'd1;
        else if (in_lead || in_trail) begin mode = 2'd2; nib0 = {2'b11, s_vsync, s_hsync}; end
        else if (in_island) begin
            mode = 2'd3;
            nib0 = {!island_first, (k < 5'd24) ? header[k] : ecc_h[k - 5'd24], s_vsync, s_hsync};
            nib1 = {bit_of(sub3, ecc_3, {k, 1'b0}), bit_of(sub2, ecc_2, {k, 1'b0}), bit_of(sub1, ecc_1, {k, 1'b0}), bit_of(sub0, ecc_0, {k, 1'b0})};
            nib2 = {bit_of(sub3, ecc_3, {k, 1'b1}), bit_of(sub2, ecc_2, {k, 1'b1}), bit_of(sub1, ecc_1, {k, 1'b1}), bit_of(sub0, ecc_0, {k, 1'b1})};
        end else if (in_pre) begin ctl0 = 1'b1; ctl2 = 1'b1; end
        else if (video_preamble) ctl0 = 1'b1;
    end

    // Words: the TMDS encoders take the stream (3 clocks), the other modes wait as long, one register stage at the end.
    wire [9:0] q_blue, q_green, q_red;
    tmds_encoder u_blue  (.clk(clk), .de(s_de), .d(s_blue),  .c0(s_hsync), .c1(s_vsync), .q(q_blue));
    tmds_encoder u_green (.clk(clk), .de(s_de), .d(s_green), .c0(ctl0),    .c1(ctl1),    .q(q_green));
    tmds_encoder u_red   (.clk(clk), .de(s_de), .d(s_red),   .c0(ctl2),    .c1(ctl3),    .q(q_red));
    reg [13:0] side0 = 0, side1 = 0, side2 = 0;          // {mode, nib0, nib1, nib2}, three clocks behind
    always @(posedge clk) begin
        side0 <= {mode, nib0, nib1, nib2};
        side1 <= side0;
        side2 <= side1;
    end
    function [9:0] terc4(input [3:0] d);
        case (d)
            4'h0: terc4 = 10'b1010011100; 4'h1: terc4 = 10'b1001100011; 4'h2: terc4 = 10'b1011100100; 4'h3: terc4 = 10'b1011100010;
            4'h4: terc4 = 10'b0101110001; 4'h5: terc4 = 10'b0100011110; 4'h6: terc4 = 10'b0110001110; 4'h7: terc4 = 10'b0100111100;
            4'h8: terc4 = 10'b1011001100; 4'h9: terc4 = 10'b0100111001; 4'hA: terc4 = 10'b0110011100; 4'hB: terc4 = 10'b1011000110;
            4'hC: terc4 = 10'b1010001110; 4'hD: terc4 = 10'b1001110001; 4'hE: terc4 = 10'b0101100011; default: terc4 = 10'b1011000011;
        endcase
    endfunction
    wire [1:0] m3 = side2[13:12];
    reg [9:0] out_blue = 0, out_green = 0, out_red = 0;
    always @(posedge clk) begin
        case (m3)
            2'd1: begin out_blue <= 10'b1011001100; out_green <= 10'b0100110011; out_red <= 10'b1011001100; end
            2'd2: begin out_blue <= terc4(side2[11:8]); out_green <= 10'b0100110011; out_red <= 10'b0100110011; end
            2'd3: begin out_blue <= terc4(side2[11:8]); out_green <= terc4(side2[7:4]); out_red <= terc4(side2[3:0]); end
            default: begin out_blue <= q_blue; out_green <= q_green; out_red <= q_red; end
        endcase
    end
    assign word_blue = out_blue;
    assign word_green = out_green;
    assign word_red = out_red;
end endgenerate
endmodule
