; Group: E10
; Annie Zhang / Stephen Chung
; z3459054 / z3463108

.include "m2560def.inc" 
; .def row = r16 ; current row number 
.def v = r16
.def temp1 = r17
.def temp2 = r18
.def temp3 = r19
.def mins = r20
.def secs = r21

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

	; Power level
	power: .byte 1

	; Time - split into minutes and seconds
	a: .byte 1
	b: .byte 1
	c: .byte 1
	d: .byte 1

	; Functions refer to magnetron, turntable and timers
	; This restarts everytime operation is stopped completed
	functionsRunning: .byte 1

	; Timers
	counter: .byte 1
	counter250: .byte 1
	counter500: .byte 1
	counter1000: .byte 1
	counter5000: .byte 1

	; Magnetron variables
	magnetronCounter: .byte 1
	magnetronRunning: .byte 1

	; Turntable
	; Specifies which character is being displayed
	index: .byte 1
	; The direction that the turntable is rotating in.
	; CCWrotation = 1 meaning it is CCW
	CCWrotation: .byte 1

	; Whether the finish sound should be playing or not
	playFinishSound: .byte 1
	finishSoundCounter: .byte 1
	nFinishSounds: .byte 1
	finishSoundIsOn: .byte 1
	
	; Beep 250ms
	beepCounter: .byte 1
	keyPressed: .byte 1

.cseg
.org 0x0000
	jmp RESET
.org INT0addr
	jmp CLOSE_DOOR
.org INT1addr
	jmp OPEN_DOOR
.org OVF2addr 
	jmp TIMER2
.org OVF0addr 
	jmp TIMER

; Value to drive the magnetron on or off.

.equ MOTORON = 0b00001000
.equ MOTOROFF = 0

; Keypad
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
.def t = r24

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
.equ LCD_SHIFT_LEFT = 16

.equ LCD_N = 1
.equ LCD_ID = 1
.equ LCD_C = 1

.equ LCD_NEW_LINE = 192

.macro lcd_write_com 
	ldi temp2, @0
	out PORTF, temp2 ; set the data port's value up 
	;clr temp1 
	;out PORTA, temp1 ; RS = 0, RW = 0 for a command write 
	delay 1000 ; delay to meet timing (Set up time) 
	sbi PORTA, LCD_E ; turn on the enable pin 
	delay 1000 ; delay to meet timing (Enable pulse width) 
	cbi PORTA, LCD_E ; turn off the enable pin 
	delay 1000 ; delay to meet timing (Enable cycle time) 
.endmacro

.macro lcd_write_data_direct
	; push temp2
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
	; pop temp2
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

; convertDigitsToTime - a, b, c, d to mins and secs
.macro convertDigitsToTime
	; takes first two digits for minutes
	getVar a, temp1
	ldi temp2, 10
	multiply temp1, temp2
	mov mins, temp1
	getVar b, temp1
	add mins, temp1

	; takes last two digits for seconds
	getVar c, temp1
	ldi temp2, 10
	multiply temp1, temp2
	mov secs, temp1
	getVar d, temp1
	add secs, temp1
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


