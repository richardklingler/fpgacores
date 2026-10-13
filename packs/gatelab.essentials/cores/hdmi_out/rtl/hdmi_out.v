// DVI/HDMI output for AMD Xilinx 7-series (DVI signalling: pixels and syncs, no audio or info
// frames — every HDMI monitor takes it). Three TMDS encoders (tmds_encoder) and four lanes, each a
// 10:1 OSERDESE2 master/slave pair in DDR into an OBUFDS: blue (lane 0, with hsync on c0 and vsync
// on c1), green (1), red (2) and the clock lane (five ones, five zeros per pixel).
//
// Clocks: `serial_clk` is five times `pixel_clk` (DDR: ten bits per pixel), both from one MMCM or
// PLL so they're in phase. On the global buffers (BUFG) that's 720p60 and 1080p30 (74.25 / 371.25
// MHz). 1080p60's 742.5 MHz serial clock is over a BUFG's limit: use `hdmi_out_bufr` below.
// `reset` is synchronous to `pixel_clk`: hold it until the clocks are stable.
//
// The pins take IOSTANDARD TMDS_33 (P and N of each pair, a 3.3 V bank). Bits go out from bit 0.
// Simulation (no SYNTHESIS) sends the same bits from a behavioural model on both edges of
// `serial_clk`, so a testbench can decode the lanes like a monitor.

