// Self-checking testbench for eth_mii_phy on a 100 MHz system clock, against a model of a PHY's MII side: rx_clk at
// 25 MHz and tx_clk at 24.97 MHz with another phase (the FIFOs really cross); received nibbles changed 10 ns after
// rx_clk rises. Receive: frames of 64 and 300 bytes (15 × 5, D, then the bytes low nibble first), one with RX_ER, one
// ending on a stray nibble, a false carrier (RX_DV without an SFD) — every byte must come out once, in order, then one
// rx_end with the right rx_error. Send: frames of 1, 12 and 200 bytes offered with valid/ready; tx_ready never on two
// clocks less than four apart, TX_EN up exactly for the frame's nibbles (low first), and two 80-byte frames offered back to
// back (the FIFO full at the first one's end) sent as two, at least 24 nibble clocks apart. A false carrier leaves RXD at
// D with RX_DV low: nothing may start. Prints PASS or every failed
// check.

`timescale 1ns / 1ps

module eth_mii_phy_tb;
    reg clk = 1'b0, rx_clk = 1'b0, tx_clk = 1'b0;
    always #5 clk = ~clk;
    always #20 rx_clk = ~rx_clk;
    initial begin #13; forever #20.024 tx_clk = ~tx_clk; end
    integer errors = 0;

    reg  [3:0] rxd = 4'd0;
    reg        rx_dv = 1'b0, rx_er = 1'b0;
    wire [3:0] txd;
    wire       tx_en;
    wire [7:0] rx_data;
    wire       rx_valid, rx_end, rx_error, tx_ready;
    reg  [7:0] tx_data = 8'd0;
    reg        tx_valid = 1'b0;
    eth_mii_phy dut (.clk(clk), .mii_rx_clk(rx_clk), .mii_rxd(rxd), .mii_rx_dv(rx_dv), .mii_rx_er(rx_er),
        .mii_tx_clk(tx_clk), .mii_txd(txd), .mii_tx_en(tx_en), .rx_data(rx_data), .rx_valid(rx_valid),
        .rx_end(rx_end), .rx_error(rx_error), .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready));

    // ---- Receive ----------------------------------------------------------------------------------------------
    reg [7:0] got [0:511];
    integer got_n = 0, ends = 0;
    reg last_error = 1'b0;
    always @(posedge clk) begin
        if (rx_valid) begin got[got_n] = rx_data; got_n = got_n + 1; end
        if (rx_end) begin ends = ends + 1; last_error = rx_error; end
    end

    reg [7:0] frame [0:511];
    task nibble(input [3:0] v, input dv);
        begin @(posedge rx_clk); #10; rxd = v; rx_dv = dv; end
    endtask
    // `odd`: a stray nibble after the bytes; `er_at`: RX_ER during that byte (-1 none).
    task send(input integer n, input odd, input integer er_at);
        integer i;
        begin
            for (i = 0; i < 15; i = i + 1) nibble(4'h5, 1'b1);
            nibble(4'hD, 1'b1);
            for (i = 0; i < n; i = i + 1) begin
                rx_er = (i == er_at);
                nibble(frame[i][3:0], 1'b1);
                nibble(frame[i][7:4], 1'b1);
            end
            rx_er = 1'b0;
            if (odd) nibble(4'hA, 1'b1);
            nibble(4'h0, 1'b0);
            repeat (20) @(posedge rx_clk);
        end
    endtask
    task check_received(input integer n, input expect_error, input [8*32-1:0] what);
        integer i, wrong;
        begin
            wrong = 0;
            if (got_n != n) begin $display("FAIL: %0s: %0d bytes, expected %0d", what, got_n, n); errors = errors + 1; end
            else for (i = 0; i < n; i = i + 1) if (got[i] !== frame[i]) wrong = wrong + 1;
            if (wrong != 0) begin $display("FAIL: %0s: %0d bytes wrong", what, wrong); errors = errors + 1; end
            if (ends != 1 || last_error !== expect_error) begin
                $display("FAIL: %0s: %0d ends, rx_error %b", what, ends, last_error);
                errors = errors + 1;
            end
            got_n = 0; ends = 0;
        end
    endtask

    // ---- Send -------------------------------------------------------------------------------------------------
    reg [7:0] wire_bytes [0:511];
    integer wire_n = 0, nibbles = 0, frames = 0, idle = 1000, min_gap = 1000;
    reg [7:0] cur = 8'd0;
    reg en_was = 1'b0;
    always @(posedge tx_clk) begin
        if (tx_en) begin
            if (!en_was && frames > 0 && idle < min_gap) min_gap = idle;
            cur = {txd, cur[7:4]};
            nibbles = nibbles + 1;
            if (nibbles % 2 == 0) begin wire_bytes[wire_n] = cur; wire_n = wire_n + 1; end
        end else begin
            if (en_was) frames = frames + 1;
            idle = en_was ? 1 : idle + 1;
        end
        en_was = tx_en;
    end

    // tx_ready's pace: never on two clocks less than four apart.
    integer since_ready = 100, fast_ready = 0;
    always @(posedge clk) begin
        if (tx_ready) begin
            if (since_ready < 3) fast_ready = fast_ready + 1;   // three clocks between: four apart
            since_ready = 0;
        end else since_ready = since_ready + 1;
    end

    reg [7:0] sent [0:511];
    task offer(input integer n, input [7:0] seed);
        integer i;
        begin
            @(posedge clk); #1;   // offer between edges, so no handshake happens before it's watched for
            for (i = 0; i < n; i = i + 1) begin
                sent[i] = (seed + i * 8'h3D) ^ (i >> 2);
                tx_data = sent[i];
                tx_valid = 1'b1;
                @(negedge clk);
                while (!tx_ready) @(negedge clk);
                @(posedge clk);
                #1;
            end
            tx_valid = 1'b0;
            tx_data = 8'hXX;
        end
    endtask
    task check_sent(input integer n, input [8*32-1:0] what);
        integer i, wrong, t;
        begin
            t = 0;
            while (frames == 0 && t < 20000) begin @(posedge tx_clk); t = t + 1; end
            wrong = 0;
            if (frames != 1 || wire_n != n) begin
                $display("FAIL: %0s: %0d frames, %0d bytes (expected %0d)", what, frames, wire_n, n);
                errors = errors + 1;
            end else for (i = 0; i < n; i = i + 1) if (wire_bytes[i] !== sent[i]) wrong = wrong + 1;
            if (wrong != 0) begin $display("FAIL: %0s: %0d bytes wrong", what, wrong); errors = errors + 1; end
            frames = 0; wire_n = 0; nibbles = 0;
        end
    endtask

    integer k, i;
    initial begin
        for (k = 0; k < 512; k = k + 1) frame[k] = (k * 8'h47) ^ 8'hC3 ^ (k >> 3);

        send(64, 1'b0, -1);  check_received(64, 1'b0, "64 bytes");
        send(300, 1'b0, -1); check_received(300, 1'b0, "300 bytes");
        send(64, 1'b0, 20);  check_received(64, 1'b1, "RX_ER");
        send(64, 1'b1, -1);  check_received(64, 1'b1, "a stray nibble");
        for (k = 0; k < 12; k = k + 1) nibble(4'h5, 1'b1);
        // RX_DV low again, and RXD left at D (a PHY's RXD means nothing without RX_DV): no frame may start.
        for (k = 0; k < 6; k = k + 1) nibble(4'hD, 1'b0);
        nibble(4'h0, 1'b0);
        repeat (20) @(posedge rx_clk);
        if (got_n != 0 || ends != 0) begin $display("FAIL: a false carrier gave %0d bytes, %0d ends", got_n, ends); errors = errors + 1; end
        got_n = 0; ends = 0;
        send(64, 1'b0, -1);  check_received(64, 1'b0, "after a false carrier");

        offer(1, 8'h11);   check_sent(1, "one byte");
        offer(12, 8'h5A);  check_sent(12, "12 bytes");
        offer(200, 8'hA7); check_sent(200, "200 bytes");
        // Two frames back to back: the second waits for the gap.
        min_gap = 1000;
        // 80 bytes each: the FIFO is full when the first one's end comes.
        offer(80, 8'h21);
        offer(80, 8'h42);
        k = 0;
        while (frames < 2 && k < 20000) begin @(posedge tx_clk); k = k + 1; end
        if (frames != 2) begin $display("FAIL: two frames back to back: %0d frames", frames); errors = errors + 1; end
        // Every byte of both (the second's are still in sent[]).
        k = 0;
        for (i = 0; i < 80; i = i + 1) if (wire_bytes[i] !== (((8'h21 + i * 8'h3D) ^ (i >> 2)) & 8'hFF)) k = k + 1;
        for (i = 0; i < 80; i = i + 1) if (wire_bytes[80 + i] !== sent[i]) k = k + 1;
        if (wire_n != 160 || k != 0) begin $display("FAIL: two frames back to back: %0d bytes, %0d wrong", wire_n, k); errors = errors + 1; end
        if (min_gap < 24) begin $display("FAIL: a gap of %0d nibble clocks", min_gap); errors = errors + 1; end
        if (fast_ready != 0) begin $display("FAIL: tx_ready %0d times less than four clocks apart", fast_ready); errors = errors + 1; end

        if (errors == 0) $display("PASS");
        else $display("FAILED: %0d", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("FAIL: watchdog");
        $finish;
    end
endmodule
