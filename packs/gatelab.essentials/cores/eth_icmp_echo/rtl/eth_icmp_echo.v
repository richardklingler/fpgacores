// ICMP echo responder ("ping", RFC 792) for IPv4 over Ethernet: answers an echo request to `mac` and `ip` with an
// echo reply carrying the same identifier, sequence number and data.
//
// It watches eth_mac's received frames and keeps each one in a buffer of 2^ADDR_BITS bytes (one block RAM at 11)
// while checking it: to `mac` (not broadcast), EtherType 0800, IPv4 with a 20-byte header (45), not a fragment (MF
// clear, offset 0 — a fragmented ping's first piece looks like a whole request), protocol 1, destination `ip`, a
// correct header checksum, ICMP type 8, code 0, and the IP total length within the frame and the buffer. When the
// frame's last byte comes with `rx_good`, the reply goes out from the buffer with the addresses swapped, type 0
// and the ICMP checksum adjusted (RFC 1624: +0800); the IP header's checksum stays as it is. The reply is offered
// on a valid/ready/last stream — `tx_valid` drops for two clocks after each byte while the next one is read
// (eth_mac asks every fourth clock). Frames that arrive while a reply waits or goes out aren't kept.

module eth_icmp_echo #(
    parameter integer ADDR_BITS = 11
) (
    input  wire        clk,
    input  wire [47:0] mac,
    input  wire [31:0] ip,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    input  wire        rx_last,
    input  wire        rx_good,
    output wire [7:0]  tx_data,
    output wire        tx_valid,
    output wire        tx_last,
    input  wire        tx_ready,
    output reg         replied = 1'b0
);
    localparam integer SIZE = 1 << ADDR_BITS;

    reg [7:0]  buffer [0:SIZE-1];
    reg [7:0]  rd_data = 8'd0;

    // ---- The request ----------------------------------------------------------------------------------------
    // Addresses are compared against bytes shifted out of registers; the IP header's words are summed without
    // folding (20 bits hold ten of them) and the frame is judged over three clocks after its last byte (the next
    // frame can't start for more than 48).
    reg [11:0] index = 12'd0;   // bytes so far (stops at 4095)
    reg        ok = 1'b1;
    reg [47:0] mac_left = 48'd0;
    reg [31:0] ip_left = 32'd0;
    reg [15:0] total = 16'd0;   // the IP total length
    reg [19:0] header_sum = 20'd0;
    reg [7:0]  high = 8'd0;     // a 16-bit word's first byte
    reg [15:0] icmp_sum = 16'd0;
    reg        busy = 1'b0;     // a reply waits or goes out
    reg [11:0] reply_last = 12'd0;
    reg [15:0] reply_sum = 16'd0;

    // The end of a frame: 1 the facts latched, 2 the sums folded and the lengths compared, 3 the decision.
    reg        judge1 = 1'b0, judge2 = 1'b0;
    reg        cand = 1'b0;
    reg [11:0] count = 12'd0;
    reg [16:0] fold1 = 17'd0;
    reg [16:0] adjusted = 17'd0;
    reg        lengths_ok = 1'b0;

    function [7:0] fixed(input [11:0] i);
        case (i)
            12'd12: fixed = 8'h08;
            12'd14: fixed = 8'h45;
            12'd23: fixed = 8'h01;
            12'd34: fixed = 8'h08;
            default: fixed = 8'h00;   // 13, 35 (code 0)
        endcase
    endfunction

    wire sending_last = tx_valid && tx_ready && tx_last;

    always @(posedge clk) begin
        replied <= 1'b0;
        judge1 <= 1'b0;
        judge2 <= 1'b0;
        if (sending_last) busy <= 1'b0;
        if (rx_valid) begin
            if (!busy && index < SIZE) buffer[index[ADDR_BITS-1:0]] <= rx_data;
            if (index != 12'd4095) index <= index + 12'd1;
            if (index < 12'd6) begin
                if (rx_data != (index == 12'd0 ? mac[47:40] : mac_left[47:40])) ok <= 1'b0;
                mac_left <= {(index == 12'd0 ? mac[39:0] : mac_left[39:0]), 8'd0};
            end
            if (index == 12'd29) ip_left <= ip;
            if (index >= 12'd30 && index <= 12'd33) begin
                if (rx_data != ip_left[31:24]) ok <= 1'b0;
                ip_left <= {ip_left[23:0], 8'd0};
            end
            if ((index == 12'd12 || index == 12'd13 || index == 12'd14 || index == 12'd23 || index == 12'd34 || index == 12'd35)
                && rx_data != fixed(index)) ok <= 1'b0;
            if (index == 12'd17) total <= {high, rx_data};
            if (index == 12'd20 && rx_data[5:0] != 6'd0) ok <= 1'b0;   // MF and the offset's high bits
            if (index == 12'd21 && rx_data != 8'd0) ok <= 1'b0;        // the offset's low bits
            if (!index[0]) high <= rx_data;
            if (index >= 12'd14 && index <= 12'd33 && index[0]) header_sum <= header_sum + {4'd0, high, rx_data};
            if (index == 12'd37) icmp_sum <= {high, rx_data};
            if (rx_last) begin
                judge1 <= 1'b1;
                cand <= rx_good && ok && !busy && !sending_last && index >= 12'd41;
                count <= index + 12'd1;
                index <= 12'd0;
                ok <= 1'b1;
            end
        end
        if (judge1) begin
            judge2 <= 1'b1;
            fold1 <= {1'b0, header_sum[15:0]} + {13'd0, header_sum[19:16]};
            adjusted <= {1'b0, icmp_sum} + 17'h0800;
            lengths_ok <= total >= 16'd28 && {4'd0, count} >= total + 16'd14 && total + 16'd14 <= SIZE;
            header_sum <= 20'd0;
        end
        if (judge2) begin
            if (cand && lengths_ok && fold1[15:0] + {15'd0, fold1[16]} == 16'hFFFF) begin
                busy <= 1'b1;
                reply_last <= total[11:0] + 12'd13;
                reply_sum <= adjusted[15:0] + {15'd0, adjusted[16]};
                replied <= 1'b1;
            end
        end
    end

    // ---- The reply ------------------------------------------------------------------------------------------
    // Byte d of the reply comes from the buffer at source(d), then is rewritten. A read is issued whenever the
    // two-byte queue in front of tx_* will have room for it when it arrives (the read takes a clock), so with
    // `tx_ready` on every clock a byte goes on every clock.
    reg [11:0] next = 12'd0;          // the reply byte to read next
    reg [11:0] reading = 12'd0;       // the one whose data arrives on this clock
    reg        arriving = 1'b0;
    reg [7:0]  q0 = 8'd0, q1 = 8'd0;
    reg        l0 = 1'b0, l1 = 1'b0;
    reg [1:0]  queued = 2'd0;

    function [11:0] source(input [11:0] d);
        if (d < 12'd6) source = d + 12'd6;
        else if (d >= 12'd26 && d < 12'd30) source = d + 12'd4;
        else if (d >= 12'd30 && d < 12'd34) source = d - 12'd4;
        else source = d;
    endfunction

    assign tx_data = q0;
    assign tx_valid = busy && queued != 2'd0;
    assign tx_last = l0;

    wire       take = tx_valid && tx_ready;
    wire [7:0] arrived = reading >= 12'd6 && reading < 12'd12 ? mac[47 - 8 * (reading - 12'd6) -: 8]
                       : reading == 12'd34 ? 8'h00
                       : reading == 12'd36 ? reply_sum[15:8]
                       : reading == 12'd37 ? reply_sum[7:0]
                       : rd_data;
    wire       arrived_last = reading == reply_last;
    wire [1:0] after = queued + {1'b0, arriving} - {1'b0, take};
    wire       issue = busy && next <= reply_last && after <= 2'd1;
    wire [11:0] read_at = source(next);

    always @(posedge clk) begin
        rd_data <= buffer[read_at[ADDR_BITS-1:0]];
        if (!busy) begin
            next <= 12'd0;
            arriving <= 1'b0;
            queued <= 2'd0;
        end else begin
            arriving <= issue;
            if (issue) begin
                reading <= next;
                next <= next + 12'd1;
            end
            queued <= after;
            // A read is issued only when the queue will hold at most one byte as its data arrives: taking and
            // arriving together find exactly one queued.
            if (take && arriving) begin
                q0 <= arrived; l0 <= arrived_last;
            end else if (take) begin
                q0 <= q1; l0 <= l1;
            end else if (arriving) begin
                if (queued == 2'd0) begin q0 <= arrived; l0 <= arrived_last; end
                else begin q1 <= arrived; l1 <= arrived_last; end
            end
        end
    end
endmodule
