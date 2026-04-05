# BASIC-SYMBOLS.md -- Symbol Map & Navigation Guide

Source code navigation reference for the Atari ST BASIC Interpreter (68000 assembly).
All line numbers refer to the **annotated** source files in `src/`.

---

## 1. Overview

| Module | Lines | Purpose |
|--------|------:|---------|
| `HEADER.S` | 514 | Program entry point, STAD interface, Init/Edit/Run, character renderer |
| `EDITOR.S` | 1105 | Full-screen text editor (25x80), cursor, scrolling, key handling |
| `BLIBF.S` | 3330 | BCD floating-point math library (22-digit precision) |
| `DATA.S` | 39 | Shared global memory pointers (program, variables, strings) |
| `BASIC_COMMENTS.S` | 10612 | Main interpreter: tokenizer, execution engine, commands, expression evaluator, garbage collector, I/O, error handling |
| **Total** | **15600** | |

Architecture: Program lines as linked list (`prgbase..prgend`), variables as linked list (`varbase..varend`), strings stored backwards growing downward (`strend..strbase`). Three types: FLOAT=1, INT=2, STRING=4. Token system with 3 classes ($01xx, $02xx, $03xx).

---

## 2. HEADER.S -- Entry Point & Initialization

### Key Routines

| Symbol | Line | Description |
|--------|-----:|-------------|
| *(entry)* | 72 | Standalone entry: `lea datas,a0` / call Init / call Edit / Pterm0 |
| `edibase` | 85 | Pointer to STAD structure instance |
| `initcode` | 86 | Pointer to `Init` routine (for STAD embedding) |
| `editcode` | 87 | Pointer to `Edit` routine |
| `runcode` | 88 | Pointer to `Run` routine |
| `Init` | 110 | Initialize interpreter+editor (a0=membase, d0=memsize; returns 0 or -1) |
| `Edit` | 211 | Enter interactive editor loop (`jmp ed_editor`) |
| `Run` | 236 | Execute BASIC commands directly (d0=mode, a0=param) |
| `RunLoad` | 244 | Mode 0: build `load "file":run` and execute |
| `RunProc` | 259 | Mode 1: build `clr:procname` and execute |
| `RunRun` | 272 | Mode 2: build `run N` and execute |
| `copya1a0` | 309 | Copy NUL-terminated string from a1 to a0 |
| `_g_char` | 354 | Character renderer: d0=char, d1=X pixels, d2=Y pixels |
| `g8char` | ~366 | 8x8 font rendering path (branch target) |

### STAD Structure EQU Constants

| Constant | Offset | Type | Description |
|----------|-------:|------|-------------|
| `edi_base` | 0 | long | Physical screen base address |
| `edi_screen` | 4 | long | Screen width in bytes |
| `edi_plan` | 8 | word | (unused/reserved) |
| `edi_x` | 10 | word | Window X offset in pixels |
| `edi_y` | 12 | word | Window Y offset in pixels |
| `edi_ext` | 14 | long | (reserved/extension) |
| `edi_breit` | 18 | word | Window width in pixels |
| `edi_hoch` | 20 | word | Window height in pixels |
| `edi_maxzeilen` | 22 | word | Max editor rows |
| `edi_maxspalten` | 24 | word | Max editor columns |
| `edi_tab` | 26 | word | Tab stop interval |
| `edi_print` | 28 | long | Character output callback pointer |
| `edi_pgblock` | 32 | long | Line-A routine variables base |
| `edi_vrblock` | 36 | long | System variables block base |
| `edi_retprg` | 40 | long | Return-to-program callback (0=BASIC) |
| `edi_preup` | 44 | long | Pre-scroll-up callback |
| `edi_up` | 48 | long | Post-scroll-up callback |
| `edi_predown` | 52 | long | Pre-scroll-down callback |
| `edi_down` | 56 | long | Post-scroll-down callback |
| `edi_font` | 60 | long | Font header pointer |
| `edi_y_shft` | 64 | word | Bit-shift for font height (4=16px, 3=8px) |

---

## 3. DATA.S -- Shared Global Memory Pointers

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `editscreen` | 33 | long | Base address of editor screen buffer (25x80 chars) |
| `prgbase` | 34 | long | Base address of tokenized BASIC program |
| `prgend` | 35 | long | End of BASIC program (first free byte after) |
| `varbase` | 36 | long | Base of variable storage (relocatable) |
| `varend` | 37 | long | End of variable storage |
| `strbase` | 38 | long | Upper boundary of string heap (fixed) |
| `strend` | 39 | long | Current bottom of string heap (grows down) |

---

## 4. EDITOR.S -- Full-Screen Text Editor

### Key Routines

| Symbol | Line | Description |
|--------|-----:|-------------|
| `ed_editor` | 98 | Editor main loop entry point |
| `ed_edit` | 208 | Process one keystroke |
| `ed_display` | 167 | Redraw full screen from buffer |
| `ed_homepos` | 150 | Move cursor to home position (0,0) |
| `ed_clrmem` | 127 | Fill editor buffer with spaces ($20) |
| `ed_newline` | 392 | Handle RETURN key (send line to BASIC) |
| `ed_clr` | 422 | Clear current line |
| `ed_clrhome` | 432 | Clear screen and home cursor |
| `ed_clrline` | 463 | Clear from cursor to end of line |
| `ed_backspace` | 490 | Handle backspace (delete char left of cursor) |
| `ed_insert` | 502 | Insert a character at cursor position |
| `ed_delete` | 541 | Delete character at cursor position |
| `ed_tab` | 583 | Handle TAB key |
| `ed_store` | 630 | Store character into editor buffer at cursor |
| `ed_runter` | 678 | Move cursor down one line |
| `ed_hoch` | 763 | Move cursor up one line |
| `ed_rechts` | 841 | Move cursor right one column |
| `ed_links` | 892 | Move cursor left one column |
| `ed_prline` | 937 | Print one line from editor buffer to screen |
| `ed_print` | 993 | Output single char via edi_print callback |
| `ed_pos` | 1034 | Compute pixel position from cursor coords |
| `ed_curon` | 251 | Enable cursor display |
| `ed_curoff` | 252 | Disable cursor display |
| `ed_tstcmd` | 333 | Test for special key commands (arrows, DEL, etc.) |
| `ed_clrask` | 408 | Handle SHIFT+CLR (clear screen prompt) |
| `ed_delask` | 447 | Handle CTRL+DEL (clear line) |
| `delay` | 1070 | Short delay loop |
| `waitctrl` | 1073 | Wait for CTRL key release |
| `waitshift` | 1084 | Wait for SHIFT key release |

### BSS Variables

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `ed_xoffs` | 1100 | word | Horizontal scroll offset |
| `ed_x` | 1101 | word | Current cursor column (visible, 0-based) |
| `ed_y` | 1102 | word | Current cursor row (0-based) |
| `edi_yshft` | 1104 | word | Font height bit-shift (4=16px, 3=8px) |

---

## 5. BLIBF.S -- BCD Floating-Point Library

BCD format: 4 registers (d0-d3), 22-digit mantissa, exponent biased at $4000. Special: exp 0 = zero (tiny), $7FFF = infinity (huge).

### Comparison

