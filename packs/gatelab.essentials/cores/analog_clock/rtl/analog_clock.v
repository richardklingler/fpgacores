// Analogue clock layer: draws a round clock face over the picture passing through — an outer
// ring, hour ticks (and, if wanted, minute ticks), hour, minute and second hands and a centre
// cap. The picture arrives as a pixel stream (position, timing and the colour below) and leaves
// LATENCY = 20 clocks later with the clock on top; position and timing leave with it, so layers
// chain like sprite_layer, text_layer and bar_graph.
//
// Every pixel's angle and distance from the centre come from a pipelined CORDIC (adders only,
// 13 stages). The angle is measured clockwise from 12 o'clock in units of 1/16384 of a turn.
// Ticks and the ring are tested by angle and radius; a hand covers a pixel when it is valid
// the hand's length and its distance across the hand (radius × angle difference) is valid half
// the hand's width, so hands have the same width along their length. Three small multiplies
// (radius × angle difference) do that; everything else is adders and comparators.
//
// `hour` (0–23), `minute` and `second` (0–59) may change at any time; the hour hand moves on
// with the minutes and the minute hand with the seconds. A hand of length 0 is not drawn.
// RADIUS up to 1000 pixels.

module analog_clock #(
    parameter X_BITS = 11,
    parameter Y_BITS = 10,
    parameter CENTER_X = 160,
    parameter CENTER_Y = 120,
    parameter RADIUS = 100,
    parameter RING = 4,
    parameter TICK_LENGTH = 12,
    parameter TICK_WIDTH = 4,
    parameter MINUTE_TICKS = 1,
    parameter MINUTE_TICK_WIDTH = 2,
    parameter HOUR_LENGTH = 55,
    parameter HOUR_WIDTH = 8,
    parameter MINUTE_LENGTH = 80,
    parameter MINUTE_WIDTH = 6,
    parameter SECOND_LENGTH = 88,
    parameter SECOND_WIDTH = 2,
    parameter CAP = 6,
    parameter FILL = 0,
    parameter [23:0] FACE_COLOUR = 24'h101820,
    parameter [23:0] RING_COLOUR = 24'hC0C8D0,
    parameter [23:0] TICK_COLOUR = 24'hFFFFFF,
    parameter [23:0] MINUTE_TICK_COLOUR = 24'h808890,
    parameter [23:0] HOUR_COLOUR = 24'hFFFFFF,
    parameter [23:0] MINUTE_COLOUR = 24'hFFFFFF,
    parameter [23:0] SECOND_COLOUR = 24'hFF4040,
    parameter [23:0] CAP_COLOUR = 24'hFF4040
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
    input  wire [4:0] hour,
    input  wire [5:0] minute,
    input  wire [5:0] second,
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
    localparam LATENCY = 20;
    localparam ITERATIONS = 13;
    localparam [13:0] HALF_TURN = 14'd8192;

    // atan(2^-i) in 1/16384 turns.
    function integer atan_step(input integer i);
        case (i)
            0: atan_step = 2048;  1: atan_step = 1209; 2: atan_step = 639; 3: atan_step = 324;
            4: atan_step = 163;   5: atan_step = 81;   6: atan_step = 41;  7: atan_step = 20;
            8: atan_step = 10;    9: atan_step = 5;    10: atan_step = 3;  11: atan_step = 1;
            default: atan_step = 1;
        endcase
    endfunction

    // A radius in pixels as the CORDIC reports it: × 32 (input scale) × 1.64676 (gain).
    function integer scaled(input integer pixels);
        scaled = (pixels * 53961 + 512) / 1024;
    endfunction

    // Half a tick's width in pixels, as an angle at `radius` (1/16384 turns, at least 1).
    function integer tick_angle(input integer width, input integer radius);
        tick_angle = (radius < 1) ? 1 : (((width * 1304 + radius / 2) / radius) < 1 ? 1 : (width * 1304 + radius / 2) / radius);
    endfunction

    function integer max3(input integer a, input integer b, input integer c);
        max3 = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
    endfunction

    // The CORDIC's width: a corner of the box (radius × √2 × the scale) with its sign.
    localparam integer W = $clog2(scaled(RADIUS) * 3 / 2 + 1) + 1;
    // The radius the hands' multiplies need: up to the longest hand, divided by 8.
    localparam integer RB = $clog2(scaled(max3(HOUR_LENGTH, MINUTE_LENGTH, SECOND_LENGTH)) / 8 + 2);

    localparam integer R_FACE = scaled(RADIUS);
    localparam integer R_RING = scaled(RADIUS - RING);
    localparam integer R_TICK = scaled(RADIUS - RING - TICK_LENGTH);
    localparam integer R_MINUTE_TICK = scaled(RADIUS - RING - TICK_LENGTH / 2);
    localparam integer R_HOUR = scaled(HOUR_LENGTH);
    localparam integer R_MINUTE = scaled(MINUTE_LENGTH);
    localparam integer R_SECOND = scaled(SECOND_LENGTH);
    localparam integer R_HANDS = scaled(max3(HOUR_LENGTH, MINUTE_LENGTH, SECOND_LENGTH));
    localparam integer R_CAP = scaled(CAP);
    localparam integer TICK_SPAN = 12 * tick_angle(TICK_WIDTH, RADIUS - RING - TICK_LENGTH / 2);
    localparam integer MINUTE_TICK_SPAN = 60 * tick_angle(MINUTE_TICK_WIDTH, RADIUS - RING - TICK_LENGTH / 4);
    // Across-the-hand limits: (radius / 8) × angle ≤ width × 8588 (half the width in those units).
    localparam integer HOUR_ACROSS = HOUR_WIDTH * 8588;
    localparam integer MINUTE_ACROSS = MINUTE_WIDTH * 8588;
    localparam integer SECOND_ACROSS = SECOND_WIDTH * 8588;

    // ---- The hands' angles (1/16384 turns; × 4369 / 16 for 16384 / 60), by shifts and adds --
    function [17:0] times4369(input [5:0] v);
        times4369 = ({12'd0, v} << 12) + ({12'd0, v} << 8) + ({12'd0, v} << 4) + {12'd0, v};
    endfunction
    // Three registered steps (the time changes once a second; the clocks in between don't matter):
    // the hour's step on the dial, the products, their sums.
    reg [13:0] hour_angle = 0, minute_angle = 0, second_angle = 0;
    reg [5:0] hour_step = 0, minute_q = 0, second_q = 0;
    reg [17:0] second_4369 = 0, minute_4369 = 0, hour_4369 = 0;
    reg [12:0] second_73 = 0, minute_91 = 0;
    always @(posedge clk) begin
        hour_step <= ((hour >= 5'd12) ? hour - 5'd12 : hour) * 3'd5;
        minute_q <= minute;
        second_q <= second;
        second_4369 <= times4369(second_q);
        minute_4369 <= times4369(minute_q);
        hour_4369 <= times4369(hour_step);
        second_73 <= ({7'd0, second_q} << 6) + ({7'd0, second_q} << 3) + {7'd0, second_q};   // up to 4307
        minute_91 <= ({7'd0, minute_q} << 6) + ({7'd0, minute_q} << 4) + ({7'd0, minute_q} << 3) +
                     ({7'd0, minute_q} << 1) + {7'd0, minute_q};
        second_angle <= second_4369 >> 4;
        minute_angle <= (minute_4369 >> 4) + (second_73 >> 4);
        hour_angle <= (hour_4369 >> 4) + (minute_91 >> 2);
    end

    // ---- Stage 1: offset from the centre -------------------------------------------------------
    wire signed [X_BITS+1:0] dx = $signed({2'b00, x}) - CENTER_X;
    wire signed [Y_BITS+1:0] dy = $signed({2'b00, y}) - CENTER_Y;
    reg signed [W-1:0] dx_1 = 0, dy_1 = 0;
    reg in_box_1 = 1'b0;
    // Each stage loads only when its pixel is in the clock's box (its valid bit): outside it the
    // pipeline holds still (less switching, and a simulator has nothing to compute).
    wire in_box = enable && de && dx >= -RADIUS && dx <= RADIUS && dy >= -RADIUS && dy <= RADIUS;
    always @(posedge clk) begin
        in_box_1 <= in_box;
        if (in_box) begin
            dx_1 <= dx <<< 5;
            dy_1 <= dy <<< 5;
        end
    end

    // ---- Stage 2: into the right half-plane (clockwise from 12 o'clock: atan2(dx, -dy)) --------
    // Packed per stage: stage k at [k*W +: W] (arrays written in a loop would be memories to Yosys).
    reg [W*(ITERATIONS+1)-1:0] cx = 0;
    reg [W*(ITERATIONS+1)-1:0] cy = 0;
    reg [14*(ITERATIONS+1)-1:0] cz = 0;
    reg [ITERATIONS:0] valid = 0;   // (`inside` and `within` are SystemVerilog keywords)

    // ---- Stages 3–15: CORDIC vectoring (y driven to 0, the angle collected in z) ---------------
    // Add or subtract as one adder: v ± t = v + (t ^ mask) + carry. One clocked block for all the
    // stages (a simulator then wakes one process a clock, and only that test while the pipeline
    // is empty); the loop unrolls into one adder per stage.
    // Skipping the idle pipeline is for simulators only: in hardware the wide OR in front of every
    // enable would cost speed, and each stage's own valid bit already holds it.
`ifdef SYNTHESIS
    localparam SKIP_IDLE = 0;
`else
    localparam SKIP_IDLE = 1;
`endif
    integer k;
    reg signed [W-1:0] xs, ys, tx, ty;
    reg [13:0] step;
    reg negative;
    always @(posedge clk) begin
        valid <= {valid[ITERATIONS-1:0], in_box_1};
        if (SKIP_IDLE == 0 || in_box_1 || valid[ITERATIONS-1:0] != 0) begin
            // Stage 2, up = -dy: into the right half-plane (up < 0: turn by half a turn).
            if (in_box_1 && dy_1 > 0) begin
                cx[0 +: W] <= dy_1;
                cy[0 +: W] <= -dx_1;
                cz[0 +: 14] <= HALF_TURN;
            end else if (in_box_1) begin
                cx[0 +: W] <= -dy_1;
                cy[0 +: W] <= dx_1;
                cz[0 +: 14] <= 14'd0;
            end
            for (k = 0; k < ITERATIONS; k = k + 1)
                if (valid[k]) begin
                    xs = cx[k*W +: W];
                    ys = cy[k*W +: W];
                    negative = ys[W-1];
                    ty = ys >>> k;
                    tx = xs >>> k;
                    step = atan_step(k);
                    cx[(k+1)*W +: W] <= xs + (ty ^ {W{negative}}) + negative;
                    cy[(k+1)*W +: W] <= ys + (tx ^ {W{!negative}}) + !negative;
                    cz[(k+1)*14 +: 14] <= cz[k*14 +: 14] + (step ^ {14{negative}}) + negative;
                end
        end
    end

    wire [W-1:0] radius = cx[ITERATIONS*W +: W];
    wire [13:0] angle = cz[ITERATIONS*14 +: 14];

    // ---- Stage 16: radial tests, the angle differences and the tick angles ---------------------
    reg in_3 = 1'b0, face_3 = 1'b0, ring_3 = 1'b0, tick_zone_3 = 1'b0, minute_zone_3 = 1'b0, cap_3 = 1'b0;
    reg hour_len_3 = 1'b0, minute_len_3 = 1'b0, second_len_3 = 1'b0;
    reg [RB-1:0] radius_3 = 0;
    reg [13:0] hour_d_3 = 0, minute_d_3 = 0, second_d_3 = 0, around12_3 = 0, around60_3 = 0;

    // ---- Stage 17: tick sectors, |angle difference| within 45° --------------------------------
    function [11:0] near_angle(input [13:0] d);   // {below 45°, |d| as 11 bits}
        reg [13:0] magnitude;
        begin
            magnitude = d[13] ? -d : d;
            near_angle = {magnitude < 14'd2048, magnitude[10:0]};
        end
    endfunction
    wire [11:0] hour_n = near_angle(hour_d_3);
    wire [11:0] minute_n = near_angle(minute_d_3);
    wire [11:0] second_n = near_angle(second_d_3);

    reg in_4 = 1'b0, face_4 = 1'b0, ring_4 = 1'b0, tick_4 = 1'b0, minute_tick_4 = 1'b0, cap_4 = 1'b0;
    reg hour_ok_4 = 1'b0, minute_ok_4 = 1'b0, second_ok_4 = 1'b0;
    reg [RB-1:0] radius_4 = 0;
    reg [10:0] hour_a_4 = 0, minute_a_4 = 0, second_a_4 = 0;

    // ---- Stage 18: across the hands, (radius / 8) × angle difference ---------------------------
    reg in_5 = 1'b0, face_5 = 1'b0, ring_5 = 1'b0, tick_5 = 1'b0, minute_tick_5 = 1'b0, cap_5 = 1'b0;
    reg hour_ok_5 = 1'b0, minute_ok_5 = 1'b0, second_ok_5 = 1'b0;
    reg [RB+10:0] hour_across_5 = 0, minute_across_5 = 0, second_across_5 = 0;

    // ---- Stage 19: on the hands ----------------------------------------------------------------
    reg in_6 = 1'b0, face_6 = 1'b0, ring_6 = 1'b0, tick_6 = 1'b0, minute_tick_6 = 1'b0, cap_6 = 1'b0;
    reg hour_6 = 1'b0, minute_6 = 1'b0, second_6 = 1'b0;

    // Stages 16–19 in one clocked block (one process for a simulator, skipped while idle).
    always @(posedge clk) begin
        if (SKIP_IDLE == 0 || valid[ITERATIONS] || in_3 || in_4 || in_5 || in_6) begin
            in_3 <= valid[ITERATIONS];
            if (valid[ITERATIONS]) begin
                radius_3 <= (radius > R_HANDS) ? {RB{1'b1}} : radius >> 3;
                face_3 <= radius <= R_FACE;
                ring_3 <= RING > 0 && radius > R_RING && radius <= R_FACE;
                tick_zone_3 <= TICK_LENGTH > 0 && radius > R_TICK && radius <= R_RING;
                minute_zone_3 <= MINUTE_TICKS != 0 && TICK_LENGTH > 0 && radius > R_MINUTE_TICK && radius <= R_RING;
                cap_3 <= CAP > 0 && radius <= R_CAP;
                hour_len_3 <= HOUR_LENGTH > 0 && radius <= R_HOUR;
                minute_len_3 <= MINUTE_LENGTH > 0 && radius <= R_MINUTE;
                second_len_3 <= SECOND_LENGTH > 0 && radius <= R_SECOND;
                hour_d_3 <= angle - hour_angle;
                minute_d_3 <= angle - minute_angle;
                second_d_3 <= angle - second_angle;
                around12_3 <= (angle << 3) + (angle << 2);
                around60_3 <= (angle << 6) - (angle << 2);
            end
            in_4 <= in_3;
            if (in_3) begin
                face_4 <= face_3;
                ring_4 <= ring_3;
                cap_4 <= cap_3;
                tick_4 <= tick_zone_3 && (around12_3 < TICK_SPAN || around12_3 > 16384 - TICK_SPAN);
                minute_tick_4 <= minute_zone_3 && (around60_3 < MINUTE_TICK_SPAN || around60_3 > 16384 - MINUTE_TICK_SPAN);
                hour_ok_4 <= hour_len_3 && hour_n[11];
                minute_ok_4 <= minute_len_3 && minute_n[11];
                second_ok_4 <= second_len_3 && second_n[11];
                radius_4 <= radius_3;
                hour_a_4 <= hour_n[10:0];
                minute_a_4 <= minute_n[10:0];
                second_a_4 <= second_n[10:0];
            end
            in_5 <= in_4;
            if (in_4) begin
                {face_5, ring_5, tick_5, minute_tick_5, cap_5} <= {face_4, ring_4, tick_4, minute_tick_4, cap_4};
                {hour_ok_5, minute_ok_5, second_ok_5} <= {hour_ok_4, minute_ok_4, second_ok_4};
                hour_across_5 <= radius_4 * hour_a_4;
                minute_across_5 <= radius_4 * minute_a_4;
                second_across_5 <= radius_4 * second_a_4;
            end
            in_6 <= in_5;
            if (in_5) begin
                {face_6, ring_6, tick_6, minute_tick_6, cap_6} <= {face_5, ring_5, tick_5, minute_tick_5, cap_5};
                hour_6 <= hour_ok_5 && hour_across_5 <= HOUR_ACROSS;
                minute_6 <= minute_ok_5 && minute_across_5 <= MINUTE_ACROSS;
                second_6 <= second_ok_5 && second_across_5 <= SECOND_ACROSS;
            end
        end
    end

    // ---- The picture waits 19 clocks; stage 20 draws on it ------------------------------------
    localparam PW = X_BITS + Y_BITS + 3 + 24;
    localparam STAGES = LATENCY - 1;
    // A ring of STAGES - 1 words, one written a clock and read back with one more register: the
    // picture STAGES clocks late (one write a clock instead of shifting every word — less for a
    // simulator; on the FPGA LUT RAM or registers).
    localparam DEPTH = STAGES - 1;
    reg [PW-1:0] delay [0:DEPTH-1];
    reg [$clog2(DEPTH)-1:0] slot = 0;
    reg [PW-1:0] last = 0;

    // The picture's ring and the topmost feature's colour (worked out only for pixels in the box).
    always @(posedge clk) begin
        delay[slot] <= {x, y, de, hsync, vsync, red, green, blue};
        last <= delay[slot];
        slot <= (slot == DEPTH - 1) ? 0 : slot + 1'b1;
        {x_out, y_out, de_out, hsync_out, vsync_out} <= last[PW-1:24];
        covered <= 1'b0;
        {red_out, green_out, blue_out} <= last[23:0];
        if (in_6) begin
            covered <= 1'b1;
            if (cap_6) {red_out, green_out, blue_out} <= CAP_COLOUR;
            else if (second_6) {red_out, green_out, blue_out} <= SECOND_COLOUR;
            else if (minute_6) {red_out, green_out, blue_out} <= MINUTE_COLOUR;
            else if (hour_6) {red_out, green_out, blue_out} <= HOUR_COLOUR;
            else if (tick_6) {red_out, green_out, blue_out} <= TICK_COLOUR;
            else if (minute_tick_6) {red_out, green_out, blue_out} <= MINUTE_TICK_COLOUR;
            else if (ring_6) {red_out, green_out, blue_out} <= RING_COLOUR;
            else if (FILL != 0 && face_6) {red_out, green_out, blue_out} <= FACE_COLOUR;
            else covered <= 1'b0;
        end
    end
endmodule
