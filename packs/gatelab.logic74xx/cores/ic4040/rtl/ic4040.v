// 4040: 12-stage binary ripple counter, CMOS (CD4040B, HEF4040B …). The count advances on each
// FALLING edge of CP; MR high clears it at once. The real part ripples (each stage clocks the next,
// so the outputs settle one after another); the model changes them together.
// Pins: Q11 Q5 Q4 Q6 Q3 Q2 Q1 = 1 … 7, Q0 CP MR Q8 Q7 Q9 Q10 = 9 … 15.

`timescale 1ns / 1ps

module ic4040 (
    input  wire CP,
    input  wire MR,
    output wire Q0,
    output wire Q1,
    output wire Q2,
    output wire Q3,
    output wire Q4,
    output wire Q5,
    output wire Q6,
    output wire Q7,
    output wire Q8,
    output wire Q9,
    output wire Q10,
    output wire Q11
);
    reg [11:0] count = 12'd0;

    always @(negedge CP or posedge MR)
        if (MR) count <= 12'd0;
        else count <= count + 12'd1;

    assign {Q11, Q10, Q9, Q8, Q7, Q6, Q5, Q4, Q3, Q2, Q1, Q0} = count;
endmodule
