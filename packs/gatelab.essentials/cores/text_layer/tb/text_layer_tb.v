// Self-checking testbench for text_layer. A small screen (32 × 16 visible, 36 × 18 in all) is
// scanned for four frames through two layers in a chain, each with its own font model:
//   t1: 5 × 2 cells of 4 × 4 at (3, 1), ×1, font latency 1, 8-bit codes, the picture shows
//       through where there is no ink;
//   t2: 2 × 3 cells of 8 × 4 at (13, 3), ×2 — half off the right and bottom edges —, font latency
//       2, 4-bit codes (a font of its own characters), BACKGROUND = 1.
// Cells start blank, some are written before the first frame, others in the vertical blanking of
// later frames. Every output pixel (colour, ink, and the position and timing passed through) is
// compared with a reference written apart from the RTL.

`timescale 1ns / 1ps

module text_layer_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    localparam H_TOTAL = 36, H_ACTIVE = 32, V_TOTAL = 18, V_ACTIVE = 16, FRAMES = 4;
    localparam [23:0] BOX = 24'h123456;

    reg [5:0] x = 0;
    reg [4:0] y = 0;
    reg de = 1'b0, hsync = 1'b0, vsync = 1'b0;
    reg [7:0] red = 0, green = 0, blue = 0;

    function [23:0] background(input integer px, input integer py);
        reg [7:0] r, g, b;
        begin
            r = {px[5:0], 2'b01}; g = {py[4:0], 3'b110}; b = 8'h5A ^ (px * 3 + py);
            background = {r, g, b};
        end
    endfunction

    // The CGA palette, as the core's default.
    function [23:0] palette(input [3:0] index);
        case (index)
            0: palette = 24'h000000; 1: palette = 24'h0000AA; 2: palette = 24'h00AA00; 3: palette = 24'h00AAAA;
            4: palette = 24'hAA0000; 5: palette = 24'hAA00AA; 6: palette = 24'hAA5500; 7: palette = 24'hAAAAAA;
            8: palette = 24'h555555; 9: palette = 24'h5555FF; 10: palette = 24'h55FF55; 11: palette = 24'h55FFFF;
            12: palette = 24'hFF5555; 13: palette = 24'hFF55FF; 14: palette = 24'hFFFF55; default: palette = 24'hFFFFFF;
        endcase
    endfunction

    // A font model: one pixel of a glyph, different for every code, row and column.
    function glyph(input integer code, input integer row, input integer column);
        glyph = ((code * 5 + row * 3 + column * 7 + code / 4) % 3) == 0;
    endfunction

    // ---- Writing cells ----------------------------------------------------------------------
    reg w1 = 1'b0, w2 = 1'b0;
    reg [3:0] a1 = 0;
    reg [2:0] a2 = 0;
    reg [7:0] code_1 = 0, code_2 = 0;
    reg [3:0] colour_1 = 0, colour_2 = 0;
    reg [11:0] shadow1 [0:9];
    reg [11:0] shadow2 [0:5];

    // ---- The two layers in a chain, each with its font model --------------------------------
    wire [7:0] code1;
    wire [3:0] code2;
    wire [1:0] row1, column1, row2;
    wire [2:0] column2;
    reg pixel1 = 1'b0, pixel2_1 = 1'b0, pixel2 = 1'b0;
    always @(posedge clk) begin
        pixel1 <= glyph(code1, row1, column1);
        pixel2_1 <= glyph(code2, row2, column2);
        pixel2 <= pixel2_1;
    end

    wire [5:0] x1, x2;
    wire [4:0] y1, y2;
    wire de1, hs1, vs1, de2, hs2, vs2, ink1, ink2;
    wire [7:0] r1, g1, b1, r2, g2, b2;

    text_layer #(.X_BITS(6), .Y_BITS(5), .COLUMNS(5), .ROWS(2), .CELL_WIDTH(4), .CELL_HEIGHT(4), .SCALE_SHIFT(0),
                 .TEXT_X(3), .TEXT_Y(1), .CODE_BITS(8), .FONT_LATENCY(1)) dut1 (
        .clk(clk), .x(x), .y(y), .de(de), .hsync(hsync), .vsync(vsync), .red(red), .green(green), .blue(blue),
        .write(w1), .write_address(a1), .write_code(code_1), .write_colour(colour_1),
        .font_code(code1), .font_row(row1), .font_column(column1), .font_pixel(pixel1),
        .x_out(x1), .y_out(y1), .de_out(de1), .hsync_out(hs1), .vsync_out(vs1), .red_out(r1), .green_out(g1), .blue_out(b1), .ink(ink1));
    text_layer #(.X_BITS(6), .Y_BITS(5), .COLUMNS(2), .ROWS(3), .CELL_WIDTH(8), .CELL_HEIGHT(4), .SCALE_SHIFT(1),
                 .TEXT_X(13), .TEXT_Y(3), .CODE_BITS(4), .FONT_LATENCY(2), .BACKGROUND(1), .BACKGROUND_COLOUR(BOX)) dut2 (
        .clk(clk), .x(x1), .y(y1), .de(de1), .hsync(hs1), .vsync(vs1), .red(r1), .green(g1), .blue(b1),
        .write(w2), .write_address(a2), .write_code(code_2), .write_colour(colour_2),
        .font_code(code2), .font_row(row2), .font_column(column2), .font_pixel(pixel2),
        .x_out(x2), .y_out(y2), .de_out(de2), .hsync_out(hs2), .vsync_out(vs2), .red_out(r2), .green_out(g2), .blue_out(b2), .ink(ink2));

    // ---- Reference --------------------------------------------------------------------------
    localparam LAT1 = 3, LAT2 = 4;
    localparam CYCLES = H_TOTAL * V_TOTAL * FRAMES;
    reg [5:0] in_x [0:CYCLES-1];
    reg [4:0] in_y [0:CYCLES-1];
    reg in_de [0:CYCLES-1];
    reg in_hs [0:CYCLES-1];
    reg in_vs [0:CYCLES-1];

    integer errors = 0, checks = 0, inked1 = 0, inked2 = 0, boxed = 0, t, t1, t2, i;
    integer px, py, u, v, cell_index;
    reg [23:0] want1, want2;
    reg ink_1, ink_2, in1, in2;

    task check(input [8*2-1:0] name, input [23:0] got, input got_ink, input [23:0] want, input want_ink,
               input [5:0] got_x, input [4:0] got_y, input got_de, input got_hs, input got_vs, input integer t0);
        begin
            checks = checks + 1;
            if (got !== want || got_ink !== want_ink) begin
                $display("FAIL: %s at (%0d, %0d): colour %h ink %b, expected %h %b", name, in_x[t0], in_y[t0], got, got_ink, want, want_ink);
                errors = errors + 1;
            end
            if (got_x !== in_x[t0] || got_y !== in_y[t0] || got_de !== in_de[t0] || got_hs !== in_hs[t0] || got_vs !== in_vs[t0]) begin
                $display("FAIL: %s passes (%0d, %0d) de %b hs %b vs %b, expected (%0d, %0d) %b %b %b", name, got_x, got_y, got_de, got_hs, got_vs,
                         in_x[t0], in_y[t0], in_de[t0], in_hs[t0], in_vs[t0]);
                errors = errors + 1;
            end
        end
    endtask

    // What layer 1 draws at (px, py) over `below`.
    task layer1(input integer px, input integer py, input [23:0] below, output [23:0] out, output inked);
        begin
            u = px - 3; v = py - 1;
            in1 = u >= 0 && v >= 0 && u < 20 && v < 8;
            cell_index = (v / 4) * 5 + u / 4;
            inked = in1 && glyph(shadow1[cell_index][7:0], v % 4, u % 4);
            out = inked ? palette(shadow1[cell_index][11:8]) : below;
        end
    endtask

    // What layer 2 draws at (px, py) over `below`.
    task layer2(input integer px, input integer py, input [23:0] below, output [23:0] out, output inked);
        begin
            u = (px - 13) / 2; v = (py - 3) / 2;
            in2 = px >= 13 && py >= 3 && u < 16 && v < 12;
            cell_index = (v / 4) * 2 + u / 8;
            inked = in2 && glyph(shadow2[cell_index][3:0], v % 4, u % 8);
            out = inked ? palette(shadow2[cell_index][11:8]) : in2 ? BOX : below;
        end
    endtask

    // Before the scan a write takes a clock of its own; during it, writes go along with the pixels.
    task write1(input [3:0] address, input [7:0] c, input [3:0] k);
        begin
            w1 = 1'b1; a1 = address; code_1 = c; colour_1 = k;
            @(posedge clk); #1;
            w1 = 1'b0;
            shadow1[address] = {k, c};
        end
    endtask

    task write2(input [2:0] address, input [7:0] c, input [3:0] k);
        begin
            w2 = 1'b1; a2 = address; code_2 = c; colour_2 = k;
            @(posedge clk); #1;
            w2 = 1'b0;
            shadow2[address] = {k, c};
        end
    endtask

    // The writes of frames 1 and 2, in their first blanking line: step k of 0 … 2.
    task schedule(input integer frame, input integer k);
        begin
            case (frame * 4 + k)
                4: begin w1 = 1'b1; a1 = 4; code_1 = "L"; colour_1 = 4'd1; w2 = 1'b1; a2 = 5; code_2 = 8'd14; colour_2 = 4'd2; end
                5: begin w1 = 1'b1; a1 = 9; code_1 = "B"; colour_1 = 4'd15; end
                8: begin w1 = 1'b1; a1 = 0; code_1 = 8'h7E; colour_1 = 4'd6; w2 = 1'b1; a2 = 0; code_2 = 8'd1; colour_2 = 4'd4; end
                9: begin w2 = 1'b1; a2 = 2; code_2 = 8'd7; colour_2 = 4'd8; end
                default: ;
            endcase
        end
    endtask

    initial begin
        $dumpfile("text_layer_tb.vcd");
        $dumpvars(0, text_layer_tb);
        for (i = 0; i < 10; i = i + 1) shadow1[i] = {4'hF, 8'h20};
        for (i = 0; i < 6; i = i + 1) shadow2[i] = {4'hF, 8'h20};
        // Before the first frame: "GATE" in four colours, and two cells of layer 2.
        write1(0, "G", 4'd14); write1(1, "A", 4'd12); write1(2, "T", 4'd10); write1(3, "E", 4'd9);
        write1(7, "!", 4'd3);
        write2(0, 8'd5, 4'd11); write2(3, 8'd9, 4'd13);
        for (t = 0; t < CYCLES + LAT1 + LAT2; t = t + 1) begin
            px = t % H_TOTAL;
            py = (t / H_TOTAL) % V_TOTAL;
            // In the vertical blanking of frames 1 and 2 (no pixel of the grid is on its way), change cells.
            if (t < CYCLES && py == V_ACTIVE && px < 3) schedule(t / (H_TOTAL * V_TOTAL), px);
            if (t < CYCLES) begin
                x = px; y = py;
                de = px < H_ACTIVE && py < V_ACTIVE;
                hsync = px >= 33;
                vsync = py == 17;
                {red, green, blue} = background(px, py);
                in_x[t] = x; in_y[t] = y; in_de[t] = de; in_hs[t] = hsync; in_vs[t] = vsync;
            end
            @(posedge clk);
            #1;
            if (w1) shadow1[a1] = {colour_1, code_1};
            if (w2) shadow2[a2] = {colour_2, code_2};
            w1 = 1'b0; w2 = 1'b0;
            t1 = t - LAT1 + 1;
            t2 = t1 - LAT2;
            if (t1 >= 0 && t1 < CYCLES) begin
                if (in_de[t1]) layer1(in_x[t1], in_y[t1], background(in_x[t1], in_y[t1]), want1, ink_1);
                else begin want1 = background(in_x[t1], in_y[t1]); ink_1 = 1'b0; end
                if (ink_1) inked1 = inked1 + 1;
                check("t1", {r1, g1, b1}, ink1, want1, ink_1, x1, y1, de1, hs1, vs1, t1);
            end
            if (t2 >= 0 && t2 < CYCLES) begin
                if (in_de[t2]) begin
                    layer1(in_x[t2], in_y[t2], background(in_x[t2], in_y[t2]), want1, ink_1);
                    layer2(in_x[t2], in_y[t2], want1, want2, ink_2);
                    if (in2 && !ink_2) boxed = boxed + 1;
                end else begin want2 = background(in_x[t2], in_y[t2]); ink_2 = 1'b0; end
                if (ink_2) inked2 = inked2 + 1;
                check("t2", {r2, g2, b2}, ink2, want2, ink_2, x2, y2, de2, hs2, vs2, t2);
            end
            if (errors > 10) t = CYCLES + 100;
        end
        if (inked1 < 100 || inked2 < 100 || boxed < 100) begin
            $display("FAIL: too little drawn (%0d + %0d inked, %0d background)", inked1, inked2, boxed);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS: %0d pixels checked, %0d + %0d inked, %0d background", checks, inked1, inked2, boxed);
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
