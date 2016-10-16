;####################
; MACROS
;####################

.macro lcd_write_com 
	ldi temp2, @0
	out PORTF, temp2 ; set the data port's value up 
	;clr temp 
	;out PORTA, temp ; RS = 0, RW = 0 for a command write 
	delay 1000 ; delay to meet timing (Set up time) 
	sbi PORTA, LCD_E ; turn on the enable pin 
	delay 1000 ; delay to meet timing (Enable pulse width) 
	cbi PORTA, LCD_E ; turn off the enable pin 
	delay 1000 ; delay to meet timing (Enable cycle time) 
.endmacro

.macro lcd_write_data
	push temp2
		mov temp2, @0
		out PORTF, temp2 ; set the data port's value up 
		sbi PORTA, LCD_RS ; RS = 1, RW = 0 for a data write 
		delay 1000 ; delay to meet timing (Set up time) 
		sbi PORTA, LCD_E ; turn on the enable pin 
		delay 1000 ; delay to meet timing (Enable pulse width)  
		cbi PORTA, LCD_E ; turn off the enable pin 
		delay 1000 ; delay to meet timing (Enable cycle time) 
		cbi PORTA, LCD_RS
		lcd_wait_busy
	pop temp2
.endmacro

.macro lcd_write_digit
	push temp1
		mov temp1, @0
		subi temp1, -48
		lcd_write_data temp1
		clr temp1
	pop temp1
.endmacro

.macro lcd_wait_busy 
	push temp1
		clr temp1
		out DDRF, temp1 ; Make PORTF be an input port for now 
		out PORTF, temp1 
		sbi PORTA, LCD_RW ; RS = 0, RW = 1 for a command port read 
	busy_loop: 
		delay 1000 ; delay to meet set-up time) 
		sbi PORTA, LCD_E ; turn on the enable pin 
		delay 1000 ; delay to meet timing (Data delay time) 
		in temp1, PINF ; read value from LCF 
		cbi PORTA, LCD_E ; turn off the enable pin 
		sbrc temp1, LCD_BF ; if the busy flag is set 
		rjmp busy_loop ; repeat command read ;else
		cbi PORTA, LCD_RW ; turn off read mode, 
		ser temp1 ; 
		out DDRF, temp1 ; make PORTD an output port again
	pop temp1 
.endmacro


;.equ F_CPU = 16000000
;.equ DELAY_1MS = F_CPU / 4 / 1000 - 4
; 4 cycles per iteration - setup/call-return overhead

.macro delay
	push del_lo
	push del_hi
	ldi del_lo, low(@0)
	ldi del_hi, high(@0)
loop: 
	subi del_lo, 1 
	sbci del_hi, 0  
	brne loop ; taken branch takes two cycles. 
		; one loop time is 8 cycles = ~1.08us 
	pop del_hi
	pop del_lo
.endmacro

.macro display_numbers ; load in number to be split into digits and displayed
	push temp1
	push temp2
	push temp3
	
	mov temp1, @0
	clr temp2
	clr temp3

	rcall checkHundredsDigit

	pop temp3
	pop temp2
	pop temp1
.endmacro