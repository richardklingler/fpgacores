// Self-checking testbench for ic74x00: all 256 combinations of the four gates' inputs.

`timescale 1ns / 1ps

module ic74x00_tb;
    reg  [3:0] a, b;
    wire [3:0] y;

    ic74x00 dut (.A1(a[0]), .B1(b[0]), .Y1(y[0]), .A2(a[1]), .B2(b[1]), .Y2(y[1]), .A3(a[2]), .B3(b[2]), .Y3(y[2]), .A4(a[3]), .B4(b[3]), .Y4(y[3]));

    integer i, errors = 0;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            {a, b} = i[7:0];
            #1;
            if (y !== (~(a & b))) begin
                $display("FAIL: a=%b b=%b gave y=%b, expected %b", a, b, y, ~(a & b));
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
