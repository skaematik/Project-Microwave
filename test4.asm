.include "m2560def.inc"

.set pattern = 0xFF

.def basePattern = r16
.def sound = r17
.def on = r18
.def temp1 = r19
.def temp = r20
.def counter1 = r21

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


.macro clearVar
	clr v
	setVar @0, v
.endmacro

; The macro clears a word (2 bytes) in a memory 
; the parameter @0 is the memory address for that word 
.macro clear
	ldi YL, low(@0) ; load the memory address to Y 
	ldi YH, high(@0) 
	clr temp 
	st Y+, temp  ; clear the two bytes at @0 in SRAM
	st Y, temp
.endmacro 

.dseg
	counter: .byte 2 ; Two-byte counter for counting seconds.
	beep_count: .byte 2
.cseg
.org 0x0000
   jmp start
.org OVF2addr 
	jmp TIMER2 ; Jump to the interrupt handler for Timer0 overflow.
   	jmp DEFAULT          ; default service for all other interrupts.

DEFAULT:  reti          ; no service

start:
	; -- stack
	ldi temp, low(RAMEND) ;init stack / stackpointer from RAMEND
	out SPL, temp
	ldi temp, high(RAMEND)
	out SPH, temp

	; -- portB
	ser temp ;set PORTB as output
	out DDRB, temp

	clr temp ;write 0 to PORTB
	out PORTB, temp

	; -- Timer Counter Control Register for timer0
	ldi temp, 0b00000000
	sts TCCR2A, temp
	ldi temp, 0b00000010
	sts TCCR2B, temp ; prescaling value = 8

	; -- enable Timer/counter interrupt (enable overflow interrupt)
	ldi temp, 1 << TOIE2 ;= 128 microsecs
	sts TIMSK2, temp ;T/C0 interrupt enable

	sei ;set global interrupt flag (I) in sreg

	clr on
	ldi counter1, 3
	; -- rjmp
	rjmp main

	; -- timer
TIMER2: 
	; -- load tempcounter and increment it
	lds r24, counter
	lds r25, counter+1
	adiw r25:r24, 1 

	out PORTB, basePattern

continue:

	; -- check if second has passed -- 7812 = 10^6/128
	cpi r24, low(7812)
	ldi temp, high(7812)
	cpc r25, temp
	brne timerNotSecondYet

	; -- second has been reached
	clear counter ; Reset the temporary counter.

	cpi on, 0
	breq turnon
	ldi sound, 0x00
	ldi on, 0

	rjmp timerFinish

turnon:
	cpi counter1, 0
	breq timerFinish
	ldi sound, 0xFF
	ldi on, 1
	dec counter1
	rjmp timerFinish

timerNotSecondYet: ; Store the new value of the temp counter

display_LED:
	out PORTC, sound

	sts counter, r24 
	sts counter+1, r25
	cpi on, 1
	brne timerFinish
	
	out PORTB,sound

timerFinish:
	reti

	; -- main
main:
	ldi basePattern, 0x00
	ldi sound, 0x00
	ldi on, 0

	clr temp

	; -- start timers
	clear counter

loop:
	rjmp loop

