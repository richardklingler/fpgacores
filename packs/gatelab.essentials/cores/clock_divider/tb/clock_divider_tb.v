// Self-checking testbench for clock_divider: 1 MHz down to 1 kHz. Ticks must come exactly every
// 1000 cycles, and the square wave must be high for 500 of every 1000.

`timescale 1ns / 1ps

module clock_divider_tb;
    reg clk = 1'b0;
    wire tick, square;

    clock_divider #(.CLK_HZ(1000000), .HZ(1000)) dut (.clk(clk), .tick(tick), .square(square));

    always #500 clk = ~clk;

    integer errors = 0;
    integer cycle = 0, last_tick = -1, ticks = 0, high = 0;
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (cycle > 2000 && cycle <= 12000 && square) high = high + 1;
        if (tick) begin
            if (last_tick >= 0 && cycle - last_tick != 1000) begin
                $display("FAIL: ticks %0d cycles apart, expected 1000", cycle - last_tick);
                errors = errors + 1;
            end
            last_tick = cycle;
            ticks = ticks + 1;
        end
    end

    initial begin
        $dumpfile("clock_divider_tb.vcd");
        $dumpvars(0, clock_divider_tb);
        repeat (12010) @(posedge clk);   // the first tick comes after 1000 cycles + 1 (registered)
        #1;
        if (ticks != 12) begin
            $display("FAIL: %0d ticks in 12010 cycles, expected 12", ticks);
            errors = errors + 1;
        end
        if (high != 5000) begin
            $display("FAIL: square high for %0d of 10000 cycles, expected 5000", high);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS");
        $finish;
    end

    // A broken design must not hang the simulation.
    initial begin
        #20000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
