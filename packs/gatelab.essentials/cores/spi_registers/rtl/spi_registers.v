// SPI registers: a microcontroller writes bytes anywhere in the design through one SPI link
// (mode 0, most significant bit first) — text cells, bar values, colours. Built on spi_slave, so
// SCLK must stay below clk / 8. Everything runs on `clk`; on a video design that's the pixel clock,
// the same clock text_layer's and bar_graph's write ports use, so no clock crossing is needed.
//
// One transaction per chip select (CS low … high):
//   0x01, address high, address low, data, data, …   writes each data byte to the address, then
//                                                     the next address (ADDR_BITS wide, wrapping)
//   0x02, then any bytes                              reads: the replies are ID, VERSION, status,
//                                                     then 0x00
// The reply to the first byte of every transaction is ID, so a controller sees the FPGA is there
// and configured with any command. Other commands are ignored until CS rises. `wr` pulses for one
// clock with `wr_addr` and `wr_data`; `done` pulses when CS rises after a write transaction, for
// designs that take a set of values at once.

module spi_registers #(
    parameter ADDR_BITS = 12,   // 1 … 16
    parameter [7:0] ID = 8'h47,
    parameter [7:0] VERSION = 8'h01
) (
    input  wire clk,
    input  wire sclk,
    input  wire cs_n,
    input  wire mosi,
    output wire miso,
    output reg  wr = 1'b0,
    output reg  [ADDR_BITS-1:0] wr_addr = 0,
    output reg  [7:0] wr_data = 8'd0,
    output reg  done = 1'b0,
    input  wire [7:0] status
);
    localparam [7:0] CMD_WRITE = 8'h01, CMD_READ = 8'h02;
    localparam S_COMMAND = 3'd0, S_ADDR_HI = 3'd1, S_ADDR_LO = 3'd2, S_DATA = 3'd3, S_READ = 3'd4, S_IGNORE = 3'd5;

    wire [7:0] rx_data;
    wire       rx_valid;
    reg  [7:0] tx_data = ID;

    spi_slave link (
        .clk(clk), .sclk(sclk), .cs_n(cs_n), .mosi(mosi), .miso(miso),
        .rx_data(rx_data), .rx_valid(rx_valid), .tx_data(tx_data)
    );

    // CS with spi_slave's own two-stage delay, and a third stage to see it rise.
    reg [2:0] cs_s = 3'b111;
    always @(posedge clk) cs_s <= {cs_s[1:0], cs_n};
    wire deselected = cs_s[1];
    wire cs_rose = cs_s[1] && !cs_s[2];

    reg [2:0] state = S_COMMAND;
    reg [1:0] reply = 2'd0;
    reg       wrote = 1'b0;
    reg [7:0] address_high = 8'd0;
    wire [15:0] address = {address_high, rx_data};

    always @(posedge clk) begin
        wr <= 1'b0;
        done <= 1'b0;
        if (deselected) begin
            state <= S_COMMAND;
            tx_data <= ID;
            if (cs_rose && wrote) done <= 1'b1;
            wrote <= 1'b0;
        end else if (rx_valid) begin
            tx_data <= 8'd0;
            case (state)
                S_COMMAND:
                    if (rx_data == CMD_WRITE) state <= S_ADDR_HI;
                    else if (rx_data == CMD_READ) begin
                        state <= S_READ;
                        tx_data <= ID;
                        reply <= 2'd1;
                    end else state <= S_IGNORE;
                S_ADDR_HI: begin
                    address_high <= rx_data;
                    state <= S_ADDR_LO;
                end
                S_ADDR_LO: begin
                    wr_addr <= address[ADDR_BITS-1:0];
                    state <= S_DATA;
                end
                S_DATA: begin
                    wr <= 1'b1;
                    wr_data <= rx_data;
                    wrote <= 1'b1;
                end
                S_READ: begin
                    case (reply)
                        2'd1: tx_data <= VERSION;
                        2'd2: tx_data <= status;
                        default: tx_data <= 8'd0;
                    endcase
                    if (reply != 2'd3) reply <= reply + 2'd1;
                end
                default: ;
            endcase
        end
        // The next data byte goes to the next address (after this one was written).
        if (wr) wr_addr <= wr_addr + 1'b1;
    end
endmodule
