// Self-checking testbench for i2s_receiver with i2s_clocks at 8 system clocks per SCLK: a model of an ADC
// (CS5343: I2S, 24 bits, data changed on SCLK's falling edge, valid 35 ns later — of a 40 ns half period, so only a
// sample at the rising edge reads it)
// sends asymmetric samples; each `valid` must bring the frame sent, left and right. Prints PASS or every
// failed check.

`timescale 1ns / 1ps

module i2s_receiver_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    integer errors = 0;

    wire mclk, sclk, lrck, bit_start, bit_sample, frame_start;
    wire [5:0] slot_next, slot;
    i2s_clocks #(.MCLK_DIV(2), .RATIO(256)) u_clocks (.clk(clk), .mclk(mclk), .sclk(sclk), .lrck(lrck),
        .bit_start(bit_start), .slot_next(slot_next), .bit_sample(bit_sample), .slot(slot), .frame_start(frame_start));

    reg sdout = 1'b0;
    wire [23:0] left, right;
    wire valid;
    i2s_receiver dut (.clk(clk), .bit_sample(bit_sample), .slot(slot), .sdout(sdout), .left(left), .right(right), .valid(valid));

    // The ADC: LRCK's change seen on SCLK's rising edge (LRCK changes on the falling one, so reading it there
    // would race), a new word for the channel, each bit out on the next falling edge: the MSB one SCLK after
    // LRCK changed.
    reg [23:0] lfsr = 24'h5F3A91, word = 0;
    reg [23:0] sent_left [0:63], sent_right [0:63];
    integer adc_slot = 0, frames_sent = 0;
    reg lrck_was = 1'b0;
    always @(posedge sclk) begin
        if (lrck !== lrck_was) begin
            adc_slot = 0;
            lrck_was = lrck;
            lfsr = {lfsr[22:0], lfsr[23] ^ lfsr[22] ^ lfsr[21] ^ lfsr[16]};
            word = lrck ? lfsr ^ 24'h0F1E2D : lfsr;
            if (!lrck) sent_left[frames_sent % 64] = word;
            else begin
                sent_right[frames_sent % 64] = word;
                frames_sent = frames_sent + 1;
            end
        end else begin
            adc_slot = adc_slot + 1;
        end
    end
    always @(negedge sclk)
        sdout <= #35 (adc_slot + 1 >= 1 && adc_slot + 1 <= 24 ? word[24 - (adc_slot + 1)] : 1'b1);   // ones between words

    integer frames_got = 0;
    always @(posedge clk)
        if (valid) begin
            // The first frame may have started before the ADC's first word.
            if (frames_got > 0 && (left !== sent_left[frames_got % 64] || right !== sent_right[frames_got % 64])) begin
                if (errors < 8) $display("FAIL: frame %0d got %h %h, sent %h %h", frames_got, left, right,
                                         sent_left[frames_got % 64], sent_right[frames_got % 64]);
                errors = errors + 1;
            end
            frames_got = frames_got + 1;
        end

    initial begin
        #(10 * 512 * 12);
        if (frames_got < 10) begin $display("FAIL: only %0d frames received", frames_got); errors = errors + 1; end
        if (errors == 0) $display("PASS (%0d frames)", frames_got);
        $finish;
    end
endmodule
