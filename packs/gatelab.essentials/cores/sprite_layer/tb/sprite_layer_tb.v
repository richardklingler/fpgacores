// Self-checking testbench for sprite_layer. A small screen (24 × 12 visible, 28 × 14 in all) is
// scanned for eight frames while the sprites move: at the top left corner, inside, half off the
// right and bottom edges, in the blanking, switched off. Three layers, each with its own ROM
// model and latency, are checked pixel by pixel against a reference written apart from the RTL:
//   a: 5 × 3 sprite (not a power of two), ×1, ROM latency 2, palette-style opaque/transparent;
//   b: 4 × 4 sprite, ×2, ROM latency 3, flipped in x on even frames and in y on odd ones;
//   c: 4 × 2 sprite, ×1, ROM latency 2, ALPHA = 1 with a premultiplied colour and alpha ramp.
// Every output (colour, covered, and the position and timing passed through) is compared.

`timescale 1ns / 1ps

module sprite_layer_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    localparam H_TOTAL = 28, H_ACTIVE = 24, V_TOTAL = 14, V_ACTIVE = 12, FRAMES = 8;

    reg [4:0] x = 0;
    reg [3:0] y = 0;
    reg de = 1'b0, hsync = 1'b0, vsync = 1'b0;
    reg [7:0] red = 0, green = 0, blue = 0;
    reg enable = 1'b1;
    reg [4:0] sx = 0;
    reg [3:0] sy = 0;
    reg flip_x = 1'b0, flip_y = 1'b0;

    // The picture below: a colour from the position, so every pixel differs.
    function [23:0] background(input integer px, input integer py);
        reg [7:0] r, g, b;
        begin
            r = {px[4:0], 3'b101}; g = {py[3:0], 4'b0110}; b = 8'h3C ^ (px + py);
            background = {r, g, b};
        end
    endfunction

    // ---- ROM models: pixel (u, v) → colour, opaque, alpha ------------------------------------
    function [23:0] colour_a(input integer u, input integer v);
        reg [7:0] r, g, b;
        begin
            r = 8'h10 * u + 8'h01; g = 8'h20 * v + 8'h02; b = 8'h80 + u * 3 + v;
            colour_a = {r, g, b};
        end
    endfunction
    function opaque_a(input integer u, input integer v);
        opaque_a = ((u * 2 + v) % 3) != 0;
    endfunction
    function [23:0] colour_b(input integer u, input integer v);
        reg [7:0] r, g, b;
        begin
            r = 8'hF0 - u * 16; g = 8'h11 * v; b = 8'h40 + u * 4 + v;
            colour_b = {r, g, b};
        end
    endfunction
    function opaque_b(input integer u, input integer v);
        opaque_b = !(u == 0 && v == 3) && !(u == 2 && v == 1);
    endfunction
    function [7:0] alpha_c(input integer u, input integer v);
        alpha_c = (u * 2 + v) * 36;    // 0, 36, … 252: transparent, ramp, almost opaque
    endfunction
    function [23:0] colour_c(input integer u, input integer v);
        // Premultiplied: each channel at most alpha — except red at the two most opaque steps,
        // which is too bright on purpose, so the sum must be clipped at 255.
        reg [7:0] a, r, g, b;
        begin
            a = alpha_c(u, v); r = a >= 216 ? 8'd255 : a; g = a / 2; b = a / 3;
            colour_c = {r, g, b};
        end
    endfunction

    // ---- The three layers in a chain: a, then b on top, then c on top -----------------------
    wire [2:0] rax;
    wire [1:0] rbx, ray, rby;
    wire [1:0] rcx;
    wire rcy;
    reg [7:0] a_r = 0, a_g = 0, a_b = 0, b_r = 0, b_g = 0, b_b = 0, c_r = 0, c_g = 0, c_b = 0, c_a = 0;
    reg a_o = 0, b_o = 0, c_o = 0;
    reg [26:0] a_rom_1 = 0, b_rom_1 = 0, b_rom_2 = 0, c_rom_1 = 0;
    reg [7:0] c_alpha_1 = 0;
    // Latency 2: registered address, then registered data.
    always @(posedge clk) begin
        a_rom_1 <= {opaque_a(rax, ray), colour_a(rax, ray), 2'b00};
        {a_o, a_r, a_g, a_b} <= a_rom_1[26:2];
        b_rom_1 <= {opaque_b(rbx, rby), colour_b(rbx, rby), 2'b00};
        b_rom_2 <= b_rom_1;
        {b_o, b_r, b_g, b_b} <= b_rom_2[26:2];
        c_rom_1 <= {alpha_c(rcx, rcy) != 0, colour_c(rcx, rcy), 2'b00};
        c_alpha_1 <= alpha_c(rcx, rcy);
        {c_o, c_r, c_g, c_b} <= c_rom_1[26:2];
        c_a <= c_alpha_1;
    end

    wire [4:0] ax, bx, cx;
    wire [3:0] ay, by, cy;
    wire ade, ahs, avs, bde, bhs, bvs, cde, chs, cvs, a_cov, b_cov, c_cov;
    wire [7:0] ar, ag, ab, br, bg, bb, cr, cg, cb;
    // b and c sit a fixed distance from a's position.
    wire [4:0] bsx = sx + 5'd6;
    wire [3:0] bsy = sy + 4'd1;
    wire [4:0] csx = sx + 5'd1;
    wire [3:0] csy = sy + 4'd4;

    sprite_layer #(.X_BITS(5), .Y_BITS(4), .WIDTH(5), .HEIGHT(3), .SCALE_SHIFT(0), .ROM_LATENCY(2)) dut_a (
        .clk(clk), .x(x), .y(y), .de(de), .hsync(hsync), .vsync(vsync), .red(red), .green(green), .blue(blue),
        .enable(enable), .sprite_x(sx), .sprite_y(sy), .flip_x(1'b0), .flip_y(1'b0),
        .rom_x(rax), .rom_y(ray), .rom_red(a_r), .rom_green(a_g), .rom_blue(a_b), .rom_opaque(a_o), .rom_alpha(8'd0),
        .x_out(ax), .y_out(ay), .de_out(ade), .hsync_out(ahs), .vsync_out(avs), .red_out(ar), .green_out(ag), .blue_out(ab), .covered(a_cov));
    sprite_layer #(.X_BITS(5), .Y_BITS(4), .WIDTH(4), .HEIGHT(4), .SCALE_SHIFT(1), .ROM_LATENCY(3)) dut_b (
        .clk(clk), .x(ax), .y(ay), .de(ade), .hsync(ahs), .vsync(avs), .red(ar), .green(ag), .blue(ab),
        .enable(1'b1), .sprite_x(bsx), .sprite_y(bsy), .flip_x(flip_x), .flip_y(flip_y),
        .rom_x(rbx), .rom_y(rby), .rom_red(b_r), .rom_green(b_g), .rom_blue(b_b), .rom_opaque(b_o), .rom_alpha(8'd0),
        .x_out(bx), .y_out(by), .de_out(bde), .hsync_out(bhs), .vsync_out(bvs), .red_out(br), .green_out(bg), .blue_out(bb), .covered(b_cov));
    sprite_layer #(.X_BITS(5), .Y_BITS(4), .WIDTH(4), .HEIGHT(2), .SCALE_SHIFT(0), .ROM_LATENCY(2), .ALPHA(1)) dut_c (
        .clk(clk), .x(bx), .y(by), .de(bde), .hsync(bhs), .vsync(bvs), .red(br), .green(bg), .blue(bb),
        .enable(1'b1), .sprite_x(csx), .sprite_y(csy), .flip_x(1'b0), .flip_y(1'b0),
        .rom_x(rcx), .rom_y(rcy), .rom_red(c_r), .rom_green(c_g), .rom_blue(c_b), .rom_opaque(c_o), .rom_alpha(c_a),
        .x_out(cx), .y_out(cy), .de_out(cde), .hsync_out(chs), .vsync_out(cvs), .red_out(cr), .green_out(cg), .blue_out(cb), .covered(c_cov));

    // ---- Reference: what each layer makes of the pixel that went in LATENCY clocks earlier ---
    localparam LAT_A = 4, LAT_B = 5, LAT_C = 4;
    localparam CYCLES = H_TOTAL * V_TOTAL * FRAMES;
    reg [4:0] in_x [0:CYCLES-1];
    reg [3:0] in_y [0:CYCLES-1];
    reg in_de [0:CYCLES-1];
    reg in_hs [0:CYCLES-1];
    reg in_vs [0:CYCLES-1];
    reg in_en [0:CYCLES-1];
    reg [4:0] in_sx [0:CYCLES-1];
    reg [3:0] in_sy [0:CYCLES-1];
    reg in_fx [0:CYCLES-1];
    reg in_fy [0:CYCLES-1];

    function [23:0] mix(input [7:0] alpha, input [23:0] colour, input [23:0] below);
        integer channel, value;
        begin
            for (channel = 0; channel < 3; channel = channel + 1) begin
                // colour + round((255 - alpha) × below / 255), at most 255.
                value = colour[8 * channel +: 8] + ((255 - alpha) * below[8 * channel +: 8] * 2 + 255) / 510;
                mix[8 * channel +: 8] = value > 255 ? 255 : value;
            end
        end
    endfunction

    integer errors = 0, checks = 0, covered_a = 0, covered_b = 0, blended = 0, t, t_a, t_b, t_c;
    integer px, py, u, v;
    reg [23:0] want_a, want_b, want_c, below;
    reg cov_a, cov_b, cov_c, in_sprite;

    task check_layer(input [8*1-1:0] name, input [23:0] got, input got_cov, input [23:0] want, input want_cov,
                     input [4:0] got_x, input [3:0] got_y, input got_de, input got_hs, input got_vs, input integer t0);
        begin
            checks = checks + 1;
            if (got !== want || got_cov !== want_cov) begin
                $display("FAIL: layer %s at (%0d, %0d): colour %h covered %b, expected %h %b", name, in_x[t0], in_y[t0], got, got_cov, want, want_cov);
                errors = errors + 1;
            end
            if (got_x !== in_x[t0] || got_y !== in_y[t0] || got_de !== in_de[t0] || got_hs !== in_hs[t0] || got_vs !== in_vs[t0]) begin
                $display("FAIL: layer %s passes (%0d, %0d) de %b hs %b vs %b, expected (%0d, %0d) %b %b %b", name, got_x, got_y, got_de, got_hs, got_vs,
                         in_x[t0], in_y[t0], in_de[t0], in_hs[t0], in_vs[t0]);
                errors = errors + 1;
            end
        end
    endtask

    // Sprite a's top left per frame: corner, inside, half off right and bottom, in the blanking, off.
    function [8:0] position(input integer frame);
        case (frame)
            0: position = {5'd0, 4'd0};
            1: position = {5'd3, 4'd2};
            2: position = {5'd9, 4'd5};
            3: position = {5'd21, 4'd10};
            4: position = {5'd14, 4'd7};
            5: position = {5'd25, 4'd3};
            6: position = {5'd2, 4'd8};
            default: position = {5'd7, 4'd1};
        endcase
    endfunction

    initial begin
        $dumpfile("sprite_layer_tb.vcd");
        $dumpvars(0, sprite_layer_tb);
        for (t = 0; t < CYCLES + LAT_A + LAT_B + LAT_C; t = t + 1) begin
            // Drive the pixel of cycle t.
            if (t < CYCLES) begin
                px = t % H_TOTAL;
                py = (t / H_TOTAL) % V_TOTAL;
                if (px == 0 && py == 0) begin
                    {sx, sy} = position(t / (H_TOTAL * V_TOTAL));
                    enable = (t / (H_TOTAL * V_TOTAL)) != 6;
                    flip_x = (t / (H_TOTAL * V_TOTAL)) % 2 == 0;
                    flip_y = !flip_x;
                end
                x = px; y = py;
                de = px < H_ACTIVE && py < V_ACTIVE;
                hsync = px >= 25;
                vsync = py == 13;
                {red, green, blue} = background(px, py);
                in_x[t] = x; in_y[t] = y; in_de[t] = de; in_hs[t] = hsync; in_vs[t] = vsync;
                in_en[t] = enable; in_sx[t] = sx; in_sy[t] = sy; in_fx[t] = flip_x; in_fy[t] = flip_y;
            end
            @(posedge clk);
            #1;
            // Check each layer's output against the pixel that entered it LATENCY clocks before.
            t_a = t - LAT_A + 1;
            t_b = t_a - LAT_B;
            t_c = t_b - LAT_C;
            if (t_c >= 0 && t_c < CYCLES) begin
                px = in_x[t_c]; py = in_y[t_c];
                below = background(px, py);
                // a
                in_sprite = in_de[t_c] && in_en[t_c] && px >= in_sx[t_c] && px < in_sx[t_c] + 5 && py >= in_sy[t_c] && py < in_sy[t_c] + 3;
                u = px - in_sx[t_c]; v = py - in_sy[t_c];
                cov_a = in_sprite && opaque_a(u, v);
                want_a = cov_a ? colour_a(u, v) : below;
                // b, over a
                in_sprite = in_de[t_c] && px >= in_sx[t_c] + 6 && px < in_sx[t_c] + 6 + 8 && py >= in_sy[t_c] + 1 && py < in_sy[t_c] + 1 + 8;
                u = (px - in_sx[t_c] - 6) / 2; v = (py - in_sy[t_c] - 1) / 2;
                if (in_fx[t_c]) u = 3 - u;
                if (in_fy[t_c]) v = 3 - v;
                cov_b = in_sprite && opaque_b(u, v);
                want_b = cov_b ? colour_b(u, v) : want_a;
                // c, blended over b
                in_sprite = in_de[t_c] && px >= in_sx[t_c] + 1 && px < in_sx[t_c] + 1 + 4 && py >= in_sy[t_c] + 4 && py < in_sy[t_c] + 4 + 2;
                u = px - in_sx[t_c] - 1; v = py - in_sy[t_c] - 4;
                cov_c = in_sprite && alpha_c(u, v) != 0;
                want_c = in_sprite ? mix(alpha_c(u, v), colour_c(u, v), want_b) : want_b;
                if (in_sprite && alpha_c(u, v) != 0 && alpha_c(u, v) != 255) blended = blended + 1;
                if (cov_a) covered_a = covered_a + 1;
                if (cov_b) covered_b = covered_b + 1;
                check_layer("c", {cr, cg, cb}, c_cov, want_c, cov_c, cx, cy, cde, chs, cvs, t_c);
            end
            // Layers a and b on their own (their outputs feed the next layer).
            if (t_a >= 0 && t_a < CYCLES) begin
                px = in_x[t_a]; py = in_y[t_a];
                in_sprite = in_de[t_a] && in_en[t_a] && px >= in_sx[t_a] && px < in_sx[t_a] + 5 && py >= in_sy[t_a] && py < in_sy[t_a] + 3;
                u = px - in_sx[t_a]; v = py - in_sy[t_a];
                cov_a = in_sprite && opaque_a(u, v);
                check_layer("a", {ar, ag, ab}, a_cov, cov_a ? colour_a(u, v) : background(px, py), cov_a, ax, ay, ade, ahs, avs, t_a);
            end
            if (errors > 10) t = CYCLES + 100;
        end
        // The sprites must really have been drawn, in every way.
        if (covered_a < 40 || covered_b < 60 || blended < 20) begin
            $display("FAIL: too little drawn (a %0d, b %0d, blended %0d)", covered_a, covered_b, blended);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS: %0d pixels checked, %0d + %0d covered, %0d blended", checks, covered_a, covered_b, blended);
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
