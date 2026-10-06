// Asynchronous FIFO: first in, first out between two unrelated clocks. 2^DEPTH_LOG2 entries.
//
// The pointers cross clock domains in Gray code (one bit changes per step) through two
// flip-flops each, so a pointer is never seen half-updated. `full` (write side) and `empty`
// (read side) are conservative: they may stay set a few cycles longer than needed, never too
// short. The read is registered: `rd_data` shows the word one rd_clk cycle after `rd_en` and
// keeps it until the next read.
// Reset both sides together (each reset synchronous to its own clock, active high).

module async_fifo #(
    parameter WIDTH      = 8,
    parameter DEPTH_LOG2 = 4
) (
    input  wire             wr_clk,
    input  wire             wr_rst,
    input  wire [WIDTH-1:0] wr_data,
    input  wire             wr_en,
    output reg              full = 1'b0,

    input  wire             rd_clk,
    input  wire             rd_rst,
    input  wire             rd_en,
    output reg  [WIDTH-1:0] rd_data = 0,
    output reg              empty = 1'b1
);
    localparam A = DEPTH_LOG2;

    reg [WIDTH-1:0] memory [0:(1 << A)-1];

    // Binary pointers address the memory; Gray pointers cross to the other side.
    reg [A:0] wr_bin = 0, wr_gray = 0;
    reg [A:0] rd_bin = 0, rd_gray = 0;

    // Write side.
    reg [A:0] rd_gray_w1 = 0, rd_gray_w2 = 0;           // the read pointer, synchronised
    wire [A:0] wr_bin_next  = wr_bin + (wr_en && !full);
    wire [A:0] wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;

    always @(posedge wr_clk) begin
        if (wr_en && !full) memory[wr_bin[A-1:0]] <= wr_data;
    end

    always @(posedge wr_clk) begin
        if (wr_rst) begin
            wr_bin <= 0; wr_gray <= 0; full <= 1'b0;
            rd_gray_w1 <= 0; rd_gray_w2 <= 0;
        end else begin
            wr_bin <= wr_bin_next;
            wr_gray <= wr_gray_next;
            {rd_gray_w2, rd_gray_w1} <= {rd_gray_w1, rd_gray};
            // Full: the next write pointer is a full turn ahead of the read pointer — in Gray
            // code the two top bits differ and the rest are equal.
            full <= (wr_gray_next == {~rd_gray_w2[A:A-1], rd_gray_w2[A-2:0]});
        end
    end

    // Read side.
    reg [A:0] wr_gray_r1 = 0, wr_gray_r2 = 0;           // the write pointer, synchronised
    wire [A:0] rd_bin_next  = rd_bin + (rd_en && !empty);
    wire [A:0] rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    always @(posedge rd_clk) begin
        if (rd_en && !empty) rd_data <= memory[rd_bin[A-1:0]];
    end

    always @(posedge rd_clk) begin
        if (rd_rst) begin
            rd_bin <= 0; rd_gray <= 0; empty <= 1'b1;
            wr_gray_r1 <= 0; wr_gray_r2 <= 0;
        end else begin
            rd_bin <= rd_bin_next;
            rd_gray <= rd_gray_next;
            {wr_gray_r2, wr_gray_r1} <= {wr_gray_r1, wr_gray};
            empty <= (rd_gray_next == wr_gray_r2);
        end
    end
endmodule
