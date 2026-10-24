// Bar graph layer: BARS vertical bars in a rectangle on the screen, two values per bar — series A
// (e.g. today) drawn in front, INSET pixels narrower on each side, and series B (e.g. yesterday)
// behind it at full width. Like text_layer and sprite_layer it takes a pixel stream (position,
// timing and the colour below) and passes it on LATENCY = 3 clocks later with the graph on top,
// so layers chain.
//
// The bars start at (BAR_X, BAR_Y): BARS slots of BAR_WIDTH pixels with GAP pixels between them,
// HEIGHT pixels high, so the graph is BARS × (BAR_WIDTH + GAP) − GAP pixels wide. A value is the
// bar's height in pixels from the bottom (0 = no bar; more than HEIGHT fills the column). The
// slot is counted along the line instead of divided, so `x` must count up by one per clock
// through the graph, as video_timing's does.
//
// Optional: a baseline one pixel below the bars, horizontal grid lines every GRID_STEP pixels of
// height (a power of two; 0 = none) where no bar is, and a background inside the rectangle.
// Values live in a small RAM of their own (starting from INIT_A / INIT_B, or 0), written at any time on `clk`: write_address holds the
// series in its top bit (0 = A, 1 = B) and the bar below it. `covered` marks pixels a bar draws.

