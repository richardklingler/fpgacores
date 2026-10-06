// Self-checking testbench for uart_rx: bytes back to back, a glitch that isn't a start bit, a
// frame with a low stop bit followed by a break, then a byte that must still arrive. The sender
// runs 2 % slow to show the receiver tolerates clock mismatch. Prints PASS or every failed check.

`timescale 1ns / 1ps

module uart_rx_tb;
    localparam CLK_HZ = 1600000;
    localparam BAUD = 100000;          // 16 clocks per bit
    localparam BIT_NS = 10200;         // the sender's bit: 2 % longer than 10 us

    reg clk = 1'b0;
    reg rx = 1'b1;
    wire [7:0] data;
    wire valid;
    wire frame_error;

    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (.clk(clk), .rx(rx), .data(data), .valid(valid), .frame_error(frame_error));

    always #312.5 clk = ~clk;          // 1.6 MHz

    integer errors = 0;
    integer bytes = 0;
    integer frame_errors = 0;
    reg [7:0] last = 8'h00;

    always @(posedge clk) begin
        if (valid) begin
            bytes = bytes + 1;
            last = data;
        end
        if (frame_error) frame_errors = frame_errors + 1;
        if (valid && frame_error) begin
            $display("FAIL: valid and frame_error together");
            errors = errors + 1;
        end
    end

    task send(input [7:0] value, input stop);
        integer i;
        begin
            rx = 1'b0;
            #(BIT_NS);
            for (i = 0; i < 8; i = i + 1) begin
                rx = value[i];
                #(BIT_NS);
            end
            rx = stop;
            #(BIT_NS);
            rx = 1'b1;
        end
    endtask

    task expect_byte(input [7:0] value, input integer count);
        begin
            #(BIT_NS);
            if (bytes != count) begin
                $display("FAIL: %0d bytes received, expected %0d", bytes, count);
                errors = errors + 1;
            end else if (last !== value) begin
                $display("FAIL: received %h, expected %h", last, value);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("uart_rx_tb.vcd");
        $dumpvars(0, uart_rx_tb);
        #(BIT_NS * 2);

        send(8'h55, 1'b1); expect_byte(8'h55, 1);
        send(8'hA3, 1'b1); expect_byte(8'hA3, 2);
        send(8'h00, 1'b1); expect_byte(8'h00, 3);
        send(8'hFF, 1'b1); expect_byte(8'hFF, 4);

        // A glitch of a fifth of a bit is not a start bit.
        rx = 1'b0; #(BIT_NS / 5); rx = 1'b1;
        #(BIT_NS * 12);
        if (bytes != 4 || frame_errors != 0) begin
            $display("FAIL: a glitch produced a byte or an error (%0d bytes, %0d frame errors)", bytes, frame_errors);
            errors = errors + 1;
        end

        // Low stop bit, then the line stays low (a break): one frame error, no byte.
        send(8'h3C, 1'b0);
        rx = 1'b0; #(BIT_NS * 20); rx = 1'b1;
        #(BIT_NS * 2);
        if (bytes != 4) begin
            $display("FAIL: a frame with a low stop bit or a break produced a byte");
            errors = errors + 1;
        end
        if (frame_errors != 1) begin
            $display("FAIL: %0d frame errors, expected 1", frame_errors);
            errors = errors + 1;
        end

        // Still receiving afterwards.
        send(8'h96, 1'b1); expect_byte(8'h96, 5);

        if (errors == 0) $display("PASS");
        $finish;
    end

    // A broken design must not hang the simulation.
    initial begin
        #5000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
