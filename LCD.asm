; STUB CODE 
; includes code for displaying the number pressed on the
; keypad onto the LCD screen

; taken & modified from lab 4, part D

; The program gets input from keypad and displays its ascii value on the 
; LED bar

.include "m2560def.inc" 
; .def row = r16 ; current row number 
.def v = r16
.def temp1 = r17
.def temp2 = r18
.def temp3 = r19

.dseg
	row: .byte 1
	col: .byte 1
	rmask: .byte 1
	cmask: .byte 1

	doorIsOpen: .byte 1

	; Selects the mode: 1 = entry, 2 = power selection, 3 = running, 4 = paused, 5 = finished
	mode: .byte 1

	; The current input from the keypad
	currentInput: .byte 1

	; Time - split into minutes and seconds
	a: .byte 1
	b: .byte 1
	c: .byte 1
	d: .byte 1
	
.cseg


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


.equ PORTLDIR = 0xF0 ; PD7-4: output, PD3-0, input 
.equ INITCOLMASK = 0xEF ; scan from the rightmost column, \
.equ INITROWMASK = 0x01 ; scan from the top row 
.equ ROWMASK = 0x0F ; for obtaining input from Port L

; The del_hi:del_lo register pair store the loop counts 
; each loop generates about 1 us delay 

; Register data stores value to be written to the LCD 
; Port F is output and connects to LCD; Port A controls the LCD. 
; Assume all other labels are pre-defined. 

.def del_hi = r22
.def del_lo = r23
; .def current = r24
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

.macro lcd_write_data_direct
	ldi temp2, @0 
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

.macro lcd_write_data_register
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
	lcd_write_data_register temp2
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
	; Stack init
	ldi temp1, low(RAMEND)
	out SPL, temp1 
	ldi temp1, high(RAMEND) 
	out SPH, temp1 

	; Keypad init
	ldi temp1, PORTLDIR ; PA7:4/PA3:0, out/in 
	sts DDRL, temp1 

	; LED init
	ser temp1 ; PORTC is set as output 
	out DDRC, temp1 
	ldi temp1, 0xFF
	out PORTC, temp1

	; LCD init
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


	; Your own init
	clr total
	; clr current

	; Door is not initially open
	ldi v, 0
	setVar doorIsOpen, v

	; Mode is initially entry
	ldi v, 1
	setVar mode, v

	; The current input is non existent
	ldi v, -1 ; null
	setVar currentInput, v

	; The current time is initialised to 00:00
	ldi v, 0
	setVar a, v
	setVar b, v
	setVar c, v
	setVar d, v

	; Init with 0 0 display
	lcd_write_data_direct '0'
	lcd_write_data_direct '0'
	lcd_write_data_direct ':'
	lcd_write_data_direct '0'
	lcd_write_data_direct '0'
	
main: 
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	ldi v, INITCOLMASK ; initial column mask 
	setVar cmask, v
	clr v ; initial column
	setVar col, v

colloop: 
	getVar col, v
	cpi v, 4 
	breq main ; If all keys are scanned, repeat. 
	getVar cmask, v
	sts PORTL, v ; Otherwise, scan a column.
	ldi temp1, 0xFF ; Slow down the scan operation. 

wait: 
	dec temp1 
	brne wait

	lds temp1, PINL ; Read PORTL
	andi temp1, ROWMASK ; Get the keypad output value 
	cpi temp1, 0xF ; Check if any row is low 
	breq nextcol ; If yes, find which row is low 
	ldi v, INITROWMASK ; Initialize for row check 
	setVar rmask, v
	clr v ;
	setVar row, v

rowloop: 
	getVar row, v
	cpi v, 4 
	breq nextcol ; the row scan is over. 
	mov temp2, temp1 
	getVar rmask, v
	and temp2, v ; check un-masked bit 
	breq convert ; if bit is clear, the key is pressed 
	getVar row, v
	inc v ; else move to the next row 
	setVar row, v
	getVar rmask, v
	lsl v
	setVar rmask, v
	jmp rowloop 

nextcol: ; if row scan is over 
	getVar cmask, v
	lsl v 
	inc v
	setVar cmask, v
	getVar col, v
	inc v ; increase column value 
	setVar col, v
	jmp colloop ; go to the next column

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Find out what button was pressed
convert: 
	getVar col, v
	cpi v, 3 ; If the pressed key is in col.3 
	breq isLetter ; we have a letter 

	; If the key is not in col.3 and 

	getVar row, v
	cpi v, 3 ; If the key is in row3, 
	breq isSymbol_train ; we have a symbol or 0 
	jmp isDigit

isSymbol_train:
	jmp isSymbol

