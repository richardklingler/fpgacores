// Self-checking testbench for ic74x161: load, count with both enables, hold with either low,
// terminal count, wrap-around and the asynchronous clear.

`timescale 1ns / 1ps

module ic74x161_tb;
    reg cp = 0, mr_n = 1, pe_n = 1, cep = 0, cet = 0;
    reg [3:0] d = 4'd0;
    wire [3:0] q;
    wire tc;

    ic74x161 dut (.CP(cp), .MR_n(mr_n), .PE_n(pe_n), .CEP(cep), .CET(cet),
              .D0(d[0]), .D1(d[1]), .D2(d[2]), .D3(d[3]),
              .Q0(q[0]), .Q1(q[1]), .Q2(q[2]), .Q3(q[3]), .TC(tc));

    integer i, errors = 0;
    task tick; begin #5 cp = 1; #5 cp = 0; #1; end endtask
    task check(input [3:0] count, input terminal, input [8*32-1:0] what);
        begin
            if (q !== count || tc !== terminal) begin
                $display("FAIL: %0s: Q=%0d TC=%b, expected Q=%0d TC=%b", what, q, tc, count, terminal);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        mr_n = 0; tick; mr_n = 1;
        check(4'd0, 0, "reset");
        d = 4'd5; pe_n = 0; tick; pe_n = 1;
        check(4'd5, 0, "loaded 5");
        tick; check(4'd5, 0, "no enables: hold");
        cep = 1; tick; check(4'd5, 0, "CEP only: hold");
        cep = 0; cet = 1; tick; check(4'd5, 0, "CET only: hold");
        // Asynchronous clear: at once, without a clock.
        mr_n = 0; #1;
        check(4'd0, 0, "MR_n low, no clock");
        tick; check(4'd0, 0, "MR_n low holds against the clock");
        mr_n = 1;
        d = 4'd13; pe_n = 0; tick; pe_n = 1;
        check(4'd13, 0, "loaded 13, CET high");
        cep = 1;
        tick; check(4'd14, 0, "count 14");
        tick; check(4'd15, 1, "count 15: TC");
        cet = 0; #1; check(4'd15, 0, "TC follows CET");
        cet = 1; tick; check(4'd0, 0, "wrapped to 0");
        for (i = 1; i <= 15; i = i + 1) tick;
        check(4'd15, 1, "counted around to 15");
        pe_n = 0; d = 4'd9; tick; pe_n = 1;
        check(4'd9, 0, "load beats count");
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