RESET: 
	; Stack init
	ldi temp1, low(RAMEND)
	out SPL, temp1 
	ldi temp1, high(RAMEND) 
	out SPH, temp1 

	; Magnetron/motor init
	ldi v, 0b00001000
	sts DDRH, v

	; Keypad init
	ldi temp1, PORTLDIR ; PA7:4/PA3:0, out/in 
	sts DDRL, temp1 

	; LED init
	ser temp1 ; PORTC is set as output 
	out DDRC, temp1 

	; Top LED init
	ser temp1
	out DDRG, temp1

	; LCD init
	ser temp1
	out DDRF, temp1
	out DDRA, temp1
	clr temp1
	out PORTF, temp1
	out PORTA, temp1
	

	; Sound init
	ser temp1 ; set PORTB as output
	out DDRB, temp1

	clr temp1 ; write 0 to PORTB
	out PORTB, temp1

	; Timer init
	; -- Timer Counter Control Register for timer0
	ldi temp1, 0b00000000
	out TCCR0A, temp1
	ldi temp1, 0b00000011
	out TCCR0B, temp1 ; prescaling value = 8

	; -- enable Timer/counter interrupt (enable overflow interrupt)
	ldi temp1, 1 << TOIE0 
	sts TIMSK0, temp1 ;T/C0 interrupt enable

	; Timer 2
	ldi temp1, 0b00000000
	sts TCCR2A, temp1
	ldi temp1, 0b00000101
	sts TCCR2B, temp1 
	ldi temp1, 1 << TOIE2 
	sts TIMSK2, temp1 

	sei ;set global interrupt flag (I) in sreg

	; Interrupts for push buttons (INT0 and INT1)
	ldi temp1, (2 << ISC00) | (2 << ISC10) ;set INT0 and INT1 (i.e. from ISCn0) as falling-edge triggered
	sts EICRA, temp1 ;use register A (i.e EICRA) for INT0

	in temp1, EIMSK ;enable INT0 by setting corresp. bit in EIMSK
	ori temp1, (1 << INT0) | (1 << INT1) ;ori=logical OR
	out EIMSK, temp1

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

	; Door is not initially open
	ldi v, 0
	setVar doorIsOpen, v
	ldi v, 0
	call setDoorLEDClosed

	; Mode is initially entry
	ldi v, 1
	setVar mode, v

	; The current input is non existent
	ldi v, -1 ; null
	setVar currentInput, v

	; Set functions to not running
	ldi v, 0
	setVar functionsRunning, v

	; The current time is initialised to 00:00
	ldi v, 0
	setVar a, v
	setVar b, v
	setVar c, v
	setVar d, v

	; Reset timers
	ldi v, 0
	setVar counter, v
	setVar counter250, v
	setVar counter500, v
	setVar counter1000, v
	setVar counter5000, v

	; turntable
	ldi v, 0
	setVar index, v
	ldi v, 1
	setVar CCWrotation, v

	; Set power level to 100
	ldi v, 100
	setVar power, v
	ldi temp1, 0xFF
	out PORTC, temp1

	; Motor is not initally running
	ldi v, MOTOROFF
	sts PORTH, v

	; Finish sound shouldnt be playing
	ldi v, 0
	setVar playFinishSound, v
	setVar finishSoundCounter, v
	setVar nFinishSounds, v
	setVar finishSoundIsOn, v

	; Init with 0 0 display
	rcall printDigitsToLCD
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
main: 
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

	lsl temp1 
	getVar row, v
	add temp1, v
	getVar col, v 
	add temp1, v ; temp1 = row*3 + col 
	subi temp1, -1 ; Add the value of character 1

	setVar currentInput, temp1
	clr temp1
	clr temp2
	clr r0
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
	ldi v, 0
	setVar currentInput, v
	jmp convert_end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Handle the key that was pressed
convert_end: 

	; Register a keypress
	clr v
	setVar beepCounter, v
	ldi v, 1
	setVar keyPressed, v

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
		lcd_write_com LCD_DISP_CLR ;clear the display
		lcd_wait_busy ;take yo time buddy

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
		jmp end

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

			getVar currentInput, v

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

			jmp handleEntryMode_keypad_end

			clearTime_train:
				jmp clearTime
			setPowerAdjustmentMode_train:
				jmp setPowerAdjustmentMode
			beginRunning_train:
				jmp beginRunning
			insertDigitIntoTime_train:
				jmp insertDigitIntoTime

			clearTime:
				rcall clearTimeAndDigits

				rcall printDigitsToLCD

				jmp end

			setPowerAdjustmentMode: ;NO DEBOUNCING ON BUTTON A?
				ldi v, 2
				setVar mode, v

				call writePowerLabels

				jmp end		

			beginRunning:

				; Check if time is empty or not 
				getVar a, temp1
				getVar b, temp2
				add temp1, temp2
				getVar c, temp2
				add temp1, temp2
				getVar d, temp2
				add temp1, temp2
				cpi temp1, 0
				breq setToOneMin

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
					convertDigitsToTime
					call printTimeToLCD

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
					rcall printDigitsToLCD

				jmp end	

			handleEntryMode_keypad_end:
				rcall printDigitsToLCD
				jmp end	


