// DVI/HDMI output for Gowin GW1N/GW2A (Essentials, HDMI on Gowin/ECP5, 2026-10-14): the ports and
// the encoders of hdmi_out for 7-series, with Gowin's I/O. Three TMDS encoders (tmds_encoder) and
// four lanes, each a 10:1 OSER10 into a true-LVDS TLVDS_OBUF: blue (lane 0, with hsync on c0 and
// vsync on c1), green (1), red (2) and the clock lane (five ones, five zeros per pixel).
//
// Clocks: `serial_clk` is five times `pixel_clk` (the OSER10's FCLK, DDR: ten bits per pixel) and
// `pixel_clk` its PCLK, in phase: an rPLL for the serial clock and a CLKDIV dividing it by 5
// (GateLab's Add Clock makes that pair; 720p60 and 1080p30: 371.25 and 74.25 MHz from 27).
// `reset` is synchronous to `pixel_clk`: hold it until the PLL has locked.
//
// Pins: each lane a true-LVDS pair, P on the pair's A site and N on its B site, each constrained
// on its own IO_LOC line (nextpnr reads no "P,N" form). Bits go out from bit 0 (D0). Simulation
// (no SYNTHESIS) sends the same bits from a behavioural model on both edges of `serial_clk`.

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

// One lane: a 10-bit word per pixel clock, bit 0 first, out of a true-LVDS pair.
module hdmi_out_lane (
    input  wire       pixel_clk,
    input  wire       serial_clk,
    input  wire       reset,
    input  wire [9:0] word,
    output wire       out_p,
    output wire       out_n
);
`ifdef SYNTHESIS
    wire serial;
    OSER10 u_oser (
        .D0(word[0]), .D1(word[1]), .D2(word[2]), .D3(word[3]), .D4(word[4]),
        .D5(word[5]), .D6(word[6]), .D7(word[7]), .D8(word[8]), .D9(word[9]),
        .FCLK(serial_clk), .PCLK(pixel_clk), .RESET(reset), .Q(serial)
    );
    TLVDS_OBUF u_out (.I(serial), .O(out_p), .OB(out_n));
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
