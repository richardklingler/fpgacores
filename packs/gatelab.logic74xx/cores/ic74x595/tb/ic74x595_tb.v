// Self-checking testbench for ic74x595: 800 steps of pseudo-random shift clocks, latch clocks,
// clears and output enables against a reference shift register and latch; the outputs float while
// OE_n is high, QH_prime never does.

`timescale 1ns / 1ps

module ic74x595_tb;
    reg ser = 0, srclk = 0, srclr_n = 0, rclk = 0, oe_n = 1;
    wire [7:0] q;
    wire qh_prime;

    ic74x595 dut (.SER(ser), .SRCLK(srclk), .SRCLR_n(srclr_n), .RCLK(rclk), .OE_n(oe_n),
                  .QA(q[0]), .QB(q[1]), .QC(q[2]), .QD(q[3]), .QE(q[4]), .QF(q[5]), .QG(q[6]), .QH(q[7]),
                  .QH_prime(qh_prime));

    reg [7:0] shift = 8'h00, latch = 8'h00;
    reg [15:0] lfsr = 16'hB5C3;
    integer i, errors = 0;

    task check(input [255:0] what);
        if (q !== (oe_n ? 8'bzzzzzzzz : latch) || qh_prime !== shift[7]) begin
            $display("FAIL: %0s: QH..QA=%b QH'=%b, expected %b %b (OE_n=%b, t=%0t)", what, q, qh_prime,
                     oe_n ? 8'bzzzzzzzz : latch, shift[7], oe_n, $time);
            errors = errors + 1;
        end
    endtask

    initial begin
        #5 srclr_n = 1;
        for (i = 0; i < 800; i = i + 1) begin
            lfsr = {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            ser = lfsr[1];
            oe_n = lfsr[6] & lfsr[8];          // enabled most of the time
            #1 check("output enable");
            #2 srclk = 1;                       // a shift every step
            shift = {shift[6:0], ser};
            #1 check("after a shift");
            #2 srclk = 0;
            if (lfsr[4] & lfsr[10]) begin       // a latch clock now and then
                #1 rclk = 1;
                latch = shift;
                #1 check("after a latch");
                #2 rclk = 0;
            end
            if (lfsr[12:11] == 2'b11 && lfsr[3]) begin   // a clear between edges: the latches keep theirs
                #1 srclr_n = 0;
                shift = 8'h00;
                #1 check("clear");
                #2 srclr_n = 1;
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
