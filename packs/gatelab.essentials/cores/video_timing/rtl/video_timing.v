// Video timing generator for VGA and DVI/HDMI: horizontal and vertical sync, the active area
// (`active`, also called data enable) and the position of the pixel being drawn. Defaults:
// 640×480 at 60 Hz, which needs a 25.175 MHz pixel clock (25 MHz works on almost every monitor).
//
// `x` and `y` count from 0 at the top left of the active area; outside it they keep counting
// through the blanking (x up to H_TOTAL - 1). `frame_start` pulses at x = 0, y = 0. Syncs follow
// the SYNC_POSITIVE parameters (640×480 uses negative syncs for both).

module video_timing #(
    parameter H_ACTIVE = 640,
    parameter H_FRONT  = 16,
    parameter H_SYNC   = 96,
    parameter H_BACK   = 48,
    parameter V_ACTIVE = 480,
    parameter V_FRONT  = 10,
    parameter V_SYNC   = 2,
    parameter V_BACK   = 33,
    parameter H_SYNC_POSITIVE = 0,
    parameter V_SYNC_POSITIVE = 0
) (
    input  wire clk,
    output reg  hsync = 1'b0,
    output reg  vsync = 1'b0,
    output reg  active = 1'b0,
    output reg  frame_start = 1'b0,
    output reg  [$clog2(H_ACTIVE + H_FRONT + H_SYNC + H_BACK)-1:0] x = 0,
    output reg  [$clog2(V_ACTIVE + V_FRONT + V_SYNC + V_BACK)-1:0] y = 0
);
    localparam H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    // The position of the next pixel; the outputs describe the current one.
    reg [$clog2(H_TOTAL)-1:0] h = 0;
    reg [$clog2(V_TOTAL)-1:0] v = 0;

    always @(posedge clk) begin
        if (h == H_TOTAL - 1) begin
            h <= 0;
            v <= (v == V_TOTAL - 1) ? 0 : v + 1'b1;
        end else begin
            h <= h + 1'b1;
        end
        x <= h;
        y <= v;
        active <= (h < H_ACTIVE) && (v < V_ACTIVE);
        frame_start <= (h == 0) && (v == 0);
        hsync <= ((h >= H_ACTIVE + H_FRONT) && (h < H_ACTIVE + H_FRONT + H_SYNC)) == (H_SYNC_POSITIVE != 0);
        vsync <= ((v >= V_ACTIVE + V_FRONT) && (v < V_ACTIVE + V_FRONT + V_SYNC)) == (V_SYNC_POSITIVE != 0);
    end
endmodule
