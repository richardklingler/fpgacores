// 4017: decade counter with ten decoded outputs, CMOS (CD4017B, HEF4017B …). The count advances on
// the rising edge of CLK AND NOT INH (the clock inhibit — KiCad's CKEN — is a gated clock: a falling
// INH while CLK is high counts too). RST high clears to 0 at once. Exactly one of Q0–Q9 is high;
// COUT is high for counts 0–4 (one pulse per ten clocks). The real part is a Johnson counter; its
// outputs are the same.
// Pins: Q5 Q1 Q0 Q2 Q6 Q7 Q3 = 1 … 7, Q8 Q4 Q9 COUT INH CLK RST = 9 … 15.

`timescale 1ns / 1ps

module ic4017 (
    input  wire CLK,
    input  wire INH,
    input  wire RST,
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
    output wire COUT
);
    reg [3:0] count = 4'd0;
    wire clock = CLK & ~INH;

    always @(posedge clock or posedge RST)
        if (RST) count <= 4'd0;
        else count <= (count == 4'd9) ? 4'd0 : count + 4'd1;

    wire [9:0] q = 10'b1 << count;
    assign {Q9, Q8, Q7, Q6, Q5, Q4, Q3, Q2, Q1, Q0} = q;
    assign COUT = count < 4'd5;
endmodule
