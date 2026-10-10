// 74x121: monostable multivibrator (one-shot), not retriggerable (74LS121 …).
// A pulse of PULSE_NS starts when (A1 or A2 is low) and B is high becomes true. On the real part
// the time comes from Rext/Cext (pins 9–11, about 0.7 · R · C); these analogue pins aren't modelled.
// Simulation model only: the delay doesn't synthesize — on an FPGA a counter replaces it (the
// KiCad import report says so and computes the time).
// Pins: Q_n = 1, A1 A2 B Q = 3 4 5 6.

`timescale 1ns / 1ps

module ic74x121 #(
    parameter PULSE_NS = 30
) (
    input  wire A1,
    input  wire A2,
    input  wire B,
    output wire Q,
    output wire Q_n
);
    reg pulse = 1'b0;
    wire trigger = B && !(A1 && A2);

    always @(posedge trigger)
        if (!pulse) begin
            pulse = 1'b1;
            #(PULSE_NS) pulse = 1'b0;
        end

    assign Q = pulse;
    assign Q_n = ~pulse;
endmodule
