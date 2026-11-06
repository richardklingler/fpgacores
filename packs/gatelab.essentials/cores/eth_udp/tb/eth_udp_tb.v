// Self-checking testbench for eth_udp (PORT 1234): frames as eth_mac delivers them (a byte every fourth clock,
// frame_last and frame_good with the last; short ones padded with non-zero bytes) and a MAC on the send side that
// takes a byte every fourth clock and counts the times it found no byte (an underrun).
// Receive: payloads of 5 (with a UDP checksum), 300 (checksum 0), 33 (odd, checksummed) and 18 bytes (a 60-byte
// frame without padding: the last byte is in the checksum) are handed over exactly, with rx_new, rx_length and the
// sender; so is a broadcast to 255.255.255.255 and an empty datagram (rx_new, no bytes). Dropped: a wrong UDP
// checksum, another port, a fragment, a frame shorter than its IP length, another IP, rx_good low, a wrong header checksum, a UDP length that doesn't
// match. A datagram arriving while the one before is still being taken is dropped (rx_dropped), the first intact.
// Send: 0, 5, 1472 and 9 bytes (the last to an address whose header sum carries), and 12 to a consumer that's ready on
// every clock — the headers field by field (a new identification each time), a valid IP checksum, the payload as offered by a source
// that answers three clocks after each byte. And an echo: the received stream wired straight into the send side.
// Then at 1000 Mbit/s: frames a byte on every clock, a consumer ready on every clock that must find a byte on every
// clock (no underrun), a payload source that answers on every clock, the handover to a design taking a byte every
// clock without a pause, and the echo at that pace.
// Prints PASS or every failed check.

