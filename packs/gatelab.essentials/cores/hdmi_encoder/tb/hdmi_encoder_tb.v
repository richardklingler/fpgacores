// hdmi_encoder's testbench: a decoder written like a sink's checks every character of HDMI = 1 and compares HDMI = 0
// with three plain tmds_encoders. The timing is the testbench's own: 12 MHz pixels, lines of 1000 (640 active, 360
// blanking), 60 lines (40 active), so every line carries four samples and audio packets are full (all 16 TERC4 values
// on the data channels). Samples are pseudo-random and recorded as the core takes them; pixels likewise.
`timescale 1ns / 1ps
module hdmi_encoder_tb;
    localparam integer PIXEL_HZ = 12000000, H_ACTIVE = 640, H_TOTAL = 1000, V_ACTIVE = 40, V_TOTAL = 60;
    localparam integer H_SYNC_AT = 680, H_SYNC_LEN = 40, V_SYNC_AT = 45, V_SYNC_LEN = 3;
    localparam integer FRAMES = 4;
    reg clk = 0;
    always #41.667 clk = ~clk;

    // Timing and pixels.
    integer x = 0, y = 0;
    reg [7:0] red = 0, green = 0, blue = 0;
    reg de = 0, hsync = 0, vsync = 0;
    reg [15:0] lfsr = 16'hACE1;
    always @(posedge clk) begin
        x <= (x == H_TOTAL - 1) ? 0 : x + 1;
        if (x == H_TOTAL - 1) y <= (y == V_TOTAL - 1) ? 0 : y + 1;
        de <= (x < H_ACTIVE) && (y < V_ACTIVE);
        hsync <= (x >= H_SYNC_AT) && (x < H_SYNC_AT + H_SYNC_LEN);
        vsync <= (y >= V_SYNC_AT) && (y < V_SYNC_AT + V_SYNC_LEN);
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        red <= lfsr[7:0]; green <= lfsr[15:8] ^ x[7:0]; blue <= x[7:0] + y[7:0];
    end

    // Audio: a new pseudo-random pair after each request.
    reg [15:0] audio_l = 16'h1234, audio_r = 16'hFEDC;
    reg [31:0] alfsr = 32'h1F2E3D4C;
    wire audio_ready;

    wire [9:0] wb, wg, wr, db, dg, dr, rb, rg, rr;
    wire audio_ready_dvi;
    hdmi_encoder #(.HDMI(1), .PIXEL_HZ(PIXEL_HZ), .VIC(7'd1), .ASPECT(2'b01)) dut (
        .clk(clk), .red(red), .green(green), .blue(blue), .de(de), .hsync(hsync), .vsync(vsync),
        .audio_l(audio_l), .audio_r(audio_r), .audio_ready(audio_ready), .word_blue(wb), .word_green(wg), .word_red(wr));
    hdmi_encoder #(.HDMI(0)) dvi (
        .clk(clk), .red(red), .green(green), .blue(blue), .de(de), .hsync(hsync), .vsync(vsync),
        .audio_l(audio_l), .audio_r(audio_r), .audio_ready(audio_ready_dvi), .word_blue(db), .word_green(dg), .word_red(dr));
    tmds_encoder r_blue  (.clk(clk), .de(de), .d(blue),  .c0(hsync), .c1(vsync), .q(rb));
    tmds_encoder r_green (.clk(clk), .de(de), .d(green), .c0(1'b0),  .c1(1'b0),  .q(rg));
    tmds_encoder r_red   (.clk(clk), .de(de), .d(red),   .c0(1'b0),  .c1(1'b0),  .q(rr));

    // What went in, in order.
    reg [31:0] sent_audio [0:8191];
    reg [23:0] sent_pixel [0:65535];
    integer audio_in = 0, pixel_in = 0;
    always @(posedge clk) begin
        if (audio_ready) begin
            sent_audio[audio_in] = {audio_l, audio_r}; audio_in = audio_in + 1;
            alfsr = {alfsr[30:0], alfsr[31] ^ alfsr[21] ^ alfsr[1] ^ alfsr[0]};
            audio_l <= alfsr[15:0]; audio_r <= alfsr[31:16] ^ 16'h5A5A;
        end
        if (de) begin sent_pixel[pixel_in % 65536] = {red, green, blue}; pixel_in = pixel_in + 1; end
    end

    integer errors = 0;
    task fail(input [8*72-1:0] what); begin if (errors < 12) $display("FAIL: %0s", what); errors = errors + 1; end endtask

    // ---- decoding -------------------------------------------------------------------------------------------------
    function [9:0] terc4(input [3:0] d);
        case (d)
            4'h0: terc4 = 10'b1010011100; 4'h1: terc4 = 10'b1001100011; 4'h2: terc4 = 10'b1011100100; 4'h3: terc4 = 10'b1011100010;
            4'h4: terc4 = 10'b0101110001; 4'h5: terc4 = 10'b0100011110; 4'h6: terc4 = 10'b0110001110; 4'h7: terc4 = 10'b0100111100;
            4'h8: terc4 = 10'b1011001100; 4'h9: terc4 = 10'b0100111001; 4'hA: terc4 = 10'b0110011100; 4'hB: terc4 = 10'b1011000110;
            4'hC: terc4 = 10'b1010001110; 4'hD: terc4 = 10'b1001110001; 4'hE: terc4 = 10'b0101100011; default: terc4 = 10'b1011000011;
        endcase
    endfunction
    function [4:0] terc4_value(input [9:0] w);       // {valid, value}
        integer v;
        begin terc4_value = 5'd0; for (v = 0; v < 16; v = v + 1) if (terc4(v) == w) terc4_value = {1'b1, v[3:0]}; end
    endfunction
    function [2:0] ctrl_value(input [9:0] w);          // {valid, c1, c0}
        case (w)
            10'b1101010100: ctrl_value = 3'b100; 10'b0010101011: ctrl_value = 3'b101;
            10'b0101010100: ctrl_value = 3'b110; 10'b1010101011: ctrl_value = 3'b111;
            default: ctrl_value = 3'b000;
        endcase
    endfunction
    function [7:0] tmds_value(input [9:0] w);
        reg [7:0] d;
        integer i;
        begin
            d = w[9] ? ~w[7:0] : w[7:0];
            tmds_value[0] = d[0];
            for (i = 1; i < 8; i = i + 1) tmds_value[i] = w[8] ? d[i] ^ d[i-1] : ~(d[i] ^ d[i-1]);
        end
    endfunction
    // The ECC computed independently: BCH with G(x) = 1 + x^6 + x^7 + x^8 by long division, the first bit the
    // highest power of the reflected message (the reflected CRC the core runs bit by bit must equal it).
    function [7:0] bch(input [63:0] bits, input integer n);
        reg [71:0] r;
        integer p, j;
        begin
            r = 0;
            for (j = 0; j < n; j = j + 1) r[n - 1 - j + 8] = bits[j];
            for (p = n + 7; p >= 8; p = p - 1) if (r[p]) begin r[p] = 0; r[p - 2] = r[p - 2] ^ 1; r[p - 1] = r[p - 1] ^ 1; r[p - 8] = r[p - 8] ^ 1; end
            for (j = 0; j < 8; j = j + 1) bch[j] = r[7 - j];
        end
    endfunction

    // The decoder's state.
    localparam S_CTRL = 0, S_VPRE = 1, S_VGUARD = 2, S_VIDEO = 3, S_IPRE = 4, S_ILEAD = 5, S_ISLAND = 6, S_ITRAIL = 7;
    integer state = S_CTRL, run = 0, k = 0, packets = 0, pixel_out = 0, audio_out = 0, lines = 0, frame = 0;
    integer acr = 0, avi = 0, aif = 0, audio_packets = 0, full_packets = 0, last_acr_at = -1, now = 0, hs_rises = 0;
    reg [31:0] hdr;
    reg [63:0] sb0, sb1, sb2, sb3;
    reg [15:0] seen1 = 0, seen2 = 0;
    reg hs_was = 0, first = 0;
    reg [7:0] cs_frame = 0;
    reg started = 0;
    reg [9:0] b, g, r;
    reg [4:0] tb_, tg, tr;
    reg [2:0] cb, cg, cr;

    task check_packet;
        reg [7:0] t;
        integer s, sum, j, present;
        reg [63:0] sp;
        reg [15:0] l, rr2;
        begin
            packets = packets + 1;
            if (bch({32'd0, hdr[31:0]}, 24) != hdr[31:24]) fail("header ECC");
            if (bch(sb0, 56) != sb0[63:56] || bch(sb1, 56) != sb1[63:56] || bch(sb2, 56) != sb2[63:56] || bch(sb3, 56) != sb3[63:56]) fail("subpacket ECC");
            t = hdr[7:0];
            case (t)
                8'h01: begin
                    acr = acr + 1;
                    if ({sb0[11:8], sb0[23:16], sb0[31:24]} != PIXEL_HZ / 1000) fail("ACR CTS");
                    if ({sb0[35:32], sb0[47:40], sb0[55:48]} != 20'd6144) fail("ACR N");
                    if (sb1[55:0] != sb0[55:0] || sb3[55:0] != sb0[55:0]) fail("ACR subpackets differ");
                    if (last_acr_at >= 0 && (now - last_acr_at > PIXEL_HZ / 1000 + 2 * H_TOTAL)) fail("ACR more than a millisecond apart");
                    last_acr_at = now;
                end
                8'h02: begin
                    audio_packets = audio_packets + 1;
                    present = hdr[11:8];
                    if (present == 4'hF) full_packets = full_packets + 1;
                    for (s = 0; s < 4; s = s + 1) if (present[s]) begin
                        sp = (s == 0) ? sb0 : (s == 1) ? sb1 : (s == 2) ? sb2 : sb3;
                        l = sp[23:8]; rr2 = sp[47:32];
                        if (sp[7:0] != 0 || sp[31:24] != 0) fail("audio low bytes");
                        if ({l, rr2} != sent_audio[audio_out]) begin if (errors < 3) $display("  got %h want %h (sample %0d), next %h prev %h", {l, rr2}, sent_audio[audio_out], audio_out, sent_audio[audio_out+1], (audio_out > 0) ? sent_audio[audio_out-1] : 32'd0); fail("audio sample"); end
                        audio_out = audio_out + 1;
                        if (sp[51] != ^{sp[23:0], sp[50]}) fail("left parity");
                        if (sp[55] != ^{sp[47:24], sp[54]}) fail("right parity");
                        if (sp[50] != ((cs_frame == 25) || (cs_frame == 33)) || sp[54] != sp[50]) fail("channel status");
                        if (hdr[20 + s] != (cs_frame == 0)) fail("block start flag");
                        cs_frame = (cs_frame == 191) ? 0 : cs_frame + 1;
                    end
                end
                8'h82: begin
                    avi = avi + 1;
                    sum = hdr[7:0] + hdr[15:8] + hdr[23:16];
                    for (j = 0; j < 7; j = j + 1) sum = sum + sb0[8*j +: 8] + sb1[8*j +: 8];
                    if (sum % 256 != 0) fail("AVI checksum");
                    if (hdr[23:8] != 16'h0D02 || sb0[39:32] != 8'd1 || sb0[23:16] != 8'h18 || sb0[31:24] != 8'h08) fail("AVI fields");
                end
                8'h84: begin
                    aif = aif + 1;
                    sum = hdr[7:0] + hdr[15:8] + hdr[23:16];
                    for (j = 0; j < 7; j = j + 1) sum = sum + sb0[8*j +: 8] + sb1[8*j +: 8];
                    if (sum % 256 != 0) fail("audio InfoFrame checksum");
                    if (hdr[23:8] != 16'h0A01 || sb0[15:8] != 8'h01) fail("audio InfoFrame fields");
                end
                default: fail("unknown packet type");
            endcase
        end
    endtask

    always @(posedge clk) begin
        now = now + 1;
        if (db !== rb || dg !== rg || dr !== rr) begin if (now > 4) fail("HDMI = 0 differs from three tmds_encoders"); end
        b = wb; g = wg; r = wr;
        cb = ctrl_value(b); cg = ctrl_value(g); cr = ctrl_value(r);
        tb_ = terc4_value(b); tg = terc4_value(g); tr = terc4_value(r);
        if (!started) begin if (cb[2] && cg[2] && cr[2]) started = 1; end
        else case (state)
            S_CTRL, S_VPRE, S_IPRE: begin
                if (cb[2] && cg[2] && cr[2]) begin
                    if (cg[1:0] == 2'b01 && cr[1:0] == 2'b00) begin run = (state == S_VPRE) ? run + 1 : 1; state = S_VPRE; end
                    else if (cg[1:0] == 2'b01 && cr[1:0] == 2'b01) begin run = (state == S_IPRE) ? run + 1 : 1; state = S_IPRE; end
                    else if (cg[1:0] == 2'b00 && cr[1:0] == 2'b00) begin
                        if (state != S_CTRL) fail("preamble cut short");
                        state = S_CTRL;
                    end else fail("control bits on green or red outside a preamble");
                    if (cb[0] && !hs_was) hs_rises = hs_rises + 1;
                    hs_was = cb[0];
                end else if (state == S_VPRE && run == 8 && b == 10'b1011001100 && g == 10'b0100110011 && r == 10'b1011001100) begin
                    state = S_VGUARD; run = 1;
                end else if (state == S_IPRE && run == 8 && g == 10'b0100110011 && r == 10'b0100110011 && tb_[4]) begin
                    if (tb_[3:2] != 2'b11) fail("leading guard band bits");
                    state = S_ILEAD; run = 1;
                end else fail("a character outside any period");
            end
            S_VGUARD: begin
                if (b == 10'b1011001100 && g == 10'b0100110011 && r == 10'b1011001100) run = run + 1;
                else begin
                    if (run != 2) fail("video guard band not two characters");
                    state = S_VIDEO; lines = lines + 1;
                end
            end
            S_ILEAD: begin
                if (g == 10'b0100110011 && r == 10'b0100110011 && tb_[4]) run = run + 1;
                else begin
                    if (run != 2) fail("leading guard band not two characters");
                    state = S_ISLAND; k = 0; first = 1;
                end
            end
            S_ISLAND: ;
            S_ITRAIL: begin
                if (g == 10'b0100110011 && r == 10'b0100110011 && tb_[4]) begin run = run + 1; if (tb_[3:2] != 2'b11) fail("trailing guard band bits"); end
                else begin
                    if (run != 2) fail("trailing guard band not two characters");
                    state = S_CTRL;
                    if (!(cb[2] && cg[2] && cr[2])) fail("no control period after an island");
                end
            end
        endcase
        // Video and island characters (also the first of each, taken over from the transitions above).
        if (state == S_VIDEO) begin
            if (cb[2] && cg[2] && cr[2]) begin
                state = S_CTRL;
                if (cb[0] && !hs_was) hs_rises = hs_rises + 1;
                hs_was = cb[0];
            end else begin
                if ({tmds_value(r), tmds_value(g), tmds_value(b)} != sent_pixel[pixel_out % 65536]) fail("pixel");
                pixel_out = pixel_out + 1;
            end
        end
        if (state == S_ISLAND) begin
            if (!(tb_[4] && tg[4] && tr[4])) begin
                if (g == 10'b0100110011 && r == 10'b0100110011 && tb_[4] && k == 0) begin
                    state = S_ITRAIL; run = 1; if (tb_[3:2] != 2'b11) fail("trailing guard band bits");
                end else fail("not TERC4 inside an island");
            end else begin
                if (tb_[3] != !first) fail("channel 0 bit 3");
                first = 0;
                seen1[tg[3:0]] = 1; seen2[tr[3:0]] = 1;
                if (tb_[0] && !hs_was) hs_rises = hs_rises + 1;
                hs_was = tb_[0];
                hdr[k] = tb_[2];
                sb0[2*k] = tg[0]; sb1[2*k] = tg[1]; sb2[2*k] = tg[2]; sb3[2*k] = tg[3];
                sb0[2*k+1] = tr[0]; sb1[2*k+1] = tr[1]; sb2[2*k+1] = tr[2]; sb3[2*k+1] = tr[3];
                k = k + 1;
                if (k == 32) begin check_packet; k = 0; end
            end
        end
    end

    initial begin
        repeat (FRAMES * H_TOTAL * V_TOTAL) @(posedge clk);
        $display("lines %0d, pixels %0d of %0d, packets %0d (ACR %0d, audio %0d with %0d full, AVI %0d, audio InfoFrame %0d), samples %0d of %0d, hsync %0d",
                 lines, pixel_out, pixel_in, packets, acr, audio_packets, full_packets, avi, aif, audio_out, audio_in, hs_rises);
        if (seen1 != 16'hFFFF || seen2 != 16'hFFFF) begin $display("TERC4 values seen: %b %b", seen1, seen2); fail("not every TERC4 value was used"); end
        if (lines < (FRAMES - 1) * V_ACTIVE) fail("too few video lines");
        if (pixel_in - pixel_out > H_ACTIVE) fail("pixels missing");
        if (audio_in - audio_out > 8) fail("samples missing");
        if (audio_in < (FRAMES * V_TOTAL - 3) * 4 - 8) fail("audio_ready not at 48 kHz");    // requests start after three lines
        if (acr < FRAMES * V_TOTAL * H_TOTAL / (PIXEL_HZ / 1000) - 1) fail("too few ACR packets");
        if (avi < FRAMES - 1 || aif < FRAMES - 1) fail("too few InfoFrames");
        if (full_packets < audio_packets / 2) fail("too few full audio packets");
        if (hs_rises < (FRAMES - 1) * V_TOTAL) fail("hsync lost in the islands");
        if (audio_ready_dvi !== 1'b0) fail("audio_ready with HDMI = 0");
        if (errors == 0) $display("PASS"); else $display("FAILED: %0d", errors);
        $finish;
    end
endmodule
