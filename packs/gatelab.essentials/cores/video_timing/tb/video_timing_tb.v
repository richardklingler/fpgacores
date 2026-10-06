// Self-checking testbench for video_timing in a tiny mode (8×4 active, 15×9 total — neither a power of two, so the counters must wrap by themselves, positive
// horizontal and negative vertical sync): over three frames, every cycle's x, y, active area,
// both syncs and the frame start are compared with a reference count.

`timescale 1ns / 1ps

module video_timing_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    wire hsync, vsync, active, frame_start;
    wire [3:0] x;
    wire [3:0] y;

    video_timing #(
        .H_ACTIVE(8), .H_FRONT(2), .H_SYNC(3), .H_BACK(2),
        .V_ACTIVE(4), .V_FRONT(1), .V_SYNC(2), .V_BACK(2),
        .H_SYNC_POSITIVE(1), .V_SYNC_POSITIVE(0)
    ) dut (.clk(clk), .hsync(hsync), .vsync(vsync), .active(active), .frame_start(frame_start), .x(x), .y(y));

    integer errors = 0;
    integer hx = 0, vy = 0, frames = 0, cycle;

    initial begin
        $dumpfile("video_timing_tb.vcd");
        $dumpvars(0, video_timing_tb);
        @(posedge frame_start);
        for (cycle = 0; cycle < 15 * 9 * 3; cycle = cycle + 1) begin
            #1;
            if (frame_start) frames = frames + 1;
            if (x !== hx || y !== vy) begin $display("FAIL: position (%0d, %0d), expected (%0d, %0d)", x, y, hx, vy); errors = errors + 1; end
            if (active !== (hx < 8 && vy < 4)) begin $display("FAIL: active %b at (%0d, %0d)", active, hx, vy); errors = errors + 1; end
            if (hsync !== (hx >= 10 && hx < 13)) begin $display("FAIL: hsync %b at x %0d", hsync, hx); errors = errors + 1; end
            if (vsync !== !(vy >= 5 && vy < 7)) begin $display("FAIL: vsync %b at y %0d", vsync, vy); errors = errors + 1; end
            if (frame_start !== (hx == 0 && vy == 0)) begin $display("FAIL: frame_start %b at (%0d, %0d)", frame_start, hx, vy); errors = errors + 1; end
            if (errors > 5) cycle = 1000;
            @(posedge clk);
            hx = hx + 1;
            if (hx == 15) begin hx = 0; vy = (vy + 1) % 9; end
        end
        if (frames != 3) begin $display("FAIL: %0d frame starts in three frames", frames); errors = errors + 1; end
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
