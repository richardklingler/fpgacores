// Self-checking testbench for ic74x164: 600 clocks of pseudo-random serial data on both inputs,
// with clears between clock edges, against a reference shift register.

`timescale 1ns / 1ps

module ic74x164_tb;
    reg dsa = 0, dsb = 0, cp = 0, mr_n = 0;
    wire [7:0] q;

    ic74x164 dut (.DSA(dsa), .DSB(dsb), .CP(cp), .MR_n(mr_n),
                  .Q0(q[0]), .Q1(q[1]), .Q2(q[2]), .Q3(q[3]), .Q4(q[4]), .Q5(q[5]), .Q6(q[6]), .Q7(q[7]));

    reg [7:0] expected = 8'h00;
    reg [15:0] lfsr = 16'hACE1;
    integer i, errors = 0;

    task check(input [255:0] what);
        if (q !== expected) begin
            $display("FAIL: %0s: Q7..Q0=%b, expected %b (t=%0t)", what, q, expected, $time);
            errors = errors + 1;
        end
    endtask

    initial begin
        #5 mr_n = 1;
        for (i = 0; i < 600; i = i + 1) begin
            lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            dsa = lfsr[0];
            dsb = lfsr[3] | lfsr[7];   // mostly high, so DSA shows through
            #5 cp = 1;
            expected = {expected[6:0], dsa & dsb};
            #1 check("after a clock");
            #4 cp = 0;
            // Now and then a clear between edges: immediate, without a clock.
            if (lfsr[11:9] == 3'b101) begin
                #2 mr_n = 0;
                expected = 8'h00;
                #1 check("clear");
                #2 mr_n = 1;
            end
        end
        // While MR_n is low, clocks change nothing.
        mr_n = 0; dsa = 1; dsb = 1; expected = 8'h00;
        #5 cp = 1; #5 cp = 0;
        #1 check("clock during clear");
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
