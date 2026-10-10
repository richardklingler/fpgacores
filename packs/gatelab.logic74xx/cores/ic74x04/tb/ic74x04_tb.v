// Self-checking testbench for ic74x04: all 64 combinations of the six inputs.

`timescale 1ns / 1ps

module ic74x04_tb;
    reg  [5:0] a;
    wire [5:0] y;

    ic74x04 dut (.A1(a[0]), .Y1(y[0]), .A2(a[1]), .Y2(y[1]), .A3(a[2]), .Y3(y[2]), .A4(a[3]), .Y4(y[3]), .A5(a[4]), .Y5(y[4]), .A6(a[5]), .Y6(y[5]));

    integer i, errors = 0;
    initial begin
        for (i = 0; i < 64; i = i + 1) begin
            a = i[5:0];
            #1;
            if (y !== ~a) begin
                $display("FAIL: a=%b gave y=%b, expected %b", a, y, ~a);
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
