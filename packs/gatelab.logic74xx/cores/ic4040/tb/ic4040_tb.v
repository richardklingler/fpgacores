// Self-checking testbench for ic4040: 5,000 falling edges (past a wrap of the low stages and well
// into Q12's range) with resets between edges; nothing happens on rising edges.

`timescale 1ns / 1ps

module ic4040_tb;
    reg cp = 1, mr = 1;
    wire [11:0] q;

    ic4040 dut (.CP(cp), .MR(mr), .Q0(q[0]), .Q1(q[1]), .Q2(q[2]), .Q3(q[3]), .Q4(q[4]), .Q5(q[5]), .Q6(q[6]), .Q7(q[7]), .Q8(q[8]), .Q9(q[9]), .Q10(q[10]), .Q11(q[11]));

    reg [11:0] expected = 12'd0;
    integer i, errors = 0;

    task check(input [255:0] what);
        if (q !== expected) begin
            $display("FAIL: %0s: Q=%0d, expected %0d (t=%0t)", what, q, expected, $time);
            errors = errors + 1;
        end
    endtask

    initial begin
        #1 check("reset");
        mr = 0;
        for (i = 0; i < 5000; i = i + 1) begin
            #1 cp = 0;
            expected = expected + 12'd1;
            #1 check("after a falling edge");
            #1 cp = 1;
            #1 check("rising edge");
            if (i == 4321) begin                  // a reset between edges, once
                mr = 1; expected = 12'd0;
                #1 check("reset");
                mr = 0;
            end
        end
        // Up to the wrap: 4,096 more counts from here.
        repeat (4096) begin #1 cp = 0; #1 cp = 1; end
        #1 check("after a full wrap");
        if (errors == 0) $display("PASS");
        $finish;
    end

    // A broken model must not hang the simulation.
    initial begin
        #10000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
