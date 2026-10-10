// 74x163: synchronous 4-bit binary counter with synchronous clear (74LS163, 74HC163 …).
// Clear beats load beats count; counting needs CEP and CET; TC = CET at count 15.
// Pins: MR_n CP D0 D1 D2 D3 CEP = 1 … 7, PE_n CET = 9 10, Q3 Q2 Q1 Q0 TC = 11 … 15.

`timescale 1ns / 1ps

module ic74x163 (
    input  wire CP,
    input  wire MR_n,
    input  wire PE_n,
    input  wire CEP,
    input  wire CET,
    input  wire D0,
    input  wire D1,
    input  wire D2,
    input  wire D3,
    output wire Q0,
    output wire Q1,
    output wire Q2,
    output wire Q3,
    output wire TC
);
    reg [3:0] count = 4'd0;

    always @(posedge CP)
        if (!MR_n) count <= 4'd0;
        else if (!PE_n) count <= {D3, D2, D1, D0};
        else if (CEP && CET) count <= count + 4'd1;

    assign {Q3, Q2, Q1, Q0} = count;
    assign TC = CET && (count == 4'hF);
endmodule
