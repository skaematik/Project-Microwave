.include "m2560def.inc"

.def temp1 = r16
.def temp2 = r17

;.include "Macros.asm"
;.include "LCD.asm"

.dseg
	var: .byte 1

; getVar <VARIABLE LABEL> <REGISTER>
.macro getVar
	ldi XH, high(@0)
	ldi XL, low(@0)

	ld @1, X
.endmacro

; setVar <VARIABLE LABEL> <REGISTER>
.macro setVar
	ldi XH, high(@0)
	ldi XL, low(@0)

	st X, @1
.endmacro

.cseg

START:
	; init the stack
	ldi YL, low(RAMEND)
	ldi YH, high(RAMEND)
	out SPH, YH
	out SPL, YL


	ldi temp1, 0xFF
	setVar var, temp1

	ldi temp1, 0xEE
	getVar var, temp1
	
END:
	jmp END
