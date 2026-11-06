// Self-checking testbench for eth_rgmii_phy (its behavioural model; the board run checks IDDR/ODDR/BUFIO/BUFR): a PHY's
// RGMII side with rx_clk at 125 MHz and the system clock at 124.99 MHz with another phase (the FIFO really crosses).
// RX_LATE 0: each nibble centred on the edge that takes it, the low one on the rising edge; RX_LATE 1: half a clock
// later (the low nibble on a falling edge). Receive: frames of 64 and 1500 bytes, two of them with only the gap and
// the preamble between, one with RX_ER, garbage that never sends D5 — every byte out once, in order, then one rx_end with
// the right rx_error. Send: frames of 60 and 1514 bytes offered a byte a clock (tx_ready never low), decoded on
// TX_CLK's halves: TX_CTL high exactly for the frame, every byte right. Prints PASS or every failed check.

`timescale 1ns / 1ps

module eth_rgmii_phy_tb;
    parameter RX_LATE = 1;
    reg clk = 1'b0, rx_clk = 1'b0;
    initial begin #1.3; forever #4.0002 clk = ~clk; end    // 124.99 MHz
    always #4 rx_clk = ~rx_clk;                           // 125 MHz
    integer errors = 0;

    reg  [3:0] rxd = 4'd0;
    reg        rx_ctl = 1'b0;
    wire       tx_clk, tx_ctl;
    wire [3:0] txd;
    wire [7:0] rx_data;
    wire       rx_valid, rx_end, rx_error, tx_ready;
    reg  [7:0] tx_data = 8'd0;
    reg        tx_valid = 1'b0;
    eth_rgmii_phy #(.RX_LATE(RX_LATE)) dut (.clk(clk), .rgmii_rx_clk(rx_clk), .rgmii_rxd(rxd), .rgmii_rx_ctl(rx_ctl),
        .rgmii_tx_clk(tx_clk), .rgmii_txd(txd), .rgmii_tx_ctl(tx_ctl), .rx_data(rx_data), .rx_valid(rx_valid),
        .rx_end(rx_end), .rx_error(rx_error), .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready));

    // ---- Receive ----------------------------------------------------------------------------------------------
    reg [7:0] got [0:4095];
    integer got_n = 0, ends = 0;
    reg last_error = 1'b0;
    always @(posedge clk) begin
        if (rx_valid) begin got[got_n] = rx_data; got_n = got_n + 1; end
        if (rx_end) begin ends = ends + 1; last_error = rx_error; end
    end

    reg [7:0] frame [0:4095];
    // A nibble and its RX_CTL value, set 2 ns after the opposite edge so it's centred on the edge that takes it.
    task half(input low_half, input [3:0] v, input c);
        begin
            if (low_half ^ RX_LATE) @(negedge rx_clk); else @(posedge rx_clk);
            #2 rxd = v; rx_ctl = c;
        end
    endtask
    // One byte: the low nibble with DV, the high one with DV ^ ER.
    task byte_out(input [7:0] b, input dv, input er);
        begin half(1'b1, b[3:0], dv); half(1'b0, b[7:4], dv ^ er); end
    endtask
    // A frame: 7 × 55, D5, n bytes from frame[] (ER during byte er_at, -1 none), then `gap` idle bytes.
    task send(input integer n, input integer er_at, input integer gap);
        integer i;
        begin
            for (i = 0; i < 7; i = i + 1) byte_out(8'h55, 1'b1, 1'b0);
            byte_out(8'hD5, 1'b1, 1'b0);
            for (i = 0; i < n; i = i + 1) byte_out(frame[i], 1'b1, i == er_at);
            for (i = 0; i < gap; i = i + 1) byte_out(8'h00, 1'b0, 1'b0);
        end
    endtask
    task check_received(input integer n, input integer frames, input expect_error, input [8*32-1:0] what);
        integer i, wrong, f;
        begin
            repeat (60) @(posedge clk);
            wrong = 0;
            if (got_n != n * frames) begin $display("FAIL: %0s: %0d bytes, expected %0d", what, got_n, n * frames); errors = errors + 1; end
            else for (f = 0; f < frames; f = f + 1) for (i = 0; i < n; i = i + 1) if (got[f * n + i] !== frame[i]) wrong = wrong + 1;
            if (wrong != 0) begin $display("FAIL: %0s: %0d bytes wrong", what, wrong); errors = errors + 1; end
            if (ends != frames || last_error !== expect_error) begin
                $display("FAIL: %0s: %0d ends, rx_error %b", what, ends, last_error);
                errors = errors + 1;
            end
            got_n = 0; ends = 0;
        end
    endtask

    // ---- Send: decoded on TX_CLK's halves ---------------------------------------------------------------------
    reg [7:0] wire_bytes [0:4095];
    integer wire_n = 0, frames_out = 0;
    reg [3:0] low;
    reg low_ctl, en_was = 1'b0;
    always @(posedge tx_clk) begin
        #1 low = txd; low_ctl = tx_ctl;
        @(negedge tx_clk); #1;
        if (low_ctl !== tx_ctl) begin $display("FAIL: TX_CTL differs between the halves"); errors = errors + 1; end
        if (low_ctl) begin wire_bytes[wire_n] = {txd, low}; wire_n = wire_n + 1; end
        else if (en_was) frames_out = frames_out + 1;
        en_was = low_ctl;
    end
    reg [7:0] sent [0:4095];
    integer not_ready = 0;
    task offer(input integer n, input [7:0] seed);
        integer i;
        begin
            @(posedge clk); #1;
            for (i = 0; i < n; i = i + 1) begin
                sent[i] = (seed + i * 8'h3D) ^ (i >> 3);
                tx_data = sent[i]; tx_valid = 1'b1;
                @(posedge clk); #1;
                if (!tx_ready) not_ready = not_ready + 1;
            end
            tx_valid = 1'b0;
            repeat (20) @(posedge clk);
        end
    endtask
    task check_sent(input integer n, input [8*32-1:0] what);
        integer i, wrong;
        begin
            wrong = 0;
            if (frames_out != 1 || wire_n != n) begin
                $display("FAIL: %0s: %0d frames, %0d bytes (expected %0d)", what, frames_out, wire_n, n); errors = errors + 1;
            end else for (i = 0; i < n; i = i + 1) if (wire_bytes[i] !== sent[i]) wrong = wrong + 1;
            if (wrong != 0) begin $display("FAIL: %0s: %0d bytes wrong", what, wrong); errors = errors + 1; end
            frames_out = 0; wire_n = 0;
        end
    endtask

    integer k;
    initial begin
        for (k = 0; k < 4096; k = k + 1) frame[k] = (k * 8'h47) ^ 8'hC3 ^ (k >> 5);
        repeat (10) @(posedge rx_clk);
        send(64, -1, 12);    check_received(64, 1, 1'b0, "64 bytes");
        send(1500, -1, 12);  check_received(1500, 1, 1'b0, "1500 bytes");
        send(64, 20, 12);    check_received(64, 1, 1'b1, "RX_ER");
        send(1500, -1, 12);  send(1500, -1, 12); check_received(1500, 2, 1'b0, "two back to back");
        // A carrier that never sends D5: nothing comes out.
        for (k = 0; k < 20; k = k + 1) byte_out(8'h55, 1'b1, 1'b0);
        for (k = 0; k < 8; k = k + 1) byte_out(8'h3C, 1'b1, 1'b0);
        for (k = 0; k < 12; k = k + 1) byte_out(8'h00, 1'b0, 1'b0);
        repeat (60) @(posedge clk);
        if (got_n != 0 || ends != 0) begin $display("FAIL: no SFD gave %0d bytes, %0d ends", got_n, ends); errors = errors + 1; end
        got_n = 0; ends = 0;
        send(64, -1, 12);    check_received(64, 1, 1'b0, "after no SFD");

        offer(60, 8'h11);    check_sent(60, "60 bytes");
        offer(1514, 8'hA7);  check_sent(1514, "1514 bytes");
        if (not_ready != 0) begin $display("FAIL: tx_ready low %0d times", not_ready); errors = errors + 1; end

        if (errors == 0) $display("PASS");
        else $display("FAILED: %0d", errors);
        $finish;
    end
    initial begin #3_000_000; $display("FAIL: watchdog"); $finish; end
endmodule
