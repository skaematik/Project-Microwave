


; STUB CODE 
; includes code for displaying the number pressed on the
; keypad onto the LCD screen

; taken & modified from lab 4, part D


.def row = r16 ; current row number 
.def col = r17 ; current column number 
.def rmask = r18 ; mask for current row during scan 
.def cmask = r19 ; mask for current column during scan 
.def temp1 = r20 
.def temp2 = r21 
.def temp3 = r26

.equ PORTLDIR = 0xF0 ; PD7-4: output, PD3-0, input 
.equ INITCOLMASK = 0xEF ; scan from the rightmost column, \
.equ INITROWMASK = 0x01 ; scan from the top row 
.equ ROWMASK = 0x0F ; for obtaining input from Port L

;
; The del_hi:del_lo register pair store the loop counts 
; each loop generates about 1 us delay 

; Register data stores value to be written to the LCD 
; Port F is output and connects to LCD; Port A controls the LCD. 
; Assume all other labels are pre-defined. 

.def del_hi = r22
.def del_lo = r23
.def current = r24
.def total = r25

.equ LCD_RS = 7
.equ LCD_E = 6
.equ LCD_RW = 5
.equ LCD_BE = 4

.equ LCD_BF = 7
.equ LCD_FUNC_SET = 56
.equ LCD_DISP_OFF = 8
.equ LCD_DISP_CLR = 1
.equ LCD_ENTRY_SET = 6
.equ LCD_DISP_ON = 14

.equ LCD_N = 1
.equ LCD_ID = 1
.equ LCD_C = 1

.equ LCD_NEW_LINE = 192

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
.endmacro

.macro lcd_write_digit
	push temp2
	mov temp2, @0
	subi temp2, -48
	lcd_write_data temp2
	clr temp2
	pop temp2
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

.macro display_numbers ;load in number to be split into digits and displayed
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


RESET: 
	ldi temp1, low(RAMEND) ; initialize the stack 
	out SPL, temp1 
	ldi temp1, high(RAMEND) 
	out SPH, temp1 

	; -- keypad
	ldi temp1, PORTLDIR ; PA7:4/PA3:0, out/in 
	sts DDRL, temp1 

	ser temp1 ; PORTC is output 
	out DDRC, temp1 
	out PORTC, temp1

	; -- LCD
	ser temp1
	out DDRF, temp1
	out DDRA, temp1
	clr temp1
	out PORTF, temp1
	out PORTA, temp1


	;lcd display initialisation
	delay 15000; delay (>15ms) 

	; Function set command with N = 1 and F = 0 
	; for 2 line display and 5*7 font. The 1st command 
	lcd_write_com LCD_FUNC_SET

	delay 4100 ; delay (>4.1 ms) 

	lcd_write_com LCD_FUNC_SET; 2nd Function set command 

	delay 100 ; delay (>100 ns)

	lcd_write_com LCD_FUNC_SET; 3rd Function set command 
	lcd_write_com LCD_FUNC_SET; Final Function set command 

	lcd_wait_busy ; Wait until the LCD is ready 
	lcd_write_com LCD_DISP_OFF ; Turn Display off 

	lcd_wait_busy ; Wait until the LCD is ready 
	lcd_write_com LCD_DISP_CLR ; Clear Display 

	lcd_wait_busy ; Wait until the LCD is ready 
	; Entry set command with I/D = 1 and S = 0 
	; Set Entry mode: Increment = yes and Shift = no 
	lcd_write_com  LCD_ENTRY_SET

	lcd_wait_busy ; Wait until the LCD is ready 
	; Display On command with C = 1 and B = 0 
	lcd_write_com LCD_DISP_ON

	clr total
	clr current
	;initialise with 0 0 display
	lcd_write_digit total
	lcd_write_com LCD_NEW_LINE
	lcd_write_digit current

main: 
	ldi cmask, INITCOLMASK ; initial column mask 
	clr col ; initial column

colloop: 
	cpi col, 4 
	breq main ; If all keys are scanned, repeat. 
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

