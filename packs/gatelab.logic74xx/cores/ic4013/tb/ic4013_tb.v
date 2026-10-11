// Self-checking testbench for ic4013: 400 steps per flip-flop of pseudo-random D, clocks, sets and
// resets (between edges) against a reference; both flip-flops at once, on different data, so one
// following the other's inputs fails.

`timescale 1ns / 1ps

module ic4013_tb;
    reg d1 = 0, clk1 = 0, s1 = 0, r1 = 0, d2 = 0, clk2 = 0, s2 = 0, r2 = 0;
    wire q1, q1_n, q2, q2_n;

    ic4013 dut (.D1(d1), .CLK1(clk1), .S1(s1), .R1(r1), .Q1(q1), .Q1_n(q1_n),
                .D2(d2), .CLK2(clk2), .S2(s2), .R2(r2), .Q2(q2), .Q2_n(q2_n));

    reg e1 = 0, e2 = 0;
    reg [15:0] lfsr = 16'h4E7B;
    integer i, errors = 0;

    task check(input [255:0] what);
        if (q1 !== (e1 | (s1 && r1)) || q1_n !== (!e1 | (s1 && r1)) || q2 !== (e2 | (s2 && r2)) || q2_n !== (!e2 | (s2 && r2))) begin
            $display("FAIL: %0s: Q1=%b Q1_n=%b Q2=%b Q2_n=%b, expected Q1=%b Q2=%b (S1 R1=%b%b S2 R2=%b%b, t=%0t)",
                     what, q1, q1_n, q2, q2_n, e1, e2, s1, r1, s2, r2, $time);
            errors = errors + 1;
        end
    endtask

    initial begin
        // Start from a known state.
        r1 = 1; r2 = 1; #1 r1 = 0; r2 = 0;
        for (i = 0; i < 400; i = i + 1) begin
            lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            d1 = lfsr[0]; d2 = ~lfsr[4];
            #2 clk1 = 1; clk2 = lfsr[7];
            e1 = d1; if (clk2) e2 = d2;
            #1 check("after a clock");
            #2 clk1 = 0; clk2 = 0;
            if (lfsr[11:9] == 3'b011) begin        // asynchronous set, reset or both, between edges
                s1 = lfsr[1]; r1 = lfsr[2]; s2 = lfsr[5]; r2 = lfsr[6];
                #1;
                if (r1) e1 = 0; else if (s1) e1 = 1;
                if (r2) e2 = 0; else if (s2) e2 = 1;
                check("set or reset");
                // Set released before reset: after both at once the real part's state is undefined.
                #1 s1 = 0; s2 = 0;
                #1 check("set released");
                #1 r1 = 0; r2 = 0;
                #1 check("released");
            end
        end
        // Directed: set and reset together on each flip-flop (both outputs high), set released first.
        s1 = 1; r1 = 1; e1 = 0; #1 check("both on 1");
        s1 = 0; #1 check("set 1 released"); r1 = 0; #1 check("reset 1 released");
        s2 = 1; r2 = 1; e2 = 0; #1 check("both on 2");
        s2 = 0; #1 check("set 2 released"); r2 = 0; #1 check("reset 2 released");
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
