// Self-checking testbench for ic74x74: clocking data in, asynchronous preset and clear (also
// between clock edges), both together, and that the two flip-flops don't influence each other.

`timescale 1ns / 1ps

module ic74x74_tb;
    reg d1 = 0, clk1 = 0, pre1 = 1, clr1 = 1;
    reg d2 = 0, clk2 = 0, pre2 = 1, clr2 = 1;
    wire q1, q1_n, q2, q2_n;

    ic74x74 dut (.D1(d1), .CLK1(clk1), .PRE1_n(pre1), .CLR1_n(clr1), .Q1(q1), .Q1_n(q1_n),
                 .D2(d2), .CLK2(clk2), .PRE2_n(pre2), .CLR2_n(clr2), .Q2(q2), .Q2_n(q2_n));

    integer errors = 0;
    task check(input e1, input e1n, input e2, input e2n, input [8*24-1:0] what);
        begin
            #1;
            if ({q1, q1_n, q2, q2_n} !== {e1, e1n, e2, e2n}) begin
                $display("FAIL: %0s: Q1 Q1_n Q2 Q2_n = %b%b%b%b, expected %b%b%b%b", what, q1, q1_n, q2, q2_n, e1, e1n, e2, e2n);
                errors = errors + 1;
            end
        end
    endtask

    task tick1; begin #5 clk1 = 1; #5 clk1 = 0; end endtask
    task tick2; begin #5 clk2 = 1; #5 clk2 = 0; end endtask

    initial begin
        clr1 = 0; clr2 = 0; #5 clr1 = 1; clr2 = 1;
        check(0, 1, 0, 1, "cleared");
        d1 = 1; tick1;           check(1, 0, 0, 1, "1D=1 clocked");
        d2 = 1;                  check(1, 0, 0, 1, "2D=1, no clock yet");
        tick2;                   check(1, 0, 1, 0, "2D=1 clocked");
        d1 = 0; tick1;           check(0, 1, 1, 0, "1D=0 clocked");
        #3 pre1 = 0;             check(1, 0, 1, 0, "1PRE low, no clock");
        tick1;                   check(1, 0, 1, 0, "1PRE holds against D=0");
        pre1 = 1;                check(1, 0, 1, 0, "1PRE released");
        #3 clr2 = 0;             check(1, 0, 0, 1, "2CLR low, no clock");
        clr2 = 1; pre1 = 0; clr1 = 0; check(1, 1, 0, 1, "1PRE and 1CLR both low");
        pre1 = 1; clr1 = 1;
        d1 = 1; tick1;           check(1, 0, 0, 1, "after both released, 1D=1 clocked");
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
