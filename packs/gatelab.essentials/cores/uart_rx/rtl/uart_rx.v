// UART receiver, 8N1. Synchronises `rx` with two flip-flops, starts on a falling edge, checks the
// start bit in its middle (a short glitch is ignored) and samples every bit in its middle.
//
// `valid` is high for one cycle when a byte with a high stop bit has arrived; a low stop bit
// drops the byte and pulses `frame_error` instead. A line held low (a break) is not a new byte:
// the next start bit needs a falling edge.

module uart_rx #(
    parameter CLK_HZ = 12000000,
    parameter BAUD   = 115200
) (
    input  wire       clk,
    input  wire       rx,
    output reg  [7:0] data = 8'd0,
    output reg        valid = 1'b0,
    output reg        frame_error = 1'b0
);
    localparam CLKS_PER_BIT = (CLK_HZ + BAUD / 2) / BAUD;
    localparam COUNTER_BITS = CLKS_PER_BIT > 1 ? $clog2(CLKS_PER_BIT) : 1;

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    // The idle line is high.
    reg [1:0] sync = 2'b11;
    always @(posedge clk)
        sync <= {sync[0], rx};
    wire rx_sync = sync[1];

    reg rx_last = 1'b1;
    always @(posedge clk)
        rx_last <= rx_sync;
    wire rx_fell = rx_last && !rx_sync;

    reg [1:0] state = IDLE;
    reg [COUNTER_BITS-1:0] clocks = 0;
    reg [2:0] bit_index = 3'd0;

    always @(posedge clk) begin
        valid <= 1'b0;
        frame_error <= 1'b0;
        case (state)
            IDLE:
                if (rx_fell) begin
                    clocks <= 0;
                    state <= START;
                end

            START:
                if (clocks == CLKS_PER_BIT / 2 - 1) begin
                    clocks <= 0;
                    bit_index <= 3'd0;
                    state <= rx_sync ? IDLE : DATA;
                end else begin
                    clocks <= clocks + 1'b1;
                end

            DATA:
                if (clocks == CLKS_PER_BIT - 1) begin
                    clocks <= 0;
                    data[bit_index] <= rx_sync;
                    bit_index <= bit_index + 1'b1;
                    if (bit_index == 3'd7)
                        state <= STOP;
                end else begin
                    clocks <= clocks + 1'b1;
                end

            STOP:
                if (clocks == CLKS_PER_BIT - 1) begin
                    clocks <= 0;
                    valid <= rx_sync;
                    frame_error <= !rx_sync;
                    state <= IDLE;
                end else begin
                    clocks <= clocks + 1'b1;
                end
        endcase
    end
endmodule
