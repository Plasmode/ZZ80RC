; 8/20/18 v0.26 disable refresh register
;  L ist memory in Intel Hex format
;  I in from port # in I/O page 0
;  O out to port # in I/O page 0
;  Display the ASCII characters along with HEX value
;  show the correct memory address with 'R' command
; 8/11/18 fork from ZZMon v0.99
;  bootstrap monitor for ZZ80RC
;  Resides in physical page 0 (0x0-0xFFF)
;  Immediately after power up, it will make a copy of itself into 0xB400 and jump to it
;  It will enable MMU, write protect physical page 0 and map physical page 0x3C000 to logical page 0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; ZZMon, Copyright (C) 2018 Hui-chien Shen
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
UARTconf 	equ 10h		; UART configuration register
RxData  	equ 16h        	; on-chip UART receive register
TxData  	equ 18h        	; on-chip UART transmit register
RxStat  	equ 14h        	; on-chip UART transmitter status/control register
TxStat  	equ 12h        	; 0n-chip UART receiver status/control register

;CFdata   	equ 0C0h    	;CF data register
;CFerr    	equ 0C2h    	;CF error reg
;CFsectcnt equ 0C5h    	;CF sector count reg
;CF07     	equ 0C7h   	;CF LA0-7
;CF815    	equ 0C9h       	;CF LA8-15
;CF1623   	equ 0CBh       	;CF LA16-23
;CF2427   	equ 0CDh       	;CF LA24-27
;CFstat   	equ 0CFh       	;CF status/command reg

MMUctrl	equ 0f0h		; MMU master control reg
MMUptr	equ 0f1h		; MMU page descriptor reg pointer
MMUsel	equ 0f5h		; MMU descriptor select port
MMUmove	equ 0f4h		; MMU block move port
MMUinv	equ 0f2h		; MMU invalidation port
DMActrl	equ 01fh		; DMA master control reg
DMA2dstL	equ 10h		; DMA chan 2 destination reg low
DMA2dstH	equ 11h		; DMA chan 2 destination reg high
DMA2srcL	equ 12h		; DMA chan 2 source reg low
DMA2srcH	equ 13h		; DMA chan 2 source reg high
DMA2cnt	equ 14h		; DMA chan 2 count reg
DMA2td	equ 15h		; DMA chan 2 transaction descriptor
DMA3dstL	equ 18h		; DMA chan 3 destination reg low
DMA3dstH	equ 19h		; DMA chan 3 destination reg high
DMA3srcL	equ 1ah		; DMA chan 3 source reg low
DMA3srcH	equ 1bh		; DMA chan 3 source reg high
DMA3cnt	equ 1ch		; DMA chan 3 count reg
DMA3td	equ 1dh		; DMA chan 3 transaction descriptor

	ORG 0b000h
	ld hl,400h	; ZZ80Mon is stored in 0x400 to 0xFFF
	ld de,0b400h	; destination where ZZ80Mon will run
	ld bc,0c00h	; copy 3K of program
	ldir
	jp 0b400h		; jump into ZZ80Mon

	ORG 0b400H
; This part of the program will be relocated to 0x400 post process		
	jr start
; variable area
testseed: ds 2		; RAM test seed value
addr3116	ds 2		; high address for Intel Hex format 4
RDsector	ds 1		; current RAM disk sector
RDtrack	ds 1		; current RAM disk track 
RDaddr	ds 2		; current RAM disk address 
;Initialization and sign-on message
start:
	ld sp,0bfffh	; initialize stack 

	ld c,08h		; reg c points to I/O page register
	ld l,0ffh		; set I/O page register to 0xFF
	db 0edh,6eh	; this is the op code for LDCTL (C),HL
;	ldctl (c),hl	; write to I/O page register
;;	ld a,0b0h		; initialize the refresh register to 48 counts, 16uS
	ld a,30h		; disable refresh
	out (0e8h),a	; disable refresh
	call MMUPage	; init MMU
	call initMMU
	call UARTPage	; initialize page i/o reg to UART
	ld a,0e2h		; initialize the UART configuration register
	out (UARTconf),a
	ld a,80h		;enable UART transmit and receive
	out (TxStat),a
	out (RxStat),a
    	LD HL,signon$
        	CALL STROUT
	ld hl,251		; initialize RAM test seed value
	ld (testseed),hl	; save it
clrRx:  
        	IN A,(RxStat)	; read on-chip UART receive status
        	AND 10H				; data available?
        	jp z,CMD
        	IN A,(RxData)	; read clear the input buffer
	jr clrRx
;Main command loop
CMD:  	LD HL, PROMPT$
        	CALL STROUT
CMDLP1:
        	CALL CINQ
	cp ':'		; Is this Intel load file?
	jp z,initload
	cp 0ah		; ignore line feed
	jp z,CMDLP1
	cp 0dh		; carriage return get a new prompt
	jp z,CMD
	CALL COUT		; echo character
        	AND 5Fh
	cp 'H'		; help command
	jp z,HELP
        	CP A,'D'
        	JP Z,MEMDMP
        	CP A,'E'
        	JP Z,EDMEM
	cp a,'I'		; read data from specified I/O port in page 0
	jp z,INPORT
	cp a,'O'		; write data to specified I/O port in page 0
	jp z,OUTPORT
	cp a,'L'		; list memory as Intel Hex format
	jp z,LISTHEX
        	CP A,'G'
        	JP Z,go
	cp a,'R'		; read a CF sector
	jp z,READRD
	cp a,'Z'		; fill memory with zeros
	jp z,fillZ
	cp a,'F'		; fill memory with ff
	jp z,fillF
	cp a,'C'		; Copy to CF	
	jp z,COPYCF
	cp a,'T'		; testing RAM 
	jp z,TESTRAM
	cp 'B'		; boot CPM
	jp z,BootCPM
	cp 'X'		; clear RAMdisk directory at 0x80000
	jp z,format
what:
        	LD HL, what$
        	CALL STROUT
        	JP CMD
abort:
	ld hl,abort$	; print command not executed
	call STROUT
	jp CMD
; initialize for file load operation
initload:
	ld hl,0		; clear the high address in preparation for file load
	ld (addr3116),hl	; addr3116 modified with Intel Hex format 4 
; load Intel file
fileload:
	call GETHEXQ	; get two ASCII char (byte count) into hex byte in reg A
	ld d,a		; save byte count to reg D
	ld c,a		; save copy of byte count to reg C
	ld b,a		; initialize the checksum
	call GETHEXQ	; get MSB of address
	ld h,a		; HL points to memory to be loaded
	add a,b		; accumulating checksum
	ld b,a		; checksum is kept in reg B
	call GETHEXQ	; get LSB of address
	ld l,a
	add a,b		; accumulating checksum
	ld b,a		; checksum is kept in reg B
	call GETHEXQ	; get the record type, 0 is data, 1 is end
	cp 0
	jp z,filesave
	cp 1		; end of file transfer?
	jp z,fileend
	cp 4		; Extended linear address?
	jp nz,unknown	; if not, print a 'U'
