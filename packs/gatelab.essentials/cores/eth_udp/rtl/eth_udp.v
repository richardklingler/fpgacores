// UDP over IPv4 and Ethernet (RFC 768): receives datagrams to one port and sends datagrams from it.
//
// Receive: eth_mac's frames are checked while they arrive — to `mac` or broadcast, EtherType 0800, IPv4 without
// options, not a fragment, protocol 17, to `ip` or 255.255.255.255, a correct header checksum, destination port
// PORT, a UDP length that matches the IP length and fits the frame, and the UDP checksum unless it is 0 — and the
// payload is kept in a buffer of 2^ADDR_BITS bytes. When the frame's last byte comes with `rx_good`, the datagram is
// handed to the design (`rx_new` pulses, also for an empty one): `rx_length` bytes on rx_data/rx_valid/rx_last with `rx_ready`, and the sender in peer_mac,
// peer_ip and peer_port (they stay until the next datagram is handed over). `rx_valid` drops for two clocks after
// each byte while the next one is read. A datagram whose frame starts arriving before the design has taken the last
// byte of the one before is dropped (`rx_dropped` pulses).
//
// Send: with `send_ready` high, `send` starts a datagram of `send_length` bytes (0 … 1472) to dst_mac, dst_ip and
// dst_port from port PORT (latched then). The core puts out the Ethernet, IP (identification counting, don't
// fragment, TTL 64, the header checksum) and UDP headers (checksum 0: none), then asks for the payload with
// `payload_ready`, one byte a request (a byte is taken when `payload_valid` and `payload_ready` are both high). The
// MAC asks every fourth clock and doesn't wait: the next byte must be valid within three clocks of the last one taken
// (eth_udp's own rx side qualifies, so an echo can send straight from it). tx_data/tx_valid/tx_last/tx_ready go to
// eth_mac or a multiplexer.

