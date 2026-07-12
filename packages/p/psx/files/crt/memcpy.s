.set noreorder
.set nomacro
.set noat

.set return, $v0
.set dst, $a0
.set src, $a1
.set length, $a2

.set target, $v1
.set tmp, $at

.global memcpy
.weak memcpy
memcpy:
	beqz length, .Lreturn
	addu target, dst, length // branch delay slot

.Lloop:
	lb tmp, (src)
	addiu src, 1
	addiu dst, 1
	bne dst, target, .Lloop
	sb tmp, -1(dst) // branch delay slot

.Lreturn:
	jr $ra
	move return, dst // branch delay slot
