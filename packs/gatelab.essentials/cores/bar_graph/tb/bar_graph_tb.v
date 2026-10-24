// Self-checking testbench for bar_graph. A small screen (32 × 26 visible, 40 × 30 in all) is
// scanned for two frames; the values are written through the write port before each frame.
// Graph: 3 bars at (3, 2), 5 pixels wide with gaps of 2, 16 pixels high, series A inset by 1,
// grid every 4 pixels, baseline and background on. The values cover an empty bar, a full one,
// one taller than the graph, B taller than A and A taller than B. Every output pixel (colour,
// covered, and the position and timing passed through) is compared with a reference model that
// computes the slot by division, apart from the RTL's counter.

`timescale 1ns / 1ps

module bar_graph_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    localparam H_TOTAL = 40, H_ACTIVE = 32, V_TOTAL = 30, V_ACTIVE = 26;
    localparam BARS = 3, BAR_X = 3, BAR_Y = 2, BAR_WIDTH = 5, GAP = 2, HEIGHT = 16, INSET = 1, GRID_STEP = 4;
    localparam [23:0] CA = 24'hF0A010, CB = 24'h4060C0, CG = 24'h303030, CL = 24'hB0B0B0, CBG = 24'h0A0A14;

    reg [5:0] x = 0;
    reg [4:0] y = 0;
    reg de = 1'b0, hsync = 1'b0, vsync = 1'b0;
    reg [7:0] red = 0, green = 0, blue = 0;
    reg write = 1'b0;
    reg [2:0] write_address = 0;
    reg [4:0] write_value = 0;

    wire [5:0] x_out;
    wire [4:0] y_out;
    wire de_out, hsync_out, vsync_out, covered;
    wire [7:0] red_out, green_out, blue_out;

    bar_graph #(
        .X_BITS(6), .Y_BITS(5), .BARS(BARS), .BAR_X(BAR_X), .BAR_Y(BAR_Y), .BAR_WIDTH(BAR_WIDTH), .GAP(GAP),
        .HEIGHT(HEIGHT), .VALUE_BITS(5), .INSET(INSET), .GRID_STEP(GRID_STEP), .BASELINE(1), .BACKGROUND(1),
        .COLOUR_A(CA), .COLOUR_B(CB), .GRID_COLOUR(CG), .BASELINE_COLOUR(CL), .BACKGROUND_COLOUR(CBG)
    ) dut (
        .clk(clk), .x(x), .y(y), .de(de), .hsync(hsync), .vsync(vsync), .red(red), .green(green), .blue(blue),
        .write(write), .write_address(write_address), .write_value(write_value),
        .x_out(x_out), .y_out(y_out), .de_out(de_out), .hsync_out(hsync_out), .vsync_out(vsync_out),
        .red_out(red_out), .green_out(green_out), .blue_out(blue_out), .covered(covered)
    );

    // The picture below: every pixel differs.
    function [23:0] below(input integer px, input integer py);
        reg [7:0] mix;
        begin
            mix = 8'h5A ^ (px * 7 + py);
            below = {px[5:0], 2'b10, py[4:0], 3'b011, mix};
        end
    endfunction

    integer value_a [0:BARS-1];
    integer value_b [0:BARS-1];

    // The reference: what pixel (px, py) must show, and whether a bar covers it.
    reg [23:0] want_colour;
    reg want_covered;
    task reference(input integer px, input integer py);
        integer slot, offset, level, width;
        reg in_x, in_y, base, a, b, grid;
        begin
            width = BARS * (BAR_WIDTH + GAP) - GAP;
            in_x = px >= BAR_X && px < BAR_X + width;
            in_y = py >= BAR_Y && py < BAR_Y + HEIGHT;
            base = py == BAR_Y + HEIGHT;
            slot = (px - BAR_X) / (BAR_WIDTH + GAP);
            offset = (px - BAR_X) % (BAR_WIDTH + GAP);
            level = BAR_Y + HEIGHT - 1 - py;
            a = in_x && in_y && offset >= INSET && offset < BAR_WIDTH - INSET && level < value_a[slot];
            b = in_x && in_y && offset < BAR_WIDTH && level < value_b[slot];
            grid = in_x && in_y && (level + 1) % GRID_STEP == 0;
            want_covered = a || b;
            if (a) want_colour = CA;
            else if (b) want_colour = CB;
            else if (in_x && base) want_colour = CL;
            else if (grid) want_colour = CG;
            else if (in_x && (in_y || base)) want_colour = CBG;
            else want_colour = below(px, py);
        end
    endtask

    integer errors = 0, checked = 0;
    // The outputs belong to the pixel three clocks earlier: compare against x_out / y_out.
    always @(posedge clk) begin
        #1;
        if (de_out) begin
            reference(x_out, y_out);
            checked = checked + 1;
            if ({red_out, green_out, blue_out} !== want_colour || covered !== want_covered) begin
                if (errors < 10)
                    $display("FAIL: (%0d, %0d) shows %h covered %b, expected %h covered %b",
                             x_out, y_out, {red_out, green_out, blue_out}, covered, want_colour, want_covered);
                errors = errors + 1;
            end
        end
    end

    // The timing passes through unchanged, three clocks late.
    reg [5:0] x_d [0:2];
    reg [4:0] y_d [0:2];
    reg [2:0] de_d = 3'b000, hs_d = 3'b000, vs_d = 3'b000;
    initial begin x_d[0] = 0; x_d[1] = 0; x_d[2] = 0; y_d[0] = 0; y_d[1] = 0; y_d[2] = 0; end
    always @(posedge clk) begin
        x_d[0] <= x; x_d[1] <= x_d[0]; x_d[2] <= x_d[1];
        y_d[0] <= y; y_d[1] <= y_d[0]; y_d[2] <= y_d[1];
        de_d <= {de_d[1:0], de}; hs_d <= {hs_d[1:0], hsync}; vs_d <= {vs_d[1:0], vsync};
        #1;
        if (x_out !== x_d[2] || y_out !== y_d[2] || de_out !== de_d[2] || hsync_out !== hs_d[2] || vsync_out !== vs_d[2]) begin
            if (errors < 10) $display("FAIL: timing not passed through at (%0d, %0d)", x_d[2], y_d[2]);
            errors = errors + 1;
        end
    end

    task put(input integer series, input integer bar, input integer v);
        begin
            @(negedge clk);
            write = 1'b1; write_address = {series[0], bar[1:0]}; write_value = v;
            @(negedge clk);
            write = 1'b0;
            if (series == 0) value_a[bar] = v; else value_b[bar] = v;
        end
    endtask

    integer frame, px, py;
    initial begin
        for (px = 0; px < BARS; px = px + 1) begin value_a[px] = 0; value_b[px] = 0; end
        for (frame = 0; frame < 2; frame = frame + 1) begin
            if (frame == 0) begin
                put(0, 0, 0);  put(1, 0, 16);   // empty front, full back
                put(0, 1, 7);  put(1, 1, 3);    // A taller than B
                put(0, 2, 20); put(1, 2, 9);    // A taller than the graph
            end else begin
                put(0, 0, 5);  put(1, 0, 1);
                put(0, 1, 0);  put(1, 1, 12);   // B only
                put(0, 2, 16); put(1, 2, 0);
            end
            for (py = 0; py < V_TOTAL; py = py + 1)
                for (px = 0; px < H_TOTAL; px = px + 1) begin
                    @(negedge clk);
                    x = px; y = py;
                    de = px < H_ACTIVE && py < V_ACTIVE;
                    hsync = px >= 34 && px < 37;
                    vsync = py == 27;
                    {red, green, blue} = below(px, py);
                end
        end
        repeat (5) @(negedge clk);
        if (checked != 2 * H_ACTIVE * V_ACTIVE) begin
            $display("FAIL: %0d pixels checked, expected %0d", checked, 2 * H_ACTIVE * V_ACTIVE);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #1_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
