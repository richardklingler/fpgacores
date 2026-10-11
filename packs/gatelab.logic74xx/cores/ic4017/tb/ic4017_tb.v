// Self-checking testbench for ic4017: 500 clocks with inhibits (changed only while CLK is low) and
// resets between edges against a reference count; exactly the one decoded output, and COUT.

`timescale 1ns / 1ps

module ic4017_tb;
    reg clk = 0, inh = 0, rst = 1;
    wire [9:0] q;
    wire cout;

    ic4017 dut (.CLK(clk), .INH(inh), .RST(rst),
                .Q0(q[0]), .Q1(q[1]), .Q2(q[2]), .Q3(q[3]), .Q4(q[4]),
                .Q5(q[5]), .Q6(q[6]), .Q7(q[7]), .Q8(q[8]), .Q9(q[9]), .COUT(cout));

    integer count = 0;
    reg [15:0] lfsr = 16'h93E1;
    integer i, errors = 0;

    task check(input [255:0] what);
        if (q !== (10'b1 << count) || cout !== (count < 5)) begin
            $display("FAIL: %0s: Q9..Q0=%b COUT=%b, expected count %0d (t=%0t)", what, q, cout, count, $time);
            errors = errors + 1;
        end
    endtask

    initial begin
        #1 check("reset");
        rst = 0;
        for (i = 0; i < 500; i = i + 1) begin
            lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            inh = lfsr[3] & lfsr[8];             // inhibited now and then
            #2 clk = 1;
            if (!inh) count = (count + 1) % 10;
            #1 check("after a clock");
            #2 clk = 0;
            if (lfsr[12:10] == 3'b110) begin     // reset between edges
                #1 rst = 1; count = 0;
                #1 check("reset");
                #1 rst = 0;
            end
        end
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
