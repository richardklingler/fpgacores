// Self-checking testbench for PicoRV32 (packaged by GateLab; this testbench is GateLab's, CC0):
// a 1 KB memory with a small RV32I program assembled by riscv64-elf-gcc (source below) that
// sums 1 … 10, subtracts, loads a word, stores a byte and writes its results to an output port at
// 0x1000_0000. Checked: the results, the byte lane of the byte store, no trap.
//
//   li t0, 0; li t1, 1; li t2, 11
//   loop: add t0, t0, t1; addi t1, t1, 1; bne t1, t2, loop
//   lui t3, 0x10000; sw t0, 0(t3)            # 55
//   sub t4, t0, t1; sw t4, 16(t3)            # 44
//   lw a0, data; sw a0, 8(t3)                # 0xCAFEF00D
//   li a1, 0xA5; sb a1, 13(t3)               # lane 1 of 0x1000_000C
//   sw zero, 4(t3)                           # done
//   end: j end
//   data: .word 0xCAFEF00D

`timescale 1ns / 1ps

module picorv32_tb;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg resetn = 1'b0;

    wire        trap, mem_valid, mem_instr;
    reg         mem_ready = 1'b0;
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata = 32'd0;

    picorv32 dut (
        .clk(clk), .resetn(resetn), .trap(trap),
        .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
        .mem_la_read(), .mem_la_write(), .mem_la_addr(), .mem_la_wdata(), .mem_la_wstrb(),
        .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(),
        .pcpi_wr(1'b0), .pcpi_rd(32'd0), .pcpi_wait(1'b0), .pcpi_ready(1'b0),
        .irq(32'd0), .eoi(), .trace_valid(), .trace_data()
    );

    reg [31:0] memory [0:255];
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) memory[i] = 32'd0;
        memory[0] = 32'h00000293;
        memory[1] = 32'h00100313;
        memory[2] = 32'h00b00393;
        memory[3] = 32'h006282b3;
        memory[4] = 32'h00130313;
        memory[5] = 32'hfe731ce3;
        memory[6] = 32'h10000e37;
        memory[7] = 32'h005e2023;
        memory[8] = 32'h40628eb3;
        memory[9] = 32'h01de2823;
        memory[10] = 32'h00000517;
        memory[11] = 32'h01c52503;
        memory[12] = 32'h00ae2423;
        memory[13] = 32'h0a500593;
        memory[14] = 32'h00be06a3;
        memory[15] = 32'h000e2223;
        memory[16] = 32'h0000006f;
        memory[17] = 32'hcafef00d;
    end

    integer errors = 0;
    reg done = 1'b0;
    reg [31:0] sum = 32'hx, loaded = 32'hx, difference = 32'hx;
    reg [3:0] byte_strobe = 4'hx;
    reg [31:0] byte_data = 32'hx;

    // Memory and output port, one cycle per access.
    always @(posedge clk) begin
        mem_ready <= 1'b0;
        if (mem_valid && !mem_ready) begin
            mem_ready <= 1'b1;
            if (mem_addr < 32'h400) begin
                mem_rdata <= memory[mem_addr[9:2]];
                if (mem_wstrb != 0) begin
                    $display("FAIL: the program wrote to its own memory at %h", mem_addr);
                    errors = errors + 1;
                end
            end else if (mem_wstrb != 0) begin
                case (mem_addr)
                    32'h1000_0000: sum <= mem_wdata;
                    32'h1000_0004: done <= 1'b1;
                    32'h1000_0008: loaded <= mem_wdata;
                    32'h1000_0010: difference <= mem_wdata;
                    32'h1000_000C: begin byte_strobe <= mem_wstrb; byte_data <= mem_wdata; end
                    default: begin $display("FAIL: write to %h", mem_addr); errors = errors + 1; end
                endcase
            end else begin
                $display("FAIL: read from %h", mem_addr);
                errors = errors + 1;
            end
        end
    end

    initial begin
        $dumpfile("picorv32_tb.vcd");
        $dumpvars(0, picorv32_tb);
        repeat (10) @(posedge clk);
        resetn = 1'b1;
        wait (done || trap);
        repeat (2) @(posedge clk);
        if (trap) begin $display("FAIL: trap"); errors = errors + 1; end
        if (sum !== 32'd55) begin $display("FAIL: sum %0d, expected 55", sum); errors = errors + 1; end
        if (difference !== 32'd44) begin $display("FAIL: difference %0d, expected 44", difference); errors = errors + 1; end
        if (loaded !== 32'hCAFEF00D) begin $display("FAIL: loaded %h, expected cafef00d", loaded); errors = errors + 1; end
        if (byte_strobe !== 4'b0010 || byte_data[15:8] !== 8'hA5) begin
            $display("FAIL: byte store strobe %b data %h, expected 0010 and a5 in bits 15:8", byte_strobe, byte_data);
            errors = errors + 1;
        end
        if (errors == 0) $display("PASS");
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