convert: 
	cpi col, 3 ; If the pressed key is in col.3 
	breq letters ; we have a letter 

	; If the key is not in col.3 and 

	cpi row, 3 ; If the key is in row3, 
	breq symbols ; we have a symbol or 0 

	mov temp1, row ; Otherwise we have a number in 1-9 

	; Dont display if larger than 100 
	cpi current, 100
	brsh convert_end_connector

	lsl temp1 
	add temp1, row 
	add temp1, col ; temp1 = row*3 + col 
	subi temp1, -1 ; Add the value of character ‘1’ 
	ldi temp2, 10 ;multiply current number by ten then add the new digit
	mul current, temp2
	mov current, r0
	add current, temp1
	clr temp2
	clr temp1
	clr r0
	;subi temp1, -48
	jmp convert_end

letters: 
	jmp convert_end 

symbols: 
	cpi col, 0 ; Check if we have a star 
	breq star 
	cpi col, 1 ; or if we have zero 
	breq zero 
	;ldi temp1, '#' ; if not we have hash 
	;jmp convert_end 
	jmp main

star: 
	ldi temp1, '*' ; Set to star 
	; jmp RESET ;reset whole thingo
	jmp convert_end 

zero: 
	ldi temp1, '0' ; Set to zero 
	
convert_end: 
	lcd_write_com LCD_DISP_CLR ;clear the display
	lcd_wait_busy ;take yo time buddy
	;lcd_write_data total
	display_numbers total ;display total number
	lcd_write_com LCD_NEW_LINE ;next line
	;lcd_write_data current ; Write value to PORTC 

	mov temp1, current
	clr temp2
	clr temp3

	rcall checkHundredsDigit

	; display_numbers current ;display current number

wait2:  ;wait until button is released
	lds temp2, PINL ; Read PORTL
	;ldi temp1, 0xF
	andi temp2, 0x0F ; rowmask of 0x0f
	cpi temp2, 0x0F

	breq end

	push temp2
	ldi temp1, 0xFF ; Slow down
wait3: 
	ldi temp2, 0xFF
wait4:
	dec temp2
	brne wait4
	dec temp1 
	brne wait3
	pop temp2

	rjmp wait2

end: ;restart yo ass
	rjmp main

;; temp1 -- current number to be displayed / parsed
;; temp2 -- the number of <hundreds/tens/ones> found in temp1
; -- check if the number has a hundreds digit, if none left, 
; then push the number of hundreds onto stack
checkHundredsDigit: 
	cpi temp1, 100
	brsh incHundreds ; branch if temp1 >= 100
	push temp2 
	clr temp2
; -- check if the number has a tens digit, if none left,
; then push number of tens onto stack	
checkTensDigit: 
	cpi temp1, 10 
	brsh incTens ; branch if temp1 >= 10
	push temp2
	clr temp2
; -- push the number of ones digits onto stack
addones: 
	push temp1
	jmp popDigits

incHundreds: ; increment number of hundreds
	subi temp1, 100
	inc temp2
	rjmp checkHundredsDigit
incTens: ; increment number of tens
	subi temp1, 10
	inc temp2
	rjmp checkTensDigit

; pop stored digits off stack
popDigits: 

	clr rmask
	clr cmask
	clr temp1
	clr temp2
	clr temp3

	pop temp2 ; ones
	pop temp1 ; tens
	pop temp3 ; hundreds

; check if we have a nonzero hundreds digit, if so then display the hundreds digit
displayHundred:
	; pop temp1 ; ones
	cpi temp3, 0 
	brne displayHundred_continue
	rjmp displayTen
displayHundred_continue:
	lcd_write_digit temp3
; check if we have a nonzero tens AND hundreds digit, if so then display the tens digit
displayTen:
	add temp3, temp1
	cpi temp3, 0
	brne displayTen_continue
	rjmp displayOne
displayTen_continue:
	lcd_write_digit temp1
; display ones digit
displayOne: 
	; out PORTC, temp2
	lcd_write_digit temp2
cleanup:
	clr rmask
	clr cmask
	clr temp1
	clr temp2
	clr temp3
	ret
