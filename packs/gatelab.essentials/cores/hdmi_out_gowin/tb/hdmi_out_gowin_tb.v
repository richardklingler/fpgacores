// Self-checking testbench for hdmi_out on Gowin (the simulation lanes: the OSER10's model):
// a tiny mode (12 × 4 active, 20 × 6
// clocks, syncs in the blanking) with colours that differ per channel, pixel and line. A receiver
// samples the four lanes in the middle of every bit, finds the word boundary from the clock lane
// (0000011111, bit 0 first) like a monitor, decodes each channel and compares every pixel, data
// enable and sync with what was sent — in order, at the latency the first data word shows.

`timescale 1ns / 1ps

module hdmi_out_gowin_tb;
    // Pixel clock 50 ns, serial clock 10 ns (five times, DDR: ten bits per pixel), in phase.
    reg pixel_clk = 1'b0, serial_clk = 1'b0;
    always #25 pixel_clk = ~pixel_clk;
    always #5 serial_clk = ~serial_clk;

    reg reset = 1'b1;
    reg [7:0] red = 8'd0, green = 8'd0, blue = 8'd0;
    reg de = 1'b0, hsync = 1'b0, vsync = 1'b0;
    wire tmds_clk_p, tmds_clk_n;
    wire [2:0] tmds_d_p, tmds_d_n;

    hdmi_out dut (
        .pixel_clk(pixel_clk), .serial_clk(serial_clk), .reset(reset),
        .red(red), .green(green), .blue(blue), .de(de), .hsync(hsync), .vsync(vsync),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n), .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n)
    );

    // What was sent, one entry per pixel clock: {de, vsync, hsync, red, green, blue}.
    localparam H_TOTAL = 20, H_ACTIVE = 12, V_TOTAL = 6, V_ACTIVE = 4, FRAMES = 3;
    reg [26:0] sent [0:H_TOTAL * V_TOTAL * FRAMES + 63];
    integer pixels = 0, x = 0, y = 0;

    initial begin
        repeat (3) @(posedge pixel_clk);
        reset <= 1'b0;
        while (pixels < H_TOTAL * V_TOTAL * FRAMES) begin
            // New inputs right after an edge, taken by the encoders at the next one.
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
            @(posedge pixel_clk);
        end
    end

    // The receiver.
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
        // Bit 0 arrives first: shift in from the top.
        lane_clock = {tmds_clk_p, lane_clock[9:1]};
        lane_blue  = {tmds_d_p[0], lane_blue[9:1]};
        lane_green = {tmds_d_p[1], lane_green[9:1]};
        lane_red   = {tmds_d_p[2], lane_red[9:1]};
        if (tmds_clk_n !== ~tmds_clk_p || tmds_d_n !== ~tmds_d_p) begin
            $display("FAIL: a lane's N side isn't the inverse of its P side");
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
            // The first data word fixes the latency: it's the first pixel sent with de high.
            if (offset < 0 && !cb[2]) begin
                // still blanking
            end else if (offset < 0) begin
                for (index = 0; index < pixels && sent[index][26] == 1'b0; index = index + 1) ;
                offset = received - index;
            end
            if (offset >= 0 && received - offset < H_TOTAL * V_TOTAL * FRAMES) begin
                wanted = sent[received - offset];
                if (wanted[26]) begin
                    data_words = data_words + 1;
                    if (cb[2] !== 1'b1 || cg[2] !== 1'b1 || cr[2] !== 1'b1) begin
                        $display("FAIL: pixel %0d: a control word during active video", received - offset);
                        errors = errors + 1;
                    end else if ({decode(lane_red), decode(lane_green), decode(lane_blue)} !== wanted[23:0]) begin
                        $display("FAIL: pixel %0d: rgb %h %h %h, sent %h %h %h", received - offset,
                                 decode(lane_red), decode(lane_green), decode(lane_blue), wanted[23:16], wanted[15:8], wanted[7:0]);
                        errors = errors + 1;
                    end
                end else begin
                    // Blanking: blue carries {vsync, hsync}, the others 00.
                    if (cb !== {1'b0, wanted[25], wanted[24]} || cg !== 3'b000 || cr !== 3'b000) begin
                        $display("FAIL: pixel %0d: control words b %b g %b r %b, sent vsync %b hsync %b", received - offset,
                                 cb, cg, cr, wanted[25], wanted[24]);
                        errors = errors + 1;
                    end
                    if (wanted[24] || wanted[25]) syncs = syncs + 1;
                end
            end
            received = received + 1;
            if (errors > 5) begin $display("FAIL: too many errors"); $finish; end
        end
    endtask

    initial begin
        $dumpfile("hdmi_out_gowin_tb.vcd");
        $dumpvars(0, hdmi_out_gowin_tb);
        wait (pixels == H_TOTAL * V_TOTAL * FRAMES);
        repeat (8) @(posedge pixel_clk);
        if (offset < 0) begin $display("FAIL: no data word was received"); errors = errors + 1; end
        if (data_words < H_ACTIVE * V_ACTIVE * FRAMES - H_ACTIVE) begin
            $display("FAIL: %0d data words checked, expected about %0d", data_words, H_ACTIVE * V_ACTIVE * FRAMES);
            errors = errors + 1;
        end
        if (syncs < 3 * FRAMES) begin $display("FAIL: only %0d sync words checked", syncs); errors = errors + 1; end
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
