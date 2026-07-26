.set noreorder
.set nomacro
.set noat

#define return $v0
#define dst $a0
#define src $a1
#define length $a2

#define target $v1
#define tmp $at

.section .text.memcpy
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
