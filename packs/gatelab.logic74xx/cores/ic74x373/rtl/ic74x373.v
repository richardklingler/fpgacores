// 74x373: octal transparent latch with three-state outputs (74LS373, 74HC373 …). While LE is high
// the latches follow D; when LE falls they hold. The outputs show the latches while OE_n is low
// and float otherwise (the latches keep working).
// Pins: OE_n Q0 D0 D1 Q1 Q2 D2 D3 Q3 = 1 … 9, LE Q4 D4 D5 Q5 Q6 D6 D7 Q7 = 11 … 19.

`timescale 1ns / 1ps

module ic74x373 (
    input  wire D0,
    input  wire D1,
    input  wire D2,
    input  wire D3,
    input  wire D4,
    input  wire D5,
    input  wire D6,
    input  wire D7,
    input  wire LE,
    input  wire OE_n,
    output wire Q0,
    output wire Q1,
    output wire Q2,
    output wire Q3,
    output wire Q4,
    output wire Q5,
    output wire Q6,
    output wire Q7
);
    // No start value: the real part powers up undefined (and Gowin refuses initialised latches).
    reg [7:0] q;
    always @*
        if (LE) q = {D7, D6, D5, D4, D3, D2, D1, D0};

    assign {Q7, Q6, Q5, Q4, Q3, Q2, Q1, Q0} = OE_n ? 8'bzzzzzzzz : q;
endmodule
