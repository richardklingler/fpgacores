// 74x164: 8-bit serial-in, parallel-out shift register with asynchronous clear (74LS164, 74HC164 …).
// On each rising CP edge Q0 takes DSA AND DSB and every Qn takes Qn-1; MR_n low clears all outputs
// at once, whatever the clock does.
// Pins: DSA DSB Q0 Q1 Q2 Q3 = 1 … 6, CP MR_n Q4 Q5 Q6 Q7 = 8 … 13.

`timescale 1ns / 1ps

module ic74x164 (
    input  wire DSA,
    input  wire DSB,
    input  wire CP,
    input  wire MR_n,
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

    always @(posedge CP or negedge MR_n)
        if (!MR_n) q <= 8'h00;
        else q <= {q[6:0], DSA & DSB};

    assign {Q7, Q6, Q5, Q4, Q3, Q2, Q1, Q0} = q;
endmodule
