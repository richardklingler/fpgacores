// 74x165: 8-bit parallel-load shift register (74LS165, 74HC165 …). PL_n low loads D0–D7 at once
// (asynchronously, the outputs follow D7 while it stays low). Otherwise the stages shift on the rising
// edge of CP OR CE_n — the clock is a gated OR, so CE_n low enables CP (and the two are
// interchangeable): Q0 takes DS, Q7 is the last stage.
// Pins: PL_n CP D4 D5 D6 D7 Q7_n = 1 … 7, Q7 DS D0 D1 D2 D3 CE_n = 9 … 15.

`timescale 1ns / 1ps

module ic74x165 (
    input  wire PL_n,
    input  wire CP,
    input  wire CE_n,
    input  wire DS,
    input  wire D0,
    input  wire D1,
    input  wire D2,
    input  wire D3,
    input  wire D4,
    input  wire D5,
    input  wire D6,
    input  wire D7,
    output wire Q7,
    output wire Q7_n
);
    reg [7:0] q = 8'h00;
    wire clock = CP | CE_n;

    always @(posedge clock or negedge PL_n)
        if (!PL_n) q <= {D7, D6, D5, D4, D3, D2, D1, D0};
        else q <= {q[6:0], DS};

    // While PL_n is low the stages follow the data inputs.
    wire last = PL_n ? q[7] : D7;
    assign Q7 = last;
    assign Q7_n = ~last;
endmodule
