// Pulse-width modulation: `out` is high for `duty` of every 2^WIDTH clock cycles (0 = always
// low, 2^WIDTH - 1 = all but one cycle). `duty` is taken at the start of each period, so changing
// it never makes a short glitch.

module pwm #(
    parameter WIDTH = 8
) (
    input  wire             clk,
    input  wire [WIDTH-1:0] duty,
    output reg              out = 1'b0
);
    reg [WIDTH-1:0] counter = 0;
    reg [WIDTH-1:0] current = 0;

    always @(posedge clk) begin
        counter <= counter + 1'b1;
        if (counter == {WIDTH{1'b1}})
            current <= duty;
        out <= (counter < current);
    end
endmodule
