// Clock divider: a one-cycle `tick` HZ times per second, and `square`, a 50 % square wave at HZ.
// Both are ordinary signals in the clk domain — use `tick` as a clock enable rather than as a
// clock (FPGA clock nets want real clocks from a PLL or a pin). CLK_HZ / HZ is rounded down.

module clock_divider #(
    parameter CLK_HZ = 12000000,
    parameter HZ     = 1
) (
    input  wire clk,
    output reg  tick = 1'b0,
    output reg  square = 1'b0
);
    localparam PERIOD       = CLK_HZ / HZ;
    localparam COUNTER_BITS = PERIOD > 1 ? $clog2(PERIOD) : 1;

    reg [COUNTER_BITS-1:0] clocks = 0;
    always @(posedge clk) begin
        tick <= (clocks == PERIOD - 1);
        square <= (clocks < PERIOD / 2);
        clocks <= (clocks == PERIOD - 1) ? 0 : clocks + 1'b1;
    end
endmodule
