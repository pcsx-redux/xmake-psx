.set noreorder
.set nomacro
.set noat

.set return, $v0
.set str, $a0

.set tmp, $at
.set tmp2, $v1

.global strlen
.weak strlen
strlen:
	li return, 0

.Lloop:
	lb tmp, (str)
	bnez tmp, .Lloop
	addiu return, 1 # branch delay slot
	jr $ra
	addiu return, -1 # branch delay slot
