// Self-checking testbench for edge_detect: every change of `in` gives exactly one pulse of the
// right kind, one cycle long, and a steady input none.

`timescale 1ns / 1ps

module edge_detect_tb;
    reg clk = 1'b0;
    reg in = 1'b0;
    wire rise, fall;

    edge_detect dut (.clk(clk), .in(in), .rise(rise), .fall(fall));

    always #5 clk = ~clk;

    integer errors = 0;
    integer rises = 0, falls = 0;
    reg rise_last = 1'b0, fall_last = 1'b0;
    always @(posedge clk) begin
        if (rise && !rise_last) rises = rises + 1;
        if (fall && !fall_last) falls = falls + 1;
        if (rise && rise_last) begin $display("FAIL: rise longer than one cycle"); errors = errors + 1; end
        if (fall && fall_last) begin $display("FAIL: fall longer than one cycle"); errors = errors + 1; end
        if (rise && fall) begin $display("FAIL: rise and fall together"); errors = errors + 1; end
        rise_last = rise;
        fall_last = fall;
    end

    // `in` changes after the clock edge, like a register output.
    task set(input level, input integer cycles);
        begin
            @(negedge clk) in = level;
            repeat (cycles) @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("edge_detect_tb.vcd");
        $dumpvars(0, edge_detect_tb);
        repeat (4) @(posedge clk);
        set(1, 5); set(0, 5); set(1, 1); set(0, 1); set(1, 3); set(0, 3);
        repeat (10) @(posedge clk);       // steady: nothing more
        #1;
        if (rises != 3 || falls != 3) begin
            $display("FAIL: %0d rises and %0d falls, expected 3 and 3", rises, falls);
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
