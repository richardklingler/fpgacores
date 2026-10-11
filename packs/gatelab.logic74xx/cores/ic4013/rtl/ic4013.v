// 4013: dual D flip-flop with set and reset, CMOS (CD4013B, HEF4013B …). Rising CLK takes D. Set
// and reset are asynchronous and active HIGH (unlike the 74x74); with both high, Q and Q_n are both
// high, as on the real part.
// Pins: Q1 Q1_n CLK1 R1 D1 S1 = 1 … 6, S2 D2 R2 CLK2 Q2_n Q2 = 8 … 13.

`timescale 1ns / 1ps

module ic4013 (
    input  wire D1,
    input  wire CLK1,
    input  wire S1,
    input  wire R1,
    output wire Q1,
    output wire Q1_n,
    input  wire D2,
    input  wire CLK2,
    input  wire S2,
    input  wire R2,
    output wire Q2,
    output wire Q2_n
);
    reg q1 = 1'b0;
    reg q2 = 1'b0;

    always @(posedge CLK1 or posedge S1 or posedge R1)
        if (R1) q1 <= 1'b0;
        else if (S1) q1 <= 1'b1;
        else q1 <= D1;

    always @(posedge CLK2 or posedge S2 or posedge R2)
        if (R2) q2 <= 1'b0;
        else if (S2) q2 <= 1'b1;
        else q2 <= D2;

    assign Q1   = q1 | (S1 && R1);
    assign Q1_n = ~q1 | (S1 && R1);
    assign Q2   = q2 | (S2 && R2);
    assign Q2_n = ~q2 | (S2 && R2);
endmodule
