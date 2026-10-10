// 74x04: hex inverter (74LS04, 74HC04 …). Zero-delay model; pins: 1A 1Y = 1 2, 2A 2Y = 3 4,
// 3A 3Y = 5 6, 4Y 4A = 8 9, 5Y 5A = 10 11, 6Y 6A = 12 13.

`timescale 1ns / 1ps

module ic74x04 (
    input  wire A1,
    output wire Y1,
    input  wire A2,
    output wire Y2,
    input  wire A3,
    output wire Y3,
    input  wire A4,
    output wire Y4,
    input  wire A5,
    output wire Y5,
    input  wire A6,
    output wire Y6
);
    assign Y1 = ~A1;
    assign Y2 = ~A2;
    assign Y3 = ~A3;
    assign Y4 = ~A4;
    assign Y5 = ~A5;
    assign Y6 = ~A6;
endmodule
