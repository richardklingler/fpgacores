// Text layer: draws a grid of characters from a font ROM over the picture passing through. Like
// sprite_layer it takes a pixel stream (position, timing and the colour below) and passes it on
// LATENCY = FONT_LATENCY + 2 clocks later with the text on top, so layers chain.
//
// The grid is COLUMNS × ROWS cells at (TEXT_X, TEXT_Y) on the screen, each CELL_WIDTH ×
// CELL_HEIGHT pixels (the font's cells, powers of two) times 2^SCALE_SHIFT. The text lives in a
// small RAM of its own, one word per cell: a 4-bit colour (an index into PALETTE) and an 8-bit
// character code. It starts from INIT_FILE (hex, one word per cell row by row, e.g. F41 = white
// "A"), or blank (BLANK_CODE in colour 15) without one; `write` changes a cell at any time
// (address = row × COLUMNS + column).
//
// The glyphs come from a font ROM reader (Project ▸ Add Font ROM…): the layer drives its code,
// row and column and reads `pixel` back FONT_LATENCY clocks later. Pixels without ink show the
// picture below, or BACKGROUND_COLOUR inside the grid with BACKGROUND = 1. `ink` marks output
// pixels drawn by a character.

module text_layer #(
    parameter X_BITS = 11,
    parameter Y_BITS = 10,
    parameter COLUMNS = 40,
    parameter ROWS = 2,
    parameter CELL_WIDTH = 8,
    parameter CELL_HEIGHT = 8,
    parameter SCALE_SHIFT = 0,
    parameter TEXT_X = 0,
    parameter TEXT_Y = 0,
    parameter CODE_BITS = 8,
    parameter FONT_LATENCY = 1,
    parameter INIT_FILE = "",
    parameter [7:0] BLANK_CODE = 8'h20,
    parameter BACKGROUND = 0,
    parameter [23:0] BACKGROUND_COLOUR = 24'h000000,
    // 16 colours, index 0 in the lowest 24 bits: the CGA palette (15 = white).
    parameter [383:0] PALETTE = {
        24'hFFFFFF, 24'hFFFF55, 24'hFF55FF, 24'hFF5555, 24'h55FFFF, 24'h55FF55, 24'h5555FF, 24'h555555,
        24'hAAAAAA, 24'hAA5500, 24'hAA00AA, 24'hAA0000, 24'h00AAAA, 24'h00AA00, 24'h0000AA, 24'h000000
    }
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
    input  wire [$clog2(COLUMNS * ROWS)-1:0] write_address,
    input  wire [7:0] write_code,
    input  wire [3:0] write_colour,
    output wire [CODE_BITS-1:0] font_code,
    output reg  [$clog2(CELL_HEIGHT)-1:0] font_row = 0,
    output reg  [$clog2(CELL_WIDTH)-1:0] font_column = 0,
    input  wire font_pixel,
    output reg  [X_BITS-1:0] x_out = 0,
    output reg  [Y_BITS-1:0] y_out = 0,
    output reg  de_out = 1'b0,
    output reg  hsync_out = 1'b0,
    output reg  vsync_out = 1'b0,
    output reg  [7:0] red_out = 8'd0,
    output reg  [7:0] green_out = 8'd0,
    output reg  [7:0] blue_out = 8'd0,
    output reg  ink = 1'b0
);
    localparam CELLS = COLUMNS * ROWS;
    localparam AB = $clog2(CELLS);
    localparam CB = COLUMNS > 1 ? $clog2(COLUMNS) : 1;
    localparam RB = ROWS > 1 ? $clog2(ROWS) : 1;
    localparam CW = $clog2(CELL_WIDTH);
    localparam CH = $clog2(CELL_HEIGHT);
    localparam GRID_WIDTH = COLUMNS * CELL_WIDTH;
    localparam GRID_HEIGHT = ROWS * CELL_HEIGHT;

    // ---- The text ---------------------------------------------------------------------------
    reg [11:0] cells [0:CELLS-1];
    integer i;
    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, cells);
        else for (i = 0; i < CELLS; i = i + 1) cells[i] = {4'hF, BLANK_CODE};
    end

    // ---- Cycle 0: which cell, and which pixel of its glyph? ---------------------------------
    wire [X_BITS:0] dx = {1'b0, x} - TEXT_X;
    wire [Y_BITS:0] dy = {1'b0, y} - TEXT_Y;
    wire [X_BITS:0] u = dx >> SCALE_SHIFT;
    wire [Y_BITS:0] v = dy >> SCALE_SHIFT;
    wire in_grid = de && !dx[X_BITS] && !dy[Y_BITS] && u < GRID_WIDTH && v < GRID_HEIGHT;
    wire [X_BITS:0] column = u >> CW;
    wire [Y_BITS:0] row = v >> CH;
    // row × COLUMNS as a sum of shifted rows, one per set bit of COLUMNS (120 = four), with the row
    // as narrow as ROWS allows. Written as `*`, Yosys maps it to a DSP48 on 7-series once the grid
    // is large (33 × 120 cells), and nextpnr-xilinx fed that DSP's clock over ordinary wires.
    function [AB-1:0] times_columns(input [RB-1:0] r);
        integer k;
        begin
            times_columns = {AB{1'b0}};
            for (k = 0; k < 31; k = k + 1)
                if (((COLUMNS >> k) & 1) != 0) times_columns = times_columns + ({{AB{1'b0}}, r} << k);
        end
    endfunction
    wire [AB-1:0] address = times_columns(row[RB-1:0]) + column[CB-1:0];

    reg [11:0] cell_word = 12'd0;
    reg inside_1 = 1'b0;
    always @(posedge clk) begin
        if (write) cells[write_address] <= {write_colour, write_code};
        cell_word <= cells[address];
        font_row <= v[CH-1:0];
        font_column <= u[CW-1:0];
        inside_1 <= in_grid;
    end
    assign font_code = cell_word[CODE_BITS-1:0];

    // ---- The font's clocks: the picture, the colour and `in_grid` wait for the glyph ---------
    localparam PW = X_BITS + Y_BITS + 3 + 24;
    localparam STAGES = FONT_LATENCY + 1;
    reg [PW*STAGES-1:0] pass = 0;
    wire [PW*(STAGES+1)-1:0] pass_next = {pass, x, y, de, hsync, vsync, red, green, blue};
    reg [5*FONT_LATENCY-1:0] cell_pipe = 0;
    wire [5*(FONT_LATENCY+1)-1:0] cell_next = {cell_pipe, inside_1, cell_word[11:8]};
    always @(posedge clk) begin
        pass <= pass_next[PW*STAGES-1:0];
        cell_pipe <= cell_next[5*FONT_LATENCY-1:0];
    end
    wire [PW-1:0] below = pass[PW*STAGES-1 -: PW];
    wire hit = cell_pipe[5*FONT_LATENCY-1];
    wire [3:0] colour = cell_pipe[5*FONT_LATENCY-2 -: 4];
    wire [23:0] ink_colour = PALETTE[24*colour +: 24];

    // ---- Cycle FONT_LATENCY + 1: the text over the picture ----------------------------------
    always @(posedge clk) begin
        {x_out, y_out, de_out, hsync_out, vsync_out} <= below[PW-1:24];
        if (hit && font_pixel) {red_out, green_out, blue_out} <= ink_colour;
        else if (hit && BACKGROUND != 0) {red_out, green_out, blue_out} <= BACKGROUND_COLOUR;
        else {red_out, green_out, blue_out} <= below[23:0];
        ink <= hit && font_pixel;
    end
endmodule
