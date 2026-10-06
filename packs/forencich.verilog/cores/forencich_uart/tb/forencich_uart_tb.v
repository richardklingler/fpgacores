// Self-checking testbench for Alex Forencich's uart (packaged by GateLab; this testbench is
// GateLab's, CC0): four bytes through the AXI-Stream interface with txd looped back to rxd, in
// order and unchanged; then a frame with a low stop bit from the testbench must raise
// rx_frame_error and deliver no byte. prescale 2: 16 clocks per bit.

`timescale 1ns / 1ps

module forencich_uart_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;

    reg  [7:0] s_tdata = 8'd0;
    reg        s_tvalid = 1'b0;
    wire       s_tready;
    wire [7:0] m_tdata;
    wire       m_tvalid;
    wire       txd, tx_busy, rx_busy, overrun, frame_error;
    reg        loop = 1'b1;
    reg        tb_rxd = 1'b1;
    wire       rxd = loop ? txd : tb_rxd;

    uart dut (
        .clk(clk), .rst(rst),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(1'b1),
        .rxd(rxd), .txd(txd),
        .tx_busy(tx_busy), .rx_busy(rx_busy), .rx_overrun_error(overrun), .rx_frame_error(frame_error),
        .prescale(16'd2)
    );

    integer errors = 0;
    reg [7:0] message [0:3];
    reg [7:0] got [0:7];
    integer received = 0, sent = 0, frame_errors = 0;

    always @(posedge clk) begin
        if (m_tvalid) begin got[received] = m_tdata; received = received + 1; end
        if (frame_error) frame_errors = frame_errors + 1;
        if (s_tvalid && s_tready) begin
            sent = sent + 1;
            if (sent < 4) s_tdata <= message[sent];
            else s_tvalid <= 1'b0;
        end
    end

    integer n, i;
    initial begin
        $dumpfile("forencich_uart_tb.vcd");
        $dumpvars(0, forencich_uart_tb);
        message[0] = 8'hA6; message[1] = 8'h31; message[2] = 8'h0F; message[3] = 8'hFF;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(negedge clk);
        s_tdata = message[0];
        s_tvalid = 1'b1;
        wait (received == 4);
        for (n = 0; n < 4; n = n + 1)
            if (got[n] !== message[n]) begin
                $display("FAIL: byte %0d: received %h, expected %h", n, got[n], message[n]);
                errors = errors + 1;
            end
        if (frame_errors != 0 || overrun) begin
            $display("FAIL: errors on a clean line (%0d frame errors, overrun %b)", frame_errors, overrun);
            errors = errors + 1;
        end

        // A frame with a low stop bit, 16 clocks per bit.
        repeat (40) @(posedge clk);
        loop = 1'b0;
        tb_rxd = 1'b0; repeat (16) @(posedge clk);                 // start
        for (i = 0; i < 8; i = i + 1) begin tb_rxd = 8'h5C >> i; repeat (16) @(posedge clk); end
        tb_rxd = 1'b0; repeat (16) @(posedge clk);                 // stop bit low
        tb_rxd = 1'b1; repeat (64) @(posedge clk);
        if (frame_errors != 1) begin
            $display("FAIL: %0d frame errors after a low stop bit, expected 1", frame_errors);
            errors = errors + 1;
        end
        if (received != 4) begin
            $display("FAIL: a broken frame delivered a byte");
            errors = errors + 1;
        end

        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
