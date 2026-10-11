// Self-checking testbench for ic74x374: 400 clocks of pseudo-random data and output enable against
// a reference register — D taken only on the rising edge, and still taken while the outputs float.

`timescale 1ns / 1ps

module ic74x374_tb;
    reg  [7:0] d = 8'h00;
    reg  cp = 0, oe_n = 0;
    wire [7:0] q;

    ic74x374 dut (.CP(cp), .OE_n(oe_n), .D0(d[0]), .D1(d[1]), .D2(d[2]), .D3(d[3]), .D4(d[4]), .D5(d[5]), .D6(d[6]), .D7(d[7]), .Q0(q[0]), .Q1(q[1]), .Q2(q[2]), .Q3(q[3]), .Q4(q[4]), .Q5(q[5]), .Q6(q[6]), .Q7(q[7]));

    reg [7:0] stored = 8'h00;
    reg [15:0] lfsr = 16'h2C9D;
    integer i, errors = 0;

    task check(input [255:0] what);
        if (q !== (oe_n ? 8'bzzzzzzzz : stored)) begin
            $display("FAIL: %0s: Q=%b, expected %b (OE_n=%b, t=%0t)", what, q, oe_n ? 8'bzzzzzzzz : stored, oe_n, $time);
            errors = errors + 1;
        end
    endtask

    initial begin
        for (i = 0; i < 400; i = i + 1) begin
            lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            oe_n = lfsr[9] & lfsr[3];
            d = lfsr[15:8] ^ 8'h93;
            #1 check("D before the edge");  // not taken yet
            #2 cp = 1;
            stored = d;
            #1 check("after the edge");
            d = d ^ 8'h5E;                  // changes while CP is high: not taken
            #1 check("D while high");
            #2 cp = 0;
            #1 check("falling edge");
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