; Extended linear address for greater than 64K
; this is where addr3116 is modified
	add a,b		; accumulating checksum of record type
	ld b,a		; checksum is kept in reg B
	ld a,d		; byte count should always be 2
	cp 2
	jp nz,unknown
	call GETHEXQ	; get first byte (MSB) of high address
	ld (addr3116+1),a	; save to addr3116+1
	add a,b		; accumulating checksum
	ld b,a		; checksum is kept in reg B
; Little Endian format.  MSB in addr3116+1, LSB in addr3116
	call GETHEXQ	; get the 2nd byte (LSB) of of high address
	ld (addr3116),a	; save to addr3116
	add a,b		; accumulating checksum
	ld b,a		; checksum is kept in reg B
	call GETHEXQ	; get the checksum
	neg a		; 2's complement
	cp b		; compare to checksum accumulated in reg B
	jp nz,badload	; checksum not match, put '?'
	ld a,'E'		; denote a successful Extended linear addr update
	jp filesav2
; end of the file load
fileend:
	call GETHEXQ	; flush the line, get the last byte
	ld a,'X'		; mark the end with 'X'
	call COUT
	ld a,10			; carriage return and line feed
	call COUT
	ld a,13
	call COUT
	jp CMD
; the assumption is the data is good and will be saved to the destination memory
filesave:
	add a,b		; accumulating checksum of record type
	ld b,a		; checksum is kept in reg B
	ld ix,0c000h	; 0c000h is buffer for incoming data
filesavx:
	call GETHEXQ	; get a byte
	ld (ix),a		; save to buffer
	add a,b		; accumulating checksum
	ld b,a		; checksum is kept in reg B
	inc ix
	dec d
	jp nz,filesavx
	call GETHEXQ	; get the checksum
	neg a		; 2's complement
	cp b		; compare to checksum accumulated in reg B
	jp nz,badload	; checksum not match, put '?'
	call DMAPage	; set page i/o reg to DMA
; use DMA to put data from buffer to location pointed by ehl
	push hl		; destination RAM in hl, save it for now
	ld b,0		; clear out MSB of reg BC, reg C contains the saved byte count
	push bc		; DMA count is in reg BC, save it 
; set up DMA master control
	ld c,DMActrl	; set up DMA master control
	ld hl,0f0e0h	; software ready for dma0&1, no end-of-process, no links
;	outw (c),hl	; write DMA master control reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; set up DMA count register 
	ld c,DMA3cnt	; setup count of 128 byte
	pop hl		; transfer what was saved in bc into hl
;	outw (c),hl	; write DMA3 count reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; source buffer starts at 0xc000
	ld c,DMA3srcH	; source is 0x1000
	ld hl,0cfh		; A23..A12 are 0x00c		
;	outw (c),hl	; write DMA3 source high reg
	db 0edh,0bfh	; op code for OUTW (C),HL
	ld c,DMA3srcL	;
	ld hl,0f000h	; A11..A0 are 0x0
;	outw (c),hl	; write DMA3 source low reg
	db 0edh,0bfh	; op code for OUTW (C),HL	
; destination buffer is in e + hl (saved in stack right now)
	ld c,DMA3dstH
	ld a,(addr3116)	; get A23..A16 value into reg H
	ld h,a		; 	
	pop de		; restore saved hl into de

;lines marked with ;;mmu comment are added to check for physical page 0
; insert a test for physical page 0 (addr3116 equal 0 & upper nibble of reg D also zero)
	or a		;;mmu reg A contains (addr3116)
	jp nz,notpage0	;;mmu not physical page 0
	ld a,d		;;mmu A31..A16 is zero, now examine A15..A12
	and 0f0h		;;mmu mask off A11..A8
	jp nz,notpage0	;;mmu not physical page 0
; the destination is physical page 0, substitue 0x3C000 instead
; put 3C000 in HL and jump to write dma3destination

	ld l,0cfh		;;mmu
	ld h,03h		;;mmu
	jp do_dma3hi	;;mmu

notpage0:
	ld l,d		; move A15..A8 value
	ld a,0fh		; force lowest nibble of DMA3dstH to 0xF
	or l
do_dma3hi:
;	outw (c),hl	; write DMA3 destination high reg
	db 0edh,0bfh	; op code for OUTW (C),HL
	ld c,DMA3dstL
	ld h,d		; reg DE contain A15..A0 value
	ld l,e
	ld a,0f0h		; force highest nibble of DMA3dstL to 0xF
	or h
;	outw (c),hl	; write DMA3 destination low reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; write DMA3 transaction description reg and start DMA
	ld hl,8080h	; enable DMA3, burst, byte size, flowthrough, no interrupt
;			;  incrementing memory for source & destination
	ld c,DMA3td	; setup DMA3 transaction descriptor reg
;	outw (c),hl	; write DMA3 transaction description reg
	db 0edh,0bfh	; op code for OUTW (C),HL
;  DMA should start now
	call UARTPage	; set page i/o reg to default

	ld a,'.'		; checksum match, put '.'
filesav2:
	call COUT
	jp flushln	; repeat until record end
badload:
	ld a,'?'		; checksum not match, put '?'
	jp filesav2
unknown:
	ld a,'U'		; put out a 'U' and wait for next record
	call COUT
flushln:
	call CINQ		; keep on reading until ':' is encountered
	cp ':'
	jp nz,flushln
	jp fileload
; format CF drives directories unless it is RAM disk
; drive A directory is track 1, sectors 0-0x1F
; drive B directory is track 0x40, sectors 0-0x1F
; drive C directory is track 0x80, sectors 0-0x1F
; drive D directory is track 0xC0, sectors 0-0x1F
format:
	ld hl,clrdir$	; command message
	call STROUT
	call CIN
	cp 'A'
	jp z,ClearA	; clear directory of RAM disk A
	cp 'B'
	jp z,ClearB	; clear directory of RAM disk B
	jp abort		; abort command if not in the list of options
; subroutine to fill 2K block at 0x1000 with 0xE5
fillE5:
	push hl		; save reg
	push bc
	ld hl,1000h	; fill 2K block with 0xE5
	ld bc,800h	; count of 800
fillE51:
	ld (hl),0e5h
	inc hl
	dec bc
	ld a,b		; test reg BC=0
	or c
	jp nz,fillE51
	pop bc		; restore reg
	pop hl
	ret
