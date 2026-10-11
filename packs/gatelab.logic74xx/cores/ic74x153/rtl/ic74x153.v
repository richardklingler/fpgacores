// 74x153: dual 4-to-1 data selector/multiplexer, shared select, separate strobes (74LS153,
// 74HC153 …). Each Y is the input C{B A} of its half while its strobe is low, else low.
// Ports: datasheet 1C0 = C1_0 (half 1, input 0) …, 1G = G1_n, 1Y = Y1.
// Pins: G1_n B C1_3 C1_2 C1_1 C1_0 Y1 = 1 2 3 4 5 6 7, Y2 C2_0 C2_1 C2_2 C2_3 A G2_n = 9 … 15.

`timescale 1ns / 1ps

module ic74x153 (
    input  wire A,
    input  wire B,
    input  wire C1_0,
    input  wire C1_1,
    input  wire C1_2,
    input  wire C1_3,
    input  wire G1_n,
    output wire Y1,
    input  wire C2_0,
    input  wire C2_1,
    input  wire C2_2,
    input  wire C2_3,
    input  wire G2_n,
    output wire Y2
);
    wire [3:0] c1 = {C1_3, C1_2, C1_1, C1_0};
    wire [3:0] c2 = {C2_3, C2_2, C2_1, C2_0};
    assign Y1 = !G1_n && c1[{B, A}];
    assign Y2 = !G2_n && c2[{B, A}];
endmodule
