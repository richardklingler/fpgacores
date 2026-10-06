// Edge detector: one-cycle pulses on `rise` and `fall` when `in` changes. `in` must already be
// synchronous to `clk` (from a debouncer, a synchroniser or other logic in the same clock
// domain). The pulses come one cycle after the change.

module edge_detect (
    input  wire clk,
    input  wire in,
    output reg  rise = 1'b0,
    output reg  fall = 1'b0
);
    reg last = 1'b0;
    always @(posedge clk) begin
        last <= in;
        rise <= in && !last;
        fall <= !in && last;
    end
endmodule
