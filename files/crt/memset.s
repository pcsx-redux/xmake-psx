.set noreorder
.set nomacro
.set noat

.set return, $v0
.set dst, $a0
.set filler, $a1
.set length, $a2

.set target, $v1
.set tmp, $at

.global memset
.weak memset
memset:
	beqz length, .Lreturn
	addu target, dst, length // branch delay slot

.Lloop:
	addiu dst, 1
	bne dst, target, .Lloop
	sb filler, -1(dst) // branch delay slot

.Lreturn:
	jr $ra
	move return, dst // branch delay slot
