.model small
.8086
.stack 1024
.data

	INT0	EQU	0*4   ; four bytes taken by CS:IP
		
		
     	TABLE	DB	00000001b
		
;8255-1
	porta equ 00h
	portb equ 02h
	portc equ 04h
	creg equ 06h

;8255-2
	port2a equ 08h
	port2b equ 0ah
	port2c equ 0ch
	creg2 equ 0eh

;8253 - 10h

	clk0 equ 10h
	clk1 equ 12h
	clk2 equ 14h
	creg3 equ 16h

;8259 - 18h

	p1 equ 18h
	p2 equ 1ah

	DAT1 db 00h
	DAT2 db 00h

.code
.startup
				cli  												;------------disable the interrupt

		; set data segment       
		mov ax, @data
		mov ds, ax
	
		; set the ISRs address table
		mov ax, 0
      		mov es, ax				; SMALL mode used put CS:IP in IVT starting at 00000
		mov bx, cs
		mov ax, ac_isr				; find the offset of the ISR procedure
		
		mov es:[INT0], ax			; enter the ip value of ISR in IVT 
      		mov es:[INT0+2], bx     		; enter the cs value of iSR
		

;--------------------------------------------------Initializing 8255(1) and 8255(2)-----------------;

		;c lower is for buttons (8255-1)
		;c3-load
		;c2-resume
		;c1-stop
		;c0-start
	
		;c upper is for buzzers(8255-2)
		;c4-rinse
		;c5-wash
		;c6-dry

 

START:

		mov al,10001011b
		out creg,al
	
		mov al,10000010b
		out creg2,al	

		mov al,00001000b	  ;setting PC4=0, upper sensor
		out creg,al

		mov al,00001010b   ;setting PC5=1, lower sensor
		out creg,al

		mov al,00001100b   ;setting PC6=0, gate of 8253
		out creg,al

		mov al,00001110b   ;setting PC7=0, for disabling DC motor to rotate tub and agitator
		out creg,al	



;-----------------------------------------------Initialize 8259--------------;

		; ICW1 (edge triggered, single 8259a, 80x86 cpu)
		mov al, 00010111b		;       D5,6,7->dont care ,1->always 1,0->edge triggered,1->interval of 4,1->single CPU,1->IC4- needed
		out p1, al		

		; ICW2 (base interrupt number 0x00)
		mov al, 00000000b		;	tells  8259, the IVT to be sent to CPU in response to an interrupt signal on the IR input,lowest 3 bits always 0
		out p2, al
		
		; ICW4 (not special fully nested, non-buffered, auto EOI, 80x86 cpu)
		mov al, 00000101b		;	
		out p2, al
		
		; OCW1 (unmask all interrupt bits)
		mov al, 00h
		out p2, al


;------------------------------------------------ input from user------------;
;-----------------------------------------------check if start is pressed-----;
       
		mov bx,0

;----------------------------------Assumption: the user presses load button only between one and three times-------------------;


	LOAD:		in al,portc
			and al,00001000b  
			cmp al,00000000b
			jnz LOAD
	
			; De bounce key press
			CALL DEBOUNCE
	
			in al,portc
			and al,00001000b 
			cmp al,00000000b
			jnz LOAD
	
			inc bx 	;still pressed	 ;-----------to store the count of presses----------;
	
			in al,portc
			and al,00000001b 
			cmp al,00000000b
			jnz LOAD     		;------------start not pressed , check for load presses again----;	

			CALL DEBOUNCE
	
			in al,portc
			and al,00000001b 
			cmp al,00000000b
			jnz LOAD
			
			cmp bx,1                 ;----------check which label to go, whether light,medium or heavy--------;
			jz LIGHT
	
			cmp bx,2
			jz MEDIUM

			cmp bx,3
			jz HEAVY

			cmp bx,0
			jz LOAD



;-------------------------------------DAT1 and DAT2 store the count for the second counter of 8253 depending on the cycle--------;
;-----------------first counter generates a pulse of 1khz by taking a count of 2500d and this is the cascaded to second counter-----MODE -3 is used-----------;

		LIGHT:	MOV DAT1,10h
			MOV DAT2,27h

			CALL RINSE
	
			MOV DAT1,98h
			MOV DAT2,3Ah
			CALL WASH

			MOV DAT1,10h
			MOV DAT2,27h
			CALL RINSE

			MOV DAT1,10h
			MOV DAT2,27h
			CALL DRY

			jmp START                         ;----------for taking new load-----------;

		MEDIUM:	MOV DAT1,98h
			MOV DAT2,3Ah
			CALL RINSE

			MOV DAT1,0A8h
			MOV DAT2,61h
			CALL WASH

			MOV DAT1,98h
			MOV DAT2,3Ah
			CALL RINSE

			MOV DAT1,20h
			MOV DAT2,4Eh
			CALL DRY
	
			jmp START
	

		HEAVY:  MOV DAT1,98h
			MOV DAT2,3Ah
			CALL RINSE

			MOV DAT1,0A8h
			MOV DAT2,61h
			CALL WASH

			MOV DAT1,98h
			MOV DAT2,3Ah
			CALL RINSE

			MOV DAT1,0A8h
			MOV DAT2,61h
			CALL WASH

			MOV DAT1,98h
			MOV DAT2,3Ah
			CALL RINSE

			MOV DAT1,20h
			MOV DAT2,4Eh
			CALL DRY
	
			jmp START

