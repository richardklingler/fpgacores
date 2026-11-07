// Testbench for eth_10gbase_r_pcs.
// 1. Without the scrambler: XGMII blocks encode to the block formats of IEEE 802.3 figure 49-7 (spelled out here), and
//    crafted blocks — ordered sets, an invalid header, an unknown type, a bad control code too — decode back.
// 2. With the scrambler, over a serial model of the transceiver's gearbox (most significant bit first, BIT_REVERSE 1):
//    a misaligned receiver finds block lock through rx_slip, the XGMII stream (frames starting in lane 0 and 4,
//    terminates in every lane, an error character) comes back unchanged, a flipped payload bit spoils at most two
//    blocks (the descrambler resynchronises), 16 bad headers within the BER window raise high_ber, 20 in a row lose block
//    lock, which comes back. Noise instead of the link asks for a receiver restart (rx_restart); the clean link never.
`timescale 1ns / 1ps

module eth_10gbase_r_pcs_tb;
    reg clk = 1'b0;
    always #3.103 clk = ~clk;
    integer failures = 0;
    task fail(input [8*100-1:0] what);
        begin $display("FAIL: %0s", what); failures = failures + 1; end
    endtask

    // The gearbox's sequence counter (0 ... 32, no data at 32), one for transmit and one for receive.
    reg [5:0] seq = 6'd0, rseq = 6'd17;
    always @(posedge clk) begin
        seq <= seq == 6'd32 ? 6'd0 : seq + 6'd1;
        rseq <= rseq == 6'd32 ? 6'd0 : rseq + 6'd1;
    end
    function [63:0] rev(input [63:0] v);
        integer i;
        for (i = 0; i < 64; i = i + 1) rev[i] = v[63 - i];
    endfunction
    localparam [1:0] DATA = 2'b10, CTRL = 2'b01;      // {second, first} on the wire

    // ==== 1. Block formats, unscrambled ==================================================================================
    localparam N = 13;
    reg [63:0] vd [0:N-1];                            // XGMII
    reg [7:0] vc [0:N-1];
    reg [63:0] vp [0:N-1];                            // its block
    reg [1:0] vh [0:N-1];
    function [63:0] codes(input [6:0] c);             // a 0x1E block of one control code
        integer i;
        begin codes = 64'h1E; for (i = 0; i < 8; i = i + 1) codes[8 + 7 * i +: 7] = c; end
    endfunction
    initial begin
        vd[0] = 64'h0707070707070707; vc[0] = 8'hFF; vp[0] = 64'h000000000000001E; vh[0] = CTRL;   // idle
        vd[1] = 64'hD5555555555555FB; vc[1] = 8'h01; vp[1] = 64'hD555555555555578; vh[1] = CTRL;   // start, lane 0
        vd[2] = 64'h0123456789ABCDEF; vc[2] = 8'h00; vp[2] = 64'h0123456789ABCDEF; vh[2] = DATA;   // data
        vd[3] = 64'h07070707FDCCBBAA; vc[3] = 8'hF8; vp[3] = 64'h00000000CCBBAAB4; vh[3] = CTRL;   // terminate, lane 3
        vd[4] = 64'h07070707070707FD; vc[4] = 8'hFF; vp[4] = 64'h0000000000000087; vh[4] = CTRL;   // terminate, lane 0
        vd[5] = 64'h555555FB07070707; vc[5] = 8'h1F; vp[5] = 64'h5555550000000033; vh[5] = CTRL;   // start, lane 4
        vd[6] = 64'hFD66554433221100; vc[6] = 8'h80; vp[6] = 64'h66554433221100FF; vh[6] = CTRL;   // terminate, lane 7
        vd[7] = 64'h0707FD5544332211; vc[7] = 8'hE0; vp[7] = 64'd0; vh[7] = CTRL; // terminate, lane 5
        vd[8] = 64'hFEFEFEFEFEFEFEFE; vc[8] = 8'hFF; vp[8] = codes(7'h1E); vh[8] = CTRL;            // error
        vd[9] = 64'h0707070707070707; vc[9] = 8'h02; vp[9] = codes(7'h1E); vh[9] = CTRL;            // no such block
        vd[10] = 64'h0707070707FD0707; vc[10] = 8'hFF; vp[10] = 64'h1E; vh[10] = CTRL;               // T after control
        // Terminate in lane 5: D0-D4 at bits 8-47, 2 zero bits, C6 and C7 (idle, 0).
        vp[7] = {16'h0000, 40'h5544332211, 8'hD2};
        // Terminate in lane 3, error characters after it: codes 0x1E from bit 36 on (type, 3 data bytes, 4 zero bits).
        vd[11] = 64'hFEFEFEFEFDCCBBAA; vc[11] = 8'hF8; vh[11] = CTRL;
        vp[11] = {7'h1E, 7'h1E, 7'h1E, 7'h1E, 4'h0, 24'hCCBBAA, 8'hB4};
        // Data after control characters in lanes 0-4 without a start in lane 4: no such block.
        vd[12] = 64'h5555550707070707; vc[12] = 8'h1F; vp[12] = codes(7'h1E); vh[12] = CTRL;
        // A terminate after control characters isn't a terminate block: that lane alone becomes /E/.
        vp[10][8 + 7 * 2 +: 7] = 7'h1E;
    end

    integer p_ix = 0;
    wire plain_ready;
    always @(posedge clk) if (plain_ready) p_ix <= p_ix == N - 1 ? 0 : p_ix + 1;
    wire [63:0] plain_tx_data, plain_rxd;
    wire [1:0] plain_tx_header;
    wire [7:0] plain_rxc;
    wire plain_rx_valid;

    // Decoding: crafted blocks into the receiver, a block a cycle.
    localparam M = 11;
    reg [63:0] dp [0:M-1];
    reg [1:0] dh [0:M-1];
    reg [63:0] dd [0:M-1];
    reg [7:0] dc [0:M-1];
    initial begin
        dp[0] = 64'h000000000100004B; dh[0] = CTRL; dd[0] = 64'h070707070100009C; dc[0] = 8'hF1;   // local fault, lane 0
        dp[1] = 64'h5555550001000066; dh[1] = CTRL; dd[1] = 64'h555555FB0100009C; dc[1] = 8'h11;   // ordered set + start 4
        dp[2] = 64'h0200000001000055; dh[2] = CTRL; dd[2] = 64'h0200009C0100009C; dc[2] = 8'h11;   // two ordered sets
        dp[3] = 64'h010000000000002D; dh[3] = CTRL; dd[3] = 64'h0100009C07070707; dc[3] = 8'h1F;   // ordered set, lane 4
        dp[4] = 64'h5555550000000033; dh[4] = CTRL; dd[4] = 64'h555555FB07070707; dc[4] = 8'h1F;   // start, lane 4
        dp[5] = 64'h0123456789ABCDEF; dh[5] = 2'b00; dd[5] = 64'hFEFEFEFEFEFEFEFE; dc[5] = 8'hFF;   // invalid header
        dp[6] = 64'h0123456789ABCD11; dh[6] = CTRL; dd[6] = 64'hFEFEFEFEFEFEFEFE; dc[6] = 8'hFF;   // unknown type
        dp[7] = 64'h0000000000002A1E; dh[7] = CTRL; dd[7] = 64'hFEFEFEFEFEFEFEFE; dc[7] = 8'hFF;   // bad control code
        dp[8] = 64'h00000000CCBBAAB4; dh[8] = CTRL; dd[8] = 64'h07070707FDCCBBAA; dc[8] = 8'hF8;   // terminate, lane 3
        dp[9] = {7'h1E, 7'h1E, 7'h1E, 7'h1E, 4'h0, 24'hCCBBAA, 8'hB4}; dh[9] = CTRL;                // … errors after it
        dd[9] = 64'hFEFEFEFEFDCCBBAA; dc[9] = 8'hF8;
        dp[10] = {7'h1E, 7'h1E, 7'h1E, 7'h1E, 4'h0, 24'h010000, 8'h4B}; dh[10] = CTRL;              // ordered set, errors
        dd[10] = 64'hFEFEFEFE0100009C; dc[10] = 8'hF1;
    end
    integer d_ix = 0;
    always @(posedge clk) if (rseq != 6'd32) d_ix <= d_ix == M - 1 ? 0 : d_ix + 1;
    wire [63:0] plain_rx_data = rev(dp[d_ix]);
    wire [1:0] plain_rx_header = {dh[d_ix][0], dh[d_ix][1]};

    eth_10gbase_r_pcs #(.SCRAMBLER(0), .BER_WINDOW(1000)) u_plain (
        .tx_clk(clk), .tx_sequence(seq), .xgmii_txd(vd[p_ix]), .xgmii_txc(vc[p_ix]), .xgmii_tx_ready(plain_ready),
        .xgmii_tx_ready_next(), .tx_data(plain_tx_data), .tx_header(plain_tx_header),
        .rx_clk(clk), .rx_reset(1'b0), .rx_data(plain_rx_data), .rx_header(plain_rx_header),
        .rx_data_valid(rseq != 6'd32), .rx_header_valid(rseq != 6'd32), .rx_slip(), .rx_restart(),
        .xgmii_rxd(plain_rxd), .xgmii_rxc(plain_rxc), .xgmii_rx_valid(plain_rx_valid),
        .block_lock(), .high_ber(), .rx_error_blocks());

    // Encoded blocks as the gearbox takes them, and decoded blocks as they arrive.
    reg [63:0] enc_p [0:255]; reg [1:0] enc_h [0:255];
    integer enc_n = 0;
    always @(posedge clk) if (seq != 6'd32 && enc_n < 256) begin
        enc_p[enc_n] <= rev(plain_tx_data); enc_h[enc_n] <= {plain_tx_header[0], plain_tx_header[1]}; enc_n <= enc_n + 1;
    end
    reg [63:0] dec_d [0:255]; reg [7:0] dec_c [0:255];
    integer dec_n = 0;
    always @(posedge clk) if (plain_rx_valid && dec_n < 256) begin
        dec_d[dec_n] <= plain_rxd; dec_c[dec_n] <= plain_rxc; dec_n <= dec_n + 1;
    end

    task check_formats;
        integer i, k, start, wrong;
        begin
            // Encoding: find the idle-then-start pair, then N blocks in order.
            start = -1;
            for (i = 4; i < enc_n - N && start < 0; i = i + 1) if (enc_p[i] == vp[1] && enc_p[i - 1] == vp[0]) start = i - 1;
            if (start < 0) fail("encoder: the start block never came out");
            else begin
                wrong = 0;
                for (k = 0; k < 3 * N; k = k + 1)
                    if (enc_p[start + k] !== vp[k % N] || enc_h[start + k] !== vh[k % N]) begin
                        wrong = wrong + 1;
                        if (wrong < 4) $display("  encoder: block %0d is %h/%b, expected %h/%b", k % N, enc_p[start + k], enc_h[start + k], vp[k % N], vh[k % N]);
                    end
                if (wrong != 0) fail("encoder: blocks differ from figure 49-7");
            end
            // Decoding: find the local fault, then M blocks in order.
            start = -1;
            for (i = 2; i < dec_n - M && start < 0; i = i + 1) if (dec_d[i] == dd[0] && dec_c[i] == dc[0]) start = i;
            if (start < 0) fail("decoder: the ordered set never came out");
            else begin
                wrong = 0;
                for (k = 0; k < 3 * M; k = k + 1)
                    if (dec_d[start + k] !== dd[k % M] || dec_c[start + k] !== dc[k % M]) begin
                        wrong = wrong + 1;
                        if (wrong < 4) $display("  decoder: block %0d is %h/%h, expected %h/%h", k % M, dec_d[start + k], dec_c[start + k], dd[k % M], dc[k % M]);
                    end
                if (wrong != 0) fail("decoder: blocks differ");
            end
        end
    endtask

    // ==== 2. A serial link =================================================================================================
    // The XGMII stream to send, byte by byte: frames starting in lane 0 or 4, 46-200 data bytes, a terminate, idles.
    localparam Q = 1 << 19;
    reg [7:0] qd [0:Q-1];
    reg qc [0:Q-1];
    integer qn = 0;
    task put(input [7:0] d, input c);
        begin qd[qn] = d; qc[qn] = c; qn = qn + 1; end
    endtask
    integer f, i2, len, gap, seed = 7;
    initial begin
        for (f = 0; qn < Q - 512; f = f + 1) begin
            gap = 5 + ($random(seed) & 15);
            for (i2 = 0; i2 < gap; i2 = i2 + 1) put(8'h07, 1'b1);
            // Lane 0 or lane 4 of a block.
            while ((f & 1) ? qn % 8 != 4 : qn % 8 != 0) put(8'h07, 1'b1);
            put(8'hFB, 1'b1);
            for (i2 = 0; i2 < 6; i2 = i2 + 1) put(8'h55, 1'b0);
            put(8'hD5, 1'b0);
            len = 46 + ($random(seed) & 127) + (f % 8);
            for (i2 = 0; i2 < len; i2 = i2 + 1)
                if (f % 23 == 5 && i2 == 20) put(8'hFE, 1'b1);              // an error character now and then
                else put($random(seed), 1'b0);
            put(8'hFD, 1'b1);
        end
        while (qn < Q) put(8'h07, 1'b1);
    end

    wire link_ready;
    integer head = 0;
    always @(posedge clk) if (link_ready && head < Q - 8) head <= head + 8;
    wire [63:0] link_txd = {qd[head + 7], qd[head + 6], qd[head + 5], qd[head + 4], qd[head + 3], qd[head + 2], qd[head + 1], qd[head]};
    wire [7:0] link_txc = {qc[head + 7], qc[head + 6], qc[head + 5], qc[head + 4], qc[head + 3], qc[head + 2], qc[head + 1], qc[head]};
    wire [63:0] link_tx_data;
    wire [1:0] link_tx_header;

    // The wire: most significant bit first, header first; bits a test flips.
    localparam W = 8192;
    reg wire_bits [0:W-1];
    integer wr = 0, rd = 0, k2;
    // The testbench's own descrambler (x^58 + x^39 + 1, bit by bit) on what the transmitter puts on the wire: the idle
    // blocks between frames must read 0x1E with a control header. A wrong polynomial at both ends would pass the link.
    reg [57:0] wire_state = 58'd0;
    reg [63:0] wire_payload;
    reg [1:0] wire_sync;
    integer wire_idles = 0, wire_bit = 0;
    task wire_take(input b);
        begin
            if (wire_bit < 2) wire_sync[wire_bit] = b;
            else begin
                wire_payload[wire_bit - 2] = b ^ wire_state[38] ^ wire_state[57];
                wire_state = {wire_state[56:0], b};
            end
            wire_bit = wire_bit + 1;
            if (wire_bit == 66) begin
                if (wire_sync == 2'b01 && wire_payload == 64'h1E) wire_idles = wire_idles + 1;
                wire_bit = 0;
            end
        end
    endtask
    always @(posedge clk) if (seq != 6'd32) begin
        wire_bits[wr % W] = link_tx_header[1]; wire_bits[(wr + 1) % W] = link_tx_header[0];
        wire_take(link_tx_header[1]); wire_take(link_tx_header[0]);
        for (k2 = 0; k2 < 64; k2 = k2 + 1) begin wire_bits[(wr + 2 + k2) % W] = link_tx_data[63 - k2]; wire_take(link_tx_data[63 - k2]); end
        wr = wr + 66;
    end
    // The receiver starts 37 bits off a block boundary; a slip skips one bit two cycles later. `noise` replaces the link
    // with random bits.
    reg receiving = 1'b0, noise = 1'b0;
    integer noise_seed = 3;
    reg [63:0] link_rx_data = 64'd0;
    reg [1:0] link_rx_header = 2'b00;
    reg link_rx_valid = 1'b0, link_rx_hvalid = 1'b0;
    wire link_slip;
    reg [1:0] slip_delay = 2'b00;
    integer slips = 0, k3, last_header = 0;
    always @(posedge clk) begin
        slip_delay <= {slip_delay[0], link_slip};
        if (slip_delay[1]) begin rd = rd + 1; slips = slips + 1; end
        if (!receiving && wr > 2000 && rseq == 6'd0) begin receiving <= 1'b1; rd = wr - 1500 + 37; end
        link_rx_valid <= receiving && rseq != 6'd32;
        link_rx_hvalid <= receiving && rseq != 6'd32;
        if (receiving && rseq != 6'd32) begin
            last_header = rd;
            link_rx_header <= {wire_bits[rd % W], wire_bits[(rd + 1) % W]};
            for (k3 = 0; k3 < 64; k3 = k3 + 1) link_rx_data[63 - k3] <= wire_bits[(rd + 2 + k3) % W];
            if (noise) begin link_rx_header <= $random(noise_seed); link_rx_data <= {$random(noise_seed), $random(noise_seed)}; end
            rd = rd + 66;
        end
    end
    wire [63:0] link_rxd;
    wire [7:0] link_rxc;
    wire link_rx_out, block_lock, high_ber, link_restart;
    wire [31:0] error_blocks;
    eth_10gbase_r_pcs #(.BER_WINDOW(1000), .RESTART_BLOCKS(20000)) u_link (
        .tx_clk(clk), .tx_sequence(seq), .xgmii_txd(link_txd), .xgmii_txc(link_txc), .xgmii_tx_ready(link_ready),
        .xgmii_tx_ready_next(), .tx_data(link_tx_data), .tx_header(link_tx_header),
        .rx_clk(clk), .rx_reset(1'b0), .rx_data(link_rx_data), .rx_header(link_rx_header), .rx_data_valid(link_rx_valid),
        .rx_header_valid(link_rx_hvalid), .rx_slip(link_slip), .rx_restart(link_restart),
        .xgmii_rxd(link_rxd), .xgmii_rxc(link_rxc), .xgmii_rx_valid(link_rx_out),
        .block_lock(block_lock), .high_ber(high_ber), .rx_error_blocks(error_blocks));
    integer restarts = 0;
    always @(posedge clk) if (link_restart) restarts = restarts + 1;
    // The ready a cycle ahead must be next cycle's ready.
    reg ready_was_predicted = 1'b0, ahead_ok = 1'b1;
    always @(posedge clk) begin
        ready_was_predicted <= u_link.xgmii_tx_ready_next;
        if (ready_was_predicted !== link_ready && $time > 100) ahead_ok = 1'b0;
    end

    // What came out while locked, block by block; compared with the stream sent once aligned on 16 blocks in a row.
    localparam R = 1 << 15;
    reg [63:0] rxd_log [0:R-1];
    reg [7:0] rxc_log [0:R-1];
    integer rxn = 0;
    always @(posedge clk) if (link_rx_out && block_lock && rxn < R) begin
        rxd_log[rxn] = link_rxd; rxc_log[rxn] = link_rxc; rxn = rxn + 1;
    end
    // Received block j against stream bytes q … q+7. A block with an error character among data bytes has no 66-bit
    // format: it goes out as an error block, all /E/.
    function same(input integer j, input integer q);
        integer k;
        reg mixed;
        reg [63:0] d;
        reg [7:0] c;
        begin
            mixed = 1'b0;
            for (k = 0; k < 8; k = k + 1) begin
                if (qc[q + k] && qd[q + k] == 8'hFE) mixed = 1'b1;
                d[8 * k +: 8] = qd[q + k]; c[k] = qc[q + k];
            end
            if (mixed && c != 8'hFF) same = rxd_log[j] === {8{8'hFE}} && rxc_log[j] === 8'hFF;
            else same = rxd_log[j] === d && rxc_log[j] === c;
        end
    endfunction
    integer j0 = -1, q0 = -1;
    task align(input integer from);
        integer q, k, run;
        begin
            j0 = from; q0 = -1;
            for (q = 0; q + 8 * 20 < head && q0 < 0; q = q + 8) begin
                run = 0;
                for (k = 0; k < 16; k = k + 1) if (same(from + k, q + 8 * k)) run = run + 1;
                if (run == 16) q0 = q;
            end
        end
    endtask
    // Blocks from j to n that differ from the stream (with the alignment found).
    integer matched = 0, mismatched = 0;
    task compare(input integer from, input integer upto);
        integer j;
        begin
            matched = 0; mismatched = 0;
            for (j = from; j < upto; j = j + 1)
                if (same(j, q0 + 8 * (j - j0))) matched = matched + 1; else mismatched = mismatched + 1;
        end
    endtask

    integer matched_before, lock_drops = 0, b;
    reg was_locked = 1'b0;
    always @(posedge clk) begin was_locked <= block_lock; if (was_locked && !block_lock) lock_drops = lock_drops + 1; end
    // Flip a bit on the wire three blocks ahead of the last header read: 0 a header bit, more a payload bit.
    task flip(input integer offset);
        integer at_bit;
        begin at_bit = last_header + 66 * 3 + offset; wire_bits[at_bit % W] = !wire_bits[at_bit % W]; end
    endtask
    task wait_header;
        begin @(posedge clk); while (!(receiving && rseq != 6'd32)) @(posedge clk); end
    endtask

    initial begin
        $dumpfile("eth_10gbase_r_pcs_tb.vcd");
        $dumpvars(1, eth_10gbase_r_pcs_tb);
        repeat (3000) @(posedge clk);
        check_formats;

        // ---- Lock, then the stream ----------------------------------------------------------------------------------
        repeat (20000) @(posedge clk);
        if (!block_lock) fail("no block lock");
        if (slips == 0) fail("locked without a slip, though the receiver started 37 bits off");
        align(100);
        if (q0 < 0) fail("the stream didn't come back (no 16 blocks in a row matched)");
        else begin
            compare(100, rxn);
            if (matched < 2000) fail("too few blocks came back");
            if (mismatched != 0) fail("blocks differ from the stream sent");
        end
        if (!ahead_ok) fail("xgmii_tx_ready_next isn't the next cycle's xgmii_tx_ready");
        if (high_ber || error_blocks != 0) fail("high BER or error blocks on a clean link");
        if (wire_idles < 500) fail("the wire doesn't carry x^58 + x^39 + 1 scrambled idle blocks");
        $display("  locked after %0d slips, %0d blocks matched, %0d idle blocks descrambled on the wire", slips, matched, wire_idles);

        // ---- A payload bit: at most two blocks spoilt, then the descrambler is back --------------------------------
        matched_before = rxn;
        wait_header; flip(2 + 10);
        repeat (2000) @(posedge clk);
        compare(matched_before, rxn);
        if (mismatched == 0) fail("a flipped bit changed nothing (the check doesn't see the stream)");
        if (mismatched > 2) fail("a flipped bit spoilt more than two blocks");
        if (!block_lock || matched < 1000) fail("the stream didn't go on after the flipped bit");
        $display("  one flipped bit: %0d blocks differed", mismatched);

        // ---- Bad headers every sixth block: never 16 within 64 blocks, so the lock stays, but 33 of them put 16 into
        // one BER window (1000 blocks) wherever its boundary falls: high_ber -----------------------------------------
        for (b = 0; b < 33; b = b + 1) begin
            wait_header; flip(0);
            repeat (6) wait_header;
        end
        repeat (50) @(posedge clk);
        if (!high_ber) fail("16 bad headers in the window didn't raise high_ber");
        if (lock_drops != 0) fail("spread bad headers lost the lock");
        repeat (6000) @(posedge clk);
        if (high_ber) fail("high_ber didn't clear after a clean window");

        // ---- 20 bad headers in a row: lock lost, found again ------------------------------------------------------------
        // Positions fixed up front: with a block a cycle, flipping "the next header" each cycle could hit one twice.
        wait_header;
        for (b = 0; b < 20; b = b + 1) flip(66 * b);
        repeat (200) @(posedge clk);
        if (lock_drops == 0) fail("20 bad headers in a row kept the lock");
        repeat (20000) @(posedge clk);
        if (!block_lock) fail("no lock again after the bad headers");
        if (restarts != 0) fail("a receiver restart while the link was there");

        // ---- Noise: lock lost for good, the PCS asks for a restart --------------------------------------------------
        noise = 1'b1;
        repeat (30000) @(posedge clk);
        if (block_lock) fail("locked on noise");
        if (restarts == 0) fail("no rx_restart after 20,000 blocks without lock");
        $display("  noise: %0d restart request(s)", restarts);

        if (failures == 0) $display("PASS: eth_10gbase_r_pcs block formats, lock, stream, descrambler, BER, relock");
        else $display("FAIL: %0d check(s)", failures);
        $finish;
    end
    initial begin #4000000; $display("FAIL: timeout"); $finish; end
endmodule
