// Self-checking testbench for ic74x121: the pulse length, the three ways to trigger it, no
// trigger while A1 and A2 are high, and no retriggering during a pulse.

`timescale 1ns / 1ps

module ic74x121_tb;
    reg a1 = 1, a2 = 1, b = 0;
    wire q, q_n;

    ic74x121 #(.PULSE_NS(100)) dut (.A1(a1), .A2(a2), .B(b), .Q(q), .Q_n(q_n));

    integer errors = 0;
    task check(input expected, input [8*32-1:0] what);
        begin
            if (q !== expected || q_n !== !expected) begin
                $display("FAIL: %0s: Q=%b Q_n=%b, expected Q=%b", what, q, q_n, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        #10 check(0, "idle");
        // B rises while A1 and A2 are high: no pulse.
        b = 1; #10 check(0, "B up with A1 A2 high");
        b = 0; #10;
        // B rises with A1 low.
        a1 = 0; #10 b = 1; #1 check(1, "B up with A1 low");
        #98 check(1, "after 99 ns");
        #2 check(0, "after 101 ns");
        b = 0; a1 = 1; #50;
        // A2 falls while A1 and B are high.
        b = 1; #10 a2 = 0; #1 check(1, "A2 down with B high");
        // Not retriggerable: another trigger edge during the pulse doesn't extend it.
        #30 a2 = 1; #5 a2 = 0; #66 check(0, "no retrigger: ended at 100 ns");
        a2 = 1; b = 0; #50;
        // A1 falls while A2 and B are high.
        b = 1; #10 a1 = 0; #1 check(1, "A1 down with B high");
        #100 check(0, "pulse over");
        if (errors == 0) $display("PASS");
        $finish;
    end

    // A broken model must not hang the simulation.
    initial begin
        #1000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
