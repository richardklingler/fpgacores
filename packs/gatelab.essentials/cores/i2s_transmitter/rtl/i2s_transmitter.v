// I2S transmitter for a DAC (24-bit samples, 32 bit slots a channel): the data bit for i2s_clocks, MSB first,
// the MSB one SCLK after LRCK changes (slots 1 … 24 left, 33 … 56 right, the rest zero).
//
// `left` and `right` are taken at the start of each frame; `taken` pulses then, so new samples can follow
// within the frame (one sample period). `sdin` is registered and changes with SCLK's falling edge.

module i2s_transmitter (
    input  wire        clk,
    input  wire        bit_start,
    input  wire [5:0]  slot_next,
    input  wire [23:0] left,
    input  wire [23:0] right,
    output reg         taken = 1'b0,
    output reg         sdin = 1'b0
);
    reg [23:0] word_left = 24'd0, word_right = 24'd0;
    // Slot 0 starts a frame: it sends a zero, the words are taken with it.
    wire [23:0] word_now = slot_next[5] ? word_right : word_left;
    wire [4:0]  in_half = slot_next[4:0];
    wire        data_slot = in_half >= 5'd1 && in_half <= 5'd24;
    wire [4:0]  bit_index = 5'd24 - in_half;

    always @(posedge clk) begin
        taken <= 1'b0;
        if (bit_start) begin
            if (slot_next == 6'd0) begin
                word_left <= left;
                word_right <= right;
                taken <= 1'b1;
                sdin <= 1'b0;
            end else begin
                sdin <= data_slot ? word_now[bit_index] : 1'b0;
            end
        end
    end
endmodule
