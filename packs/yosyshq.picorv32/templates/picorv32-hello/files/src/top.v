// {{PROJECT_NAME}}: a PicoRV32 RISC-V system on the {{BOARD_NAME}}.
// 4 KB of RAM loaded from src/firmware.hex, a UART transmitter at 115200 baud and the LEDs.
// The firmware (firmware/main.c) prints a line and counts on the LEDs; see firmware/README.md.
//
// Memory map: 0x0000_0000 RAM (4 KB) · 0x1000_0000 UART data (write) · 0x1000_0004 UART status
// (bit 0: ready) · 0x2000_0000 LEDs.

module top #(
    // The board's clock; the testbench in sim/ runs a slower one.
    parameter CLK_HZ = {{CLK_HZ}}
) (
    input  wire clk,
    output wire uart_tx,
    input  wire uart_rx,
    output wire [{{LED_COUNT}}-1:0] led
);
    localparam LED_COUNT = {{LED_COUNT}};
    localparam [LED_COUNT-1:0] LED_ACTIVE_LOW = {{LED_ACTIVE_LOW}};

    // Hold the CPU in reset for the first 16 cycles after configuration.
    reg [4:0] reset_count = 0;
    wire resetn = reset_count[4];
    always @(posedge clk)
        if (!resetn) reset_count <= reset_count + 1'b1;

    wire        mem_valid;
    reg         mem_ready = 1'b0;
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata = 32'd0;

    picorv32 #(
        .ENABLE_COUNTERS(0),
        .ENABLE_COUNTERS64(0),
        .CATCH_MISALIGN(0),
        .CATCH_ILLINSN(0)
    ) cpu (
        .clk(clk), .resetn(resetn), .trap(),
        .mem_valid(mem_valid), .mem_instr(), .mem_ready(mem_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
        .mem_la_read(), .mem_la_write(), .mem_la_addr(), .mem_la_wdata(), .mem_la_wstrb(),
        .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(),
        .pcpi_wr(1'b0), .pcpi_rd(32'd0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
        .irq(32'd0), .eoi(), .trace_valid(), .trace_data()
    );

    // RAM: 1024 words, one cycle per access (block RAM on every family).
    reg [31:0] ram [0:1023];
    initial $readmemh("src/firmware.hex", ram);

    // UART: GateLab Essentials' uart_tx, one byte per write.
    reg  [7:0] tx_byte = 8'd0;
    reg        tx_valid = 1'b0;
    wire       tx_ready;
    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(115200)) uart (
        .clk(clk), .data(tx_byte), .valid(tx_valid), .ready(tx_ready), .tx(uart_tx)
    );

    reg [LED_COUNT-1:0] led_on = 0;
    assign led = led_on ^ LED_ACTIVE_LOW;

    wire is_ram = (mem_addr[31:12] == 20'd0);

    always @(posedge clk) begin
        mem_ready <= 1'b0;
        if (tx_valid && tx_ready) tx_valid <= 1'b0;
        if (is_ram && mem_valid && !mem_ready) begin
            mem_rdata <= ram[mem_addr[11:2]];
            if (mem_wstrb[0]) ram[mem_addr[11:2]][ 7: 0] <= mem_wdata[ 7: 0];
            if (mem_wstrb[1]) ram[mem_addr[11:2]][15: 8] <= mem_wdata[15: 8];
            if (mem_wstrb[2]) ram[mem_addr[11:2]][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) ram[mem_addr[11:2]][31:24] <= mem_wdata[31:24];
            mem_ready <= 1'b1;
        end else if (mem_valid && !mem_ready) begin
            mem_ready <= 1'b1;
            mem_rdata <= 32'd0;
            case (mem_addr)
                32'h1000_0000: if (mem_wstrb != 0) begin tx_byte <= mem_wdata[7:0]; tx_valid <= 1'b1; end
                32'h1000_0004: mem_rdata <= {31'd0, tx_ready && !tx_valid};
                32'h2000_0000: if (mem_wstrb != 0) led_on <= mem_wdata[LED_COUNT-1:0];
                default: ;
            endcase
        end
    end

    // uart_rx is there for your own receiver (GateLab Essentials' uart_rx).
    wire unused = uart_rx;
endmodule
