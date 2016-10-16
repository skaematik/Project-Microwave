; STUB CODE 
; includes code for displaying the number pressed on the
; keypad onto the LCD screen

; taken & modified from lab 4, part D


.def row = r16 ; time row number 
.def col = r17 ; time column number 
.def rmask = r18 ; mask for time row during scan 
.def cmask = r19 ; mask for time column during scan 
.def temp1 = r20 
.def temp2 = r21 
.def temp3 = r22

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

.def del_hi = r23
.def del_lo = r24
.def time = r25

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

;####################
; INITIALISATION
;####################

Reset: 

	; Initialize the stack 
	ldi temp1, low(RAMEND) 
	out SPL, temp1 
	ldi temp1, high(RAMEND) 
	out SPH, temp1 

	; Keypad
	ldi temp1, PORTLDIR ; PA7:4/PA3:0, out/in 
	sts DDRL, temp1 

	; Set PORTC as output (LEDS)
	ser temp1 
	out DDRC, temp1 
	out PORTC, temp1

	; LCD
	ser temp1
	out DDRF, temp1
	out DDRA, temp1
	clr temp1
	out PORTF, temp1
	out PORTA, temp1

	; Lcd display initialisation
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


	; Your own initialisation
	clr time

	; Initialise with current time as 00:00
	ldi temp1, 0
	lcd_write_digit temp1
	lcd_write_digit temp1
	ldi temp1, ':'
	lcd_write_data temp1
	ldi temp1, 0
	lcd_write_digit temp1
	lcd_write_digit temp1

	; New line
	lcd_write_com LCD_NEW_LINE

	; Write E10 to bottom line of the LCD
	ldi temp1, 'E'
	lcd_write_data temp1
	ldi temp1, 1
	lcd_write_digit temp1
	ldi temp1, 0
	lcd_write_digit temp1

;####################
; READ KEYPAD
;####################

main: 
	ldi cmask, INITCOLMASK ; cmask = INITCOLMASK = 0xEF = 1110 1111
	clr col ; column = 0

colloop: 
	; Scan each column
	cpi col, 4 ; if (col == 4)
	breq main ; go to main -> If all keys are scanned, repeat. 
	sts PORTL, cmask ; else, scan a column.

	; Slow down the scan operation by waiting.
	ldi temp1, 0xFF 
wait: 
	dec temp1 
	brne wait

	; Read input from PortL
	lds temp1, PINL ; Read PORTL
	andi temp1, ROWMASK ; Get the keypad output value 
	cpi temp1, 0xF ; Check if any row is low 
	breq nextcol ; If yes, find which row is low 
	ldi rmask, INITROWMASK ; Initialize for row check 
	clr row ; row = 0

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
	breq isLetter ; we have a letter 

	; If the key is not in col.3 and 
	cpi row, 3 ; If the key is in row3, 
	breq isSymbol ; we have a symbol or 0 

	mov temp1, row ; Otherwise we have a number in 1-9 

isNumber:
	; Dont display if larger than 100 
	cpi time, 100
	brsh convert_end

	lsl temp1 
	add temp1, row 
	add temp1, col ; temp1 = row*3 + col 
	subi temp1, -1 ; Add the value of character ‘1’ 
	ldi temp2, 10 ;multiply time number by ten then add the new digit
	mul time, temp2
	mov time, r0
	add time, temp1
	clr temp2
	clr temp1
	clr r0
	;subi temp1, -48
	jmp convert_end

isLetter: 
	jmp convert_end 

isSymbol: 
	cpi col, 0 ; Check if we have a star 
	breq isStar 
	cpi col, 1 ; or if we have zero 
	breq isZero 
	jmp isHash ; if not we have hash 
	jmp main

isStar: 
	ldi temp1, '*' ; Set to star 
	jmp convert_end 

isHash:
	ldi temp1, '#'
	jmp convert_end 

isZero: 
	ldi temp1, '0' ; Set to zero 
	jmp convert_end 
	
convert_end: 
	lcd_write_com LCD_DISP_CLR ; clear the display
	lcd_wait_busy 


	; Display the input time
	display_numbers time 

	lcd_write_com LCD_NEW_LINE 

	; Write E10 to bottom line of the LCD
	ldi temp1, 'E'
	lcd_write_data temp1
	ldi temp1, 1
	lcd_write_digit temp1
	ldi temp1, 0
	lcd_write_digit temp1


end: ;restart yo ass
	rjmp main

;; temp1 -- time number to be displayed / parsed
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
