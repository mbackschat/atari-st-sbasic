# GEM AES, VDI, and Line-A Graphics -- Programmer's Reference

## For the Atari ST BASIC Interpreter (STAD BASIC, November 1988)

This document describes how to access GEM AES, GEM VDI, and Line-A graphics
functions from within the BASIC interpreter. All information is derived from
the reverse-engineered source code (`BASIC_COMMENTS.S`, `HEADER.S`).

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [AES (Application Environment Services)](#2-aes-application-environment-services)
   - 2.1 AES Arrays
   - 2.2 AES Parameter Block
   - 2.3 AES Control Array Format
   - 2.4 Complete AES Function Reference
   - 2.5 AES Examples
3. [VDI (Virtual Device Interface)](#3-vdi-virtual-device-interface)
   - 3.1 VDI Arrays
   - 3.2 VDI Parameter Block
   - 3.3 VDI Control Array Format
   - 3.4 Key VDI Functions
   - 3.5 VDI Examples
4. [Line-A Graphics](#4-line-a-graphics)
   - 4.1 Overview
   - 4.2 The LINE Command
   - 4.3 Line-A Initialization
   - 4.4 Complete Line-A Opcode Table
   - 4.5 Key Line-A Variable Offsets
   - 4.6 Accessing Line-A from BASIC
5. [Practical Programming Patterns](#5-practical-programming-patterns)
   - 5.1 GEM Application Skeleton
   - 5.2 Common Patterns
6. [Reference: AES Function Numbers Quick Table](#6-reference-aes-function-numbers-quick-table)
7. [Reference: VDI Function Numbers Quick Table](#7-reference-vdi-function-numbers-quick-table)

---

## 1. Introduction

The BASIC interpreter provides built-in access to the three graphics and UI
subsystems of the Atari ST:

- **GEM AES** (Application Environment Services) -- window management, menus,
  dialogs, event handling, and other desktop UI operations.
- **GEM VDI** (Virtual Device Interface) -- device-independent drawing
  primitives: lines, polygons, text, fill patterns, raster operations.
- **Line-A** -- direct hardware-level graphics via special 68000 opcodes
  ($A000-$A00F), bypassing GEM for maximum speed.

The interpreter exposes AES and VDI through dedicated array commands and
execution commands (`AES`, `VDI`). Each array corresponds to one of the
parameter arrays in the AES or VDI parameter blocks. Line-A is available
through the `LINE` command (which calls opcode $A003) and can be further
manipulated via `LPEEK` and `LPOKE` on the Line-A variable block.

### Key Concepts

- AES/VDI arrays are **commands** when used standalone (they write values)
  and **functions** when used inside an expression (they read values). The
  interpreter checks the internal `cmdfktfl` flag to distinguish the two
  modes.
- Multiple index/value pairs can be passed in a single command, separated
  by commas.
- The `AES` and `VDI` commands accept optional inline parameters that fill
  the control array sequentially before executing the trap.
- Line-A is initialized automatically at interpreter startup. The `LINE`
  command uses the stored Line-A variable block pointer.

---

## 2. AES (Application Environment Services)

### 2.1 AES Arrays

The interpreter provides six array interfaces for AES. Each array resides in
the BSS section and is pointed to by the AESPB parameter block.

#### AESCTRL -- AES Control Array (10 words)

```
Command:  AESCTRL index, value [, index, value ...]
Function: AESCTRL(index)
```

Sets or reads entries in the AES control array. The control array has 10
word-sized entries (indices 0-9). When used as a command, writes index/value
pairs. When used as a function (in an expression), reads the word at the
given index and returns it as a sign-extended integer.

#### AESINTIN -- AES Integer Input Array (128 words)

```
Command:  AESINTIN index, value [, index, value ...]
```

Write-only command. Sets word-sized entries in the AES integer input array.
Supports up to 128 entries (indices 0-127). Multiple index/value pairs can
be written in a single statement.

#### AESINTOUT -- AES Integer Output Array (128 words)

```
Function: AESINTOUT(index)
```

Read-only function. Returns the sign-extended word value at the given index
in the AES integer output array. This array is filled by the AES after an
`AES` call.

#### AESADRIN -- AES Address Input Array (128 longs)

```
Command:  AESADRIN index, value [, index, value ...]
```

Write-only command. Sets entries in the AES address input array. The array
consists of 128 longword entries. Each entry is indexed by number (0-127).

**Implementation note:** The write path stores `fac1+2` (the lower 16 bits
of the evaluated integer expression) as a word at the base of each longword
slot. For full 32-bit addresses, BASIC integers must be large enough, and the
programmer should be aware that the write uses `move.w` to the element
address, which in big-endian 68000 writes to the high word of the longword.
To store a full 32-bit address, use `VARPTR()` to obtain pointers, as the
interpreter's integer type carries 32-bit values internally through `fac1`.

#### AESADROUT -- AES Address Output Array (128 longs)

```
Function: AESADROUT(index)
```

Read-only function. Returns the full 32-bit longword value at the given index
in the AES address output array. The read path correctly returns the full
longword (`move.l`).

#### AES -- Execute AES Call

```
Command:  AES [param0, param1, param2, ...]
```

Executes the AES call by issuing `trap #2` with `d0 = $C8` and
`d1 = address of AESPB`. If inline parameters are provided, they are stored
sequentially as words in the AES control array (up to 10 entries) before
the trap is issued. Double commas (`,,`) skip a slot, leaving its previous
value intact.

The `AES` command can be used in two ways:

1. **Pre-filled arrays:** Set up AESCTRL, AESINTIN, and AESADRIN first, then
   call `AES` with no parameters.
2. **Inline control:** Pass control values directly: `AES 52, 1, 1, 1, 0`
   fills control[0..4] and then executes.

#### AESglobal -- AES Global Array (10 longs)

The AES global array occupies 10 longwords (40 bytes) in BSS. It is filled
by `appl_init` (AES function 10) and contains application-wide information
such as the AES version number, application ID, and resource pointers. It is
not directly accessible as a named BASIC command, but its address is part of
the AESPB and it is populated automatically when `appl_init` is called.

### 2.2 AES Parameter Block

The AESPB is a fixed structure in the data section containing six longword
pointers:

```
AESPB:
  .dc.l  AESctrl       ;  [0] -> AES control array (10 words)
  .dc.l  AESglobal     ;  [4] -> AES global array (10 longs)
  .dc.l  AESintin      ;  [8] -> AES integer input (128 words)
  .dc.l  AESintout     ; [12] -> AES integer output (128 words)
  .dc.l  AESadrin      ; [16] -> AES address input (128 longs)
  .dc.l  AESadrout     ; [20] -> AES address output (128 longs)
```

When `AES` is executed, the interpreter loads:
- `d1` = address of AESPB
- `d0` = $C8 (AES function dispatcher code)
- Then executes `trap #2`

### 2.3 AES Control Array Format

The control array tells the AES dispatcher which function to call and how
many parameters to expect in each array:

```
control[0] = AES function opcode (e.g., 10 for appl_init)
control[1] = sintin:  number of words in AESINTIN used as input
control[2] = sintout: number of words in AESINTOUT returned
control[3] = saddrin: number of longs in AESADRIN used as input
control[4] = saddrout: number of longs in AESADROUT returned
control[5..9] = (reserved / unused by most functions)
```

### 2.4 Complete AES Function Reference

Each row shows: opcode, function name, and the four size values that must be
placed in `control[1..4]` (sintin, sintout, saddrin, saddrout).

#### Application Management

| Opcode | Name | sintin | sintout | saddrin | saddrout | Description |
|-------:|------|-------:|--------:|--------:|---------:|-------------|
| 10 | appl_init | 0 | 1 | 0 | 0 | Initialize application, get ap_id |
| 11 | appl_read | 2 | 1 | 1 | 0 | Read from message pipe |
| 12 | appl_write | 2 | 1 | 1 | 0 | Write to message pipe |
| 13 | appl_find | 0 | 1 | 1 | 0 | Find application by name |
| 19 | appl_exit | 0 | 1 | 0 | 0 | Terminate application |

#### Event Handling

| Opcode | Name | sintin | sintout | saddrin | saddrout | Description |
|-------:|------|-------:|--------:|--------:|---------:|-------------|
| 20 | evnt_keybd | 0 | 1 | 0 | 0 | Wait for keyboard event |
| 21 | evnt_button | 3 | 5 | 0 | 0 | Wait for mouse button event |
| 22 | evnt_mouse | 5 | 5 | 0 | 0 | Wait for mouse enter/leave rectangle |
| 23 | evnt_mesag | 0 | 1 | 1 | 0 | Wait for message event |
| 24 | evnt_timer | 2 | 1 | 0 | 0 | Wait for timer event |
| 25 | evnt_multi | 16 | 7 | 1 | 0 | Wait for multiple events |
| 26 | evnt_dclick | 2 | 1 | 0 | 0 | Set/get double-click speed |

#### Menu Operations

| Opcode | Name | sintin | sintout | saddrin | saddrout | Description |
|-------:|------|-------:|--------:|--------:|---------:|-------------|
| 30 | menu_bar | 1 | 1 | 1 | 0 | Show/hide menu bar |
| 31 | menu_icheck | 2 | 1 | 1 | 0 | Check/uncheck menu item |
| 32 | menu_ienable | 2 | 1 | 1 | 0 | Enable/disable menu item |
| 33 | menu_tnormal | 2 | 1 | 1 | 0 | Normal/reverse menu title |
| 34 | menu_text | 1 | 1 | 2 | 0 | Change menu item text |
| 35 | menu_register | 1 | 1 | 1 | 0 | Register desk accessory name |

#### Object Operations

| Opcode | Name | sintin | sintout | saddrin | saddrout | Description |
|-------:|------|-------:|--------:|--------:|---------:|-------------|
| 40 | objc_add | 2 | 1 | 1 | 0 | Add object to tree |
| 41 | objc_delete | 1 | 1 | 1 | 0 | Delete object from tree |
| 42 | objc_draw | 6 | 1 | 1 | 0 | Draw object tree |
| 43 | objc_find | 4 | 1 | 1 | 0 | Find object at coordinates |
| 44 | objc_offset | 1 | 3 | 1 | 0 | Get object absolute position |
| 45 | objc_order | 2 | 1 | 1 | 0 | Reorder object in tree |
| 46 | objc_edit | 4 | 2 | 1 | 0 | Edit text in object |
| 47 | objc_change | 8 | 1 | 1 | 0 | Change object state and redraw |

#### Form Management

| Opcode | Name | sintin | sintout | saddrin | saddrout | Description |
|-------:|------|-------:|--------:|--------:|---------:|-------------|
| 50 | form_do | 1 | 1 | 1 | 0 | Handle dialog interaction |
| 51 | form_dial | 9 | 1 | 0 | 0 | Reserve/release screen for dialog |
| 52 | form_alert | 1 | 1 | 1 | 0 | Display alert box |
| 53 | form_error | 1 | 1 | 0 | 0 | Display system error alert |
| 54 | form_center | 0 | 5 | 1 | 0 | Center dialog on screen |
| 55 | form_keybd | 3 | 3 | 1 | 0 | Handle keyboard in dialog |
| 56 | form_button | 2 | 2 | 1 | 0 | Handle button click in dialog |

#### Graphics Utilities

| Opcode | Name | sintin | sintout | saddrin | saddrout | Description |
|-------:|------|-------:|--------:|--------:|---------:|-------------|
| 70 | graf_rubberbox | 4 | 3 | 0 | 0 | Rubber-band box |
| 71 | graf_dragbox | 8 | 3 | 0 | 0 | Drag box within bounds |
| 72 | graf_movebox | 6 | 1 | 0 | 0 | Animate box movement |
| 73 | graf_growbox | 8 | 1 | 0 | 0 | Animate box growing |
| 74 | graf_shrinkbox | 8 | 1 | 0 | 0 | Animate box shrinking |
| 75 | graf_watchbox | 4 | 1 | 1 | 0 | Watch for mouse in/out of object |
| 76 | graf_slidebox | 3 | 1 | 1 | 0 | Slide box within parent |
| 77 | graf_handle | 0 | 5 | 0 | 0 | Get VDI workstation handle |
| 78 | graf_mouse | 1 | 1 | 1 | 0 | Set mouse cursor form |
| 79 | graf_mkstate | 0 | 5 | 0 | 0 | Get mouse/keyboard state |

#### Clipboard (Scrap)

| Opcode | Name | sintin | sintout | saddrin | saddrout | Description |
|-------:|------|-------:|--------:|--------:|---------:|-------------|
| 80 | scrp_read | 0 | 1 | 1 | 0 | Read clipboard path |
| 81 | scrp_write | 0 | 1 | 1 | 0 | Set clipboard path |

#### File Selector

| Opcode | Name | sintin | sintout | saddrin | saddrout | Description |
|-------:|------|-------:|--------:|--------:|---------:|-------------|
| 90 | fsel_input | 0 | 2 | 2 | 0 | File selector dialog |
| 91 | fsel_exinput | 0 | 2 | 3 | 0 | File selector with title (TOS 1.4+) |

#### Window Management

| Opcode | Name | sintin | sintout | saddrin | saddrout | Description |
|-------:|------|-------:|--------:|--------:|---------:|-------------|
| 100 | wind_create | 5 | 1 | 0 | 0 | Create window |
| 101 | wind_open | 5 | 1 | 0 | 0 | Open (display) window |
| 102 | wind_close | 1 | 1 | 0 | 0 | Close window |
| 103 | wind_delete | 1 | 1 | 0 | 0 | Delete window |
| 104 | wind_get | 2 | 5 | 0 | 0 | Get window attributes |
| 105 | wind_set | 6 | 1 | 0 | 0 | Set window attributes |
| 106 | wind_find | 2 | 1 | 0 | 0 | Find window at coordinates |
| 107 | wind_update | 1 | 1 | 0 | 0 | Begin/end window update |
| 108 | wind_calc | 6 | 5 | 0 | 0 | Calculate window rectangles |
| 109 | wind_new | 0 | 1 | 0 | 0 | Delete all windows (TOS 1.4+) |

#### Resource Management

| Opcode | Name | sintin | sintout | saddrin | saddrout | Description |
|-------:|------|-------:|--------:|--------:|---------:|-------------|
| 110 | rsrc_load | 0 | 1 | 1 | 0 | Load resource file |
| 111 | rsrc_free | 0 | 1 | 0 | 0 | Free resource data |
| 112 | rsrc_gaddr | 2 | 1 | 0 | 1 | Get resource address |
| 113 | rsrc_saddr | 2 | 1 | 1 | 0 | Set resource address |
| 114 | rsrc_obfix | 1 | 1 | 1 | 0 | Fix object coordinates |

#### Shell

| Opcode | Name | sintin | sintout | saddrin | saddrout | Description |
|-------:|------|-------:|--------:|--------:|---------:|-------------|
| 120 | shel_read | 0 | 1 | 2 | 0 | Read command and tail |
| 121 | shel_write | 3 | 1 | 2 | 0 | Launch application |
| 122 | shel_get | 1 | 1 | 1 | 0 | Read shell buffer |
| 123 | shel_put | 1 | 1 | 1 | 0 | Write shell buffer |
| 124 | shel_find | 0 | 1 | 1 | 0 | Find file on path |
| 125 | shel_envrn | 2 | 1 | 1 | 0 | Search environment string |

### 2.5 AES Examples

#### Initialize AES Application (appl_init)

```basic
10 REM === Initialize AES application ===
20 REM control: opcode=10, sintin=0, sintout=1, saddrin=0, saddrout=0
30 AESCTRL 0, 10, 1, 0, 2, 1, 3, 0, 4, 0
40 AES
50 ap_id% = AESINTOUT(0)
60 PRINT "Application ID: "; ap_id%
```

Or equivalently, using inline control parameters:

```basic
10 REM === appl_init with inline parameters ===
20 AES 10, 0, 1, 0, 0
30 ap_id% = AESINTOUT(0)
40 PRINT "Application ID: "; ap_id%
```

#### Display Alert Box (form_alert)

```basic
10 REM === Display an alert box ===
20 a$ = "[1][Hello from BASIC!|This is line two.][OK|Cancel]"
30 AESCTRL 0, 52, 1, 1, 2, 1, 3, 1, 4, 0
40 AESINTIN 0, 1              : REM Default button = 1
50 AESADRIN 0, VARPTR(a$)     : REM Pointer to alert string
60 AES
70 button% = AESINTOUT(0)
80 PRINT "Button pressed: "; button%
```

Alert string format: `[icon][message lines separated by |][button labels separated by |]`
- Icon: 0=none, 1=exclamation, 2=question, 3=stop

#### Wait for Keyboard Event (evnt_keybd)

```basic
10 REM === Wait for a keypress ===
20 AESCTRL 0, 20, 1, 0, 2, 1, 3, 0, 4, 0
30 AES
40 key% = AESINTOUT(0)
50 ascii% = key% AND 255
60 scan% = (key% / 256) AND 255
70 PRINT "ASCII: "; CHR$(ascii%); " Scan: "; scan%
```

#### Get Mouse Position and Button State (graf_mkstate)

```basic
10 REM === Read current mouse state ===
20 AESCTRL 0, 79, 1, 0, 2, 5, 3, 0, 4, 0
30 AES
40 PRINT "Mouse X: "; AESINTOUT(1)
50 PRINT "Mouse Y: "; AESINTOUT(2)
60 PRINT "Buttons: "; AESINTOUT(3)
70 PRINT "Kbd state: "; AESINTOUT(4)
```

#### Wait for Mouse Button Event (evnt_button)

```basic
10 REM === Wait for left button click ===
20 AESCTRL 0, 21, 1, 3, 2, 5, 3, 0, 4, 0
30 AESINTIN 0, 1    : REM clicks = 1
40 AESINTIN 1, 1    : REM mask = left button
50 AESINTIN 2, 1    : REM state = pressed
60 AES
70 PRINT "Click at: "; AESINTOUT(1); ","; AESINTOUT(2)
80 PRINT "Button state: "; AESINTOUT(3)
```

#### File Selector Dialog (fsel_input)

```basic
10 REM === File selector ===
20 path$ = "A:\*.BAS" + CHR$(0)
30 file$ = SPACE$(80)
40 AESCTRL 0, 90, 1, 0, 2, 2, 3, 2, 4, 0
50 AESADRIN 0, VARPTR(path$), 1, VARPTR(file$)
60 AES
70 IF AESINTOUT(1) = 1 THEN PRINT "Selected: "; file$
80 IF AESINTOUT(1) = 0 THEN PRINT "Cancelled"
```

#### Get VDI Workstation Handle (graf_handle)

```basic
10 REM === Get physical workstation handle ===
20 AESCTRL 0, 77, 1, 0, 2, 5, 3, 0, 4, 0
30 AES
40 phys_handle% = AESINTOUT(0)
50 char_w% = AESINTOUT(1)
60 char_h% = AESINTOUT(2)
70 box_w% = AESINTOUT(3)
80 box_h% = AESINTOUT(4)
90 PRINT "Handle: "; phys_handle%
```

#### Create and Open a Window

```basic
100 REM === Create a window ===
110 REM wind_create: components, x, y, w, h
120 AESCTRL 0, 100, 1, 5, 2, 1, 3, 0, 4, 0
130 AESINTIN 0, $0FEF       : REM All window components
140 AESINTIN 1, 0            : REM Full screen x
150 AESINTIN 2, 0            : REM Full screen y
160 AESINTIN 3, 640          : REM Full screen w
170 AESINTIN 4, 400          : REM Full screen h
180 AES
190 win_handle% = AESINTOUT(0)
200 REM
210 REM === Open the window ===
220 AESCTRL 0, 101, 1, 5, 2, 1, 3, 0, 4, 0
230 AESINTIN 0, win_handle%
240 AESINTIN 1, 50           : REM x
250 AESINTIN 2, 50           : REM y
260 AESINTIN 3, 300          : REM w
270 AESINTIN 4, 200          : REM h
280 AES
```

#### Close and Delete a Window

```basic
300 REM === Close window ===
310 AESCTRL 0, 102, 1, 1, 2, 1, 3, 0, 4, 0
320 AESINTIN 0, win_handle%
330 AES
340 REM
350 REM === Delete window ===
360 AESCTRL 0, 103, 1, 1, 2, 1, 3, 0, 4, 0
370 AESINTIN 0, win_handle%
380 AES
```

#### Set Window Title (wind_set)

```basic
400 REM === Set window title ===
410 title$ = "My Window" + CHR$(0)
420 AESCTRL 0, 105, 1, 6, 2, 1, 3, 0, 4, 0
430 AESINTIN 0, win_handle%
440 AESINTIN 1, 2            : REM WF_NAME = 2
450 t_addr% = VARPTR(title$)
460 AESINTIN 2, t_addr% / 65536       : REM High word of address
470 AESINTIN 3, t_addr% AND 65535     : REM Low word of address
480 AESINTIN 4, 0
490 AESINTIN 5, 0
500 AES
```

#### Exit AES Application (appl_exit)

```basic
900 REM === Clean up and exit ===
910 AESCTRL 0, 19, 1, 0, 2, 1, 3, 0, 4, 0
920 AES
```

---

## 3. VDI (Virtual Device Interface)

### 3.1 VDI Arrays

The interpreter provides five array interfaces for VDI, plus the VDI
execution command. All arrays reside in BSS and are pointed to by the
VDIPB parameter block.

#### VDICTRL -- VDI Control Array (12 words)

```
Command:  VDICTRL index, value [, index, value ...]
Function: VDICTRL(index)
```

Sets or reads entries in the VDI control array. 12 word-sized entries
(indices 0-11). When used as a command, writes index/value pairs. When
used as a function, reads and returns the sign-extended word at the given
index.

#### VDIINTIN -- VDI Integer Input Array (128 words)

```
Command:  VDIINTIN index, value [, index, value ...]
```

Write-only command. Sets word-sized entries in the VDI integer input array.
Used for passing non-coordinate parameters: colors, styles, character codes,
fill patterns, etc.

#### VDIINTOUT -- VDI Integer Output Array (128 words)

```
Function: VDIINTOUT(index)
```

Read-only function. Returns the sign-extended word at the given index in the
VDI integer output array. Filled by the VDI after a call.

#### VDIPTSIN -- VDI Points Input Array (128 words)

```
Command:  VDIPTSIN index, value [, index, value ...]
```

Write-only command. Sets word-sized entries in the VDI coordinate input
array. Points are stored as consecutive (x, y) pairs: index 0 = x1,
index 1 = y1, index 2 = x2, index 3 = y2, etc.

#### VDIPTSOUT -- VDI Points Output Array (128 words)

```
Function: VDIPTSOUT(index)
```

Read-only function. Returns the sign-extended word at the given index in the
VDI coordinate output array. Filled by the VDI after a call.

#### VDI -- Execute VDI Call

```
Command:  VDI [param0, param1, param2, ...]
```

Executes the VDI call by issuing `trap #2` with `d0 = $73` and
`d1 = address of VDIPB`. If inline parameters are provided, they are stored
sequentially as words in the VDI control array (up to 12 entries) before
the trap is issued. Double commas skip a slot.

### 3.2 VDI Parameter Block

The VDIPB is a fixed structure containing five longword pointers:

```
VDIPB:
  .dc.l  VDIctrl       ;  [0] -> VDI control array (12 words)
  .dc.l  VDIintin      ;  [4] -> VDI integer input (128 words)
  .dc.l  VDIptsin      ;  [8] -> VDI coordinate input (128 words)
  .dc.l  VDIintout     ; [12] -> VDI integer output (128 words)
  .dc.l  VDIptsout     ; [16] -> VDI coordinate output (128 words)
```

When `VDI` is executed, the interpreter loads:
- `d1` = address of VDIPB
- `d0` = $73 (VDI function dispatcher code)
- Then executes `trap #2`

**Note:** The VDIPB pointer order differs from AESPB. Specifically, `ptsin`
comes before `intout` in VDIPB, reflecting the VDI's emphasis on coordinate
data.

### 3.3 VDI Control Array Format

The control array specifies the VDI function and data counts:

```
contrl[0]  = VDI function opcode
contrl[1]  = number of input points (ptsin pairs count)
contrl[2]  = (output) number of output points returned
contrl[3]  = number of integer inputs (intin words count)
contrl[4]  = (output) number of integer outputs returned
contrl[5]  = sub-function number (used by some functions)
contrl[6]  = VDI workstation handle
contrl[7..11] = (additional sub-parameters for some functions)
```

Fields `contrl[2]` and `contrl[4]` are filled by the VDI on return. You
must set `contrl[0]`, `contrl[1]`, `contrl[3]`, `contrl[5]`, and
`contrl[6]` before calling.

### 3.4 Key VDI Functions

#### Workstation Functions

| Function | Sub | Name | Description |
|---------:|----:|------|-------------|
| 1 | -- | v_opnwk | Open physical workstation |
| 2 | -- | v_clswk | Close physical workstation |
| 3 | -- | v_clrwk | Clear workstation (clear screen) |
| 4 | -- | v_updwk | Update workstation (flush output) |
| 100 | 1 | v_opnvwk | Open virtual workstation |
| 101 | 1 | v_clsvwk | Close virtual workstation |

#### Output Functions

| Function | Sub | Name | Description |
|---------:|----:|------|-------------|
| 6 | -- | v_pline | Draw polyline (connected line segments) |
| 7 | -- | v_pmarker | Draw polymarker |
| 8 | -- | v_gtext | Draw graphics text |
| 9 | -- | v_fillarea | Draw filled polygon |
| 11 | 1 | v_bar | Draw filled rectangle (bar) |
| 11 | 2 | v_arc | Draw circular arc |
| 11 | 3 | v_pieslice | Draw pie slice (filled arc) |
| 11 | 4 | v_circle | Draw filled circle |
| 11 | 5 | v_ellipse | Draw filled ellipse |
| 11 | 6 | v_ellarc | Draw elliptical arc |
| 11 | 7 | v_ellpie | Draw elliptical pie slice |
| 11 | 8 | v_rbox | Draw rounded rectangle (outline) |
| 11 | 9 | v_rfbox | Draw rounded rectangle (filled) |
| 11 | 10 | v_justified | Draw justified text |

#### Attribute Functions

| Function | Sub | Name | Description |
|---------:|----:|------|-------------|
| 12 | -- | vst_height | Set character height (absolute) |
| 13 | -- | vst_rotation | Set character rotation angle |
| 14 | -- | vs_color | Set color index RGB values |
| 15 | -- | vsl_type | Set polyline type (solid, dashed, etc.) |
| 16 | -- | vsl_width | Set polyline width |
| 17 | -- | vsl_color | Set polyline color |
| 18 | -- | vsm_type | Set polymarker type |
| 19 | -- | vsm_height | Set polymarker height |
| 20 | -- | vsm_color | Set polymarker color |
| 21 | -- | vst_font | Set text font |
| 22 | -- | vst_color | Set text color |
| 23 | -- | vsf_interior | Set fill interior style (0-4) |
| 24 | -- | vsf_style | Set fill style index |
| 25 | -- | vsf_color | Set fill color |
| 32 | -- | vswr_mode | Set writing mode (1-4) |
| 35 | -- | vsl_ends | Set polyline end styles |
| 36 | -- | vsf_perimeter | Set fill perimeter visibility |
| 38 | -- | vst_effects | Set text special effects |
| 39 | -- | vst_alignment | Set text alignment |
| 106 | -- | vst_point | Set character height (in points) |
| 107 | -- | vsl_udsty | Set user-defined line style |

#### Raster Operations

| Function | Sub | Name | Description |
|---------:|----:|------|-------------|
| 109 | -- | vro_cpyfm | Copy raster, opaque (all planes) |
| 121 | -- | vrt_cpyfm | Copy raster, transparent (single plane) |
| 110 | -- | v_contourfill | Contour (seed) fill |

#### Input Functions

| Function | Sub | Name | Description |
|---------:|----:|------|-------------|
| 33 | -- | vsin_mode | Set input mode (request/sample) |
| 122 | -- | v_show_c | Show mouse cursor |
| 123 | -- | v_hide_c | Hide mouse cursor |

#### Inquire Functions

| Function | Sub | Name | Description |
|---------:|----:|------|-------------|
| 26 | -- | vq_color | Inquire color representation |
| 35 | -- | vql_attributes | Inquire current polyline attributes |
| 36 | -- | vqm_attributes | Inquire current marker attributes |
| 37 | -- | vqf_attributes | Inquire current fill attributes |
| 38 | -- | vqt_attributes | Inquire current text attributes |
| 102 | -- | vq_extnd | Extended inquire function |
| 131 | -- | vqt_extent | Inquire text extent |

### 3.5 VDI Examples

#### Open Virtual Workstation (v_opnvwk)

First, get the physical handle from AES, then open a virtual workstation:

```basic
10 REM === Get physical workstation handle via graf_handle ===
20 AESCTRL 0, 77, 1, 0, 2, 5, 3, 0, 4, 0
30 AES
40 phys_handle% = AESINTOUT(0)
50 REM
60 REM === Open virtual workstation (v_opnvwk) ===
70 REM contrl[0]=100, contrl[1]=0 pts, contrl[3]=11 ints,
80 REM contrl[5]=1 (sub), contrl[6]=phys_handle
90 VDICTRL 0, 100, 1, 0, 3, 11, 5, 1, 6, phys_handle%
100 REM Work_in array: 10 device defaults + coordinate type
110 FOR i% = 0 TO 9
120   VDIINTIN i%, 1
130 NEXT i%
140 VDIINTIN 10, 2           : REM 2 = Raster Coordinate mode (RC)
150 VDI
160 vdi_handle% = VDICTRL(6) : REM Virtual handle returned in contrl[6]
170 PRINT "VDI handle: "; vdi_handle%
```

**Work_in array values (intin[0..10]):**

| Index | Meaning | Typical Value |
|------:|---------|:-------------:|
| 0 | Device ID | 1 |
| 1 | Line type | 1 (solid) |
| 2 | Line color index | 1 (black) |
| 3 | Marker type | 1 (dot) |
| 4 | Marker color index | 1 |
| 5 | Font ID | 1 (system) |
| 6 | Text color index | 1 |
| 7 | Fill interior style | 1 (solid) |
| 8 | Fill style index | 1 |
| 9 | Fill color index | 1 |
| 10 | Coordinate type | 2 (RC) |

#### Clear the Workstation (v_clrwk)

```basic
10 REM === Clear screen ===
20 VDICTRL 0, 3, 1, 0, 3, 0, 6, vdi_handle%
30 VDI
```

#### Draw a Polyline (v_pline)

```basic
10 REM === Draw a triangle outline ===
20 REM v_pline: function 6, 4 points (triangle + close)
30 VDICTRL 0, 6, 1, 4, 3, 0, 6, vdi_handle%
40 REM Point 1
50 VDIPTSIN 0, 160          : REM x1 (top)
60 VDIPTSIN 1, 20           : REM y1
70 REM Point 2
80 VDIPTSIN 2, 60           : REM x2 (bottom-left)
90 VDIPTSIN 3, 180          : REM y2
100 REM Point 3
110 VDIPTSIN 4, 260         : REM x3 (bottom-right)
120 VDIPTSIN 5, 180         : REM y3
130 REM Point 4 = Point 1 (close the triangle)
140 VDIPTSIN 6, 160         : REM x4
150 VDIPTSIN 7, 20          : REM y4
160 VDI
```

#### Set Line Attributes

```basic
10 REM === Set line type to dashed, color black, width 3 ===
20 REM vsl_type (function 15): intin[0] = line type
30 VDICTRL 0, 15, 1, 0, 3, 1, 6, vdi_handle%
40 VDIINTIN 0, 2            : REM 2 = dashed
50 VDI
60 REM
70 REM vsl_width (function 16): ptsin[0] = width
80 VDICTRL 0, 16, 1, 1, 3, 0, 6, vdi_handle%
90 VDIPTSIN 0, 3            : REM width = 3 pixels
100 VDIPTSIN 1, 0           : REM (y ignored)
110 VDI
120 REM
130 REM vsl_color (function 17): intin[0] = color index
140 VDICTRL 0, 17, 1, 0, 3, 1, 6, vdi_handle%
150 VDIINTIN 0, 1           : REM 1 = black
160 VDI
```

**Line types:** 1=solid, 2=long dash, 3=dot, 4=dash-dot, 5=dash,
6=dash-dot-dot, 7=user-defined (set via vsl_udsty)

#### Draw Graphics Text (v_gtext)

```basic
10 REM === Draw text "Hello" at position (50, 100) ===
20 REM v_gtext: function 8, 1 point, 5 characters
30 VDICTRL 0, 8, 1, 1, 3, 5, 6, vdi_handle%
40 VDIPTSIN 0, 50           : REM x position
50 VDIPTSIN 1, 100          : REM y position
60 REM Each character as its ASCII code in intin[]
70 VDIINTIN 0, 72           : REM 'H'
80 VDIINTIN 1, 101          : REM 'e'
90 VDIINTIN 2, 108          : REM 'l'
100 VDIINTIN 3, 108         : REM 'l'
110 VDIINTIN 4, 111         : REM 'o'
120 VDI
```

**Tip:** To output a string, loop through its characters:

```basic
10 REM === Draw arbitrary string ===
20 t$ = "GEM VDI from BASIC!"
30 n% = LEN(t$)
40 VDICTRL 0, 8, 1, 1, 3, n%, 6, vdi_handle%
50 VDIPTSIN 0, 10           : REM x
60 VDIPTSIN 1, 50           : REM y
70 FOR i% = 0 TO n% - 1
80   VDIINTIN i%, ASC(MID$(t$, i% + 1, 1))
90 NEXT i%
100 VDI
```

#### Draw Filled Rectangle / Bar (v_bar)

```basic
10 REM === Draw a filled bar ===
20 REM v_bar: function 11, sub 1, 2 corner points
30 VDICTRL 0, 11, 1, 2, 3, 0, 5, 1, 6, vdi_handle%
40 VDIPTSIN 0, 50           : REM x1 (top-left)
50 VDIPTSIN 1, 50           : REM y1
60 VDIPTSIN 2, 200          : REM x2 (bottom-right)
70 VDIPTSIN 3, 150          : REM y2
80 VDI
```

#### Draw a Circle (v_circle)

```basic
10 REM === Draw a filled circle ===
20 REM v_circle: function 11, sub 4, 3 points (center + radius)
30 VDICTRL 0, 11, 1, 3, 3, 0, 5, 4, 6, vdi_handle%
40 VDIPTSIN 0, 160          : REM center x
50 VDIPTSIN 1, 100          : REM center y
60 VDIPTSIN 2, 0            : REM (unused)
70 VDIPTSIN 3, 0            : REM (unused)
80 VDIPTSIN 4, 50           : REM radius
90 VDIPTSIN 5, 0            : REM (unused)
100 VDI
```

#### Set Fill Attributes

```basic
10 REM === Set fill to solid black ===
20 REM vsf_interior (function 23): intin[0] = fill style
30 VDICTRL 0, 23, 1, 0, 3, 1, 6, vdi_handle%
40 VDIINTIN 0, 1            : REM 1 = solid
50 VDI
60 REM
70 REM vsf_color (function 25): intin[0] = color index
80 VDICTRL 0, 25, 1, 0, 3, 1, 6, vdi_handle%
90 VDIINTIN 0, 1            : REM 1 = black
100 VDI
```

**Fill interior styles:** 0=hollow, 1=solid, 2=pattern, 3=hatch, 4=user-defined

#### Set Writing Mode (vswr_mode)

```basic
10 REM === Set writing mode to XOR ===
20 VDICTRL 0, 32, 1, 0, 3, 1, 6, vdi_handle%
30 VDIINTIN 0, 3            : REM 3 = XOR
40 VDI
```

**Writing modes:** 1=replace, 2=transparent, 3=XOR, 4=reverse transparent

#### Draw an Arc (v_arc)

```basic
10 REM === Draw a 90-degree arc ===
20 REM v_arc: function 11, sub 2
30 REM ptsin: center x, center y, 0, 0, radius, 0
40 REM intin: start angle (tenths of degrees), end angle
50 VDICTRL 0, 11, 1, 4, 3, 2, 5, 2, 6, vdi_handle%
60 VDIPTSIN 0, 160          : REM center x
70 VDIPTSIN 1, 100          : REM center y
80 VDIPTSIN 2, 0
90 VDIPTSIN 3, 0
100 VDIPTSIN 4, 0
110 VDIPTSIN 5, 0
120 VDIPTSIN 6, 80          : REM radius
130 VDIPTSIN 7, 0
140 VDIINTIN 0, 0           : REM start angle: 0 = 3 o'clock
150 VDIINTIN 1, 900         : REM end angle: 900 = 12 o'clock (90.0 degrees)
160 VDI
```

**VDI angles** are in tenths of degrees: 0=right (3 o'clock), 900=top
(12 o'clock), 1800=left (9 o'clock), 2700=bottom (6 o'clock), counter-clockwise.

#### Show/Hide Mouse Cursor

```basic
10 REM === Show mouse cursor ===
20 VDICTRL 0, 122, 1, 0, 3, 1, 6, vdi_handle%
30 VDIINTIN 0, 0            : REM 0 = reset hide count
40 VDI
```

```basic
10 REM === Hide mouse cursor ===
20 VDICTRL 0, 123, 1, 0, 3, 0, 6, vdi_handle%
30 VDI
```

#### Raster Copy (vro_cpyfm)

```basic
10 REM === Copy a screen rectangle (opaque raster copy) ===
20 REM vro_cpyfm: function 109, 4 points (source + dest rectangles)
30 VDICTRL 0, 109, 1, 4, 3, 1, 6, vdi_handle%
40 VDIINTIN 0, 3            : REM mode: 3 = source (S_ONLY)
50 REM Source rectangle
60 VDIPTSIN 0, 0            : REM src x1
70 VDIPTSIN 1, 0            : REM src y1
80 VDIPTSIN 2, 100          : REM src x2
90 VDIPTSIN 3, 100          : REM src y2
100 REM Destination rectangle
110 VDIPTSIN 4, 200         : REM dst x1
120 VDIPTSIN 5, 50          : REM dst y1
130 VDIPTSIN 6, 300         : REM dst x2
140 VDIPTSIN 7, 150         : REM dst y2
150 VDI
```

**Raster operation modes (vro_cpyfm):**
0=ALL_WHITE, 1=S_AND_D, 2=S_AND_NOTD, 3=S_ONLY, 4=NOTS_AND_D,
5=D_ONLY, 6=S_XOR_D, 7=S_OR_D, 8=NOT_SORD, 9=NOT_SXORD,
10=NOT_D, 11=S_OR_NOTD, 12=NOT_S, 13=NOTS_OR_D, 14=NOT_SANDD,
15=ALL_BLACK

#### Close Virtual Workstation (v_clsvwk)

```basic
10 REM === Close virtual workstation ===
20 VDICTRL 0, 101, 1, 0, 3, 0, 5, 1, 6, vdi_handle%
30 VDI
```

---

## 4. Line-A Graphics

### 4.1 Overview

Line-A provides low-level, high-speed graphics routines accessed via special
68000 opcodes in the range $A000-$A00F. These are "illegal instruction"
traps that the Atari ST ROM intercepts and dispatches to built-in drawing
routines that operate directly on screen memory.

The BASIC interpreter initializes Line-A at startup (in `HEADER.S`, line 120)
by executing the `$A000` opcode, which returns a pointer to the Line-A
variable block in register `a0`. This pointer is saved in the global
`la_variablen` and used by the `LINE2` command.

Line-A bypasses GEM entirely, so it is faster than VDI but not
device-independent. It works only on the Atari ST's built-in screen hardware.

### 4.2 The LINE2 Command

```basic
LINE2 x1, y1, x2, y2
```

Draws a straight line from point (x1, y1) to point (x2, y2) using Line-A
opcode $A003. All four parameters are evaluated as integer expressions.

**Important:** The keyword is `LINE2`, not `LINE`. The LINE command exists only in the TOKEN2 extended command class with keyword string `"line2"`, so the digit '2' is part of the keyword. `LINE3` also works (identical handler in TOKEN3). Typing `LINE` without the digit is not recognized by the tokenizer. See BASIC-ANALYSIS.md Section 3 for the full technical explanation.

**Implementation detail** (from `BASIC_COMMENTS.S` lines 9385-9422):

1. Parse four integer arguments via `get_term`.
2. Load the Line-A variable block base from `la_variablen`.
3. Store coordinates:
   - `x1` at offset `$26`
   - `y1` at offset `$28`
   - `x2` at offset `$2A`
   - `y2` at offset `$2C`
4. Execute `.dc.w $A003` (Line-A draw line opcode).

The line is drawn using whatever settings are currently in the Line-A
variable block. At startup, the interpreter configures:

| Setting | Offset | Value | Meaning |
|---------|-------:|------:|---------|
| fg_bp_1 | $18 | 1 | Foreground color = black (mono plane 0) |
| LSTLIN | $20 | -1 ($FFFF) | Draw the last pixel of the line |
| LNMASK | $22 | $FFFF | Solid line (no dashing pattern) |
| WMODE | $24 | 1 | XOR write mode |

**Examples:**

```basic
10 LINE 0, 0, 319, 199          : REM Diagonal across ST low-res
20 LINE 0, 199, 319, 0          : REM X pattern
30 FOR i% = 0 TO 319 STEP 10
40   LINE i%, 0, 319 - i%, 199
50 NEXT i%
```

```basic
10 REM === Draw a box using LINE ===
20 x1% = 50 : y1% = 50 : x2% = 200 : y2% = 150
30 LINE x1%, y1%, x2%, y1%      : REM Top
40 LINE x2%, y1%, x2%, y2%      : REM Right
50 LINE x2%, y2%, x1%, y2%      : REM Bottom
60 LINE x1%, y2%, x1%, y1%      : REM Left
```

```basic
10 REM === Draw a star pattern ===
20 cx% = 160 : cy% = 100
30 FOR a% = 0 TO 359 STEP 15
40   r = 3.14159 * a% / 180
50   x% = cx% + INT(80 * COS(r))
60   y% = cy% + INT(80 * SIN(r))
70   LINE cx%, cy%, x%, y%
80 NEXT a%
```

**Note:** Because the default write mode is XOR, drawing the same line
twice erases it. This is useful for animation and rubber-banding but can be
surprising if you expect overwrite behavior. To change the write mode, you
must modify the Line-A variable block directly (see Section 4.6).

### 4.3 Line-A Initialization (Done at Startup)

The initialization sequence in `HEADER.S` (lines 114-125):

```asm
    .dc.w   $A000               ; Line-A INIT: returns a0 = variable block
    move.l  a0, la_variablen    ; Save pointer globally
    move.w  #1, $18(a0)         ; fg_bp_1 = 1 (black foreground, plane 0)
    move.w  #-1, $20(a0)        ; LSTLIN = -1 (draw last pixel)
    move.w  #$FFFF, $22(a0)     ; LNMASK = $FFFF (solid line)
    move.w  #1, $24(a0)         ; WMODE = 1 (XOR mode)
```

The `$A000` opcode also returns:
- `a1` = pointer to array of three font headers (6x6, 8x8, 8x16)
- `a2` = pointer to the Line-A opcode routine table (16 entries)

These are not saved by the interpreter but could be captured by a
machine-code routine called via `CALL`.

### 4.4 Complete Line-A Opcode Table

| Opcode | Hex | Name | Description |
|-------:|-----|------|-------------|
| 0 | $A000 | Initialization | Initialize Line-A, return variable block pointer |
| 1 | $A001 | Put Pixel | Set a single pixel at (PTSIN[0], PTSIN[1]) |
| 2 | $A002 | Get Pixel | Read pixel color at (PTSIN[0], PTSIN[1]) |
| 3 | $A003 | Arbitrary Line | Draw line from (X1,Y1) to (X2,Y2) -- used by LINE |
| 4 | $A004 | Horizontal Line | Draw fast horizontal line (X1 to X2 at Y1) |
| 5 | $A005 | Filled Rectangle | Draw solid/patterned filled rectangle |
| 6 | $A006 | Filled Polygon | Render one scanline of a filled polygon |
| 7 | $A007 | BitBlt | Bit block transfer (raster copy between memory) |
| 8 | $A008 | TextBlt | Render a single character glyph (text blit) |
| 9 | $A009 | Show Mouse | Make the mouse cursor visible |
| 10 | $A00A | Hide Mouse | Hide the mouse cursor |
| 11 | $A00B | Transform Mouse | Change the mouse cursor shape |
| 12 | $A00C | Undraw Sprite | Restore screen area under a sprite |
| 13 | $A00D | Draw Sprite | Draw a 16x16 software sprite |
| 14 | $A00E | Copy Raster Form | Copy rectangular raster between forms |
| 15 | $A00F | Seed Fill | Flood fill from a seed point |

### 4.5 Key Line-A Variable Offsets

These offsets are relative to the Line-A variable block base address (the
pointer returned by `$A000` and stored in `la_variablen`).

#### Screen Information

| Offset | Name | Size | Description |
|-------:|------|------|-------------|
| $00 | VPLANES | word | Number of bit planes (1=mono, 2=medium, 4=low) |
| $02 | VWRAP | word | Screen line width in bytes (160 or 80) |

#### Line Drawing Parameters (used by $A003, $A004)

| Offset | Name | Size | Description |
|-------:|------|------|-------------|
| $18 | FG_BP_1 | word | Foreground color, bit plane 0 (0 or 1) |
| $1A | FG_BP_2 | word | Foreground color, bit plane 1 |
| $1C | FG_BP_3 | word | Foreground color, bit plane 2 |
| $1E | FG_BP_4 | word | Foreground color, bit plane 3 |
| $20 | LSTLIN | word | Last pixel flag: -1 = draw last pixel, 0 = skip |
| $22 | LNMASK | word | Line style bitmask ($FFFF = solid, $FF00 = dashed) |
| $24 | WMODE | word | Write mode |
| $26 | X1 | word | Line start X coordinate |
| $28 | Y1 | word | Line start Y coordinate |
| $2A | X2 | word | Line end X coordinate |
| $2C | Y2 | word | Line end Y coordinate |

**Write mode values:**

| Value | Mode | Description |
|------:|------|-------------|
| 0 | Replace | Destination = source |
| 1 | XOR | Destination = source XOR destination |
| 2 | Transparent | Only foreground pixels written |
| 3 | Reverse transparent | Only background pixels written |

#### Fill Parameters (used by $A005, $A006)

| Offset | Name | Size | Description |
|-------:|------|------|-------------|
| $2E | PATPTR | long | Pointer to fill pattern data |
| $32 | PATMSK | word | Pattern mask = pattern_height - 1 |
| $34 | MFILL | word | Multi-plane fill flag (0=single, 1=multi) |

**Note:** Some references list PATPTR at offset $46. The exact offset depends
on the TOS version. The values above match TOS 1.0/1.2. Always verify
against your specific TOS revision.

#### Clipping Parameters

| Offset | Name | Size | Description |
|-------:|------|------|-------------|
| $4E | CLIP | word | Clipping enable: 0 = off, 1 = on |
| $50 | XMINCL | word | Clip rectangle left edge |
| $52 | YMINCL | word | Clip rectangle top edge |
| $54 | XMAXCL | word | Clip rectangle right edge |
| $56 | YMAXCL | word | Clip rectangle bottom edge |

#### Pixel and Cursor

| Offset | Name | Size | Description |
|-------:|------|------|-------------|
| $36 | INTIN[0] | word | Input parameter (pixel color for $A001) |
| $3A | PTSIN[0] | word | X coordinate for pixel ops |
| $3C | PTSIN[1] | word | Y coordinate for pixel ops |
| $44 | CUR_X | word | Current text cursor X (in characters) |
| $46 | CUR_Y | word | Current text cursor Y (in characters) |

#### Font Information (set by $A000)

| Offset | Name | Size | Description |
|-------:|------|------|-------------|
| -$0E | FONT_RING[0] | long | Pointer to first font header (6x6) |
| -$0A | FONT_RING[1] | long | Pointer to second font header (8x8) |
| -$06 | FONT_RING[2] | long | Pointer to third font header (8x16) |
| -$02 | FONT_RING[3] | long | End marker (0) |

(Negative offsets are relative to the variable block base.)

### 4.6 Accessing Line-A from BASIC

The interpreter does not provide a built-in function to read the Line-A
variable block address. However, there are several approaches:

#### Method 1: Using LPEEK/LPOKE with Known Addresses

If you know the address of the `la_variablen` storage location (which
depends on where the interpreter is loaded), you can read it:

```basic
10 REM Get Line-A base address (address of la_variablen must be known)
20 la_base% = LPEEK(la_addr%)
30 REM Now modify Line-A variables:
40 WPOKE la_base% + $22, $FF00    : REM Dashed line pattern
50 WPOKE la_base% + $24, 0        : REM Replace write mode (not XOR)
60 LINE 0, 0, 319, 199            : REM Draw with new settings
```

#### Method 2: Using CALL for Line-A Init

Write a small machine code routine that executes `$A000` and stores the
result:

```basic
10 REM Machine code: $A000, move.l a0,($addr), rts
20 REM (Exact code depends on target address)
30 DIM code%(4)
40 REM ... poke machine code into code%() ...
50 CALL VARPTR(code%(0))
60 la_base% = LPEEK(result_addr%)
```

#### Method 3: Change Line Settings Before Drawing

Since the `LINE` command reads its settings from the Line-A variable block
each time, changing the block between LINE calls changes the drawing style:

```basic
10 REM === Draw lines with different patterns ===
20 REM (Assuming la_base% is known)
30 WPOKE la_base% + $22, $FFFF    : REM Solid
40 LINE 10, 10, 310, 10
50 WPOKE la_base% + $22, $FF00    : REM Long dash
60 LINE 10, 20, 310, 20
70 WPOKE la_base% + $22, $F0F0    : REM Short dash
80 LINE 10, 30, 310, 30
90 WPOKE la_base% + $22, $AAAA    : REM Dotted
100 LINE 10, 40, 310, 40
```

#### Setting Colors in Low/Medium Resolution

In medium resolution (4 colors, 2 planes), set both foreground planes:

```basic
10 REM === Set Line-A foreground to color 2 (medium res) ===
20 WPOKE la_base% + $18, 0        : REM fg_bp_1 = 0 (plane 0)
30 WPOKE la_base% + $1A, 1        : REM fg_bp_2 = 1 (plane 1)
40 REM Color index = bp_2 * 2 + bp_1 = 1*2 + 0 = 2
50 LINE 0, 0, 319, 99
```

In low resolution (16 colors, 4 planes), set all four planes:

```basic
10 REM === Set Line-A foreground to color 5 (low res) ===
20 REM 5 = binary 0101 -> planes: 1, 0, 1, 0
30 WPOKE la_base% + $18, 1        : REM fg_bp_1 (bit 0)
40 WPOKE la_base% + $1A, 0        : REM fg_bp_2 (bit 1)
50 WPOKE la_base% + $1C, 1        : REM fg_bp_3 (bit 2)
60 WPOKE la_base% + $1E, 0        : REM fg_bp_4 (bit 3)
70 LINE 0, 0, 159, 99
```

---

## 5. Practical Programming Patterns

### 5.1 GEM Application Skeleton

A minimal GEM-aware BASIC program follows this structure:

```basic
10 REM ================================================
20 REM  Minimal GEM Application Skeleton
30 REM ================================================
40 REM
50 REM --- Step 1: Initialize AES (appl_init) ---
60 AESCTRL 0, 10, 1, 0, 2, 1, 3, 0, 4, 0
70 AES
80 ap_id% = AESINTOUT(0)
90 IF ap_id% < 0 THEN PRINT "appl_init failed!" : END
100 REM
110 REM --- Step 2: Get physical workstation handle ---
120 AESCTRL 0, 77, 1, 0, 2, 5, 3, 0, 4, 0
130 AES
140 phys_handle% = AESINTOUT(0)
150 REM
160 REM --- Step 3: Open virtual workstation ---
170 VDICTRL 0, 100, 1, 0, 3, 11, 5, 1, 6, phys_handle%
180 FOR i% = 0 TO 9: VDIINTIN i%, 1: NEXT i%
190 VDIINTIN 10, 2
200 VDI
210 vdi_handle% = VDICTRL(6)
220 REM
230 REM --- Step 4: Main program ---
240 REM   (Drawing, event handling, etc.)
250 GOSUB 1000
260 REM
270 REM --- Step 5: Cleanup ---
280 REM Close virtual workstation (v_clsvwk)
290 VDICTRL 0, 101, 1, 0, 3, 0, 5, 1, 6, vdi_handle%
300 VDI
310 REM Exit AES (appl_exit)
320 AESCTRL 0, 19, 1, 0, 2, 1, 3, 0, 4, 0
330 AES
340 END
350 REM
1000 REM === Main drawing/event subroutine ===
1010 REM (Your code here)
1020 RETURN
```

### 5.2 Common Patterns

#### Pattern: Event Loop with evnt_multi

```basic
500 REM === Event loop ===
510 REM evnt_multi: wait for keyboard, message, or timer
520 AESCTRL 0, 25, 1, 16, 2, 7, 3, 1, 4, 0
530 REM intin[0] = event flags: MU_KEYBD(1) + MU_MESAG(16) + MU_TIMER(32)
540 AESINTIN 0, $31
550 REM Mouse parameters (not used, but must be present)
560 AESINTIN 1, 0 : AESINTIN 2, 0 : AESINTIN 3, 0 : AESINTIN 4, 0
570 AESINTIN 5, 0 : AESINTIN 6, 0 : AESINTIN 7, 0 : AESINTIN 8, 0
580 AESINTIN 9, 0 : AESINTIN 10, 0 : AESINTIN 11, 0 : AESINTIN 12, 0
590 REM Timer: low word = 1000 (1 second), high word = 0
600 AESINTIN 14, 1000 : AESINTIN 15, 0
610 REM Message buffer
620 DIM msg%(8)
630 AESADRIN 0, VARPTR(msg%(0))
640 AES
650 events% = AESINTOUT(0)
660 REM
670 REM Check which event occurred
680 IF events% AND 1 THEN GOSUB 2000  : REM Keyboard event
690 IF events% AND 16 THEN GOSUB 3000 : REM Message event
700 IF events% AND 32 THEN GOSUB 4000 : REM Timer event
710 GOTO 520                            : REM Loop
```

**evnt_multi event flag bits:**

| Bit | Value | Name | Description |
|----:|------:|------|-------------|
| 0 | $01 | MU_KEYBD | Keyboard event |
| 1 | $02 | MU_BUTTON | Mouse button event |
| 2 | $04 | MU_M1 | Mouse enters/leaves rectangle 1 |
| 3 | $08 | MU_M2 | Mouse enters/leaves rectangle 2 |
| 4 | $10 | MU_MESAG | Message received |
| 5 | $20 | MU_TIMER | Timer expired |

#### Pattern: Display an Alert Box

```basic
10 REM === Quick alert box ===
20 DEF FN alert$(icon%, msg$, buttons$)
30 REM Builds: [icon][msg][buttons]
40 a$ = "[" + STR$(icon%) + "][" + msg$ + "][" + buttons$ + "]" + CHR$(0)
50 AESCTRL 0, 52, 1, 1, 2, 1, 3, 1, 4, 0
60 AESINTIN 0, 1
70 AESADRIN 0, VARPTR(a$)
80 AES
90 FN alert$ = STR$(AESINTOUT(0))
```

Simple one-liner usage:

```basic
10 a$ = "[1][File saved successfully.][OK]" + CHR$(0)
20 AESCTRL 0, 52, 1, 1, 2, 1, 3, 1, 4, 0
30 AESINTIN 0, 1 : AESADRIN 0, VARPTR(a$) : AES
```

#### Pattern: File Selection Dialog

```basic
10 REM === File selector ===
20 path$ = "A:\*.*" + CHR$(0) + SPACE$(80)
30 file$ = SPACE$(13) + CHR$(0)
40 AESCTRL 0, 90, 1, 0, 2, 2, 3, 2, 4, 0
50 AESADRIN 0, VARPTR(path$), 1, VARPTR(file$)
60 AES
70 ok% = AESINTOUT(1)
80 IF ok% = 0 THEN PRINT "Cancelled" : GOTO 110
90 PRINT "Path: "; path$
100 PRINT "File: "; file$
110 REM done
```

#### Pattern: Set Mouse Cursor Form (graf_mouse)

```basic
10 REM === Change mouse cursor ===
20 REM graf_mouse: intin[0] = cursor form number
30 AESCTRL 0, 78, 1, 1, 2, 1, 3, 1, 4, 0
40 AESINTIN 0, 2              : REM 2 = busy bee (hourglass)
50 AESADRIN 0, 0              : REM No custom form
60 AES
```

**Standard mouse cursor forms:**

| Number | Shape |
|-------:|-------|
| 0 | Arrow |
| 1 | Text cursor (I-beam) |
| 2 | Busy bee (hourglass) |
| 3 | Pointing hand |
| 4 | Flat hand |
| 5 | Thin crosshair |
| 6 | Thick crosshair |
| 7 | Outline crosshair |
| 255 | User-defined (AESADRIN points to form data) |

#### Pattern: Drawing with VDI Colors and Fills

```basic
10 REM === Draw colored filled shapes ===
20 REM Set fill to hatched pattern, color 1
30 VDICTRL 0, 23, 1, 0, 3, 1, 6, vdi_handle%
40 VDIINTIN 0, 3              : REM Interior: 3 = hatch
50 VDI
60 VDICTRL 0, 24, 1, 0, 3, 1, 6, vdi_handle%
70 VDIINTIN 0, 4              : REM Hatch style index: 4
80 VDI
90 VDICTRL 0, 25, 1, 0, 3, 1, 6, vdi_handle%
100 VDIINTIN 0, 1             : REM Color: 1 = black
110 VDI
120 REM Draw bar with these settings
130 VDICTRL 0, 11, 1, 2, 3, 0, 5, 1, 6, vdi_handle%
140 VDIPTSIN 0, 20, 1, 20, 2, 300, 3, 180
150 VDI
```

#### Pattern: Inquire Text Extent

```basic
10 REM === Get pixel width of a string ===
20 t$ = "How wide am I?"
30 n% = LEN(t$)
40 VDICTRL 0, 116, 1, 0, 3, n%, 6, vdi_handle%
50 FOR i% = 0 TO n% - 1
60   VDIINTIN i%, ASC(MID$(t$, i% + 1, 1))
70 NEXT i%
80 VDI
90 w% = VDIPTSOUT(2) - VDIPTSOUT(0)
100 h% = VDIPTSOUT(5) - VDIPTSOUT(3)
110 PRINT "Text width: "; w%; " height: "; h%
```

---

## 6. Reference: AES Function Numbers Quick Table

Compact lookup table for all standard AES functions.

| Op | Name | sin | sout | ain | aout |
|---:|------|----:|-----:|----:|-----:|
| 10 | appl_init | 0 | 1 | 0 | 0 |
| 11 | appl_read | 2 | 1 | 1 | 0 |
| 12 | appl_write | 2 | 1 | 1 | 0 |
| 13 | appl_find | 0 | 1 | 1 | 0 |
| 19 | appl_exit | 0 | 1 | 0 | 0 |
| 20 | evnt_keybd | 0 | 1 | 0 | 0 |
| 21 | evnt_button | 3 | 5 | 0 | 0 |
| 22 | evnt_mouse | 5 | 5 | 0 | 0 |
| 23 | evnt_mesag | 0 | 1 | 1 | 0 |
| 24 | evnt_timer | 2 | 1 | 0 | 0 |
| 25 | evnt_multi | 16 | 7 | 1 | 0 |
| 26 | evnt_dclick | 2 | 1 | 0 | 0 |
| 30 | menu_bar | 1 | 1 | 1 | 0 |
| 31 | menu_icheck | 2 | 1 | 1 | 0 |
| 32 | menu_ienable | 2 | 1 | 1 | 0 |
| 33 | menu_tnormal | 2 | 1 | 1 | 0 |
| 34 | menu_text | 1 | 1 | 2 | 0 |
| 35 | menu_register | 1 | 1 | 1 | 0 |
| 40 | objc_add | 2 | 1 | 1 | 0 |
| 41 | objc_delete | 1 | 1 | 1 | 0 |
| 42 | objc_draw | 6 | 1 | 1 | 0 |
| 43 | objc_find | 4 | 1 | 1 | 0 |
| 44 | objc_offset | 1 | 3 | 1 | 0 |
| 45 | objc_order | 2 | 1 | 1 | 0 |
| 46 | objc_edit | 4 | 2 | 1 | 0 |
| 47 | objc_change | 8 | 1 | 1 | 0 |
| 50 | form_do | 1 | 1 | 1 | 0 |
| 51 | form_dial | 9 | 1 | 0 | 0 |
| 52 | form_alert | 1 | 1 | 1 | 0 |
| 53 | form_error | 1 | 1 | 0 | 0 |
| 54 | form_center | 0 | 5 | 1 | 0 |
| 55 | form_keybd | 3 | 3 | 1 | 0 |
| 56 | form_button | 2 | 2 | 1 | 0 |
| 70 | graf_rubberbox | 4 | 3 | 0 | 0 |
| 71 | graf_dragbox | 8 | 3 | 0 | 0 |
| 72 | graf_movebox | 6 | 1 | 0 | 0 |
| 73 | graf_growbox | 8 | 1 | 0 | 0 |
| 74 | graf_shrinkbox | 8 | 1 | 0 | 0 |
| 75 | graf_watchbox | 4 | 1 | 1 | 0 |
| 76 | graf_slidebox | 3 | 1 | 1 | 0 |
| 77 | graf_handle | 0 | 5 | 0 | 0 |
| 78 | graf_mouse | 1 | 1 | 1 | 0 |
| 79 | graf_mkstate | 0 | 5 | 0 | 0 |
| 80 | scrp_read | 0 | 1 | 1 | 0 |
| 81 | scrp_write | 0 | 1 | 1 | 0 |
| 90 | fsel_input | 0 | 2 | 2 | 0 |
| 91 | fsel_exinput | 0 | 2 | 3 | 0 |
| 100 | wind_create | 5 | 1 | 0 | 0 |
| 101 | wind_open | 5 | 1 | 0 | 0 |
| 102 | wind_close | 1 | 1 | 0 | 0 |
| 103 | wind_delete | 1 | 1 | 0 | 0 |
| 104 | wind_get | 2 | 5 | 0 | 0 |
| 105 | wind_set | 6 | 1 | 0 | 0 |
| 106 | wind_find | 2 | 1 | 0 | 0 |
| 107 | wind_update | 1 | 1 | 0 | 0 |
| 108 | wind_calc | 6 | 5 | 0 | 0 |
| 109 | wind_new | 0 | 1 | 0 | 0 |
| 110 | rsrc_load | 0 | 1 | 1 | 0 |
| 111 | rsrc_free | 0 | 1 | 0 | 0 |
| 112 | rsrc_gaddr | 2 | 1 | 0 | 1 |
| 113 | rsrc_saddr | 2 | 1 | 1 | 0 |
| 114 | rsrc_obfix | 1 | 1 | 1 | 0 |
| 120 | shel_read | 0 | 1 | 2 | 0 |
| 121 | shel_write | 3 | 1 | 2 | 0 |
| 122 | shel_get | 1 | 1 | 1 | 0 |
| 123 | shel_put | 1 | 1 | 1 | 0 |
| 124 | shel_find | 0 | 1 | 1 | 0 |
| 125 | shel_envrn | 2 | 1 | 1 | 0 |

Column legend: **Op** = opcode (control[0]), **sin** = sintin (control[1]),
**sout** = sintout (control[2]), **ain** = saddrin (control[3]),
**aout** = saddrout (control[4]).

---

## 7. Reference: VDI Function Numbers Quick Table

| Func | Sub | Name | Category |
|-----:|----:|------|----------|
| 1 | -- | v_opnwk | Workstation |
| 2 | -- | v_clswk | Workstation |
| 3 | -- | v_clrwk | Workstation |
| 4 | -- | v_updwk | Workstation |
| 5 | 1 | vq_chcells | Inquire |
| 5 | 2 | v_exit_cur | Output |
| 5 | 3 | v_enter_cur | Output |
| 5 | 4 | v_curup | Output |
| 5 | 5 | v_curdown | Output |
| 5 | 6 | v_curright | Output |
| 5 | 7 | v_curleft | Output |
| 5 | 8 | v_curhome | Output |
| 5 | 9 | v_eeos | Output |
| 5 | 10 | v_eeol | Output |
| 5 | 11 | vs_curaddress | Output |
| 5 | 12 | v_curtext | Output |
| 5 | 13 | v_rvon | Output |
| 5 | 14 | v_rvoff | Output |
| 5 | 15 | vq_curaddress | Inquire |
| 5 | 16 | vq_tabstatus | Inquire |
| 5 | 17 | v_hardcopy | Output |
| 5 | 18 | v_dspcur | Output |
| 5 | 19 | v_rmcur | Output |
| 6 | -- | v_pline | Output |
| 7 | -- | v_pmarker | Output |
| 8 | -- | v_gtext | Output |
| 9 | -- | v_fillarea | Output |
| 11 | 1 | v_bar | Output |
| 11 | 2 | v_arc | Output |
| 11 | 3 | v_pieslice | Output |
| 11 | 4 | v_circle | Output |
| 11 | 5 | v_ellipse | Output |
| 11 | 6 | v_ellarc | Output |
| 11 | 7 | v_ellpie | Output |
| 11 | 8 | v_rbox | Output |
| 11 | 9 | v_rfbox | Output |
| 11 | 10 | v_justified | Output |
| 12 | -- | vst_height | Attribute |
| 13 | -- | vst_rotation | Attribute |
| 14 | -- | vs_color | Attribute |
| 15 | -- | vsl_type | Attribute |
| 16 | -- | vsl_width | Attribute |
| 17 | -- | vsl_color | Attribute |
| 18 | -- | vsm_type | Attribute |
| 19 | -- | vsm_height | Attribute |
| 20 | -- | vsm_color | Attribute |
| 21 | -- | vst_font | Attribute |
| 22 | -- | vst_color | Attribute |
| 23 | -- | vsf_interior | Attribute |
| 24 | -- | vsf_style | Attribute |
| 25 | -- | vsf_color | Attribute |
| 26 | -- | vq_color | Inquire |
| 32 | -- | vswr_mode | Attribute |
| 33 | -- | vsin_mode | Input |
| 35 | 0 | vql_attributes | Inquire |
| 35 | -- | vsl_ends | Attribute |
| 36 | 0 | vqm_attributes | Inquire |
| 36 | -- | vsf_perimeter | Attribute |
| 37 | -- | vqf_attributes | Inquire |
| 38 | 0 | vqt_attributes | Inquire |
| 38 | -- | vst_effects | Attribute |
| 39 | -- | vst_alignment | Attribute |
| 100 | 1 | v_opnvwk | Workstation |
| 101 | 1 | v_clsvwk | Workstation |
| 102 | -- | vq_extnd | Inquire |
| 104 | -- | vrq_locator | Input |
| 105 | -- | vsm_locator | Input |
| 106 | -- | vst_point | Attribute |
| 107 | -- | vsl_udsty | Attribute |
| 108 | -- | vr_recfl | Output |
| 109 | -- | vro_cpyfm | Raster |
| 110 | -- | v_contourfill | Output |
| 111 | -- | vr_trnfm | Raster |
| 112 | -- | vsc_form | Input |
| 113 | -- | vsf_udpat | Attribute |
| 114 | -- | vsl_udsty | Attribute |
| 116 | -- | vqt_extent | Inquire |
| 117 | -- | vqt_width | Inquire |
| 121 | -- | vrt_cpyfm | Raster |
| 122 | -- | v_show_c | Input |
| 123 | -- | v_hide_c | Input |
| 124 | -- | vq_mouse | Inquire |
| 125 | -- | vex_butv | Input |
| 126 | -- | vex_motv | Input |
| 127 | -- | vex_curv | Input |
| 128 | -- | vq_key_s | Inquire |
| 129 | -- | vs_clip | Attribute |
| 130 | -- | vqt_name | Inquire |
| 131 | -- | vqt_fontinfo | Inquire |

---

## Appendix: Token Numbers for GEM Commands

These are the token values assigned to AES/VDI commands in the interpreter's
token table (from `BASIC_COMMENTS.S` lines 225-237):

| Token | Hex | Command |
|------:|-----|---------|
| $015D | 015D | AESCTRL |
| $015E | 015E | AESINTIN |
| $015F | 015F | AESINTOUT |
| $0160 | 0160 | AESADRIN |
| $0161 | 0161 | AESADROUT |
| $0162 | 0162 | VDICTRL |
| $0163 | 0163 | VDIINTIN |
| $0164 | 0164 | VDIINTOUT |
| $0165 | 0165 | VDIPTSIN |
| $0166 | 0166 | VDIPTSOUT |
| $0167 | 0167 | AES |
| $0168 | 0168 | VDI |
| $0200 | 0200 | LINE (class 2) |
| $0300 | 0300 | LINE (class 3) |

The dual-class LINE tokens ($02xx / $03xx) allow the tokenizer to handle
`LINE` in both command context (class 2 = $0200) and function/expression
context (class 3 = $0300).

---

## Appendix: Memory Layout of AES/VDI Arrays in BSS

From `BASIC_COMMENTS.S` lines 10582-10604:

```
AESctrl:    10 words   (20 bytes)   -- AES control array
AESintin:   128 words  (256 bytes)  -- AES integer input
AESintout:  128 words  (256 bytes)  -- AES integer output
AESadrin:   128 longs  (512 bytes)  -- AES address input
AESadrout:  128 longs  (512 bytes)  -- AES address output

VDIctrl:    12 words   (24 bytes)   -- VDI control array
VDIintin:   128 words  (256 bytes)  -- VDI integer input
VDIintout:  128 words  (256 bytes)  -- VDI integer output
VDIptsin:   128 words  (256 bytes)  -- VDI coordinate input
VDIptsout:  128 words  (256 bytes)  -- VDI coordinate output

AESglobal:  10 longs   (40 bytes)   -- AES global (filled by appl_init)
```

Total: 2,604 bytes of BSS for GEM communication arrays.

---

*Document generated from reverse-engineered source analysis of the STAD BASIC
interpreter (November 1988). Source files: `BASIC_COMMENTS.S`, `HEADER.S`.*
