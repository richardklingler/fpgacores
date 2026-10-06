# Firmware

`main.c` and `start.s`, linked with `link.ld` into 4 KB of RAM. GateLab doesn't compile C: the
project ships the result as `src/firmware.hex`, which the design loads (`$readmemh`). To change
the firmware, install a RISC-V compiler (`brew install riscv64-elf-gcc`), then from the project
folder:

```sh
cd firmware
riscv64-elf-gcc -march=rv32i -mabi=ilp32 -Os -ffreestanding -nostdlib \
    -Wl,-T,link.ld -Wl,--no-warn-rwx-segments -o firmware.elf start.s main.c
riscv64-elf-objcopy -O binary firmware.elf firmware.bin
python3 -c "import struct; d = open('firmware.bin', 'rb').read(); d += bytes(4096 - len(d)); \
open('../src/firmware.hex', 'w').writelines('%08x\n' % w for w in struct.unpack('<1024I', d))"
```

The image is padded to the full 4 KB (1024 words). Then simulate (⌘U) and build again. The
program must fit in 4 KB including its stack.
