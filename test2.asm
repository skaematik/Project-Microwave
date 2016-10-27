.include "m2560def.inc"

.def temp1 = r16
.def temp2 = r17



.cseg

START:
	; init the stack
	ldi YL, low(RAMEND)
	ldi YH, high(RAMEND)
	out SPH, YH
	out SPL, YL

	ldi temp1, 0
	ldi temp2, 1

	cpi temp1, 0
	cpi temp2, 0
	cpi temp1, 0
	cpi temp1, 0
	brne END
	jmp START
	
END:
	jmp END