ClearA:
; drive A resides in memory 0x10000 to 0x3BFFF
; drive A directory is 2K in size starts from 0x10000
; fill it with 0xE5 using DMA
; Source is at 0x1000
	call fillE5	; fill 2K block at 0x1000 with 0xE5
	call DMAPage	; set page i/o reg to DMA
; set up DMA master control
	ld c,DMActrl	; set up DMA master control
	ld hl,0f0e0h	; software ready for dma0&1, no end-of-process, no links
;	outw (c),hl	; write DMA master control reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; set up DMA count register 
	ld c,DMA3cnt	; setup count of 2048 byte
	ld hl,800h	
;	outw (c),hl	; write DMA3 count reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; source buffer starts at 0x1000
	ld c,DMA3srcH	; source is 0x1000
	ld hl,01fh	; A23..A12 are 0x001, low nibble is all 1's		
;	outw (c),hl	; write DMA3 source high reg
	db 0edh,0bfh	; op code for OUTW (C),HL
	ld c,DMA3srcL	;
	ld hl,0f000h	; A11..A0 are 0x0, high nibble is all 1's
;	outw (c),hl	; write DMA3 source low reg
	db 0edh,0bfh	; op code for OUTW (C),HL	
; destination is 0x10000
	ld c,DMA3dstH
	ld hl,10fh	; A23..A12 are 0x010, low nibble is all 1's
;	outw (c),hl	; write DMA3 destination high reg
	db 0edh,0bfh	; op code for OUTW (C),HL
	ld c,DMA3dstL
	ld hl,0f000h	; A11..A0 are 0x0, high nibble is all 1's
;	outw (c),hl	; write DMA3 destination low reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; write DMA3 transaction description reg and start DMA
	ld hl,8080h	; enable DMA3, burst, byte size, flowthrough, no interrupt
;			;  incrementing memory for source & destination
	ld c,DMA3td	; setup DMA3 transaction descriptor reg
;	outw (c),hl	; write DMA3 transaction description reg
	db 0edh,0bfh	; op code for OUTW (C),HL
;  DMA should start now
	call UARTPage	; set page i/o reg to UART
	jp CMD

ClearB:
; drive B resides in memory 0x40000 to 0x7FFFF
; drive B directory is 2K in size starts from 0x40000
; fill it with 0xE5 using DMA
; Source is at 0x1000
	call fillE5	; fill 2K block at 0x1000 with 0xE5
	call DMAPage	; set page i/o reg to DMA
; set up DMA master control
	ld c,DMActrl	; set up DMA master control
	ld hl,0f0e0h	; software ready for dma0&1, no end-of-process, no links
;	outw (c),hl	; write DMA master control reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; set up DMA count register 
	ld c,DMA3cnt	; setup count of 2048 byte
	ld hl,800h	
;	outw (c),hl	; write DMA3 count reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; source buffer starts at 0x1000
	ld c,DMA3srcH	; source is 0x1000
	ld hl,01fh	; A23..A12 are 0x001, low nibble is all 1's		
;	outw (c),hl	; write DMA3 source high reg
	db 0edh,0bfh	; op code for OUTW (C),HL
	ld c,DMA3srcL	;
	ld hl,0f000h	; A11..A0 are 0x0, high nibble is all 1's
;	outw (c),hl	; write DMA3 source low reg
	db 0edh,0bfh	; op code for OUTW (C),HL	
; destination is 0x40000
	ld c,DMA3dstH
	ld hl,40fh	; A23..A12 are 0x040, low nibble is all 1's
;	outw (c),hl	; write DMA3 destination high reg
	db 0edh,0bfh	; op code for OUTW (C),HL
	ld c,DMA3dstL
	ld hl,0f000h	; A11..A0 are 0x0, high nibble is all 1's
;	outw (c),hl	; write DMA3 destination low reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; write DMA3 transaction description reg and start DMA
	ld hl,8080h	; enable DMA3, burst, byte size, flowthrough, no interrupt
;			;  incrementing memory for source & destination
	ld c,DMA3td	; setup DMA3 transaction descriptor reg
;	outw (c),hl	; write DMA3 transaction description reg
	db 0edh,0bfh	; op code for OUTW (C),HL
;  DMA should start now
	call UARTPage	; set page i/o reg to UART
	jp CMD
INPORT:
; read data from specified I/O port in page 0
; command format is "I port#"
; 
	ld hl,inport$	; print command 'I' prompt
	call STROUT
	call GETHEX	; get port # into reg A
	push bc		; save register
	ld c,a		; load port # in reg C
	call ZeroPage	; The I/O port resides in page 0
	in b,(c)		; get data from port # into reg B
	call UARTPage
	ld hl,invalue$
	call STROUT
	ld a,b
	call HEXOUT
	pop bc		; restore reg
	jp CMD
OUTPORT:
; write data to specified I/O port in page 0
; command format is "O value port#"
	ld hl,outport$	; print command 'O' prompt
	call STROUT
	call GETHEX	; get value to be output
	push bc		; save register

	ld b,a		; load value in reg B
	ld hl,outport2$	; print additional prompt for command 'O'
	call STROUT
	call GETHEX	; get port number into reg A
	ld c,a
	call ZeroPage	; The I/O port resides in page 0
	out (c),b		; output data in regB to port in reg C

	call UARTPage
	pop bc
	jp CMD
LISTHEX:
; list memory as Intel Hex format
; the purpose of command is to save memory as Intel Hex format to console
	ld hl,listhex$	; print command 'L' prompt
	call STROUT
	call ADRIN	; get address word into reg DE
	push de		; save for later use
	ld hl,listhex1$	; print second part of 'L' command prompt
	call STROUT
	call ADRIN	; get end address into reg DE
listhex1:
	ld hl,CRLF$	; put out a CR, LF	
	call STROUT
	ld c,10h		; each line contains 16 bytes
	ld b,c		; reg B is the running checksum
	ld a,':'		; start of Intel Hex record
	call COUT
	ld a,c		; byte count
	call HEXOUT
	pop hl		; start address in HL
	call ADROUT	; output start address
	ld a,b		; get the checksum
	add a,h		; accumulate checksum
	add a,l		; accumulate checksum
	ld b,a		; checksum is kept in reg B
	xor a		
	call HEXOUT	; record type is 00 (data)
listhex2:
	ld a,(hl)		; get memory pointed by hl
	call HEXOUT	; output the memory value in hex
	ld a,(hl)		; get memory again
	add a,b		; accumulate checksum
	ld b,a		; checksum is kept in reg B
	inc hl
	dec c
	jp nz,listhex2
	ld a,b		; get the checksum
	neg a
	call HEXOUT	; output the checksum