module bar_graph #(
    parameter X_BITS = 11,
    parameter Y_BITS = 10,
    parameter BARS = 24,
    parameter BAR_X = 0,
    parameter BAR_Y = 0,
    parameter BAR_WIDTH = 16,
    parameter GAP = 4,
    parameter HEIGHT = 256,
    parameter VALUE_BITS = 9,
    parameter INSET = 3,
    parameter GRID_STEP = 0,
    parameter BASELINE = 1,
    parameter BACKGROUND = 0,
    parameter [23:0] COLOUR_A = 24'hFFAA00,
    parameter [23:0] COLOUR_B = 24'h555555,
    parameter [23:0] GRID_COLOUR = 24'h333333,
    parameter [23:0] BASELINE_COLOUR = 24'hAAAAAA,
    parameter [23:0] BACKGROUND_COLOUR = 24'h000000,
    // Hex files with the starting values, one per bar (empty: 0).
    parameter INIT_A = "",
    parameter INIT_B = ""
) (
    input  wire clk,
    input  wire [X_BITS-1:0] x,
    input  wire [Y_BITS-1:0] y,
    input  wire de,
    input  wire hsync,
    input  wire vsync,
    input  wire [7:0] red,
    input  wire [7:0] green,
    input  wire [7:0] blue,
    input  wire write,
    input  wire [$clog2(BARS):0] write_address,
    input  wire [VALUE_BITS-1:0] write_value,
    output reg  [X_BITS-1:0] x_out = 0,
    output reg  [Y_BITS-1:0] y_out = 0,
    output reg  de_out = 1'b0,
    output reg  hsync_out = 1'b0,
    output reg  vsync_out = 1'b0,
    output reg  [7:0] red_out = 8'd0,
    output reg  [7:0] green_out = 8'd0,
    output reg  [7:0] blue_out = 8'd0,
    output reg  covered = 1'b0
);
    localparam IB = $clog2(BARS);
    localparam PITCH = BAR_WIDTH + GAP;
    localparam WIDTH = BARS * PITCH - GAP;
    localparam OB = $clog2(PITCH);
    localparam SB = $clog2(BARS + 1);
    localparam LB = $clog2(HEIGHT);
    localparam BOTTOM = BAR_Y + HEIGHT - 1;
    localparam GB = GRID_STEP > 1 ? $clog2(GRID_STEP) : 1;

    // ---- The values -------------------------------------------------------------------------
    reg [VALUE_BITS-1:0] series_a [0:BARS-1];
    reg [VALUE_BITS-1:0] series_b [0:BARS-1];
    integer i;
    initial begin
        for (i = 0; i < BARS; i = i + 1) begin
            series_a[i] = 0;
            series_b[i] = 0;
        end
        if (INIT_A != "") $readmemh(INIT_A, series_a);
        if (INIT_B != "") $readmemh(INIT_B, series_b);
    end
    always @(posedge clk)
        if (write) begin
            if (write_address[IB]) series_b[write_address[IB-1:0]] <= write_value;
            else series_a[write_address[IB-1:0]] <= write_value;
        end

    // ---- Stage 1: where the pixel is ---------------------------------------------------------
    reg [SB-1:0] slot = 0;
    reg [OB-1:0] offset = 0;
    reg in_x = 1'b0, in_y = 1'b0, base_row = 1'b0;
    reg [LB-1:0] level = 0;
    reg [X_BITS-1:0] x1 = 0;
    reg [Y_BITS-1:0] y1 = 0;
    reg de1 = 1'b0, hs1 = 1'b0, vs1 = 1'b0;
    reg [23:0] below1 = 24'd0;
    always @(posedge clk) begin
        if (x == BAR_X) begin
            slot <= 0;
            offset <= 0;
        end else if (offset == PITCH - 1) begin
            slot <= slot + 1'b1;
            offset <= 0;
        end else offset <= offset + 1'b1;
        in_x <= x >= BAR_X && x < BAR_X + WIDTH;
        in_y <= y >= BAR_Y && y <= BOTTOM;
        level <= BOTTOM - y;
        base_row <= BASELINE != 0 && y == BOTTOM + 1;
        x1 <= x; y1 <= y; de1 <= de; hs1 <= hsync; vs1 <= vsync;
        below1 <= {red, green, blue};
    end

    // ---- Stage 2: the bar's values ------------------------------------------------------------
    reg [VALUE_BITS-1:0] value_a = 0, value_b = 0;
    reg [OB-1:0] offset2 = 0;
    reg in_x2 = 1'b0, in_y2 = 1'b0, base2 = 1'b0;
    reg [LB-1:0] level2 = 0;
    reg [X_BITS-1:0] x2 = 0;
    reg [Y_BITS-1:0] y2 = 0;
    reg de2 = 1'b0, hs2 = 1'b0, vs2 = 1'b0;
    reg [23:0] below2 = 24'd0;
    always @(posedge clk) begin
        value_a <= series_a[slot[IB-1:0]];
        value_b <= series_b[slot[IB-1:0]];
        offset2 <= offset;
        in_x2 <= in_x; in_y2 <= in_y; base2 <= base_row; level2 <= level;
        x2 <= x1; y2 <= y1; de2 <= de1; hs2 <= hs1; vs2 <= vs1;
        below2 <= below1;
    end

    // ---- Stage 3: the colour ------------------------------------------------------------------
    wire in_bar = offset2 < BAR_WIDTH;
    wire in_front = offset2 >= INSET && offset2 < BAR_WIDTH - INSET;
    wire draw_a = in_x2 && in_y2 && in_front && level2 < value_a;
    wire draw_b = in_x2 && in_y2 && in_bar && level2 < value_b;
    wire [GB-1:0] grid_bits = level2[GB-1:0];
    wire grid = GRID_STEP > 1 && in_x2 && in_y2 && grid_bits == {GB{1'b1}};
    wire in_rect = in_x2 && (in_y2 || base2);
    always @(posedge clk) begin
        x_out <= x2; y_out <= y2; de_out <= de2; hsync_out <= hs2; vsync_out <= vs2;
        covered <= draw_a || draw_b;
        if (draw_a) {red_out, green_out, blue_out} <= COLOUR_A;
        else if (draw_b) {red_out, green_out, blue_out} <= COLOUR_B;
        else if (in_x2 && base2) {red_out, green_out, blue_out} <= BASELINE_COLOUR;
        else if (grid) {red_out, green_out, blue_out} <= GRID_COLOUR;
        else if (BACKGROUND != 0 && in_rect) {red_out, green_out, blue_out} <= BACKGROUND_COLOUR;
        else {red_out, green_out, blue_out} <= below2;
    end
endmodule