; Power Selection Mode
	; elsif mode == powerAdjustment
	; 	if 1
	; 		power = 100
	; 	if 2 
	; 		power = 50
	; 	if 3
	; 		power = 25
	; 	if #
	; 		mode = entry
	; 		display entryStuff

		handlePowerSelectionMode_keypad:
			; ldi v, 0x02
			; out PORTC, v

			getVar currentInput, v

			cpi v, 1
			breq setPowerOf100
			cpi v, 2
			breq setPowerOf50
			cpi v, 3
			breq setPowerOf25

			cpi v, '#'
			breq goBackToEntry

			jmp handlePowerSelectionMode_keypad_else

			setPowerOf100:
				ldi v, 100
				setVar power, v

				ldi v, 0b11111111
 				out PORTC, v

				rcall writePowerLabels

				jmp end

			setPowerOf50:
				ldi v, 50
				setVar power, v

				ldi v, 0b00001111
 				out PORTC, v

				rcall writePowerLabels

				jmp end

			setPowerOf25:
				ldi v, 25
				setVar power, v

				ldi v, 0b00000011
 				out PORTC, v

				rcall writePowerLabels

				jmp end

			goBackToEntry:
				ldi v, 1
				setVar mode, v
				rcall printDigitsToLCD

				jmp end


			handlePowerSelectionMode_keypad_else:
				rcall writePowerLabels

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

			getVar currentInput, v

			cpi v, 'C'
			breq add30Secs
			cpi v, 'D'
			breq minus30Secs
			cpi v, '*'
			breq add1Min
			cpi v, '#'
			breq goToPaused

			jmp handleRunningMode_keypad_else

				; if secs < 30
				; 	add 30 to secs
				; elsif secs >= 30
				; 	remove 30 from secs
				; 	add 1 to min if min != 99
				add30Secs:
					cpi secs, 30
					brsh add30Secs_specialCase
					subi secs, -30
					jmp add30Secs_end

					add30Secs_specialCase:
						cpi mins, 99
						breq add30Secs_end
						subi secs, 30
						subi mins, -1
						jmp add30Secs_end

					add30Secs_end:
						call printTimeToLCD
						jmp end

				; if secs >= 30
				; 	remove 30 from secs
				; elsif secs < 30
				; 	add 30 to secs
				; 	remove 1 from min if min != 0
				minus30Secs:
					cpi secs, 30
					brlt minus30Secs_specialCase
					subi secs, 30
					jmp minus30Secs_end

					minus30Secs_specialCase:
						cpi mins, 0
						breq goToFinished_train
						subi secs, -30
						subi mins, 1
						jmp minus30Secs_end

						goToFinished_train:
							call finished
							jmp end

					minus30Secs_end:
						call printTimeToLCD
						jmp end

				add1Min:
					cpi mins, 99
					breq add1Min_end
					subi mins, -1
					jmp add1Min_end

					add1Min_end:
						call printTimeToLCD
						jmp end

				goToPaused:
					ldi v, 4
					setVar mode, v

					call pauseMotor

					call printTimeToLCD

					jmp end

			handleRunningMode_keypad_else:
				call printTimeToLCD

				jmp end


; Paused mode
	; elsif mode == paused
	; 	if * 
	; 		mode = running
	; 	if #
	;       mode = entry

		handlePausedMode_keypad:

			getVar currentInput, v

			cpi v, '*'
			breq startRunningAgain
			cpi v, '#'
			breq goToEntryModeAgain

			jmp handlePausedMode_keypad_else


			startRunningAgain:
				ldi v, 3
				setVar mode, v

				call resumeMotor
				call toggleRotationDirection

				call printTimeToLCD
				jmp end

			goToEntryModeAgain:
				ldi v, 1
				setVar mode, v


				ldi v, 0
				setVar functionsRunning, v
				setVar magnetronRunning, v

				rcall clearTimeAndDigits
				rcall printDigitsToLCD

				jmp end

			handlePausedMode_keypad_else:
				call printTimeToLCD

				jmp end


