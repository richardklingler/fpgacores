// DVI/HDMI output for Lattice ECP5 (Essentials, HDMI on Gowin/ECP5, 2026-10-14): the ports and
// the encoders of hdmi_out for 7-series, with ECP5's I/O. Three TMDS encoders (tmds_encoder) and
// four lanes: blue (lane 0, with hsync on c0 and vsync on c1), green (1), red (2) and the clock lane
// (five ones, five zeros per pixel). ECP5 has no 10:1 serialiser: each lane is a shift register on
// `serial_clk` that takes a word every fifth clock and hands two bits per clock to an ODDRX1F.
//
// Clocks: `serial_clk` is five times `pixel_clk` (DDR: ten bits per pixel), both from one EHXPLLL
// so they stay in phase (GateLab's Add Clock: 25 MHz → 74 and 370 MHz for 720p60, 0.34 % under
// HDMI's 74.25). The shift register's load comes from a free-running one-hot ring of five, straight
// from a flip-flop: on a -6 part it closes at about 410 MHz (a counter's compare went into the
// flip-flops' set/reset logic and reached 280). `reset` is synchronous to `pixel_clk`; the ring
// needs none.
//
// Pins: P and N are two single-ended LVCMOS33 outputs, N driven with the inverted bits by its own
// ODDRX1F, so any two pins of a bank serve (the Colorlight i5/i9 extension board's HDMI). Bits go
// out from bit 0. Simulation (no SYNTHESIS) runs the same shift register; only the ODDRX1F is a
// model (D0 while the clock is high, D1 while low, both taken at the rising edge).

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

    hdmi_out_lane u_lane_blue  (.pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset), .word(word_blue),  .out_p(tmds_d_p[0]), .out_n(tmds_d_n[0]));
    hdmi_out_lane u_lane_green (.pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset), .word(word_green), .out_p(tmds_d_p[1]), .out_n(tmds_d_n[1]));
    hdmi_out_lane u_lane_red   (.pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset), .word(word_red),   .out_p(tmds_d_p[2]), .out_n(tmds_d_n[2]));
    hdmi_out_lane u_lane_clock (.pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset), .word(10'b0000011111), .out_p(tmds_clk_p), .out_n(tmds_clk_n));
endmodule

// One lane: a 10-bit word per pixel clock, bit 0 first, out of two LVCMOS33 pins.
module hdmi_out_lane (
    input  wire       pixel_clk,
    input  wire       serial_clk,
    input  wire       reset,
    input  wire [9:0] word,
    output wire       out_p,
    output wire       out_n
);
    // Five serial clocks per pixel, two bits per clock: load every fifth clock, shift by two.
    // N has a shift register of its own with the inverted word, so both ODDRX1Fs take their bits
    // straight from flip-flops: an inverter between them was the 370 MHz path in a larger design
    // (354 MHz on the i9 with the image, text and sprite template). Both registers rotate rather
    // than shift constants in: a constant made Yosys load those bits through the flip-flops'
    // set/reset (LSR), and the ring's path through a LUT into LSR missed 370 MHz in the test card
    // (322–357 MHz). The bits rotated round are reloaded before they go out.
    reg [4:0] ring = 5'b00001;
    reg [9:0] shift = 10'd0;
    reg [9:0] shift_n = 10'h3FF;
    always @(posedge serial_clk) begin
        ring <= {ring[3:0], ring[4]};
        shift <= ring[4] ? word : {shift[1:0], shift[9:2]};
        shift_n <= ring[4] ? ~word : {shift_n[1:0], shift_n[9:2]};
    end
`ifdef SYNTHESIS
    ODDRX1F u_p (.SCLK(serial_clk), .RST(1'b0), .D0(shift[0]), .D1(shift[1]), .Q(out_p));
    ODDRX1F u_n (.SCLK(serial_clk), .RST(1'b0), .D0(shift_n[0]), .D1(shift_n[1]), .Q(out_n));
`else
    reg [1:0] bits = 2'b00, bits_n = 2'b11;
    always @(posedge serial_clk) begin
        bits <= shift[1:0];
        bits_n <= shift_n[1:0];
    end
    assign out_p = serial_clk ? bits[0] : bits[1];
    assign out_n = serial_clk ? bits_n[0] : bits_n[1];
`endif
endmodule
