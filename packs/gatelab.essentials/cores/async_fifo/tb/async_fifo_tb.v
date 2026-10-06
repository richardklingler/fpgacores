// Self-checking testbench for async_fifo (8 bits × 8 entries) between a 100 MHz writer and a
// 37 MHz reader, then the other way round: random bursts on both sides, every word checked in
// order against what was written, nothing read while empty, nothing lost or duplicated, and
// `full` reached when the reader stalls.

`timescale 1ns / 1ps

module async_fifo_tb;
    reg wr_clk = 1'b0, rd_clk = 1'b0;
    reg rst = 1'b1;
    reg [7:0] wr_data = 8'd0;
    reg wr_en = 1'b0, rd_en = 1'b0;
    wire full, empty;
    wire [7:0] rd_data;

    async_fifo #(.WIDTH(8), .DEPTH_LOG2(3)) dut (
        .wr_clk(wr_clk), .wr_rst(rst), .wr_data(wr_data), .wr_en(wr_en), .full(full),
        .rd_clk(rd_clk), .rd_rst(rst), .rd_en(rd_en), .rd_data(rd_data), .empty(empty)
    );

    real wr_half = 5.0, rd_half = 13.5;
    always #(wr_half) wr_clk = ~wr_clk;
    always #(rd_half) rd_clk = ~rd_clk;

    integer errors = 0;
    integer written = 0, read = 0;
    reg [7:0] next_write = 8'd0, next_read = 8'd0;
    reg pending = 1'b0;
    reg [7:0] held = 8'd0;
    reg saw_full = 1'b0;
    integer phase = 0;     // 0: random, 1: reader stalled

    // Writer: counts up, so order and loss are easy to check.
    always @(posedge wr_clk) begin
        if (!rst) begin
            if (wr_en && !full) begin
                written = written + 1;
                next_write = next_write + 1;
            end
            if (full) saw_full = 1'b1;
        end
    end
    always @(negedge wr_clk) begin
        wr_en <= !rst && written < 300 && ($random % 3 != 0);
        wr_data <= next_write;
    end

    // Reader: checks each word the cycle after it was taken.
    always @(posedge rd_clk) begin
        if (pending) begin
            if (rd_data !== next_read) begin
                $display("FAIL: read %h, expected %h (word %0d)", rd_data, next_read, read);
                errors = errors + 1;
            end
            next_read = next_read + 1;
            read = read + 1;
            pending = 1'b0;
        end else if (!rst && rd_data !== held) begin
            $display("FAIL: rd_data changed to %h without a read", rd_data);
            errors = errors + 1;
        end
        held = rd_data;
        if (!rst && rd_en && !empty) pending = 1'b1;
    end
    always @(negedge rd_clk) rd_en <= !rst && phase == 0 && ($random % 2 == 0);

    task run(input real writer_half, input real reader_half);
        begin
            wr_half = writer_half; rd_half = reader_half;
            rst = 1'b1; written = 0; read = 0; next_write = 0; next_read = 0; pending = 0; saw_full = 0; phase = 0;
            #200 rst = 1'b0;
            // The reader stalls for a while: the FIFO must fill and report full.
            #300 phase = 1;
            #600 phase = 0;
            wait (written == 300);
            #5000;
            if (read != written) begin
                $display("FAIL: wrote %0d words, read %0d", written, read);
                errors = errors + 1;
            end
            if (!saw_full) begin
                $display("FAIL: never full while the reader stalled");
                errors = errors + 1;
            end
            if (!empty) begin
                $display("FAIL: not empty at the end");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("async_fifo_tb.vcd");
        $dumpvars(0, async_fifo_tb);
        run(5.0, 13.5);     // fast writer, slow reader
        run(13.5, 5.0);     // slow writer, fast reader
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