module hdmi_out (
    input  wire       pixel_clk,
    input  wire       serial_clk,
    input  wire       reset,
    input  wire [7:0] red,
    input  wire [7:0] green,
    input  wire [7:0] blue,
    input  wire       de,
    input  wire       hsync,
    input  wire       vsync,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n
);
    wire [9:0] word_blue, word_green, word_red;
    tmds_encoder u_blue  (.clk(pixel_clk), .de(de), .d(blue),  .c0(hsync), .c1(vsync), .q(word_blue));
    tmds_encoder u_green (.clk(pixel_clk), .de(de), .d(green), .c0(1'b0),  .c1(1'b0),  .q(word_green));
    tmds_encoder u_red   (.clk(pixel_clk), .de(de), .d(red),   .c0(1'b0),  .c1(1'b0),  .q(word_red));

    hdmi_out_lane u_lane_blue  (.pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset), .word(word_blue),  .out_p(tmds_d_p[0]), .out_n(tmds_d_n[0]));
    hdmi_out_lane u_lane_green (.pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset), .word(word_green), .out_p(tmds_d_p[1]), .out_n(tmds_d_n[1]));
    hdmi_out_lane u_lane_red   (.pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset), .word(word_red),   .out_p(tmds_d_p[2]), .out_n(tmds_d_n[2]));
    hdmi_out_lane u_lane_clock (.pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset), .word(10'b0000011111), .out_p(tmds_clk_p), .out_n(tmds_clk_n));
endmodule

// hdmi_out for serial clocks over a BUFG's limit (1080p60: 742.5 MHz). The serialisers take
// `serial_clk` from a BUFIO and `lane_clk` from a BUFR dividing the same MMCM output by 5, in the
// TMDS pins' clock region. A BUFR reaches that one region only, and nextpnr-xilinx doesn't know:
// logic it clocks may land in the next region and get its clock over data wires (GateLab's HDMI
// follow-up, 2026-10-13). So the encoders and everything the design feeds in run on `pixel_clk`, a
// BUFG at the same frequency from the same MMCM, and only the serialisers, a read pointer and a
// reset synchroniser are on `lane_clk`. The words cross through a ring of eight, written on
// `pixel_clk` and read on `lane_clk` about four entries behind: the two clocks have the same
// frequency, their phase isn't known.
//
// BLACK_LAST_PIXEL (default 1) sends each line's last pixel black. At 1080p60 the link runs about
// 20 % over the HR banks' rating, and on GateLab's test monitor a line whose last pixel was white
// came out one pixel to the side of the others; a black last pixel cured it. 0 sends the picture
// unchanged. One register stage in front of the encoders either way, for timing: the pixels come
// out a clock later than with hdmi_out.
module hdmi_out_bufr #(
    parameter BLACK_LAST_PIXEL = 1
) (
    input  wire       pixel_clk,
    input  wire       lane_clk,
    input  wire       serial_clk,
    input  wire       reset,
    input  wire [7:0] red,
    input  wire [7:0] green,
    input  wire [7:0] blue,
    input  wire       de,
    input  wire       hsync,
    input  wire       vsync,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n
);
    // One stage: a pixel whose successor has `de` low is the line's last.
    reg [23:0] colour = 24'd0;
    reg de_q = 1'b0, hsync_q = 1'b0, vsync_q = 1'b0;
    always @(posedge pixel_clk) begin
        colour <= {red, green, blue};
        de_q <= de;
        hsync_q <= hsync;
        vsync_q <= vsync;
    end
    wire last = BLACK_LAST_PIXEL != 0 && de_q && !de;
    wire [23:0] shown = last ? 24'd0 : colour;

    wire [9:0] word_blue, word_green, word_red;
    tmds_encoder u_blue  (.clk(pixel_clk), .de(de_q), .d(shown[7:0]),   .c0(hsync_q), .c1(vsync_q), .q(word_blue));
    tmds_encoder u_green (.clk(pixel_clk), .de(de_q), .d(shown[15:8]),  .c0(1'b0),    .c1(1'b0),    .q(word_green));
    tmds_encoder u_red   (.clk(pixel_clk), .de(de_q), .d(shown[23:16]), .c0(1'b0),    .c1(1'b0),    .q(word_red));

    // The reset reaches lane_clk through two flip-flops, so the read pointer starts a little after
    // the write pointer. Starting the write pointer at 3 puts the entry being read half the ring
    // away from the entry being written (the testbench measures it for every phase), so a lane
    // clock more or less from the synchroniser can't make them meet.
    reg [1:0] lane_reset_sync = 2'b11;
    always @(posedge lane_clk or posedge reset) begin
        if (reset) lane_reset_sync <= 2'b11;
        else lane_reset_sync <= {lane_reset_sync[0], 1'b0};
    end
    wire lane_reset = lane_reset_sync[1];

    reg [29:0] ring [0:7];
    reg [2:0] write_at = 3'd3, read_at = 3'd0;
    integer i;
    initial for (i = 0; i < 8; i = i + 1) ring[i] = 30'd0;   // LUT RAM starts at 0
    always @(posedge pixel_clk) begin
        ring[write_at] <= {word_red, word_green, word_blue};
        write_at <= reset ? 3'd3 : write_at + 3'd1;
    end
    always @(posedge lane_clk) read_at <= lane_reset ? 3'd0 : read_at + 3'd1;
    wire [29:0] words = ring[read_at];

    hdmi_out_lane u_lane_blue  (.pixel_clk(lane_clk), .serial_clk(serial_clk), .reset(lane_reset), .word(words[9:0]),   .out_p(tmds_d_p[0]), .out_n(tmds_d_n[0]));
    hdmi_out_lane u_lane_green (.pixel_clk(lane_clk), .serial_clk(serial_clk), .reset(lane_reset), .word(words[19:10]), .out_p(tmds_d_p[1]), .out_n(tmds_d_n[1]));
    hdmi_out_lane u_lane_red   (.pixel_clk(lane_clk), .serial_clk(serial_clk), .reset(lane_reset), .word(words[29:20]), .out_p(tmds_d_p[2]), .out_n(tmds_d_n[2]));
    hdmi_out_lane u_lane_clock (.pixel_clk(lane_clk), .serial_clk(serial_clk), .reset(lane_reset), .word(10'b0000011111), .out_p(tmds_clk_p), .out_n(tmds_clk_n));
endmodule

// One TMDS lane: a 10-bit word per pixel clock, bit 0 first, out of a differential pair.
module hdmi_out_lane (
    input  wire       pixel_clk,
    input  wire       serial_clk,
    input  wire       reset,
    input  wire [9:0] word,
    output wire       out_p,
    output wire       out_n
);
`ifdef SYNTHESIS
    wire serial, shift1, shift2;
    OSERDESE2 #(
        .DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"), .DATA_WIDTH(10), .SERDES_MODE("MASTER"),
        .TRISTATE_WIDTH(1), .TBYTE_CTL("FALSE"), .TBYTE_SRC("FALSE")
    ) u_master (
        .CLK(serial_clk), .CLKDIV(pixel_clk), .RST(reset), .OCE(1'b1), .OQ(serial),
        .D1(word[0]), .D2(word[1]), .D3(word[2]), .D4(word[3]), .D5(word[4]), .D6(word[5]), .D7(word[6]), .D8(word[7]),
        .SHIFTIN1(shift1), .SHIFTIN2(shift2), .SHIFTOUT1(), .SHIFTOUT2(),
        .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0), .TCE(1'b0), .TBYTEIN(1'b0), .TBYTEOUT(), .TFB(), .TQ(), .OFB()
    );
    OSERDESE2 #(
        .DATA_RATE_OQ("DDR"), .DATA_RATE_TQ("SDR"), .DATA_WIDTH(10), .SERDES_MODE("SLAVE"),
        .TRISTATE_WIDTH(1), .TBYTE_CTL("FALSE"), .TBYTE_SRC("FALSE")
    ) u_slave (
        .CLK(serial_clk), .CLKDIV(pixel_clk), .RST(reset), .OCE(1'b1), .OQ(),
        .D1(1'b0), .D2(1'b0), .D3(word[8]), .D4(word[9]), .D5(1'b0), .D6(1'b0), .D7(1'b0), .D8(1'b0),
        .SHIFTIN1(1'b0), .SHIFTIN2(1'b0), .SHIFTOUT1(shift1), .SHIFTOUT2(shift2),
        .T1(1'b0), .T2(1'b0), .T3(1'b0), .T4(1'b0), .TCE(1'b0), .TBYTEIN(1'b0), .TBYTEOUT(), .TFB(), .TQ(), .OFB()
    );
    OBUFDS u_out (.I(serial), .O(out_p), .OB(out_n));
`else
    // The word of each pixel clock goes out during the next one, a bit per edge of serial_clk
    // from bit 0 (a counter of serial edges, back at 0 on every rising pixel_clk edge).
    reg [9:0] held = 10'd0;
    reg [3:0] index = 4'd0;
    always @(posedge pixel_clk) held <= word;
    always @(posedge serial_clk or negedge serial_clk) index <= (reset || index == 4'd9) ? 4'd0 : index + 4'd1;
    assign out_p = held[index];
    assign out_n = ~held[index];
`endif
endmodule
