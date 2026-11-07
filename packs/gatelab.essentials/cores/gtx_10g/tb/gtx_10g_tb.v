// Testbench for gtx_10g on its simulation stand-in: the reset sequence (MMCMs included), 64-bit blocks through the gearbox
// from one channel to the other (the fibre between two cages) and back on a near-end loopback, PRBS error counts per
// channel, a retry after a lost link (with PRBS only), rx_restart, the DFE hold, and reset. A "millisecond" is 200 cycles
// of the 50 MHz clock.
`timescale 1ns / 1ps

module gtx_10g_tb;
    reg clk = 1'b0;
    always #10 clk = ~clk;

    reg reset = 1'b0, prbs = 1'b0, near_loopback = 1'b0, lpm = 1'b0, prbs_clear = 1'b0;
    reg [1:0] rx_restart = 2'b00, rx_invert = 2'b00;
    wire qpll_lock, tx_ready, tx_clk;
    wire [1:0] rx_ready, rx_clk, rx_data_valid, rx_header_valid, txp, txn;
    wire [31:0] rx_retries;
    wire [63:0] prbs_errors;
    wire [127:0] rx_data;
    wire [3:0] rx_header;
    wire [5:0] tx_sequence;
    reg [127:0] tx_data = 128'd0;
    reg [3:0] tx_header = 4'd0;

    gtx_10g #(.CLK_HZ(50000000), .CHANNELS(2), .MS_CYCLES(200)) dut (
        .clk(clk), .reset(reset), .refclk_p(1'b0), .refclk_n(1'b1), .txp(txp), .txn(txn), .rxp(2'b00), .rxn(2'b11),
        .qpll_lock(qpll_lock), .tx_ready(tx_ready), .rx_ready(rx_ready), .rx_retries(rx_retries),
        .rx_restart(rx_restart), .prbs(prbs), .near_loopback(near_loopback), .lpm(lpm), .rx_invert(rx_invert),
        .prbs_errors(prbs_errors), .prbs_clear(prbs_clear),
        .tx_clk(tx_clk), .tx_sequence(tx_sequence), .tx_data(tx_data), .tx_header(tx_header),
        .rx_clk(rx_clk), .rx_data(rx_data), .rx_header(rx_header), .rx_data_valid(rx_data_valid),
        .rx_header_valid(rx_header_valid), .rx_slip(2'b00));

    integer failures = 0;
    task fail(input [8*100-1:0] what);
        begin $display("FAIL: %0s", what); failures = failures + 1; end
    endtask
    // Inputs change on the falling edge, away from the edge the core samples.
    task ms(input integer count);
        begin repeat (count * 200) @(posedge clk); @(negedge clk); end
    endtask
    task pulse_clear;
        begin @(negedge clk) prbs_clear = 1'b1; @(negedge clk) prbs_clear = 1'b0; end
    endtask

    // ---- What each channel sends: its number and a block counter (both halves), the header from the counter -----------
    // The counter steps on every data cycle (not at sequence 32).
    reg [23:0] word [0:1];
    initial begin word[0] = 24'd0; word[1] = 24'd0; end
    integer c;
    always @(posedge tx_clk) begin
        for (c = 0; c < 2; c = c + 1) begin
            if (tx_sequence != 6'd32) word[c] = word[c] + 24'd1;
            tx_data[64 * c +: 64] <= {8'hB0 + c[7:0], ~word[c], 8'hA0 + c[7:0], word[c]};
            tx_header[2 * c +: 2] <= word[c][1:0];
        end
    end

    // ---- What each receiver gets: the sender's number, a counter that steps by one, a header with every block ---------
    reg [7:0] expect_from [0:1];
    reg [23:0] last [0:1];
    reg seen [0:1];
    integer received [0:1];
    integer wrong [0:1];
    integer pauses [0:1];
    integer r;
    initial for (r = 0; r < 2; r = r + 1) begin
        expect_from[r] = 8'hA0 + (r ^ 1); seen[r] = 1'b0; received[r] = 0; wrong[r] = 0; pauses[r] = 0;
    end
    task watch(input integer n);
        reg [63:0] d;
        begin
            d = rx_data[64 * n +: 64];
            if (!rx_data_valid[n]) begin
                pauses[n] = pauses[n] + 1;
                if (rx_header_valid[n]) wrong[n] = wrong[n] + 1;     // a header in the pause
            end else begin
                if (d[31:24] != expect_from[n] || d[63:56] != expect_from[n] + 8'h10) wrong[n] = wrong[n] + 1;
                else if (d[55:32] != ~d[23:0]) wrong[n] = wrong[n] + 1;   // both halves of one block
                else if (seen[n] && d[23:0] != last[n] + 24'd1) wrong[n] = wrong[n] + 1;
                if (!rx_header_valid[n] || rx_header[2 * n +: 2] != d[1:0]) wrong[n] = wrong[n] + 1;
                last[n] = d[23:0];
                seen[n] = 1'b1;
                received[n] = received[n] + 1;
            end
        end
    endtask
    always @(posedge rx_clk[0]) if (rx_ready[0]) watch(0);
    always @(posedge rx_clk[1]) if (rx_ready[1]) watch(1);
    task restart_count;
        integer i;
        begin for (i = 0; i < 2; i = i + 1) begin seen[i] = 1'b0; received[i] = 0; wrong[i] = 0; pauses[i] = 0; end end
    endtask

    initial begin
        $dumpfile("gtx_10g_tb.vcd");
        $dumpvars(1, gtx_10g_tb);

        // ---- Up: QPLL, the transmit MMCM, TX, then both receivers and their MMCMs ---------------------------------------
        ms(12);
        if (!qpll_lock || !tx_ready) fail("QPLL lock and TX ready after the reset sequence");
        if (rx_ready !== 2'b11) fail("both receivers ready");
        if (rx_retries !== 32'd0) fail("no retries on a clean start");

        // ---- Words over the fibre: 0 -> 1 and 1 -> 0 -------------------------------------------------------------
        restart_count;
        ms(2);
        if (received[0] < 500 || received[1] < 500) fail("blocks arrive on both receivers");
        if (wrong[0] != 0 || wrong[1] != 0) fail("the partner's blocks, in order, a header with each");
        if (pauses[0] == 0 || pauses[0] * 31 > received[0] || pauses[0] * 34 < received[0]) fail("one pause in 33 cycles");

        // ---- Near-end loopback: each receiver gets its own words again, after a restart ---------------------------
        near_loopback = 1'b1;
        expect_from[0] = 8'hA0; expect_from[1] = 8'hA1;
        @(posedge clk); @(posedge clk); @(posedge clk); @(posedge clk);
        if (rx_ready !== 2'b00) fail("a loopback change restarts the receivers");
        ms(6);
        restart_count;
        ms(1);
        if (rx_ready !== 2'b11 || received[0] < 250 || wrong[0] != 0 || wrong[1] != 0) fail("near-end loopback: own blocks");
        near_loopback = 1'b0;
        expect_from[0] = 8'hA1; expect_from[1] = 8'hA0;
        ms(6);
        restart_count;

        // ---- PRBS: error words per channel, no retry for a short burst, cleared on request -------------------------
        prbs = 1'b1;
        ms(2);
        dut.g_ch[1].sim_errors = 1234;
        ms(3);
        if (prbs_errors[63:32] != 32'd1234) fail("1234 error words counted on channel 1");
        if (prbs_errors[31:0] != 32'd0) fail("no error words on channel 0");
        if (rx_retries !== 32'd0) fail("a short burst made a retry");
        pulse_clear;
        ms(2);
        if (prbs_errors !== 64'd0) fail("prbs_clear clears the counts");

        // ---- DFE: held after four good milliseconds (channel 1's burst reset its count); LPM never holds --------------
        ms(4);
        if (dut.dfe_hold !== 2'b11) fail("the DFE is held after good milliseconds");
        lpm = 1'b1;
        ms(10);
        if (dut.dfe_hold !== 2'b00) fail("LPM doesn't hold the DFE");
        if (rx_ready !== 2'b11) fail("receivers back after the equaliser change");
        lpm = 1'b0;
        ms(10);

        // ---- A lost link with PRBS: a retry after RETRY_MS bad milliseconds, then recovery; channel 1 untouched -----
        dut.g_ch[0].sim_no_link = 1'b1;
        ms(150);
        dut.g_ch[0].sim_no_link = 1'b0;
        ms(12);
        if (rx_retries[15:0] == 16'd0) fail("no retry after 100 bad milliseconds");
        if (!rx_ready[0]) fail("channel 0 recovers after the link comes back");
        if (rx_retries[31:16] != 16'd0) fail("channel 1 was touched by channel 0's lost link");

        // ---- Without PRBS a lost link isn't the transceiver's business (a PCS asks with rx_restart) ----------------
        prbs = 1'b0;
        ms(2);
        dut.g_ch[1].sim_no_link = 1'b1;
        ms(150);
        if (rx_retries[31:16] != 16'd0 || !rx_ready[1]) fail("data mode: no retries of its own");
        dut.g_ch[1].sim_no_link = 1'b0;
        @(negedge clk) rx_restart = 2'b10; @(negedge clk) rx_restart = 2'b00;
        @(posedge clk); @(posedge clk); @(posedge clk);
        if (rx_ready[1] || !rx_ready[0]) fail("rx_restart resets that receiver alone");
        ms(6);
        if (!rx_ready[1]) fail("the receiver is back after rx_restart");

        // ---- A receive MMCM that loses lock (the recovered clock went): that receiver starts again --------------------
        force dut.g_ch[0].rx_mmcm_r = 1'b0;
        repeat (10) @(posedge clk);
        release dut.g_ch[0].rx_mmcm_r;
        @(negedge clk);
        if (rx_ready[0]) fail("a receive MMCM out of lock leaves the receiver ready");
        ms(6);
        if (!rx_ready[0] || rx_retries[15:0] < 2) fail("the receiver isn't back (and counted) after its MMCM lost lock");

        // ---- reset: the whole sequence again -------------------------------------------------------------------------
        @(negedge clk) reset = 1'b1; @(negedge clk) reset = 1'b0;
        repeat (6) @(posedge clk);                     // QPLLRESET, then two synchroniser clocks
        if (tx_ready || qpll_lock) fail("reset drops TX ready and the QPLL lock");
        ms(12);
        if (!tx_ready || rx_ready !== 2'b11) fail("up again after reset");

        if (failures == 0) $display("PASS: gtx_10g reset sequence, MMCMs, gearbox blocks, loopback, PRBS counts, retry, DFE hold");
        else $display("FAIL: %0d check(s)", failures);
        $finish;
    end
    initial begin #40000000; $display("FAIL: timeout"); $finish; end
endmodule
