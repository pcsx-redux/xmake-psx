.set reorder

// symbols imported from elsewhere
.global __preinit_array_start, __preinit_array_end
.global __init_array_start, __init_array_end
.global __fini_array_start, __fini_array_end
.global _bss_start, _bss_end
.global _gp
.global main

#define main_a0 $s0
#define main_a1 $s1
#define main_ra $s2
#define tmp_ra_backup $s3
#define current_ptr $s4
#define target_ptr $s5
#define tmp $s6

.section .text.startup._start
.weak _start
_start:
	// backup argc, argv and $ra
	move main_a0, $a0
	move main_a1, $a1
	move main_ra, $ra

	// allow pcsx-redux functions to not crash
	lui $v0, 9
	sw $v0, 0x1F80101C

	// set $gp to the address provided by the linker
	la $gp, _gp

	// set $sp to 8MB - 16 bytes
	// this allows you to use 8MB if you have it, and is harmless if you don't
	li $sp, 0x807ffff0

	// clear bss region
	la current_ptr, _bss_start
	la target_ptr, _bss_end
	bgeu current_ptr, target_ptr, .Lbss_finish
.Lbss_loop:
	sw $0, (current_ptr)
	addiu current_ptr, current_ptr, 4
	bne current_ptr, target_ptr, .Lbss_loop
.Lbss_finish:

	// clear scratchpad
	la current_ptr, 0x1F800000
	la target_ptr, 0x1F800400
	bgeu current_ptr, target_ptr, .Lbss_finish
.Lscratchpad_loop:
	sw $0, (current_ptr)
	addiu current_ptr, current_ptr, 4
	bne current_ptr, target_ptr, .Lscratchpad_loop
.Lscratchpad_finish:

	// call all pre-main functions
	la current_ptr, __preinit_array_start
	la target_ptr, __preinit_array_end
	jal .Lcall_all_in_list

	la current_ptr, __init_array_start
	la target_ptr, __init_array_end
	jal .Lcall_all_in_list

	// actually call main
	move $a0, main_a0
	move $a1, main_a1
	jal main

	// global destructors
	la current_ptr, __fini_array_start
	la target_ptr, __fini_array_end
	jal .Lcall_all_in_list

	// this will most likely crash the console
	jr main_ra

.Lcall_all_in_list:
	move tmp_ra_backup, $ra
	bgeu current_ptr, target_ptr, .Lcall_all_in_list_ret
.Lcall_all_in_list_loop:
	lw tmp, (current_ptr)
	addiu current_ptr, current_ptr, 4
	// for some mysterious reason, g++ sometimes makes lists with null pointers, so check for that
	beqz tmp, .Lloop_forever
	jalr tmp
	bne current_ptr, target_ptr, .Lcall_all_in_list_loop
.Lcall_all_in_list_ret:
	jr tmp_ra_backup

.Lloop_forever:
	b .Lloop_forever
