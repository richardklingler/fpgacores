// I2C master, byte level. One command per `go` (while `ready`):
//   cmd 0 START  — a start, or a repeated start after a byte
//   cmd 1 WRITE  — send `tx_data`; `ack` says whether the device acknowledged
//   cmd 2 READ   — receive a byte into `rx_data`; answer ACK if `ack_read` (more bytes to come),
//                  NACK for the last byte
//   cmd 3 STOP
// `done` pulses when the command has finished. A transaction is START, WRITE (address << 1 |
// read bit), WRITE or READ bytes, STOP.
//
// The bus is open drain: `scl_oe` / `sda_oe` high means "pull the line low", low means "let go"
// (the pull-up makes it high). `scl_in` / `sda_in` are the lines as they are; they are
// synchronised here. A device may stretch the clock by holding SCL low: the master waits.
// At the top: `assign sda = sda_oe ? 1'b0 : 1'bz; assign sda_in = sda;` (the same for SCL).

module i2c_master #(
    parameter CLK_HZ = 12000000,
    parameter I2C_HZ = 100000
) (
    input  wire       clk,
    input  wire [1:0] cmd,
    input  wire [7:0] tx_data,
    input  wire       ack_read,
    input  wire       go,
    output wire       ready,
    output reg        done = 1'b0,
    output reg  [7:0] rx_data = 8'd0,
    output reg        ack = 1'b0,
    output reg        scl_oe = 1'b0,
    input  wire       scl_in,
    output reg        sda_oe = 1'b0,
    input  wire       sda_in
);
    localparam START = 2'd0, WRITE = 2'd1, READ = 2'd2, STOP = 2'd3;
    // Each bit is four quarter periods: SCL low (set SDA), release SCL, SCL high (sample), SCL low.
    localparam QUARTER = CLK_HZ / (4 * I2C_HZ) > 0 ? CLK_HZ / (4 * I2C_HZ) : 1;
    localparam COUNTER_BITS = QUARTER > 1 ? $clog2(QUARTER) : 1;

    reg [1:0] scl_s = 2'b11, sda_s = 2'b11;
    always @(posedge clk) begin
        scl_s <= {scl_s[0], scl_in};
        sda_s <= {sda_s[0], sda_in};
    end
    wire scl_high = scl_s[1];
    wire sda_high = sda_s[1];

    reg       busy = 1'b0;
    reg [1:0] op = START;
    reg [1:0] phase = 2'd0;
    reg [3:0] bit_index = 4'd0;           // 0 … 7 data bits, 8 the acknowledge bit
    reg [7:0] tx_shift = 8'd0;
    reg [7:0] rx_shift = 8'd0;
    reg       answer_ack = 1'b0;
    reg [COUNTER_BITS-1:0] clocks = 0;

    assign ready = !busy;

    always @(posedge clk) begin
        done <= 1'b0;
        if (!busy) begin
            if (go) begin
                busy <= 1'b1;
                op <= cmd;
                phase <= 2'd0;
                bit_index <= 4'd0;
                clocks <= 0;
                tx_shift <= tx_data;
                answer_ack <= ack_read;
                // Phase 0 of the command; SCL is low here except before a first START.
                case (cmd)
                    START: sda_oe <= 1'b0;
                    WRITE: begin scl_oe <= 1'b1; sda_oe <= !tx_data[7]; end
                    READ:  begin scl_oe <= 1'b1; sda_oe <= 1'b0; end
                    STOP:  begin scl_oe <= 1'b1; sda_oe <= 1'b1; end
                endcase
            end
        end else if (phase == 2'd1 && !scl_high) begin
            // SCL released but still low: a device stretches the clock. Wait.
            clocks <= 0;
        end else if (clocks != QUARTER - 1) begin
            clocks <= clocks + 1'b1;
        end else begin
            clocks <= 0;
            case (phase)
                2'd0: begin
                    phase <= 2'd1;
                    scl_oe <= 1'b0;
                end
                2'd1: begin
                    // SCL has been high for a quarter period.
                    phase <= 2'd2;
                    case (op)
                        START: sda_oe <= 1'b1;                   // SDA falls while SCL is high
                        STOP:  sda_oe <= 1'b0;                   // SDA rises while SCL is high
                        WRITE: if (bit_index == 4'd8) ack <= !sda_high;
                        READ:  if (bit_index != 4'd8) rx_shift <= {rx_shift[6:0], sda_high};
                    endcase
                end
                2'd2: begin
                    if (op == STOP) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        phase <= 2'd3;
                        scl_oe <= 1'b1;
                    end
                end
                2'd3: begin
                    if (op == START || bit_index == 4'd8) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        if (op == READ) rx_data <= rx_shift;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                        phase <= 2'd0;
                        // Phase 0 of the next bit.
                        if (op == WRITE) begin
                            tx_shift <= {tx_shift[6:0], 1'b0};
                            sda_oe <= (bit_index == 4'd7) ? 1'b0 : !tx_shift[6];
                        end else begin
                            sda_oe <= (bit_index == 4'd7) ? answer_ack : 1'b0;
                        end
                    end
                end
            endcase
        end
    end
endmodule
