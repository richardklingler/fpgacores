// Self-checking testbench for eth_mdio against a model of a PHY's MDIO side (clause 22, its own address only, data
// changed 10 or 290 ns after MDC rises (the spec allows 0 to 300), a register file; register 1's bit 2 the link). Two cores on two PHYs: the default
// (ADVERTISE 0101) and one with ADVERTISE 0. Checks:
//   - MDC never faster than 2.5 MHz; MDIO never driven by both sides at once;
//   - nothing before SETTLE_MS; then register 4 = 0101 and register 0 = 1200, in that order (none with ADVERTISE 0);
//   - `link_up` follows the PHY's link (up, down, up again) through the polls;
//   - the design's read of register 3 and write of register 0x1F reach the PHY and come back; `done` pulses once each.
// Prints PASS or every failed check.

`timescale 1ns / 1ps

module phy_mdio_model #(parameter [4:0] ADDR = 5'd1, parameter real DELAY = 100.0) (
    input  wire mdc,
    inout  wire mdio,
    input  wire master_oe
);
    reg [15:0] regs [0:31];
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1) regs[i] = 16'h0000;
        regs[0] = 16'h3100; regs[1] = 16'h782D; regs[2] = 16'h001C; regs[3] = 16'hC816; regs[4] = 16'h01E1;
    end
    integer ones = 0, n = -1, writes = 0, contention = 0;
    reg [1:0] op;
    reg [4:0] pa, ra;
    reg [15:0] data;
    reg drive = 1'b0, value = 1'b1;
    reg [4:0] write_regs [0:15];
    assign mdio = drive ? value : 1'bz;

    always @(posedge mdc) begin : slave
        reg b;
        b = mdio;
        if (n < 0) begin
            if (b === 1'b1) ones = ones + 1;
            else begin
                if (ones >= 32) n = 32;
                ones = 0;
            end
        end else begin
            n = n + 1;
            if (n == 33 && b !== 1'b1) n = -1;
            else if (n == 34 || n == 35) op = {op[0], b};
            else if (n >= 36 && n <= 40) pa = {pa[3:0], b};
            else if (n >= 41 && n <= 45) begin
                ra = {ra[3:0], b};
                if (n == 45) data = regs[ra];
            end else if (op == 2'b10 && pa == ADDR) begin
                if (n == 46) #(DELAY) begin drive = 1'b1; value = 1'b0; end
                else if (n >= 47 && n <= 62) #(DELAY) value = data[62 - n];
                else if (n == 63) begin #(DELAY) drive = 1'b0; n = -1; end
            end else if (op == 2'b01 && pa == ADDR) begin
                if (n >= 48) data = {data[14:0], b};
                if (n == 63) begin
                    regs[ra] = data;
                    if (writes < 16) write_regs[writes] = ra;
                    writes = writes + 1;
                    n = -1;
                end
            end else if (n == 63) n = -1;
        end
    end
    always @(master_oe or drive) if (master_oe === 1'b1 && drive) contention = contention + 1;
endmodule

module eth_mdio_tb;
    reg clk = 1'b0;
    always #10 clk = ~clk;   // 50 MHz
    integer errors = 0;
    task fail(input [8*72-1:0] what);
        begin
            $display("FAIL: %0s", what);
            errors = errors + 1;
        end
    endtask

    wire mdc_a, mdio_a, out_a, oe_a, link_a, setup_a, ready_a, done_a;
    wire [15:0] rdata_a;
    reg go = 1'b0, write = 1'b0;
    reg [4:0] reg_addr = 5'd0;
    reg [15:0] wdata = 16'd0;
    pullup (mdio_a);
    assign mdio_a = oe_a ? out_a : 1'bz;
    eth_mdio #(.CLK_HZ(50_000_000), .MDC_HZ(2_000_000), .SETTLE_MS(1), .POLL_HZ(2000)) dut (
        .clk(clk), .mdc(mdc_a), .mdio_out(out_a), .mdio_oe(oe_a), .mdio_in(mdio_a), .link_up(link_a),
        .setup_done(setup_a), .go(go), .write(write), .reg_addr(reg_addr), .wdata(wdata), .ready(ready_a),
        .done(done_a), .rdata(rdata_a));
    phy_mdio_model #(.ADDR(5'd1), .DELAY(10.0)) phy_a (.mdc(mdc_a), .mdio(mdio_a), .master_oe(oe_a));

    wire mdc_b, mdio_b, out_b, oe_b, link_b, setup_b;
    pullup (mdio_b);
    assign mdio_b = oe_b ? out_b : 1'bz;
    eth_mdio #(.CLK_HZ(50_000_000), .MDC_HZ(2_000_000), .ADVERTISE(16'h0000), .SETTLE_MS(1), .POLL_HZ(2000)) dut_b (
        .clk(clk), .mdc(mdc_b), .mdio_out(out_b), .mdio_oe(oe_b), .mdio_in(mdio_b), .link_up(link_b),
        .setup_done(setup_b), .go(1'b0), .write(1'b0), .reg_addr(5'd0), .wdata(16'd0), .ready(), .done(), .rdata());
    phy_mdio_model #(.ADDR(5'd1), .DELAY(290.0)) phy_b (.mdc(mdc_b), .mdio(mdio_b), .master_oe(oe_b));

    // MDC's shortest period, and the first MDC edge's time.
    realtime last_rise = 0, shortest = 1e9, first_rise = 0;
    always @(posedge mdc_a) begin
        if (last_rise > 0 && $realtime - last_rise < shortest) shortest = $realtime - last_rise;
        if (first_rise == 0) first_rise = $realtime;
        last_rise = $realtime;
    end

    integer dones = 0;
    always @(posedge clk) if (done_a) dones = dones + 1;

    task wait_ready;
        begin
            @(negedge clk);
            while (!ready_a) @(negedge clk);
        end
    endtask

    initial begin
        // Setup.
        wait (setup_a === 1'b1);
        if (first_rise < 1_000_000) fail("MDC ran before SETTLE_MS");
        if (phy_a.writes != 2 || phy_a.write_regs[0] != 5'd4 || phy_a.write_regs[1] != 5'd0) fail("the setup writes (4, then 0)");
        if (phy_a.regs[4] !== 16'h0101) fail("register 4 not 0101");
        if (phy_a.regs[0] !== 16'h1200) fail("register 0 not 1200");
        if (link_a !== 1'b1) fail("link_up after the first poll");

        // The link goes down and comes back.
        phy_a.regs[1] = 16'h782D & ~16'h0004;
        #1_200_000;
        if (link_a !== 1'b0) fail("link_up didn't follow the link down");
        phy_a.regs[1] = 16'h782D;
        #1_200_000;
        if (link_a !== 1'b1) fail("link_up didn't follow the link up");

        // The design's own read and write.
        wait_ready;
        go = 1'b1; write = 1'b0; reg_addr = 5'd3;
        @(posedge clk); #1; go = 1'b0;
        wait (done_a === 1'b1);
        @(posedge clk); #1;
        if (rdata_a !== 16'hC816) fail("the read of register 3");
        wait_ready;
        go = 1'b1; write = 1'b1; reg_addr = 5'd31; wdata = 16'h5A3C;
        @(posedge clk); #1; go = 1'b0;
        wait (done_a === 1'b1);
        @(posedge clk); #1;
        if (phy_a.regs[31] !== 16'h5A3C) fail("the write of register 31");
        if (dones != 2) fail("done pulses");

        if (shortest < 400) fail("MDC faster than 2.5 MHz");
        if (phy_a.contention != 0 || phy_b.contention != 0) fail("MDIO driven by both sides");
        if (phy_b.writes != 0) fail("ADVERTISE 0 still wrote");
        if (setup_b !== 1'b1 || link_b !== 1'b1) fail("ADVERTISE 0: no polls");

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
