// 74x374: octal D flip-flop with three-state outputs (74LS374, 74HC374 …). On each rising CP edge
// the flip-flops take D. The outputs show them while OE_n is low and float otherwise (the
// flip-flops keep clocking).
// Pins: OE_n Q0 D0 D1 Q1 Q2 D2 D3 Q3 = 1 … 9, CP Q4 D4 D5 Q5 Q6 D6 D7 Q7 = 11 … 19.

`timescale 1ns / 1ps

module ic74x374 (
    input  wire D0,
    input  wire D1,
    input  wire D2,
    input  wire D3,
    input  wire D4,
    input  wire D5,
    input  wire D6,
    input  wire D7,
    input  wire CP,
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
    reg [7:0] q = 8'h00;
    always @(posedge CP)
        q <= {D7, D6, D5, D4, D3, D2, D1, D0};

    assign {Q7, Q6, Q5, Q4, Q3, Q2, Q1, Q0} = OE_n ? 8'bzzzzzzzz : q;
endmodule
