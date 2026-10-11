// 74x157: quad 2-to-1 data selector/multiplexer, shared select and strobe (74LS157, 74HC157 …).
// Each Y is its A input with S low, its B input with S high, and low while G_n is high.
// Pins: S A1 B1 Y1 A2 B2 Y2 = 1 … 7, Y3 B3 A3 Y4 B4 A4 G_n = 9 … 15.

`timescale 1ns / 1ps

module ic74x157 (
    input  wire S,
    input  wire G_n,
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
    assign Y1 = !G_n && (S ? B1 : A1);
    assign Y2 = !G_n && (S ? B2 : A2);
    assign Y3 = !G_n && (S ? B3 : A3);
    assign Y4 = !G_n && (S ? B4 : A4);
endmodule
