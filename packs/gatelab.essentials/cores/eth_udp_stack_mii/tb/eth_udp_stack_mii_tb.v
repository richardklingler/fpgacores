// Self-checking testbench for eth_udp_stack_mii end to end over MII: a host on the wire through a model of the PHY's
// MII side (rx_clk at 25 MHz and tx_clk at 24.98 MHz with another phase, received nibbles changed 10 ns after rx_clk
// rises; everything sent back decoded on tx_clk, its FCS checked) and the PHY's MDIO side (link up), with the stack on
// a 100 MHz system clock. The design is a UDP echo, wired as in eth_udp's README, plus a datagram of its own on demand.
// Checks as eth_udp_stack's: MDIO setup and link_up; ARP; ping; a UDP echo; the design's own broadcast datagram while
// a ping is answered (both intact); ARP and ping back to back; frame_bad for a bad FCS. Prints PASS or every failed
// check.

`timescale 1ns / 1ps

module stack_mii_phy_mdio (input wire mdc, inout wire mdio);
    reg [15:0] regs [0:31];
    integer i, ones = 0, n = -1;
    reg [1:0] op;
    reg [4:0] pa, ra;
    reg [15:0] data;
    reg drive = 1'b0, value = 1'b1;
    assign mdio = drive ? value : 1'bz;
    initial begin
        for (i = 0; i < 32; i = i + 1) regs[i] = 16'h0000;
        regs[1] = 16'h782D; regs[2] = 16'h001C; regs[3] = 16'hC816;
    end
    always @(posedge mdc) begin : slave
        reg b;
        b = mdio;
        if (n < 0) begin
            if (b === 1'b1) ones = ones + 1;
            else begin if (ones >= 32) n = 32; ones = 0; end
        end else begin
            n = n + 1;
            if (n == 33 && b !== 1'b1) n = -1;
            else if (n == 34 || n == 35) op = {op[0], b};
            else if (n >= 36 && n <= 40) pa = {pa[3:0], b};
            else if (n >= 41 && n <= 45) begin ra = {ra[3:0], b}; if (n == 45) data = regs[ra]; end
            else if (op == 2'b10 && pa == 5'd1) begin
                if (n == 46) #50 begin drive = 1'b1; value = 1'b0; end
                else if (n >= 47 && n <= 62) #50 value = data[62 - n];
                else if (n == 63) begin #50 drive = 1'b0; n = -1; end
            end else if (op == 2'b01 && pa == 5'd1) begin
                if (n >= 48) data = {data[14:0], b};
                if (n == 63) begin regs[ra] = data; n = -1; end
            end else if (n == 63) n = -1;
        end
    end
endmodule

module eth_udp_stack_mii_tb;
    reg clk = 1'b0, rx_clk = 1'b0, tx_clk = 1'b0;
    always #5 clk = ~clk;                  // the system clock, 100 MHz
    always #20 rx_clk = ~rx_clk;           // 25 MHz
    initial begin #7; forever #20.016 tx_clk = ~tx_clk; end   // 24.98 MHz, another phase
    integer errors = 0;
    task fail(input [8*72-1:0] what);
        begin
            $display("FAIL: %0s", what);
            errors = errors + 1;
        end
    endtask

    localparam [47:0] MAC = 48'h02_47_4C_00_00_01, HOST = 48'h3C_22_FB_A1_B2_C3;
    localparam [31:0] IP = {8'd10, 8'd0, 8'd100, 8'd222}, HOST_IP = {8'd10, 8'd0, 8'd100, 8'd10};

    reg  [3:0]  rxd = 4'd0;
    reg         rx_dv = 1'b0;
    wire [3:0]  txd;
    wire        tx_en, mdc, mdio_out, mdio_oe, mdio, link_up, frame_good, frame_bad, arp_replied, ping_replied;
    pullup (mdio);
    assign mdio = mdio_oe ? mdio_out : 1'bz;
    stack_mii_phy_mdio u_phy_mdio (.mdc(mdc), .mdio(mdio));

    wire [7:0]  udp_data;
    wire        udp_valid, udp_last, rx_new, payload_ready, send_ready;
    wire [10:0] udp_length;
    wire [47:0] peer_mac;
    wire [31:0] peer_ip;
    wire [15:0] peer_port;
    reg         own = 1'b0;          // the design's own datagram instead of the echo
    reg         own_send = 1'b0;
    reg  [3:0]  own_index = 4'd0;
    wire        send = own ? own_send : rx_new;
    wire [7:0]  payload = own ? 8'hB0 + own_index : udp_data;
    wire        payload_valid = own ? 1'b1 : udp_valid;
    always @(posedge clk) if (own && payload_ready) own_index <= own_index + 4'd1;

    eth_udp_stack_mii #(.PORT(16'd1234), .SETTLE_MS(1)) dut (
        .clk(clk), .mac(MAC), .ip(IP), .mii_rx_clk(rx_clk), .mii_rxd(rxd), .mii_rx_dv(rx_dv), .mii_rx_er(1'b0),
        .mii_tx_clk(tx_clk), .mii_txd(txd), .mii_tx_en(tx_en), .mdc(mdc), .mdio_out(mdio_out), .mdio_oe(mdio_oe), .mdio_in(mdio), .link_up(link_up),
        .frame_good(frame_good), .frame_bad(frame_bad), .arp_replied(arp_replied), .ping_replied(ping_replied),
        .rx_data(udp_data), .rx_valid(udp_valid), .rx_last(udp_last), .rx_ready(own ? 1'b0 : payload_ready),
        .rx_length(udp_length), .peer_mac(peer_mac), .peer_ip(peer_ip), .peer_port(peer_port), .rx_new(rx_new),
        .rx_dropped(), .send(send), .send_length(own ? 11'd10 : udp_length),
        .dst_mac(own ? 48'hFFFF_FFFF_FFFF : peer_mac), .dst_ip(own ? 32'h0A00_FFFF : peer_ip),
        .dst_port(own ? 16'd4321 : peer_port), .send_ready(send_ready), .payload_data(payload),
        .payload_valid(payload_valid), .payload_ready(payload_ready));

    integer goods = 0, bads = 0;
    always @(posedge clk) begin
        if (frame_good) goods = goods + 1;
        if (frame_bad) bads = bads + 1;
    end

    // ---- CRC and checksums ---------------------------------------------------------------------------------
    function [31:0] crc_update(input [31:0] c, input [7:0] d);
        integer i;
        reg [31:0] x;
        begin
            x = c ^ {24'd0, d};
            for (i = 0; i < 8; i = i + 1) x = {1'b0, x[31:1]} ^ (x[0] ? 32'hEDB8_8320 : 32'd0);
            crc_update = x;
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

    // ---- The host sending -----------------------------------------------------------------------------------
    reg [7:0] frame [0:1599];
    integer frame_n;
    task put16(input integer at, input [15:0] v); begin frame[at] = v[15:8]; frame[at + 1] = v[7:0]; end endtask
    task put32(input integer at, input [31:0] v); begin put16(at, v[31:16]); put16(at + 2, v[15:0]); end endtask
    task put48(input integer at, input [47:0] v); begin put16(at, v[47:32]); put32(at + 2, v[31:0]); end endtask
    function [31:0] sum16(input integer from, input integer to);
        integer i;
        reg [31:0] s;
        begin
            s = 0;
            for (i = from; i < to; i = i + 2) s = s + {frame[i], (i + 1 < to) ? frame[i + 1] : 8'h00};
            sum16 = s;
        end
    endfunction

    task ipv4(input [7:0] proto, input integer payload_bytes);
        begin
            put48(0, MAC); put48(6, HOST); put16(12, 16'h0800);
            frame[14] = 8'h45; frame[15] = 8'h00; put16(16, 20 + payload_bytes); put16(18, 16'h3E01);
            put16(20, 16'h4000); frame[22] = 8'd64; frame[23] = proto; put16(24, 16'h0000);
            put32(26, HOST_IP); put32(30, IP);
            put16(24, ~fold(sum16(14, 34)));
            frame_n = 34 + payload_bytes;
        end
    endtask
    task make_arp;
        begin
            put48(0, 48'hFFFF_FFFF_FFFF); put48(6, HOST); put16(12, 16'h0806); put16(14, 16'h0001); put16(16, 16'h0800);
            frame[18] = 8'd6; frame[19] = 8'd4; put16(20, 16'h0001); put48(22, HOST); put32(28, HOST_IP); put48(32, 48'h0);
            put32(38, IP);
            frame_n = 42;
        end
    endtask
    task make_ping(input integer data_bytes);
        integer i;
        begin
            ipv4(8'd1, 8 + data_bytes);
            frame[34] = 8'd8; frame[35] = 8'd0; put16(36, 16'h0000); put16(38, 16'h1234); put16(40, 16'h0007);
            for (i = 0; i < data_bytes; i = i + 1) frame[42 + i] = i * 3 + 1;
            put16(36, ~fold(sum16(34, 42 + data_bytes)));
        end
    endtask
    task make_udp(input integer n);
        integer i;
        begin
            ipv4(8'd17, 8 + n);
            put16(34, 16'd50123); put16(36, 16'd1234); put16(38, 8 + n); put16(40, 16'h0000);
            for (i = 0; i < n; i = i + 1) frame[42 + i] = (i * 41) ^ 8'h6C;
        end
    endtask

    task put_nibble(input [3:0] v, input dv);
        begin @(posedge rx_clk); #10; rxd = v; rx_dv = dv; end
    endtask
    task transmit(input bad);
        integer i, n;
        reg [31:0] c;
        reg [7:0] b;
        begin
            n = frame_n < 60 ? 60 : frame_n;
            for (i = frame_n; i < n; i = i + 1) frame[i] = 8'h00;
            c = 32'hFFFF_FFFF;
            for (i = 0; i < n; i = i + 1) c = crc_update(c, frame[i]);
            c = ~c ^ (bad ? 32'h0001_0000 : 32'd0);
            for (i = 0; i < 15; i = i + 1) put_nibble(4'h5, 1'b1);
            put_nibble(4'hD, 1'b1);
            for (i = 0; i < n + 4; i = i + 1) begin
                b = i < n ? frame[i] : c[8 * (i - n) +: 8];
                put_nibble(b[3:0], 1'b1);
                put_nibble(b[7:4], 1'b1);
            end
            put_nibble(4'h0, 1'b0);
            repeat (12) @(posedge rx_clk);
        end
    endtask

    // ---- What comes back: frames in a list, each with its FCS checked ------------------------------------------
    reg [7:0] back [0:7][0:1599];
    integer back_len [0:7];
    integer backs = 0, nibbles = 0, raw_n = 0;
    reg [7:0] shift = 8'd0;
    reg [7:0] raw [0:1607];
    reg tx_en_was = 1'b0;
    always @(posedge tx_clk) begin
        if (tx_en) begin
            shift = {txd, shift[7:4]};
            nibbles = nibbles + 1;
            if (nibbles % 2 == 0) begin raw[raw_n] = shift; raw_n = raw_n + 1; end
        end else if (tx_en_was) begin : done
            integer i;
            reg [31:0] c;
            c = 32'hFFFF_FFFF;
            for (i = 8; i < raw_n; i = i + 1) c = crc_update(c, raw[i]);
            if (c !== 32'hDEBB_20E3 || raw[7] !== 8'hD5) fail("a frame sent with a bad FCS or preamble");
            if (backs < 8) begin
                for (i = 8; i < raw_n - 4; i = i + 1) back[backs][i - 8] = raw[i];
                back_len[backs] = raw_n - 12;
            end
            backs = backs + 1;
            raw_n = 0;
            nibbles = 0;
        end
        tx_en_was = tx_en;
    end
    function [15:0] b16(input integer f, input integer at); b16 = {back[f][at], back[f][at + 1]}; endfunction
    function [31:0] bsum(input integer f, input integer from, input integer to);
        integer i;
        reg [31:0] s;
        begin
            s = 0;
            for (i = from; i < to; i = i + 2) s = s + {back[f][i], (i + 1 < to) ? back[f][i + 1] : 8'h00};
            bsum = s;
        end
    endfunction

    task wait_backs(input integer n);
        integer t;
        begin
            t = 0;
            while (backs < n && t < 80000) begin @(posedge clk); t = t + 1; end
        end
    endtask

    // Finds the frame sent back with this EtherType and IP protocol (0 for ARP), or -1.
    function integer find(input [15:0] ethertype, input [7:0] proto);
        integer f;
        begin
            find = -1;
            for (f = 0; f < backs && f < 8; f = f + 1)
                if (b16(f, 12) == ethertype && (ethertype == 16'h0806 || back[f][23] == proto) && find < 0) find = f;
        end
    endfunction

    integer f, i, wrong;
    initial begin
        wait (link_up === 1'b1);
        if (u_phy_mdio.regs[4] !== 16'h0101) fail("MDIO didn't advertise 100 full duplex");

        // ARP.
        make_arp; transmit(1'b0); wait_backs(1);
        f = find(16'h0806, 8'd0);
        if (f < 0) fail("no ARP reply");
        else if (b16(f, 20) !== 16'h0002 || {back[f][28], back[f][29], back[f][30], back[f][31]} !== IP) fail("the ARP reply");
        backs = 0;

        // Ping.
        make_ping(56); transmit(1'b0); wait_backs(1);
        f = find(16'h0800, 8'd1);
        if (f < 0) fail("no echo reply");
        else if (back[f][34] !== 8'd0 || fold(bsum(f, 14, 34)) !== 16'hFFFF || fold(bsum(f, 34, 98)) !== 16'hFFFF) fail("the echo reply");
        backs = 0;

        // UDP echo.
        make_udp(37); transmit(1'b0); wait_backs(1);
        f = find(16'h0800, 8'd17);
        if (f < 0) fail("no UDP echo");
        else begin
            wrong = 0;
            for (i = 0; i < 37; i = i + 1) if (back[f][42 + i] !== (((i * 41) ^ 8'h6C) & 8'hFF)) wrong = wrong + 1;
            if (wrong != 0 || b16(f, 36) !== 16'd50123 || b16(f, 38) !== 16'd45 || fold(bsum(f, 14, 34)) !== 16'hFFFF)
                fail("the UDP echo");
        end
        backs = 0;

        // The design's own datagram while a ping is answered: both intact.
        own = 1'b1;
        make_ping(200);
        fork
            transmit(1'b0);
            begin
                // Once the echo reply is going out (its tx_valid drops between bytes), the design sends: the datagram
                // must wait for the reply's last byte.
                wait (dut.u_core.sel == 2'd2 && dut.u_core.u_mac.state == 3'd2);
                repeat (40) @(posedge clk);
                @(negedge clk); own_send = 1'b1; @(posedge clk); #1; own_send = 1'b0;
            end
        join
        wait_backs(2);
        if (backs != 2) fail("the design's datagram and the echo reply: not both sent");
        f = find(16'h0800, 8'd17);
        if (f < 0) fail("the design's datagram");
        else begin
            wrong = 0;
            for (i = 0; i < 10; i = i + 1) if (back[f][42 + i] !== 8'hB0 + i) wrong = wrong + 1;
            if (wrong != 0 || b16(f, 0) !== 16'hFFFF || b16(f, 36) !== 16'd4321) fail("the design's datagram's contents");
        end
        f = find(16'h0800, 8'd1);
        if (f < 0 || fold(bsum(f, 34, 242)) !== 16'hFFFF) fail("the echo reply next to the datagram");
        own = 1'b0;
        backs = 0;

        // ARP and ping back to back.
        make_arp; transmit(1'b0);
        make_ping(20); transmit(1'b0);
        wait_backs(2);
        if (find(16'h0806, 8'd0) < 0 || find(16'h0800, 8'd1) < 0) fail("ARP and ping back to back");
        backs = 0;

        // A bad FCS.
        goods = 0; bads = 0;
        make_ping(10); transmit(1'b1);
        repeat (2000) @(posedge clk);
        if (bads != 1 || goods != 0 || backs != 0) fail("a bad FCS");

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
