// Sine tone generator: a phase accumulator and a 256-point sine (from a 65-entry quarter wave), 16-bit signed
// full scale (±32767). Each `advance` adds `step` to the phase; `sample` is the sine of the phase before it,
// one clock later. Frequency = step · rate / 2^PHASE_BITS, with `rate` the advances a second (the sample rate:
// i2s_transmitter's `taken`). Scale the sample down (>>>) for a quieter tone.

module tone_generator #(
    parameter PHASE_BITS = 24
) (
    input  wire                  clk,
    input  wire                  advance,
    input  wire [PHASE_BITS-1:0] step,
    output reg  signed [15:0]    sample = 16'sd0
);
    reg [PHASE_BITS-1:0] phase = {PHASE_BITS{1'b0}};
    wire [7:0] index = phase[PHASE_BITS-1 -: 8];
    // Quadrant by the top two bits; the table runs 0 … 64 (sin 0 … sin pi/2).
    wire [6:0] at = index[6] ? 7'd64 - {1'b0, index[5:0]} : {1'b0, index[5:0]};
    reg [14:0] quarter;
    always @(*) begin
        case (at)
            7'd0: quarter = 15'd0;
            7'd1: quarter = 15'd804;
            7'd2: quarter = 15'd1608;
            7'd3: quarter = 15'd2410;
            7'd4: quarter = 15'd3212;
            7'd5: quarter = 15'd4011;
            7'd6: quarter = 15'd4808;
            7'd7: quarter = 15'd5602;
            7'd8: quarter = 15'd6393;
            7'd9: quarter = 15'd7179;
            7'd10: quarter = 15'd7962;
            7'd11: quarter = 15'd8739;
            7'd12: quarter = 15'd9512;
            7'd13: quarter = 15'd10278;
            7'd14: quarter = 15'd11039;
            7'd15: quarter = 15'd11793;
            7'd16: quarter = 15'd12539;
            7'd17: quarter = 15'd13279;
            7'd18: quarter = 15'd14010;
            7'd19: quarter = 15'd14732;
            7'd20: quarter = 15'd15446;
            7'd21: quarter = 15'd16151;
            7'd22: quarter = 15'd16846;
            7'd23: quarter = 15'd17530;
            7'd24: quarter = 15'd18204;
            7'd25: quarter = 15'd18868;
            7'd26: quarter = 15'd19519;
            7'd27: quarter = 15'd20159;
            7'd28: quarter = 15'd20787;
            7'd29: quarter = 15'd21403;
            7'd30: quarter = 15'd22005;
            7'd31: quarter = 15'd22594;
            7'd32: quarter = 15'd23170;
            7'd33: quarter = 15'd23731;
            7'd34: quarter = 15'd24279;
            7'd35: quarter = 15'd24811;
            7'd36: quarter = 15'd25329;
            7'd37: quarter = 15'd25832;
            7'd38: quarter = 15'd26319;
            7'd39: quarter = 15'd26790;
            7'd40: quarter = 15'd27245;
            7'd41: quarter = 15'd27683;
            7'd42: quarter = 15'd28105;
            7'd43: quarter = 15'd28510;
            7'd44: quarter = 15'd28898;
            7'd45: quarter = 15'd29268;
            7'd46: quarter = 15'd29621;
            7'd47: quarter = 15'd29956;
            7'd48: quarter = 15'd30273;
            7'd49: quarter = 15'd30571;
            7'd50: quarter = 15'd30852;
            7'd51: quarter = 15'd31113;
            7'd52: quarter = 15'd31356;
            7'd53: quarter = 15'd31580;
            7'd54: quarter = 15'd31785;
            7'd55: quarter = 15'd31971;
            7'd56: quarter = 15'd32137;
            7'd57: quarter = 15'd32285;
            7'd58: quarter = 15'd32412;
            7'd59: quarter = 15'd32521;
            7'd60: quarter = 15'd32609;
            7'd61: quarter = 15'd32678;
            7'd62: quarter = 15'd32728;
            7'd63: quarter = 15'd32757;
            7'd64: quarter = 15'd32767;
            default: quarter = 15'd32767;
        endcase
    end
    always @(posedge clk)
        if (advance) begin
            phase <= phase + step;
            sample <= index[7] ? -$signed({1'b0, quarter}) : $signed({1'b0, quarter});
        end
endmodule