;-------------------ISR---------------------------------;

ac_isr proc far  ; ISR procedure for INT-0/use 0 to 7 in proteus;
		;  OCW3 (no action, no polling, read ISR next read)        
	    	mov al, 00001011b  ; control word to read ISR
		out 10h, al 
		
		
		; Read ISR register to check for pending interrupts
		in al, 10h 
		
		; Find the index of the pending interrupt
		mov si, 0
		mov ah, 1
		mov cx, 8

search:		test al, ah  ; bitwise AND 
		jnz done ; if ISR is set go to done
		inc si
		shl ah, 1
		loop search

done:		; OCW2 (non-specific EOI command) for resetting ISR 
		mov al, 00100000b
		out 10h, al

		; code for switching off all the LED's to indicate end of a particular cycle
		mov al,00000000b
		out creg2,al

		mov al,00000010b
		out creg2,al

		mov al,00000100b
		out creg2,al

		mov al,00000110b
		out creg2,al		
		
		mov al,00001100b   ;-------------------setting PC6=0, gate of 8253, to disable 8253 so that it doesn't generate further interrupts
		out creg,al

		iret
ac_isr endp

.exit	

;-------------------------------------------RINSE PROCEDURE--------------------------;

RINSE PROC NEAR

			call run_motor2	;step angle of 45 degree to open valve

		FILL:	in al,portc	;water level sensor
			and al,10H
			cmp al,10H
			jnz FILL	

		;step angle of 45 degree to open valve close valve
	
			call stop_motor2	
	
			mov al,00110110b	;mode 3 for counter 0,1
			out creg3,al

			mov al,01110110b
			out creg3,al

			mov al,0c4h	;counter 1 initialize for load-10s
			out clk0,al

			mov al,09h
			out clk0,al	;1ms pulse
	
			mov al,DAT1	;counter 2 initialize for load-10s
			out clk1,al

			mov al,DAT2
			out clk1,al	;10s pulse 		

			mov al,00001101b	; gating signal ON
			out creg,al

			mov al,00000001b ;LED=ON for rinse	
			out creg2,al		

			mov al,00000111b ;LED=ON for door closed 	
			out creg2,al
	
			call run_motor1	;DC motor On for rinse

			sti

		LOC:	in al,port2c
			and al,0F
			cmp al,0
			jz RINSE_END		

			in al,portc		;check for stop
			and al,00000010b 
			cmp al,00000000b
			jnz LOC 

			; De bounce key press
			CALL DEBOUNCE	

			in al,portc
			and al,00000010b 
			cmp al,00000000b
			jz STOPR

			jmp LOC
			
		STOPR:  mov al,00001100b
			out creg,al		;gating signal OFF
	
			in al,portc
			and al,00000100b 
			cmp al,00000000b	;resume
			jnz STOPR 		

			; De bounce key press
			CALL DEBOUNCE
	
			in al,portc
			and al,00000100b 
			cmp al,00000000b	;resume
			jnz STOPR 

			mov al,00001101b	; gating signal ON, count resumes
			out creg,al

			jmp LOC

		RINSE_END:
			call stop_motor1	;  DC motor off		
	
			call rinseBuzzer

			call run_motor2	;  valve open to drain water 

		DRAIN:	in al,portc		;water level sensor
			and al,20H
			cmp al,20H
			jnz DRAIN

			call stop_motor2	
	
			RET
			RINSE ENDP

;-------------------------------------------------WASH PROCEDURE-------------------------;

WASH PROC NEAR

			call run_motor2	;step angle of 45 degree to open valve

		FILLW:	in al,portc	;water level sensor
			and al,10H
			cmp al,00H
			jnz FILLW	

		;step angle of 90 degree to open valve close valve
	
			call stop_motor2	
	
			mov al,00110110b	;mode 3 for counter 0,1
			out creg3,al

			mov al,01110110b
			out creg3,al

			mov al,0c4h	;counter 1 initialize for load-10s
			out clk0,al

			mov al,09h
			out clk0,al	;1ms pulse
	
			mov al,DAT1	;counter 2 initialize for load-10s
			out clk1,al

			mov al,DAT2
			out clk1,al	;10s pulse 		

			mov al,00001101b	; gating signal ON
			out creg,al

			mov al,00000011b ;LED=ON for wash	
			out creg2,al		

			mov al,00000111b ;LED=ON for door closed 	
			out creg2,al
	
			call run_motor1	;DC motor On for wash

		LOCW:	in al,portc
			and al,0
			cmp al,0
			jz WASH_END		

			in al,portc		;check for stop
			and al,00000010b 
			cmp al,00000000b
			jnz LOCW 

			; De bounce key press
			CALL DEBOUNCE	

			in al,portc
			and al,00000010b 
			cmp al,00000000b
			jz STOPRW

			jmp LOCW
			
		STOPRW: mov al,00001100b
			out creg,al		;gating signal OFF
	
			in al,portc
			and al,00000100b 
			cmp al,00000000b	;resume
			jnz STOPRW 		

			; De bounce key press
			CALL DEBOUNCE
	
			in al,portc
			and al,00000100b 
			cmp al,00000000b	;resume
			jnz STOPRW 

			mov al,00001101b	; gating signal ON, count resumes
			out creg,al

			jmp LOCW

		WASH_END:
			call stop_motor1	;  DC motor off		
	
			call washBuzzer

			call run_motor2	;  valve open to drain water 

		DRAINW:	in al,portc		;water level sensor
			and al,20H
			cmp al,20H
			jnz DRAINW

			call stop_motor2	
	
			RET
			WASH ENDP