; output 16 memory location, check if reached the end address (saved in reg DE)
; unsign compare: if reg A < reg N, C flag set, if reg A > reg N, C flag clear
	push hl		; save current address pointer
	ld a,h		; get MSB of current address
	cp d		; reg DE contain the end address
	jp nc,hexend	; if greater, output end-of-file record
	jp c,listhex1	; if less, output more record
; if equal, compare the LSB value of the current address pointer
	ld a,l		; now compare the LSB of current address
	cp e
	jp c,listhex1	; if less, output another line of Intel Hex
hexend:
; end-of-record is :00000001FF
	ld hl,CRLF$
	call STROUT
	ld a,':'		; start of Intel Hex record
	call COUT
	xor a
	call HEXOUT	; output "00"
	xor a
	call HEXOUT	; output "00"
	xor a
	call HEXOUT	; output "00"
	ld a,1
	call HEXOUT	; output "01"
	ld a,0ffh
	call HEXOUT	; output "FF"

	pop hl		; clear up the stack

	jp CMD

; print help message
HELP:
	ld hl,HELP$	; print help message
	call STROUT
	jp CMD
; boot CPM
; copy program from LA9-LA26 (9K) to 0xDC00
; jump to 0xF200 after copy is completed.
BootCPM:
	ld hl,bootcpm$	; print command message
	call STROUT
	call CIN		; get input
;	cp '1'		; '1' is user apps
;	jp z,bootApps
	cp '2'		; '2' is cpm2.2
	jp z,boot22
;	cp '3'		; '3' is cpm3, not implemented
;	jp z,boot3
	jp what

boot22:
; copy CP/M from 0x3D000 to 0x3FFFF to 0xDC00-0xFFFF using DMA operation
;  jump into 0xF200 after copy completed
	ld hl,confirm$	; carriage return to execute the program
	call STROUT
	call tstCRLF
	jp nz,abort	; abort command if not CR or LF

	call DMAPage	; set page i/o reg to DMA
; set up DMA master control
	ld c,DMActrl	; set up DMA master control
	ld hl,0f0e0h	; software ready for dma0&1, no end-of-process, no links
;	outw (c),hl	; write DMA master control reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; set up DMA count register 
	ld c,DMA3cnt	; setup count of 9216 byte
	ld hl,2400h	
;	outw (c),hl	; write DMA3 count reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; source buffer starts at 0x3D000
	ld c,DMA3srcH	; source is 0x3D000
	ld hl,03dfh	; A23..A12 are 0x03d, low nibble is all 1's		
;	outw (c),hl	; write DMA3 source high reg
	db 0edh,0bfh	; op code for OUTW (C),HL
	ld c,DMA3srcL	;
	ld hl,0f000h	; A11..A0 are 0x000, high nibble is all 1's
;	outw (c),hl	; write DMA3 source low reg
	db 0edh,0bfh	; op code for OUTW (C),HL	
; destination is 0xDC00
	ld c,DMA3dstH
	ld hl,0dfh	; A23..A12 are 0x00d, low nibble is all 1's
;	outw (c),hl	; write DMA3 destination high reg
	db 0edh,0bfh	; op code for OUTW (C),HL
	ld c,DMA3dstL
	ld hl,0fc00h	; A11..A0 are 0xc00, high nibble is all 1's
;	outw (c),hl	; write DMA3 destination low reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; write DMA3 transaction description reg and start DMA
	ld hl,8080h	; enable DMA3, burst, byte size, flowthrough, no interrupt
;			;  incrementing memory for source & destination
	ld c,DMA3td	; setup DMA3 transaction descriptor reg
;	outw (c),hl	; write DMA3 transaction description reg
	db 0edh,0bfh	; op code for OUTW (C),HL
;  DMA should start now
	call UARTPage	; set page i/o reg to UART
	jp 0f200h		; BIOS starting address of CP/M22

;bootApps:
; User applications resides in CF sector 0x40-0x7F.  
; Copy it to 0x0-0x7FFF and jump to 0x0
;	ld hl,confirm$	; CRLF to execute the command
;	call STROUT
;	call tstCRLF
;	jp nz,abort	; abort command if no CRLF
;	call CFPage	; initialize page i/o reg to CF
;	ld a,40h		; set Logical Address addressing mode
;	out (CF2427),a
;	xor a		; clear reg A
;	out (CF1623),a	; track 0
;	out (CF815),a
;	ld hl,0		; user apps starts from 0x0
;	ld c,CFdata	; reg C points to CF data reg
;	ld d,40h		; read from LA 0x40 to LA 0x7F
;readApp1:
;	ld a,1		; read 1 sector
;	out (CFsectcnt),a	; write to sector count with 1
;	ld a,d		; read CPM sector
;	cp 80h		; between LA40h and LA7fh
;	jp z,goApps	; done copying, execute user apps
;	out (CF07),a	; 
;	ld a,20h		; read sector command
;	out (CFstat),a	; issue the read sector command
;readdrqApp:
;	in a,(CFstat)	; check data request bit set before read CF data
;	and 8		; bit 3 is DRQ, wait for it to set
;	jp z,readdrqApp
;	ld b,0h		; sector has 256 16-bit data
;	db 0edh,92h	; op code for inirw input word and increment
;;	inirw
;	inc d		; read next sector
;	jp readApp1
;goApps:
;	call UARTPage	; set page i/o reg to internal UART
;	jp 0h		; User apps starts at 0x0
; fill memory from end of program to 0xFFFF with zero or 0xFF
; also fill memory from 0x0 to 0xB000 with zero or 0xFF
fillZ:
	ld hl,fill0$	; print fill memory with 0 message
	call STROUT
	ld b,0		; fill memory with 0
	jp dofill
fillF:
	ld hl,fillf$	; print fill memory with F message
	call STROUT
	ld b,0ffh		; fill memory with ff
dofill:
	ld hl,confirm$	; get confirmation before executing
	call STROUT
	call tstCRLF	; check for carriage return
	jp nz,abort
	ld hl,PROGEND	; start from end of this program
	ld a,0ffh		; end address in reg A
filla:
	ld (hl),b		; write memory location
	inc hl
	cp h		; reached 0xFF00?
	jp nz,filla	; continue til done
	cp l		; reached 0xFFFF?
	jp nz,filla
	ld hl,0b000h	; fill value from 0xB000 down to 0x0000
fillb:
	dec hl
	ld (hl),b		; write memory location with desired value
	ld a,h		; do until h=l=0
	or l
	jp nz,fillb
	jp CMD
