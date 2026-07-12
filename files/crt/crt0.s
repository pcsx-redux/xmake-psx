.set reorder

.global _preinit_array_start, _preinit_array_end
.global _init_array_start, _init_array_end
.global _fini_array_start, _fini_array_end
.global _bss_start, _bss_end
.global _gp
.global main
.global _start

.set bak0, $s0
.set bak1, $s1
.set ra_backup, $s2
.set bak3, $s3
.set current_ptr, $s4
.set target_ptr, $s5
.set tmp, $s6

_start:
	// backup argc, argv and $ra
	move bak0, $a0
	move bak1, $a1
	move ra_backup, $ra
	la $gp, _gp // load up $gp

	// allow pcsx-redux functions to not crash
	lui $v0, 9
	sw $v0, 0x1F80101C

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
	la current_ptr, _preinit_array_start
	la target_ptr, _preinit_array_end
	jal .Lcall_all_in_list

	la current_ptr, _init_array_start
	la target_ptr, _init_array_end
	jal .Lcall_all_in_list

	// actually call main
	move $a0, bak0
	move $a1, bak1
	jal main

	// global destructors
	la current_ptr, _fini_array_start
	la target_ptr, _fini_array_end
	jal .Lcall_all_in_list

	// this will most likely crash the console
	jr ra_backup

.Lcall_all_in_list:
	move bak3, $ra
	bgeu current_ptr, target_ptr, .Lcall_all_in_list_ret
.Lcall_all_in_list_loop:
	lw tmp, (current_ptr)
	addiu current_ptr, current_ptr, 4
	// for some mysterious reason, g++ sometimes makes lists with null pointers, so check for that
	beqz tmp, .Lloop_forever
	jalr tmp
	bne current_ptr, target_ptr, .Lcall_all_in_list_loop
.Lcall_all_in_list_ret:
	jr bak3

.Lloop_forever:
	b .Lloop_forever

.global atexit
atexit:
	jr $ra
	nop
