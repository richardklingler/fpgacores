// Self-checking testbench for ws2812 at 20 MHz: three pixels back to back, decoded from the
// line by pulse width the way an LED does; high times and bit periods must be within the
// datasheet tolerances, the colour order on the wire must be green, red, blue, and `idle` must
// rise RESET_US after the last bit — then a second frame starts again at the first LED.

`timescale 1ns / 1ps

module ws2812_tb;
    reg clk = 1'b0;
    always #25 clk = ~clk;             // 20 MHz

    reg  [23:0] rgb = 24'd0;
    reg         valid = 1'b0;
    wire        ready, dout, idle;

    ws2812 #(.CLK_HZ(20000000), .RESET_US(50)) dut (.clk(clk), .rgb(rgb), .valid(valid), .ready(ready), .dout(dout), .idle(idle));

    integer errors = 0;

    // The receiving LED chain: bits by pulse width; a low time of over 50 us ends the frame.
    reg [23:0] received [0:7];
    integer bits = 0, pixels = 0, frames = 0;
    realtime rise = 0, last_rise = 0;
    always @(posedge dout) begin
        if (last_rise != 0 && $realtime - last_rise < 20000) begin
            if ($realtime - last_rise < 1100 || $realtime - last_rise > 1400) begin
                $display("FAIL: bit period %0.0f ns", $realtime - last_rise);
                errors = errors + 1;
            end
        end else if (last_rise != 0) begin
            frames = frames + 1;           // a reset gap: the next bit is LED 0 again
        end
        rise = $realtime;
        last_rise = $realtime;
    end
    realtime last_fall = 0;
    always @(negedge dout) begin
        last_fall = $realtime;
        if (rise != 0) begin
            if ($realtime - rise >= 600) begin
                if ($realtime - rise > 950) begin $display("FAIL: a 1 high for %0.0f ns", $realtime - rise); errors = errors + 1; end
                received[pixels] = {received[pixels][22:0], 1'b1};
            end else begin
                if ($realtime - rise < 250) begin $display("FAIL: a 0 high for %0.0f ns", $realtime - rise); errors = errors + 1; end
                received[pixels] = {received[pixels][22:0], 1'b0};
            end
            bits = bits + 1;
            if (bits == 24) begin bits = 0; pixels = pixels + 1; end
        end
    end

    reg [23:0] colours [0:2];     // {r, g, b}
    integer sent = 0;
    always @(posedge clk) if (valid && ready) begin
        sent <= sent + 1;
        if (sent + 1 < 3) rgb <= colours[sent + 1];
        else valid <= 1'b0;
    end

    initial begin
        $dumpfile("ws2812_tb.vcd");
        $dumpvars(0, ws2812_tb);
        colours[0] = 24'hFF0000;   // red
        colours[1] = 24'h00A501;   // green-ish with a blue LSB
        colours[2] = 24'h12345E;
        #100000;                   // longer than a reset: starts idle
        if (!idle || !ready || dout) begin
            $display("FAIL: not idle at the start (idle %b, ready %b, dout %b)", idle, ready, dout);
            errors = errors + 1;
        end
        @(negedge clk);
        rgb = colours[0];
        valid = 1'b1;
        wait (pixels == 3);
        @(posedge idle);
        // idle after the last bit's 1.25 us slot plus RESET_US.
        if ($realtime - last_fall < 50000 || $realtime - last_fall > 52000) begin
            $display("FAIL: idle %0.0f ns after the last pulse, expected about 50.5 us", $realtime - last_fall);
            errors = errors + 1;
        end
        if (received[0] !== 24'h00FF00 || received[1] !== 24'hA50001 || received[2] !== 24'h34125E) begin
            $display("FAIL: LEDs received %h %h %h (GRB), expected 00ff00 a50001 34125e", received[0], received[1], received[2]);
            errors = errors + 1;
        end

        // A second frame: one pixel.
        @(negedge clk);
        rgb = 24'h0000FF;
        sent = 2;
        valid = 1'b1;
        wait (pixels == 4);
        if (frames != 1 || received[3] !== 24'h0000FF) begin
            $display("FAIL: second frame: %0d reset gaps, pixel %h", frames, received[3]);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
