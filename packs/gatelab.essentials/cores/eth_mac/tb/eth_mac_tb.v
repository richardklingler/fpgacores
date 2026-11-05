// Self-checking testbench for eth_mac on eth_rmii_phy, against a model of a PHY's RMII side (outputs changed 4 ns
// after the reference clock's rising edge).
// Receive: a 64-byte frame, a 1518-byte one, a bad FCS, a runt (44 bytes), one too long (1523), one with RX_ER —
// each frame's bytes without the FCS must come out in order, `rx_last` on the last, `rx_good` only for the good
// ones.
// Send: 14 bytes (padded to 60), exactly 60, 59 (one zero), 100 and straight after it 30 more (the gap between them
// at least 48 clocks with TX_EN low), and one with an underrun. Each must go out as 7 × 55, D5, the bytes, the zeros,
// the FCS — two of them checked against FCS values computed with Python's zlib (60 bytes (i*7+1): ed 70 90 df; 14
// padded: 6b de f2 d2), the rest with the residue. The underrun's frame must fail its FCS and say so.
// Prints PASS or every failed check.

`timescale 1ns / 1ps

module eth_mac_tb;
    reg clk = 1'b0;
    always #10 clk = ~clk;   // 50 MHz
    integer errors = 0;

    reg  [1:0] rxd = 2'b00;
    reg        crs_dv = 1'b0, rx_er = 1'b0;
    wire [1:0] txd;
    wire       tx_en;
    wire [7:0] p_rx_data, p_tx_data;
    wire       p_rx_valid, p_rx_end, p_rx_error, p_tx_valid, p_tx_ready;
    wire [7:0] rx_data;
    wire       rx_valid, rx_last, rx_good, tx_ready, tx_underrun;
    reg  [7:0] tx_data = 8'd0;
    reg        tx_valid = 1'b0, tx_last = 1'b0;

    eth_rmii_phy u_phy (.clk(clk), .rmii_rxd(rxd), .rmii_crs_dv(crs_dv), .rmii_rx_er(rx_er), .rmii_txd(txd),
        .rmii_tx_en(tx_en), .rx_data(p_rx_data), .rx_valid(p_rx_valid), .rx_end(p_rx_end), .rx_error(p_rx_error),
        .tx_data(p_tx_data), .tx_valid(p_tx_valid), .tx_ready(p_tx_ready));
    eth_mac dut (.clk(clk), .phy_rx_data(p_rx_data), .phy_rx_valid(p_rx_valid), .phy_rx_end(p_rx_end),
        .phy_rx_error(p_rx_error), .phy_tx_data(p_tx_data), .phy_tx_valid(p_tx_valid), .phy_tx_ready(p_tx_ready),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_last(rx_last), .rx_good(rx_good),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready), .tx_underrun(tx_underrun));

    task fail(input [8*72-1:0] what);
        begin
            $display("FAIL: %0s", what);
            errors = errors + 1;
        end
    endtask

    // A CRC-32 written differently from the core's.
    function [31:0] crc_update(input [31:0] c, input [7:0] d);
        integer i;
        reg [31:0] x;
        begin
            x = c ^ {24'd0, d};
            for (i = 0; i < 8; i = i + 1) x = {1'b0, x[31:1]} ^ (x[0] ? 32'hEDB8_8320 : 32'd0);
            crc_update = x;
        end
    endfunction

    // ---- Received frames ----------------------------------------------------------------------------------
    reg [7:0] got [0:2047];
    integer got_n = 0, lasts = 0, last_at = -1;
    reg good = 1'b0;
    always @(posedge clk)
        if (rx_valid) begin
            got[got_n] = rx_data;
            if (rx_last) begin lasts = lasts + 1; last_at = got_n; good = rx_good; end
            got_n = got_n + 1;
        end

    reg [7:0] frame [0:2047];
    task put_dibit(input [1:0] d, input dv);
        begin
            @(posedge clk); #4;
            rxd = d;
            crs_dv = dv;
        end
    endtask

    // `n` bytes of frame[] then their FCS (`bad`: one bit flipped), RX_ER during byte `er_at`.
    task send(input integer n, input bad, input integer er_at);
        integer i, j;
        reg [31:0] c;
        reg [7:0] b;
        begin
            c = 32'hFFFF_FFFF;
            for (i = 0; i < n; i = i + 1) c = crc_update(c, frame[i]);
            c = ~c ^ (bad ? 32'h0040_0000 : 32'd0);
            put_dibit(2'b00, 1'b1);
            for (i = 0; i < 31; i = i + 1) put_dibit(2'b01, 1'b1);
            put_dibit(2'b11, 1'b1);
            for (i = 0; i < n + 4; i = i + 1) begin
                b = i < n ? frame[i] : c[8 * (i - n) +: 8];
                for (j = 0; j < 4; j = j + 1) begin
                    rx_er = (i == er_at);
                    put_dibit(b[2 * j +: 2], 1'b1);
                end
            end
            rx_er = 1'b0;
            put_dibit(2'b00, 1'b0);
            repeat (8) @(posedge clk);
        end
    endtask

    task check_rx(input integer n, input expect_good, input [8*40-1:0] what);
        integer i, wrong;
        begin
            wrong = 0;
            if (got_n != n) begin $display("FAIL: %0s: %0d bytes out, expected %0d", what, got_n, n); errors = errors + 1; end
            else for (i = 0; i < n; i = i + 1) if (got[i] !== frame[i]) wrong = wrong + 1;
            if (wrong != 0) begin $display("FAIL: %0s: %0d bytes wrong", what, wrong); errors = errors + 1; end
            if (lasts != 1 || last_at != n - 1) begin
                $display("FAIL: %0s: %0d rx_last, at byte %0d", what, lasts, last_at);
                errors = errors + 1;
            end else if (good !== expect_good) begin
                $display("FAIL: %0s: rx_good %b", what, good);
                errors = errors + 1;
            end
            got_n = 0;
            lasts = 0;
            last_at = -1;
        end
    endtask

    // ---- Sent frames: decoded from TXD while TX_EN is up -----------------------------------------------------
    reg [7:0] wire_bytes [0:2047];
    integer wire_n = 0, dibits = 0, frames_out = 0, quiet = 0, min_gap = 1000000;
    reg [7:0] shift = 8'd0;
    reg tx_en_was = 1'b0;
    always @(posedge clk) begin
        if (tx_en) begin
            if (!tx_en_was && frames_out > 0 && quiet < min_gap) min_gap = quiet;
            shift = {txd, shift[7:2]};
            dibits = dibits + 1;
            if (dibits % 4 == 0) begin wire_bytes[wire_n] = shift; wire_n = wire_n + 1; end
        end else begin
            if (tx_en_was) frames_out = frames_out + 1;
            quiet = tx_en_was ? 1 : quiet + 1;
        end
        tx_en_was = tx_en;
    end

    reg [7:0] out [0:2047];
    // Offers out[0 .. n-1]; `stall_at`: the byte withheld for 8 clocks once it's asked for (-1 none).
    task offer(input integer n, input integer stall_at);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                tx_data = out[i];
                tx_last = (i == n - 1);
                tx_valid = 1'b1;
                if (i == stall_at) begin
                    tx_valid = 1'b0;
                    @(negedge clk);
                    while (!p_tx_ready || dut.state != 3'd2) @(negedge clk);   // asked for and not there
                    repeat (8) @(posedge clk);
                    #1;
                    tx_valid = 1'b1;
                end
                @(negedge clk);
                while (!tx_ready) @(negedge clk);
                @(posedge clk);
                #1;
            end
            tx_valid = 1'b0;
            tx_last = 1'b0;
        end
    endtask

    // Waits for the frame to have gone out, then checks it: preamble, bytes, padding, FCS (residue; `fcs` if not 0).
    task check_tx(input integer n, input [31:0] fcs, input expect_bad, input [8*40-1:0] what);
        integer i, padded, wrong, start;
        reg [31:0] c;
        begin
            while (frames_out == 0) @(posedge clk);
            padded = n < 60 ? 60 : n;
            wrong = 0;
            if (!expect_bad && wire_n != 8 + padded + 4) begin $display("FAIL: %0s: %0d bytes on the wire, expected %0d", what, wire_n, 12 + padded); errors = errors + 1; end
            else begin
                for (i = 0; i < 7; i = i + 1) if (wire_bytes[i] !== 8'h55) wrong = wrong + 1;
                if (wire_bytes[7] !== 8'hD5) wrong = wrong + 1;
                if (wrong != 0) begin $display("FAIL: %0s: the preamble", what); errors = errors + 1; end
                wrong = 0;
                for (i = 0; i < padded; i = i + 1)
                    if (wire_bytes[8 + i] !== (i < n ? out[i] : 8'h00)) wrong = wrong + 1;
                if (wrong != 0 && !expect_bad) begin $display("FAIL: %0s: %0d bytes wrong", what, wrong); errors = errors + 1; end
                c = 32'hFFFF_FFFF;
                for (i = 8; i < wire_n; i = i + 1) c = crc_update(c, wire_bytes[i]);
                if ((c === 32'hDEBB_20E3) === expect_bad) begin $display("FAIL: %0s: the FCS", what); errors = errors + 1; end
                start = 8 + padded;
                if (fcs != 0 && {wire_bytes[start], wire_bytes[start + 1], wire_bytes[start + 2], wire_bytes[start + 3]} !== fcs) begin
                    $display("FAIL: %0s: FCS %h %h %h %h, zlib says %h", what, wire_bytes[start], wire_bytes[start + 1],
                             wire_bytes[start + 2], wire_bytes[start + 3], fcs);
                    errors = errors + 1;
                end
            end
            wire_n = 0;
            dibits = 0;
            frames_out = 0;
        end
    endtask

    integer k;
    initial begin
        for (k = 0; k < 2048; k = k + 1) frame[k] = (k * 8'h5B) ^ 8'h3C ^ (k >> 4);

        // ---- Receive
        send(60, 0, -1);    check_rx(60, 1'b1, "64 bytes");
        send(1514, 0, -1);  check_rx(1514, 1'b1, "1518 bytes");
        send(60, 1, -1);    check_rx(60, 1'b0, "a bad FCS");
        send(40, 0, -1);    check_rx(40, 1'b0, "a runt");
        send(1519, 0, -1);  check_rx(1519, 1'b0, "1523 bytes");
        send(60, 0, 30);    check_rx(60, 1'b0, "RX_ER");
        send(61, 0, -1);    check_rx(61, 1'b1, "65 bytes");

        // ---- Send
        for (k = 0; k < 60; k = k + 1) out[k] = (k * 7 + 1) & 8'hFF;
        offer(14, -1);  check_tx(14, 32'h6BDE_F2D2, 1'b0, "14 bytes, padded");
        offer(60, -1);  check_tx(60, 32'hED70_90DF, 1'b0, "60 bytes");
        offer(59, -1);  check_tx(59, 0, 1'b0, "59 bytes");
        for (k = 0; k < 2048; k = k + 1) out[k] = (k * 8'h29) ^ 8'h96 ^ (k >> 5);
        offer(100, -1);
        min_gap = 1000000;
        offer(30, -1);   // straight after: the MAC waits for the gap
        while (frames_out < 2) @(posedge clk);
        if (min_gap < 48) begin $display("FAIL: an inter-frame gap of %0d clocks", min_gap); errors = errors + 1; end
        wire_n = 0; dibits = 0; frames_out = 0;
        offer(1514, -1); check_tx(1514, 0, 1'b0, "1514 bytes");
        offer(80, 20);   check_tx(80, 0, 1'b1, "an underrun");
        if (tx_underrun !== 1'b1) fail("tx_underrun not set");

        if (errors == 0) $display("PASS");
        else $display("FAILED: %0d", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL: watchdog");
        $finish;
    end
endmodule