; Finished mode
	; elsif mode == finished
	; 	if #
	; 		mode = entry

		handleFinishedMode_keypad:
			getVar currentInput, v
			cpi v, '#'
			breq fromFinishedToEntry

			jmp handleFinishedMode_keypad_else

			fromFinishedToEntry:
				ldi v, 1
				setVar mode, v

				ldi v, 0
				setVar playFinishSound, v

				ldi v, 0
				setVar finishSoundCounter, v
				setVar nFinishSounds, v
				setVar finishSoundIsOn, v

				rcall clearTimeAndDigits
				rcall printDigitsToLCD
				jmp end

			handleFinishedMode_keypad_else:
				call writeFinishedText
				jmp end
				
;;;;;;;;;;;;;;;;;;;;;;
end:

wait2:  ;wait until button is released
	lds v, PINL ; Read PORTL
	andi v, 0x0F ; Rowmask of 0x0F
	cpi v, 0x0F

	breq final

	rjmp wait2

;;;;;;;;;;;;;;;;;;;;;;
final:
	jmp main
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; The printDigitsToLCD function will, in entry mode,
; display the correct time, turntable, group number and door state.
printDigitsToLCD:
	getVar a, v
	lcd_write_digit v

	getVar b, v
	lcd_write_digit v

	lcd_write_data_direct ':'

	getVar c, v
	lcd_write_digit v

	getVar d, v
	lcd_write_digit v

	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '

	call turntable

	call writeSecondLineToDisplay

	ret

;;;;;;;;;;;;;;;;;;;;;;;
; The clearTimeAndDigits function will clear the a, b, c and d
; time variables used in entry mode as well as the mins and secs 
; registers used during running mode.
clearTimeAndDigits:
	ldi v, 0
	setVar a, v
	setVar b, v
	setVar c, v
	setVar d, v

	clr mins
	clr secs

	ret

;;;;;;;;;;;;;;;;;;;;;
; The turntable function will, according to the current character 
; it should be displaying, specified by the index variable, display 
; that character on the display
turntable:
	push temp1
	getVar index, temp1
	cpi temp1, 0
	breq index0
	cpi temp1, 1
	breq index1
	cpi temp1, 2
	breq index2
	cpi temp1, 3
	breq index3
	jmp turntable_display

	index0:
		ldi temp1, '-'
		jmp turntable_display
	index1:
		ldi temp1, '`'
		jmp turntable_display
	index2:
		ldi temp1,  '|'
		jmp turntable_display
	index3:
		ldi temp1, '/'
		jmp turntable_display

	turntable_display:
		lcd_write_data_register temp1
		pop temp1

	ret
;;;;;;;;;;;;;;;;;;;;
; INTERRUPTS

OPEN_DOOR:
	; -- save
	
	push temp1
	push temp2
	push temp3
	push v
	push XL
	push XH
	in temp1, SREG 
	push temp1

	; -- instructions

	ldi temp2, 1
	setVar doorIsOpen, temp2

	call setDoorLEDOpen
	call pauseMotor

	getVar mode, v
	cpi v, 3
	breq runningToPausedSinceDoorOpened
	cpi v, 5
	breq finishedToEntrySinceDoorOpened
	rjmp OPEN_DOOR_end

	runningToPausedSinceDoorOpened:
		ldi v, 4
		setVar mode, v
		rjmp OPEN_DOOR_end

	finishedToEntrySinceDoorOpened:
		ldi v, 1
		setVar mode, v

		ldi v, 0
		setVar playFinishSound, v

		lcd_write_com LCD_DISP_CLR ;clear the display
		lcd_wait_busy ;take yo time buddy
		
		rcall clearTimeAndDigits
		rcall printDigitsToLCD

		rjmp OPEN_DOOR_end

	OPEN_DOOR_end:
		; -- restore
		lcd_write_com LCD_SHIFT_LEFT
		call writeDoorStateToDisplay
		
		pop temp1
		out SREG, temp1
		pop XH
		pop XL
		pop v
		pop temp3
		pop temp2
		pop temp1

		reti ;return from interrupt

