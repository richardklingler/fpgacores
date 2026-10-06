// Self-checking testbench for Alex Forencich's i2c_master (packaged by GateLab; this testbench is
// GateLab's, CC0) against an I2C target modelled on a small EEPROM at address 0x50, which
// stretches the clock before every acknowledge. Checked: a write-multiple lands in the target,
// a pointer write and two reads (the second with stop) return it, an absent address strobes
// missed_ack, and START/STOP conditions happen exactly where the commands put them.

`timescale 1ns / 1ps

module i2c_target_model #(parameter [6:0] ADDRESS = 7'h50, parameter STRETCH_NS = 3000) (
    input  wire scl,
    input  wire sda,
    output reg  scl_low = 1'b0,
    output reg  sda_low = 1'b0
);
    localparam IDLE = 0, RX = 1, RX_ACK = 2, TX = 3, TX_ACK = 4;
    integer state = IDLE;
    integer count = 0;
    reg [7:0] shift = 8'd0;
    reg [7:0] memory [0:255];
    reg [7:0] pointer = 8'd0;
    reg addressed = 1'b0, reading = 1'b0, first_data = 1'b0, master_ack = 1'b0;
    integer starts = 0, stops = 0;

    // START and STOP: SDA changes while SCL is high (not the lines settling at time 0).
    always @(negedge sda) if (scl === 1'b1 && $time > 0) begin
        starts = starts + 1;
        state = RX; count = 0; addressed = 1'b0; sda_low = 1'b0;
    end
    always @(posedge sda) if (scl === 1'b1 && $time > 0) begin
        stops = stops + 1;
        state = IDLE; sda_low = 1'b0;
    end

    always @(posedge scl) begin
        if (state == RX) begin
            shift = {shift[6:0], sda};
            count = count + 1;
        end else if (state == TX_ACK) begin
            master_ack = !sda;
        end
    end

    always @(negedge scl) begin
        case (state)
            RX: if (count == 8) begin
                // Hold SCL low while deciding: the master must wait for it.
                scl_low = 1'b1;
                #(STRETCH_NS);
                if (!addressed) begin
                    if (shift[7:1] == ADDRESS) begin
                        addressed = 1'b1; reading = shift[0]; first_data = !shift[0];
                        sda_low = 1'b1; state = RX_ACK;
                    end else begin
                        state = IDLE;            // not us: no ACK
                    end
                end else begin
                    if (first_data) begin pointer = shift; first_data = 1'b0; end
                    else begin memory[pointer] = shift; pointer = pointer + 1; end
                    sda_low = 1'b1; state = RX_ACK;
                end
                // Data setup time before SCL is let go (releasing both at once would look
                // like a START).
                #100;
                scl_low = 1'b0;
            end
            RX_ACK: begin
                if (reading) begin
                    shift = memory[pointer]; pointer = pointer + 1;
                    sda_low = !shift[7]; count = 1; state = TX;
                end else begin
                    sda_low = 1'b0; count = 0; state = RX;
                end
            end
            TX: if (count == 8) begin
                sda_low = 1'b0; state = TX_ACK;
            end else begin
                sda_low = !shift[7 - count]; count = count + 1;
            end
            TX_ACK: if (master_ack) begin
                shift = memory[pointer]; pointer = pointer + 1;
                sda_low = !shift[7]; count = 1; state = TX;
            end else begin
                sda_low = 1'b0; state = IDLE;
            end
        endcase
    end
endmodule

module forencich_i2c_master_tb;
    reg clk = 1'b0;
    always #10 clk = ~clk;              // 50 MHz
    reg rst = 1'b1;

    reg  [6:0] address = 7'd0;
    reg        start = 1'b0, read = 1'b0, write = 1'b0, write_multiple = 1'b0, stop = 1'b0;
    reg        cmd_valid = 1'b0;
    wire       cmd_ready;
    wire       data_tready, rd_tvalid, rd_tlast;
    wire [7:0] rd_tdata;
    wire       scl_o, scl_t, sda_o, sda_t;
    wire       busy, bus_control, bus_active, missed_ack;
    wire       target_scl_low, target_sda_low;

    // Open-drain bus with pull-ups (the core drives a line low when *_t is 0 and *_o is 0).
    wire scl = !((!scl_t && !scl_o) || target_scl_low);
    wire sda = !((!sda_t && !sda_o) || target_sda_low);

    // Bytes to write, fed through the data stream.
    reg [7:0] bytes [0:7];
    integer byte_count = 0, byte_index = 0;
    wire [7:0] wr_tdata = bytes[byte_index];
    wire wr_tvalid = byte_index < byte_count;
    wire wr_tlast = byte_index == byte_count - 1;

    i2c_master dut (
        .clk(clk), .rst(rst),
        .s_axis_cmd_address(address), .s_axis_cmd_start(start), .s_axis_cmd_read(read),
        .s_axis_cmd_write(write), .s_axis_cmd_write_multiple(write_multiple), .s_axis_cmd_stop(stop),
        .s_axis_cmd_valid(cmd_valid), .s_axis_cmd_ready(cmd_ready),
        .s_axis_data_tdata(wr_tdata), .s_axis_data_tvalid(wr_tvalid), .s_axis_data_tready(data_tready), .s_axis_data_tlast(wr_tlast),
        .m_axis_data_tdata(rd_tdata), .m_axis_data_tvalid(rd_tvalid), .m_axis_data_tready(1'b1), .m_axis_data_tlast(rd_tlast),
        .scl_i(scl), .scl_o(scl_o), .scl_t(scl_t), .sda_i(sda), .sda_o(sda_o), .sda_t(sda_t),
        .busy(busy), .bus_control(bus_control), .bus_active(bus_active), .missed_ack(missed_ack),
        .prescale(16'd31), .stop_on_idle(1'b0)
    );
    i2c_target_model target (.scl(scl), .sda(sda), .scl_low(target_scl_low), .sda_low(target_sda_low));

    integer errors = 0;
    integer missed = 0;
    reg [7:0] got [0:7];
    integer got_count = 0;
    reg last_had_tlast = 1'b0;
    always @(posedge clk) begin
        if (wr_tvalid && data_tready) byte_index = byte_index + 1;
        if (missed_ack) missed = missed + 1;
        if (rd_tvalid) begin got[got_count] = rd_tdata; got_count = got_count + 1; last_had_tlast = rd_tlast; end
    end

    task command(input [6:0] a, input s, input r, input w, input wm, input p);
        begin
            @(negedge clk);
            address = a; start = s; read = r; write = w; write_multiple = wm; stop = p; cmd_valid = 1'b1;
            @(posedge clk);
            while (!cmd_ready) @(posedge clk);
            @(negedge clk);
            cmd_valid = 1'b0;
        end
    endtask

    task idle;
        begin
            @(posedge clk);
            while (busy || cmd_ready == 1'b0) @(posedge clk);
            repeat (200) @(posedge clk);
            while (busy) @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("forencich_i2c_master_tb.vcd");
        $dumpvars(0, forencich_i2c_master_tb);
        repeat (5) @(posedge clk);
        rst = 1'b0;
        #1000;

        // Register 0x10, then 0xAB and 0xCD, in one write-multiple with stop.
        bytes[0] = 8'h10; bytes[1] = 8'hAB; bytes[2] = 8'hCD;
        byte_index = 0; byte_count = 3;
        command(7'h50, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1);
        idle;
        if (target.memory[8'h10] !== 8'hAB || target.memory[8'h11] !== 8'hCD) begin
            $display("FAIL: the target holds %h %h, expected ab cd", target.memory[8'h10], target.memory[8'h11]);
            errors = errors + 1;
        end

        // Pointer write, then two reads (repeated start implied), the second with stop.
        bytes[0] = 8'h10;
        byte_index = 0; byte_count = 1;
        command(7'h50, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        command(7'h50, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);
        command(7'h50, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1);
        idle;
        if (got_count != 2 || got[0] !== 8'hAB || got[1] !== 8'hCD || !last_had_tlast) begin
            $display("FAIL: read %0d bytes %h %h (tlast %b), expected ab cd with tlast", got_count, got[0], got[1], last_had_tlast);
            errors = errors + 1;
        end
        if (missed != 0) begin
            $display("FAIL: missed_ack with a present target");
            errors = errors + 1;
        end

        // Nobody at 0x51.
        bytes[0] = 8'h00;
        byte_index = 0; byte_count = 1;
        command(7'h51, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1);
        idle;
        // The core still sends the data byte after the address NACK: one strobe each.
        if (missed == 0) begin
            $display("FAIL: no missed_ack strobe for an absent address");
            errors = errors + 1;
        end

        #2000;
        if (target.starts != 4 || target.stops != 3) begin
            $display("FAIL: %0d starts and %0d stops on the bus, expected 4 and 3", target.starts, target.stops);
            errors = errors + 1;
        end
        if (scl !== 1'b1 || sda !== 1'b1) begin
            $display("FAIL: bus not released at the end");
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #10000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
