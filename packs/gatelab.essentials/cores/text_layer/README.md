# Text layer

Draws a grid of characters over a video picture: a score, a title, a console. Like
`sprite_layer` it passes the pixel stream through — position, `de`, syncs and the colour below —
and leaves `LATENCY = FONT_LATENCY + 2` clocks later with the text on top, so layers chain.

The grid is `COLUMNS × ROWS` cells at (`TEXT_X`, `TEXT_Y`), each one of the font's cells
(`CELL_WIDTH × CELL_HEIGHT`, powers of two) times `2^SCALE_SHIFT`. The glyphs come from a font
ROM (Project ▸ Add Font ROM…): the layer drives its `code`, `row` and `column` and reads `pixel`.

```verilog
wire [7:0] code;
wire [2:0] row, column;
wire pixel;
font u_font (.clk(pixel_clk), .code(code), .row(row), .column(column), .row_bits(), .pixel(pixel));

text_layer #(.COLUMNS(32), .ROWS(1), .SCALE_SHIFT(1), .TEXT_X(64), .TEXT_Y(440),
             .INIT_FILE("src/title.hex")) u_text (
    .clk(pixel_clk), .x(x), .y(y), .de(de), .hsync(hsync), .vsync(vsync),
    .red(bg_red), .green(bg_green), .blue(bg_blue),
    .write(1'b0), .write_address(5'd0), .write_code(8'd0), .write_colour(4'd0),
    .font_code(code), .font_row(row), .font_column(column), .font_pixel(pixel),
    .x_out(x2), .y_out(y2), .de_out(de2), .hsync_out(hsync2), .vsync_out(vsync2),
    .red_out(red2), .green_out(green2), .blue_out(blue2), .ink());
```

- **The text** lives in the layer's own RAM, one 12-bit word per cell: a colour (an index into
  `PALETTE`, 16 colours, the CGA palette by default with 15 = white) and the character code.
  `INIT_FILE` fills it at start: a hex file with one word per cell, row by row (`F41` is a white
  "A", `E20` a yellow space); its path is relative to the project folder. Without one the cells
  are `BLANK_CODE` (a space) in white.
- **Change it** at any time with `write`: `write_address` = row × `COLUMNS` + column, the code
  and the colour (a score that counts up, a message that types itself).
- **Codes** are the font's: with ASCII or Latin-1 the character's code, with a font of its own
  characters (Add Font ROM ▸ Characters ▸ Custom) its place in the list. `CODE_BITS` is the
  reader's code width.
- **Background:** pixels without ink show the picture below, or `BACKGROUND_COLOUR` inside the
  grid with `BACKGROUND = 1` (a box behind the text). `ink` marks the pixels a character draws.
- `FONT_LATENCY` must be the reader's latency: 1 for GateLab's font ROMs.