CLOSE_DOOR:

	; -- save
	push temp1
	push temp2
	push temp3
	push v
	push XL
	push XH
	in temp1, SREG 
	push temp1

	; -- instructions

	getVar doorIsOpen, v
	cpi v, 0
	brne CLOSE_DOOR_cont
	jmp CLOSE_DOOR_end

	CLOSE_DOOR_cont:

		ldi v, 0
		setVar doorIsOpen, v

		call setDoorLEDClosed

		lcd_write_com LCD_SHIFT_LEFT
		call writeDoorStateToDisplay

		; -- restore
	CLOSE_DOOR_end:
		pop temp1
		out SREG, temp1
		pop XH
		pop XL
		pop v
		pop temp3
		pop temp2
		pop temp1
		reti
;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; if mode == running
; 	if stuff is not running
; 		reset timers
; 		reset magnetrontimer
; 		output pwn to magnetron for 100rev/min
; 		stuff is running
; 	else
; 		count 250ms
; 		counter250++
; 		magnetrontimer++
; 		if powerlevel == 1 (100)
; 			pass
; 		elsif powerlevel == 2 (50)
; 			if magnetrontimer == 2 or 4
; 				updatemagnetron
; 		elsif powerlevel == 3 (25)
; 			if magnetrontimer == 1 or 4
; 				updatemagnetron

; 		if magnetronTimer == 4
; 			reset magnetronTimer to 0

; 		if counter250 == 2
; 			reset counter250
; 			counter500++

; 		if counter500 == 2
; 			IF TIME == 0
; 			 	go to finished mode
; 				display done, remove food - rcall writeFinishedText
; 			reset counter500
; 			counter1000++
; 			UPDATETIME ON LCD

; 		if counter1000 == 5
; 			reset counter1000
; 			get current character index
; 			if CCW
; 				index++
; 			else 
; 				index--
; 			display it
; 			// 5 seconds has passed
; else
;   nothing
;
TIMER: 
	; -- save
	push temp1
	push temp2
	push temp3
	in temp1, SREG  
	push temp1 
	push XH
	push XL
	push v

; if mode == running
; 	..
; else
; 	turn off magnetron, turntable, timers
	
	; jmp TIMER_end
	getVar mode, v
	cpi v, 3
	breq handleRunning_timer
	jmp TIMER_end

	handleRunning_timer:
		getVar functionsRunning, v
		cpi v, 0
		breq startRunning_timer
		cpi v, 1
		breq continueRunning_timer
		jmp TIMER_end

		startRunning_timer:
			; Resets timers
			ldi v, 0
			setVar counter, v
			setVar counter250, v
			setVar counter500, v
			setVar counter1000, v
			setVar counter5000, v
			setVar magnetronCounter, v

			ldi v, 1
			setVar functionsRunning, v
			setVar magnetronRunning, v

			call toggleRotationDirection

			; OUTPUT MOTOR SIGNAL HERE
			call setMotorOn


			jmp TIMER_end


		continueRunning_timer:
			getVar counter, v

			cpi v, 244 ; instead of 244.14
			breq handle250Counter

			inc v
			setVar counter, v

			jmp TIMER_end

			handle250Counter:
				clr v
				setVar counter, v

				getVar magnetronCounter, v
				inc v
				setVar magnetronCounter, v
				call updateMagnetron

				getVar counter250, v
				inc v
				setVar counter250, v

				cpi v, 2
				breq handle500Counter

				jmp TIMER_end

				handle500Counter:
					clr v
					setVar counter250, v

					getVar counter500, v
					inc v
					setVar counter500, v

					cpi v, 2
					breq handle1000Counter

					jmp TIMER_end

					handle1000Counter:
						clr v
						setVar counter500, v

						getVar counter1000, v
						inc v
						setVar counter1000, v

						rcall updateTime

						getVar counter1000, v
						cpi v, 5
						breq handle5000Counter

						jmp TIMER_end

						handle5000Counter:
							clr v
							setVar counter1000, v

							rcall updateIndex

							jmp TIMER_end


	
