// 74x245: octal bus transceiver with three-state outputs (74LS245, 74HC245 …). With OE_n low, DIR
// high drives B from A, DIR low drives A from B; with OE_n high both sides float.
// Pins: DIR A1 … A8 = 1 … 9, B8 … B1 OE_n = 11 … 19 (pin 18 is B1).

`timescale 1ns / 1ps

module ic74x245 (
    input  wire DIR,
    input  wire OE_n,
    inout  wire A1,
    inout  wire A2,
    inout  wire A3,
    inout  wire A4,
    inout  wire A5,
    inout  wire A6,
    inout  wire A7,
    inout  wire A8,
    inout  wire B1,
    inout  wire B2,
    inout  wire B3,
    inout  wire B4,
    inout  wire B5,
    inout  wire B6,
    inout  wire B7,
    inout  wire B8
);
    assign B1 = (!OE_n && DIR) ? A1 : 1'bz;
    assign B2 = (!OE_n && DIR) ? A2 : 1'bz;
    assign B3 = (!OE_n && DIR) ? A3 : 1'bz;
    assign B4 = (!OE_n && DIR) ? A4 : 1'bz;
    assign B5 = (!OE_n && DIR) ? A5 : 1'bz;
    assign B6 = (!OE_n && DIR) ? A6 : 1'bz;
    assign B7 = (!OE_n && DIR) ? A7 : 1'bz;
    assign B8 = (!OE_n && DIR) ? A8 : 1'bz;
    assign A1 = (!OE_n && !DIR) ? B1 : 1'bz;
    assign A2 = (!OE_n && !DIR) ? B2 : 1'bz;
    assign A3 = (!OE_n && !DIR) ? B3 : 1'bz;
    assign A4 = (!OE_n && !DIR) ? B4 : 1'bz;
    assign A5 = (!OE_n && !DIR) ? B5 : 1'bz;
    assign A6 = (!OE_n && !DIR) ? B6 : 1'bz;
    assign A7 = (!OE_n && !DIR) ? B7 : 1'bz;
    assign A8 = (!OE_n && !DIR) ? B8 : 1'bz;
endmodule
