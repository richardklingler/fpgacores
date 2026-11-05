// ARP responder: answers "who has `ip`?" with "`ip` is at `mac`" (RFC 826, Ethernet and IPv4 only).
//
// It watches eth_mac's received frames (all of them: it picks its own) and checks a request while it arrives: to
// the broadcast address or to `mac`, EtherType 0806, hardware type 1, protocol 0800, lengths 6 and 4, operation 1,
// target `ip`. When the frame's last byte comes with `rx_good`, the reply is queued and offered on the tx side — 42
// bytes from the requester's MAC on (eth_mac pads to 60) — with valid/ready/last. `replied` pulses when a reply is
// queued. One reply waits at a time: a request that arrives while one is waiting or going out isn't answered (the
// requester asks again).
//
// For speed every comparison is against a byte shifted out of a register, and each reply byte is registered:
// `tx_valid` drops for one clock after each byte while the next one is put together (eth_mac asks every fourth).

module eth_arp (
    input  wire        clk,
    input  wire [47:0] mac,
    input  wire [31:0] ip,
    // From eth_mac
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    input  wire        rx_last,
    input  wire        rx_good,
    // The reply, to eth_mac (or a multiplexer in front of it)
    output reg  [7:0]  tx_data = 8'd0,
    output wire        tx_valid,
    output wire        tx_last,
    input  wire        tx_ready,
    output reg         replied = 1'b0
);
    // ---- The request ----------------------------------------------------------------------------------------
    reg [5:0]  index = 6'd0;        // byte of the frame (stops at 63)
    reg        to_us = 1'b1, to_all = 1'b1, fields_ok = 1'b1, for_us = 1'b1;
    reg [47:0] mac_left = 48'd0;    // `mac`, a byte shifted out for each address byte
    reg [31:0] ip_left = 32'd0;     // `ip`, a byte shifted out for each target byte
    reg [79:0] fixed_left = 80'h0806_0001_0800_0604_0001;   // bytes 12 … 21 of a request
    reg [47:0] sender_mac = 48'd0;
    reg [31:0] sender_ip = 32'd0;
    reg        pending = 1'b0;
    reg [47:0] reply_mac = 48'd0;
    reg [31:0] reply_ip = 32'd0;

    wire done_sending = tx_valid && tx_ready && tx_last;

    always @(posedge clk) begin
        replied <= 1'b0;
        if (done_sending) pending <= 1'b0;
        if (rx_valid) begin
            if (index != 6'd63) index <= index + 6'd1;
            if (index < 6'd6) begin
                if (rx_data != (index == 6'd0 ? mac[47:40] : mac_left[47:40])) to_us <= 1'b0;
                if (rx_data != 8'hFF) to_all <= 1'b0;
                mac_left <= {(index == 6'd0 ? mac[39:0] : mac_left[39:0]), 8'd0};
            end
            if (index >= 6'd12 && index <= 6'd21) begin
                if (rx_data != fixed_left[79:72]) fields_ok <= 1'b0;
                fixed_left <= {fixed_left[71:0], 8'd0};
            end
            if (index >= 6'd22 && index <= 6'd27) sender_mac <= {sender_mac[39:0], rx_data};
            if (index >= 6'd28 && index <= 6'd31) sender_ip <= {sender_ip[23:0], rx_data};
            if (index == 6'd37) ip_left <= ip;
            if (index >= 6'd38 && index <= 6'd41) begin
                if (rx_data != ip_left[31:24]) for_us <= 1'b0;
                ip_left <= {ip_left[23:0], 8'd0};
            end
            if (rx_last) begin
                // A request with a good FCS is at least 60 bytes: its target is in by now.
                if (rx_good && (to_us || to_all) && fields_ok && for_us && index >= 6'd41 && !pending && !done_sending) begin
                    pending <= 1'b1;
                    reply_mac <= sender_mac;
                    reply_ip <= sender_ip;
                    replied <= 1'b1;
                end
                index <= 6'd0;
                to_us <= 1'b1;
                to_all <= 1'b1;
                fields_ok <= 1'b1;
                for_us <= 1'b1;
                fixed_left <= 80'h0806_0001_0800_0604_0001;
            end
        end
    end

    // ---- The reply ------------------------------------------------------------------------------------------
    // The 42 bytes as a register that shifts a byte out for each one taken, loaded when the reply is queued.
    reg [335:0] reply = 336'd0;
    reg [5:0]   out = 6'd0;
    reg         settled = 1'b0;   // tx_data holds byte `out`
    assign tx_valid = pending && settled;
    assign tx_last = out == 6'd41;

    always @(posedge clk) begin
        settled <= 1'b0;
        if (replied) begin
            reply <= {reply_mac, mac, 80'h0806_0001_0800_0604_0002, mac, ip, reply_mac, reply_ip};
            out <= 6'd0;
        end else if (pending) begin
            if (tx_valid && tx_ready) begin
                out <= out + 6'd1;
                reply <= {reply[327:0], 8'd0};
            end else begin
                tx_data <= reply[335:328];
                settled <= 1'b1;
            end
        end
    end
endmodule
