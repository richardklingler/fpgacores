// gtx_10g — AMD Kintex-7 GTX transceivers at 10.3125 Gb/s (10GBASE-R line rate) from a 156.25 MHz reference, with
// GateLab's reset sequence, the GTX's own PRBS31 generator and checker, and the 64B/66B gearbox's 64-bit interface for a
// PCS: a block a cycle at 161.13 MHz. CC0 1.0 (public domain).
//
// One quad: MGTREFCLK0 (refclk_p/n) -> IBUFDS_GTE2 -> GTXE2_COMMON (QPLL x66 = 10.3125 GHz) -> CHANNELS GTXE2_CHANNELs
// (0 = the quad's channel 0 …; the placer picks the quad from the pins). The attribute values are the free Vivado's GT
// wizard 10GBASE-R preset for this transceiver with its 64-bit fabric width (GateLab's SFP+ milestone, steps 1 and 5);
// every input the wizard ties is tied the same — an input left open on the fabric isn't the primitive's default (open
// TXPD/RXPD power the PMAs down).
//
// Clocks: the GTX converts 64 <-> 32 bits itself; its user clocks come from an MMCM per direction as in the wizard's
// example (VCO 2 x 322.27 MHz): 322.27 MHz for TXUSRCLK/RXUSRCLK, which only the transceiver sees, and 161.13 MHz for
// TXUSRCLK2/RXUSRCLK2 — tx_clk (from channel 0's TXOUTCLK) for every channel's TX, rx_clk[n] (from channel n's recovered
// RXOUTCLK) for its RX: the gearbox mode has no clock correction, so a link partner's own ±100 ppm must not meet another
// channel's clock. clk is a free-running clock (CLK_HZ) for the reset sequence and the status.
//
// Reset sequence (on clk): 1 ms after configuration QPLLRESET for 1 us, QPLL lock, GTTXRESET released, the transmit MMCM
// released after 10 us and locked, TXUSERRDY, every TXRESETDONE: tx_ready. Then per channel GTRXRESET for 1 us, the
// channel's receive MMCM released after 10 us and locked, RXUSERRDY, RXRESETDONE: rx_ready. A channel's receiver is reset
// again on rx_restart (a PCS that lost block lock asks for it), when its MMCM loses lock (the recovered clock went: the
// fibre was pulled) and, with prbs on, after RETRY_MS milliseconds with PRBS errors in a row. With the DFE equaliser
// (lpm 0) its AGC and low-frequency loops are held after 4 good milliseconds, as the wizard does after its adaptation
// time. Changing lpm or near_loopback resets the receivers.
//
// Gearbox (UG476, 64B/66B with the external sequence counter, 8-byte interface): tx_sequence counts 0 … 32 on tx_clk, a
// block a cycle — tx_header (2 bits) and tx_data (64 bits) — and the cycle at 32 carries none. On the receive side
// rx_data_valid is low one cycle in 33, rx_header_valid comes with each block, and rx_slip (a pulse) moves the block
// boundary by one bit while a PCS looks for block lock. With prbs on, the PRBS31 generator replaces the TX data and the
// checker counts error words (prbs_errors, on clk).
//
// Simulation: without SYNTHESIS (Icarus) a stand-in replaces the transceivers and MMCMs — AMD's models are encrypted. It
// locks, runs the clocks at 161.13 MHz, finishes the resets and hands channel n's receiver the blocks channel
// SIM_PARTNER(n) sent (SIM_CROSS 1: 0 <-> 1, the fibre between two cages; near_loopback: its own), already block-aligned
// (rx_slip does nothing). A testbench drives g_ch[n].sim_errors (error words to report) and g_ch[n].sim_no_link (no
// signal: random words, PRBS errors all the time).
`timescale 1ns / 1ps

module gtx_10g #(
    parameter CLK_HZ = 50000000,
    // Transceivers in the quad, 1 … 4.
    parameter CHANNELS = 2,
    // TX swing (TXDIFFCTRL): 4'b1000 is about 810 mV differential, fine for SFP+ modules.
    parameter [3:0] TX_DIFF_CTRL = 4'b1000,
    // Milliseconds of PRBS errors in a row before a receiver is reset again.
    parameter RETRY_MS = 100,
    // Simulation: cycles of clk per millisecond (a testbench shortens the waits), and the stand-in's crossing.
    parameter MS_CYCLES = CLK_HZ / 1000,
    parameter SIM_CROSS = 1
) (
    input  wire                     clk,
    input  wire                     reset,              // on clk: start the whole sequence again
    input  wire                     refclk_p,
    input  wire                     refclk_n,
    output wire [CHANNELS-1:0]      txp,
    output wire [CHANNELS-1:0]      txn,
    input  wire [CHANNELS-1:0]      rxp,
    input  wire [CHANNELS-1:0]      rxn,

    // Status and control, on clk.
    output wire                     qpll_lock,
    output wire                     tx_ready,
    output wire [CHANNELS-1:0]      rx_ready,
    output wire [16*CHANNELS-1:0]   rx_retries,
    input  wire [CHANNELS-1:0]      rx_restart,         // a rising edge (from any clock, held 3 clk cycles) resets one receiver
    input  wire                     prbs,
    input  wire                     near_loopback,
    input  wire                     lpm,
    input  wire [CHANNELS-1:0]      rx_invert,
    output wire [32*CHANNELS-1:0]   prbs_errors,
    input  wire                     prbs_clear,

    // Transmit, on tx_clk (161.13 MHz).
    output wire                     tx_clk,
    output wire [5:0]               tx_sequence,
    input  wire [64*CHANNELS-1:0]   tx_data,
    input  wire [2*CHANNELS-1:0]    tx_header,

    // Receive, channel n on rx_clk[n] (161.13 MHz).
    output wire [CHANNELS-1:0]      rx_clk,
    output wire [64*CHANNELS-1:0]   rx_data,
    output wire [2*CHANNELS-1:0]    rx_header,
    output wire [CHANNELS-1:0]      rx_data_valid,
    output wire [CHANNELS-1:0]      rx_header_valid,
    input  wire [CHANNELS-1:0]      rx_slip
);
    localparam US_CYCLES = MS_CYCLES / 1000 > 0 ? MS_CYCLES / 1000 : 1;

    // ---- Settings that restart the receivers --------------------------------------------------------------------
    reg lpm_seen = 1'b0, loopback_seen = 1'b0, settings_changed = 1'b0;
    always @(posedge clk) begin
        lpm_seen <= lpm;
        loopback_seen <= near_loopback;
        settings_changed <= lpm_seen != lpm || loopback_seen != near_loopback;
    end

    // ---- The transceivers and MMCMs (or their stand-in), seen through these wires -----------------------------------
    reg qpll_reset = 1'b1;
    reg gttxreset = 1'b1, txuserrdy = 1'b0, tx_mmcm_reset = 1'b1;
    reg [CHANNELS-1:0] gtrxreset = {CHANNELS{1'b1}}, rxuserrdy = {CHANNELS{1'b0}}, dfe_hold = {CHANNELS{1'b0}};
    reg [CHANNELS-1:0] rx_mmcm_reset = {CHANNELS{1'b1}};
    wire qpll_locked, tx_mmcm_locked;
    wire [CHANNELS-1:0] txresetdone, rxresetdone, rxprbserr, rx_mmcm_locked;

    // The 64B/66B external sequence counter: 0 ... 32, a block a cycle, no data at 32.
    reg [5:0] seq_count = 6'd0;
    always @(posedge tx_clk) seq_count <= seq_count == 6'd32 ? 6'd0 : seq_count + 6'd1;
    assign tx_sequence = seq_count;

    // PRBS on/off into the transmit clock.
    reg [1:0] prbs_tx = 2'b00;
    always @(posedge tx_clk) prbs_tx <= {prbs_tx[0], prbs};

    // ---- Millisecond tick: the requests, and a step for the monitors one clock after them ------------------------
    reg [$clog2(MS_CYCLES + 1)-1:0] ms_count = 0;
    reg ms_tick = 1'b0, ms_request = 1'b0, ms_step = 1'b0;
    always @(posedge clk) begin
        ms_tick <= ms_count == MS_CYCLES - 1;
        ms_count <= ms_count == MS_CYCLES - 1 ? 0 : ms_count + 1;
        ms_step <= ms_tick;
        if (ms_tick) ms_request <= !ms_request;
    end

    // ---- Reset sequence: QPLL, the transmit MMCM and TX (shared) --------------------------------------------------
    reg [1:0] qpll_sync = 2'b00, tx_done_sync = 2'b00, tx_mmcm_sync = 2'b00;
    always @(posedge clk) begin
        qpll_sync <= {qpll_sync[0], qpll_locked};
        tx_done_sync <= {tx_done_sync[0], &txresetdone};
        tx_mmcm_sync <= {tx_mmcm_sync[0], tx_mmcm_locked};
    end
    localparam C_INIT = 3'd0, C_QPLL_RESET = 3'd1, C_QPLL_WAIT = 3'd2, C_TX_RELEASE = 3'd3, C_MMCM_WAIT = 3'd4,
               C_TX_WAIT = 3'd5, C_RUN = 3'd6;
    reg [2:0] c_state = C_INIT;
    reg [31:0] c_count = 32'd0;
    always @(posedge clk) begin
        c_count <= c_count + 32'd1;
        case (c_state)
            C_INIT: if (c_count == MS_CYCLES) begin c_state <= C_QPLL_RESET; c_count <= 0; end
            C_QPLL_RESET: begin
                qpll_reset <= 1'b1; gttxreset <= 1'b1; txuserrdy <= 1'b0; tx_mmcm_reset <= 1'b1;
                if (c_count == US_CYCLES) begin c_state <= C_QPLL_WAIT; c_count <= 0; qpll_reset <= 1'b0; end
            end
            C_QPLL_WAIT: begin
                if (qpll_sync[1]) begin c_state <= C_TX_RELEASE; c_count <= 0; gttxreset <= 1'b0; end
                else if (c_count == 2 * MS_CYCLES) begin c_state <= C_QPLL_RESET; c_count <= 0; end
            end
            // TXOUTCLK runs once GTTXRESET is gone: then its MMCM may lock.
            C_TX_RELEASE: if (c_count == 10 * US_CYCLES) begin c_state <= C_MMCM_WAIT; c_count <= 0; tx_mmcm_reset <= 1'b0; end
            C_MMCM_WAIT: begin
                if (tx_mmcm_sync[1]) begin c_state <= C_TX_WAIT; c_count <= 0; txuserrdy <= 1'b1; end
                else if (c_count == 2 * MS_CYCLES) begin c_state <= C_QPLL_RESET; c_count <= 0; end
            end
            C_TX_WAIT: begin
                if (tx_done_sync[1]) c_state <= C_RUN;
                else if (c_count == 2 * MS_CYCLES) begin c_state <= C_QPLL_RESET; c_count <= 0; end
            end
            default: if (!qpll_sync[1] || !tx_mmcm_sync[1]) begin c_state <= C_QPLL_RESET; c_count <= 0; end
        endcase
        if (reset) begin c_state <= C_QPLL_RESET; c_count <= 0; end
    end
    assign qpll_lock = qpll_sync[1];
    assign tx_ready = c_state == C_RUN;

`ifdef SYNTHESIS
    wire refclk;
    IBUFDS_GTE2 u_refclk (.I(refclk_p), .IB(refclk_n), .CEB(1'b0), .O(refclk), .ODIV2());

    wire qpll_clk, qpll_refclk;
    GTXE2_COMMON #(
        .BIAS_CFG(64'h0000040000001000),
        .COMMON_CFG(32'h00000000),
        .QPLL_CFG(27'h0680181),
        .QPLL_CLKOUT_CFG(4'b0000),
        .QPLL_COARSE_FREQ_OVRD(6'b010000),
        .QPLL_COARSE_FREQ_OVRD_EN(1'b0),
        .QPLL_CP(10'b0000011111),
        .QPLL_CP_MONITOR_EN(1'b0),
        .QPLL_DMONITOR_SEL(1'b0),
        .QPLL_FBDIV(10'b0101000000),
        .QPLL_FBDIV_MONITOR_EN(1'b0),
        .QPLL_FBDIV_RATIO(1'b0),
        .QPLL_INIT_CFG(24'h000006),
        .QPLL_LOCK_CFG(16'h21E8),
        .QPLL_LPF(4'b1111),
        .QPLL_REFCLK_DIV(1),
        .SIM_QPLLREFCLK_SEL(3'b001),
        .SIM_RESET_SPEEDUP("TRUE"),
        .SIM_VERSION("4.0")
    ) u_common (
        // The unused reference-clock inputs stay unconnected: they are dedicated clock routes, a constant can't reach them.
        .GTREFCLK0(refclk), .QPLLREFCLKSEL(3'b001),
        .QPLLPD(1'b0), .QPLLRESET(qpll_reset), .QPLLLOCKEN(1'b1), .QPLLLOCKDETCLK(clk), .QPLLOUTRESET(1'b0),
        .QPLLOUTCLK(qpll_clk), .QPLLOUTREFCLK(qpll_refclk), .QPLLLOCK(qpll_locked), .QPLLFBCLKLOST(), .QPLLREFCLKLOST(),
        .QPLLDMONITOR(), .REFCLKOUTMONITOR(),
        .BGBYPASSB(1'b1), .BGMONITORENB(1'b1), .BGPDB(1'b1), .BGRCALOVRD(5'b11111), .RCALENB(1'b1),
        .PMARSVD(8'd0), .QPLLRSVD1(16'd0), .QPLLRSVD2(5'b11111),
        .DRPCLK(1'b0), .DRPEN(1'b0), .DRPWE(1'b0), .DRPADDR(8'd0), .DRPDI(16'd0), .DRPDO(), .DRPRDY());

    // Channel 0's TXOUTCLK (322.27 MHz) -> the transmit MMCM: 322.27 MHz for TXUSRCLK, 161.13 MHz for TXUSRCLK2 = tx_clk.
    wire [CHANNELS-1:0] txoutclk, rxoutclk;
    wire tx_usrclk;
    gtx_10g_clocks u_tx_clocks (.clk_in(txoutclk[0]), .reset(tx_mmcm_reset), .usrclk(tx_usrclk), .usrclk2(tx_clk),
                                .locked(tx_mmcm_locked));
`else
    // ---- Simulation stand-in: 161.13 MHz, a lock 3 us after QPLLRESET, MMCMs 1 us after their reset, resets done 2 us
    // after release ----------------------------------------------------------------------------------------------------
    reg sim_clk = 1'b0;
    always #3.103 sim_clk = ~sim_clk;
    assign tx_clk = sim_clk;
    reg sim_lock = 1'b0, sim_tx_mmcm = 1'b0;
    always @(qpll_reset) begin
        sim_lock = 1'b0;
        if (!qpll_reset) begin #3000; if (!qpll_reset) sim_lock = 1'b1; end
    end
    always @(tx_mmcm_reset) begin
        sim_tx_mmcm = 1'b0;
        if (!tx_mmcm_reset) begin #1000; if (!tx_mmcm_reset) sim_tx_mmcm = 1'b1; end
    end
    assign qpll_locked = sim_lock;
    assign tx_mmcm_locked = sim_tx_mmcm;
    // What each channel sent last, as its partner's receiver sees it.
    reg [63:0] sim_sent_data [0:CHANNELS-1];
    reg [1:0] sim_sent_header [0:CHANNELS-1];
    reg [5:0] sim_sent_sequence = 6'd0;
    always @(posedge tx_clk) sim_sent_sequence <= seq_count;
`endif

    genvar n;
    generate for (n = 0; n < CHANNELS; n = n + 1) begin : g_ch
        // Settings into this channel's receive clock.
        reg [1:0] prbs_rx = 2'b00, invert_rx = 2'b00;
        always @(posedge rx_clk[n]) begin
            prbs_rx <= {prbs_rx[0], prbs};
            invert_rx <= {invert_rx[0], rx_invert[n]};
        end
`ifdef SYNTHESIS
        wire [2:0] rx_header_wide;
        wire rx_usrclk;
        // This channel's recovered RXOUTCLK -> its MMCM: RXUSRCLK and RXUSRCLK2 = rx_clk[n].
        gtx_10g_clocks u_rx_clocks (.clk_in(rxoutclk[n]), .reset(rx_mmcm_reset[n]), .usrclk(rx_usrclk), .usrclk2(rx_clk[n]),
                                    .locked(rx_mmcm_locked[n]));
        GTXE2_CHANNEL #(
            .ALIGN_COMMA_DOUBLE("FALSE"),
            .ALIGN_COMMA_ENABLE(10'b1111111111),
            .ALIGN_COMMA_WORD(1),
            .ALIGN_MCOMMA_DET("FALSE"),
            .ALIGN_MCOMMA_VALUE(10'b1010000011),
            .ALIGN_PCOMMA_DET("FALSE"),
            .ALIGN_PCOMMA_VALUE(10'b0101111100),
            .CBCC_DATA_SOURCE_SEL("ENCODED"),
            .CHAN_BOND_KEEP_ALIGN("FALSE"),
            .CHAN_BOND_MAX_SKEW(1),
            .CHAN_BOND_SEQ_1_1(10'b0000000000),
            .CHAN_BOND_SEQ_1_2(10'b0000000000),
            .CHAN_BOND_SEQ_1_3(10'b0000000000),
            .CHAN_BOND_SEQ_1_4(10'b0000000000),
            .CHAN_BOND_SEQ_1_ENABLE(4'b1111),
            .CHAN_BOND_SEQ_2_1(10'b0000000000),
            .CHAN_BOND_SEQ_2_2(10'b0000000000),
            .CHAN_BOND_SEQ_2_3(10'b0000000000),
            .CHAN_BOND_SEQ_2_4(10'b0000000000),
            .CHAN_BOND_SEQ_2_ENABLE(4'b1111),
            .CHAN_BOND_SEQ_2_USE("FALSE"),
            .CHAN_BOND_SEQ_LEN(1),
            .CLK_CORRECT_USE("FALSE"),
            .CLK_COR_KEEP_IDLE("FALSE"),
            .CLK_COR_MAX_LAT(19),
            .CLK_COR_MIN_LAT(15),
            .CLK_COR_PRECEDENCE("TRUE"),
            .CLK_COR_REPEAT_WAIT(0),
            .CLK_COR_SEQ_1_1(10'b0100000000),
            .CLK_COR_SEQ_1_2(10'b0000000000),
            .CLK_COR_SEQ_1_3(10'b0000000000),
            .CLK_COR_SEQ_1_4(10'b0000000000),
            .CLK_COR_SEQ_1_ENABLE(4'b1111),
            .CLK_COR_SEQ_2_1(10'b0100000000),
            .CLK_COR_SEQ_2_2(10'b0000000000),
            .CLK_COR_SEQ_2_3(10'b0000000000),
            .CLK_COR_SEQ_2_4(10'b0000000000),
            .CLK_COR_SEQ_2_ENABLE(4'b1111),
            .CLK_COR_SEQ_2_USE("FALSE"),
            .CLK_COR_SEQ_LEN(1),
            .CPLL_CFG(24'hBC07DC),
            .CPLL_FBDIV(4),
            .CPLL_FBDIV_45(5),
            .CPLL_INIT_CFG(24'h00001E),
            .CPLL_LOCK_CFG(16'h01E8),
            .CPLL_REFCLK_DIV(1),
            .DEC_MCOMMA_DETECT("FALSE"),
            .DEC_PCOMMA_DETECT("FALSE"),
            .DEC_VALID_COMMA_ONLY("FALSE"),
            .DMONITOR_CFG(24'h000A00),
            .ES_CONTROL(6'b000000),
            .ES_ERRDET_EN("FALSE"),
            .ES_EYE_SCAN_EN("TRUE"),
            .ES_HORZ_OFFSET(12'h000),
            .ES_PMA_CFG(10'b0000000000),
            .ES_PRESCALE(5'b00000),
            .ES_QUALIFIER(80'h00000000000000000000),
            .ES_QUAL_MASK(80'h00000000000000000000),
            .ES_SDATA_MASK(80'h00000000000000000000),
            .ES_VERT_OFFSET(9'b000000000),
            .FTS_DESKEW_SEQ_ENABLE(4'b1111),
            .FTS_LANE_DESKEW_CFG(4'b1111),
            .FTS_LANE_DESKEW_EN("FALSE"),
            .GEARBOX_MODE(3'b001),
            .OUTREFCLK_SEL_INV(2'b11),
            .PCS_PCIE_EN("FALSE"),
            .PCS_RSVD_ATTR(48'h000000000000),
            .PD_TRANS_TIME_FROM_P2(12'h03c),
            .PD_TRANS_TIME_NONE_P2(8'h19),
            .PD_TRANS_TIME_TO_P2(8'h64),
            .PMA_RSV(32'h001E7080),
            .PMA_RSV2(16'h2050),
            .PMA_RSV3(2'b00),
            .PMA_RSV4(32'h00000000),
            .RXBUFRESET_TIME(5'b00001),
            .RXBUF_ADDR_MODE("FAST"),
            .RXBUF_EIDLE_HI_CNT(4'b1000),
            .RXBUF_EIDLE_LO_CNT(4'b0000),
            .RXBUF_EN("TRUE"),
            .RXBUF_RESET_ON_CB_CHANGE("TRUE"),
            .RXBUF_RESET_ON_COMMAALIGN("FALSE"),
            .RXBUF_RESET_ON_EIDLE("FALSE"),
            .RXBUF_RESET_ON_RATE_CHANGE("TRUE"),
            .RXBUF_THRESH_OVFLW(61),
            .RXBUF_THRESH_OVRD("FALSE"),
            .RXBUF_THRESH_UNDFLW(4),
            .RXCDRFREQRESET_TIME(5'b00001),
            .RXCDRPHRESET_TIME(5'b00001),
            .RXCDR_CFG(72'h0b000023ff10400020),
            .RXCDR_FR_RESET_ON_EIDLE(1'b0),
            .RXCDR_HOLD_DURING_EIDLE(1'b0),
            .RXCDR_LOCK_CFG(6'b010101),
            .RXCDR_PH_RESET_ON_EIDLE(1'b0),
            .RXDFELPMRESET_TIME(7'b0001111),
            .RXDLY_CFG(16'h001F),
            .RXDLY_LCFG(9'h030),
            .RXDLY_TAP_CFG(16'h0000),
            .RXGEARBOX_EN("TRUE"),
            .RXISCANRESET_TIME(5'b00001),
            .RXLPM_HF_CFG(14'b00000011110000),
            .RXLPM_LF_CFG(14'b00000011110000),
            .RXOOB_CFG(7'b0000110),
            .RXOUT_DIV(1),
            .RXPCSRESET_TIME(5'b00001),
            .RXPHDLY_CFG(24'h084020),
            .RXPH_CFG(24'h000000),
            .RXPH_MONITOR_SEL(5'b00000),
            .RXPMARESET_TIME(5'b00011),
            .RXPRBS_ERR_LOOPBACK(1'b0),
            .RXSLIDE_AUTO_WAIT(7),
            .RXSLIDE_MODE("OFF"),
            .RX_BIAS_CFG(12'b000000000100),
            .RX_BUFFER_CFG(6'b000000),
            .RX_CLK25_DIV(7),
            .RX_CLKMUX_PD(1'b1),
            .RX_CM_SEL(2'b11),
            .RX_CM_TRIM(3'b010),
            .RX_DATA_WIDTH(64),
            .RX_DDI_SEL(6'b000000),
            .RX_DEBUG_CFG(12'b000000000000),
            .RX_DEFER_RESET_BUF_EN("TRUE"),
            .RX_DFE_GAIN_CFG(23'h020FEA),
            .RX_DFE_H2_CFG(12'b000000000000),
            .RX_DFE_H3_CFG(12'b000001000000),
            .RX_DFE_H4_CFG(11'b00011110000),
            .RX_DFE_H5_CFG(11'b00011100000),
            .RX_DFE_KL_CFG(13'b0000011111110),
            .RX_DFE_KL_CFG2(32'h301148AC),
            .RX_DFE_LPM_CFG(16'h0954),
            .RX_DFE_LPM_HOLD_DURING_EIDLE(1'b0),
            .RX_DFE_UT_CFG(17'b10001111000000000),
            .RX_DFE_VP_CFG(17'b00011111100000011),
            .RX_DFE_XYD_CFG(13'b0000000000000),
            .RX_DISPERR_SEQ_MATCH("FALSE"),
            .RX_INT_DATAWIDTH(1),
            .RX_OS_CFG(13'b0000010000000),
            .RX_SIG_VALID_DLY(10),
            .RX_XCLK_SEL("RXREC"),
            .SAS_MAX_COM(64),
            .SAS_MIN_COM(36),
            .SATA_BURST_SEQ_LEN(4'b0101),
            .SATA_BURST_VAL(3'b100),
            .SATA_CPLL_CFG("VCO_3000MHZ"),
            .SATA_EIDLE_VAL(3'b100),
            .SATA_MAX_BURST(8),
            .SATA_MAX_INIT(21),
            .SATA_MAX_WAKE(7),
            .SATA_MIN_BURST(4),
            .SATA_MIN_INIT(12),
            .SATA_MIN_WAKE(4),
            .SHOW_REALIGN_COMMA("FALSE"),
            .SIM_CPLLREFCLK_SEL(3'b001),
            .SIM_RECEIVER_DETECT_PASS("TRUE"),
            .SIM_RESET_SPEEDUP("FALSE"),
            .SIM_TX_EIDLE_DRIVE_LEVEL("X"),
            .SIM_VERSION("4.0"),
            .TERM_RCAL_CFG(5'b10000),
            .TERM_RCAL_OVRD(1'b0),
            .TRANS_TIME_RATE(8'h0E),
            .TST_RSV(32'h00000000),
            .TXBUF_EN("TRUE"),
            .TXBUF_RESET_ON_RATE_CHANGE("TRUE"),
            .TXDLY_CFG(16'h001F),
            .TXDLY_LCFG(9'h030),
            .TXDLY_TAP_CFG(16'h0000),
            .TXGEARBOX_EN("TRUE"),
            .TXOUT_DIV(1),
            .TXPCSRESET_TIME(5'b00001),
            .TXPHDLY_CFG(24'h084020),
            .TXPH_CFG(16'h0780),
            .TXPH_MONITOR_SEL(5'b00000),
            .TXPMARESET_TIME(5'b00001),
            .TX_CLK25_DIV(7),
            .TX_CLKMUX_PD(1'b1),
            .TX_DATA_WIDTH(64),
            .TX_DEEMPH0(5'b00000),
            .TX_DEEMPH1(5'b00000),
            .TX_DRIVE_MODE("DIRECT"),
            .TX_EIDLE_ASSERT_DELAY(3'b110),
            .TX_EIDLE_DEASSERT_DELAY(3'b100),
            .TX_INT_DATAWIDTH(1),
            .TX_LOOPBACK_DRIVE_HIZ("FALSE"),
            .TX_MAINCURSOR_SEL(1'b0),
            .TX_MARGIN_FULL_0(7'b1001110),
            .TX_MARGIN_FULL_1(7'b1001001),
            .TX_MARGIN_FULL_2(7'b1000101),
            .TX_MARGIN_FULL_3(7'b1000010),
            .TX_MARGIN_FULL_4(7'b1000000),
            .TX_MARGIN_LOW_0(7'b1000110),
            .TX_MARGIN_LOW_1(7'b1000100),
            .TX_MARGIN_LOW_2(7'b1000010),
            .TX_MARGIN_LOW_3(7'b1000000),
            .TX_MARGIN_LOW_4(7'b1000000),
            .TX_PREDRIVER_MODE(1'b0),
            .TX_QPI_STATUS_EN(1'b0),
            .TX_RXDETECT_CFG(14'h1832),
            .TX_RXDETECT_REF(3'b100),
            .TX_XCLK_SEL("TXOUT"),
            .UCODEER_CLR(1'b0)
        ) u_channel (
            .QPLLCLK(qpll_clk), .QPLLREFCLK(qpll_refclk),
            .CPLLPD(1'b1), .CPLLRESET(1'b0), .CPLLLOCKEN(1'b0), .CPLLREFCLKSEL(3'b001),
            .TXSYSCLKSEL(2'b11), .RXSYSCLKSEL(2'b11),
            .GTTXRESET(gttxreset), .GTRXRESET(gtrxreset[n]), .TXUSERRDY(txuserrdy), .RXUSERRDY(rxuserrdy[n]),
            .TXRESETDONE(txresetdone[n]), .RXRESETDONE(rxresetdone[n]),
            .TXUSRCLK(tx_usrclk), .TXUSRCLK2(tx_clk), .RXUSRCLK(rx_usrclk), .RXUSRCLK2(rx_clk[n]),
            .TXOUTCLK(txoutclk[n]), .RXOUTCLK(rxoutclk[n]), .TXOUTCLKSEL(3'b010), .RXOUTCLKSEL(3'b010),
            .TXOUTCLKFABRIC(), .TXOUTCLKPCS(), .RXOUTCLKFABRIC(),
            .LOOPBACK(near_loopback ? 3'b010 : 3'b000),
            .TXPRBSSEL(prbs_tx[1] ? 3'b100 : 3'b000), .RXPRBSSEL(prbs_rx[1] ? 3'b100 : 3'b000),
            .RXPRBSERR(rxprbserr[n]), .RXPRBSCNTRESET(1'b0), .TXPRBSFORCEERR(1'b0),
            .TXDATA(tx_data[64 * n +: 64]), .TXHEADER({1'b0, tx_header[2 * n +: 2]}),
            .TXSEQUENCE({1'b0, seq_count}), .TXCHARISK(8'd0), .TXCHARDISPMODE(8'd0), .TXCHARDISPVAL(8'd0),
            .RXDATA(rx_data[64 * n +: 64]), .RXHEADER(rx_header_wide), .RXHEADERVALID(rx_header_valid[n]),
            .RXDATAVALID(rx_data_valid[n]), .RXSTARTOFSEQ(), .RXGEARBOXSLIP(rx_slip[n]),
            .RXPOLARITY(invert_rx[1]), .TXPOLARITY(1'b0), .TXINHIBIT(1'b0),
            .RXLPMEN(lpm), .RXDFEAGCHOLD(dfe_hold[n]), .RXDFELFHOLD(dfe_hold[n]), .RXLPMHFHOLD(1'b0), .RXLPMLFHOLD(1'b0),
            .RXCDRHOLD(1'b0), .RXDFELPMRESET(1'b0),
            .GTXTXP(txp[n]), .GTXTXN(txn[n]), .GTXRXP(rxp[n]), .GTXRXN(rxn[n]),
            // Every input the GT wizard ties, tied the same (step 2's hardware run: open inputs aren't defaults).
            .CFGRESET(1'b0), .EYESCANMODE(1'b0), .EYESCANRESET(1'b0), .EYESCANTRIGGER(1'b0), .GTRESETSEL(1'b0),
            .GTRSVD(16'b0000000000000000), .PCSRSVDIN(16'b0000000000000000), .PCSRSVDIN2(5'b00000),
            .PMARSVDIN(5'b00000), .PMARSVDIN2(5'b00000), .RESETOVRD(1'b0), .RX8B10BEN(1'b0), .RXBUFRESET(1'b0),
            .RXCDRFREQRESET(1'b0), .RXCDROVRDEN(1'b0), .RXCDRRESET(1'b0), .RXCDRRESETRSV(1'b0), .RXCHBONDEN(1'b0),
            .RXCHBONDI(5'b00000), .RXCHBONDLEVEL(3'd0), .RXCHBONDMASTER(1'b0), .RXCHBONDSLAVE(1'b0),
            .RXCOMMADETEN(1'b0), .RXDDIEN(1'b0), .RXDFEAGCOVRDEN(1'b0), .RXDFECM1EN(1'b0), .RXDFELFOVRDEN(1'b1),
            .RXDFETAP2HOLD(1'b0), .RXDFETAP2OVRDEN(1'b0), .RXDFETAP3HOLD(1'b0), .RXDFETAP3OVRDEN(1'b0),
            .RXDFETAP4HOLD(1'b0), .RXDFETAP4OVRDEN(1'b0), .RXDFETAP5HOLD(1'b0), .RXDFETAP5OVRDEN(1'b0),
            .RXDFEUTHOLD(1'b0), .RXDFEUTOVRDEN(1'b0), .RXDFEVPHOLD(1'b0), .RXDFEVPOVRDEN(1'b0), .RXDFEVSEN(1'b0),
            .RXDFEXYDEN(1'b1), .RXDFEXYDHOLD(1'b0), .RXDFEXYDOVRDEN(1'b0), .RXDLYBYPASS(1'b1), .RXDLYEN(1'b0),
            .RXDLYOVRDEN(1'b0), .RXDLYSRESET(1'b0), .RXELECIDLEMODE(2'b11), .RXLPMHFOVRDEN(1'b0),
            .RXLPMLFKLOVRDEN(1'b0), .RXMCOMMAALIGNEN(1'b0), .RXMONITORSEL(2'b00), .RXOOBRESET(1'b0), .RXOSHOLD(1'b0),
            .RXOSOVRDEN(1'b0), .RXPCOMMAALIGNEN(1'b0), .RXPCSRESET(1'b0), .RXPD(2'b00), .RXPHALIGN(1'b0),
            .RXPHALIGNEN(1'b0), .RXPHDLYPD(1'b0), .RXPHDLYRESET(1'b0), .RXPHOVRDEN(1'b0), .RXPMARESET(1'b0),
            .RXQPIEN(1'b0), .RXRATE(3'd0), .RXSLIDE(1'b0), .SETERRSTATUS(1'b0), .TSTIN(20'b11111111111111111111),
            .TX8B10BBYPASS(8'd0), .TX8B10BEN(1'b0), .TXBUFDIFFCTRL(3'b100), .TXCOMINIT(1'b0), .TXCOMSAS(1'b0),
            .TXCOMWAKE(1'b0), .TXDEEMPH(1'b0), .TXDETECTRX(1'b0), .TXDIFFCTRL(TX_DIFF_CTRL), .TXDIFFPD(1'b0),
            .TXDLYBYPASS(1'b1), .TXDLYEN(1'b0), .TXDLYHOLD(1'b0), .TXDLYOVRDEN(1'b0), .TXDLYSRESET(1'b0),
            .TXDLYUPDOWN(1'b0), .TXELECIDLE(1'b0), .TXMAINCURSOR(7'd0), .TXMARGIN(3'd0), .TXPCSRESET(1'b0),
            .TXPD(2'b00), .TXPDELECIDLEMODE(1'b0), .TXPHALIGN(1'b0), .TXPHALIGNEN(1'b0), .TXPHDLYPD(1'b0),
            .TXPHDLYRESET(1'b0), .TXPHINIT(1'b0), .TXPHOVRDEN(1'b0), .TXPISOPD(1'b0), .TXPMARESET(1'b0),
            .TXPOSTCURSOR(5'd0), .TXPOSTCURSORINV(1'b0), .TXPRECURSOR(5'd0), .TXPRECURSORINV(1'b0), .TXQPIBIASEN(1'b0),
            .TXQPISTRONGPDOWN(1'b0), .TXQPIWEAKPUP(1'b0), .TXRATE(3'd0), .TXSTARTSEQ(1'b0), .TXSWING(1'b0),
            .DRPCLK(1'b0), .DRPEN(1'b0), .DRPWE(1'b0), .DRPADDR(9'd0), .DRPDI(16'd0), .DRPDO(), .DRPRDY());
        assign rx_header[2 * n +: 2] = rx_header_wide[1:0];
`else
        // Stand-in: error words to report and a lost link, set by a testbench.
        integer sim_errors = 0;
        reg sim_no_link = 1'b0;
        reg tx_done_r = 1'b0, rx_done_r = 1'b0, rx_mmcm_r = 1'b0;
        // The receive clock stops while its MMCM is in reset, as the MMCM's outputs do.
        assign rx_clk[n] = sim_clk && rx_mmcm_r;
        // As the transceiver: USERRDY says the user clocks are stable — raised before the MMCM locked, the reset never
        // completes.
        always @(gttxreset or txuserrdy) begin
            tx_done_r = 1'b0;
            if (!gttxreset && txuserrdy && tx_mmcm_locked) begin #2000; if (!gttxreset) tx_done_r = 1'b1; end
        end
        always @(gtrxreset[n] or rxuserrdy[n]) begin
            rx_done_r = 1'b0;
            if (!gtrxreset[n] && rxuserrdy[n] && rx_mmcm_r) begin #2000; if (!gtrxreset[n]) rx_done_r = 1'b1; end
        end
        always @(rx_mmcm_reset[n]) begin
            rx_mmcm_r = 1'b0;
            if (!rx_mmcm_reset[n]) begin #1000; if (!rx_mmcm_reset[n]) rx_mmcm_r = 1'b1; end
        end
        assign txresetdone[n] = tx_done_r;
        assign rxresetdone[n] = rx_done_r;
        assign rx_mmcm_locked[n] = rx_mmcm_r;
        always @(posedge tx_clk) begin
            sim_sent_data[n] <= tx_data[64 * n +: 64];
            sim_sent_header[n] <= tx_header[2 * n +: 2];
        end
        localparam PARTNER = SIM_CROSS && CHANNELS > 1 ? n ^ 1 : n;
        reg [63:0] data_r = 64'd0;
        reg [1:0] header_r = 2'b00;
        reg data_valid_r = 1'b0, error_r = 1'b0;
        always @(posedge rx_clk[n]) begin
            data_valid_r <= sim_sent_sequence != 6'd32;
            data_r <= sim_no_link || !rx_done_r ? {$random, $random} : sim_sent_data[near_loopback ? n : PARTNER];
            header_r <= sim_no_link || !rx_done_r ? $random : sim_sent_header[near_loopback ? n : PARTNER];
            error_r <= rx_done_r && prbs_rx[1] && (sim_no_link || sim_errors > 0);
            if (sim_errors > 0) sim_errors = sim_errors - 1;
        end
        assign rx_data[64 * n +: 64] = data_r;
        assign rx_header[2 * n +: 2] = header_r;
        assign rx_data_valid[n] = data_valid_r;
        assign rx_header_valid[n] = data_valid_r;
        assign rxprbserr[n] = error_r;
        assign txp[n] = 1'b0;
        assign txn[n] = 1'b1;
`endif

        // ---- PRBS error words: counted on rx_clk[n], copied to clk on request (a toggle each millisecond) ----------
        reg [31:0] errors = 32'd0, copy = 32'd0;
        reg [2:0] req_sync = 3'b000;
        reg ack = 1'b0;
        always @(posedge rx_clk[n]) begin
            if (rxprbserr[n]) errors <= errors + 32'd1;
            req_sync <= {req_sync[1:0], ms_request};
            if (req_sync[2] != req_sync[1]) begin copy <= errors; ack <= !ack; end
        end
        reg [2:0] ack_sync = 3'b000;
        reg [31:0] now = 32'd0, base = 32'd0;
        reg answered = 1'b0, bad_ms = 1'b0;
        reg [1:0] done_sync = 2'b00, mmcm_sync = 2'b00;
        always @(posedge clk) begin
            ack_sync <= {ack_sync[1:0], ack};
            done_sync <= {done_sync[0], rxresetdone[n]};
            mmcm_sync <= {mmcm_sync[0], rx_mmcm_locked[n]};
            if (ack_sync[2] != ack_sync[1]) begin
                // A millisecond is bad when errors came (with prbs on) …
                bad_ms <= prbs && copy != now;
                now <= copy;
                answered <= 1'b1;
            end
            // … or when the receive clock didn't answer the request.
            if (ms_tick) begin
                if (!answered) bad_ms <= 1'b1;
                answered <= 1'b0;
            end
            if (prbs_clear) base <= now;
        end
        assign prbs_errors[32 * n +: 32] = now - base;

        // ---- Reset sequence: each receiver and its MMCM ---------------------------------------------------------------
        localparam R_IDLE = 3'd0, R_RESET = 3'd1, R_RELEASE = 3'd2, R_MMCM = 3'd3, R_WAIT = 3'd4, R_MONITOR = 3'd5;
        reg [2:0] state = R_IDLE;
        reg [31:0] count = 32'd0;
        reg [15:0] bad = 16'd0;
        reg [2:0] good = 3'd0;
        reg [15:0] retries = 16'd0;
        // rx_restart comes from the receive clock (a PCS), which stops while the receiver restarts: a request may stay
        // high then. Synchronised, and only its rising edge counts.
        reg [2:0] restart_sync = 3'b000;
        always @(posedge clk) begin
            restart_sync <= {restart_sync[1:0], rx_restart[n]};
            count <= count + 32'd1;
            case (state)
                R_IDLE: begin
                    gtrxreset[n] <= 1'b1; rx_mmcm_reset[n] <= 1'b1; rxuserrdy[n] <= 1'b0; dfe_hold[n] <= 1'b0;
                    if (tx_ready) begin state <= R_RESET; count <= 32'd0; end
                end
                R_RESET: begin
                    gtrxreset[n] <= 1'b1; rx_mmcm_reset[n] <= 1'b1; rxuserrdy[n] <= 1'b0; dfe_hold[n] <= 1'b0;
                    bad <= 16'd0; good <= 3'd0;
                    if (count == US_CYCLES) begin state <= R_RELEASE; count <= 32'd0; gtrxreset[n] <= 1'b0; end
                end
                // RXOUTCLK runs once GTRXRESET is gone: then its MMCM may lock.
                R_RELEASE: if (count == 10 * US_CYCLES) begin state <= R_MMCM; count <= 32'd0; rx_mmcm_reset[n] <= 1'b0; end
                R_MMCM: begin
                    if (mmcm_sync[1]) begin state <= R_WAIT; count <= 32'd0; rxuserrdy[n] <= 1'b1; end
                    else if (count == 2 * MS_CYCLES) begin state <= R_RESET; count <= 32'd0; retries <= retries + 16'd1; end
                end
                R_WAIT: begin
                    if (done_sync[1]) state <= R_MONITOR;
                    else if (count == 2 * MS_CYCLES) begin state <= R_RESET; count <= 32'd0; retries <= retries + 16'd1; end
                end
                default: begin                         // R_MONITOR
                    // The recovered clock went (the fibre was pulled): its MMCM lost lock, so start the receiver again.
                    if (!mmcm_sync[1]) begin state <= R_RESET; count <= 32'd0; retries <= retries + 16'd1; end
                    else if (ms_step) begin
                        if (bad_ms || !done_sync[1]) begin
                            good <= 3'd0;
                            dfe_hold[n] <= 1'b0;
                            bad <= bad + 16'd1;
                            if (bad == RETRY_MS - 1) begin state <= R_RESET; count <= 32'd0; retries <= retries + 16'd1; end
                        end else begin
                            bad <= 16'd0;
                            if (good != 3'd7) good <= good + 3'd1;
                            if (good >= 3'd3 && !lpm) dfe_hold[n] <= 1'b1;
                        end
                    end
                end
            endcase
            if (!tx_ready) state <= R_IDLE;
            else if ((restart_sync[1] && !restart_sync[2]) || settings_changed) begin state <= R_RESET; count <= 32'd0; end
        end
        assign rx_ready[n] = state == R_MONITOR && done_sync[1] && mmcm_sync[1];
        assign rx_retries[16 * n +: 16] = retries;
    end endgenerate

endmodule

// One direction's user clocks, as in the GT wizard's example: the transceiver's 322.27 MHz output on a BUFG into an
// MMCM (VCO 644.5 MHz), 322.27 MHz for USRCLK and 161.13 MHz for USRCLK2, each on a BUFG, phase-aligned.
module gtx_10g_clocks (
    input  wire clk_in,
    input  wire reset,
    output wire usrclk,
    output wire usrclk2,
    output wire locked
);
`ifdef SYNTHESIS
    wire clk_in_buffered, feedback, usrclk_unbuffered, usrclk2_unbuffered;
    BUFG u_in (.I(clk_in), .O(clk_in_buffered));
    MMCME2_BASE #(
        .CLKIN1_PERIOD(3.103),
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(2.000),
        .CLKOUT0_DIVIDE_F(4.000),
        .CLKOUT1_DIVIDE(2)
    ) u_mmcm (
        .CLKIN1(clk_in_buffered), .CLKFBOUT(feedback), .CLKFBIN(feedback),
        .CLKOUT0(usrclk2_unbuffered), .CLKOUT0B(), .CLKOUT1(usrclk_unbuffered), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB(),
        .LOCKED(locked), .RST(reset), .PWRDWN(1'b0)
    );
    BUFG u_usrclk (.I(usrclk_unbuffered), .O(usrclk));
    BUFG u_usrclk2 (.I(usrclk2_unbuffered), .O(usrclk2));
`else
    // Not used in simulation: the stand-in above makes its own clocks.
    assign usrclk = clk_in;
    assign usrclk2 = clk_in;
    assign locked = !reset;
`endif
endmodule
