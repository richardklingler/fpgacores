/* 4 KB of RAM at 0: code, data and stack (the stack starts at the top, in start.s). */
MEMORY { ram (rwx) : ORIGIN = 0x00000000, LENGTH = 4K }
SECTIONS {
    .text : { *(.text.start) *(.text*) *(.rodata*) *(.srodata*) } > ram
    .data : { *(.data*) *(.sdata*) } > ram
    .bss  : { *(.bss*) *(.sbss*) *(COMMON) } > ram
}
