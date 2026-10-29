// Self-checking testbench for i2s_transmitter with i2s_clocks at 8 system clocks per SCLK: a model of a DAC
// (CS4344: I2S, 24 bits, the MSB on the second rising SCLK edge after LRCK changes) decodes the pins, and every
// frame must bring the samples given when `taken` pulsed. The samples are asymmetric (no bit palindromes).
// Prints PASS or every failed check.

`timescale 1ns / 1ps

module i2s_transmitter_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    integer errors = 0;

    wire mclk, sclk, lrck, bit_start, bit_sample, frame_start;
    wire [5:0] slot_next, slot;
    i2s_clocks #(.MCLK_DIV(2), .RATIO(256)) u_clocks (.clk(clk), .mclk(mclk), .sclk(sclk), .lrck(lrck),
        .bit_start(bit_start), .slot_next(slot_next), .bit_sample(bit_sample), .slot(slot), .frame_start(frame_start));

    reg [23:0] left = 24'h000000, right = 24'h000000;
    wire taken, sdin;
    i2s_transmitter dut (.clk(clk), .bit_start(bit_start), .slot_next(slot_next), .left(left), .right(right),
        .taken(taken), .sdin(sdin));

    // New samples after each `taken`; the ones taken are remembered for the DAC's check.
    reg [23:0] sent_left [0:63], sent_right [0:63];
    integer frames_taken = 0;
    reg [23:0] lfsr = 24'h9E3779;
    always @(posedge clk)
        if (taken) begin
            sent_left[frames_taken % 64] = left;
            sent_right[frames_taken % 64] = right;
            frames_taken = frames_taken + 1;
            lfsr = {lfsr[22:0], lfsr[23] ^ lfsr[22] ^ lfsr[21] ^ lfsr[16]};
            left <= lfsr;
            right <= {lfsr[11:0], lfsr[23:12]} ^ 24'hA5C30F;
        end

    // The DAC: a slot counter from LRCK's changes, bits taken on SCLK's rising edge.
    integer dac_slot = 0, frames_heard = 0, taken_per_frame = 0;
    reg lrck_was = 1'b0;
    reg [23:0] shift = 0, heard_left = 0;
    always @(posedge sclk) begin
        if (lrck !== lrck_was) begin
            dac_slot = 0;
            lrck_was = lrck;
        end else begin
            dac_slot = dac_slot + 1;
        end
        if (dac_slot >= 1 && dac_slot <= 24) shift = {shift[22:0], sdin};
        if (dac_slot == 24) begin
            if (!lrck) heard_left = shift;
            else if (frames_heard < frames_taken) begin
                if (heard_left !== sent_left[frames_heard % 64] || shift !== sent_right[frames_heard % 64]) begin
                    if (errors < 8) $display("FAIL: frame %0d heard %h %h, sent %h %h", frames_heard, heard_left, shift,
                                             sent_left[frames_heard % 64], sent_right[frames_heard % 64]);
                    errors = errors + 1;
                end
                frames_heard = frames_heard + 1;
            end
        end
        // Bits outside the data slots are zero.
        if ((dac_slot == 0 || dac_slot > 24) && sdin !== 1'b0) begin
            if (errors < 8) $display("FAIL: a one in slot %0d", dac_slot + (lrck ? 32 : 0));
            errors = errors + 1;
        end
    end

    // `taken` once a frame, with slot 0.
    always @(posedge clk) if (taken && slot != 6'd0) begin
        $display("FAIL: taken off slot 0 (slot %0d)", slot);
        errors = errors + 1;
    end

    initial begin
        #(10 * 512 * 12);   // twelve frames
        if (frames_heard < 10) begin $display("FAIL: only %0d frames heard", frames_heard); errors = errors + 1; end
        if (errors == 0) $display("PASS (%0d frames)", frames_heard);
        $finish;
    end
endmodule