; Read RAMdisk
; start from 0x1000 as track 0 sector 0
; each track is 128k, so there are total of 4 tracks
; each sector is 512 bytes, this is holdover from a CF sector
; use DMA to read a sector to 0x1000
READRD:
	ld hl,read$	; put out read command message
	call STROUT
	ld hl,track$	; enter track in hex value
	call STROUT
	call GETHEX	; get a byte of hex value as track
	ld (RDtrack),a	; save it 
;;	push af		; save track value in stack
	ld hl,sector$	; enter sector in hex value
	call STROUT
	call GETHEX	; get a byte of hex value as sector
	ld (RDsector),a	; save it
;;	push af		; save sector value in stack
READRD1:
	ld hl,1000h	; copy previous block to 2000h
	ld de,2000h
	ld bc,200h	; copy 512 bytes
	ldir		; block copy

; track 0 is 0x10000 base address plus 0x200*sector
; track 1 is 0x30000 base address plus 0x200*sector
; track 2 is 0x50000 base address plus 0x200*sector
; track 3 is 0x70000 base address plus 0x200*sector

	call DMAPage	; set page i/o reg to DMA
; set up DMA master control
	ld c,DMActrl	; set up DMA master control
	ld hl,0f0e0h	; software ready for dma0&1, no end-of-process, no links
;	outw (c),hl	; write DMA master control reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; set up DMA count register 
	ld c,DMA3cnt	; setup count of 512 bytes
	ld hl,200h	
;	outw (c),hl	; write DMA3 count reg
	db 0edh,0bfh	; op code for OUTW (C),HL
;;	pop af		; get sector value from stack
;;	push af		; save for later use
	ld a,(RDsector)	; get sector value
	add a		; 2*n, no need to worry about carry for this part of operation
	or 0f0h		; set high nibble to all 1's
	ld h,a		; forming source low address
	ld l,0
	ld c,DMA3srcL	;
;	outw (c),hl	; write DMA3 source low reg
	db 0edh,0bfh	; op code for OUTW (C),HL

;;	pop af		; restore, now calculate the high 12-bit of source address
	ld a,(RDsector)
	ld h,0
	ld l,a		; get the sector value into reg L
	add hl,hl		; 16-bit add, carry bit goes into reg H
	ld a,0fh		; force lowest nibble to all 1's
	or l		; 
	ld l,a		; reg L has the low address value
; now get the high address value into reg H:
;;	pop af		; get track number
	ld a,(RDtrack)
	add a		; track 0 ->0x10000, track 1 -> 0x30000, track 2 -> 0x50000, etc
	add 1		; add the track offset
	add h		; h may be 1 due to carry from hl+hl operation
	ld h,a		; reg H has the high address value
	ld c,DMA3srcH	; point to source high register
;	outw (c),hl	; write DMA3 source high reg
	db 0edh,0bfh	; op code for OUTW (C),HL

; destination is 0x1000
	ld c,DMA3dstH
	ld hl,01fh	; A23..A12 are 0x001, low nibble is all 1's
;	outw (c),hl	; write DMA3 destination high reg
	db 0edh,0bfh	; op code for OUTW (C),HL
	ld c,DMA3dstL
	ld hl,0f000h	; A11..A0 are 0x000, high nibble is all 1's
;	outw (c),hl	; write DMA3 destination low reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; write DMA3 transaction description reg and start DMA
	ld hl,8080h	; enable DMA3, burst, byte size, flowthrough, no interrupt
;			;  incrementing memory for source & destination
	ld c,DMA3td	; setup DMA3 transaction descriptor reg
;	outw (c),hl	; write DMA3 transaction description reg
	db 0edh,0bfh	; op code for OUTW (C),HL
;  DMA should start now
	call UARTPage	; set page i/o reg to UART

dumpdata:
	ld d,32		; 32 lines of data
	ld hl,1000h	; display 512 bytes of data
dmpdata1:
	push hl		; save hl
	ld hl,CRLF$	; add a CRLF per line
	call STROUT
	pop hl		; hl is the next address to display
	call DMP16TS	; display 16 bytes per line
	dec d
	jp nz,dmpdata1

	ld hl,1000h	; compare with data block in 2000h
	ld bc,200h
	ld de,2000h
blkcmp:
	ld a,(de)		; get a byte from block in 2000h
	inc de
	cpi		; compare with corresponding data in 1000h
	jp po,blkcmp1	; exit at end of block compare
	jp z,blkcmp	; exit if data not compare
	ld hl,notsame$	; send out message that data not same as previous read
	call STROUT
	jp chkRDmore
blkcmp1:	
	ld hl,issame$	; send out message that data read is same as before
	call STROUT

chkRDmore:
	ld hl,RDmore$	; carriage return for next sector of data
	call STROUT
	call tstCRLF	; look for CRLF
	jp nz,CMD		; 
	ld hl,(RDsector)	; load track & sector as 16-bit value
	inc hl		; increment by 1
	ld (RDsector),hl	; save updated values
	ld hl,track$	; print track & sector value
	call STROUT
	ld a,(RDtrack)
	call HEXOUT
	ld hl,sector$
	call STROUT
	ld a,(RDsector)
	call HEXOUT

	jp READRD1
; Write CF
;  allowable parameters are '0' for boot sector & ZZMon, '1' for 32K apps, 
;   '2' for CPM2.2, '3' for CPM3
; Set page I/O to 0, afterward set it back to 0FEh
COPYCF:
	ld hl,copycf$	; print copy message
	call STROUT
	call CIN		; get write parameters
	cp '0'
	jp z,cpboot
;	cp '1'
;	jp z,cpAPPS
	cp '2'
	jp z,CopyCPM2
;	cp '3'
;	jp z,CopyCPM3
	jp what		; error, abort command

	jp CMD
; test for CR or LF.  Echo back. return 0
tstCRLF:
	call CIN		; get a character					
	cp 0dh		; if carriage return, output LF
	jp z,tstCRLF1
	cp 0ah		; if line feed, output CR 
	jp z,tstCRLF2
	ret
tstCRLF1:
	ld a,0ah		; put out a LF
	call COUT
	xor a		; set Z flag
	ret
tstCRLF2:
	ld a,0dh		; put out a CR
	call COUT
	xor a		; set Z flag
	ret

; write CPM to 0x3D000 to 0x3FFFF
;  CP/M is previously loaded to 0xDC00-0xFFFF
; Use DMA operation to do the copy
CopyCPM2:
	ld hl,confirm$	; carriage return to execute the program
	call STROUT
	call tstCRLF
	jp nz,CMD		; abort command if not CR or LF
; Source is at 0xDC00
	call DMAPage	; set page i/o reg to DMA
; set up DMA master control
	ld c,DMActrl	; set up DMA master control
	ld hl,0f0e0h	; software ready for dma0&1, no end-of-process, no links
