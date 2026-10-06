// Self-checking testbench for i2c_master against an I2C target modelled on a small EEPROM at
// address 0x50 (a register pointer, then data; reads continue from the pointer). The target
// stretches the clock before it answers each acknowledge, so a master that doesn't wait for SCL
// reads a wrong ACK. Checked: written bytes land in the target, a repeated start and reads with
// ACK/NACK return them, an absent address is NACKed, and START/STOP conditions happen exactly
// where the commands put them (no glitch counts as one).

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

module i2c_master_tb;
    reg clk = 1'b0;
    always #10 clk = ~clk;              // 50 MHz

    reg  [1:0] cmd = 2'd0;
    reg  [7:0] tx_data = 8'd0;
    reg        ack_read = 1'b0, go = 1'b0;
    wire       ready, done, ack, scl_oe, sda_oe;
    wire [7:0] rx_data;
    wire       target_scl_low, target_sda_low;

    // Open-drain bus with pull-ups.
    wire scl = !(scl_oe || target_scl_low);
    wire sda = !(sda_oe || target_sda_low);

    i2c_master #(.CLK_HZ(50000000), .I2C_HZ(400000)) dut (
        .clk(clk), .cmd(cmd), .tx_data(tx_data), .ack_read(ack_read), .go(go), .ready(ready),
        .done(done), .rx_data(rx_data), .ack(ack),
        .scl_oe(scl_oe), .scl_in(scl), .sda_oe(sda_oe), .sda_in(sda)
    );
    i2c_target_model target (.scl(scl), .sda(sda), .scl_low(target_scl_low), .sda_low(target_sda_low));

    integer errors = 0;

    task command(input [1:0] c, input [7:0] d, input a);
        begin
            @(negedge clk);
            while (!ready) @(negedge clk);
            cmd = c; tx_data = d; ack_read = a; go = 1'b1;
            @(negedge clk);
            go = 1'b0;
            @(posedge done);
            @(negedge clk);
        end
    endtask

    task write(input [7:0] d, input expect_ack);
        begin
            command(2'd1, d, 1'b0);
            if (ack !== expect_ack) begin
                $display("FAIL: write %h: ack %b, expected %b", d, ack, expect_ack);
                errors = errors + 1;
            end
        end
    endtask

    task read(input more, input [7:0] expected);
        begin
            command(2'd2, 8'h00, more);
            if (rx_data !== expected) begin
                $display("FAIL: read %h, expected %h", rx_data, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("i2c_master_tb.vcd");
        $dumpvars(0, i2c_master_tb);
        #1000;
        if (scl !== 1'b1 || sda !== 1'b1) begin
            $display("FAIL: the master doesn't release the bus when idle");
            errors = errors + 1;
        end

        // Write 0xAB, 0xCD to registers 0x10, 0x11.
        command(2'd0, 0, 0);
        write(8'hA0, 1'b1);
        write(8'h10, 1'b1);
        write(8'hAB, 1'b1);
        write(8'hCD, 1'b1);
        command(2'd3, 0, 0);
        if (target.memory[8'h10] !== 8'hAB || target.memory[8'h11] !== 8'hCD) begin
            $display("FAIL: the target holds %h %h, expected ab cd", target.memory[8'h10], target.memory[8'h11]);
            errors = errors + 1;
        end

        // Read them back: pointer write, repeated start, two reads (ACK, then NACK).
        command(2'd0, 0, 0);
        write(8'hA0, 1'b1);
        write(8'h10, 1'b1);
        command(2'd0, 0, 0);
        write(8'hA1, 1'b1);
        read(1'b1, 8'hAB);
        read(1'b0, 8'hCD);
        command(2'd3, 0, 0);

        // Nobody at 0x51.
        command(2'd0, 0, 0);
        write(8'hA2, 1'b0);
        command(2'd3, 0, 0);

        #2000;
        if (target.starts != 4 || target.stops != 3) begin
            $display("FAIL: %0d starts and %0d stops on the bus, expected 4 and 3", target.starts, target.stops);
            errors = errors + 1;
        end
        if (scl !== 1'b1 || sda !== 1'b1) begin
            $display("FAIL: bus not released after STOP");
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #5000000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