TIMER_end:

	pop v
	pop XL
	pop XH
	pop temp1
	out SREG, temp1
	pop temp3
	pop temp2
	pop temp1

	reti

;;;;;;;;;;;;;;;;;;;;;;;;;;

; The updateIndex function will, when called, either increment or
; decrement the index variable between the bounds of 0 and 3 inclusive
; according to whether the CCWrotation variable is set or not. The 
; turntable will turn counter-clockwise if the CCWrotation variable is
; set to 1.
updateIndex:
	getVar CCWrotation, v
	cpi v, 1
	breq decrementIndex
	cpi v, 0
	breq incrementIndex
	ret

	decrementIndex:
		getVar index, v
		dec v
		setVar index, v
		jmp checkIndexValue

	incrementIndex:
		getVar index, v
		inc v
		setVar index, v
		jmp checkIndexValue

	checkIndexValue:
		cpi v, 4
		breq setIndexBackToZero
		cpi v, -1
		breq setIndexToThree 
		ret

		setIndexBackToZero:
			clr v
			setVar index, v
			ret

		setIndexToThree:
			ldi v, 3
			setVar index, v
			ret

; The updateTime function will decrement 1 second from the time 
; represented by the mins and secs registers and print this on the
; display.
updateTime:
	cpi secs, 0
	breq minus1Sec_SpecialCase
	dec secs
	jmp updateTime_cont

	minus1Sec_SpecialCase:
		cpi mins, 0
		breq goToFinished
		dec mins
		ldi secs, 59

	updateTime_cont:
		call printTimeToLCD
		ret

	goToFinished:
		call finished

	ret

; The updateMagnetron function, when called, will check which segment
; of the second has been reached, and then therefore will decide whether
; to turn the magnetron on or off. It will then set the magnetron to be
; on or off.
updateMagnetron:
	getVar magnetronRunning, v
	out PORTC, v

	getVar power, v

	cpi v, 100
	breq updateMagnetron_end
	cpi v, 50
	breq updateMagnetron_checkTimeIsUp_50
	cpi v, 25
	breq updateMagnetron_checkTimeIsUp_25
	ret

	updateMagnetron_end:
		ret

	updateMagnetron_checkTimeIsUp_50:
		getVar magnetronCounter, v
		cpi v, 2
		breq updateMagnetron_toggle
		cpi v, 4
		breq updateMagnetron_toggleAndResetCounter
		ret

	updateMagnetron_checkTimeIsUp_25:
		getVar magnetronCounter, v
		cpi v, 1
		breq updateMagnetron_toggle
		cpi v, 4
		breq updateMagnetron_toggleAndResetCounter
		ret

		updateMagnetron_toggleAndResetCounter:
			clr v
			setVar magnetronCounter, v
			jmp updateMagnetron_toggle

		updateMagnetron_toggle:
			getVar magnetronRunning, v
			cpi v, 0
			breq updateMagnetron_toggleOn
			cpi v, 1
			breq updateMagnetron_toggleOff
			ret

			updateMagnetron_toggleOn:
				call setMotorOn
				ret
			updateMagnetron_toggleOff:
				call setMotorOff
				ret

;;;;;;;;;;;;;;;;;;;;;;;;;;

; Timer 2
; if playFinishSound == 1
; 	if on
; 		out 0, 1
; 	if off
; 		out 0
; 	if 1 sec has passed
; 		clear counter
; 		inc number of seconds passed
; 		toggle on/off 

