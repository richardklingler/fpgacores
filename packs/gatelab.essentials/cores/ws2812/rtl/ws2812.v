// WS2812 / WS2812B ("NeoPixel") LED chain driver. Each pixel is 24 bits sent as green, red, blue,
// most significant bit first, on one wire: a 1 is 0.8 µs high + 0.45 µs low, a 0 is 0.4 µs high +
// 0.85 µs low (1.25 µs per bit, within the ±150 ns the LEDs accept).
//
// Hand the pixels over one by one with `rgb` = {red, green, blue} and `valid`; a pixel is taken
// when `valid` and `ready` are both high. When no pixel follows, the line stays low and after
// RESET_US the LEDs show what they received: `idle` goes high, and the next pixel starts again at
// the first LED.

module ws2812 #(
    parameter CLK_HZ   = 12000000,
    parameter RESET_US = 300
) (
    input  wire        clk,
    input  wire [23:0] rgb,
    input  wire        valid,
    output wire        ready,
    output reg         dout = 1'b0,
    output wire        idle
);
    // Clock cycles, rounded to the nearest cycle.
    localparam T0H   = (CLK_HZ * 2 + 2500000) / 5000000;     // 0.4 µs
    localparam T1H   = (CLK_HZ * 4 + 2500000) / 5000000;     // 0.8 µs
    localparam TBIT  = (CLK_HZ * 5 + 2000000) / 4000000;     // 1.25 µs
    localparam TRESET = (CLK_HZ / 1000000) * RESET_US;
    localparam COUNTER_BITS = $clog2(TRESET > TBIT ? TRESET + 1 : TBIT + 1);

    reg        sending = 1'b0;
    reg [23:0] shift = 24'd0;               // green, red, blue
    reg [4:0]  bit_index = 5'd0;
    reg [COUNTER_BITS-1:0] clocks = 0;
    reg [COUNTER_BITS-1:0] low_clocks = 0;

    assign ready = !sending;
    assign idle = !sending && (low_clocks == TRESET);

    always @(posedge clk) begin
        if (!sending) begin
            dout <= 1'b0;
            if (low_clocks != TRESET) low_clocks <= low_clocks + 1'b1;
            if (valid) begin
                sending <= 1'b1;
                shift <= {rgb[15:8], rgb[23:16], rgb[7:0]};
                bit_index <= 5'd0;
                clocks <= 0;
                dout <= 1'b1;
                low_clocks <= 0;
            end
        end else begin
            clocks <= clocks + 1'b1;
            if (clocks == (shift[23] ? T1H : T0H) - 1) dout <= 1'b0;
            if (clocks == TBIT - 1) begin
                clocks <= 0;
                if (bit_index == 5'd23) begin
                    sending <= 1'b0;
                end else begin
                    bit_index <= bit_index + 1'b1;
                    shift <= {shift[22:0], 1'b0};
                    dout <= 1'b1;
                end
            end
        end
    end
endmodule
