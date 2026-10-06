// SPI master: one byte per transfer, most significant bit first, any of the four SPI modes
// (CPOL = clock idle level, CPHA = 0: sample on the first edge, 1: on the second).
//
// Raise `start` with `tx_data` while `ready`; eight bits go out on `mosi` while eight come in on
// `miso`, and `done` pulses with the received byte on `rx_data`. Chip select is yours: hold your
// device's CS low around the bytes of one transaction. SCLK = CLK_HZ / (2 × the half period).

module spi_master #(
    parameter CLK_HZ = 12000000,
    parameter SPI_HZ = 1000000,
    parameter CPOL   = 0,
    parameter CPHA   = 0
) (
    input  wire       clk,
    input  wire [7:0] tx_data,
    input  wire       start,
    output wire       ready,
    output reg  [7:0] rx_data = 8'd0,
    output reg        done = 1'b0,
    output reg        sclk = CPOL,
    output wire       mosi,
    input  wire       miso
);
    localparam HALF = CLK_HZ / (2 * SPI_HZ) > 0 ? CLK_HZ / (2 * SPI_HZ) : 1;
    localparam COUNTER_BITS = HALF > 1 ? $clog2(HALF) : 1;

    reg       busy = 1'b0;
    reg [7:0] tx_shift = 8'd0;
    reg [7:0] rx_shift = 8'd0;
    reg [4:0] edge_index = 5'd0;        // 0 … 15: even = leading edge, odd = trailing edge
    reg [COUNTER_BITS-1:0] clocks = 0;

    assign ready = !busy;
    assign mosi = tx_shift[7];

    always @(posedge clk) begin
        done <= 1'b0;
        if (!busy) begin
            sclk <= CPOL;
            if (start) begin
                busy <= 1'b1;
                tx_shift <= tx_data;
                edge_index <= 5'd0;
                clocks <= 0;
            end
        end else if (clocks == HALF - 1) begin
            clocks <= 0;
            if (edge_index == 5'd16) begin
                // The last half period after the final edge: the clock is idle again.
                busy <= 1'b0;
                done <= 1'b1;
                rx_data <= rx_shift;
            end else begin
                sclk <= !sclk;
                edge_index <= edge_index + 1'b1;
                if (edge_index[0] == (CPHA != 0)) begin
                    // Sampling edge.
                    rx_shift <= {rx_shift[6:0], miso};
                end else if (CPHA == 0 || edge_index != 5'd0) begin
                    // Shifting edge (with CPHA = 1 the first bit is already on mosi).
                    tx_shift <= {tx_shift[6:0], 1'b0};
                end
            end
        end else begin
            clocks <= clocks + 1'b1;
        end
    end
endmodule
