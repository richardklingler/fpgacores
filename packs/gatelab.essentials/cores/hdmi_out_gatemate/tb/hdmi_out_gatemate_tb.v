// Self-checking testbench for hdmi_out on GateMate (the real shift registers and the load from the
// pixel clock's toggle; only the CC_ODDR is a model). The pixel clock comes from the serial clock
// divided by five, as GateLab's GateMate clocks make it, and arrives late through the clock buffer:
// three copies of the core run with it 0, 3.5 and 7 ns behind a 10 ns serial clock. A tiny mode
// (12 × 4 active, 20 × 6 clocks, syncs in the blanking) with colours that differ per channel, pixel
// and line. A receiver per copy samples the four lanes in the middle of every bit, finds the word
// boundary from the clock lane (0000011111, bit 0 first) like a monitor, decodes each channel and
// compares every pixel, data enable and sync with what was sent — in order, at the latency the
// first data word shows.

`timescale 1ns / 1ps

module hdmi_out_gatemate_tb;
    localparam H_TOTAL = 20, H_ACTIVE = 12, V_TOTAL = 6, V_ACTIVE = 4, FRAMES = 3;

    // Serial clock 10 ns; the pixel clock high for two of five serial clocks, as the divider makes it.
    reg serial_clk = 1'b0;
    always #5 serial_clk = ~serial_clk;
    reg [2:0] count = 3'd0;
    reg pixel_divided = 1'b0;
    always @(posedge serial_clk) begin
        count <= count == 3'd4 ? 3'd0 : count + 3'd1;
        pixel_divided <= count < 3'd2;
    end
    wire pixel_early = pixel_divided;
    wire #3.5 pixel_mid = pixel_divided;
    wire #7 pixel_late = pixel_divided;

    // The inputs follow the undelayed pixel clock; each copy takes them at its own edge.
    reg reset = 1'b1;
    reg [7:0] red = 8'd0, green = 8'd0, blue = 8'd0;
    reg de = 1'b0, hsync = 1'b0, vsync = 1'b0;

    // What was sent, one entry per pixel clock: {de, vsync, hsync, red, green, blue}.
    reg [26:0] sent [0:H_TOTAL * V_TOTAL * FRAMES + 63];
    integer pixels = 0, x = 0, y = 0;

    initial begin
        repeat (3) @(posedge pixel_early);
        reset <= 1'b0;
        while (pixels < H_TOTAL * V_TOTAL * FRAMES) begin
            #1;
            de = x < H_ACTIVE && y < V_ACTIVE;
            hsync = x >= 14 && x < 17;
            vsync = y == 5;
            red = x * 17 + y * 3;
            green = 8'hA5 ^ (x * 5) ^ (y << 4);
            blue = 8'd200 - x * 9 - y;
            sent[pixels] = {de, vsync, hsync, red, green, blue};
            pixels = pixels + 1;
            x = x + 1;
            if (x == H_TOTAL) begin x = 0; y = (y + 1) % V_TOTAL; end
            @(posedge pixel_early);
        end
    end

    wire [2:0] clk_p, clk_n;
    wire [2:0] d_p [0:2], d_n [0:2];
    wire [2:0] pixel_clocks = {pixel_late, pixel_mid, pixel_early};
    genvar i;
    generate
        for (i = 0; i < 3; i = i + 1) begin : copy
            hdmi_out dut (
                .pixel_clk(pixel_clocks[i]), .serial_clk(serial_clk), .reset(reset),
                .red(red), .green(green), .blue(blue), .de(de), .hsync(hsync), .vsync(vsync),
                .tmds_clk_p(clk_p[i]), .tmds_clk_n(clk_n[i]), .tmds_d_p(d_p[i]), .tmds_d_n(d_n[i])
            );
            hdmi_out_gatemate_tb_rx #(.COPY(i)) rx (
                .serial_clk(serial_clk), .reset(reset), .clk_p(clk_p[i]), .clk_n(clk_n[i]), .d_p(d_p[i]), .d_n(d_n[i])
            );
        end
    endgenerate

    integer copies_passed = 0;
    initial begin
        $dumpfile("hdmi_out_gatemate_tb.vcd");
        $dumpvars(1, hdmi_out_gatemate_tb);
        wait (pixels == H_TOTAL * V_TOTAL * FRAMES);
        repeat (8) @(posedge pixel_early);
        copies_passed = copy[0].rx.passed(1'b0) + copy[1].rx.passed(1'b0) + copy[2].rx.passed(1'b0);
        if (copies_passed == 3) $display("PASS");
        else $display("FAIL: %0d of 3 copies passed", copies_passed);
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule

// The receiver for one copy; reads what was sent from the testbench.
module hdmi_out_gatemate_tb_rx #(parameter COPY = 0) (
    input wire       serial_clk,
    input wire       reset,
    input wire       clk_p,
    input wire       clk_n,
    input wire [2:0] d_p,
    input wire [2:0] d_n
);
    localparam H_TOTAL = 20, H_ACTIVE = 12, V_TOTAL = 6, V_ACTIVE = 4, FRAMES = 3;

    function [7:0] decode;
        input [9:0] word;
        reg [7:0] v;
        integer k;
        begin
            v = word[9] ? ~word[7:0] : word[7:0];
            decode[0] = v[0];
            for (k = 1; k < 8; k = k + 1) decode[k] = word[8] ? (v[k] ^ v[k - 1]) : ~(v[k] ^ v[k - 1]);
        end
    endfunction

    // Control words carry {c1, c0}; anything else is data. Returns 3'b1xx for data.
    function [2:0] control;
        input [9:0] word;
        begin
            case (word)
                10'b1101010100: control = 3'b000;
                10'b0010101011: control = 3'b001;
                10'b0101010100: control = 3'b010;
                10'b1010101011: control = 3'b011;
                default: control = 3'b100;
            endcase
        end
    endfunction

    reg [9:0] lane_clock = 10'd0, lane_blue = 10'd0, lane_green = 10'd0, lane_red = 10'd0;
    integer errors = 0, received = 0, offset = -1, data_words = 0, syncs = 0, index;
    reg [26:0] wanted;

    always @(serial_clk) begin
        #2.5;
        lane_clock = {clk_p, lane_clock[9:1]};
        lane_blue  = {d_p[0], lane_blue[9:1]};
        lane_green = {d_p[1], lane_green[9:1]};
        lane_red   = {d_p[2], lane_red[9:1]};
        if (clk_n !== ~clk_p || d_n !== ~d_p) begin
            if (errors < 5) $display("FAIL (copy %0d): a lane's N side isn't the inverse of its P side", COPY);
            errors = errors + 1;
        end
        if (!reset && lane_clock == 10'b0000011111) word_boundary;
    end

    task word_boundary;
        reg [2:0] cb, cg, cr;
        begin
            cb = control(lane_blue);
            cg = control(lane_green);
            cr = control(lane_red);
            if (offset < 0 && cb[2]) begin
                for (index = 0; index < hdmi_out_gatemate_tb.pixels && hdmi_out_gatemate_tb.sent[index][26] == 1'b0; index = index + 1) ;
                offset = received - index;
            end
            if (offset >= 0 && received - offset < H_TOTAL * V_TOTAL * FRAMES) begin
                wanted = hdmi_out_gatemate_tb.sent[received - offset];
                if (wanted[26]) begin
                    data_words = data_words + 1;
                    if (cb[2] !== 1'b1 || cg[2] !== 1'b1 || cr[2] !== 1'b1) begin
                        if (errors < 5) $display("FAIL (copy %0d): pixel %0d: a control word during active video", COPY, received - offset);
                        errors = errors + 1;
                    end else if ({decode(lane_red), decode(lane_green), decode(lane_blue)} !== wanted[23:0]) begin
                        if (errors < 5) $display("FAIL (copy %0d): pixel %0d: rgb %h %h %h, sent %h %h %h", COPY, received - offset,
                                                 decode(lane_red), decode(lane_green), decode(lane_blue), wanted[23:16], wanted[15:8], wanted[7:0]);
                        errors = errors + 1;
                    end
                end else begin
                    // Blanking: blue carries {vsync, hsync}, the others 00.
                    if (cb !== {1'b0, wanted[25], wanted[24]} || cg !== 3'b000 || cr !== 3'b000) begin
                        if (errors < 5) $display("FAIL (copy %0d): pixel %0d: control words b %b g %b r %b, sent vsync %b hsync %b", COPY,
                                                 received - offset, cb, cg, cr, wanted[25], wanted[24]);
                        errors = errors + 1;
                    end
                    if (wanted[24] || wanted[25]) syncs = syncs + 1;
                end
            end
            received = received + 1;
        end
    endtask

    // 1 when this copy decoded every pixel and sync it should have.
    function integer passed;
        input dummy;
        begin
            passed = 1;
            if (offset < 0) begin $display("FAIL (copy %0d): no data word was received", COPY); passed = 0; end
            if (data_words < H_ACTIVE * V_ACTIVE * FRAMES - H_ACTIVE) begin
                $display("FAIL (copy %0d): %0d data words checked, expected about %0d", COPY, data_words, H_ACTIVE * V_ACTIVE * FRAMES);
                passed = 0;
            end
            if (syncs < 3 * FRAMES) begin $display("FAIL (copy %0d): only %0d sync words checked", COPY, syncs); passed = 0; end
            if (errors != 0) passed = 0;
        end
    endfunction
endmodule
