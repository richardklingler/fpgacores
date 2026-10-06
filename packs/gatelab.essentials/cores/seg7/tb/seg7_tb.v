// Self-checking testbench for seg7: four digits showing 0x1A7F with the second dot lit, in both
// polarities. Over two refresh cycles every digit must be enabled alone, for the same time, with
// its own pattern and dot.

`timescale 1ns / 1ps

module seg7_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    integer errors = 0;

    wire [6:0] seg_h, seg_l;
    wire dp_h, dp_l;
    wire [3:0] en_h, en_l;

    // 4 digits × 100 Hz at 40 kHz "clock": 100 clocks per digit.
    seg7 #(.CLK_HZ(40000), .DIGITS(4), .REFRESH_HZ(100)) high_active (
        .clk(clk), .value(16'h1A7F), .dots(4'b0010), .segments(seg_h), .dp(dp_h), .digit_enable(en_h));
    seg7 #(.CLK_HZ(40000), .DIGITS(4), .REFRESH_HZ(100), .SEGMENTS_ACTIVE_LOW(1), .DIGITS_ACTIVE_LOW(1)) low_active (
        .clk(clk), .value(16'h1A7F), .dots(4'b0010), .segments(seg_l), .dp(dp_l), .digit_enable(en_l));

    // Three digits: the digit counter must wrap by itself, not at a power of two.
    wire [6:0] seg3;
    wire dp3;
    wire [2:0] en3;
    seg7 #(.CLK_HZ(30000), .DIGITS(3), .REFRESH_HZ(100)) three (
        .clk(clk), .value(12'h1A7), .dots(3'b000), .segments(seg3), .dp(dp3), .digit_enable(en3));
    integer three_on [0:2];

    reg [6:0] expected [0:3];
    integer on_time [0:3];
    integer d, cycle;
    initial begin
        expected[0] = 7'b1110001;   // F
        expected[1] = 7'b0000111;   // 7
        expected[2] = 7'b1110111;   // A
        expected[3] = 7'b0000110;   // 1
        for (d = 0; d < 4; d = d + 1) on_time[d] = 0;
        for (d = 0; d < 3; d = d + 1) three_on[d] = 0;
        $dumpfile("seg7_tb.vcd");
        $dumpvars(0, seg7_tb);
        repeat (5) @(posedge clk);
        for (cycle = 0; cycle < 800; cycle = cycle + 1) begin
            @(posedge clk); #1;
            if (en_l !== ~en_h || seg_l !== ~seg_h || dp_l !== ~dp_h) begin
                $display("FAIL: the active-low outputs aren't the inverse of the active-high ones");
                errors = errors + 1;
            end
            case (en_h)
                4'b0001: d = 0;
                4'b0010: d = 1;
                4'b0100: d = 2;
                4'b1000: d = 3;
                default: begin d = -1; $display("FAIL: digit enables %b: not exactly one digit", en_h); errors = errors + 1; end
            endcase
            if (d >= 0) begin
                on_time[d] = on_time[d] + 1;
                if (seg_h !== expected[d]) begin
                    $display("FAIL: digit %0d shows %b, expected %b", d, seg_h, expected[d]);
                    errors = errors + 1;
                end
                if (dp_h !== (d == 1)) begin
                    $display("FAIL: digit %0d dot %b", d, dp_h);
                    errors = errors + 1;
                end
            end
            case (en3)
                3'b001: three_on[0] = three_on[0] + 1;
                3'b010: three_on[1] = three_on[1] + 1;
                3'b100: three_on[2] = three_on[2] + 1;
                default: begin $display("FAIL: three digits: enables %b", en3); errors = errors + 1; end
            endcase
            if (errors > 5) begin cycle = 800; end
        end
        for (d = 0; d < 4; d = d + 1)
            if (on_time[d] != 200) begin
                $display("FAIL: digit %0d lit for %0d of 800 cycles, expected 200", d, on_time[d]);
                errors = errors + 1;
            end
        // 800 cycles at 100 cycles per digit: 300, 300, 200 or a rotation of it.
        if (three_on[0] + three_on[1] + three_on[2] != 800 || three_on[0] > 300 || three_on[1] > 300 || three_on[2] > 300) begin
            $display("FAIL: three digits lit %0d, %0d, %0d cycles", three_on[0], three_on[1], three_on[2]);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
