// Self-checking testbench for eth_arp: frames as eth_mac delivers them (a byte every fourth clock, rx_last and
// rx_good with the last) and a MAC on the send side that takes a byte every fourth clock. Checks:
//   - a broadcast request for our IP gets exactly the reply (42 bytes: the requester's MAC, ours, 0806 0001 0800
//     06 04 0002, our MAC and IP, the requester's MAC and IP), `replied` pulses once;
//   - a request to our MAC (unicast) is answered too;
//   - no reply to: another IP, a frame with rx_good low, an ARP reply (operation 2), a request to another host's
//     MAC, an IPv4 frame, a request whose hardware type isn't 1;
//   - a reply that waits keeps its requester while another request arrives (which isn't answered);
//   - a consumer that's ready on every clock gets the same reply;
//   - a changed `ip` input is answered at once.
// Prints PASS or every failed check.

`timescale 1ns / 1ps

module eth_arp_tb;
    reg clk = 1'b0;
    always #10 clk = ~clk;
    integer errors = 0;
    task fail(input [8*72-1:0] what);
        begin
            $display("FAIL: %0s", what);
            errors = errors + 1;
        end
    endtask

    localparam [47:0] MAC = 48'h02_47_4C_00_00_01, HOST = 48'h3C_22_FB_A1_B2_C3;
    localparam [31:0] HOST_IP = {8'd10, 8'd0, 8'd100, 8'd10};
    reg [31:0] ip = {8'd10, 8'd0, 8'd100, 8'd222};

    reg  [7:0] rx_data = 8'd0;
    reg        rx_valid = 1'b0, rx_last = 1'b0, rx_good = 1'b0;
    wire [7:0] tx_data;
    wire       tx_valid, tx_last, replied;
    reg        tx_ready = 1'b0;
    eth_arp dut (.clk(clk), .mac(MAC), .ip(ip), .rx_data(rx_data), .rx_valid(rx_valid), .rx_last(rx_last),
        .rx_good(rx_good), .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready),
        .replied(replied));

    // ---- The MAC's send side: a byte every fourth clock while tx_valid ----------------------------------------
    reg [7:0] reply [0:63];
    integer reply_n = 0, replies = 0, replied_pulses = 0;
    reg [1:0] slot = 2'd0;
    always @(posedge clk) begin
        slot <= slot + 2'd1;
        if (replied) replied_pulses = replied_pulses + 1;
        if (tx_valid && tx_ready) begin
            reply[reply_n] = tx_data;
            reply_n = reply_n + 1;
            if (tx_last) replies = replies + 1;
        end
    end
    reg hold = 1'b0;   // the MAC busy with another frame: the reply waits
    reg greedy = 1'b0;   // a consumer ready on every clock: every byte offered must be right
    always @(negedge clk) tx_ready = (greedy || slot == 2'd0) && !hold;

    // ---- Frames in -----------------------------------------------------------------------------------------
    reg [7:0] frame [0:63];
    task put16(input integer at, input [15:0] v); begin frame[at] = v[15:8]; frame[at + 1] = v[7:0]; end endtask
    task put32(input integer at, input [31:0] v); begin put16(at, v[31:16]); put16(at + 2, v[15:0]); end endtask
    task put48(input integer at, input [47:0] v); begin put16(at, v[47:32]); put32(at + 2, v[31:0]); end endtask

    task make_arp(input [47:0] to, input [15:0] htype, input [15:0] oper, input [31:0] target);
        integer i;
        begin
            put48(0, to); put48(6, HOST); put16(12, 16'h0806);
            put16(14, htype); put16(16, 16'h0800); frame[18] = 8'd6; frame[19] = 8'd4; put16(20, oper);
            put48(22, HOST); put32(28, HOST_IP); put48(32, 48'h0); put32(38, target);
            for (i = 42; i < 60; i = i + 1) frame[i] = 8'hA0 + i;
        end
    endtask

    task deliver(input good);
        integer i;
        begin
            for (i = 0; i < 60; i = i + 1) begin
                @(posedge clk); #1;
                rx_data = frame[i];
                rx_valid = 1'b1;
                rx_last = (i == 59);
                rx_good = (i == 59) && good;
                @(posedge clk); #1;
                rx_valid = 1'b0; rx_last = 1'b0; rx_good = 1'b0;
                repeat (2) @(posedge clk);
            end
            repeat (400) @(posedge clk);
        end
    endtask

    function [47:0] got48(input integer at); got48 = {reply[at], reply[at + 1], reply[at + 2], reply[at + 3], reply[at + 4], reply[at + 5]}; endfunction
    function [31:0] got32(input integer at); got32 = {reply[at], reply[at + 1], reply[at + 2], reply[at + 3]}; endfunction

    task expect_reply(input [8*40-1:0] what);
        begin
            if (replies != 1 || reply_n != 42) begin
                $display("FAIL: %0s: %0d replies, %0d bytes", what, replies, reply_n);
                errors = errors + 1;
            end else begin
                if (got48(0) !== HOST || got48(6) !== MAC) begin $display("FAIL: %0s: Ethernet addresses", what); errors = errors + 1; end
                if ({reply[12], reply[13], reply[14], reply[15], reply[16], reply[17], reply[18], reply[19]} !== 64'h0806_0001_0800_0604)
                    begin $display("FAIL: %0s: types and lengths", what); errors = errors + 1; end
                if ({reply[20], reply[21]} !== 16'h0002) begin $display("FAIL: %0s: operation", what); errors = errors + 1; end
                if (got48(22) !== MAC || got32(28) !== ip) begin $display("FAIL: %0s: sender", what); errors = errors + 1; end
                if (got48(32) !== HOST || got32(38) !== HOST_IP) begin $display("FAIL: %0s: target", what); errors = errors + 1; end
            end
            if (replied_pulses != 1) begin $display("FAIL: %0s: %0d replied pulses", what, replied_pulses); errors = errors + 1; end
            replies = 0; reply_n = 0; replied_pulses = 0;
        end
    endtask

    task expect_none(input [8*40-1:0] what);
        begin
            if (replies != 0 || reply_n != 0 || replied_pulses != 0) begin
                $display("FAIL: %0s: answered", what);
                errors = errors + 1;
            end
            replies = 0; reply_n = 0; replied_pulses = 0;
        end
    endtask

    initial begin
        make_arp(48'hFFFF_FFFF_FFFF, 16'h0001, 16'h0001, ip); deliver(1'b1); expect_reply("a broadcast request");
        make_arp(MAC, 16'h0001, 16'h0001, ip);                deliver(1'b1); expect_reply("a unicast request");
        make_arp(48'hFFFF_FFFF_FFFF, 16'h0001, 16'h0001, {8'd10, 8'd0, 8'd100, 8'd99}); deliver(1'b1); expect_none("another IP");
        make_arp(48'hFFFF_FFFF_FFFF, 16'h0001, 16'h0001, ip); deliver(1'b0); expect_none("rx_good low");
        make_arp(48'hFFFF_FFFF_FFFF, 16'h0001, 16'h0002, ip); deliver(1'b1); expect_none("an ARP reply");
        make_arp(48'h02_47_4C_00_00_02, 16'h0001, 16'h0001, ip); deliver(1'b1); expect_none("another host's MAC");
        make_arp(48'hFFFF_FFFF_FFFF, 16'h0006, 16'h0001, ip); deliver(1'b1); expect_none("hardware type 6");
        make_arp(MAC, 16'h0001, 16'h0001, ip); put16(12, 16'h0800); deliver(1'b1); expect_none("an IPv4 frame");
        // A reply waiting while another request (from 10.0.100.11, MAC …C4) arrives: the waiting one stays as it was,
        // the new one isn't answered (one at a time).
        hold = 1'b1;
        make_arp(48'hFFFF_FFFF_FFFF, 16'h0001, 16'h0001, ip); deliver(1'b1);
        make_arp(48'hFFFF_FFFF_FFFF, 16'h0001, 16'h0001, ip); put48(6, HOST + 1); put48(22, HOST + 1);
        put32(28, HOST_IP + 1); deliver(1'b1);
        if (replied_pulses != 1) fail("a request answered while another waited");
        replied_pulses = 1;
        hold = 1'b0;
        repeat (400) @(posedge clk);
        expect_reply("a reply that waited");
        greedy = 1'b1;
        make_arp(48'hFFFF_FFFF_FFFF, 16'h0001, 16'h0001, ip); deliver(1'b1); expect_reply("to a consumer always ready");
        greedy = 1'b0;
        ip = {8'd192, 8'd168, 8'd1, 8'd50};
        make_arp(48'hFFFF_FFFF_FFFF, 16'h0001, 16'h0001, ip); deliver(1'b1); expect_reply("a changed IP");

        if (errors == 0) $display("PASS");
        else $display("FAILED: %0d", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("FAIL: watchdog");
        $finish;
    end
endmodule
