// Self-checking testbench for spi_master in all four SPI modes: a device model per mode answers
// each byte with its own pattern; both directions are checked byte by byte, the clock's idle
// level, its rate (half period of 4 clocks) and the handshake.

`timescale 1ns / 1ps

// A device in one SPI mode: samples mosi and shifts out miso on the right edges.
module spi_device_model #(parameter CPOL = 0, parameter CPHA = 0) (
    input  wire sclk,
    input  wire mosi,
    output wire miso,
    input  wire [7:0] next_reply,
    output reg  [7:0] received = 8'd0,
    output reg  [3:0] bits = 4'd0
);
    reg [7:0] reply = 8'd0;
    reg [7:0] shift_in = 8'd0;
    reg loaded = 1'b0;
    assign miso = reply[7];
    // The clock just left its idle level. Computed in the block from sclk itself: a continuous
    // assignment could still hold the old value when the block runs.
    reg leading;

    // Load the reply before the first edge of a byte (bits == 0).
    always @(next_reply) if (bits == 0) reply = next_reply;

    always @(sclk) begin
        leading = (sclk != CPOL);
        if ((leading && CPHA == 0) || (!leading && CPHA == 1)) begin
            shift_in = {shift_in[6:0], mosi};
            bits = bits + 1;
            if (bits == 8) begin
                received = shift_in;
                bits = 0;
                reply = next_reply;
            end
        end else if ((!leading && CPHA == 0) || (leading && CPHA == 1 && bits != 0)) begin
            reply = {reply[6:0], 1'b0};
        end
    end
endmodule

module spi_master_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    integer errors = 0;

    reg  [7:0] tx [0:3];
    reg  [7:0] reply [0:3];
    initial begin
        // Not bit palindromes, so a reversed bit order shows.
        tx[0] = 8'hA6; tx[1] = 8'h31; tx[2] = 8'h0F; tx[3] = 8'hFF;
        reply[0] = 8'h12; reply[1] = 8'hC4; reply[2] = 8'hF0; reply[3] = 8'h00;
    end

    genvar mode;
    generate
        for (mode = 0; mode < 4; mode = mode + 1) begin : modes
            reg  [7:0] data = 8'd0;
            reg        start = 1'b0;
            wire       ready, done, sclk, mosi, miso;
            wire [7:0] rx_data, device_received;
            wire [3:0] device_bits;
            reg  [7:0] next_reply = 8'd0;

            spi_master #(.CLK_HZ(800), .SPI_HZ(100), .CPOL(mode / 2), .CPHA(mode % 2)) dut (
                .clk(clk), .tx_data(data), .start(start), .ready(ready), .rx_data(rx_data), .done(done),
                .sclk(sclk), .mosi(mosi), .miso(miso)
            );
            spi_device_model #(.CPOL(mode / 2), .CPHA(mode % 2)) device (
                .sclk(sclk), .mosi(mosi), .miso(miso), .next_reply(next_reply),
                .received(device_received), .bits(device_bits)
            );

            // Clock rate: a half period of 4 system clocks (40 ns).
            realtime last_edge = 0;
            always @(sclk) begin
                if (last_edge != 0 && $realtime - last_edge != 40.0 && $realtime - last_edge < 100.0) begin
                    $display("FAIL: mode %0d: SCLK half period %0.0f ns, expected 40", mode, $realtime - last_edge);
                    errors = errors + 1;
                end
                last_edge = $realtime;
            end

            integer n;
            initial begin
                repeat (3) @(posedge clk);
                if (sclk !== mode / 2 || ready !== 1'b1) begin
                    $display("FAIL: mode %0d: idle SCLK %b, ready %b", mode, sclk, ready);
                    errors = errors + 1;
                end
                for (n = 0; n < 4; n = n + 1) begin
                    next_reply = reply[n];
                    @(negedge clk);
                    data = tx[n];
                    start = 1'b1;
                    @(negedge clk);
                    start = 1'b0;
                    if (ready) begin
                        $display("FAIL: mode %0d: still ready after start", mode);
                        errors = errors + 1;
                    end
                    @(posedge done);
                    #1;
                    if (rx_data !== reply[n]) begin
                        $display("FAIL: mode %0d byte %0d: master received %h, expected %h", mode, n, rx_data, reply[n]);
                        errors = errors + 1;
                    end
                    if (device_received !== tx[n] || device_bits !== 0) begin
                        $display("FAIL: mode %0d byte %0d: device received %h (%0d bits left), expected %h", mode, n, device_received, device_bits, tx[n]);
                        errors = errors + 1;
                    end
                    if (sclk !== mode / 2) begin
                        $display("FAIL: mode %0d: SCLK not idle after the byte", mode);
                        errors = errors + 1;
                    end
                    @(posedge clk);
                    #1;
                    if (!ready) begin
                        $display("FAIL: mode %0d: not ready after done", mode);
                        errors = errors + 1;
                    end
                end
            end
        end
    endgenerate

    initial begin
        $dumpfile("spi_master_tb.vcd");
        $dumpvars(0, spi_master_tb);
        #20000;
        if (errors == 0) $display("PASS");
        $finish;
    end
endmodule
