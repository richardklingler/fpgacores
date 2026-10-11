// 74x595: 8-bit shift register with output latches and three-state outputs (74HC595, 74LS595 …).
// SRCLK rising: the shift register moves on, stage A taking SER; SRCLR_n low clears it (the latches
// keep their value). RCLK rising copies the shift register into the latches, which drive QA–QH while
// OE_n is low (high-impedance otherwise). QH_prime (the datasheet's QH') is the shift register's
// last stage, for cascading; it is never three-state.
// Pins: QB … QH = 1 … 7, QH_prime SRCLR_n SRCLK RCLK OE_n SER QA = 9 … 15.

`timescale 1ns / 1ps

module ic74x595 (
    input  wire SER,
    input  wire SRCLK,
    input  wire SRCLR_n,
    input  wire RCLK,
    input  wire OE_n,
    output wire QA,
    output wire QB,
    output wire QC,
    output wire QD,
    output wire QE,
    output wire QF,
    output wire QG,
    output wire QH,
    output wire QH_prime
);
    reg [7:0] shift = 8'h00;   // bit 0 = stage A
    reg [7:0] latch = 8'h00;

    always @(posedge SRCLK or negedge SRCLR_n)
        if (!SRCLR_n) shift <= 8'h00;
        else shift <= {shift[6:0], SER};

    always @(posedge RCLK)
        latch <= shift;

    assign {QH, QG, QF, QE, QD, QC, QB, QA} = OE_n ? 8'bzzzzzzzz : latch;
    assign QH_prime = shift[7];
endmodule
