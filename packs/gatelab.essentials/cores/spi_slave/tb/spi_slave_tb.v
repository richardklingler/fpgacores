// Self-checking testbench for spi_slave: a mode-0 master sends three bytes in one CS-low
// transaction (the slave answers with bytes it is handed after each rx_valid), then a second
// transaction that starts with a fresh reply. SCLK is 10 times slower than clk.

`timescale 1ns / 1ps

module spi_slave_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;              // 100 MHz

    reg sclk = 1'b0, cs_n = 1'b1, mosi = 1'b0;
    wire miso;
    wire [7:0] rx_data;
    wire rx_valid;
    reg [7:0] tx_data = 8'h00;

    spi_slave dut (.clk(clk), .sclk(sclk), .cs_n(cs_n), .mosi(mosi), .miso(miso),
                   .rx_data(rx_data), .rx_valid(rx_valid), .tx_data(tx_data));

    integer errors = 0;
    integer valids = 0;
    reg [7:0] replies [0:4];
    reg [7:0] got [0:7];

    // The design under test hands the next reply over after each byte (like user logic would).
    always @(posedge clk) if (rx_valid) begin
        got[valids] = rx_data;
        valids = valids + 1;
        tx_data <= replies[valids];
    end

    localparam HALF = 50;              // SCLK 10 MHz

    task transfer(input [7:0] out_byte, output [7:0] in_byte);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                mosi = out_byte[i];
                #(HALF);
                sclk = 1'b1;
                in_byte[i] = miso;
                #(HALF);
                sclk = 1'b0;
            end
        end
    endtask

    reg [7:0] in_byte;
    initial begin
        $dumpfile("spi_slave_tb.vcd");
        $dumpvars(0, spi_slave_tb);
        replies[0] = 8'h1E; replies[1] = 8'hC4; replies[2] = 8'h07; replies[3] = 8'h80; replies[4] = 8'h00;
        tx_data = replies[0];
        #200;

        // Transaction 1: three bytes.
        cs_n = 1'b0; #(HALF * 2);
        transfer(8'hA6, in_byte); if (in_byte !== 8'h1E) begin $display("FAIL: reply 1 %h, expected 1e", in_byte); errors = errors + 1; end
        transfer(8'h31, in_byte); if (in_byte !== 8'hC4) begin $display("FAIL: reply 2 %h, expected c4", in_byte); errors = errors + 1; end
        transfer(8'hF0, in_byte); if (in_byte !== 8'h07) begin $display("FAIL: reply 3 %h, expected 07", in_byte); errors = errors + 1; end
        #(HALF); cs_n = 1'b1; #(HALF * 4);

        // SCLK while not selected is ignored.
        transfer(8'hFF, in_byte);
        #(HALF * 4);

        // Transaction 2: the reply loaded when CS falls.
        cs_n = 1'b0; #(HALF * 2);
        transfer(8'h0C, in_byte); if (in_byte !== 8'h80) begin $display("FAIL: reply 4 %h, expected 80", in_byte); errors = errors + 1; end
        #(HALF); cs_n = 1'b1; #(HALF * 4);

        if (valids != 4) begin
            $display("FAIL: %0d bytes received, expected 4", valids);
            errors = errors + 1;
        end else if (got[0] !== 8'hA6 || got[1] !== 8'h31 || got[2] !== 8'hF0 || got[3] !== 8'h0C) begin
            $display("FAIL: received %h %h %h %h, expected a6 31 f0 0c", got[0], got[1], got[2], got[3]);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
