// 74x151: 8-to-1 data selector/multiplexer with strobe and both outputs (74LS151, 74HC151 …).
// Y is the selected input D{C B A} while G_n is low; with G_n high, Y is low and Y_n high.
// Pins: D3 D2 D1 D0 Y Y_n G_n = 1 2 3 4 5 6 7, C B A = 9 10 11, D7 D6 D5 D4 = 12 13 14 15.

`timescale 1ns / 1ps

module ic74x151 (
    input  wire D0,
    input  wire D1,
    input  wire D2,
    input  wire D3,
    input  wire D4,
    input  wire D5,
    input  wire D6,
    input  wire D7,
    input  wire A,
    input  wire B,
    input  wire C,
    input  wire G_n,
    output wire Y,
    output wire Y_n
);
    wire [7:0] d = {D7, D6, D5, D4, D3, D2, D1, D0};
    assign Y = !G_n && d[{C, B, A}];
    assign Y_n = !Y;
endmodule
