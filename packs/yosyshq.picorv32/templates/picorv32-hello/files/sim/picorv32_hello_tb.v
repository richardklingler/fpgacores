// Self-checking testbench for top.v: runs the firmware on the CPU and decodes the UART line.
// The first line must be "Hello from PicoRV32 on GateLab!", the LEDs must count to 1 after it,
// and nothing may arrive with a broken frame. The design runs with a 1.152 MHz "clock" here, so
// a bit at 115200 baud lasts 10 cycles; writes picorv32_hello_tb.vcd for the waveform viewer.

`timescale 1ns / 1ps

module picorv32_hello_tb;
    localparam LED_COUNT = {{LED_COUNT}};
    localparam [LED_COUNT-1:0] LED_ACTIVE_LOW = {{LED_ACTIVE_LOW}};
    localparam CLKS_PER_BIT = 10;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    wire tx;
    wire [LED_COUNT-1:0] led;

    top #(.CLK_HZ(1152000)) dut (.clk(clk), .uart_tx(tx), .uart_rx(1'b1), .led(led));

    wire [LED_COUNT-1:0] led_on = led ^ LED_ACTIVE_LOW;

    integer errors = 0;
    reg [8*40-1:0] line = 0;
    integer length = 0;
    reg [7:0] received;
    integer i;

    initial begin
        $dumpfile("picorv32_hello_tb.vcd");
        $dumpvars(1, picorv32_hello_tb);
        // Characters until the line feed.
        received = 8'h00;
        while (received != 8'h0A && length < 40) begin
            @(negedge tx);
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                received[i] = tx;
            end
            repeat (CLKS_PER_BIT) @(posedge clk);
            if (tx !== 1'b1) begin $display("FAIL: character %0d has a low stop bit", length); errors = errors + 1; end
            line = {line[8*39-1:0], received};
            length = length + 1;
        end
        // Verilog strings have no \r: the line ends are appended as bytes.
        if (line[8*33-1:0] !== {"Hello from PicoRV32 on GateLab!", 8'h0D, 8'h0A}) begin
            $display("FAIL: received \"%0s\", expected \"Hello from PicoRV32 on GateLab!\" with CR LF", line[8*33-1:16]);
            errors = errors + 1;
        end
        // The LEDs count after the line.
        repeat (200) @(posedge clk);
        if (led_on[0] !== 1'b1) begin $display("FAIL: LEDs %b after the first line, expected the count 1", led_on); errors = errors + 1; end
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #20000000;
        $display("FAIL: timeout (no complete line from the firmware)");
        $finish;
    end
endmodule
