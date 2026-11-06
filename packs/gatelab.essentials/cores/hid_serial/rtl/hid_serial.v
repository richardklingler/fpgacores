// Keyboard and mouse from GateLab over a serial line: the packets GateLab's HDMI Input panel and Claude's hid_input
// send to a board's UART (8N1), decoded into events. A command byte has bit 7 set, data bytes have it clear:
//
//   key             0x80 | up << 1 | usage[7], usage[6:0]       USB HID usage (page 7; E0-E7 are the modifiers)
//   mouse move      0x90 | buttons, dx, dy                      7-bit two's complement, right/down positive
//   mouse position  0xA0 | buttons, x[13:7], x[6:0], y[13:7], y[6:0]   absolute, in the picture's pixels
//   wheel           0xB0, dz                                    7-bit two's complement
//   all up          0xBF                                        every key and button released
//
// buttons: bit 0 left, bit 1 right, bit 2 middle. Each event is a one-clock pulse with its values held until the
// next one of its kind; `buttons` is a level (the last move or position packet's, cleared by all up). A packet cut
// short by the next command byte is dropped, so a lost byte costs one packet, never the stream.

module hid_serial #(
    parameter CLK_HZ = 12000000,
    parameter BAUD   = 115200
) (
    input  wire              clk,
    input  wire              rx,

    output reg               key_valid = 1'b0,
    output reg        [7:0]  key_usage = 8'd0,
    output reg               key_up = 1'b0,

    output reg               move_valid = 1'b0,
    output reg  signed [7:0] move_dx = 8'sd0,
    output reg  signed [7:0] move_dy = 8'sd0,

    output reg               position_valid = 1'b0,
    output reg        [13:0] position_x = 14'd0,
    output reg        [13:0] position_y = 14'd0,

    output reg               wheel_valid = 1'b0,
    output reg  signed [7:0] wheel_dz = 8'sd0,

    output reg        [2:0]  buttons = 3'd0,
    output reg               all_up = 1'b0
);
    wire [7:0] data;
    wire       valid;
    uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (.clk(clk), .rx(rx), .data(data), .valid(valid), .frame_error());

    reg [7:0] command = 8'd0;       // 0: no packet open
    reg [2:0] count = 3'd0;         // data bytes taken
    reg [6:0] b0 = 7'd0, b1 = 7'd0, b2 = 7'd0;

    // A 7-bit two's complement step as 8 bits.
    function signed [7:0] step(input [6:0] v);
        step = {v[6], v};
    endfunction

    always @(posedge clk) begin
        key_valid <= 1'b0;
        move_valid <= 1'b0;
        position_valid <= 1'b0;
        wheel_valid <= 1'b0;
        all_up <= 1'b0;
        if (valid) begin
            if (data[7]) begin
                count <= 3'd0;
                if (data == 8'hBF) begin
                    all_up <= 1'b1;
                    buttons <= 3'd0;
                    command <= 8'd0;
                end else begin
                    command <= data;
                end
            end else if (command != 8'd0) begin
                count <= count + 3'd1;
                case (count)
                    3'd0: b0 <= data[6:0];
                    3'd1: b1 <= data[6:0];
                    3'd2: b2 <= data[6:0];
                    default: ;
                endcase
                case (command[7:4])
                    4'h8: begin                                   // key: one data byte
                        key_valid <= 1'b1;
                        key_usage <= {command[0], data[6:0]};
                        key_up <= command[1];
                        command <= 8'd0;
                    end
                    4'h9: if (count == 3'd1) begin                // move: dx, dy
                        move_valid <= 1'b1;
                        move_dx <= step(b0);
                        move_dy <= step(data[6:0]);
                        buttons <= command[2:0];
                        command <= 8'd0;
                    end
                    4'hA: if (count == 3'd3) begin                // position: x hi, x lo, y hi, y lo
                        position_valid <= 1'b1;
                        position_x <= {b0, b1};
                        position_y <= {b2, data[6:0]};
                        buttons <= command[2:0];
                        command <= 8'd0;
                    end
                    4'hB: begin                                   // wheel: dz
                        wheel_valid <= 1'b1;
                        wheel_dz <= step(data[6:0]);
                        command <= 8'd0;
                    end
                    default: command <= 8'd0;                     // unknown command: wait for the next one
                endcase
            end
        end
    end
endmodule
