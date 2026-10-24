// Self-checking testbench for tmds_encoder: 4000 cycles of pseudo-random bytes in bursts of
// active video (with 0x00, 0xFF and 0x10 runs, which lean hardest on the DC balance) and blanking
// with every control word. Each output word is compared with a reference written from the DVI 1.0
// algorithm (integer counts, 3.3.1), decoded back to the byte, and the running disparity of
// the sent words is checked to stay small.

`timescale 1ns / 1ps

module tmds_encoder_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg de = 1'b0;
    reg [7:0] d = 8'd0;
    reg c0 = 1'b0, c1 = 1'b0;
    wire [9:0] q;

    tmds_encoder dut (.clk(clk), .de(de), .d(d), .c0(c0), .c1(c1), .q(q));

    // The reference: the specification's encoder.
    integer cnt = 0;

    function integer ones8;
        input [7:0] v;
        integer k;
        begin
            ones8 = 0;
            for (k = 0; k < 8; k = k + 1) ones8 = ones8 + v[k];
        end
    endfunction

    task reference;
        input in_de;
        input [7:0] in_d;
        input in_c0, in_c1;
        output [9:0] word;
        reg [8:0] qm;
        integer k, n1, n0;
        begin
            if (!in_de) begin
                cnt = 0;
                case ({in_c1, in_c0})
                    2'b00: word = 10'b1101010100;
                    2'b01: word = 10'b0010101011;
                    2'b10: word = 10'b0101010100;
                    default: word = 10'b1010101011;
                endcase
            end else begin
                qm[0] = in_d[0];
                if (ones8(in_d) > 4 || (ones8(in_d) == 4 && in_d[0] == 1'b0)) begin
                    for (k = 1; k < 8; k = k + 1) qm[k] = ~(qm[k - 1] ^ in_d[k]);
                    qm[8] = 1'b0;
                end else begin
                    for (k = 1; k < 8; k = k + 1) qm[k] = qm[k - 1] ^ in_d[k];
                    qm[8] = 1'b1;
                end
                n1 = ones8(qm[7:0]);
                n0 = 8 - n1;
                if (cnt == 0 || n1 == n0) begin
                    word = {~qm[8], qm[8], qm[8] ? qm[7:0] : ~qm[7:0]};
                    cnt = qm[8] ? cnt + (n1 - n0) : cnt + (n0 - n1);
                end else if ((cnt > 0 && n1 > n0) || (cnt < 0 && n0 > n1)) begin
                    word = {1'b1, qm[8], ~qm[7:0]};
                    cnt = cnt + 2 * qm[8] + (n0 - n1);
                end else begin
                    word = {1'b0, qm[8], qm[7:0]};
                    cnt = cnt - 2 * (1 - qm[8]) + (n1 - n0);
                end
            end
        end
    endtask

    // A receiver's decoder for a data word.
    function [7:0] decode;
        input [9:0] word;
        reg [7:0] v;
        integer k;
        begin
            v = word[9] ? ~word[7:0] : word[7:0];
            decode[0] = v[0];
            for (k = 1; k < 8; k = k + 1) decode[k] = word[8] ? (v[k] ^ v[k - 1]) : ~(v[k] ^ v[k - 1]);
        end
    endfunction

    // The encoder's latency; the expected words wait in a short history.
    localparam LATENCY = 3;
    reg [9:0] expected_q [0:LATENCY-1];
    reg [7:0] sent_d [0:LATENCY-1];
    reg sent_de [0:LATENCY-1];
    integer errors = 0, cycle, balance = 0, worst = 0, words = 0, k;
    reg [9:0] expected;
    reg [15:0] lfsr = 16'hACE1;

    initial begin
        $dumpfile("tmds_encoder_tb.vcd");
        $dumpvars(0, tmds_encoder_tb);
        for (cycle = 0; cycle < 4000; cycle = cycle + 1) begin
            // Inputs for this clock: bursts of active video, blanking with each control word.
            lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            de = (cycle % 97) < 71;
            {c1, c0} = cycle[5:4];
            if (cycle >= 300 && cycle < 360) d = 8'h00;
            else if (cycle >= 400 && cycle < 460) d = 8'hFF;
            else if (cycle >= 500 && cycle < 560) d = 8'h10;
            else d = lfsr[7:0];
            reference(de, d, c0, c1, expected);
            for (k = LATENCY - 1; k > 0; k = k - 1) begin
                expected_q[k] = expected_q[k - 1]; sent_d[k] = sent_d[k - 1]; sent_de[k] = sent_de[k - 1];
            end
            expected_q[0] = expected; sent_d[0] = d; sent_de[0] = de;
            @(posedge clk);
            #1;
            // q now holds the word for the inputs LATENCY - 1 edges before this one.
            if (cycle >= LATENCY - 1) begin
                if (q !== expected_q[LATENCY - 1]) begin
                    $display("FAIL: cycle %0d: word %b, expected %b (de %b, d %h)", cycle, q, expected_q[LATENCY - 1], sent_de[LATENCY - 1], sent_d[LATENCY - 1]);
                    errors = errors + 1;
                end
                if (sent_de[LATENCY - 1]) begin
                    if (decode(q) !== sent_d[LATENCY - 1]) begin
                        $display("FAIL: cycle %0d: %b decodes to %h, sent %h", cycle, q, decode(q), sent_d[LATENCY - 1]);
                        errors = errors + 1;
                    end
                    for (k = 0; k < 10; k = k + 1) balance = balance + (q[k] ? 1 : -1);
                    if (balance > worst) worst = balance;
                    if (-balance > worst) worst = -balance;
                    words = words + 1;
                end else begin
                    balance = 0;
                end
            end
            if (errors > 5) cycle = 4000;
        end
        // DVI keeps the running disparity bounded; without DC balance a run of 0x10 drifts far.
        if (worst > 24) begin $display("FAIL: running disparity reached %0d bits", worst); errors = errors + 1; end
        if (words < 2500) begin $display("FAIL: only %0d data words", words); errors = errors + 1; end
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