`timescale 1ns / 1ps

module eth_udp_tb;
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
    localparam [15:0] HOST_PORT = 16'd50123;

    reg  [7:0]  frame_data = 8'd0;
    reg         frame_valid = 1'b0, frame_last = 1'b0, frame_good = 1'b0;
    wire [7:0]  rx_data;
    wire        rx_valid, rx_last, rx_new, rx_dropped;
    reg         rx_ready = 1'b1;
    wire [10:0] rx_length;
    wire [47:0] peer_mac;
    wire [31:0] peer_ip;
    wire [15:0] peer_port;
    reg         send = 1'b0;
    reg  [10:0] send_length = 11'd0;
    reg  [47:0] dst_mac = 48'd0;
    reg  [31:0] dst_ip = 32'd0;
    reg  [15:0] dst_port = 16'd0;
    wire        send_ready, payload_ready;
    reg  [7:0]  src_data = 8'd0;
    reg         src_valid = 1'b0;
    reg         echo = 1'b0;    // the send side's payload is the received stream
    wire [7:0]  payload_data = echo ? rx_data : src_data;
    wire        payload_valid = echo ? rx_valid : src_valid;
    wire [7:0]  tx_data;
    wire        tx_valid, tx_last;
    reg         tx_ready = 1'b0;
    wire        rx_ready_w = echo ? payload_ready : rx_ready;

    eth_udp #(.PORT(16'd1234)) dut (.clk(clk), .mac(MAC), .ip(IP),
        .frame_data(frame_data), .frame_valid(frame_valid), .frame_last(frame_last), .frame_good(frame_good),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_last(rx_last), .rx_ready(rx_ready_w), .rx_length(rx_length),
        .peer_mac(peer_mac), .peer_ip(peer_ip), .peer_port(peer_port), .rx_new(rx_new), .rx_dropped(rx_dropped),
        .send(send), .send_length(send_length), .dst_mac(dst_mac), .dst_ip(dst_ip), .dst_port(dst_port),
        .send_ready(send_ready), .payload_data(payload_data), .payload_valid(payload_valid), .payload_ready(payload_ready),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_last(tx_last), .tx_ready(tx_ready));

    // ---- Received datagrams -----------------------------------------------------------------------------------
    reg [7:0] got [0:2047];
    integer got_n = 0, news = 0, drops = 0, lasts = 0;
    always @(posedge clk) begin
        if (rx_valid && rx_ready_w) begin
            got[got_n] = rx_data;
            got_n = got_n + 1;
            if (rx_last) lasts = lasts + 1;
        end
        if (rx_new) news = news + 1;
        if (rx_dropped) drops = drops + 1;
    end

    reg greedy = 1'b0;   // a consumer that takes a byte on every clock it's offered one
    reg dense = 1'b0;    // frames a byte on every clock
    reg fast = 1'b0;     // a payload source that answers on every clock
    // Pauses in the handover: the design ready, the datagram not all taken, no byte offered.
    integer rx_gaps = 0;
    always @(posedge clk) if (fast && dut.holding && got_n > 0 && rx_ready_w && !rx_valid && lasts == 0) rx_gaps = rx_gaps + 1;

    // ---- The MAC's send side ---------------------------------------------------------------------------------
    reg [7:0] wire_bytes [0:2047];
    integer wire_n = 0, frames = 0, underruns = 0;
    reg [1:0] slot = 2'd0;
    always @(posedge clk) begin
        slot <= slot + 2'd1;
        // The MAC doesn't wait: whenever it asks during a datagram, a byte must be there.
        // (A consumer always ready with the slow source finds no byte between them: that pairing checks only the bytes.)
        if (tx_ready && dut.sending && !tx_valid && (!greedy || fast)) underruns = underruns + 1;
        if (tx_valid && tx_ready) begin
            wire_bytes[wire_n] = tx_data;
            wire_n = wire_n + 1;
            if (tx_last) frames = frames + 1;
        end
    end
    always @(negedge clk) tx_ready = greedy || (slot == 2'd0);

    // A payload source that answers three clocks after each byte taken.
    reg [7:0] payload [0:2047];
    integer next_byte = 0, wait_clocks = 0;
    always @(posedge clk) if (!echo) begin
        if (src_valid && payload_ready && fast) begin
            next_byte = next_byte + 1;
            src_data <= payload[next_byte];
        end else if (src_valid && payload_ready) begin
            src_valid <= 1'b0;
            next_byte = next_byte + 1;
            wait_clocks = 2;
        end else if (!src_valid && dut.sending && dut.o >= 12'd38) begin
            if (wait_clocks > 0) wait_clocks = wait_clocks - 1;
            else begin src_data <= payload[next_byte]; src_valid <= 1'b1; end
        end
    end

    // ---- Frames in -------------------------------------------------------------------------------------------
    reg [7:0] frame [0:2047];
    integer frame_n;
    task put16(input integer at, input [15:0] v); begin frame[at] = v[15:8]; frame[at + 1] = v[7:0]; end endtask
    task put32(input integer at, input [31:0] v); begin put16(at, v[31:16]); put16(at + 2, v[15:0]); end endtask
    task put48(input integer at, input [47:0] v); begin put16(at, v[47:32]); put32(at + 2, v[31:0]); end endtask

    function [31:0] sum16(input integer from, input integer to);   // the words from..to-1, not folded
        integer i;
        reg [31:0] s;
        begin
            s = 0;
            for (i = from; i < to; i = i + 2) s = s + {frame[i], (i + 1 < to) ? frame[i + 1] : 8'h00};
            sum16 = s;
        end
    endfunction
    function [15:0] fold(input [31:0] s);
        reg [31:0] t;
        begin
            t = s;
            while (t[31:16] != 0) t = t[15:0] + t[31:16];
            fold = t[15:0];
        end
    endfunction

    // A datagram of `n` bytes to `to_ip`:`port`; `checksum`: with a UDP checksum (else 0).
    task make_udp(input [47:0] to, input [31:0] to_ip, input [15:0] port, input integer n, input checksum, input [15:0] flags);
        integer i, total;
        reg [15:0] c;
        begin
            total = 28 + n;
            put48(0, to); put48(6, HOST); put16(12, 16'h0800);
            frame[14] = 8'h45; frame[15] = 8'h00; put16(16, total[15:0]); put16(18, 16'h7A01 + n);
            put16(20, flags); frame[22] = 8'd64; frame[23] = 8'd17; put16(24, 16'h0000);
            put32(26, HOST_IP); put32(30, to_ip);
            put16(24, ~fold(sum16(14, 34)));
            put16(34, HOST_PORT); put16(36, port); put16(38, (8 + n)); put16(40, 16'h0000);
            for (i = 0; i < n; i = i + 1) frame[42 + i] = (i * 53 + n) ^ 8'h5A;
            if (checksum) begin
                c = ~fold(sum16(26, 34) + sum16(34, 42 + n) + 32'd17 + (8 + n));
                put16(40, c == 16'h0000 ? 16'hFFFF : c);
            end
            frame_n = 14 + total;
            for (i = frame_n; i < 60; i = i + 1) frame[i] = 8'hE0 + i;
            if (frame_n < 60) frame_n = 60;
        end
    endtask

    task deliver(input good);
        integer i;
        begin
            @(posedge clk); #1;
            for (i = 0; i < frame_n; i = i + 1) begin
                frame_data = frame[i];
                frame_valid = 1'b1;
                frame_last = (i == frame_n - 1);
                frame_good = (i == frame_n - 1) && good;
                @(posedge clk); #1;
                if (!dense) begin
                    frame_valid = 1'b0; frame_last = 1'b0; frame_good = 1'b0;
                    repeat (3) @(posedge clk);
                    #1;
                end
            end
            frame_valid = 1'b0; frame_last = 1'b0; frame_good = 1'b0;
            repeat (40) @(posedge clk);
        end
    endtask

    reg [7:0] kept [0:2047];
    task expect_datagram(input integer n, input [8*40-1:0] what);
        integer i, wrong;
        begin
            for (i = 0; i < n; i = i + 1) kept[i] = frame[42 + i];
            repeat (4 * n + 40) @(posedge clk);
            wrong = 0;
            if (news != 1 || got_n != n || rx_length != n || (n > 0 && lasts != 1)) begin
                $display("FAIL: %0s: %0d new, %0d bytes (length %0d), %0d last", what, news, got_n, rx_length, lasts);
                errors = errors + 1;
            end else for (i = 0; i < n; i = i + 1) if (got[i] !== kept[i]) wrong = wrong + 1;
            if (wrong != 0) begin $display("FAIL: %0s: %0d bytes wrong", what, wrong); errors = errors + 1; end
            if (peer_mac !== HOST || peer_ip !== HOST_IP || peer_port !== HOST_PORT) begin $display("FAIL: %0s: the sender", what); errors = errors + 1; end
            news = 0; got_n = 0; lasts = 0;
        end
    endtask

    task expect_none(input [8*40-1:0] what);
        begin
            repeat (200) @(posedge clk);
            if (news != 0 || got_n != 0) begin $display("FAIL: %0s: handed over", what); errors = errors + 1; end
            news = 0; got_n = 0; lasts = 0;
        end
    endtask

    // ---- Sending ---------------------------------------------------------------------------------------------
    function [31:0] wire_sum(input integer from, input integer to);
        integer i;
        reg [31:0] s;
        begin
            s = 0;
            for (i = from; i < to; i = i + 2) s = s + {wire_bytes[i], (i + 1 < to) ? wire_bytes[i + 1] : 8'h00};
            wire_sum = s;
        end
    endfunction
    function [47:0] w48(input integer at); w48 = {wire_bytes[at], wire_bytes[at + 1], wire_bytes[at + 2], wire_bytes[at + 3], wire_bytes[at + 4], wire_bytes[at + 5]}; endfunction
    function [31:0] w32(input integer at); w32 = {wire_bytes[at], wire_bytes[at + 1], wire_bytes[at + 2], wire_bytes[at + 3]}; endfunction
    function [15:0] w16(input integer at); w16 = {wire_bytes[at], wire_bytes[at + 1]}; endfunction

    reg [15:0] last_ident = 16'd0;
    integer sent_before = 0;
    task check_sent(input integer n, input [47:0] to, input [31:0] to_ip, input [15:0] port, input [8*40-1:0] what);
        integer i, wrong;
        begin
            while (frames == 0) @(posedge clk);
            if (wire_n != 42 + n) begin $display("FAIL: %0s: %0d bytes sent", what, wire_n); errors = errors + 1; end
            else begin
                if (w48(0) !== to || w48(6) !== MAC || w16(12) !== 16'h0800) begin $display("FAIL: %0s: Ethernet header", what); errors = errors + 1; end
                if (wire_bytes[14] !== 8'h45 || w16(16) !== 28 + n || w16(20) !== 16'h4000 || wire_bytes[22] !== 8'd64 || wire_bytes[23] !== 8'd17)
                    begin $display("FAIL: %0s: IP header", what); errors = errors + 1; end
                if (sent_before && w16(18) === last_ident) begin $display("FAIL: %0s: the same identification as the datagram before", what); errors = errors + 1; end
                last_ident = w16(18);
                sent_before = 1;
                if (fold(wire_sum(14, 34)) !== 16'hFFFF) begin $display("FAIL: %0s: IP checksum", what); errors = errors + 1; end
                if (w32(26) !== IP || w32(30) !== to_ip) begin $display("FAIL: %0s: IP addresses", what); errors = errors + 1; end
                if (w16(34) !== 16'd1234 || w16(36) !== port || w16(38) !== 8 + n || w16(40) !== 16'h0000)
                    begin $display("FAIL: %0s: UDP header", what); errors = errors + 1; end
                wrong = 0;
                for (i = 0; i < n; i = i + 1) if (wire_bytes[42 + i] !== kept[i]) wrong = wrong + 1;
                if (wrong != 0) begin $display("FAIL: %0s: %0d payload bytes wrong", what, wrong); errors = errors + 1; end
            end
            if (underruns != 0) begin $display("FAIL: %0s: %0d underruns", what, underruns); errors = errors + 1; end
            wire_n = 0; frames = 0; underruns = 0;
        end
    endtask

    task send_datagram(input integer n, input [8*40-1:0] what);
        begin
            send_to(n, {8'd10, 8'd0, 8'd255, 8'd255}, what);
        end
    endtask

    task send_to(input integer n, input [31:0] to_ip, input [8*40-1:0] what);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin payload[i] = (i * 29) ^ 8'hC5 ^ (i >> 6); kept[i] = payload[i]; end
            next_byte = 0;
            src_valid <= 1'b0;   // a byte fetched for the datagram before is stale
            @(negedge clk);
            while (!send_ready) @(negedge clk);
            send = 1'b1; send_length = n; dst_mac = 48'h00_11_22_33_44_55; dst_ip = to_ip; dst_port = 16'd4321;
            @(posedge clk); #1; send = 1'b0;
            check_sent(n, 48'h00_11_22_33_44_55, to_ip, 16'd4321, what);
        end
    endtask

    integer k;
    reg [31:0] carry_ip = 32'd0;
    initial begin
        make_udp(MAC, IP, 16'd1234, 5, 1, 16'h4000);    deliver(1'b1); expect_datagram(5, "5 bytes, checksummed");
        make_udp(MAC, IP, 16'd1234, 300, 0, 16'h4000);  deliver(1'b1); expect_datagram(300, "300 bytes, no checksum");
        make_udp(MAC, IP, 16'd1234, 33, 1, 16'h4000);   deliver(1'b1); expect_datagram(33, "33 bytes");
        make_udp(MAC, IP, 16'd1234, 18, 1, 16'h4000);   deliver(1'b1); expect_datagram(18, "18 bytes, no padding");
        make_udp(48'hFFFF_FFFF_FFFF, 32'hFFFF_FFFF, 16'd1234, 7, 1, 16'h0000); deliver(1'b1); expect_datagram(7, "a broadcast");
        make_udp(MAC, IP, 16'd1234, 0, 1, 16'h4000);    deliver(1'b1); expect_datagram(0, "an empty datagram");

        make_udp(MAC, IP, 16'd1234, 5, 1, 16'h4000); frame[45] = frame[45] ^ 8'h10; deliver(1'b1); expect_none("a wrong UDP checksum");
        make_udp(MAC, IP, 16'd1235, 5, 1, 16'h4000);    deliver(1'b1); expect_none("another port");
        make_udp(MAC, IP, 16'd1234, 5, 1, 16'h2000);    deliver(1'b1); expect_none("a fragment");
        make_udp(MAC, {8'd10, 8'd0, 8'd100, 8'd99}, 16'd1234, 5, 1, 16'h4000); deliver(1'b1); expect_none("another IP");
        make_udp(MAC, IP, 16'd1234, 5, 1, 16'h4000);    deliver(1'b0); expect_none("rx_good low");
        make_udp(MAC, IP, 16'd1234, 5, 1, 16'h4000); frame[25] = frame[25] ^ 8'h01; deliver(1'b1); expect_none("a wrong header checksum");
        make_udp(MAC, IP, 16'd1234, 5, 0, 16'h4000); put16(38, 16'd12); deliver(1'b1); expect_none("a wrong UDP length");
        // A frame shorter than its IP length says (the lengths agree with each other, the header checksum is right).
        make_udp(MAC, IP, 16'd1234, 40, 0, 16'h4000); put16(16, 16'd88); put16(38, 16'd68); put16(24, 16'h0000);
        put16(24, ~fold(sum16(14, 34))); deliver(1'b1); expect_none("a truncated frame");

        // Taken slowly: the next datagram is dropped, the first stays.
        rx_ready = 1'b0;
        make_udp(MAC, IP, 16'd1234, 20, 1, 16'h4000); deliver(1'b1);
        for (k = 0; k < 20; k = k + 1) kept[k] = frame[42 + k];
        make_udp(MAC, IP, 16'd1234, 25, 1, 16'h4000); deliver(1'b1);
        if (drops != 1) fail("rx_dropped for a datagram while another was held");
        rx_ready = 1'b1;
        repeat (200) @(posedge clk);
        if (news != 1 || got_n != 20) fail("the held datagram");
        else for (k = 0; k < 20; k = k + 1) if (got[k] !== kept[k]) begin fail("the held datagram's bytes"); k = 20; end
        news = 0; got_n = 0; lasts = 0;

        send_datagram(0, "sending 0 bytes");
        send_datagram(5, "sending 5 bytes");
        send_datagram(1472, "sending 1472 bytes");
        // A destination whose header sum carries out of 16 bits when it's folded (the end-around carry).
        begin : carry
            reg [31:0] base, total_sum;
            integer low;
            @(posedge clk); #1;   // the identification counts up on the clock edge the last datagram ended on
            base = 32'h4500 + 32'h4000 + 32'h4011 + IP[31:16] + IP[15:0] + (28 + 9) + dut.ident + 32'h0A00;
            for (low = 0; low < 65536; low = low + 1) begin
                total_sum = base + low;
                if (total_sum[15:0] + total_sum[31:16] > 32'hFFFF && carry_ip == 0) carry_ip = {16'h0A00, low[15:0]};
            end
        end
        send_to(9, carry_ip, "a header sum that carries");
        // A consumer that is ready on every clock: every byte offered must be the right one.
        greedy = 1'b1;
        send_datagram(12, "sending to a consumer always ready");
        greedy = 1'b0;

        // An echo: what arrives goes back to its sender, straight from the receive side.
        echo = 1'b1;
        make_udp(MAC, IP, 16'd1234, 64, 1, 16'h4000);
        for (k = 0; k < 64; k = k + 1) kept[k] = frame[42 + k];
        fork
            deliver(1'b1);
            begin
                @(posedge rx_new);
                @(negedge clk);
                send = 1'b1; send_length = rx_length; dst_mac = peer_mac; dst_ip = peer_ip; dst_port = peer_port;
                @(posedge clk); #1; send = 1'b0;
            end
        join
        check_sent(64, HOST, HOST_IP, HOST_PORT, "the echo");
        echo = 1'b0;

        // 1000 Mbit/s: a byte a clock everywhere.
        greedy = 1'b1; dense = 1'b1; fast = 1'b1;
        news = 0; got_n = 0; lasts = 0; drops = 0;
        make_udp(MAC, IP, 16'd1234, 300, 1, 16'h4000);  deliver(1'b1); expect_datagram(300, "300 bytes, dense");
        make_udp(MAC, IP, 16'd1234, 1472, 0, 16'h4000); deliver(1'b1); expect_datagram(1472, "1472 bytes, dense");
        make_udp(MAC, IP, 16'd1235, 5, 1, 16'h4000);    deliver(1'b1); expect_none("another port, dense");
        if (rx_gaps != 0) begin $display("FAIL: %0d pauses handing datagrams over", rx_gaps); errors = errors + 1; end
        send_datagram(1472, "sending 1472 bytes a byte a clock");
        send_datagram(1, "sending 1 byte a byte a clock");
        echo = 1'b1;
        make_udp(MAC, IP, 16'd1234, 1000, 1, 16'h4000);
        for (k = 0; k < 1000; k = k + 1) kept[k] = frame[42 + k];
        fork
            deliver(1'b1);
            begin
                @(posedge rx_new);
                @(negedge clk);
                send = 1'b1; send_length = rx_length; dst_mac = peer_mac; dst_ip = peer_ip; dst_port = peer_port;
                @(posedge clk); #1; send = 1'b0;
            end
        join
        check_sent(1000, HOST, HOST_IP, HOST_PORT, "the echo a byte a clock");
        echo = 1'b0; greedy = 1'b0; dense = 1'b0; fast = 1'b0;

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
