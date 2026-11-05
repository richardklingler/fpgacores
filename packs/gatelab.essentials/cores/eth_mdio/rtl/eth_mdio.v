// MDIO master for an Ethernet PHY (IEEE 802.3 clause 22), with the PHY's setup and a link watch built in.
//
// After SETTLE_MS (the PHY needs about 150 ms after its reset before it answers), the core writes ADVERTISE into
// register 4 and restarts auto-negotiation (register 0 = 1200) — unless ADVERTISE is 0 — and from then on reads
// register 1 (BMSR) POLL_HZ times a second: `link_up` is its bit 2. `setup_done` goes high after the first read.
// Between polls it runs the design's own transactions (a poll that's due goes first, so they can't starve it): with `ready` high, `go` starts one — `write` with `wdata`, or
// a read into `rdata` — on register `reg_addr` of PHY_ADDR; `done` pulses when it's over.
//
// A frame is 32 ones, 01, the operation (10 read, 01 write), the PHY's address, the register, the turnaround and 16
// data bits, MSB first. MDC runs at no more than MDC_HZ; MDIO changes while MDC is low, the PHY samples on its rising
// edge. In a read the core lets go of MDIO at the turnaround's first bit and takes each data bit just before MDC
// rises (the PHY changes it up to 300 ns after the previous rising edge). MDIO is push-pull: at the top
// `assign mdio = mdio_oe ? mdio_out : 1'bz; assign mdio_in = mdio;` — with a pull-up on the pin (many boards have
// none: ask for the FPGA's).

module eth_mdio #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer MDC_HZ = 2_000_000,
    parameter [4:0]   PHY_ADDR = 5'd1,
    parameter [15:0]  ADVERTISE = 16'h0101,   // register 4: 100BASE-TX full duplex only (0: leave the PHY's own)
    parameter integer SETTLE_MS = 200,
    parameter integer POLL_HZ = 10
) (
    input  wire        clk,
    output reg         mdc = 1'b0,
    output reg         mdio_out = 1'b1,
    output reg         mdio_oe = 1'b0,
    input  wire        mdio_in,
    output reg         link_up = 1'b0,
    output reg         setup_done = 1'b0,
    input  wire        go,
    input  wire        write,
    input  wire [4:0]  reg_addr,
    input  wire [15:0] wdata,
    output wire        ready,
    output reg         done = 1'b0,
    output reg  [15:0] rdata = 16'd0
);
    localparam integer HALF = (CLK_HZ + 2 * MDC_HZ - 1) / (2 * MDC_HZ);   // clocks per MDC half period, rounded up
    localparam integer SETTLE = CLK_HZ / 1000 * SETTLE_MS;
    localparam integer POLL = CLK_HZ / POLL_HZ;

    // ---- One frame ----------------------------------------------------------------------------------------------
    reg        busy = 1'b0;
    reg        frame_done = 1'b0;
    reg        reading = 1'b0;
    reg [63:0] frame = 64'd0;
    reg [5:0]  bit_n = 6'd0;
    reg [15:0] phase = 16'd0;   // 0 … 2 HALF − 1 within a bit
    reg [1:0]  in_sync = 2'b11;
    reg [15:0] shift_in = 16'd0;
    reg        start = 1'b0;
    reg        start_write = 1'b0;
    reg [4:0]  start_reg = 5'd0;
    reg [15:0] start_data = 16'd0;

    always @(posedge clk) begin
        in_sync <= {in_sync[0], mdio_in};
        frame_done <= 1'b0;
        if (!busy) begin
            mdc <= 1'b0;
            mdio_oe <= 1'b0;
            if (start) begin
                busy <= 1'b1;
                bit_n <= 6'd0;
                phase <= 16'd0;
                reading <= !start_write;
                frame <= {32'hFFFF_FFFF, 2'b01, start_write ? 2'b01 : 2'b10, PHY_ADDR, start_reg, 2'b10, start_data};
            end
        end else begin
            phase <= phase + 16'd1;
            if (phase == 16'd0) begin
                mdc <= 1'b0;
                mdio_out <= frame[63];
                frame <= {frame[62:0], 1'b0};
                mdio_oe <= !(reading && bit_n >= 6'd46);
            end
            if (phase == HALF - 1 && reading && bit_n >= 6'd48) shift_in <= {shift_in[14:0], in_sync[1]};
            if (phase == HALF) mdc <= 1'b1;
            if (phase == 2 * HALF - 1) begin
                phase <= 16'd0;
                bit_n <= bit_n + 6'd1;
                if (bit_n == 6'd63) begin
                    busy <= 1'b0;
                    frame_done <= 1'b1;
                end
            end
        end
    end

    // ---- Setup, polls and the design's transactions ------------------------------------------------------------
    localparam S_SETTLE = 3'd0, S_ADVERTISE = 3'd1, S_RESTART = 3'd2, S_POLL = 3'd3, S_IDLE = 3'd4, S_USER = 3'd5;
    reg [2:0]  step = S_SETTLE;
    reg        waiting = 1'b0;   // a frame of ours is under way
    reg [31:0] timer = 32'd0;

    assign ready = step == S_IDLE && !waiting && timer < POLL;

    always @(posedge clk) begin
        start <= 1'b0;
        done <= 1'b0;
        // The timer runs from the start — through transactions too, so polls come due however busy the design keeps
        // the core; whoever uses it clears it.
        if (timer != 32'hFFFF_FFFF) timer <= timer + 32'd1;
        if (waiting) begin
            if (frame_done) begin
                waiting <= 1'b0;
                case (step)
                    S_ADVERTISE: step <= S_RESTART;
                    S_RESTART:   step <= S_POLL;
                    S_POLL: begin
                        link_up <= shift_in[2];
                        setup_done <= 1'b1;
                        step <= S_IDLE;
                    end
                    default: begin   // S_USER
                        if (reading) rdata <= shift_in;
                        done <= 1'b1;
                        step <= S_IDLE;
                    end
                endcase
            end
        end else begin
            case (step)
                S_SETTLE:
                    if (timer >= SETTLE) begin
                        timer <= 32'd0;
                        step <= ADVERTISE != 16'd0 ? S_ADVERTISE : S_POLL;
                    end
                S_ADVERTISE: begin
                    start <= 1'b1; start_write <= 1'b1; start_reg <= 5'd4; start_data <= ADVERTISE; waiting <= 1'b1;
                end
                S_RESTART: begin
                    start <= 1'b1; start_write <= 1'b1; start_reg <= 5'd0; start_data <= 16'h1200; waiting <= 1'b1;
                end
                S_POLL: begin
                    start <= 1'b1; start_write <= 1'b0; start_reg <= 5'd1; start_data <= 16'd0; waiting <= 1'b1;
                end
                S_IDLE:
                    // The link poll first when it's due: a design that asks for transactions back to back must not
                    // starve it (link_up would keep the first poll's answer, read while auto-negotiation restarted).
                    if (timer >= POLL) begin
                        timer <= 32'd0;
                        step <= S_POLL;
                    end else if (go) begin
                        start <= 1'b1; start_write <= write; start_reg <= reg_addr; start_data <= wdata;
                        waiting <= 1'b1;
                        step <= S_USER;
                    end
                default: ;
            endcase
        end
    end
endmodule