| Symbol | Line | Description |
|--------|-----:|-------------|
| `facscmp` | 126 | Compare fac1 with fac2 (signed float) |
| `strcmp` | 153 | Compare two strings |
| `rcmp_` | 193 | Compare two floats (d0-d3 vs d4-d7) |

### Trigonometric

| Symbol | Line | Description |
|--------|-----:|-------------|
| `rsin_` | 354 | Sine |
| `rcos_` | 374 | Cosine |
| `rtan_` | 326 | Tangent |
| `ratan_` | 246 | Arctangent (single arg) |
| `ratan2_` | 266 | Arctangent (two args, atan2) |
| `rtanr_` | 719 | Tangent ratio decomposition (internal) |
| `sincos_` | 771 | Sine/cosine common path |

### Exponential / Logarithm

| Symbol | Line | Description |
|--------|-----:|-------------|
| `rexp_` | 401 | e^x |
| `rexp10_` | 422 | 10^x |
| `rlog_` | 467 | Natural logarithm (ln) |
| `rlog10_` | 492 | Base-10 logarithm (log) |

### Algebraic

| Symbol | Line | Description |
|--------|-----:|-------------|
| `rsqrt_` | 545 | Square root |
| `rrand_` | 619 | Random number generator |
| `rmod_` | 808 | Modulo (IEEE remainder) |
| `rrem_` | 1134 | IEEE remainder (internal) |

### Core Arithmetic

| Symbol | Line | Description |
|--------|-----:|-------------|
| `radd_` | 1986 | BCD addition |
| `rsub_` | 1964 | BCD subtraction (negates then adds) |
| `rmul_` | 2356 | BCD multiplication |
| `rdiv_` | 2557 | BCD division |
| `imul` | 2239 | Integer multiply |
| `idiv` | 2257 | Integer divide |

### Conversion

| Symbol | Line | Description |
|--------|-----:|-------------|
| `rlda_` | 1329 | ASCII string to BCD float |
| `rpka_` | 1704 | BCD float to ASCII string |
| `ipka_` | 1601 | Integer to ASCII string |
| `rpkl` | 2803 | Float to integer (via pointer) |
| `rpkl_` | 2809 | Float to integer (direct) |
| `ltor_` | 1924 | Integer (d4) to BCD float |
| `rldl_` | 2786 | Load float via pointer indirection |

### Normalization & Shifting

| Symbol | Line | Description |
|--------|-----:|-------------|
| `norm_` | 1465 | Normalize BCD float |
| `dnorm_` | 650 | Denormalize (shift right to match exponent) |
| `normx_` | 2459 | Normalize extended result |
| `mul_10_` | 1432 | Multiply mantissa by 10 |
| `div_10_` | 1534 | Divide mantissa by 10 |
| `mul_100_` | 1512 | Multiply mantissa by 100 |
| `div_100_` | 1564 | Divide mantissa by 100 |
| `rnd_` | 2942 | Round BCD float |
| `rrndn_` | 2862 | Round to N digits |

### Pseudo-Division / Pseudo-Multiplication

| Symbol | Line | Description |
|--------|-----:|-------------|
| `psatan_` | 686 | PS-division for arctangent |
| `pslog_` | 919 | PS-division for logarithm |
| `psexp_` | 877 | PS-multiplication for exponential |
| `pssqrt_` | 979 | PS-division for square root |
| `psdivlog_` | 826 | PS-division with log table |
| `psdivq_` | 2625 | PS-division quotient extraction |
| `psmulq_` | 2413 | PS-multiplication quotient |
| `psmullog_` | 969 | PS-multiply with log table |
| `pstan_` | 1091 | PS-division for tangent |
| `psrmul_` | 2389 | PS-remainder multiply |
| `ps0_` | 2694 | PS common init |
| `ps1_` | 2709 | PS common exit |
| `psadd_` | 2187 | PS BCD add (fraction level) |
| `pssub_` | 2065 | PS BCD subtract (fraction level) |
| `qdiv_10_` | 2520 | Shift quotient right by one digit |
| `qmul_10_` | 2725 | Shift quotient left by one digit |
| `amul_10_` | 2744 | Multiply accumulator A by 10 |

### Error Handlers (Float)

| Symbol | Line | Code | Description |
|--------|-----:|-----:|-------------|
| `SOVER_` | 3065 | 6 | Overflow |
| `SUNDER_` | 3067 | 7 | Underflow |
| `SDIVIDE_` | 3069 | 8 | Division by zero |
| `NSQRN_` | 3061 | 4 | Square root of negative |
| `NLOGN_` | 3063 | 5 | Log of negative |
| `NSIGNAL_` | 3049 | -- | General signal handler |
| `SINEXACT_` | 3052 | -- | Inexact result |
| `NADDI_` | 3050 | 2 | Invalid operand (add/sub) |
| `NACOS_` | 3059 | 3 | Domain error (acos/asin) |

### Constants

| Symbol | Line | Value | Description |
|--------|-----:|-------|-------------|
| `zero_` | 3088 | 0.0 | Zero constant |
| `one_` | 3151 | 1.0 | One constant |
| `pi_` | 3157 | 3.14159... | Pi |
| `halfpi_` | 3164 | 1.57079... | Pi/2 |
| `loge_` | 3172 | 0.43429... | log10(e) |
| `ln10_` | 3180 | 2.30258... | ln(10) |
| `Fatntab_` | 3214 | -- | Arctangent lookup table |
| `Flogtab_` | 3244 | -- | Logarithm lookup table |
| `etiny_` | 3015 | -- | Return tiny (zero) |
| `ehuge_` | 3029 | -- | Return huge (infinity) |

### BSS (Work Registers)

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `fac1` | 3294 | 6 longs | Primary float accumulator |
| `fac2` | 3295 | 6 longs | Secondary float accumulator |
| `fl1work`..`fl10work` | 3320-3329 | 6 longs each | Temporary work registers |
| `iout` | 3269 | 20 bytes | Integer-to-ASCII output buffer |
| `ioutend` | 3270 | 2 bytes | End marker for iout |
| `X_` | 3283 | $26 bytes | Extended workspace |
| `X2_` | 3284 | $26 bytes | Extended workspace 2 |
| `ascii` | 3143 | 6 bytes | ASCII conversion buffer |

---

## 6. BASIC_COMMENTS.S -- Main Interpreter

### 6.1 Constants & Structure Definitions (lines 37-100)

**STAD Structure EQU offsets** -- see Section 2 above (duplicated in both HEADER.S and BASIC_COMMENTS.S).

**Constants:**

| Symbol | Line | Value | Description |
|--------|-----:|-------|-------------|
| `anzops` | 70 | 13 | Number of operators (+ - * / ^ < = > { } ~ & \|) |
| `HEADER` | 72 | $48454144 | Magic "HEAD" for saved BASIC files |
| `ARRAYTYP` | 79 | $8000 | Bit 15: variable is an array |
| `FNTYP` | 80 | $4000 | Bit 14: FN argument variable |
| `DEFFNTYP` | 81 | $2000 | Bit 13: DEF FN function definition |
| `PROCTYP` | 82 | $1000 | Bit 12: PROC definition |
| `FLOAT` | 89 | 1 | Float type code |
| `INT` | 88 | 2 | Integer type code |
| `STRING` | 87 | 4 | String type code |
| `TOKEN1` | 98 | 1 | Token class 1 intro byte ($01xx) |
| `TOKEN2` | 99 | 2 | Token class 2 intro byte ($02xx) |
| `TOKEN3` | 100 | 3 | Token class 3 intro byte ($03xx) |

