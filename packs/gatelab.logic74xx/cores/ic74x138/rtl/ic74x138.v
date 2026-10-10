// 74x138: 3-to-8 line decoder, outputs active low (74LS138, 74HC138 …). Zero-delay model.
// Pins: A0 A1 A2 = 1 2 3, E1_n E2_n E3 = 4 5 6, Y7_n = 7, Y6_n … Y0_n = 9 … 15.

`timescale 1ns / 1ps

module ic74x138 (
    input  wire A0,
    input  wire A1,
    input  wire A2,
    input  wire E1_n,
    input  wire E2_n,
    input  wire E3,
    output wire Y0_n,
    output wire Y1_n,
    output wire Y2_n,
    output wire Y3_n,
    output wire Y4_n,
    output wire Y5_n,
    output wire Y6_n,
    output wire Y7_n
);
    wire enabled = !E1_n && !E2_n && E3;
    wire [7:0] selected = enabled ? (8'b1 << {A2, A1, A0}) : 8'b0;
    assign {Y7_n, Y6_n, Y5_n, Y4_n, Y3_n, Y2_n, Y1_n, Y0_n} = ~selected;
endmodule
