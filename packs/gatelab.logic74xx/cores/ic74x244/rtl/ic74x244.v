// 74x244: octal buffer with three-state outputs, two sections of four with their own output enable
// (74LS244, 74HC244 …). Each Y follows its A while the section's OE_n is low, else floats.
// Ports as TI names them: 1A1 = A1_1 (section 1, bit 1), 1Y1 = Y1_1, 1OE = OE1_n.
// Pins: OE1_n A1_1 Y2_4 A1_2 Y2_3 A1_3 Y2_2 A1_4 Y2_1 = 1 … 9,
//       A2_1 Y1_4 A2_2 Y1_3 A2_3 Y1_2 A2_4 Y1_1 OE2_n = 11 … 19.

`timescale 1ns / 1ps

module ic74x244 (
    input  wire A1_1,
    input  wire A1_2,
    input  wire A1_3,
    input  wire A1_4,
    input  wire OE1_n,
    output wire Y1_1,
    output wire Y1_2,
    output wire Y1_3,
    output wire Y1_4,
    input  wire A2_1,
    input  wire A2_2,
    input  wire A2_3,
    input  wire A2_4,
    input  wire OE2_n,
    output wire Y2_1,
    output wire Y2_2,
    output wire Y2_3,
    output wire Y2_4
);
    assign Y1_1 = OE1_n ? 1'bz : A1_1;
    assign Y1_2 = OE1_n ? 1'bz : A1_2;
    assign Y1_3 = OE1_n ? 1'bz : A1_3;
    assign Y1_4 = OE1_n ? 1'bz : A1_4;
    assign Y2_1 = OE2_n ? 1'bz : A2_1;
    assign Y2_2 = OE2_n ? 1'bz : A2_2;
    assign Y2_3 = OE2_n ? 1'bz : A2_3;
    assign Y2_4 = OE2_n ? 1'bz : A2_4;
endmodule
