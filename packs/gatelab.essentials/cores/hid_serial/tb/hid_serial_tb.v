// Self-checking testbench for hid_serial: real UART frames (8N1, 10 clocks a bit) of every packet, back to back, and
// what must not count — data bytes before any command, a packet cut short by the next command, an unknown command.
// Checks every event's values and order, the buttons level and all_up. Prints PASS or the failed checks.

`timescale 1ns / 1ps

module hid_serial_tb;
    localparam CLK_HZ = 1_000_000, BAUD = 100_000;
    reg clk = 1'b0;
    always #500 clk = ~clk;

    reg rx = 1'b1;
    wire key_valid, key_up, move_valid, position_valid, wheel_valid, all_up;
    wire [7:0] key_usage;
    wire signed [7:0] move_dx, move_dy, wheel_dz;
    wire [13:0] position_x, position_y;
    wire [2:0] buttons;
    hid_serial #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
        .clk(clk), .rx(rx), .key_valid(key_valid), .key_usage(key_usage), .key_up(key_up),
        .move_valid(move_valid), .move_dx(move_dx), .move_dy(move_dy),
        .position_valid(position_valid), .position_x(position_x), .position_y(position_y),
        .wheel_valid(wheel_valid), .wheel_dz(wheel_dz), .buttons(buttons), .all_up(all_up));

    integer errors = 0;
    task fail(input [8*64-1:0] what);
        begin
            $display("FAIL: %0s", what);
            errors = errors + 1;
        end
    endtask

    // One 8N1 frame: start bit, eight data bits LSB first, stop bit.
    task send(input [7:0] b);
        integer i;
        begin
            rx = 1'b0; repeat (10) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin rx = b[i]; repeat (10) @(posedge clk); end
            rx = 1'b1; repeat (10) @(posedge clk);
        end
    endtask

    // Every event as one 48-bit record: kind, then its values.
    reg [47:0] events [0:63];
    integer n = 0;
    always @(posedge clk) begin
        if (key_valid)      begin events[n] = {8'h01, 7'd0, key_up, key_usage, 24'd0}; n = n + 1; end
        if (move_valid)     begin events[n] = {8'h02, 5'd0, buttons, move_dx, move_dy, 16'd0}; n = n + 1; end
        if (position_valid) begin events[n] = {8'h03, 5'd0, buttons, 2'd0, position_x, 2'd0, position_y}; n = n + 1; end
        if (wheel_valid)    begin events[n] = {8'h04, wheel_dz, 32'd0}; n = n + 1; end
        if (all_up)         begin events[n] = {8'h05, 40'd0}; n = n + 1; end
    end

    integer i;
    reg [47:0] expected [0:63];
    integer expected_n = 0;
    task expect_event(input [47:0] e); begin expected[expected_n] = e; expected_n = expected_n + 1; end endtask

    initial begin
        $dumpfile("hid_serial_tb.vcd");
        $dumpvars(0, hid_serial_tb);
        repeat (20) @(posedge clk);

        send(8'h45);                                   // a data byte before any command: ignored
        send(8'h80); send(8'h04);                      // key A down
        expect_event({8'h01, 7'd0, 1'b0, 8'h04, 24'd0});
        send(8'h83); send(8'h63);                      // key E3 (left Command) up: usage bit 7 in the command byte
        expect_event({8'h01, 7'd0, 1'b1, 8'hE3, 24'd0});
        send(8'h91); send(8'h05); send(8'h7F);         // move +5, -1, left
        expect_event({8'h02, 5'd0, 3'b001, 8'sd5, -8'sd1, 16'd0});
        if (buttons !== 3'b001) fail("buttons after a move with left held");
        send(8'h95); send(8'h41); send(8'h3F);         // move -63, +63, left + middle
        expect_event({8'h02, 5'd0, 3'b101, -8'sd63, 8'sd63, 16'd0});
        send(8'hA2); send(8'h09); send(8'h7F); send(8'h05); send(8'h4F);   // position 1279, 719, right
        expect_event({8'h03, 5'd0, 3'b010, 2'd0, 14'd1279, 2'd0, 14'd719});
        send(8'hB0); send(8'h7D);                      // wheel -3
        expect_event({8'h04, -8'sd3, 32'd0});
        send(8'h91); send(8'h05);                      // a move cut short by the next command: dropped
        send(8'h82); send(8'h28);                      // Return up
        expect_event({8'h01, 7'd0, 1'b1, 8'h28, 24'd0});
        send(8'hFE); send(8'h01); send(8'h02);         // an unknown command and its bytes: ignored
        send(8'hBF);                                   // all up
        expect_event({8'h05, 40'd0});
        repeat (5) @(posedge clk);
        if (buttons !== 3'd0) fail("buttons still held after all up");

        if (n != expected_n) begin
            $display("FAIL: %0d events, expected %0d", n, expected_n);
            errors = errors + 1;
        end
        for (i = 0; i < expected_n && i < n; i = i + 1)
            if (events[i] !== expected[i]) begin
                $display("FAIL: event %0d is %h, expected %h", i, events[i], expected[i]);
                errors = errors + 1;
            end

        if (errors == 0) $display("PASS");
        else $display("FAILED: %0d", errors);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FAIL: watchdog");
        $finish;
    end
endmodule
