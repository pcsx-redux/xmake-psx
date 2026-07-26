.set noreorder
.set nomacro
.set noat

#define return $v0
#define dst $a0
#define filler $a1
#define length $a2

#define target $v1
#define tmp $at

.section .text.memset
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
