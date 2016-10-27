.include "m2560def.inc"

.def temp1 = r16
.def value = r17
.def counter = r18

.cseg
.org 0x0000
	jmp start
	jmp default
	jmp default
	jmp default
	jmp default
.org OVF2addr 
	jmp TIMER

default:
	reti
	
start:

	ser temp1
	out DDRC, temp1
	ldi temp1, 0xFF
	out PORTC, temp1

	; Timer init
	; -- Timer Counter Control Register for timer0
	ldi temp1, 0b00000000
	sts TCCR2A, temp1
	ldi temp1, 0b00000010
	sts TCCR2B, temp1 ; prescaling value = 8

	; -- enable Timer/counter interrupt (enable overflow interrupt)
	ldi temp1, 1 << TOIE2 
	sts TIMSK2, temp1 ;T/C0 interrupt enable

	sei ;set global interrupt flag (I) in sreg

	ldi value, 0
	ldi counter, 0

reset:
	jmp reset

TIMER:
	cpi counter, 255
	breq show
	inc counter
	reti

	show:
		clr counter
		dec value
		out PORTC, value

		reti