TIMER2:

	push temp1
	push temp2
	push temp3
	in temp1, SREG  
	push temp1 
	push XH
	push XL
	push v

	getVar playFinishSound, v
	cpi v, 1 ; If it should be playing
	breq play3Beeps

	jmp TIMER2_continueHandling

	play3Beeps:

		getVar nFinishSounds, v
		cpi v, 6
		breq TIMER2_continueHandling

		ldi v, 0
		out PORTB, v

		getVar finishSoundIsOn, v
		cpi v, 1
		breq playOn
		jmp play3Beeps_cont

			playOn:
				delay 1000
				ldi v, 0xFF
				out PORTB, v
				jmp play3Beeps_cont

		play3Beeps_cont:
			getVar finishSoundCounter, v
			inc v
			setVar finishSoundCounter, v
			cpi v, 255
			breq play3Beeps_secHasPassed
			jmp TIMER2_continueHandling

			play3Beeps_secHasPassed:
				clr v
				setVar finishSoundCounter, v

				getVar nFinishSounds, v
				inc v
				setVar nFinishSounds, v

				getVar finishSoundIsOn, v
				ldi temp1, 1
				EOR v, temp1
				setVar finishSoundIsOn, v

				jmp TIMER2_continueHandling

 ; if keyPressed == 1
 ; 	play sound
 ; 		when 250ms is up
 ; 			keyPressed = 0

	TIMER2_continueHandling:
		getVar keyPressed, v
		cpi v, 1
		breq beepOnceSinceKeyPressed

		jmp TIMER2_END

		beepOnceSinceKeyPressed:
			ldi v, 0
			out PORTB, v
	
			delay 1000
	
			ldi v, 0xFF
			out PORTB, v

			getVar beepCounter, v
			inc v
			setVar beepCounter, v
			cpi v, 90
			breq beepOnce_250msHasPassed
		
			jmp TIMER2_END

			beepOnce_250msHasPassed:
				clr v
				setVar beepCounter, v

				clr v
				setVar keyPressed, v

				jmp TIMER2_END

TIMER2_END:

	pop v
	pop XL
	pop XH
	pop temp1
	out SREG, temp1
	pop temp3
	pop temp2
	pop temp1

	reti

;;;;;;;;;;;;;;;;;;;;;;;;

; The writePowerLabels function will display “Set Power 1/2/3”
; as well as the turntable, group number and door state.
writePowerLabels:
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

	call turntable

	call writeSecondLineToDisplay
	
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; The display_numbers macro in actuality calls a checkTensDigit
; function which splits the current time held in the mins and secs
; registers into digits to be displayed on the screen.
.macro display_numbers 
	push temp1
	push temp2
	
	mov temp1, @0
	clr temp2

	rcall checkTensDigit

	pop temp2
	pop temp1
.endmacro


;; temp1 -- current number to be displayed / parsed
;; temp2 -- the number of <hundreds/tens/ones> found in temp1
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

incTens: ; increment number of tens
	subi temp1, 10
	inc temp2
	rjmp checkTensDigit

; pop stored digits off stack
popDigits: 

	clr temp1
	clr temp2

	pop temp2 ; ones
	pop temp1 ; tens

; display tens and ones
	lcd_write_digit temp1 ; tens
	lcd_write_digit temp2 ; ones

cleanup:
	clr temp1
	clr temp2
	ret

;;;;;;;;;;;;;;
; The printTimeToLCD function will, in running mode, display
; the correct tim e, turntable, group number and door state.
printTimeToLCD:
	lcd_write_com LCD_DISP_CLR ; clear the display
	lcd_wait_busy ; take yo time buddy

	display_numbers mins
	lcd_write_data_direct ':'
	display_numbers secs
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '

	call turntable

	call writeSecondLineToDisplay

	ret

;;;;;;;;;;;;;;;;;;;;

