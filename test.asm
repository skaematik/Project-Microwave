.include "m2560def.inc"

.def temp1 = r16
.def temp2 = r17


.dseg
	var: .byte 2
`
; temp1
.macro getVar
	ldi XH, high(var)
	ldi XL, low(var)

	ld temp1, X
.endmacro

; temp1
.macro setVar
	ldi XH, high(var)
	ldi XL, low(var)

	st X, temp1
.endmacro

.cseg

START:
	; init the stack
	ldi YL, low(RAMEND)
	ldi YH, high(RAMEND)
	out SPH, YH
	out SPL, YL

	getVar

	ldi temp1, 0xFF
	setVar temp1
	
END:
	jmp END
