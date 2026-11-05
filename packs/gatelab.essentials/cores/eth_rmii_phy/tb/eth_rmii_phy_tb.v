// Self-checking testbench for eth_rmii_phy: a model of a PHY's RMII side (outputs changed 4 ns after the reference
// clock's rising edge) sends frames — CRS_DV up two clocks before the preamble, 7 × 55, D5, asymmetric bytes —
// plainly, with CRS_DV toggling over the last bytes, with RX_ER, ending inside a byte, and a false carrier (CRS_DV
// with 10 di-bits and no SFD). Every byte must arrive once, in order, then one rx_end with the right rx_error. The
// sender gets frames of 1, 2 and 9 bytes with gaps of different lengths in its tx_valid; TX_EN must be up exactly
// while their di-bits go out, low di-bit first. Prints PASS or every failed check.

`timescale 1ns / 1ps

module eth_rmii_phy_tb;
    reg clk = 1'b0;
    always #10 clk = ~clk;   // 50 MHz
    integer errors = 0;

    reg  [1:0] rxd = 2'b00;
    reg        crs_dv = 1'b0, rx_er = 1'b0;
    wire [1:0] txd;
    wire       tx_en;
    wire [7:0] rx_data;
    wire       rx_valid, rx_end, rx_error;
    reg  [7:0] tx_data = 8'd0;
    reg        tx_valid = 1'b0;
    wire       tx_ready;

    eth_rmii_phy dut (.clk(clk), .rmii_rxd(rxd), .rmii_crs_dv(crs_dv), .rmii_rx_er(rx_er), .rmii_txd(txd),
        .rmii_tx_en(tx_en), .rx_data(rx_data), .rx_valid(rx_valid), .rx_end(rx_end), .rx_error(rx_error),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready));

    // ---- What arrives ------------------------------------------------------------------------------------
    reg [7:0] got [0:255];
    integer got_n = 0, ends = 0;
    reg last_error = 1'b0;
    always @(posedge clk) begin
        if (rx_valid) begin got[got_n] = rx_data; got_n = got_n + 1; end
        if (rx_end) begin ends = ends + 1; last_error = rx_error; end
    end

    // ---- The PHY sending a frame ---------------------------------------------------------------------------
    reg [7:0] frame [0:255];
    task put_dibit(input [1:0] d, input dv);
        begin
            @(posedge clk); #4;
            rxd = d;
            crs_dv = dv;
        end
    endtask

    // `toggle`: CRS_DV low on each nibble's first di-bit over the last `toggle` bytes. `extra`: di-bits after the
    // last byte (a frame ending inside a byte). `er_at`: the byte during which RX_ER is high (-1 none).
    task send(input integer n, input integer toggle, input integer extra, input integer er_at);
        integer i, j;
        begin
            put_dibit(2'b00, 1'b1);
            put_dibit(2'b00, 1'b1);
            for (i = 0; i < 31; i = i + 1) put_dibit(2'b01, 1'b1);   // 7 × 55 and D5's first three
            put_dibit(2'b11, 1'b1);
            for (i = 0; i < n; i = i + 1)
                for (j = 0; j < 4; j = j + 1) begin
                    rx_er = (i == er_at);
                    put_dibit(frame[i][2 * j +: 2], (i >= n - toggle) ? (j % 2 == 1) : 1'b1);
                end
            rx_er = 1'b0;
            for (i = 0; i < extra; i = i + 1) put_dibit(2'b10, 1'b1);
            put_dibit(2'b00, 1'b0);
            repeat (6) @(posedge clk);
        end
    endtask

    task check_received(input integer n, input expect_error, input [8*24-1:0] what);
        integer i;
        begin
            if (got_n != n) begin $display("FAIL: %0s: %0d bytes, expected %0d", what, got_n, n); errors = errors + 1; end
            else for (i = 0; i < n; i = i + 1)
                if (got[i] !== frame[i]) begin
                    $display("FAIL: %0s: byte %0d is %h, expected %h", what, i, got[i], frame[i]);
                    errors = errors + 1;
                end
            if (ends != 1) begin $display("FAIL: %0s: %0d rx_end pulses", what, ends); errors = errors + 1; end
            else if (last_error !== expect_error) begin
                $display("FAIL: %0s: rx_error %b", what, last_error);
                errors = errors + 1;
            end
            got_n = 0;
            ends = 0;
        end
    endtask

    // ---- The sender: what goes out on TXD while TX_EN is up --------------------------------------------------
    reg [7:0] sent [0:63];
    integer sent_n = 0, out_dibits = 0, frames_out = 0;
    reg [7:0] out_byte = 8'd0;
    reg [7:0] on_wire [0:63];
    reg tx_en_was = 1'b0;
    always @(posedge clk) begin
        if (tx_en) begin
            out_byte = {txd, out_byte[7:2]};
            out_dibits = out_dibits + 1;
            if (out_dibits % 4 == 0) on_wire[out_dibits / 4 - 1] = out_byte;
        end
        if (tx_en_was && !tx_en) frames_out = frames_out + 1;
        tx_en_was = tx_en;
    end

    // The handshake: on the clock after valid and ready were both high, that byte's first di-bit is on TXD.
    always @(posedge clk)
        if (tx_valid && tx_ready) begin : handshake
            reg [7:0] taken;
            taken = tx_data;
            #2;
            if (tx_en !== 1'b1 || txd !== taken[1:0]) begin
                $display("FAIL: a byte taken (%h) didn't start on the next clock", taken);
                errors = errors + 1;
            end
        end

    // Offers `n` bytes as a frame: each byte held until taken; tx_valid low for `gap` clocks before the next frame.
    task offer(input integer n, input [7:0] seed);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                sent[i] = seed ^ (i * 8'h3B) ^ 8'h1D;
                tx_data = sent[i];
                tx_valid = 1'b1;
                @(negedge clk);
                while (!tx_ready) @(negedge clk);   // ready depends on valid: read it between edges
                @(posedge clk);
                #1;
            end
            tx_valid = 1'b0;
            tx_data = 8'hXX;
        end
    endtask

    task check_sent(input integer n, input [8*24-1:0] what);
        integer i;
        begin
            repeat (8) @(posedge clk);
            if (frames_out != 1) begin $display("FAIL: %0s: TX_EN fell %0d times", what, frames_out); errors = errors + 1; end
            if (out_dibits != 4 * n) begin
                $display("FAIL: %0s: %0d di-bits with TX_EN, expected %0d", what, out_dibits, 4 * n);
                errors = errors + 1;
            end else for (i = 0; i < n; i = i + 1)
                if (on_wire[i] !== sent[i]) begin
                    $display("FAIL: %0s: byte %0d went out as %h, expected %h", what, i, on_wire[i], sent[i]);
                    errors = errors + 1;
                end
            frames_out = 0;
            out_dibits = 0;
        end
    endtask

    integer k;
    initial begin
        for (k = 0; k < 256; k = k + 1) frame[k] = (k * 8'h47) ^ 8'hC3 ^ (k >> 3);   // no palindromes: 0xC3 → C3, 84, …
        frame[0] = 8'h1E;

        send(64, 0, 0, -1);
        check_received(64, 1'b0, "a plain frame");
        send(70, 2, 0, -1);
        check_received(70, 1'b0, "CRS_DV toggling");
        send(64, 0, 0, 20);
        check_received(64, 1'b1, "RX_ER");
        send(64, 0, 1, -1);
        check_received(64, 1'b1, "ending inside a byte");

        // A false carrier: CRS_DV with 10 di-bits, no SFD — nothing at all.
        for (k = 0; k < 20; k = k + 1) put_dibit(2'b10, 1'b1);
        put_dibit(2'b00, 1'b0);
        repeat (6) @(posedge clk);
        if (got_n != 0 || ends != 0) begin $display("FAIL: a false carrier gave %0d bytes and %0d ends", got_n, ends); errors = errors + 1; end
        got_n = 0;
        ends = 0;

        // A frame that comes straight after the last: the preamble starts two clocks after CRS_DV fell.
        send(64, 0, 0, -1);
        check_received(64, 1'b0, "the next frame");

        offer(1, 8'h00);
        check_sent(1, "one byte");
        repeat (3) @(posedge clk);
        offer(2, 8'h55);
        check_sent(2, "two bytes");
        offer(9, 8'hA7);
        check_sent(9, "nine bytes");
        if (tx_en !== 1'b0) begin $display("FAIL: TX_EN stays up"); errors = errors + 1; end

        if (errors == 0) $display("PASS");
        else $display("FAILED: %0d", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL: watchdog");
        $finish;
    end
endmodule