### 6.2 Interpreter Core (lines 275-1040)

**Output:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `tab_` | 275 | TAB output handler |
| `putstrreverse` | 298 | Print string stored in reverse |
| `put_string` | 322 | Print NUL-terminated string |
| `new_line` | 747 | Output CR/newline |

**Control:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `ed_chkstop` | 362 | Check for user break (Ctrl-C) from editor scroll |
| `chk_stop` | 367 | Check for user break during execution |
| `b_init` | 407 | BASIC interpreter initialization |
| `basic_` | 435 | Real BASIC initialization start |
| `basic1` | 451 | Main BASIC prompt loop start |
| `basic2` | 457 | Process entered line |
| `posquit` | 504 | Position to quit |
| `quit` | 508 | Exit BASIC |

**Entry:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `b_enter` | 535 | Enter BASIC direct mode (from editor RETURN) |
| `b_runcode` | 537 | Tokenize and execute a command string (a0=str, d0=len) |

**Line Management:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `zeilenverwaltung` | 582 | Line management dispatcher |
| `insline` | 592 | Insert line into program listing |
| `delline` | 597 | Delete line (only line number entered) |
| `delline2` | 605 | Delete line at d0=line#, a1=node ptr |
| `basic20` | 649 | Find insertion point for new line |
| `basic2a` | 651 | Find end of line (scan for double-NUL) |
| `basic2b` | 660 | Continue line insertion |
| `basic2c` | 711 | Create new line entry at position a1 |
| `basic2d` | 705 | Old line shorter/equal: append space |
| `basic2e` | 677 | Shift program+variables down |
| `basic2f` | 683 | Relink program line pointers |
| `basic2g` | 721 | Copy backwards (high to low) |
| `basic2h` | 728 | Copy new line data into program |
| `basic2j` | 725 | Relinking displacement calculation |
| `endezv` | 737 | End of line management |

**Tokenizer:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `konv_inpuf` | 828 | Tokenize input buffer |
| `konvCmd` | 875 | Tokenize a command keyword |
| `tokenfound` | 946 | Token match found handler |
| `token2found` | 953 | Secondary token found |
| `konvend` | 974 | End of tokenization |
| `clrendpuf` | 981 | Append NUL terminators to output buffer |

### 6.3 Execution Engine (lines 1043-1160)

| Symbol | Line | Description |
|--------|-----:|-------------|
| `exec_puf` | 1043 | Execute tokenized buffer |
| `exec_line` | 1060 | Execute one program line |
| `exec1` | 1061 | Execution entry (after line setup) |
| `notrace` | 1073 | Skip trace output |
| `execnotrace` | 1078 | Execute without trace |
| `onlyexec` | 1132 | Execute single command (dispatch) |
| `exec2a` | 1138 | Check direct-mode-only bit (bit 29) |
| `exec2b` | 1143 | Mask flag bits, keep 24-bit address |
| `exec3` | 1147 | JSR to command routine |
| `exec_end` | 1154 | End of execution (return to loop) |

### 6.4 Variable System (lines 1174-1970)

**Definition:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `var_def` | 1174 | Variable definition (assignment: `var = expr`) |
| `var2_def` | 1241 | Variable definition alternate entry |
| `var3_def` | 1244 | Entry after sysvar test |
| `mark_str` | 1277 | Mark string in string space |

**Array Access:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `posarray` | 1304 | Position into array element |
| `posa0` | 1314 | Array access: compute linear index |
| `posa1` | 1347 | Array bounds checking |
| `posa2` | 1321 | Array element offset calc |

**Read / Write:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `write_var` | 1392 | Write value to variable (dispatch by type) |
| `write_int` | 1401 | Write integer to variable |
| `write_fl` | 1404 | Write float to variable |
| `write_str` | 1408 | Write string to variable |
| `read_var` | 1422 | Read value from variable (dispatch by type) |
| `read_int` | 1429 | Read integer from variable |
| `read_fl` | 1432 | Read float from variable |
| `read_str` | 1436 | Read string from variable |

**Creation:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `create2_var` | 1461 | Create variable (alternate entry) |
| `create_var` | 1469 | Create new variable in var space |

**Lookup:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `tst_var` | 1601 | Look up variable by name |
| `tst2_var` | 1603 | Look up variable (alternate entry) |
| `tst_prcvar` | 1576 | Look up procedure-scope variable |
| `tst_dprcvar` | 1580 | Look up DEF-PROC-scope variable |
| `tst_dfnvar` | 1584 | Look up DEF-FN-scope variable |
| `tst_fnvar` | 1590 | Look up FN argument variable |
| `tstspecVar` | 1586 | Error if system variable found |
| `tstsysvar` | 1593 | System variable check |
| `tvar_found` | 1806 | Variable found handler |
| `tst_vend` | 1816 | Variable not found (end of chain) |

**System Variables:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `TiInt` | 1744 | TI system variable (integer timer ticks) |
| `TiString` | 1751 | TI$ system variable (time string) |
| `PiInt` | 1764 | PI system constant (float) |
| `settistr` | 1837 | Set TI$ value |
| `readtistr` | 1867 | Read TI$ value |
| `readtime` | 1889 | Read system time (XBIOS) |
| `writetime` | 1905 | Write system time (XBIOS) |

### 6.5 BASIC Commands (lines 1992-6920)