;	outw (c),hl	; write DMA master control reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; set up DMA count register 
	ld c,DMA3cnt	; setup count of 9216 byte
	ld hl,2400h	
;	outw (c),hl	; write DMA3 count reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; source buffer starts at 0xDC00
	ld c,DMA3srcH	; source is 0xDC00
	ld hl,0dfh	; A23..A12 are 0x00d, low nibble is all 1's		
;	outw (c),hl	; write DMA3 source high reg
	db 0edh,0bfh	; op code for OUTW (C),HL
	ld c,DMA3srcL	;
	ld hl,0fc00h	; A11..A0 are 0xc00, high nibble is all 1's
;	outw (c),hl	; write DMA3 source low reg
	db 0edh,0bfh	; op code for OUTW (C),HL	
; destination is 0x3D000
	ld c,DMA3dstH
	ld hl,03dfh		; A23..A12 are 0x03d, low nibble is all 1's
;	outw (c),hl	; write DMA3 destination high reg
	db 0edh,0bfh	; op code for OUTW (C),HL
	ld c,DMA3dstL
	ld hl,0f000h	; A11..A0 are 0x0, high nibble is all 1's
;	outw (c),hl	; write DMA3 destination low reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; write DMA3 transaction description reg and start DMA
	ld hl,8080h	; enable DMA3, burst, byte size, flowthrough, no interrupt
;			;  incrementing memory for source & destination
	ld c,DMA3td	; setup DMA3 transaction descriptor reg
;	outw (c),hl	; write DMA3 transaction description reg
	db 0edh,0bfh	; op code for OUTW (C),HL
;  DMA should start now
	call UARTPage	; set page i/o reg to UART
	jp CMD

cpboot:
; use DMA to copy itself into physical page 0
; the reason DMA is used is because physical page 0 is invisible due to MMU mapping
;  but DMA transfer between physical addresses bypassing the MMU
	ld hl,confirm$	; carriage return to execute the program
	call STROUT
	call tstCRLF
	jp nz,CMD		; abort command if not CR or LF
; Source is at 0xb000
	call DMAPage	; set page i/o reg to DMA
; set up DMA master control
	ld c,DMActrl	; set up DMA master control
	ld hl,0f0e0h	; software ready for dma0&1, no end-of-process, no links
;	outw (c),hl	; write DMA master control reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; set up DMA count register 
	ld c,DMA3cnt	; setup count of 4096 byte
	ld hl,1000h	
;	outw (c),hl	; write DMA3 count reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; source buffer starts at 0xb000
	ld c,DMA3srcH	; source is 0xb000
	ld hl,0bfh	; A23..A12 are 0x00b, low nibble is all 1's		
;	outw (c),hl	; write DMA3 source high reg
	db 0edh,0bfh	; op code for OUTW (C),HL
	ld c,DMA3srcL	;
	ld hl,0f000h	; A11..A0 are 0x0, high nibble is all 1's
;	outw (c),hl	; write DMA3 source low reg
	db 0edh,0bfh	; op code for OUTW (C),HL	
; destination is 0x0
	ld c,DMA3dstH
	ld hl,0fh		; A23..A12 are 0x000, low nibble is all 1's
;	outw (c),hl	; write DMA3 destination high reg
	db 0edh,0bfh	; op code for OUTW (C),HL
	ld c,DMA3dstL
	ld hl,0f000h	; A11..A0 are 0x0, high nibble is all 1's
;	outw (c),hl	; write DMA3 destination low reg
	db 0edh,0bfh	; op code for OUTW (C),HL
; write DMA3 transaction description reg and start DMA
	ld hl,8080h	; enable DMA3, burst, byte size, flowthrough, no interrupt
;			;  incrementing memory for source & destination
	ld c,DMA3td	; setup DMA3 transaction descriptor reg
;	outw (c),hl	; write DMA3 transaction description reg
	db 0edh,0bfh	; op code for OUTW (C),HL
;  DMA should start now
	call UARTPage	; set page i/o reg to UART
	jp CMD

cpAPPS:
	ld hl,0		; Application starts from 0 to 0x7FFF
	ld de,407fh	; reg DE contains beginning sector and end sector values
	
TESTRAM:
; test memory from top of this program to 0xFFFE 
	ld hl,testram$	; print test ram message
	call STROUT
	ld hl,confirm$	; get confirmation before executing
	call STROUT
	call tstCRLF	; check for carriage return
	jp nz,abort
	ld iy,(testseed)	; a prime number seed, another good prime number is 211
TRagain:
	ld hl,PROGEND	; start testing from the end of this program
	ld de,137		; increment by prime number
TRLOOP:
	push iy		; bounce off stack
	pop bc
	ld (hl),c		; write a pattern to memory
	inc hl
	ld (hl),b
	inc hl
	add iy,de		; add a prime number
	ld a,0ffh		; compare h to 0xff
	cp h
	jp nz,TRLOOP	; continue until reaching 0xFFFE
	ld a,0feh		; compare l to 0xFE
	cp l
	jp nz,TRLOOP
	ld hl,0b000h	; test memory from 0xAFFF down to 0x0000
TR1LOOP:
	push iy
	pop bc		; bounce off stack
	dec hl
	ld (hl),b		; write MSB
	dec hl
	ld (hl),c		; write LSB
	add iy,de		; add a prime number
	ld a,h		; check h=l=0
	or l
	jp nz,TR1LOOP
	ld hl,PROGEND	; verify starting from the end of this program
	ld iy,(testseed)	; starting seed value
TRVER:
	push iy		; bounce off stack
	pop bc
	ld a,(hl)		; get LSB
	cp c		; verify
	jp nz,TRERROR
	inc hl
	ld a,(hl)		; get MSB
	cp b
	jp nz,TRERROR
	inc hl
	add iy,de		; next reference value
	ld a,0ffh		; compare h to 0xff
	cp h
	jp nz,TRVER	; continue verifying til end of memory
	ld a,0feh		; compare l to 0xFE
	cp l
	jp nz,TRVER
	ld hl,0b000h	; verify memory from 0xB000 down to 0x0000
TR1VER:
	push iy		; bounce off stack
	pop bc
	dec hl
	ld a,(hl)		; get MSB from memory
	cp b		; verify
	jp nz,TRERROR
	dec hl
	ld a,(hl)		; get LSB from memory
	cp c
	jp nz,TRERROR
	add iy,de
	ld a,h		; check h=l=0
	or l
	jp nz,TR1VER
	call SPCOUT	; a space delimiter
	ld a,'O'		; put out 'OK' message
	call COUT
	ld a,'K'
	call COUT
	ld (testseed),iy	; save seed value

	IN A,(RxStat)	; read on-chip UART receive status
        	AND 10H				;;Z data available?
        	JP Z,TRagain	; no char, do another iteration of memory test
        	IN A,(RxData)	; save to reg A
        	OUT (TxData),A	; echo back
