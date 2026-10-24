// Self-checking testbench for spi_registers: an SPI master (mode 0, MSB first) runs the same set of
// transactions at three SCLK/clk ratios — 8 (the limit), 11 and 23 clocks per bit — and every write
// (address, data, order), every reply and every `done` pulse is checked:
//   1. a write of five bytes at 0x3A5 (auto-increment), first reply ID;
//   2. a write across the top of the address space (0xFFE, 0xFFF, 0x000);
//   3. a read: ID, ID, VERSION, status, 0x00;
//   4. an unknown command: no write, no done;
//   5. a write with an address but no data: no write, no done;
//   6. two writes back to back with a short CS high time.

`timescale 1ns / 1ps

module spi_registers_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    reg sclk = 1'b0, cs_n = 1'b1, mosi = 1'b0;
    wire miso;
    wire wr, done;
    wire [11:0] wr_addr;
    wire [7:0] wr_data;
    reg [7:0] status = 8'hC6;

    spi_registers #(.ADDR_BITS(12), .ID(8'h47), .VERSION(8'h1D)) dut (
        .clk(clk), .sclk(sclk), .cs_n(cs_n), .mosi(mosi), .miso(miso),
        .wr(wr), .wr_addr(wr_addr), .wr_data(wr_data), .done(done), .status(status)
    );

    // Every write and done pulse, in order.
    reg [11:0] log_addr [0:63];
    reg [7:0]  log_data [0:63];
    integer writes = 0, dones = 0;
    always @(posedge clk) begin
        if (wr) begin
            log_addr[writes] <= wr_addr;
            log_data[writes] <= wr_data;
            writes <= writes + 1;
        end
        if (done) dones <= dones + 1;
    end

    integer errors = 0;
    integer half_ns = 40;

    task check(input condition, input [8*48:1] what);
        if (!condition) begin
            $display("FAIL (%0d ns per bit): %0s", 2 * half_ns, what);
            errors = errors + 1;
        end
    endtask

    reg [7:0] replies [0:15];
    integer b;
    task byte_out(input [7:0] out, output [7:0] in);
        begin
            for (b = 7; b >= 0; b = b - 1) begin
                mosi = out[b];
                #(half_ns) sclk = 1'b1;
                in[b] = miso;
                #(half_ns) sclk = 1'b0;
            end
        end
    endtask

    reg [7:0] tx [0:15];
    integer count, k;
    task transaction(input integer n, input integer gap_ns);
        begin
            cs_n = 1'b0;
            #(half_ns);
            for (k = 0; k < n; k = k + 1) byte_out(tx[k], replies[k]);
            #(half_ns) cs_n = 1'b1;
            #(gap_ns);
        end
    endtask

    task wait_idle; #(400); endtask

    integer ratio, w0, d0;
    initial begin
        for (ratio = 0; ratio < 3; ratio = ratio + 1) begin
            half_ns = ratio == 0 ? 40 : ratio == 1 ? 55 : 115;   // 8, 11, 23 clocks per bit
            #(137);   // a different SCLK phase against clk each round

            // 1. Five bytes at 0x3A5.
            w0 = writes; d0 = dones;
            tx[0] = 8'h01; tx[1] = 8'h03; tx[2] = 8'hA5;
            tx[3] = 8'h13; tx[4] = 8'hC4; tx[5] = 8'h7E; tx[6] = 8'h00; tx[7] = 8'hFF;
            transaction(8, 200); wait_idle;
            check(replies[0] == 8'h47, "1: first reply is not ID");
            check(writes - w0 == 5, "1: not five writes");
            for (k = 0; k < 5; k = k + 1) begin
                check(log_addr[w0 + k] == 12'h3A5 + k, "1: wrong address");
                check(log_data[w0 + k] == tx[3 + k], "1: wrong data");
            end
            check(dones - d0 == 1, "1: done not once");

            // 2. Across the top: 0xFFE, 0xFFF, 0x000.
            w0 = writes;
            tx[0] = 8'h01; tx[1] = 8'h0F; tx[2] = 8'hFE; tx[3] = 8'h5A; tx[4] = 8'h96; tx[5] = 8'h3B;
            transaction(6, 200); wait_idle;
            check(writes - w0 == 3, "2: not three writes");
            check(log_addr[w0] == 12'hFFE && log_addr[w0 + 1] == 12'hFFF && log_addr[w0 + 2] == 12'h000, "2: no wrap");
            check(log_data[w0 + 2] == 8'h3B, "2: wrong data after the wrap");

            // 3. Read: ID, ID, VERSION, status, 0.
            w0 = writes; d0 = dones;
            status = 8'hC6 ^ ratio;
            tx[0] = 8'h02; tx[1] = 8'hAA; tx[2] = 8'h55; tx[3] = 8'h0F; tx[4] = 8'hF0;
            transaction(5, 200); wait_idle;
            check(replies[0] == 8'h47 && replies[1] == 8'h47, "3: no ID");
            check(replies[2] == 8'h1D, "3: no VERSION");
            check(replies[3] == (8'hC6 ^ ratio), "3: no status");
            check(replies[4] == 8'h00, "3: not 0 after status");
            check(writes == w0 && dones == d0, "3: a read wrote");

            // 4. Unknown command.
            tx[0] = 8'h55; tx[1] = 8'h01; tx[2] = 8'h00; tx[3] = 8'h10; tx[4] = 8'h77;
            transaction(5, 200); wait_idle;
            check(replies[0] == 8'h47 && replies[1] == 8'h00, "4: wrong replies");
            check(writes == w0 && dones == d0, "4: an unknown command wrote");

            // 5. An address, no data.
            tx[0] = 8'h01; tx[1] = 8'h01; tx[2] = 8'h23;
            transaction(3, 200); wait_idle;
            check(writes == w0 && dones == d0, "5: no data but a write or done");

            // 6. Two writes back to back, CS high for 60 ns (6 clocks).
            tx[0] = 8'h01; tx[1] = 8'h00; tx[2] = 8'h40; tx[3] = 8'hE1;
            transaction(4, 60);
            tx[0] = 8'h01; tx[1] = 8'h00; tx[2] = 8'h80; tx[3] = 8'h2C; tx[4] = 8'hD9;
            transaction(5, 200); wait_idle;
            check(writes - w0 == 3, "6: not three writes");
            check(log_addr[w0] == 12'h040 && log_data[w0] == 8'hE1, "6: first write");
            check(log_addr[w0 + 1] == 12'h080 && log_data[w0 + 1] == 8'h2C, "6: second write");
            check(log_addr[w0 + 2] == 12'h081 && log_data[w0 + 2] == 8'hD9, "6: third write");
            check(dones - d0 == 2, "6: done not twice");
        end
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
