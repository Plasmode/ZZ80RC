; 6/9/18 Change ZZMon start address to 0xB400
; 3/9/18
; This program is prepended to ZZMon and loaded via serial port
;   It will autoexecute and start up ZZMon program
; 2/8/18 version 1, clear all memory to zero
; 1/24/18 file load program fit in 256 bytes
; File is intel HEX format
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; LoadnGo, Copyright (C) 2018 Hui-chien Shen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
UARTconf 	equ 10h		; UART configuration register
RxData  	equ 16h        	; on-chip UART receive register
TxData  	equ 18h        	; on-chip UART transmit register
RxStat  	equ 14h        	; on-chip UART transmitter status/control register
TxStat  	equ 12h        	; 0n-chip UART receiver status/control register
Refresh 	equ 0E8h		; refresh register


	org 0
; initialize I/O page to 0xFE so IN and OUT instruction using internal UART
          LD SP,0FFFFH  ; initialize stack pointer to top of memory
          LD C,08H		; C points to I/O page address
   	LD L,0FEH		; write 0xFE to I/O page
	db 0EDh, 6Eh	; this is the op code for LDCTL (C),HL
;			 LDCTL (C),HL  ; write to I/O page
; UART is already configured with UART bootstrap, but if this routine is used for normal boot, then
;  UART needs to be configured
	LD A,0E2h		; configure the UART
	OUT (UARTconf),A ;
          LD A,80h         ; enable UART transmit
	OUT (TxStat),A		; enable UART transmit
	OUT (RxStat),A		; enable UART receive
;x	xor a			; clear reg A
;x	ld hl,0ffffh		; clear memory, starting from the top
;xclrmem:
;x	ld (hl),a			; clear memory
;x	dec hl
;x	cp h			; reaching 100h?
;x	jp nz,clrmem
;x	ld HL,SignOn$		; Sign on message
;x	call STROUT
main:
	call CINQ
	cp ':'			; intel load file starts with :
	jp z,fileload
	cp 'G'			; execute 
	jp nz,main
	call COUT		; echo back 'G'
	ld a,' '		; put out a space
	call COUT
	call GETHEX	; get starting address
	ld h,a
	call GETHEX
	ld l,a
	jp (hl)
fileload:
;	call COUT		; echo back valid input character 
	call GETHEX	; get two ASCII char (byte count) into hex byte in reg A
	ld d,a			; save byte count to reg D
	ld b,a			; initialize the checksum
	call GETHEX	; get MSB of address
	ld h,a			; HL points to memory to be loaded
	add a,b			; accumulating checksum
	ld b,a			; checksum is kept in reg B
	call GETHEX	; get LSB of address
	ld l,a
	add a,b			; accumulating checksum
	ld b,a			; checksum is kept in reg B
	call GETHEX	; get the record type, 0 is data, 1 is end
	cp 0
	jp z,filesave
	cp 1				; end of file transfer?
	jp nz,unknown	; if not, print a 'U'
; end of the file load
	call GETHEX	; flush the line, get the last byte
	ld a,'X'		; mark the end with 'X'
	call COUT
	ld a,10			; carriage return and line feed
	call COUT
	ld a,13
	call COUT
;	jp main
	jp 0b400h		; starting point of ZZMon

; the assumption is the data is good and will be saved to the destination memory
filesave:
	add a,b			; accumulating checksum of record type
	ld b,a			; checksum is kept in reg B
filesav1:
	call GETHEX	; get a byte
	ld (hl),a		; save to destination
	add a,b			; accumulating checksum
	ld b,a			; checksum is kept in reg B
	inc hl
	dec d
	jp nz,filesav1
	call GETHEX	; get the checksum
	neg a			; 2's complement
	cp b				; compare to checksum accumulated in reg B
	jp nz,badload	; checksum not match, put '?'
	ld a,'.'		; checksum match, put '.'
filesav2:
	call COUT
	jp main			; repeat until record end
badload:
	ld a,'?'		; checksum not match, put '?'
	jp filesav2
unknown:
	ld a,'U'		; put out a 'U' and wait for next record
	call COUT
	jp main





;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;GETHEX -- Get byte from console as hex
;
;pre: none
;post: A register contains byte from hex input
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
GETHEX:
	push de		; save register 
        	CALL CINQ
        	CALL ASCHEX
        	RLCA
        	RLCA
        	RLCA
        	RLCA
        	LD D,A
        	CALL CINQ
        	CALL ASCHEX
        	OR D 
  	pop de			;restore register
        	RET
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;ASCHEX -- Convert ASCII coded hex to nybble
;
;pre: A register contains ASCII coded nybble
;post: A register contains nybble
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ASCHEX: 	SUB 30h
        	CP 0Ah
        	RET M
        	AND 5Fh
        	SUB 07h
        	RET
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;STROUT -- Print a null-terminated string
;
;pre: HL contains pointer to start of a null-
;     terminated string
;post: string at HL printed to console
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
STROUT: 	LD A,(HL)
        	CP 00
        	RET Z
        	CALL COUT
        	INC HL
        	JP STROUT

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;CINQ -- Get a char from the console and no echo
;
;pre: console device is initialized
;post: received char is in A register
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CINQ:    
        	IN A,(RxStat)		; read on-chip UART receive status
        	AND 10H				; data available?
        	JP Z,CINQ
        	IN A,(RxData)		; save to reg A
        	RET
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;COUT -- Output a character to the console
;
;pre: A register contains char to be printed
;post: character is printed to the console
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
COUT:   
	EX AF,AF'				; save data to be printed to alternate bank
COUT1:  	IN A,(TxStat)		; transmit empty?
        	AND 01H
        	JP Z,COUT1
	EX AF,AF'				; restore data to be printed
        	OUT (TxData),A		; write it out
        	RET

SignOn$: 	db 0ah,0dh,"TinyLoad 1",0ah,0dh
	db "G xxxx when done",0ah,0dh,0

	db 0,0,0,0,0,0,0,0,0,0,0,0,0	; pad to exactly 256 byte
	db 0,0,0,0,0,0,0,0,0,0,0,0,0	; pad to exactly 256 byte
	db 0,0,0,0,0,0,0,0,0,0,0,0,0	; pad to exactly 256 byte



