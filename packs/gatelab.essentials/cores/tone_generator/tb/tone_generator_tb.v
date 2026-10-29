// Self-checking testbench for tone_generator: every sample of three tones (1/32 of the rate, an odd step, and
// a step that wraps the phase fast) against round(32767 · sin(2π · phase / 2^24)) of the phase before the step,
// within one count (the table's own rounding), and the frequency from the sign changes. Prints PASS or every
// failed check.

`timescale 1ns / 1ps

module tone_generator_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    integer errors = 0;

    reg advance = 1'b0;
    reg [23:0] step = 24'd0;
    wire signed [15:0] sample;
    tone_generator dut (.clk(clk), .advance(advance), .step(step), .sample(sample));

    real pi = 3.14159265358979;
    reg [23:0] phase = 24'd0;
    integer n, k, want, crossings;
    reg signed [15:0] last;
    reg [23:0] steps [0:2];

    initial begin
        steps[0] = 24'h080000;   // 1/32 of the rate
        steps[1] = 24'h01A7C3;   // an odd step
        steps[2] = 24'h7F1235;   // just under half the rate
        for (k = 0; k < 3; k = k + 1) begin
            step = steps[k];
            crossings = 0;
            last = 0;
            for (n = 0; n < 4096; n = n + 1) begin
                @(negedge clk) advance = 1'b1;
                @(negedge clk) advance = 1'b0;
                // The sample of the phase before this step: the table has 256 points.
                want = $rtoi($floor(32767.0 * $sin(2.0 * pi * phase[23:16] / 256.0) + 0.5));
                if (sample - want > 1 || want - sample > 1) begin
                    if (errors < 8) $display("FAIL: step %h, sample %0d is %0d, expected %0d", step, n, sample, want);
                    errors = errors + 1;
                end
                if (n > 0 && ((last < 0) != (sample < 0))) crossings = crossings + 1;
                last = sample;
                phase = phase + step;
            end
            // Two sign changes a period: 4096 samples · step / 2^24 periods.
            if (k == 0 && (crossings < 254 || crossings > 258)) begin
                $display("FAIL: %0d sign changes for 1/32 of the rate (256 expected)", crossings);
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #10000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