isDigit:
	getVar row, v
	mov temp1, v ; Otherwise we have a number in 1-9 

	; Dont display if larger than 100 
	; cpi current, 100
	; brsh convert_end_connector

	lsl temp1 
	getVar row, v
	add temp1, v
	getVar col, v 
	add temp1, v ; temp1 = row*3 + col 
	subi temp1, -1 ; Add the value of character �1� 

	; ldi temp2, 10 ;multiply current number by ten then add the new digit
	; mul current, temp2
	; mov current, r0
	; add current, temp1

	setVar currentInput, temp1
	clr temp1
	clr temp2
	clr r0
	;subi temp1, -48
	jmp convert_end

isLetter: 
	ldi temp2, 'A' 
	getVar row, v
	add temp2, v ; Get the ASCII value for the key 

	cpi temp2, 'A'
	breq AWasPressed
	cpi temp2, 'B' 
	breq BWasPressed
	cpi temp2, 'C' 
	breq CWasPressed
	cpi temp2, 'D' 
	breq DWasPressed

	clr temp2
	jmp convert_end 

convert_end_connector:
	jmp convert_end

AWasPressed:
	ldi v, 'A'
	setVar currentInput, v
	jmp convert_end

BWasPressed:
	ldi v, 'B'
	setVar currentInput, v
	jmp convert_end

CWasPressed:
	ldi v, 'C'
	setVar currentInput, v
	jmp convert_end

DWasPressed:
	ldi v, 'D'
	setVar currentInput, v
	jmp convert_end

isSymbol: 
	getVar col, v

	cpi v, 0 ; Check if we have a star 
	breq isStar 
	cpi v, 1 ; or if we have zero 
	breq isZero 
	ldi v, '#'
	setVar currentInput, v

	jmp convert_end 

isStar: 
	ldi v, '*'
	setVar currentInput, v
	jmp convert_end 

isZero: 
	; cpi current, 100
	; brsh convert_end

	; ldi temp2, 10 ;times current number by 10 (ie adding a zero to the end)
	; mul current, temp2
	; mov current, r0
	; clr temp2
	; clr r0
	ldi v, 0
	setVar currentInput, v
	jmp convert_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Handle the key that was pressed
convert_end: 
	lcd_write_com LCD_DISP_CLR ;clear the display
	lcd_wait_busy ;take yo time buddy


; Logic:
	; if open == true 
	; 	restart

	checkOpenDoor:
		getVar doorIsOpen, v
		cpi v, 0
		breq checkModes
		rjmp handleOpenDoor

	handleOpenDoor:
		jmp end

; Branch
	; if mode == entry
	; elsif mode == powerAdjustment
	; elsif mode == running
	; elsif mode == paused
	; elsif mode == finished

	checkModes:
		getVar mode, v

		cpi v, 1
		breq handleEntryMode_keypad_train
		cpi v, 2
		breq handlePowerSelectionMode_keypad_train
		cpi v, 3
		breq handleRunningMode_keypad_train
		cpi v, 4
		breq handlePausedMode_keypad_train
		cpi v, 5
		breq handleFinishedMode_keypad_train

		handleEntryMode_keypad_train:
			jmp handleEntryMode_keypad
		handlePowerSelectionMode_keypad_train:
			jmp handlePowerSelectionMode_keypad
		handleRunningMode_keypad_train:
			jmp handleRunningMode_keypad
		handlePausedMode_keypad_train:
			jmp handlePausedMode_keypad
		handleFinishedMode_keypad_train:
			jmp handleFinishedMode_keypad

		jmp error
	error:
		jmp error

