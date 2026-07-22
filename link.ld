/* One PT_LOAD segment, nothing else. No GNU_STACK, no second segment, no
 * page-alignment gap. Combined with strip + --strip-section-headers this
 * leaves only: 64-byte ELF header + one 56-byte program header + code. */
ENTRY(_start)
PHDRS { all PT_LOAD FLAGS(7); }        /* FLAGS(7) = R|W|X */
SECTIONS {
	. = 0x400000 + SIZEOF_HEADERS;
	.text : { *(.text*) *(.rodata*) *(.data*) } :all
	. = ALIGN(8);
	.bss  : { *(.bss*) *(COMMON) } :all    /* NOBITS - costs nothing on disk */
}
