// Synchronous FIFO: first in, first out, one clock. 2^DEPTH_LOG2 entries of WIDTH bits.
//
// Write: `wr_en` with `wr_data` stores a word unless `full`. Read: `rd_en` takes a word unless
// `empty`; it appears on `rd_data` one cycle later and stays until the next read (a registered
// read, so the memory can be block RAM). `count` is the number of stored words. `rst` (synchronous, active high) empties it.

module sync_fifo #(
    parameter WIDTH      = 8,
    parameter DEPTH_LOG2 = 4
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire [WIDTH-1:0]      wr_data,
    input  wire                  wr_en,
    output wire                  full,
    input  wire                  rd_en,
    output reg  [WIDTH-1:0]      rd_data = 0,
    output wire                  empty,
    output wire [DEPTH_LOG2:0]   count
);
    localparam DEPTH = 1 << DEPTH_LOG2;

    reg [WIDTH-1:0] memory [0:DEPTH-1];
    // One bit more than the address: equal pointers are empty, pointers a full turn apart full.
    reg [DEPTH_LOG2:0] wr_ptr = 0;
    reg [DEPTH_LOG2:0] rd_ptr = 0;

    assign count = wr_ptr - rd_ptr;
    assign empty = (wr_ptr == rd_ptr);
    assign full  = (count == DEPTH);

    wire write = wr_en && !full;
    wire read  = rd_en && !empty;

    always @(posedge clk) begin
        if (write) memory[wr_ptr[DEPTH_LOG2-1:0]] <= wr_data;
        if (read)  rd_data <= memory[rd_ptr[DEPTH_LOG2-1:0]];
    end

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            if (write) wr_ptr <= wr_ptr + 1'b1;
            if (read)  rd_ptr <= rd_ptr + 1'b1;
        end
    end
endmodule