; The writeFinishedText function will display “Done\nRemove Food”
; on the display.
writeFinishedText:
	lcd_write_com LCD_DISP_CLR ;clear the display
	lcd_wait_busy ;take yo time buddy
	
	lcd_write_data_direct 'D'
	lcd_write_data_direct 'o'
	lcd_write_data_direct 'n'
	lcd_write_data_direct 'e'
	lcd_write_com LCD_NEW_LINE
	lcd_write_data_direct 'R'
	lcd_write_data_direct 'e'
	lcd_write_data_direct 'm'
	lcd_write_data_direct 'o'
	lcd_write_data_direct 'v'
	lcd_write_data_direct 'e'
	lcd_write_data_direct ' '
	lcd_write_data_direct 'F'
	lcd_write_data_direct 'o'
	lcd_write_data_direct 'o'
	lcd_write_data_direct 'd'

	reti

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; The writeSecondLineToDisplay function will display the group
; number and door state to the display. This is used in the
; other functions that require writing the group number and 
; door state.
writeSecondLineToDisplay:
	
	lcd_write_com LCD_NEW_LINE

	lcd_write_data_direct 'E'
	lcd_write_data_direct '1'
	lcd_write_data_direct '0'

	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '
	lcd_write_data_direct ' '

	rcall writeDoorStateToDisplay

	ret
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; The writeDoorStateToDisplay will write either a “C” or “O”
; depending on whether the door is open or not, effective immediately.
writeDoorStateToDisplay:
	getVar doorIsOpen, v
	cpi v, 0
	breq writeC_train
	cpi v, 1
	breq writeO_train
	ret

	writeC_train:
		jmp writeC

	writeO_train:
		jmp writeO
	
			writeC:
				lcd_write_data_direct 'C'
				ret

			writeO:
				lcd_write_data_direct 'O'
				ret
;;;;;;;;;;;;;;;;;;
; The toggleRotationDirection will toggle the value of CCWrotation 
; by using an exclusive OR.
toggleRotationDirection:
	getVar CCWrotation, v
	ldi temp1, 1
	EOR v, temp1
	setVar CCWrotation, v
	ret
	
;;;;;;;;;;;;;;;;;;;;;
; The setDoorLEDClosed and setDoorLEDOpen functions will cause
; the top LED to be on or off.
setDoorLEDClosed:
	ldi v, 0
	out PORTG, v
	ret

setDoorLEDOpen:
	ldi v, 2
	out PORTG, v
	ret
	

;;;;;;;;;;;;;;;;;;
; The setMotorOn, setMotorOff, resumeMotor and pauseMotor functions 
; will turn the motor on or off. The difference between the first
; two and last two are how they handle the behavior of the motor when it
; is turned on again. When the motor is set to off using setMotorOff,
; it will begin again from the start of its cycles rather than where it
; left off when it was paused, which can be achieved by using pauseMotor.
setMotorOn:
	ldi v, MOTORON
	sts PORTH, v

	ldi v, 1
	setVar magnetronRunning, v
	ret
setMotorOff:
	ldi v, MOTOROFF
	sts PORTH, v

	clr v
	setVar magnetronRunning, v
	ret

resumeMotor:
	getVar magnetronRunning, v
	cpi v, 0
	breq setMotorOff
	cpi v, 1
	breq setMotorOn
	ret

pauseMotor:
	ldi v, MOTOROFF
	sts PORTH, v
	ret

;;;;;;;;;;;;;;;;
; The finished function will set the mode to finished,
; reset all counters, and turn off the magnetron and turntable.
finished:
	; Set mode
	ldi v, 5
	setVar mode, v

	; Resets timers
	ldi v, 0
	setVar counter, v
	setVar counter250, v
	setVar counter500, v
	setVar counter1000, v
	setVar counter5000, v
	setVar magnetronCounter, v

	call setMotorOff

	; Set to not running
	ldi v, 0
	setVar functionsRunning, v
	setVar magnetronRunning, v

	call writeFinishedText

	; set finish sound on
	ldi v, 1
	setVar playFinishSound, v

	ldi v, 0
	setVar finishSoundCounter, v
	setVar nFinishSounds, v
	setVar finishSoundIsOn, v

	ret
