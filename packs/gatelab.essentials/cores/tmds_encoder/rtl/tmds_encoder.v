// TMDS encoder for DVI and HDMI (DVI 1.0, 3.3): one channel. While `de` is high it turns a byte
// into a 10-bit word with few transitions and a running DC balance; while `de` is low it sends
// one of the four control words for {c1, c0} (blue carries hsync on c0 and vsync on c1). Three
// clocks of latency: `q` belongs to the inputs of three cycles before. Bit 0 of `q` goes out first.
//
// Three stages, so a full-colour 1080p60 picture meets its 148.5 MHz on a -1 7-series part (one
// stage reached 105 MHz on an XC7S15 with real colours; colour bars of only 00 and FF hid it, the
// encoder collapsing to two words): (1) count the byte's ones, (2) the transition-minimized word
// and its ones minus zeros, (3) the DC balance against the running disparity — the only loop.
//
// The ones in a byte are counted with a table per nibble and one add: a sum of eight bits goes
// through Yosys' maccmap, whose split carry cells nextpnr-xilinx couldn't place (GateLab's HDMI
// spike, 2026-10-13).

module tmds_encoder (
    input  wire       clk,
    input  wire       de,
    input  wire [7:0] d,
    input  wire       c0,
    input  wire       c1,
    output reg  [9:0] q = 10'd0
);
    function [2:0] nibble_ones;
        input [3:0] v;
        case (v)
            4'h0: nibble_ones = 3'd0;
            4'h1, 4'h2, 4'h4, 4'h8: nibble_ones = 3'd1;
            4'h3, 4'h5, 4'h6, 4'h9, 4'hA, 4'hC: nibble_ones = 3'd2;
            4'h7, 4'hB, 4'hD, 4'hE: nibble_ones = 3'd3;
            default: nibble_ones = 3'd4;
        endcase
    endfunction

    function [3:0] byte_ones;
        input [7:0] v;
        byte_ones = {1'b0, nibble_ones(v[3:0])} + {1'b0, nibble_ones(v[7:4])};
    endfunction

    // Stage 1: the byte's ones.
    reg [7:0] d1 = 8'd0;
    reg [3:0] ones1 = 4'd0;
    reg de1 = 1'b0, c01 = 1'b0, c11 = 1'b0;
    always @(posedge clk) begin
        d1 <= d;
        ones1 <= byte_ones(d);
        de1 <= de; c01 <= c0; c11 <= c1;
    end

    // Stage 2: transition-minimized code, XOR or XNOR chain (qm[8] says which: 1 = XOR), and
    // `diff`, the number of ones minus the number of zeros in qm[7:0], in whole bits.
    wire use_xnor = ones1 > 4 || (ones1 == 4 && d1[0] == 1'b0);
    wire [8:0] qm;
    assign qm[0] = d1[0];
    genvar i;
    generate
        for (i = 1; i < 8; i = i + 1) begin : stage
            assign qm[i] = use_xnor ? ~(qm[i - 1] ^ d1[i]) : (qm[i - 1] ^ d1[i]);
        end
    endgenerate
    assign qm[8] = ~use_xnor;
    wire [3:0] qm_ones = byte_ones(qm[7:0]);
    reg [8:0] qm2 = 9'd0;
    reg signed [5:0] diff = 6'sd0;
    reg de2 = 1'b0, c02 = 1'b0, c12 = 1'b0;
    always @(posedge clk) begin
        qm2 <= qm;
        diff <= $signed({2'b0, qm_ones, 1'b0}) - 6'sd8;
        de2 <= de1; c02 <= c01; c12 <= c11;
    end

    // Stage 3: DC balance against the running disparity.
    wire signed [5:0] qm8_twice = qm2[8] ? 6'sd2 : 6'sd0;
    wire signed [5:0] not_qm8_twice = qm2[8] ? 6'sd0 : 6'sd2;
    reg signed [5:0] disparity = 6'sd0;

    always @(posedge clk) begin
        if (!de2) begin
            disparity <= 6'sd0;
            case ({c12, c02})
                2'b00: q <= 10'b1101010100;
                2'b01: q <= 10'b0010101011;
                2'b10: q <= 10'b0101010100;
                default: q <= 10'b1010101011;
            endcase
        end else if (disparity == 0 || diff == 0) begin
            q <= {~qm2[8], qm2[8], qm2[8] ? qm2[7:0] : ~qm2[7:0]};
            disparity <= qm2[8] ? disparity + diff : disparity - diff;
        end else if ((disparity > 0 && diff > 0) || (disparity < 0 && diff < 0)) begin
            q <= {1'b1, qm2[8], ~qm2[7:0]};
            disparity <= disparity + qm8_twice - diff;
        end else begin
            q <= {1'b0, qm2[8], qm2[7:0]};
            disparity <= disparity - not_qm8_twice + diff;
        end
    end
endmodule
