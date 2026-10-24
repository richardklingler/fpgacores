// Sprite layer: draws one sprite from an image ROM over the picture passing through. The picture
// arrives as a pixel stream (position, timing and the colour below the sprite) and leaves
// LATENCY = ROM_LATENCY + 2 clocks later with the sprite on top; position and timing leave with it,
// so layers chain: the first layer's outputs feed the second, and the last layer draws on top.
//
// The sprite's pixels come from an image ROM reader (Project ▸ Add Image ROM…): the layer drives
// its x and y (`rom_x`, `rom_y`) and reads its colour, `opaque` and (with ALPHA = 1) `alpha` back
// ROM_LATENCY clocks later. A sprite sheet's frame goes straight to the reader. Transparent
// pixels (palette index 0, the mask, or alpha 0) show the picture below. With ALPHA = 1 the
// reader's premultiplied colour is blended: out = colour + (255 - alpha) × below / 255.
//
// `sprite_x`/`sprite_y` place the sprite's top left corner on the screen; SCALE_SHIFT draws each
// image pixel as 2^SCALE_SHIFT × 2^SCALE_SHIFT screen pixels. Change them at the frame start to
// move the sprite without tearing. `covered` marks output pixels the sprite covers (collisions).

module sprite_layer #(
    parameter X_BITS = 11,
    parameter Y_BITS = 10,
    parameter WIDTH = 16,
    parameter HEIGHT = 16,
    parameter SCALE_SHIFT = 0,
    parameter ROM_LATENCY = 2,
    parameter ALPHA = 0
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
    input  wire enable,
    input  wire [X_BITS-1:0] sprite_x,
    input  wire [Y_BITS-1:0] sprite_y,
    input  wire flip_x,
    input  wire flip_y,
    output reg  [$clog2(WIDTH)-1:0] rom_x = 0,
    output reg  [$clog2(HEIGHT)-1:0] rom_y = 0,
    input  wire [7:0] rom_red,
    input  wire [7:0] rom_green,
    input  wire [7:0] rom_blue,
    input  wire rom_opaque,
    input  wire [7:0] rom_alpha,
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
    localparam XB = $clog2(WIDTH);
    localparam YB = $clog2(HEIGHT);

    // ---- Cycle 0: is the pixel inside the sprite, and which image pixel is it? -------------
    wire [X_BITS:0] dx = {1'b0, x} - {1'b0, sprite_x};
    wire [Y_BITS:0] dy = {1'b0, y} - {1'b0, sprite_y};
    wire inside_x = !dx[X_BITS] && (dx >> SCALE_SHIFT) < WIDTH;
    wire inside_y = !dy[Y_BITS] && (dy >> SCALE_SHIFT) < HEIGHT;
    wire [X_BITS:0] u = dx >> SCALE_SHIFT;
    wire [Y_BITS:0] v = dy >> SCALE_SHIFT;
    wire in_sprite = de && enable && inside_x && inside_y;

    reg inside_1 = 1'b0;
    always @(posedge clk) begin
        rom_x <= flip_x ? WIDTH - 1 - u[XB-1:0] : u[XB-1:0];
        rom_y <= flip_y ? HEIGHT - 1 - v[YB-1:0] : v[YB-1:0];
        inside_1 <= in_sprite;
    end

    // ---- The ROM's clocks: the picture and `in_sprite` wait for its colour --------------------
    localparam PW = X_BITS + Y_BITS + 3 + 24;
    localparam STAGES = ROM_LATENCY + 1;
    reg [PW*STAGES-1:0] pass = 0;
    wire [PW*(STAGES+1)-1:0] pass_next = {pass, x, y, de, hsync, vsync, red, green, blue};
    reg [ROM_LATENCY-1:0] inside_pipe = 0;
    wire [ROM_LATENCY:0] inside_next = {inside_pipe, inside_1};
    always @(posedge clk) begin
        pass <= pass_next[PW*STAGES-1:0];
        inside_pipe <= inside_next[ROM_LATENCY-1:0];
    end
    wire [PW-1:0] below = pass[PW*STAGES-1 -: PW];
    wire [7:0] below_red = below[23:16];
    wire [7:0] below_green = below[15:8];
    wire [7:0] below_blue = below[7:0];
    wire hit = inside_pipe[ROM_LATENCY-1];

    // ---- Cycle ROM_LATENCY + 1: the sprite over the picture --------------------------------
    wire [7:0] mixed_red, mixed_green, mixed_blue;
    generate
        if (ALPHA != 0) begin : blend
            // (255 - alpha) × below / 255, rounded: t = product + 128, (t + t / 256) / 256.
            wire [7:0] rest = 8'd255 - rom_alpha;
            wire [16:0] t_red = rest * below_red + 17'd128;
            wire [16:0] t_green = rest * below_green + 17'd128;
            wire [16:0] t_blue = rest * below_blue + 17'd128;
            wire [8:0] s_red = rom_red + ((t_red + (t_red >> 8)) >> 8);
            wire [8:0] s_green = rom_green + ((t_green + (t_green >> 8)) >> 8);
            wire [8:0] s_blue = rom_blue + ((t_blue + (t_blue >> 8)) >> 8);
            assign mixed_red = s_red[8] ? 8'd255 : s_red[7:0];
            assign mixed_green = s_green[8] ? 8'd255 : s_green[7:0];
            assign mixed_blue = s_blue[8] ? 8'd255 : s_blue[7:0];
        end else begin : replace
            assign mixed_red = rom_opaque ? rom_red : below_red;
            assign mixed_green = rom_opaque ? rom_green : below_green;
            assign mixed_blue = rom_opaque ? rom_blue : below_blue;
        end
    endgenerate

    always @(posedge clk) begin
        {x_out, y_out, de_out, hsync_out, vsync_out} <= below[PW-1:24];
        red_out <= hit ? mixed_red : below_red;
        green_out <= hit ? mixed_green : below_green;
        blue_out <= hit ? mixed_blue : below_blue;
        covered <= hit && rom_opaque;
    end
endmodule
