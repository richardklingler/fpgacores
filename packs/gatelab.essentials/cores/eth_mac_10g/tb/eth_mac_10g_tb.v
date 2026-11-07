// Testbench for eth_mac_10g: the transmitter's XGMII bytes against frames built here (start in lane 0, preamble,
// padding to 60 bytes, the FCS from this testbench's own CRC-32, terminate, at least 12 bytes to the next start), frames
// of 1 to 1500 bytes back to back through the receiver, a corrupted byte, an underrun, and crafted traffic straight into
// the receiver: starts in lane 4 and lane 0 after the shortest gap a receiver must take (5 bytes) in every combination,
// a runt, an error character.
`timescale 1ns / 1ps

module eth_mac_10g_tb;
    reg clk = 1'b0;
    always #3.103 clk = ~clk;
    integer failures = 0;
    task fail(input [8*100-1:0] what);
        begin $display("FAIL: %0s", what); failures = failures + 1; end
    endtask

    reg [5:0] seq = 6'd0;
    always @(posedge clk) seq <= seq == 6'd32 ? 6'd0 : seq + 6'd1;
    wire ready = seq != 6'd32;                        // the PCS takes a block this cycle

    // ---- This testbench's CRC-32, bit by bit ---------------------------------------------------------------------------
    function [31:0] crc_step(input [31:0] c, input [7:0] b);
        integer i;
        reg [31:0] x;
        begin
            x = c;
            for (i = 0; i < 8; i = i + 1) begin
                if (x[0] ^ b[i]) x = {1'b0, x[31:1]} ^ 32'hEDB88320; else x = {1'b0, x[31:1]};
            end
            crc_step = x;
        end
    endfunction

    // ---- The MAC -------------------------------------------------------------------------------------------------------
    reg [63:0] tx_data = 64'd0;
    reg [7:0] tx_keep = 8'hFF;
    reg tx_valid = 1'b0, tx_last = 1'b0;
    wire tx_ready;
    wire [63:0] txd, rx_data;
    wire [7:0] txc, rx_keep;
    wire rx_valid, rx_last, rx_error;
    wire [31:0] rx_frames, rx_bad_frames;
    // The loop: what the MAC sends, a cycle later, into its receiver — or crafted blocks.
    reg [63:0] lp_d = {8{8'h07}};
    reg [7:0] lp_c = 8'hFF;
    reg lp_v = 1'b0;
    reg crafted = 1'b0;
    reg [63:0] cr_d = {8{8'h07}};
    reg [7:0] cr_c = 8'hFF;
    integer corrupt_at = -1;                           // a byte of the transmitted stream to flip
    eth_mac_10g dut (
        .tx_clk(clk), .tx_data(tx_data), .tx_keep(tx_keep), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready),
        .xgmii_tx_ready(ready), .xgmii_txd(txd), .xgmii_txc(txc),
        .rx_clk(clk), .xgmii_rxd(crafted ? cr_d : lp_d), .xgmii_rxc(crafted ? cr_c : lp_c), .xgmii_rx_valid(crafted ? ready : lp_v),
        .rx_data(rx_data), .rx_keep(rx_keep), .rx_valid(rx_valid), .rx_last(rx_last), .rx_error(rx_error),
        .rx_frames(rx_frames), .rx_bad_frames(rx_bad_frames));

    // Every byte the transmitter sends, with its control flag.
    localparam S = 1 << 17;
    reg [7:0] sb [0:S-1];
    reg sc [0:S-1];
    integer sn = 0, k;
    always @(posedge clk) begin
        lp_v <= ready;
        if (ready) begin
            lp_d <= txd; lp_c <= txc;
            for (k = 0; k < 8; k = k + 1) begin
                if (sn == corrupt_at && !txc[k]) lp_d[8 * k +: 8] <= txd[8 * k +: 8] ^ 8'h10;
                sb[sn] = txd[8 * k +: 8]; sc[sn] = txc[k]; sn = sn + 1;
            end
        end
    end

    // ---- Frames sent: payloads as given, and as they should arrive (padded to 60) --------------------------------------
    localparam F = 64;
    localparam B = 1 << 15;
    reg [7:0] pay [0:B-1];
    integer pay_at [0:F-1];
    integer pay_len [0:F-1];
    integer frames = 0, pay_n = 0;
    integer seed = 3;
    task make(input integer len);
        integer i;
        begin
            pay_at[frames] = pay_n; pay_len[frames] = len;
            for (i = 0; i < len; i = i + 1) begin pay[pay_n] = $random(seed); pay_n = pay_n + 1; end
            frames = frames + 1;
        end
    endtask
    // Sends frame f; an underrun (tx_valid low for 8 cycles) before word `gap_at` when it's not -1. A word is taken at the
    // rising edge after a falling edge that saw tx_ready (signals settle between the edges).
    task taken;
        begin @(negedge clk); while (!tx_ready) @(negedge clk); @(posedge clk); end
    endtask
    task send(input integer f, input integer gap_at);
        integer w, words, i, n;
        begin
            words = (pay_len[f] + 7) / 8;
            for (w = 0; w < words; w = w + 1) begin
                if (w == gap_at) begin
                    tx_valid <= 1'b0;
                    repeat (8) @(posedge clk);
                end
                n = pay_len[f] - 8 * w; if (n > 8) n = 8;
                for (i = 0; i < 8; i = i + 1) tx_data[8 * i +: 8] <= i < n ? pay[pay_at[f] + 8 * w + i] : 8'h6B;   // junk the MAC must ignore
                tx_keep <= 8'hFF >> (8 - n);
                tx_last <= w == words - 1;
                tx_valid <= 1'b1;
                taken;
            end
            tx_valid <= 1'b0; tx_last <= 1'b0;
        end
    endtask

    // ---- Frames received ----------------------------------------------------------------------------------------------
    reg [7:0] got [0:B-1];
    integer got_at [0:F-1];
    integer got_len [0:F-1];
    reg got_err [0:F-1];
    integer got_frames = 0, got_n = 0, cur = 0;
    // rx_keep: never empty, always lanes 0 … n-1; whole on every word but the last.
    reg keep_ok = 1'b1;
    always @(posedge clk) if (rx_valid && (rx_keep == 8'd0 || (rx_keep & (rx_keep + 8'd1)) != 8'd0 ||
                                           (!rx_last && rx_keep != 8'hFF))) keep_ok = 1'b0;
    always @(posedge clk) if (rx_valid) begin
        for (k = 0; k < 8; k = k + 1) if (rx_keep[k]) begin got[got_n] = rx_data[8 * k +: 8]; got_n = got_n + 1; cur = cur + 1; end
        if (rx_last) begin
            got_at[got_frames] = got_n - cur; got_len[got_frames] = cur; got_err[got_frames] = rx_error;
            got_frames = got_frames + 1; cur = 0;
        end
    end

    // ---- Checks ---------------------------------------------------------------------------------------------------------
    // Frame f on the wire, from byte p (its start): preamble, padded payload, FCS, terminate; returns the terminate's index.
    function integer wire_frame(input integer p, input integer f);
        integer i, len;
        reg [31:0] c;
        reg [7:0] b;
        begin
            wire_frame = -1;
            len = pay_len[f] < 60 ? 60 : pay_len[f];
            c = 32'hFFFFFFFF;
            if (!(sc[p] && sb[p] == 8'hFB && p % 8 == 0)) wire_frame = -2;
            for (i = 1; i < 7; i = i + 1) if (sc[p + i] || sb[p + i] != 8'h55) wire_frame = -3;
            if (sc[p + 7] || sb[p + 7] != 8'hD5) wire_frame = -3;
            for (i = 0; i < len; i = i + 1) begin
                b = i < pay_len[f] ? pay[pay_at[f] + i] : 8'h00;
                if (sc[p + 8 + i] || sb[p + 8 + i] != b) wire_frame = -4;
                c = crc_step(c, b);
            end
            c = ~c;
            for (i = 0; i < 4; i = i + 1) if (sc[p + 8 + len + i] || sb[p + 8 + len + i] != c[8 * i +: 8]) wire_frame = -5;
            if (!(sc[p + 12 + len] && sb[p + 12 + len] == 8'hFD)) wire_frame = -6;
            if (wire_frame == -1) wire_frame = p + 12 + len;
        end
    endfunction
    task check_wire(input integer from_frame, input integer to_frame);
        integer f, p, t, gap, minimum;
        begin
            p = 0; minimum = 1000;
            for (f = from_frame; f < to_frame; f = f + 1) begin
                while (p < sn && !(sc[p] && sb[p] == 8'hFB)) p = p + 1;
                t = wire_frame(p, f);
                if (t < 0) begin $display("  frame %0d (%0d bytes) at byte %0d: check %0d", f, pay_len[f], p, -t); fail("a frame on the wire isn't what was sent"); end
                else begin
                    gap = 0; p = t;
                    while (p < sn && !(sc[p] && sb[p] == 8'hFB)) begin p = p + 1; gap = gap + 1; end
                    if (f + 1 < to_frame && gap < minimum) minimum = gap;
                end
            end
            if (minimum < 12) begin $display("  shortest gap %0d bytes", minimum); fail("less than 12 bytes between frames"); end
        end
    endtask
    task check_received(input integer f, input integer g, input expect_error);
        integer i, len, wrong;
        begin
            len = pay_len[f] < 60 ? 60 : pay_len[f];
            if (got_err[g] !== expect_error) begin $display("  frame %0d: error %b", f, got_err[g]); fail("rx_error isn't what the frame deserves"); end
            if (!expect_error) begin
                wrong = got_len[g] != len;
                for (i = 0; i < len && !wrong; i = i + 1)
                    if (got[got_at[g] + i] !== (i < pay_len[f] ? pay[pay_at[f] + i] : 8'h00)) wrong = 1;
                if (wrong) begin $display("  frame %0d: %0d bytes back, %0d sent", f, got_len[g], len); fail("a frame came back changed"); end
            end
        end
    endtask

    // Crafted blocks straight into the receiver.
    reg [7:0] cb [0:8191];
    reg cc [0:8191];
    integer cn = 0;
    task cput(input [7:0] b, input c);
        begin cb[cn] = b; cc[cn] = c; cn = cn + 1; end
    endtask
    // A frame of `len` payload bytes with its FCS (`error_at` >= 0: an error character instead of that byte).
    task craft(input integer len, input integer error_at);
        integer i;
        reg [31:0] c;
        reg [7:0] b;
        begin
            cput(8'hFB, 1); for (i = 0; i < 6; i = i + 1) cput(8'h55, 0); cput(8'hD5, 0);
            c = 32'hFFFFFFFF;
            for (i = 0; i < len; i = i + 1) begin
                b = $random(seed);
                if (i == error_at) cput(8'hFE, 1); else cput(b, 0);
                c = crc_step(c, b);
            end
            c = ~c;
            for (i = 0; i < 4; i = i + 1) cput(c[8 * i +: 8], 0);
            cput(8'hFD, 1);
        end
    endtask
    task idles(input integer upto);                   // at least four idles (5 bytes with the terminate), up to a multiple of `upto`
        begin repeat (4) cput(8'h07, 1); while (cn % upto != 0) cput(8'h07, 1); end
    endtask
    // The shortest gap: the terminate and four idles, and the next start must fall on lane 0 or 4.
    task gap5;
        begin
            repeat (4) cput(8'h07, 1);
            if (cn % 4 != 0) fail("the testbench's gap5 doesn't end on lane 0 or 4");
        end
    endtask

    integer f, g0, i;
    initial begin
        $dumpfile("eth_mac_10g_tb.vcd");
        $dumpvars(1, eth_mac_10g_tb);
        // The testbench's CRC first: "123456789" -> CBF43926.
        begin : known
            reg [31:0] c; reg [8*9-1:0] text; integer j;
            text = "123456789"; c = 32'hFFFFFFFF;
            for (j = 8; j >= 0; j = j - 1) c = crc_step(c, text[8 * j +: 8]);
            if (~c != 32'hCBF43926) fail("the testbench's own CRC-32 is wrong");
        end

        // ---- Frames of every awkward length, back to back ----------------------------------------------------------------
        make(1); make(13); make(45); make(46); make(47); make(59); make(60); make(61); make(62); make(63);
        make(64); make(65); make(66); make(67); make(100); make(255); make(1500);
        repeat (40) @(posedge clk);
        for (f = 0; f < 17; f = f + 1) send(f, -1);
        repeat (200) @(posedge clk);
        check_wire(0, 17);
        if (got_frames != 17) fail("not every frame came back");
        for (f = 0; f < 17 && f < got_frames; f = f + 1) check_received(f, f, 1'b0);
        if (rx_frames != 17 || rx_bad_frames != 0) fail("rx_frames / rx_bad_frames don't count 17 good frames");

        // ---- A corrupted byte: rx_error, a bad frame ----------------------------------------------------------------------
        make(100);
        corrupt_at = sn + 40;                          // in the frame's payload: it starts within 8 bytes
        send(17, -1);
        repeat (200) @(posedge clk);
        if (got_frames != 18) fail("the corrupted frame didn't arrive");
        else check_received(17, 17, 1'b1);
        if (rx_bad_frames != 1) fail("the corrupted frame wasn't counted bad");
        corrupt_at = -1;

        // ---- An underrun: an error goes out, the rest is dropped, the next frame is fine ----------------------------------
        make(200); make(80);
        send(18, 10);
        send(19, -1);
        repeat (200) @(posedge clk);
        if (got_frames != 20) fail("after an underrun: not two frames back");
        else begin check_received(18, 18, 1'b1); check_received(19, 19, 1'b0); end
        begin : underrun_wire
            integer p, e;
            e = 0;
            for (p = 0; p < sn; p = p + 1) if (sc[p] && sb[p] == 8'hFE) e = e + 1;
            if (e == 0) fail("the underrun sent no error character");
        end

        // ---- Crafted: starts in lane 4 and 0 after 5-byte gaps (the terminate in lane 3 or 7: 4 idles reach lane 0 or 4),
        // a runt, an error character -------------------------------------------------------------------------------------
        repeat (40) @(posedge clk);
        crafted <= 1'b1;
        g0 = got_frames;
        idles(8); repeat (4) cput(8'h07, 1);           // start in lane 4
        craft(71, -1); gap5;                           // terminate in lane 7: lane 4 -> lane 4
        craft(91, -1); gap5;                           // terminate in lane 3: lane 4 -> lane 0
        craft(79, -1); gap5;                           // terminate in lane 3: lane 0 -> lane 0
        craft(83, -1); gap5;                           // terminate in lane 7: lane 0 -> lane 4
        craft(70, -1);
        idles(8); craft(20, -1);                       // a runt: 28 bytes
        idles(8); craft(80, 33);                       // an error character
        idles(8); idles(8);
        i = 0;
        while (i < cn) begin
            @(negedge clk);
            if (ready) begin
                for (k = 0; k < 8; k = k + 1) begin cr_d[8 * k +: 8] = cb[i + k]; cr_c[k] = cc[i + k]; end
                i = i + 8;
            end
        end
        @(negedge clk); cr_d = {8{8'h07}}; cr_c = 8'hFF;
        repeat (20) @(posedge clk);
        if (got_frames - g0 != 7) begin $display("  %0d crafted frames back", got_frames - g0); fail("crafted frames: expected seven"); end
        else begin
            for (i = 0; i < 5; i = i + 1)
                if (got_err[g0 + i] || got_len[g0 + i] != (i == 0 ? 71 : i == 1 ? 91 : i == 2 ? 79 : i == 3 ? 83 : 70)) begin
                    $display("  crafted frame %0d: %0d bytes, error %b", i, got_len[g0 + i], got_err[g0 + i]);
                    fail("a frame after the shortest gap wasn't received");
                end
            if (!got_err[g0 + 5]) fail("a runt wasn't flagged");
            if (!got_err[g0 + 6]) fail("an error character wasn't flagged");
        end

        if (!keep_ok) fail("rx_keep empty, not from lane 0, or partial before the last word");
        if (failures == 0) $display("PASS: eth_mac_10g framing, padding, FCS, gaps, receive, corruption, underrun, runts");
        else $display("FAIL: %0d check(s)", failures);
        $finish;
    end
    initial begin #2000000; $display("FAIL: timeout"); $finish; end
endmodule
