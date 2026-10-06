// Debouncer for a button or switch. Synchronises `in` with two flip-flops, then changes `out`
// only after the input has kept its new level for MS milliseconds: bounces shorter than that
// are ignored. `out` starts low.

module debouncer #(
    parameter CLK_HZ = 12000000,
    parameter MS     = 10
) (
    input  wire clk,
    input  wire in,
    output reg  out = 1'b0
);
    localparam STABLE_CLKS  = (CLK_HZ / 1000) * MS;
    localparam COUNTER_BITS = STABLE_CLKS > 1 ? $clog2(STABLE_CLKS) : 1;

    reg [1:0] sync = 2'b00;
    always @(posedge clk)
        sync <= {sync[0], in};

    reg [COUNTER_BITS-1:0] clocks = 0;
    always @(posedge clk) begin
        if (sync[1] == out) begin
            clocks <= 0;
        end else if (clocks == STABLE_CLKS - 1) begin
            clocks <= 0;
            out <= sync[1];
        end else begin
            clocks <= clocks + 1'b1;
        end
    end
endmodule
