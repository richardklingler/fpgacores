// Self-checking testbench for analog_clock. A screen of 192 × 184 visible pixels (206 × 192 in
// all) shows a clock of radius 90 at (96, 92) with every feature on (ring, hour and minute ticks,
// three hands, cap, filled face) at four times: 10:10:30, 3:45:05, 23:59:59 and 12:00:00 (all
// hands up, so their order shows). Every output pixel is compared with a reference that uses
// real geometry — sqrt and atan2, not the RTL's CORDIC — and the angles the documentation gives
// for the hands. Pixels within half a pixel of an edge are skipped (the CORDIC rounds); each
// feature must still be met at enough definite pixels in every frame, and the picture below
// and the timing must pass through unchanged.

`timescale 1ns / 1ps

module analog_clock_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    localparam H_TOTAL = 206, H_ACTIVE = 192, V_TOTAL = 192, V_ACTIVE = 184;
    localparam CX = 96, CY = 92, R = 90, RING = 3, TICK_LENGTH = 12, TICK_WIDTH = 3, MINUTE_TICK_WIDTH = 2;
    localparam HOUR_LENGTH = 50, HOUR_WIDTH = 10, MINUTE_LENGTH = 72, MINUTE_WIDTH = 6, SECOND_LENGTH = 80, SECOND_WIDTH = 2, CAP = 7;
    localparam [23:0] C_FACE = 24'h101820, C_RING = 24'hC0C8D0, C_TICK = 24'hFFFF00, C_MTICK = 24'h808890,
                      C_HOUR = 24'h40FF40, C_MINUTE = 24'h4080FF, C_SECOND = 24'hFF4040, C_CAP = 24'hFF00FF;
    localparam LATENCY = 20;
    localparam real K4 = 32.0 * 1.6467602417619722;
    localparam real TURN = 16384.0;
    localparam real PI = 3.14159265358979;

    reg [7:0] x = 0;
    reg [7:0] y = 0;
    reg de = 1'b0, hsync = 1'b0, vsync = 1'b0;
    wire [7:0] red = {x[6:0], 1'b1};
    wire [7:0] green = {y[6:0], 1'b0};
    wire [7:0] blue = 8'h5A;
    reg [4:0] hour = 10;
    reg [5:0] minute = 10, second = 30;

    wire [7:0] x_out, y_out;
    wire de_out, hsync_out, vsync_out, covered;
    wire [7:0] red_out, green_out, blue_out;

    analog_clock #(
        .X_BITS(8), .Y_BITS(8), .CENTER_X(CX), .CENTER_Y(CY), .RADIUS(R), .RING(RING),
        .TICK_LENGTH(TICK_LENGTH), .TICK_WIDTH(TICK_WIDTH), .MINUTE_TICKS(1), .MINUTE_TICK_WIDTH(MINUTE_TICK_WIDTH),
        .HOUR_LENGTH(HOUR_LENGTH), .HOUR_WIDTH(HOUR_WIDTH), .MINUTE_LENGTH(MINUTE_LENGTH), .MINUTE_WIDTH(MINUTE_WIDTH),
        .SECOND_LENGTH(SECOND_LENGTH), .SECOND_WIDTH(SECOND_WIDTH), .CAP(CAP), .FILL(1),
        .FACE_COLOUR(C_FACE), .RING_COLOUR(C_RING), .TICK_COLOUR(C_TICK), .MINUTE_TICK_COLOUR(C_MTICK),
        .HOUR_COLOUR(C_HOUR), .MINUTE_COLOUR(C_MINUTE), .SECOND_COLOUR(C_SECOND), .CAP_COLOUR(C_CAP)
    ) dut (
        .clk(clk), .x(x), .y(y), .de(de), .hsync(hsync), .vsync(vsync), .red(red), .green(green), .blue(blue),
        .enable(1'b1), .hour(hour), .minute(minute), .second(second),
        .x_out(x_out), .y_out(y_out), .de_out(de_out), .hsync_out(hsync_out), .vsync_out(vsync_out),
        .red_out(red_out), .green_out(green_out), .blue_out(blue_out), .covered(covered)
    );

    // ---- The reference: the RTL's documented quantities in real numbers --------------------
    // A radius in pixels as the RTL compares it (its constants are rounded).
    function real limit(input integer pixels);
        limit = ((pixels * 53961 + 512) / 1024) / K4;
    endfunction
    function integer tick_angle(input integer width, input integer radius);
        tick_angle = ((width * 1304 + radius / 2) / radius) < 1 ? 1 : (width * 1304 + radius / 2) / radius;
    endfunction
    function real wrap(input real a);   // into [-TURN/2, TURN/2)
        begin
            wrap = a;
            while (wrap >= TURN / 2) wrap = wrap - TURN;
            while (wrap < -TURN / 2) wrap = wrap + TURN;
        end
    endfunction
    function real absr(input real v);
        absr = v < 0 ? -v : v;
    endfunction

    localparam real EDGE = 0.5;   // pixels: closer to an edge than this is not checked
    real r, a, hour_a, minute_a, second_a;
    reg ambiguous;
    integer cls;   // 0 below, 1 face, 2 ring, 3 minute tick, 4 tick, 5 hour, 6 minute, 7 second, 8 cap

    // Radial test r <= limit(px): sets `ambiguous` when r is within EDGE of the limit.
    function radial(input real radius, input integer pixels);
        begin
            radial = radius <= limit(pixels);
            if (absr(radius - limit(pixels)) < EDGE) ambiguous = 1'b1;
        end
    endfunction
    // Inside a tick sector: the angle × n, modulo a turn, within ±span.
    function sector(input real angle, input integer n, input integer span, input real radius);
        real residual;
        begin
            residual = wrap(angle * n);
            sector = absr(residual) < span;
            // Distance to the sector's edge along the circle, in pixels.
            if (absr(absr(residual) - span) / n * 2.0 * PI / TURN * radius < EDGE) ambiguous = 1'b1;
        end
    endfunction
    // On a hand: within its length, within 45° of it, and radius × angle within half its width.
    function hand(input real radius, input real angle, input real hand_angle, input integer length, input integer width);
        real d, across;
        begin
            d = absr(wrap(angle - hand_angle));
            across = radius * d * 2.0 * PI / TURN;
            hand = length > 0 && radius <= limit(length) && d < 2048 && across <= width / 2.0;
            if (absr(across - width / 2.0) < EDGE && radius <= limit(length) + EDGE) ambiguous = 1'b1;
            if (absr(radius - limit(length)) < EDGE && across <= width / 2.0 + EDGE) ambiguous = 1'b1;
            // The 45° limit near the centre: the CORDIC's angle is a unit or two off.
            if (absr(d - 2048) < 24 && radius <= limit(length) + EDGE && across <= width / 2.0 + EDGE) ambiguous = 1'b1;
        end
    endfunction

    task reference(input integer px, input integer py, output integer klass);
        integer dx, dy;
        reg face, ring, tick, mtick, on_hour, on_minute, on_second, cap;
        begin
            dx = px - CX;
            dy = py - CY;
            ambiguous = 1'b0;
            klass = 0;
            if (dx >= -R && dx <= R && dy >= -R && dy <= R) begin
                r = $sqrt(dx * dx + dy * dy);
                // Reals: Icarus passes a negated integer to $atan2 as unsigned.
                a = $atan2(1.0 * dx, -1.0 * dy) / (2.0 * PI) * TURN;
                if (a < 0) a = a + TURN;
                face = radial(r, R);
                ring = !radial(r, R - RING) && face;
                tick = !radial(r, R - RING - TICK_LENGTH) && radial(r, R - RING) &&
                       sector(a, 12, 12 * tick_angle(TICK_WIDTH, R - RING - TICK_LENGTH / 2), r) ? 1'b1 : 1'b0;
                mtick = !radial(r, R - RING - TICK_LENGTH / 2) && radial(r, R - RING) &&
                        sector(a, 60, 60 * tick_angle(MINUTE_TICK_WIDTH, R - RING - TICK_LENGTH / 4), r) ? 1'b1 : 1'b0;
                cap = radial(r, CAP);
                on_hour = hand(r, a, hour_a, HOUR_LENGTH, HOUR_WIDTH);
                on_minute = hand(r, a, minute_a, MINUTE_LENGTH, MINUTE_WIDTH);
                on_second = hand(r, a, second_a, SECOND_LENGTH, SECOND_WIDTH);
                if (cap) klass = 8;
                else if (on_second) klass = 7;
                else if (on_minute) klass = 6;
                else if (on_hour) klass = 5;
                else if (tick) klass = 4;
                else if (mtick) klass = 3;
                else if (ring) klass = 2;
                else if (face) klass = 1;
                // The CORDIC's angle is rough very near the centre: the cap covers it.
                if (r <= CAP - 0.5) ambiguous = 1'b0;
                else if (r < CAP + 1.5) ambiguous = 1'b1;
            end
        end
    endtask

    function [23:0] class_colour(input integer klass, input [23:0] below);
        case (klass)
            1: class_colour = C_FACE;   2: class_colour = C_RING;  3: class_colour = C_MTICK;
            4: class_colour = C_TICK;   5: class_colour = C_HOUR;  6: class_colour = C_MINUTE;
            7: class_colour = C_SECOND; 8: class_colour = C_CAP;   default: class_colour = below;
        endcase
    endfunction

    // ---- Scan, delay the inputs, compare --------------------------------------------------
    integer hx = 0, vy = 0;
    always @(posedge clk) begin
        hx <= (hx == H_TOTAL - 1) ? 0 : hx + 1;
        if (hx == H_TOTAL - 1) vy <= (vy == V_TOTAL - 1) ? 0 : vy + 1;
    end
    always @(*) begin
        x = hx < H_ACTIVE ? hx : 0;
        y = vy < V_ACTIVE ? vy : 0;
        de = hx < H_ACTIVE && vy < V_ACTIVE;
        hsync = hx >= H_ACTIVE + 4 && hx < H_ACTIVE + 8;
        vsync = vy == V_ACTIVE + 3;
    end

    reg [7:0] x_d [0:LATENCY-1];
    reg [7:0] y_d [0:LATENCY-1];
    reg [LATENCY-1:0] de_d = 0, hs_d = 0, vs_d = 0;
    integer k;
    always @(posedge clk) begin
        x_d[0] <= x; y_d[0] <= y;
        de_d <= {de_d[LATENCY-2:0], de};
        hs_d <= {hs_d[LATENCY-2:0], hsync};
        vs_d <= {vs_d[LATENCY-2:0], vsync};
        for (k = 1; k < LATENCY; k = k + 1) begin
            x_d[k] <= x_d[k - 1];
            y_d[k] <= y_d[k - 1];
        end
    end

    integer errors = 0, checked = 0, skipped = 0, warm = 0, klass;
    integer seen [0:8];
    reg checking = 1'b0;
    reg [23:0] want, below;
    always @(posedge clk) begin
        if (warm < LATENCY + 2) warm <= warm + 1;
        else begin
            if (x_out !== x_d[LATENCY-1] || y_out !== y_d[LATENCY-1] || de_out !== de_d[LATENCY-1] ||
                hsync_out !== hs_d[LATENCY-1] || vsync_out !== vs_d[LATENCY-1]) begin
                errors = errors + 1;
                if (errors < 10) $display("FAIL: timing not passed through (%0d, %0d)", x_d[LATENCY-1], y_d[LATENCY-1]);
            end
            if (checking && de_out) begin
                reference(x_out, y_out, klass);
                below = {x_out[6:0], 1'b1, y_out[6:0], 1'b0, 8'h5A};
                if (ambiguous) skipped = skipped + 1;
                else begin
                    checked = checked + 1;
                    seen[klass] = seen[klass] + 1;
                    want = class_colour(klass, below);
                    if ({red_out, green_out, blue_out} !== want || covered !== (klass != 0)) begin
                        errors = errors + 1;
                        if (errors < 12)
                            $display("FAIL: %0d:%0d:%0d (%0d, %0d) r %0.2f angle %0.1f shows %h covered %b, expected %h (class %0d)",
                                     hour, minute, second, x_out, y_out, r, a, {red_out, green_out, blue_out}, covered, want, klass);
                    end
                end
            end
        end
    end

    // ---- Four frames, the time set in the blanking before each -----------------------------
    task set_time(input integer h, input integer m, input integer s);
        begin
            hour = h; minute = m; second = s;
            // The hands' angles as documented: s × 4369 / 16 (16384 / 60 per step).
            second_a = (s * 4369) / 16;
            minute_a = (m * 4369) / 16 + (s * 73) / 16;
            hour_a = (((h % 12) * 5) * 4369) / 16 + (m * 91) / 4;
        end
    endtask

    task frame;
        integer c;
        begin
            for (c = 0; c < 9; c = c + 1) seen[c] = 0;
            // Wait for the frame to start through the pipeline, then check one whole frame.
            @(posedge clk); while (!(hx == 0 && vy == 0)) @(posedge clk);
            repeat (LATENCY) @(posedge clk);
            checking = 1'b1;
            repeat (H_TOTAL * V_ACTIVE) @(posedge clk);
            checking = 1'b0;
            $display("%0d:%0d:%0d definite pixels per feature: %0d %0d %0d %0d %0d %0d %0d %0d", hour, minute, second,
                     seen[1], seen[2], seen[3], seen[4], seen[5], seen[6], seen[7], seen[8]);
            for (c = 1; c < 9; c = c + 1)
                if (seen[c] < 3 && !(c == 5 || c == 6) || seen[c] < 2) begin
                    errors = errors + 1;
                    $display("FAIL: %0d:%0d:%0d feature %0d met at only %0d definite pixels", hour, minute, second, c, seen[c]);
                end
        end
    endtask

    initial begin
        for (k = 0; k < 9; k = k + 1) seen[k] = 0;
        set_time(10, 10, 30); frame;
        set_time(3, 45, 5);   frame;
        set_time(23, 59, 59); frame;
        set_time(12, 0, 0);   frame;
        if (skipped * 4 > checked) begin
            errors = errors + 1;
            $display("FAIL: %0d pixels skipped near edges, %0d checked", skipped, checked);
        end
        $display("%0d pixels checked, %0d near an edge skipped", checked, skipped);
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #(10 * H_TOTAL * V_TOTAL * 6);
        $display("FAIL: timeout");
        $finish;
    end
endmodule
