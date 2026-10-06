# PicoRV32 RISC-V CPU

[PicoRV32](https://github.com/YosysHQ/picorv32) by Claire Xenia Wolf / YosysHQ, unchanged (ISC,
see the pack's LICENSE.txt; the notice stays in `picorv32.v`). A small RV32I CPU with a simple
memory interface: when `mem_valid` is high, answer with `mem_ready` (and `mem_rdata` for a read,
`mem_wstrb` = 0); writes come with `mem_wdata` and the byte lanes in `mem_wstrb`.

Tie the inputs you don't use: `pcpi_wr`, `pcpi_rd`, `pcpi_wait`, `pcpi_ready` and `irq` to 0.
Start with `resetn` low for a few cycles. The core needs memory and peripherals around it — the
template **PicoRV32 Hello** (File ▸ New Project…) is a complete SoC: 4 KB of RAM from
`src/firmware.hex`, a UART (GateLab Essentials' `uart_tx`) and the LEDs, with the firmware's C
source and how to rebuild it with `riscv64-elf-gcc`.

`picorv32.v` also holds the AXI and Wishbone variants (`picorv32_axi`, `picorv32_wb`) and the
PCPI multiplier and divider. The testbench is GateLab's.
