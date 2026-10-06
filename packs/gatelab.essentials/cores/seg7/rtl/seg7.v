// Seven-segment display driver for DIGITS multiplexed digits. Shows `value` in hexadecimal, four
// bits per digit (digit 0 = the lowest four bits), with a decimal point per digit from `dots`.
// The digits are lit one after another, each for 1 / (REFRESH_HZ × DIGITS) seconds.
//
// `segments` is {g, f, e, d, c, b, a}. Set SEGMENTS_ACTIVE_LOW / DIGITS_ACTIVE_LOW to match the
// board (common anode displays usually take both low).

module seg7 #(
    parameter CLK_HZ              = 12000000,
    parameter DIGITS              = 4,
    parameter REFRESH_HZ          = 250,
    parameter SEGMENTS_ACTIVE_LOW = 0,
    parameter DIGITS_ACTIVE_LOW   = 0
) (
    input  wire                  clk,
    input  wire [DIGITS*4-1:0]   value,
    input  wire [DIGITS-1:0]     dots,
    output reg  [6:0]            segments = 7'd0,
    output reg                   dp = 1'b0,
    output reg  [DIGITS-1:0]     digit_enable = 0
);
    localparam SLOT = CLK_HZ / (REFRESH_HZ * DIGITS) > 0 ? CLK_HZ / (REFRESH_HZ * DIGITS) : 1;
    localparam COUNTER_BITS = SLOT > 1 ? $clog2(SLOT) : 1;
    localparam INDEX_BITS = DIGITS > 1 ? $clog2(DIGITS) : 1;

    function [6:0] pattern(input [3:0] digit);
        case (digit)            // gfedcba
            4'h0: pattern = 7'b0111111;
            4'h1: pattern = 7'b0000110;
            4'h2: pattern = 7'b1011011;
            4'h3: pattern = 7'b1001111;
            4'h4: pattern = 7'b1100110;
            4'h5: pattern = 7'b1101101;
            4'h6: pattern = 7'b1111101;
            4'h7: pattern = 7'b0000111;
            4'h8: pattern = 7'b1111111;
            4'h9: pattern = 7'b1101111;
            4'hA: pattern = 7'b1110111;
            4'hB: pattern = 7'b1111100;
            4'hC: pattern = 7'b0111001;
            4'hD: pattern = 7'b1011110;
            4'hE: pattern = 7'b1111001;
            default: pattern = 7'b1110001;   // F
        endcase
    endfunction

    reg [COUNTER_BITS-1:0] clocks = 0;
    reg [INDEX_BITS-1:0] index = 0;

    always @(posedge clk) begin
        if (clocks == SLOT - 1) begin
            clocks <= 0;
            index <= (index == DIGITS - 1) ? 0 : index + 1'b1;
        end else begin
            clocks <= clocks + 1'b1;
        end
        segments <= pattern(value[index * 4 +: 4]) ^ {7{SEGMENTS_ACTIVE_LOW != 0}};
        dp <= dots[index] ^ (SEGMENTS_ACTIVE_LOW != 0);
        digit_enable <= ({{(DIGITS-1){1'b0}}, 1'b1} << index) ^ {DIGITS{DIGITS_ACTIVE_LOW != 0}};
    end
endmodule
