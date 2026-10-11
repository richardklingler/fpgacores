// Self-checking testbench for ic74x151: every data word, select and strobe (4,096 cases).

`timescale 1ns / 1ps

module ic74x151_tb;
    reg  [7:0] d;
    reg  [2:0] s;
    reg  g_n;
    wire y, y_n;

    ic74x151 dut (.D0(d[0]), .D1(d[1]), .D2(d[2]), .D3(d[3]), .D4(d[4]), .D5(d[5]), .D6(d[6]), .D7(d[7]),
                  .A(s[0]), .B(s[1]), .C(s[2]), .G_n(g_n), .Y(y), .Y_n(y_n));

    integer i, errors = 0;
    reg expected;
    initial begin
        for (i = 0; i < 4096; i = i + 1) begin
            {g_n, s, d} = i[11:0];
            #1;
            expected = !g_n && d[s];
            if (y !== expected || y_n !== !expected) begin
                $display("FAIL: D=%b C B A=%0d G_n=%b gave Y=%b Y_n=%b, expected Y=%b", d, s, g_n, y, y_n, expected);
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
