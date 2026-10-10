// 74x74: dual D flip-flop with asynchronous preset and clear, both active low (74LS74, 74HC74 …).
// With preset and clear low together both outputs are high, as on the real part.
// Pins: 1CLR 1D 1CLK 1PRE 1Q 1Q_n = 1 2 3 4 5 6, 2Q_n 2Q 2PRE 2CLK 2D 2CLR = 8 9 10 11 12 13.

`timescale 1ns / 1ps

module ic74x74 (
    input  wire D1,
    input  wire CLK1,
    input  wire PRE1_n,
    input  wire CLR1_n,
    output wire Q1,
    output wire Q1_n,
    input  wire D2,
    input  wire CLK2,
    input  wire PRE2_n,
    input  wire CLR2_n,
    output wire Q2,
    output wire Q2_n
);
    reg q1 = 1'b0;
    reg q2 = 1'b0;

    always @(posedge CLK1 or negedge PRE1_n or negedge CLR1_n)
        if (!CLR1_n) q1 <= 1'b0;
        else if (!PRE1_n) q1 <= 1'b1;
        else q1 <= D1;

    always @(posedge CLK2 or negedge PRE2_n or negedge CLR2_n)
        if (!CLR2_n) q2 <= 1'b0;
        else if (!PRE2_n) q2 <= 1'b1;
        else q2 <= D2;

    assign Q1   = q1 | (!PRE1_n && !CLR1_n);
    assign Q1_n = ~q1 | (!PRE1_n && !CLR1_n);
    assign Q2   = q2 | (!PRE2_n && !CLR2_n);
    assign Q2_n = ~q2 | (!PRE2_n && !CLR2_n);
endmodule
