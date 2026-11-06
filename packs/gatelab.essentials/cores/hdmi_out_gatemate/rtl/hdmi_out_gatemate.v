// DVI/HDMI output for Cologne Chip GateMate (Essentials, GateMate primitives, 2026-10-15): the ports
// and the encoders of hdmi_out for 7-series, with GateMate's I/O. Three TMDS encoders
// (tmds_encoder) and four lanes: blue (lane 0, with hsync on c0 and vsync on c1), green (1), red (2)
// and the clock lane (five ones, five zeros per pixel). Each lane is a shift register on
// `serial_clk` that takes a word every fifth clock and hands two bits per clock to a CC_ODDR.
//
// Clocks: `serial_clk` is five times `pixel_clk` (DDR: ten bits per pixel). On GateMate the PLL
// makes the serial clock and a counter divides it by five for the pixel clock (GateLab's Add Clock:
// 10 MHz → 125 and 25 MHz for 640×480), so the pixel clock arrives through a CC_BUFG a few
// nanoseconds after the serial edge it came from. The lanes therefore don't count on their own: a
// bit that toggles with every pixel clock is watched on `serial_clk`, and the word is taken two
// serial clocks after its change shows — three after the pixel edge, two before the next word (the
// spike's timing on the EVB, now independent of the divider's delay and start). `reset` is
// synchronous to `pixel_clk`.
//
// CC_ODDR sends D1 before D0 within a clock (found on the GateMate EVB, 2026-10-15; Yosys' model of
// the primitive says the opposite): bit 0 goes into D1. Simulation (no SYNTHESIS) models the pin as
// it is: bit 0 while the clock is high, bit 1 while it's low, both taken at the rising edge.
//
// Pins: P and N are two single-ended outputs, N driven with the inverted bits by its own CC_ODDR, so
// any two pins of a bank serve (the EVB's Pmod pairs sit on pins 1 and 7, not side by side).

// hdmi_out without sound: hdmi_out_audio with silence, the ports of the cores before HDMI audio (a design that
// sends sound instantiates hdmi_out_audio, which has audio_l, audio_r and audio_ready). HDMI = 1 still sends the
// InfoFrames, data islands and all.
module hdmi_out #(
    parameter HDMI = 0,                     // 1: HDMI with audio and InfoFrames (hdmi_encoder); 0: DVI as before
    parameter integer PIXEL_HZ = 74250000,  // the pixel clock, for HDMI's audio clock (CTS = PIXEL_HZ / 1000)
    parameter [6:0] VIC = 7'd4,             // CEA-861 video code in the AVI InfoFrame: 1 = 640x480, 4 = 720p60, 16 = 1080p60
    parameter [1:0] ASPECT = 2'b10          // picture aspect: 01 = 4:3, 10 = 16:9
) (
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
    hdmi_out_audio #(.HDMI(HDMI), .PIXEL_HZ(PIXEL_HZ), .VIC(VIC), .ASPECT(ASPECT)) u_out (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset), .red(red), .green(green), .blue(blue),
        .de(de), .hsync(hsync), .vsync(vsync), .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n), .tmds_d_p(tmds_d_p),
        .tmds_d_n(tmds_d_n),
        .audio_l(16'd0), .audio_r(16'd0), .audio_ready());
endmodule

