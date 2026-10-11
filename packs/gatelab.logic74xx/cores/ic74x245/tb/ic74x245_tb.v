// Self-checking testbench for ic74x245: every byte through A to B and back through B to A, both
// sides floating while disabled, and the receiving side never driven by the testbench.

`timescale 1ns / 1ps

module ic74x245_tb;
    reg  dir = 1, oe_n = 1;
    reg  [7:0] drive_a = 8'h00, drive_b = 8'h00;
    reg  a_on = 0, b_on = 0;
    wire [7:0] a = a_on ? drive_a : 8'bzzzzzzzz;
    wire [7:0] b = b_on ? drive_b : 8'bzzzzzzzz;

    ic74x245 dut (.DIR(dir), .OE_n(oe_n),
                  .A1(a[0]), .A2(a[1]), .A3(a[2]), .A4(a[3]), .A5(a[4]), .A6(a[5]), .A7(a[6]), .A8(a[7]),
                  .B1(b[0]), .B2(b[1]), .B3(b[2]), .B4(b[3]), .B5(b[4]), .B6(b[5]), .B7(b[6]), .B8(b[7]));

    integer i, errors = 0;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            // A to B.
            b_on = 0; dir = 1; oe_n = 0; drive_a = i[7:0]; a_on = 1;
            #1 if (b !== drive_a) begin $display("FAIL: A=%b to B gave %b", drive_a, b); errors = errors + 1; end
            // Disabled: B floats.
            oe_n = 1;
            #1 if (b !== 8'bzzzzzzzz) begin $display("FAIL: disabled, B=%b", b); errors = errors + 1; end
            // B to A (a different byte, so a stuck A would show).
            a_on = 0; dir = 0; drive_b = i[7:0] ^ 8'h5C; b_on = 1; oe_n = 0;
            #1 if (a !== drive_b) begin $display("FAIL: B=%b to A gave %b", drive_b, a); errors = errors + 1; end
            oe_n = 1;
            #1 if (a !== 8'bzzzzzzzz) begin $display("FAIL: disabled, A=%b", a); errors = errors + 1; end
            b_on = 0;
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
