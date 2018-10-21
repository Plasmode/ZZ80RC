# ZZ80Mon (ZZ80 Monitor) V0.23 Manual

Aug 2018
## Introduction

ZZ80Mon is the monitor program for ZZ80RC. Once installed in physical page 0, it is the program Z280 executes immediately after reset. ZZ80Mon will first copies itself to 0xB000-0xBFFF and jump to 0xB400. It then enables the MMU and maps physical page 0x3C000 to logical page 0 thus protects the physical page 0 from alteration. It then display a command prompt for user inputs. The MMU is disabled with power-on reset or manual reset, so Z280 will always boot from physical page 0.

When ZZ80RC board is powered up the very first time, the Bootstrap jumper should be set to T10-T11 to enable UART bootstrap mode. In this mode ZZ80Mon can be loaded into memory using procedure outlined in Getting Started guide. Once ZZ80Mon is installed, the Bootstrap jumper should be set to T9-T10 for RAM bootstrap mode.
## ZZ80Mon commands

ZZMon is a simple monitor with the following single-key commands. Except when noted, the commands may be entered in upper or lower cases. In the following description, command entered is in bold, the response is in `code section`

**H**
```
help
G <addr> CR
R <track> <sector>
D <start addr> <end addr>
Z CR
F CR
T CR
E <addr>
X <options> CR
B <options> CR
C <options> CR
```
**G**
```
go to address: 0x
```
Enter the 4 hexadecimal address values. Confirm the command execution with a carriage return or abort the command with other keystroke.

**R**
```
read RAMdisk track:0x
```
Enter the 2 hexadecimal digits for the track number and 2 hex digits for the sector value. The content of the selected track/sector will be displayed as 512-byte data block.
```
read RAMdisk track:0x00 sector:0x00 data not same as previous read

1000 : 21 00 10 36 3E 23 36 40 23 36 D3 23 36 CD 23 36

1010 : 16 23 36 F8 23 36 21 23 36 00 23 36 04 23 36 0E
1020 : 23 36 C0 23 36 3E 23 36 01 23 36 D3 23 36 C5 23
1030 : 36 7A 23 36 FE 23 36 FE 23 36 CA 23 36 00 23 36
1040 : 04 23 36 D3 23 36 C7 23 36 3E 23 36 20 23 36 D3
1050 : 23 36 CF 23 36 DB 23 36 CF 23 36 E6 23 36 08 23
1060 : 36 CA 23 36 1B 23 36 10 23 36 06 23 36 00 23 36
1070 : ED 23 36 92 23 36 DB 23 36 CF 23 36 14 23 36 C3
1080 : 23 36 0B 23 36 10 C3 00 10 00 00 00 00 00 00 00
1090 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
10A0 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
10B0 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
10C0 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
10D0 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
10E0 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
10F0 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
1100 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
1110 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
1120 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
1130 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
1140 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
1150 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
1160 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
1170 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
1180 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
1190 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
11A0 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
11B0 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
11C0 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
11D0 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
11E0 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
11F0 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```
The address field in the first column is that of the buffer where sector data is stored.

**D**  
Display memory from 4 hexadecimal digits start address to 4 hexadecimal end address. If start address is greater than the end address, only 1 line (16 bytes) of data will be displayed.
```
D 0400 0420

0400 : C3 09 04 88 B0 FB 00 00 00 31 FF 0F 0E 08 2E FF
0410 : ED 6E DB E8 32 03 04 3E B0 D3 E8 DB E8 32 04 04
0420 : 2E 00 ED 6E D3 A0 CD 54 0A 3E E2 D3 10 3E 80 D3
```
**Z**
```
zero memory
press Return to execute command
```
Fill memory from 0xC000 to 0xFFFE and from 0x0 to 0xAFFF with 0x0. Press carriage return to confirm the command execution; press other key to abort the command

**F**
```
fill memory with 0xFF
press Return to execute command
```
Fill memory from 0xC000 to 0xFFFE and from 0x0 to 0xAFFF with 0xFF. Press carriage return to confirm the command execution; press other key to abort the command

**T**
```
test memory
press Return to execute command
```
Test memory from 0xC000 to 0xFFFE and from 0x0 to 0xAFFF. The memory is filled with unique test patterns generated from a seed value. The seed value is changed for each iteration of the test. Each completed iteration will display an 'OK' message. Any keystroke during the test with abort the test and return to command prompt.

**E**  
Edit memory specified with the 4 hexadecimal digits value. Exit the edit session with 'X'
```
E 0000

0000 : FF 12 12
0001 : FF 23 23
0002 : EF 00 00
0003 : 7F 01 01
0004 : F7 x
```
**X**
```
clear disk directories
A – drive A,
B – drive B,
```
Fill the directories of the selected disk with 0xE5. This effectively erase the entire disk. The disk letter must be in upper case. Confirm the command with a carriage return or abort command with any other key stroke.

**B**
```
boot CP/M
2–CP/M2.2,
```
Enter '2' to boot CP/M 2.2 (it is the only option for now). This assumes the appropriate software has been copied to RAM disk as described under the “C” command. Confirm the command with a carriage return or abort command with any other key stroke.
```
boot CP/M
2–CP/M2.2,
2 press Return to execute command
Copyright 1979 © by Digital Research
CP/M 2.2 for ZZ80RC
8/12/18 v1.1

a>
```
**C**
```
copy to CF
0–boot,
2–CP/M2.2,
```
Prior to execution of the C2 command, CP/M2.2 BDOS/CCP/BIOS must be loaded in memory 0xDC00-0xFFFF.
***
Physical location of programs on 512K RAM:

* ZZ80Mon: 0x0-0xFFF
* ZZ80CPM22: 0x3D000-0x3FFFF
* Drive A: 0x10000-0x3BFFF
* Drive B: 0x40000-0x7FFFF

With MMU turned on:  
    - logical page 0 is 0x3C000-0x3CFFF
    - logical page 1 is 0x1000-0x1FFF
    - logical page 2 is 0x2000-0x2FFF
    so on up to
    - logica page F is 0xF000-0xFFFF

