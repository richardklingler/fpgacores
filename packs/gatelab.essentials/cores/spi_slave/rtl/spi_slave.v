// SPI slave, mode 0 (SCLK idles low, data sampled on the rising edge), most significant bit
// first. SCLK, CS and MOSI are synchronised into `clk` and sampled there, so `clk` must be at least
// 8 times the SPI clock.
//
// While CS is low each byte from the master arrives on `rx_data` with a one-cycle `rx_valid`.
// `tx_data` is taken when CS falls and again after every byte, and goes out on `miso` during
// the next byte. `miso` is always driven; on a shared bus, drive the pin only while `cs_n` is
// low: `assign miso_pin = cs_n ? 1'bz : miso;`.

module spi_slave (
    input  wire       clk,
    input  wire       sclk,
    input  wire       cs_n,
    input  wire       mosi,
    output wire       miso,
    output reg  [7:0] rx_data = 8'd0,
    output reg        rx_valid = 1'b0,
    input  wire [7:0] tx_data
);
    // Three stages: two to synchronise, one to see edges.
    reg [2:0] sclk_s = 3'b000;
    reg [2:0] cs_s = 3'b111;
    reg [1:0] mosi_s = 2'b00;
    always @(posedge clk) begin
        sclk_s <= {sclk_s[1:0], sclk};
        cs_s <= {cs_s[1:0], cs_n};
        mosi_s <= {mosi_s[0], mosi};
    end
    wire sclk_rise = sclk_s[1] && !sclk_s[2];
    wire sclk_fall = !sclk_s[1] && sclk_s[2];
    wire selected = !cs_s[1];
    wire cs_fell = !cs_s[1] && cs_s[2];

    reg [7:0] rx_shift = 8'd0;
    reg [7:0] tx_shift = 8'd0;
    reg [2:0] bit_count = 3'd0;
    reg       reload = 1'b0;

    assign miso = tx_shift[7];

    always @(posedge clk) begin
        rx_valid <= 1'b0;
        if (cs_fell) begin
            bit_count <= 3'd0;
            tx_shift <= tx_data;
            reload <= 1'b0;
        end else if (selected) begin
            if (sclk_rise) begin
                rx_shift <= {rx_shift[6:0], mosi_s[1]};
                bit_count <= bit_count + 1'b1;
                if (bit_count == 3'd7) begin
                    rx_data <= {rx_shift[6:0], mosi_s[1]};
                    rx_valid <= 1'b1;
                    reload <= 1'b1;
                end
            end else if (sclk_fall) begin
                // The next bit: from the shift register, or the next byte after the eighth.
                if (reload) begin
                    tx_shift <= tx_data;
                    reload <= 1'b0;
                end else begin
                    tx_shift <= {tx_shift[6:0], 1'b0};
                end
            end
        end
    end
endmodule
