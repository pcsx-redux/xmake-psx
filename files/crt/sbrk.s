.section .sdata._heap_ptr, "aw", @progbits
.weak _heap_ptr
_heap_ptr:
	.4byte _heap_start

.section .text.sbrk, "ax"
.weak sbrk
sbrk:
	lw $v0, (_heap_ptr)
	addu $a0, $v0, $a0
	sw $a0, (_heap_ptr)
	jr $ra
