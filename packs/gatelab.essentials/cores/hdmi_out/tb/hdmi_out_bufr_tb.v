// Self-checking testbench for hdmi_out_bufr (its simulation lanes). Four copies run side by side:
// pixel_clk lags lane_clk by 0, 30 % and 70 % of a period with BLACK_LAST_PIXEL on, and by 50 %
// with it off — the core must not depend on the phase between its two word clocks. Each copy
// sends a tiny mode (12 × 4 active, 20 × 6 clocks) with colours that differ per channel, pixel and
// line; a receiver finds the word boundary from the clock lane like a monitor, decodes each
// channel and compares every pixel, data enable and sync with what was sent, at the latency the
// first data word shows. With BLACK_LAST_PIXEL each line's last pixel must arrive black.

`timescale 1ns / 1ps

module hdmi_out_bufr_check #(
    parameter real PHASE = 0.0,       // pixel_clk's lag behind lane_clk, in ns (period 50)
    parameter BLACK_LAST_PIXEL = 1
) (
    output reg done = 1'b0,
    output integer errors
);
    // The serial clock (10 ns, DDR: ten bits per word), the BUFR's lane clock counted down from
    // its edges, and the BUFG's pixel clock: the same frequency, a fixed phase behind.
    reg serial_clk = 1'b0, lane_clk = 1'b0, pixel_clk = 1'b0;
    integer serial_edges = 0;
    always #5 serial_clk = ~serial_clk;
    always @(serial_clk) begin
        if (serial_edges % 5 == 0) lane_clk = ~lane_clk;
        serial_edges = serial_edges + 1;
    end
    always @(lane_clk) pixel_clk <= #(PHASE) lane_clk;

    reg reset = 1'b1;
    reg [7:0] red = 8'd0, green = 8'd0, blue = 8'd0;
    reg de = 1'b0, hsync = 1'b0, vsync = 1'b0;
    wire tmds_clk_p, tmds_clk_n;
    wire [2:0] tmds_d_p, tmds_d_n;

    hdmi_out_bufr #(.BLACK_LAST_PIXEL(BLACK_LAST_PIXEL)) dut (
        .pixel_clk(pixel_clk), .lane_clk(lane_clk), .serial_clk(serial_clk), .reset(reset),
        .red(red), .green(green), .blue(blue), .de(de), .hsync(hsync), .vsync(vsync),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n), .tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n)
    );

    // The crossing: the word the serialisers take may change only when the read pointer moves (a
    // lane_clk edge). A change at any other time is a write to the entry being read — on hardware
    // a word caught half-written. (At a phase of 0 the writes fall on lane_clk edges, so the other
    // phases are the ones that catch it.)
    realtime lane_edge = -1.0;
    integer collisions = 0;
    always @(posedge lane_clk) lane_edge = $realtime;
    always @(dut.words) begin
        if (!reset && !dut.lane_reset && $realtime != lane_edge) begin
            if (collisions == 0) $display("FAIL (phase %0.1f ns): the entry being read was written at %0t", PHASE, $time);
            collisions = collisions + 1;
            errors = errors + 1;
        end
    end

    // What should arrive, one entry per pixel clock: {de, vsync, hsync, red, green, blue}.
    localparam H_TOTAL = 20, H_ACTIVE = 12, V_TOTAL = 6, V_ACTIVE = 4, FRAMES = 3;
    reg [26:0] sent [0:H_TOTAL * V_TOTAL * FRAMES + 63];
    integer pixels = 0, x = 0, y = 0;

    initial begin
        errors = 0;
        repeat (3) @(posedge pixel_clk);
        reset <= 1'b0;
        while (pixels < H_TOTAL * V_TOTAL * FRAMES) begin
            // New inputs right after an edge, taken at the next one.
            #1;
            de = x < H_ACTIVE && y < V_ACTIVE;
            hsync = x >= 14 && x < 17;
            vsync = y == 5;
            red = x * 17 + y * 3 + 7;
            green = 8'hA5 ^ (x * 5) ^ (y << 4);
            blue = 8'd200 - x * 9 - y;
            sent[pixels] = {de, vsync, hsync, (BLACK_LAST_PIXEL != 0 && de && x == H_ACTIVE - 1) ? 24'd0 : {red, green, blue}};
            pixels = pixels + 1;
            x = x + 1;
            if (x == H_TOTAL) begin x = 0; y = (y + 1) % V_TOTAL; end
            @(posedge pixel_clk);
        end
    end

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

    // Control words carry {c1, c0}; anything else is data (3'b1xx).
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
    integer received = 0, offset = -1, data_words = 0, black_words = 0, syncs = 0, index;
    reg seen_blanking = 1'b0;   // like a monitor: lock on the blanking first
    reg [26:0] wanted;

    always @(serial_clk) begin
        #2.5;
        lane_clock = {tmds_clk_p, lane_clock[9:1]};
        lane_blue  = {tmds_d_p[0], lane_blue[9:1]};
        lane_green = {tmds_d_p[1], lane_green[9:1]};
        lane_red   = {tmds_d_p[2], lane_red[9:1]};
        if (tmds_clk_n !== ~tmds_clk_p || tmds_d_n !== ~tmds_d_p) begin
            $display("FAIL (phase %0.1f ns): a lane's N side isn't the inverse of its P side", PHASE);
            errors = errors + 1;
        end
        if (!reset && !done && lane_clock == 10'b0000011111) word_boundary;
    end

    task word_boundary;
        reg [2:0] cb, cg, cr;
        begin
            cb = control(lane_blue);
            cg = control(lane_green);
            cr = control(lane_red);
            if (!cb[2] && !cg[2] && !cr[2]) seen_blanking = 1'b1;
            if (offset < 0 && seen_blanking && cb[2]) begin
                // The first data word fixes the latency: the first pixel sent with de high.
                for (index = 0; index < pixels && sent[index][26] == 1'b0; index = index + 1) ;
                offset = received - index;
            end
            if (offset >= 0 && received - offset < H_TOTAL * V_TOTAL * FRAMES) begin
                wanted = sent[received - offset];
                if (wanted[26]) begin
                    data_words = data_words + 1;
                    if (wanted[23:0] == 24'd0) black_words = black_words + 1;
                    if (cb[2] !== 1'b1 || cg[2] !== 1'b1 || cr[2] !== 1'b1) begin
                        $display("FAIL (phase %0.1f ns): pixel %0d: a control word during active video", PHASE, received - offset);
                        errors = errors + 1;
                    end else if ({decode(lane_red), decode(lane_green), decode(lane_blue)} !== wanted[23:0]) begin
                        $display("FAIL (phase %0.1f ns): pixel %0d: rgb %h %h %h, expected %h %h %h", PHASE, received - offset,
                                 decode(lane_red), decode(lane_green), decode(lane_blue), wanted[23:16], wanted[15:8], wanted[7:0]);
                        errors = errors + 1;
                    end
                end else begin
                    if (cb !== {1'b0, wanted[25], wanted[24]} || cg !== 3'b000 || cr !== 3'b000) begin
                        $display("FAIL (phase %0.1f ns): pixel %0d: control words b %b g %b r %b, sent vsync %b hsync %b", PHASE,
                                 received - offset, cb, cg, cr, wanted[25], wanted[24]);
                        errors = errors + 1;
                    end
                    if (wanted[24] || wanted[25]) syncs = syncs + 1;
                end
            end
            received = received + 1;
            if (errors > 5) done = 1'b1;
        end
    endtask

    initial begin
        wait (pixels == H_TOTAL * V_TOTAL * FRAMES);
        repeat (12) @(posedge pixel_clk);
        if (offset < 0) begin $display("FAIL (phase %0.1f ns): no data word was received", PHASE); errors = errors + 1; end
        if (data_words < H_ACTIVE * V_ACTIVE * FRAMES - H_ACTIVE) begin
            $display("FAIL (phase %0.1f ns): %0d data words checked, expected about %0d", PHASE, data_words, H_ACTIVE * V_ACTIVE * FRAMES);
            errors = errors + 1;
        end
        // Only the blacked-out last pixels are black: the colours above never are.
        if (BLACK_LAST_PIXEL != 0 && black_words < V_ACTIVE * FRAMES - 1) begin
            $display("FAIL (phase %0.1f ns): only %0d black last pixels checked", PHASE, black_words); errors = errors + 1;
        end
        if (syncs < 3 * FRAMES) begin $display("FAIL (phase %0.1f ns): only %0d sync words checked", PHASE, syncs); errors = errors + 1; end
        done = 1'b1;
    end
endmodule

module hdmi_out_bufr_tb;
    wire [3:0] done;
    integer errors [0:3];
    hdmi_out_bufr_check #(.PHASE(0.0),  .BLACK_LAST_PIXEL(1)) check_0  (.done(done[0]), .errors(errors[0]));
    hdmi_out_bufr_check #(.PHASE(15.0), .BLACK_LAST_PIXEL(1)) check_30 (.done(done[1]), .errors(errors[1]));
    hdmi_out_bufr_check #(.PHASE(35.0), .BLACK_LAST_PIXEL(1)) check_70 (.done(done[2]), .errors(errors[2]));
    hdmi_out_bufr_check #(.PHASE(25.0), .BLACK_LAST_PIXEL(0)) check_50 (.done(done[3]), .errors(errors[3]));

    initial begin
        $dumpfile("hdmi_out_bufr_tb.vcd");
        $dumpvars(1, check_30);
        $dumpvars(1, check_30.dut);
        wait (&done);
        if (errors[0] + errors[1] + errors[2] + errors[3] == 0) $display("PASS");
        $finish;
    end

    initial begin
        #1000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
