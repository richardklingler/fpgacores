// Self-checking testbench for eth_icmp_echo: echo requests as eth_mac delivers them (a byte every fourth clock,
// rx_last and rx_good with the last; short ones padded to 60 with non-zero bytes) and a MAC on the send side that
// takes a byte every fourth clock. A reply must have the request's length without padding (14 + the IP total
// length), the Ethernet and IP addresses swapped, type 0, a valid IP header checksum and ICMP checksum, the same
// identifier, sequence and data. Payloads of 56, 1472, 18 and 1 bytes are answered, and one whose checksum carries
// when it's adjusted (F800 or more); none of these are: a fragment
// (MF set), a later fragment (an offset), a broadcast, another IP, a wrong header checksum, rx_good low, an echo
// reply (type 0), code 3, a UDP packet, a frame shorter than its IP length. A reply that waits keeps its contents while another request arrives (not answered).
// Prints PASS or every failed check.

`timescale 1ns / 1ps

module eth_icmp_echo_tb;
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
    localparam [31:0] IP = {8'd10, 8'd0, 8'd100, 8'd222}, HOST_IP = {8'd10, 8'd0, 8'd100, 8'd10};

    reg  [7:0] rx_data = 8'd0;
    reg        rx_valid = 1'b0, rx_last = 1'b0, rx_good = 1'b0;
    wire [7:0] tx_data;
    wire       tx_valid, tx_last, replied;
    reg        tx_ready = 1'b0;
    eth_icmp_echo dut (.clk(clk), .mac(MAC), .ip(IP), .rx_data(rx_data), .rx_valid(rx_valid), .rx_last(rx_last),
        .rx_good(rx_good), .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready),
        .replied(replied));

    // ---- The MAC's send side --------------------------------------------------------------------------------
    reg [7:0] reply [0:2047];
    integer reply_expected = 0;
    integer reply_n = 0, replies = 0, replied_pulses = 0, asked_unready = 0;
    reg [1:0] slot = 2'd0;
    reg hold = 1'b0;
    always @(posedge clk) begin
        slot <= slot + 2'd1;
        if (replied) replied_pulses = replied_pulses + 1;
        if (tx_valid && tx_ready) begin
            reply[reply_n] = tx_data;
            reply_n = reply_n + 1;
            if (tx_last) replies = replies + 1;
        end
        // eth_mac doesn't wait: once a reply has started, every fourth clock must find a byte.
        if (slot == 2'd0 && !hold && reply_n > 0 && reply_n < reply_expected && !tx_valid) asked_unready = asked_unready + 1;
    end
    always @(negedge clk) tx_ready = (slot == 2'd0) && !hold;

    // ---- Requests ---------------------------------------------------------------------------------------------
    reg [7:0] frame [0:2047];
    integer frame_n;
    task put16(input integer at, input [15:0] v); begin frame[at] = v[15:8]; frame[at + 1] = v[7:0]; end endtask
    task put32(input integer at, input [31:0] v); begin put16(at, v[31:16]); put16(at + 2, v[15:0]); end endtask
    task put48(input integer at, input [47:0] v); begin put16(at, v[47:32]); put32(at + 2, v[31:0]); end endtask

    function [15:0] csum(input integer from, input integer to);
        integer i;
        reg [31:0] s;
        begin
            s = 0;
            for (i = from; i < to; i = i + 2) s = s + {frame[i], (i + 1 < to) ? frame[i + 1] : 8'h00};
            while (s[31:16] != 0) s = s[15:0] + s[31:16];
            csum = ~s[15:0];
        end
    endfunction

    task make_ping(input [47:0] to, input [31:0] target, input integer payload, input [15:0] seq, input [15:0] flags, input [7:0] kind);
        integer i, total;
        begin
            total = 28 + payload;
            put48(0, to); put48(6, HOST); put16(12, 16'h0800);
            frame[14] = 8'h45; frame[15] = 8'h00; put16(16, total[15:0]); put16(18, 16'h1C46 + seq);
            put16(20, flags); frame[22] = 8'd64; frame[23] = 8'd1; put16(24, 16'h0000);
            put32(26, HOST_IP); put32(30, target);
            put16(24, csum(14, 34));
            frame[34] = kind; frame[35] = 8'd0; put16(36, 16'h0000); put16(38, 16'hBEEF); put16(40, seq);
            for (i = 0; i < payload; i = i + 1) frame[42 + i] = (i * 37 + seq) & 8'hFF;
            put16(36, csum(34, 14 + total));
            frame_n = 14 + total;
            for (i = frame_n; i < 60; i = i + 1) frame[i] = 8'hC0 + i;
            if (frame_n < 60) frame_n = 60;
        end
    endtask

    task deliver(input good);
        integer i;
        begin
            for (i = 0; i < frame_n; i = i + 1) begin
                @(posedge clk); #1;
                rx_data = frame[i];
                rx_valid = 1'b1;
                rx_last = (i == frame_n - 1);
                rx_good = (i == frame_n - 1) && good;
                @(posedge clk); #1;
                rx_valid = 1'b0; rx_last = 1'b0; rx_good = 1'b0;
                repeat (2) @(posedge clk);
            end
            repeat (60) @(posedge clk);
        end
    endtask

    reg [7:0] sent [0:2047];
    task keep_request;
        integer i;
        begin
            for (i = 0; i < 2048; i = i + 1) sent[i] = frame[i];
        end
    endtask

    function [15:0] reply_sum(input integer from, input integer to);
        integer i;
        reg [31:0] s;
        begin
            s = 0;
            for (i = from; i < to; i = i + 2) s = s + {reply[i], (i + 1 < to) ? reply[i + 1] : 8'h00};
            while (s[31:16] != 0) s = s[15:0] + s[31:16];
            reply_sum = s[15:0];
        end
    endfunction

    task expect_reply(input integer payload, input [8*40-1:0] what);
        integer i, total, wrong;
        begin
            total = 28 + payload;
            while (replies == 0) @(posedge clk);
            if (replies != 1 || reply_n != 14 + total) begin
                $display("FAIL: %0s: %0d replies, %0d bytes (expected %0d)", what, replies, reply_n, 14 + total);
                errors = errors + 1;
            end else begin
                if ({reply[0], reply[1], reply[2], reply[3], reply[4], reply[5]} !== HOST ||
                    {reply[6], reply[7], reply[8], reply[9], reply[10], reply[11]} !== MAC) begin $display("FAIL: %0s: MACs", what); errors = errors + 1; end
                if ({reply[26], reply[27], reply[28], reply[29]} !== IP || {reply[30], reply[31], reply[32], reply[33]} !== HOST_IP)
                    begin $display("FAIL: %0s: IPs", what); errors = errors + 1; end
                if (reply_sum(14, 34) !== 16'hFFFF) begin $display("FAIL: %0s: IP checksum", what); errors = errors + 1; end
                if (reply[34] !== 8'd0 || reply[35] !== 8'd0) begin $display("FAIL: %0s: type", what); errors = errors + 1; end
                if (reply_sum(34, 14 + total) !== 16'hFFFF) begin $display("FAIL: %0s: ICMP checksum", what); errors = errors + 1; end
                wrong = 0;
                for (i = 38; i < 14 + total; i = i + 1) if (reply[i] !== sent[i]) wrong = wrong + 1;
                for (i = 12; i < 26; i = i + 1) if (reply[i] !== sent[i]) wrong = wrong + 1;
                if (wrong != 0) begin $display("FAIL: %0s: %0d bytes not as requested", what, wrong); errors = errors + 1; end
            end
            if (replied_pulses != 1) begin $display("FAIL: %0s: %0d replied pulses", what, replied_pulses); errors = errors + 1; end
            if (asked_unready != 0) begin $display("FAIL: %0s: no byte ready %0d times", what, asked_unready); errors = errors + 1; end
            replies = 0; reply_n = 0; replied_pulses = 0; asked_unready = 0;
            repeat (20) @(posedge clk);
        end
    endtask

    task expect_none(input [8*40-1:0] what);
        begin
            repeat (400) @(posedge clk);
            if (replies != 0 || reply_n != 0 || replied_pulses != 0) begin $display("FAIL: %0s: answered", what); errors = errors + 1; end
            replies = 0; reply_n = 0; replied_pulses = 0;
        end
    endtask

    task ping(input integer payload, input [15:0] seq);
        begin
            make_ping(MAC, IP, payload, seq, 16'h4000, 8'd8);
            keep_request;
            reply_expected = 42 + payload;
            deliver(1'b1);
            expect_reply(payload, "a ping");
        end
    endtask

    reg [15:0] carry_seq;
    initial begin
        ping(56, 16'd1);
        ping(1472, 16'd2);
        ping(18, 16'd3);
        ping(1, 16'd4);
        // A request whose ICMP checksum is F800 or more: +0800 carries out of 16 bits (the end-around carry).
        carry_seq = 16'd100;
        make_ping(MAC, IP, 56, carry_seq, 16'h4000, 8'd8);
        while ({frame[36], frame[37]} < 16'hF800) begin
            carry_seq = carry_seq + 16'd1;
            make_ping(MAC, IP, 56, carry_seq, 16'h4000, 8'd8);
        end
        ping(56, carry_seq);
        // A frame shorter than its IP length says (the header checksum right for the longer length).
        make_ping(MAC, IP, 56, 16'd16, 16'h4000, 8'd8); put16(16, 16'd200); put16(24, 16'h0000); put16(24, csum(14, 34));
        deliver(1'b1); expect_none("a truncated frame");
        make_ping(MAC, IP, 56, 16'd15, 16'h4000, 8'd8); frame[35] = 8'd3; put16(36, 16'h0000); put16(36, csum(34, 98));
        deliver(1'b1); expect_none("code 3");
        make_ping(MAC, IP, 56, 16'd5, 16'h2000, 8'd8); deliver(1'b1); expect_none("a first fragment (MF)");
        make_ping(MAC, IP, 56, 16'd6, 16'h00B9, 8'd8); deliver(1'b1); expect_none("a later fragment");
        make_ping(48'hFFFF_FFFF_FFFF, IP, 56, 16'd7, 16'h4000, 8'd8); deliver(1'b1); expect_none("a broadcast");
        make_ping(MAC, {8'd10, 8'd0, 8'd100, 8'd99}, 56, 16'd8, 16'h4000, 8'd8); deliver(1'b1); expect_none("another IP");
        make_ping(MAC, IP, 56, 16'd9, 16'h4000, 8'd8); frame[24] = frame[24] ^ 8'h01; deliver(1'b1); expect_none("a wrong header checksum");
        make_ping(MAC, IP, 56, 16'd10, 16'h4000, 8'd8); deliver(1'b0); expect_none("rx_good low");
        make_ping(MAC, IP, 56, 16'd11, 16'h4000, 8'd0); deliver(1'b1); expect_none("an echo reply");
        make_ping(MAC, IP, 56, 16'd12, 16'h4000, 8'd8); frame[23] = 8'd17; put16(24, 16'h0000); put16(24, csum(14, 34));
        deliver(1'b1); expect_none("UDP");

        // A reply waits while another request arrives.
        hold = 1'b1;
        make_ping(MAC, IP, 40, 16'd13, 16'h4000, 8'd8);
        keep_request;
        reply_expected = 82;
        deliver(1'b1);
        make_ping(MAC, IP, 40, 16'd14, 16'h4000, 8'd8);
        deliver(1'b1);
        if (replied_pulses != 1) fail("a request answered while another waited");
        replied_pulses = 1;
        hold = 1'b0;
        expect_reply(40, "a reply that waited");

        if (errors == 0) $display("PASS");
        else $display("FAILED: %0d", errors);
        $finish;
    end

    initial begin
        #10_000_000;
        $display("FAIL: watchdog");
        $finish;
    end
endmodule