module eth_udp #(
    parameter [15:0] PORT = 16'd1234,
    parameter integer ADDR_BITS = 11
) (
    input  wire        clk,
    input  wire [47:0] mac,
    input  wire [31:0] ip,
    // From eth_mac
    input  wire [7:0]  frame_data,
    input  wire        frame_valid,
    input  wire        frame_last,
    input  wire        frame_good,
    // Received datagrams
    output reg  [7:0]  rx_data = 8'd0,
    output wire        rx_valid,
    output wire        rx_last,
    input  wire        rx_ready,
    output reg  [10:0] rx_length = 11'd0,
    output reg  [47:0] peer_mac = 48'd0,
    output reg  [31:0] peer_ip = 32'd0,
    output reg  [15:0] peer_port = 16'd0,
    output reg         rx_new = 1'b0,
    output reg         rx_dropped = 1'b0,
    // Datagrams to send
    input  wire        send,
    input  wire [10:0] send_length,
    input  wire [47:0] dst_mac,
    input  wire [31:0] dst_ip,
    input  wire [15:0] dst_port,
    output wire        send_ready,
    input  wire [7:0]  payload_data,
    input  wire        payload_valid,
    output wire        payload_ready,
    // To eth_mac
    output reg  [7:0]  tx_data,
    output wire        tx_valid,
    output wire        tx_last,
    input  wire        tx_ready
);
    localparam integer SIZE = 1 << ADDR_BITS;

    // ---- Receive: checks and the buffer ---------------------------------------------------------------------
    // For speed, addresses are compared against bytes shifted out of registers, the checksums are summed without
    // folding, and a frame is judged over three clocks after its last byte (the next can't start for over 48).
    reg [7:0]  buffer [0:SIZE-1];
    reg [ADDR_BITS-1:0] rd_addr = 0;
    reg [7:0]  rd_data = 8'd0;

    reg [11:0] index = 12'd0;
    reg        to_us = 1'b1, to_all = 1'b1, ok = 1'b1, ip_ok = 1'b1, ip_all = 1'b1;
    reg [47:0] mac_left = 48'd0;
    reg [31:0] ip_left = 32'd0;
    reg [7:0]  high = 8'd0;
    reg [19:0] header_sum = 20'd0;
    reg [27:0] udp_sum = 28'd0;     // the pseudo header's addresses and the UDP segment
    reg [15:0] total = 16'd0, udp_len = 16'd0, udp_check = 16'd0, dport = 16'd0, sport = 16'd0;
    reg [11:0] segment_end = 12'd0; // 14 + the IP total length: the first byte after the segment
    reg [47:0] src_mac = 48'd0;
    reg [31:0] src_ip = 32'd0;
    reg        holding = 1'b0;      // a datagram is being handed to the design
    reg        odd_left = 1'b0;     // the segment's last byte was a word's first …
    reg [7:0]  odd_byte = 8'd0;     // … and this (`high` is overwritten by the padding after it)
    reg        blocked = 1'b0;      // this frame began while a datagram was being handed over

    // The end of a frame: 1 the facts latched, 2 sums and lengths, 3 the folds, 4 the decision.
    reg        judge1 = 1'b0, judge2 = 1'b0, judge3 = 1'b0;
    reg        cand = 1'b0, lengths_ok = 1'b0, port_ok = 1'b0;
    reg [11:0] count = 12'd0;
    reg [27:0] udp_end = 28'd0, udp_all = 28'd0;
    reg [16:0] header_fold = 17'd0, udp_fold = 17'd0;

    wire        in_segment = index >= 12'd34 && index < segment_end;
    wire        rx_taken_last = rx_valid && rx_ready && rx_last;
    // The frame's last byte is still in the segment when there is no padding: its word is completed at the end.
    wire [15:0] last_word = (in_segment && index[0]) ? {high, frame_data}
                          : (in_segment && !index[0]) ? {frame_data, 8'h00}
                          : odd_left ? {odd_byte, 8'h00} : 16'd0;

    always @(posedge clk) begin
        rx_dropped <= 1'b0;
        rx_new <= 1'b0;
        judge1 <= 1'b0;
        judge2 <= 1'b0;
        judge3 <= 1'b0;
        if (rx_taken_last || (holding && rx_length == 11'd0)) holding <= 1'b0;
        if (frame_valid) begin
            if (index != 12'd4095) index <= index + 12'd1;
            if (index == 12'd0) blocked <= holding;
            if (!(index == 12'd0 ? holding : blocked) && index >= 12'd42 && index - 12'd42 < SIZE)
                buffer[index - 12'd42] <= frame_data;
            if (index < 12'd6) begin
                if (frame_data != (index == 12'd0 ? mac[47:40] : mac_left[47:40])) to_us <= 1'b0;
                if (frame_data != 8'hFF) to_all <= 1'b0;
                mac_left <= {(index == 12'd0 ? mac[39:0] : mac_left[39:0]), 8'd0};
            end
            if (index >= 12'd6 && index < 12'd12) src_mac <= {src_mac[39:0], frame_data};
            case (index)
                12'd12: if (frame_data != 8'h08) ok <= 1'b0;
                12'd13: if (frame_data != 8'h00) ok <= 1'b0;
                12'd14: if (frame_data != 8'h45) ok <= 1'b0;
                12'd17: total <= {high, frame_data};
                12'd18: segment_end <= total[11:0] + 12'd14;
                12'd20: if (frame_data[5:0] != 6'd0) ok <= 1'b0;   // MF and the offset
                12'd21: if (frame_data != 8'd0) ok <= 1'b0;
                12'd23: if (frame_data != 8'd17) ok <= 1'b0;
                12'd29: ip_left <= ip;
                12'd35: sport <= {high, frame_data};
                12'd37: dport <= {high, frame_data};
                12'd39: udp_len <= {high, frame_data};
                12'd41: udp_check <= {high, frame_data};
                default: ;
            endcase
            if (index >= 12'd26 && index < 12'd30) src_ip <= {src_ip[23:0], frame_data};
            if (index >= 12'd30 && index < 12'd34) begin
                if (frame_data != ip_left[31:24]) ip_ok <= 1'b0;
                if (frame_data != 8'hFF) ip_all <= 1'b0;
                ip_left <= {ip_left[23:0], 8'd0};
            end
            // Words: a byte at an even index is a word's high byte.
            if (!index[0]) high <= frame_data;
            if (index >= 12'd14 && index < 12'd34 && index[0]) header_sum <= header_sum + {4'd0, high, frame_data};
            // The pseudo header's addresses (26 … 33) and the segment (34 …); the rest of the pseudo header at the end.
            if (index >= 12'd26 && index < 12'd34 && index[0]) udp_sum <= udp_sum + {12'd0, high, frame_data};
            if (in_segment) begin
                if (index[0]) udp_sum <= udp_sum + {12'd0, high, frame_data};
                odd_left <= !index[0];
                odd_byte <= frame_data;
            end
            if (frame_last) begin
                judge1 <= 1'b1;
                cand <= frame_good && (to_us || to_all) && ok && (ip_ok || ip_all);
                count <= index + 12'd1;
                // The last word: the frame's own last byte when there is no padding (then it isn't summed above).
                udp_end <= udp_sum + {12'd0, last_word};
                index <= 12'd0;
                to_us <= 1'b1; to_all <= 1'b1; ok <= 1'b1; ip_ok <= 1'b1; ip_all <= 1'b1;
                odd_left <= 1'b0;
            end
        end
        if (judge1) begin
            judge2 <= 1'b1;
            udp_all <= udp_end + {12'd0, udp_len} + 28'd17;
            header_fold <= {1'b0, header_sum[15:0]} + {13'd0, header_sum[19:16]};
            lengths_ok <= udp_len >= 16'd8 && udp_len + 16'd20 == total && count >= segment_end
                          && udp_len - 16'd8 <= SIZE;
            port_ok <= dport == PORT;
            header_sum <= 20'd0;
            udp_sum <= 28'd0;
        end
        if (judge2) begin
            judge3 <= 1'b1;
            udp_fold <= {1'b0, udp_all[15:0]} + {5'd0, udp_all[27:16]};
            header_fold <= {1'b0, header_fold[15:0] + {15'd0, header_fold[16]}};
        end
        if (judge3) begin
            if (cand && lengths_ok && port_ok && header_fold[15:0] == 16'hFFFF
                && (udp_check == 16'd0 || udp_fold[15:0] + {15'd0, udp_fold[16]} == 16'hFFFF)) begin
                if (blocked) rx_dropped <= 1'b1;
                else begin
                    holding <= 1'b1;
                    rx_new <= 1'b1;
                    rx_length <= udp_len[10:0] - 11'd8;
                    peer_mac <= src_mac;
                    peer_ip <= src_ip;
                    peer_port <= sport;
                end
            end
        end
    end

    // ---- Receive: handing the datagram over -----------------------------------------------------------------
    reg [10:0] out = 11'd0;
    reg [1:0]  fetch = 2'd0;
    reg        started = 1'b0;
    assign rx_valid = holding && started && fetch == 2'd0 && rx_length != 11'd0;
    assign rx_last = out == rx_length - 11'd1;

    always @(posedge clk) begin
        rd_data <= buffer[rd_addr];
        if (!holding) begin
            started <= 1'b0;
            out <= 11'd0;
            fetch <= 2'd0;
        end else if (rx_length == 11'd0) begin
            // An empty datagram: nothing to hand over but rx_new and the sender.
        end else if (!started || (rx_valid && rx_ready)) begin
            if (started) out <= out + 11'd1;
            rd_addr <= started ? out + 11'd1 : 11'd0;
            started <= 1'b1;
            fetch <= 2'd2;
            if (rx_taken_last) started <= 1'b0;
        end else if (fetch != 2'd0) begin
            fetch <= fetch - 2'd1;
            if (fetch == 2'd1) rx_data <= rd_data;
        end
    end

    // ---- Send -----------------------------------------------------------------------------------------------
    // The IP header checksum is summed a term a clock after `send` (it's needed at byte 24, over 100 clocks later),
    // and each header byte is registered: `tx_valid` drops for one clock after each while the next is looked up.
    reg        sending = 1'b0;
    reg [10:0] length = 11'd0;
    reg [47:0] to_mac = 48'd0;
    reg [31:0] to_ip = 32'd0;
    reg [15:0] to_port = 16'd0;
    reg [15:0] ident = 16'd0;
    reg [15:0] ip_total = 16'd0, udp_length = 16'd0;
    reg [11:0] o = 12'd0, last_o = 12'd0;
    reg [3:0]  term = 4'd0;
    reg [19:0] check_sum = 20'd0;
    reg [15:0] ip_check = 16'd0;
    reg [7:0]  header_byte = 8'd0;
    reg        settled = 1'b0;     // header_byte is byte `o`
    wire       header = o < 12'd42;

    assign send_ready = !sending;
    assign tx_valid = sending && (header ? settled : payload_valid);
    assign tx_last = o == last_o;
    assign payload_ready = sending && !header && tx_ready;
    always @(*) tx_data = header ? header_byte : payload_data;

    reg [15:0] term_value;
    always @(*) begin
        case (term)
            4'd0: term_value = 16'h4500;
            4'd1: term_value = ip_total;
            4'd2: term_value = ident;
            4'd3: term_value = 16'h4000;
            4'd4: term_value = 16'h4011;
            4'd5: term_value = ip[31:16];
            4'd6: term_value = ip[15:0];
            4'd7: term_value = to_ip[31:16];
            default: term_value = to_ip[15:0];
        endcase
    end

    always @(posedge clk) begin
        settled <= 1'b0;
        if (!sending) begin
            if (send) begin
                sending <= 1'b1;
                length <= send_length;
                to_mac <= dst_mac;
                to_ip <= dst_ip;
                to_port <= dst_port;
                ip_total <= {5'd0, send_length} + 16'd28;
                udp_length <= {5'd0, send_length} + 16'd8;
                last_o <= {1'b0, send_length} + 12'd41;
                o <= 12'd0;
                term <= 4'd0;
                check_sum <= 20'd0;
            end
        end else begin
            // The checksum: nine terms, then two folds.
            if (term < 4'd9) check_sum <= check_sum + {4'd0, term_value};
            else if (term == 4'd9) check_sum <= {3'd0, {1'b0, check_sum[15:0]} + {13'd0, check_sum[19:16]}};
            else if (term == 4'd10) ip_check <= ~(check_sum[15:0] + {15'd0, check_sum[16]});
            if (term != 4'd11) term <= term + 4'd1;
            if (tx_valid && tx_ready) begin
                o <= o + 12'd1;
                if (tx_last) begin
                    sending <= 1'b0;
                    ident <= ident + 16'd1;
                end
            end else if (header) begin
                case (o)
                    12'd0, 12'd1, 12'd2, 12'd3, 12'd4, 12'd5: header_byte <= to_mac[47 - 8 * o -: 8];
                    12'd6, 12'd7, 12'd8, 12'd9, 12'd10, 12'd11: header_byte <= mac[47 - 8 * (o - 12'd6) -: 8];
                    12'd12: header_byte <= 8'h08;              12'd13: header_byte <= 8'h00;
                    12'd14: header_byte <= 8'h45;              12'd15: header_byte <= 8'h00;
                    12'd16: header_byte <= ip_total[15:8];     12'd17: header_byte <= ip_total[7:0];
                    12'd18: header_byte <= ident[15:8];        12'd19: header_byte <= ident[7:0];
                    12'd20: header_byte <= 8'h40;              12'd21: header_byte <= 8'h00;
                    12'd22: header_byte <= 8'd64;              12'd23: header_byte <= 8'd17;
                    12'd24: header_byte <= ip_check[15:8];     12'd25: header_byte <= ip_check[7:0];
                    12'd26, 12'd27, 12'd28, 12'd29: header_byte <= ip[31 - 8 * (o - 12'd26) -: 8];
                    12'd30, 12'd31, 12'd32, 12'd33: header_byte <= to_ip[31 - 8 * (o - 12'd30) -: 8];
                    12'd34: header_byte <= PORT[15:8];         12'd35: header_byte <= PORT[7:0];
                    12'd36: header_byte <= to_port[15:8];      12'd37: header_byte <= to_port[7:0];
                    12'd38: header_byte <= udp_length[15:8];   12'd39: header_byte <= udp_length[7:0];
                    default: header_byte <= 8'h00;             // 40, 41: no UDP checksum
                endcase
                settled <= 1'b1;
            end
        end
    end
endmodule
