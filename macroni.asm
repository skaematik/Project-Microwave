.include "m2560def.inc"

.def temp1 = r16
.def temp2 = r17
.def temp3 = r18
.def minutes = r19
.def seconds = r20

.def row = r21 ; current row number 
.def col = r22 ; current column number 
.def rmask = r23 ; mask for current row during scan 
.def cmask = r24 ; mask for current column during scan 

.equ PORTLDIR = 0xF0 ; PD7-4: output, PD3-0, input 
.equ INITCOLMASK = 0xEF ; scan from the rightmost column, \
.equ INITROWMASK = 0x01 ; scan from the top row 
.equ ROWMASK = 0x0F ; for obtaining input from Port L


;.include "Macros.asm"
;.include "LCD.asm"

.dseg
	time: .byte 2
	a: .byte 1
	b: .byte 1
	c: .byte 1
	d: .byte 1
	

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

; readKeypad <REGISTER>
.macro readKeypad
	;####################
	; READ KEYPAD
	;####################

	keypadStart: 
		ldi cmask, INITCOLMASK ; initial column mask 
		clr col ; initial column

	colloop: 
		cpi col, 4 
		breq keypadStart ; If all keys are scanned, repeat. 
		sts PORTL, cmask ; Otherwise, scan a column.
		ldi temp1, 0xFF ; Slow down the scan operation. 

	wait: 
		dec temp1 
		brne wait

		lds temp1, PINL ; Read PORTL
		andi temp1, ROWMASK ; Get the keypad output value 
		cpi temp1, 0xF ; Check if any row is low 
		breq nextcol ; If yes, find which row is low 
		ldi rmask, INITROWMASK ; Initialize for row check 
		clr row ;

	rowloop: 
		cpi row, 4 
		breq nextcol ; the row scan is over. 
		mov temp2, temp1 
		and temp2, rmask ; check un-masked bit 
		breq convert ; if bit is clear, the key is pressed 
		inc row ; else move to the next row 
		lsl rmask 
		jmp rowloop 

	nextcol: ; if row scan is over 
		lsl cmask 
		inc cmask
		inc col ; increase column value 
		jmp colloop ; go to the next column


	;##########################
	; CONVERT KEYPAD TO NUMBER
	;##########################

	convert: 
		cpi col, 3 ; If the pressed key is in col.3 
		breq letters ; we have a letter 

		; If the key is not in col.3 and 

		cpi row, 3 ; If the key is in row3, 
		breq symbols ; we have a symbol or 0 

		mov temp1, row ; Otherwise we have a number in 1-9 

		lsl temp1 
		add temp1, row 
		add temp1, col ; temp1 = row*3 + col 
		subi temp1, -1 ; Add the value of character ‘1’ 
		
		jmp keypadEnd

	letters: 
		ldi temp2, 'A' 
		add temp2, row ; Get the ASCII value for the key 

		jmp keypadEnd 

	symbols: 
		cpi col, 0 ; Check if we have a star 
		breq star 
		cpi col, 1 ; or if we have zero 
		breq zero 
		ldi temp1, '#' ; if not we have hash 
		jmp keypadEnd 

	star: 
		ldi temp1, '*' ; Set to star 
		jmp keypadEnd:

	zero: 
		ldi temp1, '0' ; Set to zero 

	keypadEnd:
		mov @0, temp1
		clr temp2
		clr temp1
			
.endmacro

; clearTime
.macro clearTime
	ldi temp1, 0
	setVar a, temp1
	setVar b, temp1
	setVar c, temp1
	setVar d, temp1
	clr minutes
	clr seconds
	setVar time, temp1
.endmacro

; multiply <NUMBER> <MULTIPLIER>
.macro multiply
	mul @0, @1
	mov @0, r0
.endmacro

; divide <NUMBER> <DIVISOR>
.macro divide
		mov temp1, @0
		mov temp2, @1
		clr temp3 ; divided amount
	compare_divide:
		cp temp1, temp2
		brsh loop_divide
		rjmp end_divide
	loop_divide:
		sub temp1, temp2
		inc temp3
		rjmp compare_divide
	end_divide:
		mov @0, temp3
.endmacro

; getTime - min, sec -> time
.macro getTime
	mov temp1, minutes
	mov temp2, seconds
	lds r25, time
	lds r26, time+1
	add_minutes:
		cpi temp1 0
		brne add_seconds
		adiw r26:r25, 60
		dec temp1
		jmp add_minutes
	add_seconds:
		cpi temp2 0
		brne add_time_end
		adiw r26:r25, 1
		dec temp2
		jmp add_seconds

	add_time_end:
		sts time, r25 
		sts time+1, r26
		clr temp1
		clr temp2
.endmacro

; setTime - time -> min, sec
.macro setTime
	; attempt at 2byte division
	lds r25, time
	lds r26, time+1
	lds r25, time
	lds r26, time+1
	cpi r25, low(60)
	ldi temp1, high(60)
	cpc r26, temp1

	;if time was a register
	divide temp1, 60
	mov minutes, temp1
	
	mov temp1, time
	compare_time:
		cp temp1, 60
		brsh loop_time
		rjmp end_time_divide
	loop_time:
		subi temp1, 60
		rjmp compare_time
	end_time_divide:
		mov seconds, temp1
.endmacro

; convertDigitsToTime - a, b, c, d to mins and secs
.macro convertDigitsToTime
	; takes first two digits for minutes
	getVar a, temp1
	multiply temp1, 10
	mov minutes, temp1
	getVar b, temp1
	add minutes, temp1

	; takes last two digits for seconds
	getVar c, temp1
	multiply temp1, 10
	mov seconds, temp1
	getVar d, temp1
	add seconds, temp1
.endmacro

; newDigit <inputDigit>
.macro newDigit
	;a = b
	getVar b, temp1
	setVar a, temp1

	;b = c
	getVar c, temp1
	setVar b, temp1

	;c = d
	getVar d, temp1
	setVar c, temp1

	;d = input
	setVar d, @0
.endmacro

;if macro???

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
