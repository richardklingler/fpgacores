// Self-checking testbench for ic74x165: 120 rounds of a parallel load with a pseudo-random byte,
// then shifting it out with random serial data and CE_n (changed only while CP is high, as the
// datasheet asks), against a reference register; Q7 follows D7 while PL_n is low.

`timescale 1ns / 1ps

module ic74x165_tb;
    reg pl_n = 1, cp = 0, ce_n = 0, ds = 0;
    reg [7:0] d = 8'h00;
    wire q7, q7_n;

    ic74x165 dut (.PL_n(pl_n), .CP(cp), .CE_n(ce_n), .DS(ds),
                  .D0(d[0]), .D1(d[1]), .D2(d[2]), .D3(d[3]), .D4(d[4]), .D5(d[5]), .D6(d[6]), .D7(d[7]),
                  .Q7(q7), .Q7_n(q7_n));

    reg [7:0] expected = 8'h00;
    reg [15:0] lfsr = 16'h1D3B;
    integer round, k, errors = 0;

    task step;
        lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    endtask

    task check(input [255:0] what);
        if (q7 !== expected[7] || q7_n !== !expected[7]) begin
            $display("FAIL: %0s: Q7=%b Q7_n=%b, expected Q7=%b (register %b, t=%0t)", what, q7, q7_n, expected[7], expected, $time);
            errors = errors + 1;
        end
    endtask

    initial begin
        for (round = 0; round < 120; round = round + 1) begin
            // Parallel load: the bits come out D7 first.
            step; d = lfsr[7:0] ^ 8'h36;
            #2 pl_n = 0;
            expected = d;
            #1 check("while loading");
            d = d ^ 8'h80;                   // follows D7 while PL_n is low
            expected = d;
            #1 check("D7 while loading");
            #1 pl_n = 1;
            for (k = 0; k < 10; k = k + 1) begin
                step; ds = lfsr[2];
                #2 cp = 1;
                if (!ce_n) expected = {expected[6:0], ds};
                #1 check("after a clock");
                ce_n = lfsr[5] & lfsr[9];    // mostly enabled; changed while CP is high
                #2 cp = 0;
            end
            ce_n = 0;
        end
        if (errors == 0) $display("PASS");
        $finish;
    end

    // A broken model must not hang the simulation.
    initial begin
        #10000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
