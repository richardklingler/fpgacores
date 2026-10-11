// Self-checking testbench for ic74x244: every input word with every pair of enables (1,024 cases);
// a disabled section floats, and the two sections don't share an enable.

`timescale 1ns / 1ps

module ic74x244_tb;
    reg  [3:0] a1, a2;
    reg  oe1_n, oe2_n;
    wire [3:0] y1, y2;

    ic74x244 dut (.A1_1(a1[0]), .A1_2(a1[1]), .A1_3(a1[2]), .A1_4(a1[3]), .OE1_n(oe1_n),
                  .Y1_1(y1[0]), .Y1_2(y1[1]), .Y1_3(y1[2]), .Y1_4(y1[3]),
                  .A2_1(a2[0]), .A2_2(a2[1]), .A2_3(a2[2]), .A2_4(a2[3]), .OE2_n(oe2_n),
                  .Y2_1(y2[0]), .Y2_2(y2[1]), .Y2_3(y2[2]), .Y2_4(y2[3]));

    integer i, errors = 0;
    reg [3:0] e1, e2;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            {oe2_n, oe1_n, a2, a1} = i[9:0];
            #1;
            e1 = oe1_n ? 4'bzzzz : a1;
            e2 = oe2_n ? 4'bzzzz : a2;
            if (y1 !== e1 || y2 !== e2) begin
                $display("FAIL: A1=%b A2=%b OE1_n=%b OE2_n=%b gave Y1=%b Y2=%b, expected %b %b", a1, a2, oe1_n, oe2_n, y1, y2, e1, e2);
                errors = errors + 1;
            end
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
