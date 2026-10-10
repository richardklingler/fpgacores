// Self-checking testbench for ic74x138: all 64 combinations of address and enables.

`timescale 1ns / 1ps

module ic74x138_tb;
    reg  [2:0] a;
    reg  e1_n, e2_n, e3;
    wire [7:0] y_n;

    ic74x138 dut (.A0(a[0]), .A1(a[1]), .A2(a[2]), .E1_n(e1_n), .E2_n(e2_n), .E3(e3),
                  .Y0_n(y_n[0]), .Y1_n(y_n[1]), .Y2_n(y_n[2]), .Y3_n(y_n[3]),
                  .Y4_n(y_n[4]), .Y5_n(y_n[5]), .Y6_n(y_n[6]), .Y7_n(y_n[7]));

    integer i, errors = 0;
    reg [7:0] expected;
    initial begin
        for (i = 0; i < 64; i = i + 1) begin
            {e3, e2_n, e1_n, a} = i[5:0];
            #1;
            expected = (!e1_n && !e2_n && e3) ? ~(8'b1 << a) : 8'hFF;
            if (y_n !== expected) begin
                $display("FAIL: A=%0d E1_n=%b E2_n=%b E3=%b gave %b, expected %b", a, e1_n, e2_n, e3, y_n, expected);
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
