// I2S receiver for an ADC (24-bit samples, 32 bit slots a channel) with i2s_clocks: `sdout` from the pin
// through two flip-flops, each bit taken on bit_sample (the value just before SCLK rose: the ADC changes it after), MSB first, the MSB one
// SCLK after LRCK changes. `left` and `right` hold the last complete frame; `valid` pulses when the right
// channel's last bit is in (both are then from the same frame).

module i2s_receiver (
    input  wire        clk,
    input  wire        bit_sample,
    input  wire [5:0]  slot,
    input  wire        sdout,
    output reg  [23:0] left = 24'd0,
    output reg  [23:0] right = 24'd0,
    output reg         valid = 1'b0
);
    reg [1:0]  sync = 2'b00;
    reg [22:0] shift = 23'd0;
    reg [23:0] left_frame = 24'd0;
    wire       data_slot = slot[4:0] >= 5'd1 && slot[4:0] <= 5'd24;
    wire [23:0] word = {shift, sync[1]};

    always @(posedge clk) begin
        sync <= {sync[0], sdout};
        valid <= 1'b0;
        if (bit_sample && data_slot) begin
            shift <= word[22:0];
            if (slot == 6'd24) left_frame <= word;
            if (slot == 6'd56) begin
                left <= left_frame;
                right <= word;
                valid <= 1'b1;
            end
        end
    end
endmodule
