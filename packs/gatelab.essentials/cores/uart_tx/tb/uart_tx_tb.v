// Self-checking testbench for uart_tx: sends bytes back to back and decodes the line bit by bit
// in the middle of each bit time. Prints PASS or every failed check.

`timescale 1ns / 1ps

module uart_tx_tb;
    localparam CLK_HZ = 1000000;
    localparam BAUD = 100000;          // 10 clocks per bit
    localparam CLKS_PER_BIT = 10;
    localparam BYTES = 4;

    reg clk = 1'b0;
    reg [7:0] data = 8'h00;
    reg valid = 1'b0;
    wire ready;
    wire tx;

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (.clk(clk), .data(data), .valid(valid), .ready(ready), .tx(tx));

    always #5 clk = ~clk;

    reg [7:0] message [0:BYTES-1];
    integer errors = 0;
    integer sent = 0;

    // Feed the bytes through the handshake as fast as `ready` allows.
    always @(posedge clk) begin
        if (valid && ready) begin
            sent <= sent + 1;
            if (sent + 1 < BYTES) data <= message[sent + 1];
            else valid <= 1'b0;
        end
    end

    // The receiving side: wait for a start bit, then sample each bit in its middle.
    task receive(output [7:0] byte_out, output framing_ok);
        integer bit_index;
        begin
            @(negedge tx);
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            if (tx !== 1'b0) begin
                $display("FAIL: start bit not low in its middle");
                errors = errors + 1;
            end
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                byte_out[bit_index] = tx;
            end
            repeat (CLKS_PER_BIT) @(posedge clk);
            framing_ok = (tx === 1'b1);
        end
    endtask

    reg [7:0] received;
    reg framing_ok;
    integer n;

    initial begin
        $dumpfile("uart_tx_tb.vcd");
        $dumpvars(0, uart_tx_tb);
        message[0] = 8'h55; message[1] = 8'hA3; message[2] = 8'h00; message[3] = 8'hFF;

        repeat (3) @(posedge clk);
        if (tx !== 1'b1 || ready !== 1'b1) begin
            $display("FAIL: idle line should be high and ready (tx=%b ready=%b)", tx, ready);
            errors = errors + 1;
        end
        data <= message[0];
        valid <= 1'b1;

        for (n = 0; n < BYTES; n = n + 1) begin
            receive(received, framing_ok);
            if (received !== message[n]) begin
                $display("FAIL: byte %0d: received %h, expected %h", n, received, message[n]);
                errors = errors + 1;
            end
            if (!framing_ok) begin
                $display("FAIL: byte %0d: stop bit not high", n);
                errors = errors + 1;
            end
        end

        // After the last byte the line goes idle and stays there.
        repeat (CLKS_PER_BIT * 3) @(posedge clk);
        if (tx !== 1'b1 || ready !== 1'b1) begin
            $display("FAIL: line not idle after the last byte (tx=%b ready=%b)", tx, ready);
            errors = errors + 1;
        end
        if (sent != BYTES) begin
            $display("FAIL: %0d bytes taken by the handshake, expected %0d", sent, BYTES);
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
