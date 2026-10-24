# Sprite layer

Draws one sprite over a video picture. The picture passes through as a pixel stream — the
position from `video_timing`, `de`, both syncs and the colour below — and leaves
`LATENCY = ROM_LATENCY + 2` clocks later with the sprite on top. Position and timing leave with
it, so layers chain: feed one layer's `*_out` into the next, and the last one draws on top.

The sprite's pixels come from an image ROM (Project ▸ Add Image ROM…). The layer drives the
reader's `x` and `y` through `rom_x`/`rom_y` and takes its colour, `opaque` and `alpha` back:

```verilog
wire [3:0] gx, gy;
wire [7:0] gr, gg, gb;
wire g_opaque;
ghost u_ghost (.clk(pixel_clk), .frame(step), .x(gx), .y(gy),
               .red(gr), .green(gg), .blue(gb), .opaque(g_opaque));

sprite_layer #(.WIDTH(16), .HEIGHT(16), .SCALE_SHIFT(1), .ROM_LATENCY(2)) u_sprite (
    .clk(pixel_clk), .x(x), .y(y), .de(de), .hsync(hsync), .vsync(vsync),
    .red(bg_red), .green(bg_green), .blue(bg_blue),
    .enable(1'b1), .sprite_x(ghost_x), .sprite_y(ghost_y), .flip_x(1'b0), .flip_y(1'b0),
    .rom_x(gx), .rom_y(gy), .rom_red(gr), .rom_green(gg), .rom_blue(gb),
    .rom_opaque(g_opaque), .rom_alpha(8'd0),
    .x_out(x2), .y_out(y2), .de_out(de2), .hsync_out(hsync2), .vsync_out(vsync2),
    .red_out(red2), .green_out(green2), .blue_out(blue2), .covered(ghost_here));
```

- **Place** the sprite with `sprite_x`/`sprite_y` (its top left corner in screen pixels); change
  them at `frame_start` so it never tears. `SCALE_SHIFT` draws each image pixel 2, 4 or 8 times
  as wide and high. `flip_x`/`flip_y` mirror it (a character walking the other way).
- **Animate** with the reader's `frame` input (a sprite sheet: Add Image ROM ▸ Frames); the
  layer doesn't need to know.
- **Transparency:** pixels the reader calls transparent (palette index 0, the mask bit) show the
  picture below. With an alpha format set `ALPHA = 1` and connect `rom_alpha`: the reader's
  premultiplied colour is blended, `out = colour + (255 − alpha) × below / 255`, rounded, which
  takes three 8 × 8 multipliers (DSP blocks where the family has them).
- **Collisions:** `covered` is high on the output pixels the sprite covers; AND two layers'
  `covered` in the same frame to see whether two sprites touch.
- `ROM_LATENCY` must be the reader's latency: 2 for a whole image or a sprite sheet, 3 for tiles
  (the generated module's header says it).

Several sprites are several layers, each with its own reader (a ROM can be added twice, or as a
copy with another name). The order of the chain is the drawing order.
