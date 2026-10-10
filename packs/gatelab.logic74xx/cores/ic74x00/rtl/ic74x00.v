// 74x00: quad 2-input NAND gate (74LS00, 74HC00, 74HCT00 …).
// Zero-delay model; pins: 1A 1B 1Y = 1 2 3, 2A 2B 2Y = 4 5 6, 3Y 3A 3B = 8 9 10, 4Y 4A 4B = 11 12 13.

`timescale 1ns / 1ps

module ic74x00 (
    input  wire A1,
    input  wire B1,
    output wire Y1,
    input  wire A2,
    input  wire B2,
    output wire Y2,
    input  wire A3,
    input  wire B3,
    output wire Y3,
    input  wire A4,
    input  wire B4,
    output wire Y4
);
    assign Y1 = ~(A1 & B1);
    assign Y2 = ~(A2 & B2);
    assign Y3 = ~(A3 & B3);
    assign Y4 = ~(A4 & B4);
endmodule