;--------------------------------------------DRY PROCEDURE-----------------------------;

DRY PROC NEAR		
	
			mov al,00110110b	;mode 3 for counter 0,1
			out creg3,al

			mov al,01110110b
			out creg3,al

			mov al,0c4h	;counter 1 initialize for load-10s
			out clk0,al
		
			mov al,09h
			out clk0,al	;1ms pulse
	
			mov al,DAT1	;counter 2 initialize for load-10s
			out clk1,al

			mov al,DAT2
			out clk1,al	;10s pulse 		

			mov al,00001101b	; gating signal ON
			out creg,al

			mov al,00000101b ;LED=ON for dry	
			out creg2,al		

			mov al,00000111b ;LED=ON for door closed 	
			out creg2,al
	
			call run_motor1	;DC motor On for dry

		LOCD:	in al,portc
			and al,0
			cmp al,0
			jz DRY_END		

			in al,portc		;check for stop
			and al,00000010b 
			cmp al,00000010b
			jnz LOCD 

			; De bounce key press
			CALL DEBOUNCE	

			in al,portc
			and al,00000010b 
			cmp al,00000000b
			jz STOPRD

			jmp LOCD
			
		STOPRD: mov al,00001100b
			out creg,al		;gating signal OFF
	
			in al,portc
			and al,00000100b 
			cmp al,00000000b	;resume
			jnz STOPRD 		

			; De bounce key press
			CALL DEBOUNCE
	
			in al,portc
			and al,00000100b 
			cmp al,00000000b	;resume
			jnz STOPRD 

			mov al,00001101b	; gating signal ON, count resumes
			out creg,al

			jmp LOCD
			
	
		DRY_END:
			call stop_motor1	;  DC motor off		
	
			call dryBuzzer

	
	RET
	DRY ENDP



;------------------------------------MOTOR1----------------------------------------------

run_motor1 proc near

	mov al,00001111b
	out creg,al

ret
run_motor1 endp


;------------------------------;

stop_motor1 proc near

	mov al,00001110b
	out creg,al

ret
stop_motor1 endp

;-----------------------------------MOTOR 2----------------------------------------------

run_motor2 proc near

	mov al,00001111b
	out creg2,al

ret
run_motor2 endp

;-----------------------------;

stop_motor2 proc near

	mov al,00001110b
	out creg2,al

ret
stop_motor2 endp

;-----------------------------------------------------------------------------------------

debounce proc near

MOV CX, 4E20H	; delay of 20ms
DELAY:	LOOP DELAY

ret
debounce endp

;-------------------------------------RinseBuzzer-----------------------------------------

rinseBuzzer proc near

	mov al,00001001b		;buzzer-rinse ON to signify RINSE end 
	out creg2,al	

	mov bx,200

	;De bounce key press
x1R:	MOV CX, 4E20H	; delay of 20ms
	DELAYR:	LOOP DELAYR

	dec bx
	cmp bx,00h
	jnz x1R

	mov al,00001000b ;buzzer off	
	out creg2,al

ret
rinseBuzzer endp
;------------------------------------------------------------------------------------------

;-------------------------------------WashBuzzer-----------------------------------------

washBuzzer proc near

	mov al,00001011b		;buzzer-rinse ON to signify WASH end 
	out creg2,al	

	mov bx,200

	;De bounce key press
x1w:	MOV CX, 4E20H	; delay of 20ms
	DELAYW:	LOOP DELAYW

	dec bx
	cmp bx,00h
	jnz x1w

	mov al,00001010b ;buzzer off	
	out creg2,al

ret
washBuzzer endp
;------------------------------------------------------------------------------------------

;-------------------------------------DryBuzzer-----------------------------------------

dryBuzzer proc near

	mov al,00001101b		;buzzer-rinse ON to signify dry end 
	out creg2,al	

	mov bx,200

	;De bounce key press
x1d:	MOV CX, 4E20H	; delay of 20ms
	DELAYD:	LOOP DELAYD

	dec bx
	cmp bx,00h
	jnz x1d

	mov al,00001100b ;buzzer off	
	out creg2,al

ret
dryBuzzer endp
;------------------------------------------------------------------------------------------


end