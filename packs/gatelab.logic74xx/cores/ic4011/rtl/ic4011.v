// 4011: quad 2-input NAND gate, CMOS (CD4011B, HEF4011B …).
// Pins: A1 B1 Y1 Y2 A2 B2 = 1 … 6, A3 B3 Y3 Y4 A4 B4 = 8 … 13 (the same pinout as the 74x00).

`timescale 1ns / 1ps

module ic4011 (
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
