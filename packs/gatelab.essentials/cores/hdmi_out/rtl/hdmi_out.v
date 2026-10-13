// DVI/HDMI output for AMD Xilinx 7-series (DVI signalling: pixels and syncs, no audio or info
// frames — every HDMI monitor takes it). Three TMDS encoders (tmds_encoder) and four lanes, each a
// 10:1 OSERDESE2 master/slave pair in DDR into an OBUFDS: blue (lane 0, with hsync on c0 and vsync
// on c1), green (1), red (2) and the clock lane (five ones, five zeros per pixel).
//
// Clocks: `serial_clk` is five times `pixel_clk` (DDR: ten bits per pixel), both from one MMCM or
// PLL so they're in phase. On the global buffers (BUFG) that's 720p60 and 1080p30 (74.25 / 371.25
// MHz). 1080p60's 742.5 MHz serial clock is over a BUFG's limit: put it on a BUFIO and the pixel
// clock on a BUFR dividing it by 5, both in the TMDS pins' clock region (GateLab's HDMI spike,
// 2026-10-13). `reset` is synchronous to `pixel_clk`: hold it until the clocks are stable.
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
