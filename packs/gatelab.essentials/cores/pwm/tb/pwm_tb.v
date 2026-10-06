// Self-checking testbench for pwm (WIDTH 4: 16-cycle periods): the high time of each period for
// several duty values, the extremes, and a duty change in the middle of a period, which must only
// take effect with the next one.

`timescale 1ns / 1ps

module pwm_tb;
    reg clk = 1'b0;
    reg [3:0] duty = 4'd0;
    wire out;

    pwm #(.WIDTH(4)) dut (.clk(clk), .duty(duty), .out(out));

    always #5 clk = ~clk;

    integer errors = 0;

    // High cycles in the next full period (aligned to the counter).
    task measure(output integer high);
        integer i;
        begin
            high = 0;
            for (i = 0; i < 16; i = i + 1) begin
                @(posedge clk); #1;
                if (out) high = high + 1;
            end
        end
    endtask

    task check(input [3:0] value);
        integer high;
        begin
            duty = value;
            measure(high);      // the period that picks the new value up
            measure(high);
            if (high != value) begin
                $display("FAIL: duty %0d: high for %0d of 16 cycles", value, high);
                errors = errors + 1;
            end
        end
    endtask

    integer high;
    integer i;
    initial begin
        $dumpfile("pwm_tb.vcd");
        $dumpvars(0, pwm_tb);
        // Align to a period boundary (the counter is internal: wait for the wrap).
        wait (dut.counter == 4'd15);
        @(posedge clk);
        #1;
        for (i = 0; i < 16; i = i + 1) @(posedge clk);
        check(4'd0); check(4'd1); check(4'd5); check(4'd8); check(4'd15);

        // A change in the middle of a period: that period keeps 15, the next one has 3.
        duty = 4'd15;
        measure(high); measure(high);
        high = 0;
        for (i = 0; i < 16; i = i + 1) begin
            if (i == 8) duty = 4'd3;
            @(posedge clk); #1;
            if (out) high = high + 1;
        end
        if (high != 15) begin
            $display("FAIL: duty changed mid-period: that period high for %0d of 16, expected 15", high);
            errors = errors + 1;
        end
        measure(high);
        if (high != 3) begin
            $display("FAIL: the period after a change to 3: high for %0d of 16", high);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS");
        $finish;
    end

    // A broken design must not hang the simulation.
    initial begin
        #100000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