; Entry mode
	; if 0-9
	; 	insert digit to the time
	; 	display updated time
	; if # 
	; 	clear time
	; 	display cleared time
	; if A
	; 	mode = powerAdjustment
	; 	display "Set Power 1/2/3"
	; if *
	; 	if time entered
	; 		mode = running
	; 		display time
	; 	else
	; 		mode = running
	; 		set time = 1 min
	; 		display 1 min of time
		
		handleEntryMode_keypad:
			ldi v, 0x01
			out PORTC, v

			cpi v, '#'
			breq clearTime_train
			cpi v, 'A'
			breq setPowerAdjustmentMode_train
			cpi v, '*'
			breq beginRunning_train

			cpi v, 0
			breq insertDigitIntoTime_train
			cpi v, 1
			breq insertDigitIntoTime_train
			cpi v, 2
			breq insertDigitIntoTime_train
			cpi v, 3
			breq insertDigitIntoTime_train
			cpi v, 4
			breq insertDigitIntoTime_train
			cpi v, 5
			breq insertDigitIntoTime_train
			cpi v, 6
			breq insertDigitIntoTime_train
			cpi v, 7
			breq insertDigitIntoTime_train
			cpi v, 8
			breq insertDigitIntoTime_train
			cpi v, 9
			breq insertDigitIntoTime_train

			jmp end

			clearTime_train:
				jmp clearTime
			setPowerAdjustmentMode_train:
				jmp setPowerAdjustmentMode
			beginRunning_train:
				jmp beginRunning
			insertDigitIntoTime_train:
				jmp insertDigitIntoTime

			clearTime:
				ldi v, 0
				setVar a, v
				setVar b, v
				setVar c, v
				setVar d, v

				rcall printTimeToLCD

				jmp end

			setPowerAdjustmentMode: ;NO DEBOUNCING ON BUTTON A?
				ldi v, 2
				setVar mode, v

				lcd_write_data_direct 'S'
				lcd_write_data_direct 'e'
				lcd_write_data_direct 't'
				lcd_write_data_direct ' '
				lcd_write_data_direct 'P'
				lcd_write_data_direct 'o'
				lcd_write_data_direct 'w'
				lcd_write_data_direct 'e'
				lcd_write_data_direct 'r'
				lcd_write_data_direct ' '
				lcd_write_data_direct '1'
				lcd_write_data_direct '/'
				lcd_write_data_direct '2'
				lcd_write_data_direct '/'
				lcd_write_data_direct '3'

				jmp end		

			beginRunning:

				; Check if time is empty or not 
				; ldi temp1, 0xFF

				; NEED TO FIX THIS
				; getVar a, v
				; and temp1, v

				; getVar b, v
				; and temp1, v

				; getVar c, v
				; and temp1, v
				
				; getVar d, v
				; and temp1, v

				; cpi temp1, 0
				; breq setToOneMin

				jmp beginRunning_goToRunningMode

				; Set the time to one min if time is empty, begin running
				setToOneMin:
					ldi v, 1
					setVar b, v

				jmp beginRunning_goToRunningMode
				
				; Else don't change the time, begin running
				beginRunning_goToRunningMode:
					ldi v, 3
					setVar mode, v

					; Print
					rcall printTimeToLCD

				jmp end

			insertDigitIntoTime:

				; If a > 0, end.
				getVar a, v
				cpi v, 0
				brne insertDigitIntoTime_printOnly_train
				jmp insertDigitIntoTime_cont

				insertDigitIntoTime_printOnly_train:
					jmp insertDigitIntoTime_printOnly

				; Shift digits, then insert the newest one.
				insertDigitIntoTime_cont:
					getVar b, v
					setVar a, v

					getVar c, v
					setVar b, v

					getVar d, v
					setVar c, v

					getVar currentInput, v
					setVar d, v	

				; Print the digits
				insertDigitIntoTime_printOnly:
					rcall printTimeToLCD

				jmp end		

; Power Selection Mode
	; elsif mode == powerAdjustment
	; 	if 1
	; 		power = 100
	; 	if 2 
	; 		power = 50
	; 	if 3
	; 		power = 25
	; 	if A
	; 		mode = entry
	; 		display entryStuff

		handlePowerSelectionMode_keypad:
			ldi v, 0x02
			out PORTC, v

			



			jmp end

; Running Mode
	; elsif mode == running
	; 	if C
	; 		add 30s to time
	; 	if D
	; 		minus 30s to time
	; 	if *
	; 		add 1 min to time
	; 	if #
	; 		mode = paused

		handleRunningMode_keypad:
			ldi v, 0x03
			out PORTC, v

			jmp end

; Paused mode
	; elsif mode == paused
	; 	if * 
	; 		mode = running
	; 	if #
	; 		if open = true
	; 			pass
	; 		else
	; 			mode = running

		handlePausedMode_keypad:
			ldi v, 0x04
			out PORTC, v

			jmp end

; Finished mode
	; elsif mode == finished
	; 	if #
	; 		mode = entry

		handleFinishedMode_keypad:
			ldi v, 0x05
			out PORTC, v

			jmp end




;;;;;;;;;;;;;;;;;;;;;;
end:

wait2:  ;wait until button is released
	lds v, PINL ; Read PORTL
	andi v, 0x0F ; rowmask of 0x0f
	cpi v, 0x0F

	breq final

	rjmp wait2

;;;;;;;;;;;;;;;;;;;;;;
final:
 ;restart yo ass
	jmp main


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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
	clr temp1
	clr temp2
	clr temp3
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

printTimeToLCD:
	getVar a, v
	lcd_write_digit v

	getVar b, v
	lcd_write_digit v

	lcd_write_data_direct ':'

	getVar c, v
	lcd_write_digit v

	getVar d, v
	lcd_write_digit v

	ret