;	cp 'X'		; if 'X' or 'x', exit memory test
;	jp z,CMD
;	cp 'x'
;	jp nz,TRagain
	jp CMD
TRERROR:
	call SPCOUT	; a space char to separate the 'r' command
	ld a,'H'		; display content of HL reg
	call COUT		; print the HL label
	ld a,'L'
	call COUT
	call SPCOUT	
	call ADROUT	; output the content of HL 	
	jp CMD

;Get an address and jump to it
go:
	ld hl,go$		; print go command message
	call STROUT
        	CALL ADRIN
        	LD H,D
        	LD L,E
	push hl		; save go address
	ld hl,confirm$	; get confirmation before executing
	call STROUT
	call tstCRLF	; check for carriage return
	pop hl
	jp nz,abort
;	ld hl,CRLF$	; insert CRLF before executing
;	call STROUT
;	pop hl		; restore saved go address
	jp (hl)		; jump to address if CRLF

;;;;;;;;;;;;;;;;;;;;;;;;;;; Utilities from Glitch Works ver 0.1 ;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;; Copyright (C) 2012 Jonathan Chapman ;;;;;;;;;;;;;;;;;;

;Edit memory from a starting address until X is
;pressed. Display mem loc, contents, and results
;of write.
EDMEM:  	CALL SPCOUT
        	CALL ADRIN
        	LD H,D
        	LD L,E
ED1:    	LD A,13
        	CALL COUT
        	LD A,10
        	CALL COUT
        	CALL ADROUT
        	CALL SPCOUT
        	LD A,':'
        	CALL COUT
        	CALL SPCOUT
        	CALL DMPLOC
        	CALL SPCOUT
        	CALL GETHEX
        	JP C,CMD
        	LD (HL),A
        	CALL SPCOUT
        	CALL DMPLOC
        	INC HL
        	JP ED1

;Dump memory between two address locations
MEMDMP: 	CALL SPCOUT
        	CALL ADRIN
        	LD H,D
        	LD L,E
        	LD C,10h
        	CALL SPCOUT
        	CALL ADRIN
MD1:    	LD A,13
        	CALL COUT
        	LD A,10
        	CALL COUT
        	CALL DMP16
        	LD A,D
        	CP H
        	JP M,CMD
        	LD A,E
        	CP L
        	JP M,MD2
        	JP MD1
MD2:    	LD A,D
        	CP H
        	JP NZ,MD1
        	JP CMD

DMP16TS:
; dump memory pointed by HL, but using the RDtrack & RDsector
;  as the address field
; compute physical address from sector & track
	push hl		; save reg
	ld hl,(RDsector)	; load current sector and track
	add hl,hl		; shift by one to get physical address
	inc h		; add track offset
; hl now contains A23..A8 of physical address.  A7..A0 are zero
	call ADROUT	; output A23..A8
	ld a,0
	call HEXOUT	; output A7..A0 which are zero
	pop hl		; restore reg
	jp DMP16D		; display the 16 data field

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;DMP16 -- Dump 16 consecutive memory locations
;
;pre: HL pair contains starting memory address
;post: memory from HL to HL + 16 printed
;post: HL incremented to HL + 16
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DMP16:  	CALL ADROUT
DMP16D:			; 16 consecutive data
        	CALL SPCOUT
        	LD A,':'
        	CALL COUT
        	LD C,10h
	push hl		; save location for later use
DM1:    	CALL SPCOUT
        	CALL DMPLOC
        	INC HL		
        	DEC C
;        	RET Z
	jp nz,DM1
;        	JP DM1

; display the ASCII equivalent of the hex values
	pop hl		; retrieve the saved location
	ld c,10h		; print 16 characters
	call SPCOUT	; insert two space
	call SPCOUT	; 
dm2:
	ld a,(hl)		; read the memory location
	cp ' '
	jp m,printdot	; if lesser than 0x20, print a dot
	cp 7fh
	jp m,printchar
printdot:
; for value lesser than 0x20 or 0x7f and greater, print '.'
	ld a,'.'
printchar:
; output printable character
	call COUT
	inc hl
	dec c
	ret z
	jp dm2



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;DMPLOC -- Print a byte at HL to console
;
;pre: HL pair contains address of byte
;post: byte at HL printed to console
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DMPLOC: 	LD A,(HL)
        	CALL HEXOUT
        	RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;HEXOUT -- Output byte to console as hex
;
;pre: A register contains byte to be output
;post: byte is output to console as hex
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
HEXOUT: 	PUSH BC
        	LD B,A
        	RRCA
        	RRCA
        	RRCA
        	RRCA
        	AND 0Fh
        	CALL HEXASC
        	CALL COUT
        	LD A,B
        	AND 0Fh
        	CALL HEXASC
        	CALL COUT
        	POP BC
        	RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;HEXASC -- Convert nybble to ASCII char
;
;pre: A register contains nybble
;post: A register contains ASCII char
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
HEXASC: 	ADD 90h
        	DAA
        	ADC A,40h
        	DAA
        	RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;ADROUT -- Print an address to the console
;
;pre: HL pair contains address to print
;post: HL printed to console as hex
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ADROUT: 	LD A,H
        	CALL HEXOUT
        	LD A,L
        	CALL HEXOUT
        	RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;ADRIN -- Get an address word from console
;
;pre: none
;post: DE contains address from console
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ADRIN:  	CALL GETHEX
        	LD D,A
        	CALL GETHEX
        	LD E,A
        	RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;GETHEX -- Get byte from console as hex
;
;pre: none
;post: A register contains byte from hex input
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
GETHEX: 	PUSH DE
        	CALL CIN
        	CP 'X'
        	JP Z,GE2
	cp 'x'		; exit with lower 'x'
	jp z,GE2
        	CALL ASCHEX
        	RLCA
        	RLCA
        	RLCA
        	RLCA
        	LD D,A
        	CALL CIN
        	CALL ASCHEX
        	OR D
GE1:    	POP DE
        	RET
GE2:    	SCF
        	JP GE1

; get hex without echo back
GETHEXQ:
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
;GOBYT -- Push a two-byte instruction and RET
;         and jump to it
;
;pre: B register contains operand
;pre: C register contains opcode
;post: code executed, returns to caller
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
GOBYT:  	LD HL,0000
        	ADD HL,SP
        	DEC HL
        	LD (HL),0C9h
        	DEC HL
        	LD (HL),B
        	DEC HL
        	LD (HL),C
        	JP (HL)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;SPCOUT -- Print a space to the console