| Symbol | Line | BASIC Keyword | Description |
|--------|-----:|---------------|-------------|
| `Hex` | 1992 | HEX$ | Integer to hex string |
| `Bin` | 2032 | BIN$ | Integer to binary string |
| `Dir` | 2051 | DIR | Directory listing |
| `Varptr` | 2189 | VARPTR | Get variable memory address |
| `Aes` | 2217 | AES | Invoke AES call |
| `Vdi` | 2222 | VDI | Invoke VDI call |
| `Gemdos` | 2429 | GEMDOS | GEMDOS system call |
| `Bios` | 2433 | BIOS | BIOS system call (trap #13) |
| `Xbios` | 2436 | XBIOS | XBIOS system call (trap #14) |
| `Cursor` | 2539 | CURSOR | Set cursor position |
| `Home` | 2568 | HOME | Clear and home cursor |
| `Cls` | 2575 | CLS | Clear screen |
| `Cont` | 2584 | CONT | Continue after STOP |
| `Stop` | 2597 | STOP | Stop program execution |
| `Call` | 2613 | CALL | Call machine code subroutine |
| `Sys` | 2704 | SYS | System call command |
| `Rnd` | 2735 | RND | Random number |
| `Sgn` | 2769 | SGN | Sign function |
| `Abs` | 2812 | ABS | Absolute value |
| `Sqr` | 2835 | SQR | Square root |
| `Ln` | 2838 | LN | Natural logarithm |
| `Log` | 2841 | LOG | Base-10 logarithm |
| `Exp10` | 2844 | EXP10 | 10^x |
| `Exp` | 2847 | EXP | e^x |
| `Tan` | 2850 | TAN | Tangent |
| `Atn` | 2890 | ATN | Arctangent |
| `Atnpt` | 2868 | ATANPT | Two-argument arctangent (atan2) |
| `Mod` | 2859 | MOD | Modulo |
| `Cos` | 2893 | COS | Cosine |
| `Sin` | 2896 | SIN | Sine |
| `Lpeek` | 2924 | LPEEK | Read 32-bit longword from address |
| `Dpeek` | 2935 | DPEEK/WPEEK | Read 16-bit word from address |
| `Peek` | 2947 | PEEK | Read 8-bit byte from address |
| `Lpoke` | 2962 | LPOKE | Write 32-bit longword to address |
| `Dpoke` | 2987 | DPOKE/WPOKE | Write 16-bit word to address |
| `Poke` | 2992 | POKE | Write 8-bit byte to address |
| `Cmd` | 3010 | CMD | Redirect output to file |
| `Not` | 3028 | NOT | Bitwise/logical NOT |
| `Pos` | 3043 | POS | Cursor position function |
| `Mid` | 3060 | MID$ | Middle substring |
| `Right` | 3092 | RIGHT$ | Right substring |
| `Left` | 3105 | LEFT$ | Left substring |
| `Instr` | 3118 | INSTR | Search string |
| `Chr` | 3238 | CHR$ | ASCII code to character |
| `Inkey` | 3259 | INKEY$ | Read key without waiting |
| `Wait` | 3275 | WAIT | Pause execution |
| `Auto` | 3295 | AUTO | Auto line numbering |
| `Tron` | 3321 | TRON | Trace on |
| `Troff` | 3324 | TROFF | Trace off |
| `Dump` | 3466 | DUMP | Dump variables |
| `Swapvars` | 3739 | SWAP | Swap two variables |
| `Asc` | 3818 | ASC | Character to ASCII code |
| `Val` | 3832 | VAL | String to number |
| `Function` | 3833 | FUNCTION | Function keyword |
| `Str` | 3868 | STR$ | Number to string |
| `Len` | 3901 | LEN | String length |
| `Get` | 3922 | GET | Get single character from keyboard/file |
| `Restore` | 4044 | RESTORE | Reset DATA pointer |
| `Read` | 4103 | READ | Read from DATA |
| `Else` | 4154 | ELSE | IF..ELSE branch |
| `If` | 4173 | IF | Conditional |
| `Next` | 4248 | NEXT | End of FOR loop |
| `For` | 4311 | FOR | Begin FOR loop |
| `Close` | 4385 | CLOSE | Close file |
| `Open` | 4438 | OPEN | Open file |
| `Create` | 4435 | CREATE | Create file |
| `On` | 4498 | ON | ON..GOTO/GOSUB |
| `Input` | 4566 | INPUT | Read user input |
| `Fn` | 4842 | FN | Call user-defined function |
| `Deffn` | 4926 | DEF FN | Define function |
| `Local` | 5070 | LOCAL | Declare local variables in procedure |
| `Proc` | 5305 | PROC | Call/define procedure |
| `Endproc` | 5405 | ENDPROC | End procedure definition |
| `Help` | 5438 | HELP | Display keyword list |
| `Prgfre` | 5470 | FRE (program) | Free program memory |
| `Varfre` | 5471 | FRE (variable) | Free variable memory |
| `Strfre` | 5494 | STRFRE | Free string space |
| `Edtab` | 5533 | EDTAB | Set editor tab width |
| `Tab` | 5562 | TAB | Tab to column in PRINT |
| `Spc` | 5607 | SPC | Output spaces in PRINT |
| `Int` | 5634 | INT | Truncate to integer |
| `New` | 5651 | NEW | Clear program and variables |
| `Clr` | 5686 | CLR | Clear all variables |
| `Return` | 5791 | RETURN | Return from subroutine |
| `Gosub` | 5838 | GOSUB | Call subroutine |
| `Goto` | 5876 | GOTO | Branch to line number |
| `Run` | 5897 | RUN | Execute program |
| `Merge` | 6019 | MERGE | Merge program from file |
| `Convert` | 6083 | CONVERT | Convert file format |
| `Load` | 6160 | LOAD | Load program from file |
| `Save` | 6212 | SAVE | Save program to file |
| `Delete` | 6472 | DELETE | Delete program lines |
| `List` | 6507 | LIST | List program lines |
| `Dim` | 6719 | DIM | Dimension arrays |
| `Print` | 6823 | PRINT | Output to screen/file |

**Additional command helpers:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `Aesctrl` | 2289 | AES control array access |
| `Aesintin` | 2295 | AES intin array access |
| `Aesintout` | 2301 | AES intout array access |
| `Aesadrin` | 2307 | AES addrin array access |
| `Aesadrout` | 2313 | AES addrout array access |
| `Vdictrl` | 2320 | VDI control array access |
| `Vdiintin` | 2326 | VDI intin array access |
| `Vdiintout` | 2332 | VDI intout array access |
| `Vdiptsin` | 2338 | VDI ptsin array access |
| `Vdiptsout` | 2344 | VDI ptsout array access |
| `Localdim` | 6728 | LOCAL DIM (local array inside PROC) |
| `Getkey` | 3944 | Read key from console device |
| `mirror_str` | 2506 | Mirror (reverse) a string |
| `callsys` | 2438 | Common GEMDOS/BIOS/XBIOS dispatcher |
| `calltrap` | 2488 | Self-modifying trap instruction |
| `get_handle` | 4400 | Get file handle from argument |
| `openfile` | 4440 | Common open/create handler |
| `get_procs` | 5165 | Scan program for procedure definitions |
| `checkforproc` | 5126 | Check if inside a procedure |
| `listlines` | 6608 | List program lines (inner loop) |
| `tstlinenr` | 6525 | Test for line number in LIST args |
| `tst_prgheader` | 5994 | Verify BASIC file header magic |
| `init_tbls` | 5762 | Initialize control flow stacks |
| `b_preup` | 6359 | BASIC pre-scroll-up callback |
| `b_predown` | 6360 | BASIC pre-scroll-down callback |
| `b_up` | 6390 | BASIC post-scroll-up callback |
| `b_down` | 6417 | BASIC post-scroll-down callback |
| `listoneline` | 6442 | List a single program line |
| `trace` | 3339 | Trace execution handler |
| `dumparray` | 3664 | Dump array contents |
| `dumptext` | 3617 | Dump text representation of variable |

### 6.6 Expression Evaluator (lines 6968-7870)

| Symbol | Line | Description |
|--------|-----:|-------------|
| `get_aterm` | 6968 | Get array term (save context) |
| `gets_term` | 6999 | Get string term |
| `get_ckterm` | 7023 | Get term with type checking |
| `get_defterm` | 7043 | Get term for string definitions |
| `get_term` | 7063 | Get expression term (main entry) |
| `get1_term` | 7154 | Get unary term |
| `get2_term` | 7204 | Get binary term (operator loop) |
| `get3_term` | 7162 | Get numeric term |
| `get_element` | 7441 | Get atomic element (number, variable, parenthesized expr) |
| `get_str` | 7495 | Get string expression |
| `resv_str` | 7516 | Reserve string space |
| `copy_str` | 7546 | Copy/concatenate string |
| `copy2_str` | 7549 | Copy string (alternate entry) |
| `get_var_konst` | 7664 | Get variable or constant value |
| `getvtstneg` | 7739 | Get value, test for negation |
| `tstnegfloat` | 7750 | Test and apply float negation |
| `no_var` | 7790 | No variable found handler |
| `get_var` | 7824 | Get variable value |
| `get_strkonst` | 7860 | Get string constant |
| `get_hexvar` | 7885 | Parse hex literal ($xxxx) |
| `get_binvar` | 7923 | Parse binary literal (%xxxx) |
| `get_fkt` | 7968 | Get function result (dispatch to built-in) |
| `get_operator` | 8055 | Parse operator token |
| `to_next_op` | 7368 | Advance to next operator in expression |
| `exec_operation` | 7405 | Execute pending operation |

**Type Conversion:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `konvfl` | 7116 | Convert to float |
| `konvint` | 7100 | Convert to integer |
| `konvstr` | 7087 | Convert to string |

### 6.7 Operators (lines 8150-8570)

**Comparison:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `Lower` | 8150 | Less-than operator |
| `Higher` | 8183 | Greater-than operator |
| `Equal` | 8210 | Equality operator |
| `cmptrue` | 8226 | Return true (-1) from comparison |
| `cmpfalse` | 8242 | Return false (0) from comparison |

**Bitwise:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `ShL` | 8272 | Shift left ({) |
| `ShR` | 8285 | Shift right (}) |
| `Xor` | 8298 | Exclusive OR (~) |
| `And` | 8311 | Bitwise AND (&) |
| `Or` | 8323 | Bitwise OR (\|) |
| `convint` | 8361 | Convert operands to int before bitwise op |
| `reconvint` | 8341 | Reconvert result back to float if needed |

**Arithmetic:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `Add` | 8392 | Addition (+) |
| `Sub` | 8411 | Subtraction (-) |
| `Mul` | 8546 | Multiplication (*) |
| `Div` | 8500 | Division (/) |
| `Exponent` | 8437 | Exponentiation (^) |

**Helpers:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `lateconv` | 8521 | Late type conversion for mixed operations |
| `submul` | 8567 | Subtract-multiply helper |
| `sgnfl` | 8436 | Sign flag storage (word) |

### 6.8 Utility Routines (lines 8585-9075)

| Symbol | Line | Description |
|--------|-----:|-------------|
| `chk_klammer` | 8585 | Check and consume closing parenthesis ')' |
| `tst_komma` | 8598 | Test for comma separator |
| `chk_komma` | 8611 | Check and consume comma (error if missing) |
| `chargot` | 8631 | Re-read current character (no advance) |
| `charget` | 8644 | Get next character from program text |
| `charget6` | 8661 | Charget returning result in d6 (for BLIBF) |
| `onqlist` | 8689 | Push string pointer onto protection queue |
| `offqlist` | 8707 | Pop string pointer from protection queue |
| `save_vname` | 8984 | Save variable name to buffer |
| `load_vname` | 9001 | Restore variable name from buffer |
| `get_int` | 9024 | Evaluate expression and convert to integer |
| `setdrv` | 9062 | Set drive from filename path |
| `isvarname` | 1006 | Test if current char starts a variable name |
| `isvarn` | 1000 | Test if char is valid in variable name |

### 6.9 Garbage Collector (lines 8751-8980)

| Symbol | Line | Description |
|--------|-----:|-------------|
| `garbage` | 8751 | Main garbage collection entry |
| `garb1` | 8774 | GC: scan phase |
| `killstr` | 8788 | Mark string as dead |
| `garb_var` | 8860 | GC: scan variable chain |
| `garb_reg` | 8839 | GC: scan register save area |
| `garb_qlist` | 8823 | GC: scan string protection queue |
| `garbstr` | 8904 | GC: compact string |
| `garbsearch` | 8918 | GC: search for string owner |
| `garbarray` | 8959 | GC: process array variables |
| `linkstr` | 8940 | GC: adjust string pointer if moved |
| `nextstr` | 8881 | GC: advance to next string |

### 6.10 File I/O (lines 9100-9280)

| Symbol | Line | Description |
|--------|-----:|-------------|
| `f_create` | 9100 | GEMDOS Fcreate wrapper |
| `f_open` | 9119 | GEMDOS Fopen wrapper |
| `f_write` | 9162 | GEMDOS Fwrite wrapper |
| `f_read` | 9188 | GEMDOS Fread wrapper |
| `f_close` | 9210 | GEMDOS Fclose wrapper |
| `new_link` | 9235 | Relink program lines after insertion |
| `poszeile` | 9266 | Find line by number in program |
| `preline` | 9265 | Storage for previous line pointer |

### 6.11 Command Flow (lines 9298-9440)

| Symbol | Line | Description |
|--------|-----:|-------------|
| `tstnxtarg` | 9298 | Test if another argument follows separator |
| `tonxtcmd` | 9322 | Skip to next command (past ':') |
| `dtonxtcmd` | 9342 | Skip to next command (data-aware, respects strings) |
| `line` | 9385 | LINE drawing command |

### 6.12 Error Handling (lines 9444-9705)

**Error Entry Points:**

| Symbol | Line | Code | Error Message |
|--------|-----:|-----:|---------------|
| `syntaxerr` | 9613 | 0 | "syntax" |
| `typemis` | 9610 | 1 | "type mismatch" |
| `badsubscr` | 9607 | 9 | "bad subscript" |
| `outvarmem` | 9604 | 10 | "out of variable space" |
| `redef` | 9601 | 11 | "re-define" |
| `dimerr` | 9598 | 12 | "dim" |
| `outprgmem` | 9595 | 13 | "out of program space" |
| `createrr` | 9592 | 14 | "file create" |
| `writerr` | 9589 | 15 | "file write" |
| `openerr` | 9586 | 16 | "file open" |
| `readerr` | 9583 | 17 | "file read" |
| `dircterr` | 9580 | 18 | "illegal direct" |
| `nexterr` | 9577 | 19 | "next without for" |
| `forflow` | 9574 | 20 | "for-next overflow" |
| `prgmerr` | 9571 | 21 | "illegal prg. mode" |
| `goserr` | 9568 | 22 | "return without gosub" |
| `gosflow` | 9565 | 23 | "gosub-return overflow" |
| `toomanyprocs` | 9562 | 24 | "procedure overflow" |
| `ifflow` | 9559 | 25 | "if-then-else overflow" |
| `stoperr` | 9556 | 26 | "prg stopped" |
| `handflow` | 9553 | 27 | "too many files open" |
| `alropen` | 9550 | 28 | "already open" |
| `nodataerr` | 9547 | 29 | "out of data" |
| `conterr` | 9544 | 30 | "can't continue" |
| `syserr` | 9541 | 31 | "improper use of system variable" |
| `callerr` | 9538 | 32 | "improper function number" |
| `varperr` | 9535 | 33 | "variable not yet defined" |
| `procnotfound` | 9532 | 34 | "procedure not defined" |
| `procerr` | 9529 | 35 | "endproc without proc" |
| `convnoerr` | 9526 | 36 | "line numbers missing" |
| `convovflerr` | 9523 | 37 | "line too long" |
| `negerr` | 9519 | 38 | "no negative arg allowed" |
| `negdimerr` | 9520 | 38 | (alias for negerr) |
| `noargerr` | 9516 | 39 | "no arg allowed" |
| `manyargerr` | 9513 | 40 | "too many args" |
| `aesrangeerr` | 9510 | 41 | "out of field range" |
| `start1err` | 9507 | 42 | "arg < 1" |
| `cposerr` | 9504 | 43 | "cursor out of range" |
| `oddadrerr` | 9501 | 44 | "odd address access" |
| `strposerr` | 9498 | 45 | "position not within string" |
| `nolineerr` | 9495 | 46 | "can't find line number" |
| `toobigerr` | 9492 | 47 | "arg too big" |
| `fndeferr` | 9489 | 48 | "fn not defined" |
| `misargerr` | 9486 | 49 | "missing arg(s)" |
| `locdeferr` | 9483 | 50 | "local definition" |
| `nocmderr` | 9480 | 51 | "illegal use as command" |
| `elseerr` | 9477 | 52 | "else without if" |
| `thenerr` | 9474 | 53 | "missing <then>" |
| `toerr` | 9471 | 54 | "missing <to>" |
| `nofkterr` | 9468 | 55 | "illegal use as function" |
| `outstrspc` | 9465 | 56 | "out of string space" |
| `nonxterr` | 9462 | 57 | "for without next" |
| `noreterr` | 9459 | 58 | "gosub without return" |
| `noeprcerr` | 9456 | 59 | "proc without endproc" |
| `trgoserr` | 9453 | 60 | "missing gosub" |
| `notopenerr` | 9450 | 61 | "no such handle known" |
| `headerr` | 9447 | 62 | "no BASIC file format" |
| `defprerr` | 9444 | 63 | "improper procedure definition" |

**Error Handler:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `error` | 9641 | Main error handler entry |
| `error0` | 9648 | Error handler: look up message |
| `error1` | 9659 | Error handler: print message |
| `error1a` | 9680 | Error handler: print line number |
| `noerrlist` | 9693 | Error handler: no listing mode |

### 6.13 Data Section -- Tables (lines 9705-10420)

**String Constants:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `hextab` | 9705 | Hex digit lookup "0123456789abcdef" |
| `qlistptr` | 9709 | Pointer to qlist (string protection stack) |
| `ready` | 9713 | "ready." prompt string |
| `fragez` | 9715 | "? " INPUT prompt |
| `errormark` | 9716 | CR + "? " error prefix |
| `errtxt1` | 9717 | " error" suffix |
| `errtxt2` | 9718 | " in line " suffix |
| `errortab` | 9727 | Error message pointer table |
| `err0`..`err63` | 9736-9799 | Individual error message strings |
| `savetext` | 9803 | "saving..." status message |
| `loadtext` | 9805 | "loading..." status message |
| `mergetext` | 9807 | "merging..." status message |
| `convtext` | 9809 | "converting..." status message |
| `joker` | 9811 | "*.*" wildcard for DIR |

**Operator Tables:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `optabl` | 9826 | Operator dispatch table (13 entries) |
| `optoktabl` | 9828 | Operator token table |
| `oppriotabl` | 9830 | Operator priority table |

**Command Dispatch:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `comadr` | 9852 | Master dispatch: [0, comadr1, comadr2, comadr3] |
| `tokenadr` | 9853 | Token address lookup |
| `comadr1` | 9856 | Token class 1 dispatch table (main commands) |
| `comadr2` | 9972 | Token class 2 dispatch table |
| `comadr3` | 9975 | Token class 3 dispatch table |

**Token Name Tables:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `token1adr` | 10019 | Token class 1 name string pointers |
| `token2adr` | 10038 | Token class 2 name string pointers |
| `token3adr` | 10041 | Token class 3 name string pointers |
| `tokennr` | 9984 | Token number lookup |
| `helpnadr` | 10008 | HELP command name pointer table |
| `tokenstr` | 10093 | Start of token name strings |
| `comn1`..`comn113` | 10095-10207 | Individual command name strings |

**System Call Tables:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `gemdtbl` | 10244 | GEMDOS parameter descriptor table (51 entries) |
| `biostbl` | 10319 | BIOS parameter descriptor table (12 entries) |
| `xbiostbl` | 10339 | XBIOS parameter descriptor table (39 entries) |

**GEM Parameter Blocks:**

| Symbol | Line | Description |
|--------|-----:|-------------|
| `AESPB` | 10409 | AES parameter block (6 pointers) |
| `VDIPB` | 10410 | VDI parameter block (5 pointers) |
| `leer_str` | 10397 | Empty string constant (4 zero bytes) |

### 6.14 BSS Section -- Runtime Variables (lines 10422-10612)

**Type System:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `typvalid` | 10436 | word | Type validity flag (whether current type is known) |
| `typflag` | 10437 | word | Current expression type: FLOAT=1, INT=2, STRING=4 |
| `typ2flag` | 10438 | word | Secondary type (binary operations) |
| `typ3flag` | 10456 | word | Tertiary type (multi-operand expressions) |

**Execution State:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `akt_zeile` | 10445 | long | Current BASIC line number being executed |
| `b_modus` | 10446 | word | BASIC mode: 0=direct, -1=program |
| `akt_adr` | 10447 | long | Address of current line in program memory |
| `operator` | 10441 | word | Current operator number |
| `workop` | 10457 | word | Saved operator during expression eval |
| `follchar` | 10454 | word | Character following a comparison operator |
| `work1` | 10455 | long | Temp work area |
| `work2` | 10468 | long | Temp work area |
| `cmdfktfl` | 10579 | word | Current token: command or function flag |

**Control Flow Stacks:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `foreptr` | 10450 | long | Current position in FOR/NEXT stack |
| `goseptr` | 10451 | long | Current position in GOSUB stack |
| `ifendptr` | 10460 | long | Current position in IF stack |
| `ifcnt` | 10461 | word | Count of nested IFs in current line |
| `fortable` | 10535 | 4200 bytes | FOR/NEXT stack (100 entries x 42 bytes) |
| `endfortbl` | 10536 | word | End sentinel |
| `gostabl` | 10541 | 1200 bytes | GOSUB stack (100 entries x 12 bytes) |
| `endgostabl` | 10542 | word | End sentinel |
| `iftbl` | 10547 | 400 bytes | IF stack (100 entries x 4 bytes) |
| `endiftbl` | 10548 | word | End sentinel |
| `proctblptr` | 10574 | long | Current pointer into procedure stack |
| `proctbl` | 10575 | 1400 bytes | Procedure stack (100 entries x 14 bytes) |
| `procetbl` | 10576 | word | End sentinel |

**String Management:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `str_ptr` | 10502 | long | Pointer to most recently stored string |
| `str_puf` | 10499 | long | Start of temp string assembly buffer |
| `str_pufend` | 10500 | long | End of temp string assembly buffer |
| `spstr` | 10491 | long | Temporary string pointer |
| `pgarbend` | 10495 | long | End of program area for GC |
| `savereg` | 10494 | 64 bytes | Register save area for GC (d0-d7/a0-a7) |
| `qlist` | 10560 | 1000 bytes | String protection stack (250 x 4 bytes) |
| `qlistptr` | 9709 | long | Current qlist pointer (in DATA section) |
| `sbase` | 10496 | long | Saved stack base |

**I/O:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `handle` | 10442 | word | Current file handle |
| `filefl` | 10474 | word | File output flag (output to file) |
| `cmdfl` | 10475 | word | CMD flag (output redirected) |
| `handtab` | 10553 | 400 bytes | File handle table (100 entries x 4 bytes) |
| `endhtab` | 10554 | word | End sentinel |
| `inputpuf` | 10514 | 256 bytes | Primary input buffer |
| `input_puf` | 10516 | 256 bytes | Secondary input buffer (file input) |
| `mirrorpend` | 10523 | -- | End marker for mirror buffer |
| `inpuf_end` | 10517 | word | End marker for BASIC line buffer |
| `inpuf2_end` | 10519 | word | End marker for expanded buffer |
| `putfl` | 10429 | word | put_string line overflow ignore flag |

**Variables:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `var_name` | 10510 | 80 bytes | Current variable name buffer |
| `var2_name` | 10511 | 512 bytes | Copy of variable name (qualified) |
| `arrayfl` | 10422 | byte | Flag: current variable is an array |
| `arraydeep` | 10424 | long | Number of dimensions in current array |
| `arraylen` | 10425 | 10 longs | Lengths of each dimension (max 10) |
| `sysvar` | 10489 | word | System variable ID: 0=none, -1=PI, -2=TI, -3=TI$ |
| `sysallow` | 10490 | word | System variable permission flag |
| `fnvarfl` | 10464 | word | DEF FN function variable flag |
| `argfl` | 10465 | word | Argument variable flag |
| `fncnt` | 10567 | word | DEF FN parameter count |
| `fntyp` | 10568 | word | DEF FN return type |

**DATA / RESTORE:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `dataptr` | 10478 | long | Pointer to next DATA element |
| `dataadr` | 10479 | long | Address of line containing current DATA |
| `restadr` | 10480 | long | Saved address for RESTORE |

**CONT:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `contline` | 10484 | long | Saved line number (-1 = can't continue) |
| `contladr` | 10485 | long | Saved line address |
| `contadr` | 10486 | long | Saved parse pointer (a0) |

**ON..GOTO/GOSUB:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `onarg` | 10470 | long | Computed branch argument |
| `oncmd` | 10471 | word | Which command (GOTO or GOSUB) |
| `inptr` | 10469 | long | Pointer into input buffer |

**Timer:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `tiint` | 10431 | long | TI integer value (200 Hz tick count) |
| `tistring` | 10432 | 10 bytes | TI$ buffer ("HH:MM:SS") |
| `tistrend` | 10433 | -- | End marker for tistring |
| `key` | 10505 | long | Last key press (scancode+ASCII) |
| `key2` | 10506 | word | Secondary key buffer |

**Trace / Auto / DIM:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `tracefl` | 3320 | word | Trace flag: 0=off, 1=on |
| `trx` | 10607 | word | Saved cursor X during trace |
| `try` | 10608 | word | Saved cursor Y during trace |
| `autozeile` | 10611 | long | AUTO current line number |
| `autoadd` | 10612 | long | AUTO line increment |
| `dimtypext` | 10715 | word | DIM type extension (0=global, procnr=local) |
| `dimcmpfl` | 10716 | word | Local array redef flag |
| `dimcmpadr` | 10717 | long | Existing array header pointer |
| `dumpfl` | 3461 | byte | Dump filter bitmask |
| `dump2fl` | 3462 | byte | Current dump type |
| `convfl` | 6081 | word | CONVERT active flag |
| `listfl` | 6607 | word | LIST/SCROLL mode flag |
| `scrline` | 6347 | long | Current scroll line storage |

**GEM Arrays:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `AESctrl` | 10585 | 20 bytes | AES control array (10 words) |
| `AESintin` | 10586 | 256 bytes | AES integer input (128 words) |
| `AESintout` | 10587 | 256 bytes | AES integer output (128 words) |
| `AESadrin` | 10588 | 512 bytes | AES address input (128 longs) |
| `AESadrout` | 10589 | 512 bytes | AES address output (128 longs) |
| `AESglobal` | 10604 | 40 bytes | AES global array (10 longs) |
| `VDIctrl` | 10595 | 24 bytes | VDI control (12 words) |
| `VDIintin` | 10596 | 256 bytes | VDI integer input (128 words) |
| `VDIintout` | 10597 | 256 bytes | VDI integer output (128 words) |
| `VDIptsin` | 10598 | 256 bytes | VDI coordinate input (128 words) |
| `VDIptsout` | 10599 | 256 bytes | VDI coordinate output (128 words) |

**Misc / DTA:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `dta_puf` | 10509 | 50 bytes | DTA buffer for Fsfirst/Fsnext |
| `maxspalten` | 10563 | long | Maximum columns in editor |

**Stack:**

| Symbol | Line | Size | Description |
|--------|-----:|------|-------------|
| `sp_base` | 10528 | 20000 bytes | Interpreter stack (5000 longs) |
| `stack` | 10529 | long | Stack top marker |

---

## 7. Cross-Reference: BASIC Keywords to Implementation

| Keyword | Routine | File:Line |
|---------|---------|-----------|
| ABS | `Abs` | BASIC_COMMENTS.S:2812 |
| AES | `Aes` | BASIC_COMMENTS.S:2217 |
| AESADRIN | `Aesadrin` | BASIC_COMMENTS.S:2307 |
| AESADROUT | `Aesadrout` | BASIC_COMMENTS.S:2313 |
| AESCTRL | `Aesctrl` | BASIC_COMMENTS.S:2289 |
| AESINTIN | `Aesintin` | BASIC_COMMENTS.S:2295 |
| AESINTOUT | `Aesintout` | BASIC_COMMENTS.S:2301 |
| AND | `And` | BASIC_COMMENTS.S:8311 |
| ASC | `Asc` | BASIC_COMMENTS.S:3818 |
| ATANPT | `Atnpt` | BASIC_COMMENTS.S:2868 |
| ATN | `Atn` | BASIC_COMMENTS.S:2890 |
| AUTO | `Auto` | BASIC_COMMENTS.S:3295 |
| BIN$ | `Bin` | BASIC_COMMENTS.S:2032 |
| BIOS | `Bios` | BASIC_COMMENTS.S:2433 |
| CALL | `Call` | BASIC_COMMENTS.S:2613 |
| CHR$ | `Chr` | BASIC_COMMENTS.S:3238 |
| CLOSE | `Close` | BASIC_COMMENTS.S:4385 |
| CLR | `Clr` | BASIC_COMMENTS.S:5686 |
| CLS | `Cls` | BASIC_COMMENTS.S:2575 |
| CMD | `Cmd` | BASIC_COMMENTS.S:3010 |
| CONT | `Cont` | BASIC_COMMENTS.S:2584 |
| CONVERT | `Convert` | BASIC_COMMENTS.S:6083 |
| COS | `Cos` | BASIC_COMMENTS.S:2893 |
| CREATE | `Create` | BASIC_COMMENTS.S:4435 |
| CURSOR | `Cursor` | BASIC_COMMENTS.S:2539 |
| DATA | *(tokenized, no handler)* | -- |
| DEF FN | `Deffn` | BASIC_COMMENTS.S:4926 |
| DELETE | `Delete` | BASIC_COMMENTS.S:6472 |
| DIM | `Dim` | BASIC_COMMENTS.S:6719 |
| DIR | `Dir` | BASIC_COMMENTS.S:2051 |
| DUMP | `Dump` | BASIC_COMMENTS.S:3466 |
| EDTAB | `Edtab` | BASIC_COMMENTS.S:5533 |
| ELSE | `Else` | BASIC_COMMENTS.S:4154 |
| END | *(alias for STOP)* | BASIC_COMMENTS.S:2597 |
| ENDPROC | `Endproc` | BASIC_COMMENTS.S:5405 |
| EOR | `Xor` | BASIC_COMMENTS.S:8298 |
| EXP | `Exp` | BASIC_COMMENTS.S:2847 |
| EXP10 | `Exp10` | BASIC_COMMENTS.S:2844 |
| FN | `Fn` | BASIC_COMMENTS.S:4842 |
| FOR | `For` | BASIC_COMMENTS.S:4311 |
| FRE | `Varfre` | BASIC_COMMENTS.S:5471 |
| FUNCTION | `Function` | BASIC_COMMENTS.S:3833 |
| GEMDOS | `Gemdos` | BASIC_COMMENTS.S:2429 |
| GET | `Get` | BASIC_COMMENTS.S:3922 |
| GOSUB | `Gosub` | BASIC_COMMENTS.S:5838 |
| GOTO | `Goto` | BASIC_COMMENTS.S:5876 |
| HELP | `Help` | BASIC_COMMENTS.S:5438 |
| HEX$ | `Hex` | BASIC_COMMENTS.S:1992 |
| HOME | `Home` | BASIC_COMMENTS.S:2568 |
| IF | `If` | BASIC_COMMENTS.S:4173 |
| INKEY$ | `Inkey` | BASIC_COMMENTS.S:3259 |
| INPUT | `Input` | BASIC_COMMENTS.S:4566 |
| INSTR | `Instr` | BASIC_COMMENTS.S:3118 |
| INT | `Int` | BASIC_COMMENTS.S:5634 |
| LEFT$ | `Left` | BASIC_COMMENTS.S:3105 |
| LEN | `Len` | BASIC_COMMENTS.S:3901 |
| LINE | `line` | BASIC_COMMENTS.S:9385 |
| LIST | `List` | BASIC_COMMENTS.S:6507 |
| LN | `Ln` | BASIC_COMMENTS.S:2838 |
| LOAD | `Load` | BASIC_COMMENTS.S:6160 |
| LOCAL | `Local` | BASIC_COMMENTS.S:5070 |
| LOG | `Log` | BASIC_COMMENTS.S:2841 |
| LPEEK | `Lpeek` | BASIC_COMMENTS.S:2924 |
| LPOKE | `Lpoke` | BASIC_COMMENTS.S:2962 |
| MERGE | `Merge` | BASIC_COMMENTS.S:6019 |
| MID$ | `Mid` | BASIC_COMMENTS.S:3060 |
| MOD | `Mod` | BASIC_COMMENTS.S:2859 |
| NEW | `New` | BASIC_COMMENTS.S:5651 |
| NEXT | `Next` | BASIC_COMMENTS.S:4248 |
| NOT | `Not` | BASIC_COMMENTS.S:3028 |
| ON | `On` | BASIC_COMMENTS.S:4498 |
| OPEN | `Open` | BASIC_COMMENTS.S:4438 |
| OR | `Or` | BASIC_COMMENTS.S:8323 |
| PEEK | `Peek` | BASIC_COMMENTS.S:2947 |
| POKE | `Poke` | BASIC_COMMENTS.S:2992 |
| POS | `Pos` | BASIC_COMMENTS.S:3043 |
| PRINT | `Print` | BASIC_COMMENTS.S:6823 |
| PROC | `Proc` | BASIC_COMMENTS.S:5305 |
| READ | `Read` | BASIC_COMMENTS.S:4103 |
| REM | *(tokenized, skipped by exec)* | -- |
| RESTORE | `Restore` | BASIC_COMMENTS.S:4044 |
| RETURN | `Return` | BASIC_COMMENTS.S:5791 |
| RIGHT$ | `Right` | BASIC_COMMENTS.S:3092 |
| RND | `Rnd` | BASIC_COMMENTS.S:2735 |
| RUN | `Run` | BASIC_COMMENTS.S:5897 |
| SAVE | `Save` | BASIC_COMMENTS.S:6212 |
| SGN | `Sgn` | BASIC_COMMENTS.S:2769 |
| SIN | `Sin` | BASIC_COMMENTS.S:2896 |
| SPC | `Spc` | BASIC_COMMENTS.S:5607 |
| SQR | `Sqr` | BASIC_COMMENTS.S:2835 |
| STEP | *(parsed inside For)* | BASIC_COMMENTS.S:4352 |
| STOP | `Stop` | BASIC_COMMENTS.S:2597 |
| STR$ | `Str` | BASIC_COMMENTS.S:3868 |
| STRFRE | `Strfre` | BASIC_COMMENTS.S:5494 |
| SWAP | `Swapvars` | BASIC_COMMENTS.S:3739 |
| SYS | `Sys` | BASIC_COMMENTS.S:2704 |
| TAB | `Tab` | BASIC_COMMENTS.S:5562 |
| TAN | `Tan` | BASIC_COMMENTS.S:2850 |
| THEN | *(parsed inside If)* | BASIC_COMMENTS.S:4173 |
| TO | *(parsed inside For)* | BASIC_COMMENTS.S:4311 |
| TROFF | `Troff` | BASIC_COMMENTS.S:3324 |
| TRON | `Tron` | BASIC_COMMENTS.S:3321 |
| VAL | `Val` | BASIC_COMMENTS.S:3832 |
| VARPTR | `Varptr` | BASIC_COMMENTS.S:2189 |
| VDI | `Vdi` | BASIC_COMMENTS.S:2222 |
| VDICTRL | `Vdictrl` | BASIC_COMMENTS.S:2320 |
| VDIINTIN | `Vdiintin` | BASIC_COMMENTS.S:2326 |
| VDIINTOUT | `Vdiintout` | BASIC_COMMENTS.S:2332 |
| VDIPTSIN | `Vdiptsin` | BASIC_COMMENTS.S:2338 |
| VDIPTSOUT | `Vdiptsout` | BASIC_COMMENTS.S:2344 |
| WAIT | `Wait` | BASIC_COMMENTS.S:3275 |
| WPEEK | `Dpeek` | BASIC_COMMENTS.S:2935 |
| WPOKE | `Dpoke` | BASIC_COMMENTS.S:2987 |
| XBIOS | `Xbios` | BASIC_COMMENTS.S:2436 |
| + | `Add` | BASIC_COMMENTS.S:8392 |
| - | `Sub` | BASIC_COMMENTS.S:8411 |
| * | `Mul` | BASIC_COMMENTS.S:8546 |
| / | `Div` | BASIC_COMMENTS.S:8500 |
| ^ | `Exponent` | BASIC_COMMENTS.S:8437 |
| < | `Lower` | BASIC_COMMENTS.S:8150 |
| = | `Equal` | BASIC_COMMENTS.S:8210 |
| > | `Higher` | BASIC_COMMENTS.S:8183 |
| { | `ShL` | BASIC_COMMENTS.S:8272 |
| } | `ShR` | BASIC_COMMENTS.S:8285 |
| ~ | `Xor` | BASIC_COMMENTS.S:8298 |
| & | `And` | BASIC_COMMENTS.S:8311 |
| \| | `Or` | BASIC_COMMENTS.S:8323 |
| $ | `get_hexvar` | BASIC_COMMENTS.S:7885 |
| % | `get_binvar` | BASIC_COMMENTS.S:7923 |
