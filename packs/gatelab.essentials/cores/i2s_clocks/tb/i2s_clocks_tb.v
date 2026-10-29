// Self-checking testbench for i2s_clocks at two settings (12 and 16 system clocks per SCLK): the periods and
// duty of MCLK, SCLK and LRCK, MCLK cycles per frame, LRCK changing with SCLK's falling edge, bit_start and
// slot_next against the slots counted on the pins, and bit_sample against a data pin that changes just before the
// middle of SCLK's high half (so an earlier sample gets the old bit), read through two flip-flops. Prints PASS or every failed check.

`timescale 1ns / 1ps

module i2s_clocks_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    integer errors = 0;

    task check;
        input ok;
        input [8*72-1:0] what;
        begin
            if (!ok) begin
                if (errors < 10) $display("FAIL: %0s at %0t", what, $time);
                errors = errors + 1;
            end
        end
    endtask

    wire mclk_a, sclk_a, lrck_a, start_a, sample_a, frame_a;
    wire [5:0] next_a, slot_a;
    i2s_clocks #(.MCLK_DIV(2), .RATIO(384)) dut_a (.clk(clk), .mclk(mclk_a), .sclk(sclk_a), .lrck(lrck_a),
        .bit_start(start_a), .slot_next(next_a), .bit_sample(sample_a), .slot(slot_a), .frame_start(frame_a));
    wire mclk_b, sclk_b, lrck_b, start_b, sample_b, frame_b;
    wire [5:0] next_b, slot_b;
    i2s_clocks #(.MCLK_DIV(4), .RATIO(256)) dut_b (.clk(clk), .mclk(mclk_b), .sclk(sclk_b), .lrck(lrck_b),
        .bit_start(start_b), .slot_next(next_b), .bit_sample(sample_b), .slot(slot_b), .frame_start(frame_b));

    // One checker per instance, counting in system clocks.
    `define CHECKER(NAME, MCLK, SCLK, LRCK, START, NEXT, SAMPLE, SLOT, FRAME, MDIV, RAT) \
    integer NAME``_t = 0, NAME``_m_rise = -1, NAME``_s_rise = -1, NAME``_s_fall = -1, NAME``_l_fall = -1; \
    integer NAME``_m_per_frame = 0, NAME``_pin_slot = -1, NAME``_frames = 0, NAME``_samples = 0; \
    reg NAME``_m_was = 0, NAME``_s_was = 0, NAME``_l_was = 0, NAME``_start_was = 0; \
    reg [5:0] NAME``_next_was = 0; \
    reg [1:0] NAME``_sync = 0; reg NAME``_data = 0; \
    always @(posedge clk) begin \
        NAME``_t = NAME``_t + 1; \
        NAME``_sync <= {NAME``_sync[0], NAME``_data}; \
        if (MCLK && !NAME``_m_was) begin \
            if (NAME``_m_rise >= 0) check(NAME``_t - NAME``_m_rise == MDIV, `"NAME MCLK period`"); \
            NAME``_m_rise = NAME``_t; NAME``_m_per_frame = NAME``_m_per_frame + 1; \
        end \
        if (!MCLK && NAME``_m_was && NAME``_m_rise >= 0) check(NAME``_t - NAME``_m_rise == MDIV / 2, `"NAME MCLK high half`"); \
        if (SCLK && !NAME``_s_was) begin \
            if (NAME``_s_rise >= 0) check(NAME``_t - NAME``_s_rise == MDIV * RAT / 64, `"NAME SCLK period`"); \
            NAME``_s_rise = NAME``_t; \
        end \
        if (!SCLK && NAME``_s_was) begin \
            if (NAME``_s_rise >= 0) check(NAME``_t - NAME``_s_rise == MDIV * RAT / 128, `"NAME SCLK high half`"); \
            NAME``_s_fall = NAME``_t; \
            NAME``_pin_slot = NAME``_pin_slot >= 0 ? (NAME``_pin_slot + 1) % 64 : -1; \
            check(NAME``_start_was, `"NAME SCLK fell without bit_start the clock before`"); \
            if (NAME``_pin_slot >= 0) check(NAME``_next_was == NAME``_pin_slot, `"NAME slot_next against the slot on the pins`"); \
            /* The data pin changes half a clock before the middle of the high half (counted from the edge SCLK fell on, \
               a clock before this check sees it): an earlier read gets the old bit */ \
            NAME``_data <= #((MDIV * RAT / 128 + MDIV * RAT / 256) * 10 - 15) (NAME``_pin_slot >= 0 ? NAME``_pin_slot[0] ^ NAME``_pin_slot[1] : 1'b0); \
        end \
        if (SCLK != NAME``_s_was) ; else if (NAME``_start_was && NAME``_s_was) check(0, `"NAME bit_start without SCLK falling`"); \
        if (LRCK != NAME``_l_was) begin \
            check(!SCLK && NAME``_s_was, `"NAME LRCK changed off SCLK's falling edge`"); \
            if (!LRCK) begin \
                if (NAME``_l_fall >= 0) begin \
                    check(NAME``_t - NAME``_l_fall == MDIV * RAT, `"NAME LRCK period`"); \
                    check(NAME``_m_per_frame == RAT, `"NAME MCLK cycles per frame`"); \
                    NAME``_frames = NAME``_frames + 1; \
                end \
                NAME``_l_fall = NAME``_t; NAME``_m_per_frame = 0; NAME``_pin_slot = 0; \
            end \
        end \
        if (SAMPLE && NAME``_pin_slot >= 0 && NAME``_t - NAME``_l_fall > 2) begin \
            check(SLOT == NAME``_pin_slot, `"NAME slot at bit_sample`"); \
            check(NAME``_sync[1] == (NAME``_pin_slot[0] ^ NAME``_pin_slot[1]), `"NAME bit_sample reads the bit of its slot`"); \
            NAME``_samples = NAME``_samples + 1; \
        end \
        if (FRAME) check(NEXT == 6'd0 && START, `"NAME frame_start off slot 0`"); \
        NAME``_m_was = MCLK; NAME``_s_was = SCLK; NAME``_l_was = LRCK; NAME``_start_was = START; NAME``_next_was = NEXT; \
    end

    `CHECKER(a, mclk_a, sclk_a, lrck_a, start_a, next_a, sample_a, slot_a, frame_a, 2, 384)
    `CHECKER(b, mclk_b, sclk_b, lrck_b, start_b, next_b, sample_b, slot_b, frame_b, 4, 256)

    initial begin
        #(10 * 1024 * 6);   // six frames of the longer setting
        check(a_frames >= 4 && b_frames >= 4, "too few frames");
        check(a_samples >= 4 * 64 && b_samples >= 4 * 64, "too few samples checked");
        if (errors == 0) $display("PASS (%0d and %0d frames, %0d and %0d bits sampled)", a_frames, b_frames, a_samples, b_samples);
        $finish;
    end
endmodule
