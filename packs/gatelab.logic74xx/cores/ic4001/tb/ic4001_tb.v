// Self-checking testbench for ic4001: every input combination of all four gates (256 cases), so a
// gate wired to its neighbour's inputs fails too.

`timescale 1ns / 1ps

module ic4001_tb;
    reg  [3:0] a, b;
    wire [3:0] y;

    ic4001 dut (.A1(a[0]), .B1(b[0]), .Y1(y[0]), .A2(a[1]), .B2(b[1]), .Y2(y[1]), .A3(a[2]), .B3(b[2]), .Y3(y[2]), .A4(a[3]), .B4(b[3]), .Y4(y[3]));

    integer i, errors = 0;
    reg [3:0] expected;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            {b, a} = i[7:0];
            #1;
            expected = ~(a | b);
            if (y !== expected) begin
                $display("FAIL: A=%b B=%b gave Y=%b, expected %b", a, b, y, expected);
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
