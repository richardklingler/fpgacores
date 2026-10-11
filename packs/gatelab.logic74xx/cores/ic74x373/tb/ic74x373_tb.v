// Self-checking testbench for ic74x373: 400 steps of pseudo-random data, latch enable and output
// enable against a reference latch — transparent while LE is high, holding after it falls, and
// still latching while the outputs float.

`timescale 1ns / 1ps

module ic74x373_tb;
    reg  [7:0] d = 8'h00;
    reg  le = 0, oe_n = 0;
    wire [7:0] q;

    ic74x373 dut (.LE(le), .OE_n(oe_n), .D0(d[0]), .D1(d[1]), .D2(d[2]), .D3(d[3]), .D4(d[4]), .D5(d[5]), .D6(d[6]), .D7(d[7]), .Q0(q[0]), .Q1(q[1]), .Q2(q[2]), .Q3(q[3]), .Q4(q[4]), .Q5(q[5]), .Q6(q[6]), .Q7(q[7]));

    reg [7:0] held = 8'h00;
    reg [15:0] lfsr = 16'h7A31;
    integer i, errors = 0;

    task check(input [255:0] what);
        if (q !== (oe_n ? 8'bzzzzzzzz : held)) begin
            $display("FAIL: %0s: Q=%b, expected %b (LE=%b OE_n=%b, t=%0t)", what, q, oe_n ? 8'bzzzzzzzz : held, le, oe_n, $time);
            errors = errors + 1;
        end
    endtask

    initial begin
        // The latches power up undefined: open them once first.
        le = 1; d = 8'h00; held = 8'h00;
        #1 check("first open");
        for (i = 0; i < 400; i = i + 1) begin
            lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            oe_n = lfsr[9] & lfsr[3];
            le = lfsr[5];
            d = lfsr[15:8] ^ 8'hA6;
            if (le) held = d;
            #1 check("after D or LE");
            d = d ^ 8'h3B;                 // D moves on: followed while LE is high, ignored after
            if (le) held = d;
            #1 check("D changed");
            le = 0;
            #1 check("LE fell");
            d = d ^ 8'hC4;
            #1 check("held");
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
