// Self-checking testbench for ic74x153: both halves' data, the shared select and both strobes
// (4,096 cases), so a half reading the other's inputs or strobe fails too.

`timescale 1ns / 1ps

module ic74x153_tb;
    reg  [3:0] c1, c2;
    reg  [1:0] s;
    reg  g1_n, g2_n;
    wire y1, y2;

    ic74x153 dut (.A(s[0]), .B(s[1]),
                  .C1_0(c1[0]), .C1_1(c1[1]), .C1_2(c1[2]), .C1_3(c1[3]), .G1_n(g1_n), .Y1(y1),
                  .C2_0(c2[0]), .C2_1(c2[1]), .C2_2(c2[2]), .C2_3(c2[3]), .G2_n(g2_n), .Y2(y2));

    integer i, errors = 0;
    reg e1, e2;
    initial begin
        for (i = 0; i < 4096; i = i + 1) begin
            {g2_n, g1_n, s, c2, c1} = i[11:0];
            #1;
            e1 = !g1_n && c1[s];
            e2 = !g2_n && c2[s];
            if (y1 !== e1 || y2 !== e2) begin
                $display("FAIL: C1=%b C2=%b B A=%0d G1_n=%b G2_n=%b gave Y1=%b Y2=%b, expected %b %b", c1, c2, s, g1_n, g2_n, y1, y2, e1, e2);
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("PASS");
        $finish;
    end

    // A broken model must not hang the simulation.
    initial begin
        #1000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
