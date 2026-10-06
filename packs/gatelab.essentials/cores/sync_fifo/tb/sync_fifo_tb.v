// Self-checking testbench for sync_fifo (8 bits × 4 entries): fill to full, writes while full
// are dropped, drain to empty, reads while empty change nothing, then random traffic checked
// against a reference queue, and a reset.

`timescale 1ns / 1ps

module sync_fifo_tb;
    localparam DEPTH = 4;

    reg clk = 1'b0;
    reg rst = 1'b0;
    reg [7:0] wr_data = 8'd0;
    reg wr_en = 1'b0, rd_en = 1'b0;
    wire full, empty;
    wire [7:0] rd_data;
    wire [2:0] count;

    sync_fifo #(.WIDTH(8), .DEPTH_LOG2(2)) dut (
        .clk(clk), .rst(rst), .wr_data(wr_data), .wr_en(wr_en), .full(full),
        .rd_en(rd_en), .rd_data(rd_data), .empty(empty), .count(count)
    );

    always #5 clk = ~clk;

    integer errors = 0;
    // Reference queue.
    reg [7:0] queue [0:255];
    integer head = 0, tail = 0;
    reg expect_data = 1'b0;
    reg [7:0] expected = 8'd0;
    reg can_read, can_write;
    reg [7:0] held = 8'd0;

    // Drive on the falling edge; check on the rising edge like the design sees it.
    always @(posedge clk) begin
        if (expect_data && rd_data !== expected) begin
            $display("FAIL: read %h, expected %h", rd_data, expected);
            errors = errors + 1;
        end
        else if (!expect_data && !rst && rd_data !== held) begin
            $display("FAIL: rd_data changed to %h without a read (was %h)", rd_data, held);
            errors = errors + 1;
        end
        held = rd_data;
        expect_data = 1'b0;
        if (rst) begin
            head = 0; tail = 0;
        end else begin
            if (count !== tail - head) begin
                $display("FAIL: count %0d, expected %0d", count, tail - head);
                errors = errors + 1;
            end
            if (full !== (tail - head == DEPTH) || empty !== (tail == head)) begin
                $display("FAIL: full=%b empty=%b with %0d entries", full, empty, tail - head);
                errors = errors + 1;
            end
            // Both decided on the state before this edge, as `full` and `empty` are.
            can_read = (tail != head);
            can_write = (tail - head < DEPTH);
            if (rd_en && can_read) begin
                expected = queue[head % 256];
                expect_data = 1'b1;
                head = head + 1;
            end
            if (wr_en && can_write) begin
                queue[tail % 256] = wr_data;
                tail = tail + 1;
            end
        end
    end

    task step(input w, input [7:0] d, input r);
        begin
            @(negedge clk);
            wr_en = w; wr_data = d; rd_en = r;
        end
    endtask

    integer i;
    initial begin
        $dumpfile("sync_fifo_tb.vcd");
        $dumpvars(0, sync_fifo_tb);
        step(0, 0, 0);
        for (i = 0; i < 6; i = i + 1) step(1, 8'h10 + i, 0);   // two too many
        step(0, 0, 0);
        if (!full) begin $display("FAIL: not full after 6 writes"); errors = errors + 1; end
        for (i = 0; i < 6; i = i + 1) step(0, 0, 1);           // two too many
        step(0, 0, 0);
        if (!empty) begin $display("FAIL: not empty after draining"); errors = errors + 1; end

        for (i = 0; i < 400; i = i + 1) step($random % 2, $random, $random % 2);
        step(0, 0, 0);

        // Reset empties it.
        step(1, 8'hAA, 0); step(1, 8'hBB, 0);
        @(negedge clk) begin wr_en = 0; rst = 1; end
        @(negedge clk) rst = 0;
        step(0, 0, 0);
        if (!empty || count != 0) begin $display("FAIL: not empty after reset"); errors = errors + 1; end

        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