;
;pre: none
;post: 0x20 printed to console
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SPCOUT: 	LD A,' '
        	CALL COUT
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
;;;;;;;;;;;;;;;;;;;;;;;;;;; Utilities by Glitch Works ver 0.1 ;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;; Copyright (C) 2012 Jonathan Chapman ;;;;;;;;;;;;;;;;;;

; initialize MMU page descriptors
; logical page 0 is mapped to physical address 0x3C000 with write protect enabled
; the remaining 15 logical pages are mapped to first 64K of physical memory
initMMU:
	push hl		; save register
	push bc
	ld a,0cah		; V/WP/C/M bits are 1/0/1/0, logical page 0 only
	ld hl,MMUtbl
	ld (hl),a		; write LSB of page descriptor 0
	inc hl
	ld (hl),03h	; write 03Ch to upper 12 bits of address
	inc hl
	ld a,1ah		; V/WP/C/M bits are 1/0/1/0, start with page 1
initMMUp
	ld (hl),a		; store page descriptor value to table
	inc hl		; point to MSB of page descriptor
	ld (hl),0		; transparent mapping
	inc hl
	add 10h		; point to next page descriptor
	cp 0ah		; end of table? (End of table when reg A wrapped around back to 0ah)
	jp nz,initMMUp	; do this for page descriptor 1 to page descriptor F
	xor a		; clear reg A 
	out (MMUptr),a	; point to this page (page 0x0), user page descriptors	
	ld hl,MMUtbl	; block move MMU page descriptors
	ld c,MMUmove	; points to MMU block move port
	ld b,16		; move 16 pages
	db 0edh,93h	; op code for otirw, output word and increment
;	otirw
	ld a,10h		; repeat the block move for system page descriptors
	out (MMUptr),a	; point to this page (page 0x0), user page descriptors	
	ld hl,MMUtbl	; block move MMU page descriptors
	ld c,MMUmove	; points to MMU block move port
	ld b,16		; move 16 pages
	db 0edh,93h	; op code for otirw, output word and increment
;	otirw
	ld c,MMUctrl	; point to MMU master control register
	ld hl,0bbffh	; enable user & system  translate
	db 0edh,0bfh	; op code for OUTW (C),HL
;	outw (c),hl	; turn on MMU
	pop bc		; restore register
	pop hl
	ret

; init page i/o reg to point to UART
UARTPage:
	push hl		; save register
	ld l,0feh		; set I/O page register to 0xFE
	jp setpage
; initialize Z280 page i/o reg to point to MMU and DMA
DMAPage:
MMUPage:
	push hl		; save register
	ld l,0ffh		; MMU and DMA page I/O reg is 0xFF
	jp setpage
; init page i/o reg to point to compactflash
ZeroPage:
CFPage:
	push hl		; save register
	ld l,0		; set I/O page register to 0

setpage:
	push bc		; save more reg
	ld c,08h		; reg c points to I/O page register
; reg L is already pre-loaded with correct page value
	db 0edh,6eh	; this is the op code for LDCTL (C),HL
	pop bc		; restore reg
	pop hl
	ret

RxData  	equ 16h        	; on-chip UART receive register
TxData  	equ 18h        	; on-chip UART transmit register
RxStat  	equ 14h        	; on-chip UART transmitter status/control register
TxStat  	equ 12h        	; 0n-chip UART receiver status/control register

;Get a char from the console and echo
CIN:    
        	IN A,(RxStat)	; read on-chip UART receive status
        	AND 10H				;;Z data available?
        	JP Z,CIN
        	IN A,(RxData)	; save to reg A
        	OUT (TxData),A	; echo back
        	RET
; get char from console without echo
CINQ:
        	IN A,(RxStat)	; read on-chip UART receive status
        	AND 10H				;;Z data available?
        	JP Z,CINQ
        	IN A,(RxData)	; save to reg A
        	RET

;Output a character to the console
COUT:   
	push af		; save data to be printed to stack
COUT1:  	IN A,(TxStat)	; transmit empty?
        	AND 01H
        	JP Z,COUT1
	pop af		; restore data to be printed
        	OUT (TxData),A	; write it out
        	RET

; check UART output completed
COUTdone:
	in a,(TxStat)	; trasmit empty?
	and 1
	jp z,COUTdone	; wait until transmit empty
	ret

MMUtbl	ds 32		; 16 pages of system MMU page descriptors

;PROGEND:	equ $		; end of the program
PROGEND:	equ 0c000h		; end of the program is above the stack

signon$:	db "ZZ80 Monitor v0.28 8/22/18", 13,10,0
;        	db "Format drives command",13,10,0 
PROMPT$:	db 13, 10, 10, ">", 0
what$:   	db 13, 10, "?", 0
CRLF$	db 13,10,0
confirm$	db " press Return to execute command",0
abort$	db 13,10,"command aborted",0
notdone$	db 13,10,"command not implemented",0
go$	db "o to address: 0x",0
track$	db " track:0x",0
sector$	db " sector:0x",0
read$	db "ead RAM disk",0
RDmore$	db 10,13,"carriage return for next sector, any other key for command prompt",10,13,0
notsame$	db 10,13,"Data NOT same as previous read",10,13,0
issame$	db 10,13,"Data same as previous read",10,13,0
inport$	db "nput from port ",0
invalue$	db 10,13,"Value=",0
outport$	db "utput ",0
outport2$	db " to port ",0
listhex$	db "ist memory as Intel Hex, start address=",0
listhex1$	db " end address=",0
fillf$	db "ill memory with 0xFF",10,13,0
fill0$	db "ero memory",10,13,0
testram$	db "est memory",10,13,0
copycf$	db "opy to RAM disk",10,13
	db "0--boot,",10,13
;	db "1--User Apps,",10,13
	db "2--CP/M2.2:",10,13
;	db "3--CP/M3: ",0
	db 0
clrdir$	db " clear disk directories",10,13
	db "A -- drive A,",10,13
	db "B -- drive B:",10,13
;	db "C -- drive C,",10,13
;	db "D -- drive D,",10,13	
;	db "E -- RAM drive: ",0
	db 0
bootcpm$	db "oot CP/M",10,13
;	db "1--User Apps,",10,13
	db "2--CP/M2.2:",10,13
;	db "3--CP/M3: ",0
	db 0
HELP$	db "elp",13,10
	db "G <addr> CR",13,10
	db "R <track> <sector>",13,10
	db "D <start addr> <end addr>",13,10
	db "I <port>",13,10
	db "O <value> <port>",13,10
	db "L <start addr> <end addr>",13,10
	db "Z CR",13,10
	db "F CR",13,10
	db "T CR",13,10
	db "E <addr>",13,10
	db "X <options> CR",13,10
	db "B <options> CR",13,10
	db "C <options> CR",0

	END


