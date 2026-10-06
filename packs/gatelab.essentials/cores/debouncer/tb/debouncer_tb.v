// Self-checking testbench for debouncer: a bouncing press and release, and a short spike that
// must not get through. 1 MHz clock, 1 ms: the input must be stable for 1000 cycles.

`timescale 1ns / 1ps

module debouncer_tb;
    reg clk = 1'b0;
    reg in = 1'b0;
    wire out;

    debouncer #(.CLK_HZ(1000000), .MS(1)) dut (.clk(clk), .in(in), .out(out));

    always #500 clk = ~clk;            // 1 MHz

    integer errors = 0;
    integer changes = 0;
    reg last = 1'b0;
    always @(posedge clk) begin
        if (out !== last) changes = changes + 1;
        last = out;
    end

    task bounce(input level);
        integer i;
        begin
            for (i = 0; i < 6; i = i + 1) begin
                in = level; #(37000 + i * 11000);      // 37–92 us
                in = !level; #(23000);
            end
            in = level;
        end
    endtask

    task check(input expected, input integer expected_changes, input [8*40-1:0] what);
        begin
            if (out !== expected || changes != expected_changes) begin
                $display("FAIL: %0s: out = %b after %0d changes, expected %b after %0d", what, out, changes, expected, expected_changes);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("debouncer_tb.vcd");
        $dumpvars(0, debouncer_tb);
        #20000;

        bounce(1'b1);
        #500000;                         // stable for 0.5 ms: not yet
        check(1'b0, 0, "half a debounce time after the press");
        #700000;
        check(1'b1, 1, "after the press settled");

        bounce(1'b0);
        #1200000;
        check(1'b0, 2, "after the release settled");

        // A 0.8 ms spike is shorter than the debounce time.
        in = 1'b1; #800000; in = 1'b0;
        #2000000;
        check(1'b0, 2, "after a short spike");

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
