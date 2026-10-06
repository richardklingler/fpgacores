// UART transmitter, 8N1 (one start bit, eight data bits LSB first, one stop bit).
//
// Handshake: present a byte on `data` and raise `valid`; the byte is taken in the cycle where
// `valid` and `ready` are both high. `ready` is low while a byte is on the line. `tx` idles high.
// CLK_HZ / BAUD should be at least 2; the bit time is rounded to whole clock cycles.

module uart_tx #(
    parameter CLK_HZ = 12000000,
    parameter BAUD   = 115200
) (
    input  wire       clk,
    input  wire [7:0] data,
    input  wire       valid,
    output wire       ready,
    output wire       tx
);
    localparam CLKS_PER_BIT = (CLK_HZ + BAUD / 2) / BAUD;
    localparam COUNTER_BITS = CLKS_PER_BIT > 1 ? $clog2(CLKS_PER_BIT) : 1;

    // Stop bit, data, start bit; shifted out from bit 0.
    reg [9:0] shift = 10'h3FF;
    reg [3:0] bits_left = 4'd0;
    reg [COUNTER_BITS-1:0] clocks = 0;

    assign ready = (bits_left == 4'd0);
    assign tx = ready ? 1'b1 : shift[0];

    always @(posedge clk) begin
        if (ready) begin
            if (valid) begin
                shift <= {1'b1, data, 1'b0};
                bits_left <= 4'd10;
                clocks <= 0;
            end
        end else if (clocks == CLKS_PER_BIT - 1) begin
            clocks <= 0;
            shift <= {1'b1, shift[9:1]};
            bits_left <= bits_left - 1'b1;
        end else begin
            clocks <= clocks + 1'b1;
        end
    end
endmodule
