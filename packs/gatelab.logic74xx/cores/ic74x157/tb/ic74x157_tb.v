// Self-checking testbench for ic74x157: all four sections' inputs, select and strobe (1,024 cases).

`timescale 1ns / 1ps

module ic74x157_tb;
    reg  [3:0] a, b;
    reg  s, g_n;
    wire [3:0] y;

    ic74x157 dut (.S(s), .G_n(g_n),
                  .A1(a[0]), .B1(b[0]), .Y1(y[0]), .A2(a[1]), .B2(b[1]), .Y2(y[1]),
                  .A3(a[2]), .B3(b[2]), .Y3(y[2]), .A4(a[3]), .B4(b[3]), .Y4(y[3]));

    integer i, errors = 0;
    reg [3:0] expected;
    initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            {g_n, s, b, a} = i[9:0];
            #1;
            expected = g_n ? 4'b0000 : (s ? b : a);
            if (y !== expected) begin
                $display("FAIL: A=%b B=%b S=%b G_n=%b gave Y=%b, expected %b", a, b, s, g_n, y, expected);
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
