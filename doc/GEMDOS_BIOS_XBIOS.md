# Atari ST BASIC Programmer's Reference: GEMDOS, BIOS, and XBIOS System Calls

## 1. Introduction

The Atari ST BASIC interpreter provides three built-in functions -- `GEMDOS()`, `BIOS()`, and `XBIOS()` -- that give the programmer direct access to the operating system's low-level services. These functions invoke the M68000 trap mechanism:

- **GEMDOS()** executes **trap #1** -- the GEM Disk Operating System, handling file I/O, memory management, process control, and date/time services.
- **BIOS()** executes **trap #13** -- the Basic Input/Output System, providing low-level device I/O and disk access.
- **XBIOS()** executes **trap #14** -- the Extended BIOS, offering hardware-specific functions for screen, sound, keyboard, floppy, and MIDI control.

These functions allow BASIC programs to perform operations that would otherwise require assembly language or C, at the cost of requiring the programmer to understand the underlying OS interface.

---

## 2. Calling Convention

### Syntax

```
result% = GEMDOS(function_number [, arg1 [, arg2 [, ...]]])
result% = BIOS(function_number [, arg1 [, arg2 [, ...]]])
result% = XBIOS(function_number [, arg1 [, arg2 [, ...]]])
```

### Key Details

- **Function number is the FIRST argument** and must be an integer. It selects which OS function to invoke.
- **Parameters follow** in the order specified by the function's definition in the Atari ST documentation.
- **String parameters** are automatically converted from BASIC's internal backward (reversed) storage format to forward null-terminated C strings via an internal `mirror_str` routine before being pushed onto the stack.
- **Integer parameters** are pushed as either 16-bit words or 32-bit longwords, depending on the function's internal descriptor table.
- **The return value** is always an integer, taken from CPU register D0 after the trap returns.
- **The trap instruction is self-modifying**: the interpreter patches the trap vector number at runtime (trap #1, #13, or #14) into a code stub before executing it.
- **Parameters are collected left-to-right** from the BASIC expression, then **pushed right-to-left** onto the supervisor stack, following the standard M68000/C calling convention.

---

## 3. Parameter Types

Each supported function has a descriptor table that defines its parameter list. The descriptor entries use the following format:

| Descriptor Entry | Meaning | Stack Usage |
|---|---|---|
| `INT, 0` | Word parameter (16-bit integer) | 2 bytes on stack |
| `INT, 1` | Longword parameter (32-bit integer or address) | 4 bytes on stack |
| `STRING, 1` | String pointer (32-bit address of null-terminated string) | 4 bytes on stack; string auto-mirrored from BASIC format |
| `0` | End of parameter list | -- |

When calling from BASIC:

- Word parameters accept values in the range -32768 to 65535.
- Longword parameters accept full 32-bit values (addresses, large counts, etc.).
- String parameters can be passed as BASIC string variables or string literals; the interpreter handles the conversion to a C-style pointer automatically.
- Using `VARPTR(variable)` provides the memory address of a BASIC variable, useful for buffer parameters.

---

## 4. Error Handling

### Return Value Conventions

- A **non-negative return value** generally indicates success. For file operations, the return value is often a file handle or byte count.
- A **negative return value** indicates an error. The specific negative number identifies the error condition.

### BASIC Runtime Error

- **Error 32**: *"improper function number for gemdos/bios/xbios"* -- raised if the function number passed as the first argument is out of range or not in the interpreter's built-in descriptor table.

### GEMDOS Error Codes

See Section 8 for the full error code table.

---

## 5. GEMDOS Functions (Trap #1)

All 51 supported GEMDOS functions are listed below, organized by category.

### 5.1 Process Control

| # (Dec) | # (Hex) | Name | Parameters | Return Value | Description |
|---|---|---|---|---|---|
| 0 | $00 | Pterm0 | (none) | Does not return | Terminate program with exit code 0. |
| 49 | $31 | Ptermres | keepcnt (long), retcode (word) | Does not return | Terminate and stay resident. `keepcnt` is the number of bytes to keep; `retcode` is the exit code. |
| 76 | $4C | Pterm | retcode (word) | Does not return | Terminate program with exit code `retcode`. |

### 5.2 Character I/O

| # (Dec) | # (Hex) | Name | Parameters | Return Value | Description |
|---|---|---|---|---|---|
| 1 | $01 | Cconin | (none) | Longword: scancode in high word, ASCII in low byte | Read a character from the console (waits for input). |
| 2 | $02 | Cconout | ch (word) | 0 | Write character `ch` to the console. |
| 3 | $03 | Cauxin | (none) | Character read | Read a character from the auxiliary (serial) port. |
| 4 | $04 | Cauxout | ch (word) | 0 | Write character `ch` to the auxiliary (serial) port. |
| 5 | $05 | Cprnout | ch (word) | 0 or -1 | Write character `ch` to the printer. Returns -1 on timeout. |
| 6 | $06 | Crawio | ch (word) | Character or 0 | Raw console I/O. If `ch` = $FF, reads (returns 0 if no char). Otherwise writes `ch`. |
| 7 | $07 | Crawcin | (none) | Character read | Raw console input (no echo, no ^C checking). |
| 8 | $08 | Cnecin | (none) | Character read | Console input with no echo (but ^C is checked). |
| 9 | $09 | Cconws | string (string) | 0 | Write a null-terminated string to the console. |
| 10 | $0A | Cconrs | buf (long) | 0 | Read an edited string from the console into buffer at `buf`. First byte of buffer = max length. |
| 11 | $0B | Cconis | (none) | -1 if char ready, 0 if not | Check console input status. |
| 16 | $10 | Cconos | (none) | -1 if ready, 0 if not | Check console output status. |
| 17 | $11 | Cprnos | (none) | -1 if ready, 0 if not | Check printer output status. |
| 18 | $12 | Cauxis | (none) | -1 if char ready, 0 if not | Check auxiliary input status. |
| 19 | $13 | Cauxos | (none) | -1 if ready, 0 if not | Check auxiliary output status. |

### 5.3 Drive and Directory Operations

| # (Dec) | # (Hex) | Name | Parameters | Return Value | Description |
|---|---|---|---|---|---|
| 14 | $0E | Dsetdrv | drv (word) | Bitmap of available drives | Set current drive (0=A, 1=B, 2=C, ...). Returns a 32-bit bitmap where bit N = drive N present. |
| 25 | $19 | Dgetdrv | (none) | Current drive number | Get current drive (0=A, 1=B, 2=C, ...). |
| 57 | $39 | Dcreate | path (string) | 0 or negative error | Create a directory. |
| 58 | $3A | Ddelete | path (string) | 0 or negative error | Delete an empty directory. |
| 59 | $3B | Dsetpath | path (string) | 0 or negative error | Set current directory path. |
| 71 | $47 | Dgetpath | buf (long), drv (word) | 0 or negative error | Get current directory path into buffer. `drv`: 0=current, 1=A, 2=B, etc. |
| 54 | $36 | Dfree | buf (long), drv (word) | 0 or negative error | Get drive free space info. `drv`: 0=current, 1=A, etc. Buffer receives 4 longwords: free clusters, total clusters, bytes/sector, sectors/cluster. |

### 5.4 File Operations

| # (Dec) | # (Hex) | Name | Parameters | Return Value | Description |
|---|---|---|---|---|---|
| 60 | $3C | Fcreate | fname (string), attr (word) | Handle (>=0) or negative error | Create a new file. `attr`: 0=normal, 1=read-only, 2=hidden, 4=system, 32=archive. |
| 61 | $3D | Fopen | fname (string), mode (word) | Handle (>=0) or negative error | Open an existing file. `mode`: 0=read, 1=write, 2=read/write. |
| 62 | $3E | Fclose | handle (word) | 0 or negative error | Close a file handle. |
| 63 | $3F | Fread | handle (word), count (long), buf (long) | Bytes read (>=0) or negative error | Read `count` bytes from file into buffer at `buf`. |
| 64 | $40 | Fwrite | handle (word), count (long), buf (long) | Bytes written (>=0) or negative error | Write `count` bytes from buffer at `buf` to file. |
| 65 | $41 | Fdelete | fname (string) | 0 or negative error | Delete a file. |
| 66 | $42 | Fseek | offset (long), handle (word), seekmode (word) | New position or negative error | Seek within a file. `seekmode`: 0=from start, 1=from current, 2=from end. |
| 67 | $43 | Fattrib | fname (string), wflag (word), attr (word) | Attribute or negative error | Get/set file attributes. `wflag`: 0=read, 1=write. `attr`: see Fcreate. |
| 69 | $45 | Fdup | handle (word) | New handle or negative error | Duplicate a file handle (like dup() in Unix). |
| 70 | $46 | Fforce | stdh (word), nonstdh (word) | 0 or negative error | Force standard handle `stdh` to refer to `nonstdh` (like dup2()). |
| 78 | $4E | Fsfirst | fspec (string), attr (word) | 0 or negative error | Search for first matching file. Results placed in the DTA. `attr` selects file types to match. |
| 79 | $4F | Fsnext | (none) | 0 or negative error | Search for next matching file (continues Fsfirst). |
| 86 | $56 | Frename | zero (word), old (string), new (string) | 0 or negative error | Rename a file. `zero` must be 0 (reserved). |
| 87 | $57 | Fdatime | buf (long), handle (word), wflag (word) | 0 or negative error | Get/set file date and time. `wflag`: 0=read, 1=write. Buffer is 2 longwords (time, date). |

### 5.5 Memory Management

| # (Dec) | # (Hex) | Name | Parameters | Return Value | Description |
|---|---|---|---|---|---|
| 72 | $48 | Malloc | amount (long) | Address or 0 (failure) | Allocate `amount` bytes of memory. If `amount` = -1, returns the size of the largest free block. |
| 73 | $49 | Mfree | addr (long) | 0 or negative error | Free a previously allocated memory block at `addr`. |
| 74 | $4A | Mshrink | zero (word), addr (long), newsize (long) | 0 or negative error | Shrink a memory block. `zero` must be 0 (reserved). |

### 5.6 Date and Time

| # (Dec) | # (Hex) | Name | Parameters | Return Value | Description |
|---|---|---|---|---|---|
| 42 | $2A | Tgetdate | (none) | Packed date | Get current date. Format: bits 0-4 = day (1-31), bits 5-8 = month (1-12), bits 9-15 = year (offset from 1980). |
| 43 | $2B | Tsetdate | date (word) | 0 or negative error | Set current date in packed format (see Tgetdate). |
| 44 | $2C | Tgettime | (none) | Packed time | Get current time. Format: bits 0-4 = seconds/2 (0-29), bits 5-10 = minutes (0-59), bits 11-15 = hours (0-23). |
| 45 | $2D | Tsettime | time (word) | 0 or negative error | Set current time in packed format (see Tgettime). |

### 5.7 System Functions

| # (Dec) | # (Hex) | Name | Parameters | Return Value | Description |
|---|---|---|---|---|---|
| 32 | $20 | Super | stack (long) | Previous SSP or status | Enter/exit supervisor mode. `stack` = 0: enter supervisor mode (returns old SSP). `stack` = old SSP: return to user mode. `stack` = 1: inquire current mode. |
| 48 | $30 | Sversion | (none) | Version number | Get GEMDOS version. High byte = minor, low byte = major (e.g., $1300 = version 0.19). |
| 26 | $1A | Fsetdta | addr (long) | (void) | Set the Disk Transfer Address (DTA) used by Fsfirst/Fsnext. |
| 47 | $2F | Fgetdta | (none) | Address of current DTA | Get the current Disk Transfer Address. |
| 75 | $4B | Pexec | mode (word), fname (string), cmdline (string), envstr (string) | Exit code or negative error | Load and/or execute a program. `mode`: 0=load and execute, 3=load but don't execute, 4=just create basepage, 5=attach environment, 6=exec a created basepage. |

---

## 6. BIOS Functions (Trap #13)

### Device Codes

The BIOS character device functions use the following device numbers:

| Code | Device | Description |
|---|---|---|
| 0 | PRT | Parallel printer port (Centronics) |
| 1 | AUX | Auxiliary (RS-232 serial) port |
| 2 | CON | Console (screen + keyboard) |
| 3 | MIDI | MIDI port |
| 4 | KBD | Intelligent keyboard processor (IKBD) |

### Function Reference

| # | Name | Parameters | Return Value | Description |
|---|---|---|---|---|
| 0 | Getmpb | mpb (long) | (void) | Get the Memory Parameter Block. `mpb` is a pointer to a structure to fill. Used at boot; not typically called from applications. |
| 1 | Bconstat | dev (word) | -1 if char ready, 0 if not | Check if a character is available on device `dev`. |
| 2 | Bconin | dev (word) | Character read (longword) | Read a character from device `dev` (waits until available). For the console (dev=2), the high word contains the keyboard scan code. |
| 3 | Bconout | dev (word), ch (word) | 0 | Write character `ch` to device `dev`. |
| 4 | Rwabs | rwflag (word), buf (long), count (word), recno (word), dev (word) | 0 or negative error | Read/write absolute disk sectors. `rwflag`: 0=read, 1=write, 2=read (no media change check), 3=write (no media change check). Add 8 for no retries. `count` = number of sectors, `recno` = starting sector, `dev` = drive (0=A, 1=B, ...). |
| 5 | Setexc | vecnum (word), addr (long) | Old vector address | Set an exception vector. `vecnum` is the vector number (0-255). If `addr` = -1, just returns the current value without changing it. |
| 6 | Tickcal | (none) | Milliseconds per tick | Get the system timer calibration value (typically 20ms, i.e., 50 Hz). |
| 7 | Getbpb | dev (word) | Pointer to BPB or 0 | Get the BIOS Parameter Block for drive `dev` (0=A, 1=B, ...). Returns a pointer to a structure describing the disk format. |
| 8 | Bcostat | dev (word) | -1 if ready, 0 if not | Check if device `dev` is ready to accept output. |
| 9 | Mediach | dev (word) | 0, 1, or 2 | Check if the media has changed on drive `dev`. Returns 0=not changed, 1=maybe changed, 2=definitely changed. |
| 10 | Drvmap | (none) | Bitmap of available drives | Get a 32-bit bitmap of mounted drives. Bit 0 = drive A, bit 1 = drive B, etc. |
| 11 | Kbshift | mode (word) | Shift key state | Get/set the keyboard shift-key state. If `mode` = -1, returns the current state without modifying it. Otherwise sets the state to `mode`. See bit definitions in examples. |

### Kbshift Bit Definitions

| Bit | Mask | Key |
|---|---|---|
| 0 | $01 | Right Shift |
| 1 | $02 | Left Shift |
| 2 | $04 | Control |
| 3 | $08 | Alternate |
| 4 | $10 | Caps Lock |
| 5 | $20 | Right mouse button (on IKBD) |
| 6 | $40 | Left mouse button (on IKBD) |
| 7 | $80 | (Reserved) |

---

## 7. XBIOS Functions (Trap #14)

All 39 supported XBIOS functions are listed below. Function #11 is not defined.

### 7.1 Mouse and Keyboard

| # | Name | Parameters | Return Value | Description |
|---|---|---|---|---|
| 0 | Initmouse | type (word), param (long), vec (long) | (void) | Initialize the mouse handler. `type`: 0=disable, 1=relative, 2=absolute, 3=unused, 4=keyboard mode. `param` = pointer to mouse parameter block, `vec` = pointer to handler routine. |
| 24 | Bioskeys | (none) | (void) | Reset the keyboard translation tables to their default (power-up) state. |
| 25 | Ikbdws | count (word), buf (long) | (void) | Write `count`+1 bytes from buffer at `buf` to the IKBD (intelligent keyboard controller). |
| 35 | Kbrate | initial (word), repeat (word) | Current rate | Set keyboard repeat rate. `initial` = initial delay, `repeat` = repeat rate (in 20ms units). Pass -1 for either to leave unchanged. Returns packed word: initial in high byte, repeat in low byte. |

### 7.2 Screen and Display

| # | Name | Parameters | Return Value | Description |
|---|---|---|---|---|
| 2 | Physbase | (none) | Address | Get the physical screen base address (the address the video shifter reads from). |
| 3 | Logbase | (none) | Address | Get the logical screen base address (the address the VDI writes to). |
| 4 | Getrez | (none) | Resolution code | Get current screen resolution. 0=low (320x200, 16 colors), 1=medium (640x200, 4 colors), 2=high (640x400, monochrome). |
| 5 | Setscreen | laddr (long), paddr (long), rez (word) | (void) | Set screen addresses and/or resolution. Pass -1 for any parameter to leave unchanged. **Warning**: changing resolution reinitializes the screen. |
| 6 | Setpalette | palette (long) | (void) | Set all 16 palette registers at once. `palette` points to an array of 16 words in $0RGB format. |
| 7 | Setcolor | colornum (word), color (word) | Previous color value | Get/set a single palette color. `colornum` = 0-15. `color` in $0RGB format (each nibble 0-7). Pass -1 for `color` to read without changing. |
| 21 | Cursconf | func (word), rate (word) | Depends on func | Configure the text cursor. `func`: 0=hide, 1=show, 2=blink on, 3=blink off, 4=set blink rate, 5=get blink rate. `rate` used only with func=4. |
| 37 | Vsync | (none) | (void) | Wait for the next vertical blank interrupt (synchronize with display refresh). |

### 7.3 Sound (PSG / Yamaha YM2149)

| # | Name | Parameters | Return Value | Description |
|---|---|---|---|---|
| 28 | Giaccess | data (word), register (word) | Register value | Read/write a PSG (Yamaha YM2149) sound chip register. `register`: 0-15 selects the register. Set bit 7 of `register` to write (`register` OR $80); clear bit 7 to read. `data` is the value to write (ignored on read). |
| 29 | Offgibit | bitno (word) | (void) | Clear (turn off) a bit in PSG register A (port A). `bitno` is the bit mask with the bit(s) to clear. |
| 30 | Ongibit | bitno (word) | (void) | Set (turn on) a bit in PSG register A (port A). `bitno` is the bit mask with the bit(s) to set. |
| 32 | Dosound | cmdaddr (long) | (void) | Play a sound using the PSG. `cmdaddr` points to a command list in memory (a byte sequence of register/value pairs terminated by special codes). |

### 7.4 Floppy Disk

| # | Name | Parameters | Return Value | Description |
|---|---|---|---|---|
| 8 | Floprd | buf (long), filler (long), dev (word), sect (word), track (word), side (word), count (word) | 0 or negative error | Read sectors from floppy. `buf` = buffer address, `filler` = reserved (0), `dev` = drive (0=A, 1=B), `sect` = starting sector (1-based), `track` = track number, `side` = 0 or 1, `count` = number of sectors. |
| 9 | Flopwr | buf (long), filler (long), dev (word), sect (word), track (word), side (word), count (word) | 0 or negative error | Write sectors to floppy. Parameters same as Floprd. |
| 10 | Flopfmt | buf (long), filler (long), dev (word), spt (word), track (word), side (word), interlv (word), magic (long), virgin (word) | 0 or negative error | Format a floppy track. `spt` = sectors per track, `interlv` = interleave factor, `magic` = $87654321, `virgin` = fill pattern (usually $E5E5). |
| 19 | Flopver | buf (long), filler (long), dev (word), sect (word), track (word), side (word), count (word) | 0 or negative error | Verify floppy sectors. Parameters same as Floprd. Returns 0 if sectors match buffer contents. |
| 18 | Protobt | buf (long), serialno (long), disktype (word), execflag (word) | (void) | Prototype a boot sector in buffer. `serialno` = serial number (-1 = keep), `disktype` = -1=keep, 0=SS/40trk, 1=DS/40trk, 2=SS/80trk, 3=DS/80trk. `execflag` = 0=non-executable, 1=executable. |

### 7.5 MIDI

| # | Name | Parameters | Return Value | Description |
|---|---|---|---|---|
| 12 | Midiws | cnt (word), buf (long) | (void) | Write `cnt`+1 bytes from buffer at `buf` to the MIDI port. |

### 7.6 Serial / RS-232

| # | Name | Parameters | Return Value | Description |
|---|---|---|---|---|
| 15 | Rsconf | baud (word), ctr (word), ucr (word), rsr (word), tsr (word), scr (word) | (void) | Configure the RS-232 port. Pass -1 for any parameter to leave unchanged. `baud`: 0=19200, 1=9600, 2=4800, 3=2400, 4=2000, 5=1800, 6=1200, 7=600, 8=300, 9=200, 10=150, 11=134, 12=110, 13=75, 14=50. `ctr`/`ucr`/`rsr`/`tsr`/`scr` are MFP register values. |

### 7.7 Interrupts and Timers

| # | Name | Parameters | Return Value | Description |
|---|---|---|---|---|
| 13 | Mfpint | intno (word), vector (long) | (void) | Install a handler for an MFP (68901) interrupt. `intno` = MFP interrupt number (0-15), `vector` = address of handler routine. |
| 14 | Iorec | dev (word) | Pointer to IOREC structure | Get the I/O record (ring buffer descriptor) for a device. `dev`: 0=RS-232, 1=keyboard, 2=MIDI. |
| 26 | Jdisint | intno (word) | (void) | Disable an MFP interrupt. `intno` = MFP interrupt number (0-15). |
| 27 | Jenabint | intno (word) | (void) | Enable an MFP interrupt. `intno` = MFP interrupt number (0-15). |
| 31 | Xbtimer | timer (word), control (word), data (word), vector (long) | (void) | Set up an MFP timer. `timer`: 0=A, 1=B, 2=C, 3=D. `control` and `data` are the MFP timer control and data register values. `vector` = handler address. |

### 7.8 Keyboard Tables

| # | Name | Parameters | Return Value | Description |
|---|---|---|---|---|
| 16 | Keytbl | unshift (long), shift (long), capslock (long) | Pointer to key table structure | Set/get keyboard translation tables. Pass -1 for any pointer to leave that table unchanged. Returns pointer to a structure containing all three table pointers. |

### 7.9 System and Miscellaneous

| # | Name | Parameters | Return Value | Description |
|---|---|---|---|---|
| 1 | Ssbrk | amount (word) | Address or error | Reserve memory at the top of RAM (used at boot time). Not generally useful for applications. |
| 17 | Random | (none) | 24-bit random number | Return a pseudo-random number in the range 0 to $00FFFFFF (0 to 16777215). |
| 20 | Scrdmp | (none) | (void) | Trigger a screen dump to the printer (same as pressing the PrintScreen key). |
| 22 | Settime | time (long) | (void) | Set the hardware real-time clock. `time` is packed: bits 0-4 = seconds/2, bits 5-10 = minutes, bits 11-15 = hours, bits 16-20 = day, bits 21-24 = month, bits 25-31 = year (from 1980). |
| 23 | Gettime | (none) | Packed date/time longword | Get the hardware real-time clock. Format same as Settime. |
| 33 | Setprt | config (word) | Previous config | Set/get printer configuration. Pass -1 to read without changing. Bits: 0=dot matrix(0)/daisy(1), 1=color(0)/mono(1), 2=Atari(0)/Epson(1), 3=draft(0)/final(1), 4=parallel(0)/serial(1), 5-15=reserved. |
| 34 | Kbdvbase | (none) | Pointer to KBDVECS structure | Get the pointer to the keyboard/MIDI vector table. The structure contains addresses of routines for handling keyboard and MIDI events. |
| 36 | Prtblk | pblk (long) | 0 or negative error | Print a screen block. `pblk` points to a parameter block defining the area to print. |
| 38 | Supexec | addr (long) | (void) | Execute a routine in supervisor mode. `addr` is the address of the routine to call. The routine runs with full supervisor privileges. |
| 39 | Puntaes | (none) | Does not return | Discard the AES and attempt to reboot into a non-GEM environment. Frees the memory used by the AES. |

---

## 8. GEMDOS Error Codes

| Code | Symbolic Name | Description |
|---|---|---|
| -1 | ERROR | Generic error |
| -2 | EDRVNR | Drive not ready |
| -3 | EUNCMD | Unknown command |
| -4 | E_CRC | CRC error (data integrity check failed) |
| -5 | EBADRQ | Bad request |
| -6 | E_SEEK | Seek error |
| -7 | EMEDIA | Unknown media (unrecognized disk format) |
| -8 | ESECNF | Sector not found |
| -9 | EPAPER | Out of paper |
| -10 | EWRITF | Write fault |
| -11 | EREADF | Read fault |
| -12 | EGENRL | General error (miscellaneous hardware failure) |
| -13 | EWRPRO | Write protected media |
| -14 | E_CHNG | Media change detected |
| -15 | EUNDEV | Unknown device |
| -16 | EBADSF | Bad sectors on format |
| -17 | EOTHER | Insert other disk (request for media swap) |
| -32 | EINVFN | Invalid function number |
| -33 | EFILNF | File not found |
| -34 | EPTHNF | Path not found |
| -35 | ENHNDL | No more handles (too many open files) |
| -36 | EACCDN | Access denied |
| -37 | EIHNDL | Invalid handle |
| -39 | ENSMEM | Insufficient memory |
| -40 | EIMBA | Invalid memory block address |
| -46 | EDRIVE | Invalid drive specification |
| -48 | ENSAME | Not the same drive (cross-device rename) |
| -49 | ENMFIL | No more files (Fsnext: no further matches) |
| -64 | ERANGE | Range error |
| -65 | EINTRN | Internal error (GEMDOS internal failure) |
| -66 | EPLFMT | Invalid program load format (bad executable) |
| -67 | EGSBF | Memory block growth failure (Mshrink error) |

---

## 9. Practical Examples

### File I/O: Create and Write

```basic
REM === File I/O Example ===
10 REM Create and write to a file
20 handle% = GEMDOS($3C, "TEST.DAT", 0)  : REM Fcreate
30 IF handle% < 0 THEN PRINT "Error!": STOP
40 a$ = "Hello, World!"
50 result% = GEMDOS($40, handle%, 13, VARPTR(a$))  : REM Fwrite
60 result% = GEMDOS($3E, handle%)  : REM Fclose
```

### Screen Resolution Query

```basic
REM === Screen Resolution ===
10 rez% = XBIOS(4)  : REM Getrez
20 IF rez% = 0 THEN PRINT "Low (320x200, 16 colors)"
30 IF rez% = 1 THEN PRINT "Medium (640x200, 4 colors)"
40 IF rez% = 2 THEN PRINT "High (640x400, mono)"
```

### Keyboard Modifier State

```basic
REM === Keyboard State ===
10 state% = BIOS(11, -1)  : REM Kbshift(-1) = read current state
20 IF state% AND 1 THEN PRINT "Right Shift pressed"
30 IF state% AND 2 THEN PRINT "Left Shift pressed"
40 IF state% AND 4 THEN PRINT "Control pressed"
50 IF state% AND 8 THEN PRINT "Alternate pressed"
```

### Get System Date

```basic
REM === Get System Date/Time ===
10 date% = GEMDOS($2A)  : REM Tgetdate
20 day% = date% AND 31
30 month% = (date%/32) AND 15
40 year% = (date%/512) + 1980
50 PRINT "Date: "; day%; "/"; month%; "/"; year%
```

### Palette Color Manipulation

```basic
REM === Set Palette Color ===
10 old% = XBIOS(7, 0, -1)       : REM Read color 0 (background)
20 result% = XBIOS(7, 0, $700)  : REM Set color 0 to red ($RGB)
30 WAIT 100                       : REM Wait ~1.4 seconds
40 result% = XBIOS(7, 0, old%)  : REM Restore original color
```

### Sound via PSG Chip

```basic
REM === Sound Example (PSG chip) ===
10 REM Set channel A frequency via Giaccess
20 result% = XBIOS(28, 200, 0)  : REM Register 0: fine tune = 200
30 result% = XBIOS(28, 0, 1)    : REM Register 1: coarse tune = 0
40 result% = XBIOS(28, $3E, 7)  : REM Register 7: mixer - enable tone A only
50 result% = XBIOS(28, 15, 8)   : REM Register 8: channel A volume = 15 (max)
60 WAIT 200                       : REM Play for ~2.8 seconds
70 result% = XBIOS(28, 0, 8)    : REM Channel A volume = 0 (off)
```

### Random Numbers from XBIOS

```basic
REM === Random Number from XBIOS ===
10 FOR i% = 1 TO 10
20   r% = XBIOS(17)  : REM Random - 24-bit random number
30   PRINT r%
40 NEXT i%
```

### Directory Operations

```basic
REM === Directory Operations ===
10 result% = GEMDOS($39, "NEWDIR")  : REM Dcreate - create directory
20 result% = GEMDOS($3B, "NEWDIR")  : REM Dsetpath - change into it
30 PRINT "Current drive: "; CHR$(GEMDOS($19) + 65)  : REM Dgetdrv
```

---

## Notes

- **Supervisor mode**: Some XBIOS functions (particularly Supexec) execute code in supervisor mode. Use with extreme caution -- a crash in supervisor mode will lock the machine.
- **Buffer addresses**: When a function requires a buffer pointer, use `VARPTR()` to obtain the address of a BASIC variable, or use `GEMDOS($48, size)` (Malloc) to allocate a dedicated buffer.
- **String mirroring**: The BASIC interpreter stores strings in reversed byte order internally. The `GEMDOS()`, `BIOS()`, and `XBIOS()` functions automatically reverse strings passed as `STRING` type parameters so the OS receives them in the correct forward order. This does **not** apply to raw buffer pointers passed as longword integers.
- **Word vs. longword**: Passing a longword value where a word is expected (or vice versa) will corrupt the stack and likely crash the system. Always verify the parameter types against the function's descriptor table.
- **Floppy operations**: Floprd, Flopwr, Flopfmt, and Flopver bypass the filesystem entirely and access raw disk sectors. Incorrect use can destroy data.
- **Pexec**: Loading and executing programs from within BASIC may interfere with the interpreter's own memory management. Use with caution.