module hdmi_out_audio #(
    parameter HDMI = 0,                     // 1: HDMI with audio and InfoFrames (hdmi_encoder); 0: DVI as before
    parameter integer PIXEL_HZ = 74250000,  // the pixel clock, for HDMI's audio clock (CTS = PIXEL_HZ / 1000)
    parameter [6:0] VIC = 7'd4,             // CEA-861 video code in the AVI InfoFrame: 1 = 640x480, 4 = 720p60, 16 = 1080p60
    parameter [1:0] ASPECT = 2'b10          // picture aspect: 01 = 4:3, 10 = 16:9
) (
    input  wire       pixel_clk,
    input  wire       serial_clk,
    input  wire       reset,
    input  wire [7:0] red,
    input  wire [7:0] green,
    input  wire [7:0] blue,
    input  wire       de,
    input  wire       hsync,
    input  wire       vsync,
    input  wire [15:0] audio_l,             // HDMI = 1: signed samples, taken while audio_ready is high (48 kHz)
    input  wire [15:0] audio_r,
    output wire       audio_ready,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_d_p,
    output wire [2:0] tmds_d_n
);
    wire [9:0] word_blue, word_green, word_red;
    hdmi_encoder #(.HDMI(HDMI), .PIXEL_HZ(PIXEL_HZ), .VIC(VIC), .ASPECT(ASPECT)) u_encoder (
        .clk(pixel_clk), .red(red), .green(green), .blue(blue), .de(de), .hsync(hsync), .vsync(vsync),
        .audio_l(audio_l), .audio_r(audio_r), .audio_ready(audio_ready),
        .word_blue(word_blue), .word_green(word_green), .word_red(word_red));

    // The lanes, each with its own load timing (below): no signal runs between them, so each sits next to its pins.
    hdmi_out_lane u_lane_blue  (.pixel_clk(pixel_clk), .serial_clk(serial_clk), .word(word_blue),  .out_p(tmds_d_p[0]), .out_n(tmds_d_n[0]));
    hdmi_out_lane u_lane_green (.pixel_clk(pixel_clk), .serial_clk(serial_clk), .word(word_green), .out_p(tmds_d_p[1]), .out_n(tmds_d_n[1]));
    hdmi_out_lane u_lane_red   (.pixel_clk(pixel_clk), .serial_clk(serial_clk), .word(word_red),   .out_p(tmds_d_p[2]), .out_n(tmds_d_n[2]));
    hdmi_out_lane u_lane_clock (.pixel_clk(pixel_clk), .serial_clk(serial_clk), .word(10'b0000011111), .out_p(tmds_clk_p), .out_n(tmds_clk_n));
endmodule

// One lane: a 10-bit word per pixel, bit 0 first, out of two pins.
module hdmi_out_lane (
    input  wire       pixel_clk,
    input  wire       serial_clk,
    input  wire [9:0] word,
    output wire       out_p,
    output wire       out_n
);
    // A pixel-clock toggle, seen on the serial clock: `load` is high for the serial clock before the third serial edge
    // after the pixel edge, worked out one stage early (seen[1] ^ seen[0] now is seen[2] ^ seen[1] a clock later). Each
    // lane has its own: the four start together from the configuration and run on the same clocks, so they stay in
    // step, and the load reaches the lane's ten shift flip-flops without crossing the chip. (One shared load had to
    // reach lanes on pins far apart: 107–140 MHz depending on placement, 126 needed; GateMate primitives step 7, and
    // again with HDMI audio's step 4, where a renamed instance moved it to 111.)
    reg pixel_toggle = 1'b0;
    always @(posedge pixel_clk) pixel_toggle <= ~pixel_toggle;
    (* keep *) reg [1:0] seen = 2'b00;
    (* keep *) reg load = 1'b0;
    always @(posedge serial_clk) begin
        seen <= {seen[0], pixel_toggle};
        load <= seen[1] ^ seen[0];
    end

    reg [9:0] shift = 10'd0;
    // The bits for P and for N (inverted) in registers of their own next to the pins: CC_ODDR takes
    // D1 on the falling edge, so only half a serial clock is left for that hop (GateMate primitives
    // step 7: from the shift register through the inverter it was the slowest path).
    (* keep *) reg [1:0] bits_p = 2'b00, bits_n = 2'b11;
    always @(posedge serial_clk) begin
        shift <= load ? word : {2'b00, shift[9:2]};
        bits_p <= shift[1:0];
        bits_n <= ~shift[1:0];
    end
`ifdef SYNTHESIS
    CC_ODDR u_p (.CLK(serial_clk), .DDR(serial_clk), .D0(bits_p[1]), .D1(bits_p[0]), .Q(out_p));
    CC_ODDR u_n (.CLK(serial_clk), .DDR(serial_clk), .D0(bits_n[1]), .D1(bits_n[0]), .Q(out_n));
`else
    reg [1:0] bits = 2'b00;
    always @(posedge serial_clk) bits <= bits_p;
    assign out_p = serial_clk ? bits[0] : bits[1];
    assign out_n = ~out_p;
`endif
endmodule
