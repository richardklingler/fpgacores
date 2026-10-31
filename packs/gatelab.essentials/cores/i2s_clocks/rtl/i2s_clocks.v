// I2S clocks for a codec that is the clock slave (Cirrus CS4344/CS5343, Digilent Pmod I2S2, most DACs and ADCs):
// MCLK, SCLK (64 Fs: 32 bits a channel) and LRCK (Fs, low = left) from the system clock, with counters only,
// all three in step. Fs = clock / (MCLK_DIV · RATIO): 27 MHz / (2 · 512) = 26.37 kHz, 100 MHz / (8 · 256) =
// 48.83 kHz.
//
// The outputs are registered and change together. Two strobes tell transmitters and receivers when:
//   bit_start   the outputs start bit slot `slot_next` (0 … 63) at the next clock edge (SCLK falls then; LRCK
//               changes with slot 0 and 32) — a transmitter registers its data bit on it (i2s_transmitter);
//   bit_sample  an input through a two-flip-flop synchroniser now shows the bit of slot `slot` as it was on
//               the pin one clock before SCLK rose — a receiver takes it then (i2s_receiver). I2S ADCs change
//               their data *after* SCLK's rising edge (the CS5343 holds the old bit at least 40 ns; on the
//               Pmod I2S2 it changed 70–90 ns after), so the bit is taken before that edge, never after it.
// frame_start is bit_start for slot 0.
//
// MCLK_DIV is even and at least 2; RATIO (MCLK per LRCK) a multiple of 64 the codec accepts (256, 384, 512,
// 768); MCLK_DIV · RATIO / 64 (system clocks per SCLK) at least 8.

module i2s_clocks #(
    parameter MCLK_DIV = 2,
    parameter RATIO    = 512
) (
    input  wire       clk,
    output reg        mclk = 1'b0,
    output reg        sclk = 1'b0,
    output reg        lrck = 1'b0,
    output wire       bit_start,
    output wire [5:0] slot_next,
    output wire       bit_sample,
    output wire [5:0] slot,
    output wire       frame_start
);
    localparam S = MCLK_DIV * RATIO / 64;               // system clocks per SCLK
    localparam S_BITS = $clog2(S);
    localparam M_BITS = MCLK_DIV > 2 ? $clog2(MCLK_DIV) : 1;
    // The positions as integers first, then their low bits (a typed localparam set from a 32-bit expression is a
    // truncation warning in Quartus).
    localparam integer S_LAST_I = S - 1, S_HALF_I = S / 2, S_SAMPLE_I = S / 2;
    localparam integer M_LAST_I = MCLK_DIV - 1, M_HALF_I = MCLK_DIV / 2;
    localparam [S_BITS-1:0] S_LAST = S_LAST_I[S_BITS-1:0], S_HALF = S_HALF_I[S_BITS-1:0], S_SAMPLE = S_SAMPLE_I[S_BITS-1:0];
    localparam [M_BITS-1:0] M_LAST = M_LAST_I[M_BITS-1:0], M_HALF = M_HALF_I[M_BITS-1:0];

    reg [S_BITS-1:0] phase = 0;     // position within the SCLK period
    reg [5:0]        slot_q = 6'd0;
    reg [M_BITS-1:0] m = 0;         // position within the MCLK period

    wire             phase_wrap = phase == S_LAST;
    wire [S_BITS-1:0] phase_n = phase_wrap ? {S_BITS{1'b0}} : phase + 1'b1;
    wire [M_BITS-1:0] m_n = m == M_LAST ? {M_BITS{1'b0}} : m + 1'b1;

    assign bit_start = phase_wrap;
    assign slot_next = phase_wrap ? slot_q + 6'd1 : slot_q;
    assign slot = slot_q;
    assign bit_sample = phase == S_SAMPLE;
    assign frame_start = bit_start && slot_next == 6'd0;

    always @(posedge clk) begin
        phase <= phase_n;
        slot_q <= slot_next;
        m <= m_n;
        // Low for the first half of each period: SCLK falls as a slot starts, MCLK as its count starts.
        sclk <= phase_n >= S_HALF;
        mclk <= m_n >= M_HALF;
        lrck <= slot_next[5];
    end
endmodule
