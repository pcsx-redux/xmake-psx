.set noreorder
.set nomacro
.set noat

#define return $v0
#define str $a0

#define tmp $at
#define tmp2 $v1

.section .text.strlen
.weak strlen
strlen:
	li return, 0

.Lloop:
	lb tmp, (str)
	bnez tmp, .Lloop
	addiu return, 1 // branch delay slot
	jr $ra
	addiu return, -1 // branch delay slot
