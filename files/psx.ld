/* linker script for psx */
/* credit: https://github.com/spicyjpeg/ps1-bare-metal/blob/main/cmake/executable.ld */

ENTRY(_start)

MEMORY {
	MAIN_RAM (rwx) : ORIGIN = 0x80010000, LENGTH = DEFINED(__LARGE_MEMORY__)? 0x7F0000: 0x1F0000
	SCRATCHPAD (rw) : ORIGIN = 0x1F800000, LENGTH = 0x400
}

SECTIONS {
	.text : ALIGN(4) {
		*(.text .text.hot .text.hot.* .text.* .gnu.linkonce.t.*)
		*(SORT(.text.sorted.*))
		*(.plt .MIPS.stubs)
		*(.text.unlikely .text.*_unlikely .text.unlikely.*)
		KEEP(*(SORT_NONE(.init)))
		KEEP(*(SORT_NONE(.fini)))
		*(.text.startup .text.startup.* .text.exit .text.exit.*)
		PROVIDE(main = _Z4mainv);
	} > MAIN_RAM
	.rodata : ALIGN(4) {
		*(.rodata .rodata.* .gnu.linkonce.r.*)

		. = ALIGN(4);
		__preinit_array_start = .;
		KEEP(*(.preinit_array))
		__preinit_array_end = .;

		__init_array_start = .;
		KEEP(*(SORT(.init_array.*) SORT(.ctors.*)))
		KEEP(*(.init_array .ctors))
		__init_array_end = .;

		__fini_array_start = .;
		KEEP(*(SORT(.fini_array.*) SORT(.dtors.*)))
		KEEP(*(.fini_array .dtors))
		__fini_array_end = .;
	} > MAIN_RAM

	. = ALIGN(16);
	.sdata : ALIGN(16) {
		_gp = . + 0x7ff0;
		*(.sdata .sdata.* .gnu.linkonce.s.*)
	} > MAIN_RAM
	.sbss (NOLOAD) : ALIGN(16) {
		_bss_start = .;
		*(.sbss* .sbss.* .gnu.linkonce.sb.*)
		*(.scommon)
	} > MAIN_RAM
	.bss (NOLOAD) : ALIGN(4) {
		*(.bss* .bss.* .gnu.linkonce.b.*)
		*(COMMON)
		. = ALIGN(4);
		_bss_end = .;
	} > MAIN_RAM
	.data : ALIGN(4) {
		*(.data .data.* .gnu.linkonce.d.*)
	} > MAIN_RAM

	.dummy (NOLOAD) : ALIGN(4) {
		KEEP(*(.dummy))
	} > MAIN_RAM
	. = ALIGN(64);
	_heap_start = .;

	/DISCARD/ : {
		*(.note.* .gnu_debuglink .gnu.lto_*)
		*(.MIPS.abiflags)
	}

	/* this only works because i patched convert_executable.py (line 115) to discard this section */
	/* otherwise it blows up the psexe to 1.8gb */
	.scratchpad (NOLOAD) : {
		*(.scratchpad)
		. = ALIGN(4);
		_scratchpad_bump_start = .;
	} > SCRATCHPAD
}
