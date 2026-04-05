# Reverse-Engineered Atari ST BASIC Interpreter -- Technical Analysis

**Date of original source:** October/November 1988  
**Analysis date:** April 2026  
**Source files:** HEADER.S, BASIC_COMMENTS.S (originally BASIC.S), BLIBF.S, EDITOR.S, DATA.S

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Memory Layout](#2-memory-layout)
3. [Token System](#3-token-system)
4. [Type System](#4-type-system)
5. [Expression Evaluator](#5-expression-evaluator)
6. [Variable System](#6-variable-system)
7. [Procedure System](#7-procedure-system)
8. [Control Flow Structures](#8-control-flow-structures)
9. [String Management](#9-string-management)
10. [File I/O](#10-file-io)
11. [System Integration](#11-system-integration)
12. [Floating-Point Library (BLIBF.S)](#12-floating-point-library-blibfs)
13. [Editor Subsystem](#13-editor-subsystem)
14. [Error Handling](#14-error-handling)
15. [Build Process](#15-build-process)
16. [Notable 68000 Idiom](#16-notable-68000-idiom)

---

## 1. Architecture Overview

### Component Diagram

```
+------------------------------------------------------------------+
|                        HEADER.S                                   |
|  Entry point, Init, Edit, Run, STAD interface, _g_char renderer  |
+---+----------+---------------------------------------------------+
    |          |
    v          v
+--------+  +----------------------------------------------------+
|EDITOR.S|  |               BASIC_COMMENTS.S                      |
| Screen |  | Tokenizer, Interpreter loop, Commands, Expression  |
| editor |  | evaluator, Variables, Procedures, I/O, Errors      |
+--------+  +---+------------------------------------------------+
                |
                v
          +-----------+     +--------+
          |  BLIBF.S  |     | DATA.S |
          | BCD float |     | Memory |
          | library   |     | ptrs   |
          +-----------+     +--------+
```

### Component Responsibilities

- **HEADER.S** (307 lines) -- Program entry point and STAD embedding API. Initializes Line-A graphics, allocates memory zones, fills in the STAD editor structure, and provides Init/Edit/Run entry points for external hosts. Contains the `_g_char` character rendering routine that blits font glyphs directly to screen memory.

- **BASIC_COMMENTS.S** (10612 lines; originally BASIC.S, 7661 lines before comments were added) -- The core interpreter. Contains the tokenizer (`konv_inpuf`), the main execution loop (`exec_line`), all BASIC commands and functions, the expression evaluator (`get_term`/`get_element`), variable management, procedure/function system, garbage collector, file I/O, GEMDOS/BIOS/XBIOS wrappers, AES/VDI interfaces, and error handling.

- **BLIBF.S** (2045 lines) -- BCD floating-point arithmetic library. Provides addition, subtraction, multiplication, division, trigonometric functions (sin, cos, tan, atan, atan2), exponential/logarithmic functions, square root, random number generation, and conversions between float/integer/ASCII representations.

- **EDITOR.S** (727 lines) -- Full-screen text editor. Maintains a 25x80 internal character buffer, renders via callback, handles keyboard input, cursor movement, scrolling, and communicates with the BASIC interpreter for line entry and program listing navigation.

- **DATA.S** (37 lines) -- Global memory layout pointers (`editscreen`, `prgbase`, `prgend`, `varbase`, `varend`, `strbase`, `strend`) shared by all modules.

### STAD Interface

The interpreter can operate standalone or be embedded via the STAD interface. The STAD structure is a communication block at `edibase` containing:

| Offset | Name | Type | Description |
|--------|------|------|-------------|
| 0 | `edi_base` | long | Physical screen framebuffer address |
| 4 | `edi_screen` | long | Screen width in bytes (80 for 640px mono) |
| 8 | `edi_plan` | word | Reserved/unused |
| 10 | `edi_x` | word | Window X pixel offset |
| 12 | `edi_y` | word | Window Y pixel offset |
| 14 | `edi_ext` | long | Reserved/extension |
| 18 | `edi_breit` | word | Window width in pixels |
| 20 | `edi_hoch` | word | Window height in pixels |
| 22 | `edi_maxzeilen` | word | Max editor rows (e.g., 25) |
| 24 | `edi_maxspalten` | word | Max editor columns (e.g., 80) |
| 26 | `edi_tab` | word | Tab stop interval (e.g., 7) |
| 28 | `edi_print` | long | Character output callback pointer |
| 32 | `edi_pgblock` | long | Line-A variables base pointer |
| 36 | `edi_vrblock` | long | System variables block pointer |
| 40 | `edi_retprg` | long | Return callback (0 = stay in BASIC) |
| 44 | `edi_preup` | long | Pre-scroll-up callback |
| 48 | `edi_up` | long | Post-scroll-up callback |
| 52 | `edi_predown` | long | Pre-scroll-down callback |
| 56 | `edi_down` | long | Post-scroll-down callback |
| 60 | `edi_font` | long | GEM font header pointer |
| 64 | `edi_y_shft` | word | Font height shift (4=16px, 3=8px) |

Exported entry points for STAD hosts:

- `initcode` -> `Init(a0=membase, d0=memsize)` -- returns 0 on success, -1 if insufficient memory
- `editcode` -> `Edit()` -- enters the interactive editor loop
- `runcode` -> `Run(d0=mode, a0=param)` -- executes commands directly:
  - Mode 0: Load file named by A0 and RUN (builds `load "filename":run`)
  - Mode 1: CLR then call procedure named by A0 (builds `clr:procname`)
  - Mode 2: RUN from line number in A0 (builds `run N`)

### Line-A Initialization and Graphics Globals

During `Init`, the `$A000` Line-A trap returns three pointers (HEADER.S:115-120):
- **a0** = Line-A variable block base (saved to `la_variablen`)
- **a1** = array of 3 font header pointers: `0(a1)` = 6x6, `4(a1)` = 8x8, `8(a1)` = 8x16
- **a2** = Line-A opcode table (not used by the interpreter)

Four Line-A variables are configured for the LINE2 drawing command (HEADER.S:122-125):

| Offset | Variable | Value | Why |
|--------|----------|-------|-----|
| $18 | `COLBIT0` | 1 | Foreground color plane 0 = black in monochrome mode |
| $20 | `LSTLIN` | -1 | Draw the last pixel of each line (complete lines, no gap) |
| $22 | `LNMASK` | $FFFF | Solid line style (all bits set = no dashing) |
| $24 | `WMODE` | 1 | XOR write mode: drawing the same line twice erases it |

The font is selected from the Line-A font table: `move.l 8(a1),bsc_font` loads the 8x16 system font (HEADER.S:126). The source contains a commented-out alternative for 8x8 font at `4(a1)`. The font height shift value `edi_yshft` is set to 4 (for `row << 4` = row * 16), or would be 3 for the 8x8 font.

Four module-global variables (HEADER.S:483-492) bridge initialization to runtime:

| Variable | Set by | Used by | Purpose |
|----------|--------|---------|---------|
| `la_variablen` | `$A000` trap | LINE2 command | Line-A variable block base address |
| `bsc_font` | Init (from font table) | `_g_char` | GEM font header pointer for glyph lookup |
| `w_base` | XBIOS Physbase ($02) | `_g_char` | Physical screen framebuffer address |
| `w_screen` | Init (hardcoded 80) | `_g_char` | Screen width in bytes (640 pixels / 8 = 80 in mono) |

### Pseudo-Code: Main Interpreter Loop (`basic1` / `basic2`, BASIC_COMMENTS.S:451)

The interpreter's idle state is a pair of cooperating functions. `basic1` prints the "ready." prompt; `basic2` resets internal state (mode flags, stacks) and returns control to the editor. The two entry points exist because AUTO mode needs to skip the prompt but still reset state. A notable detail: `init_tbls` (which clears the FOR/GOSUB/IF/PROC stacks) is skipped when CONT is valid, preserving the execution state so the user can resume.

```
function basic1():
    clear_file_output()                  # output goes to screen
    if not AUTO_MODE:
        print "ready."

function basic2():                       # also entry after AUTO numbering
    clear_file_output()
    restore_data_pointer()               # reset READ/DATA cursor
    argfl = 0                            # not inside FN argument
    b_modus = 0                          # direct mode
    ifcnt = 0                            # reset IF nesting
    init_tbls()                          # clear FOR/GOSUB/IF/PROC stacks
                                         #   (skipped if CONT is valid)
    if CONT_possible:
        keep akt_zeile                   # preserve line number for CONT
    else:
        akt_zeile = 0

    if AUTO_MODE:
        print autozeile, " "             # display next line number
        autozeile += autoadd             # advance for next iteration
        if autozeile < 0: AUTO_MODE = false

    return_to_editor()                   # restore stack, return d0=0 to editor
```

**68000 Implementation Notes:** The interpreter uses a separate 20,000-byte stack (`lea stack,sp` at line 464), distinct from the editor/system stack. `return_to_editor` restores the saved stack pointer and returns d0=0 to the editor loop. The CONT validity check uses `bpl` (branch if plus, i.e., `contline >= 0`), so `contline = -1` means invalid. An assembly detail not shown in the pseudo-code: when a program is modified (line 584), `traceline` is also cleared to -1 alongside `contline`, invalidating any active ON TRACE GOSUB handler. The AUTO mode output (lines 473-476) checks the editor cursor column (`ed_x + ed_xoffs`) and outputs a newline if not at column 0 before printing the line number.

### Pseudo-Code: Entry from Editor (`b_enter`, BASIC_COMMENTS.S:535)

This is the gateway between the editor and the interpreter. Every line the user types passes through `b_enter`, which makes three critical decisions based on the first non-space character: empty lines reset AUTO mode, `!` exits, digits trigger line management (insert/replace/delete), and anything else is executed immediately. The stack pointer is saved at entry so that errors can unwind cleanly back to the editor via `posquit`. A key finding: modifying any program line invalidates CONT (`contline = -1`) and forces a full CLR if any procedures were defined, because procedure definitions embed pointers into program memory that become stale after line insertion/deletion.

```
function b_enter(input_text, max_length):
    save stack_pointer                   # for posquit/quit to unwind to
    switch to BASIC stack                # lea stack,sp

    copy_and_trim(input_text → input_puf)   # strip leading/trailing spaces
    tokenize(input_puf)                      # konv_inpuf: keywords → token bytes
    newline()                                # advance cursor on screen

    ch = first_nonspace_char(input_puf)

    if ch == NUL:                        # empty line
        AUTO_MODE = false
        goto basic2                      # back to idle loop (no "ready.")

    if ch == '!':                        # exit command
        AUTO_MODE = false
        return -1 to editor              # quit signal

    if ch is a digit ('0'-'9'):          # numbered line
        contline = -1                    # program modified → invalidate CONT
        if FN or PROC definitions exist:
            Clr1()                       # must clear variables (defs invalidated)
        line_management(input_puf)       # insert, replace, or delete line
        goto basic2

    # --- Not a line number: execute directly ---
    AUTO_MODE = false
    exec_line(input_puf)                 # execute the tokenized input
    goto basic1                          # back to "ready." prompt
```

**68000 Implementation Notes:** The `posquit` error recovery works by saving the system stack pointer at entry (`move.l sp,oldstack` at line 538). When an error occurs anywhere in the interpreter, the error handler restores `oldstack` into SP, unwinding all nested calls in one step. This is essentially a `longjmp` implemented with raw stack manipulation. The `zeilenverwaltung` (line management) call backs up `a0` by 1 byte (`subq.l #1,a0` at line 561) to re-include the first digit character, which was consumed by the digit test. The CLR-on-modification check (lines 585-588) tests both `fncnt` (DEF FN count) and `anzprocs` (PROC count) separately, because either type of definition embeds pointers that become stale.

### Pseudo-Code: Statement Executor (`exec_line`, BASIC_COMMENTS.S:1060)

The statement executor is the inner loop of the interpreter. It processes one line of tokenized BASIC, dispatching each command via a handler address table (`comadr`). An elegant design: command handler addresses encode permission flags in their upper bits (bit 31 = function-only, bit 30 = program-only, bit 29 = direct-only, bit 28 = dual command/function). These flags are checked before dispatch, avoiding per-command permission checks. The trace mechanism inserts itself transparently: when `tracefl` is active, each statement triggers a display-and-GOSUB before execution. The `tracefl=2` state handles the case where the trace GOSUB just returned -- it re-enables tracing for the next statement without re-tracing the current one.

```
function exec_line(a0 → tokenized_data):
    loop:
        check_for_break()                # ALT+UNDO → stop
        ch = next_nonspace_char()
        if ch == NUL: return             # end of line

        # --- Trace support ---
        if b_modus == PROGRAM_MODE and tracefl == 1:
            trace(ch)                    # display line#: command text
        if tracefl == 2:                 # just returned from trace GOSUB
            tracefl = 1                  # re-enable for next statement

        # --- Dispatch ---
        if ch == TOKEN1 or TOKEN2 or TOKEN3:
            index = next_byte()          # token command index
            class = ch                   # token class (1, 2, or 3)
            addr = comadr[class][index]  # look up handler address + flags

            # Check permission flags encoded in the address
            if addr.bit31 (FUNCTION_ONLY):
                if not addr.bit28 (DUAL): error "illegal use as command"
                cmdfktfl = 0             # mark: called as command
            if addr.bit30 (PROGRAM_ONLY) and b_modus == DIRECT:
                error "illegal direct"
            if addr.bit29 (DIRECT_ONLY) and b_modus == PROGRAM:
                error "illegal program mode"

            handler = addr AND $00FFFFFF # strip flag bits → 24-bit address
            call handler()

        elif ch == '\'' (single quote):
            treat as REM                 # skip rest of line

        elif ch is digit '0'-'9':
            treat as implicit GOTO       # bare number → GOTO number

        else:
            var_def()                    # variable = expression (assignment)

        # --- After command, check for separator ---
        ch = current_char()
        if ch == NUL: return             # end of line
        if ch == ':': continue loop      # next command on same line
        error "syntax"                   # unexpected character
```

**68000 Implementation Notes:** Command handler addresses use the upper 8 bits of a 32-bit longword for permission flags -- this works because the 68000 has a 24-bit address bus, so bits 24-31 are unused in addresses and available as flag storage. The mask `AND $00FFFFFF` strips the flags before the JSR. The single-quote (REM shorthand) check at line 1089 uses `cmp.b #'&'+1,d0`, which equals the ASCII code for `'` (39 = 38+1) -- a minor code-golf trick. The token dispatch uses a two-level indirection: `comadr` is an array of 4 pointers to per-class command tables, indexed by the token class byte (1, 2, or 3) multiplied by 4 for longword access. This allows the three token classes to have independent handler tables.

---

## 2. Memory Layout

### Overview

```
Low addresses                                              High addresses
+-------------------+-------------------+----------+-------+-------+-----+-----+
| Editor Screen Buf | BASIC Program     |  (gap)   | Vars  | free  |Strs |sent.|
| (25 x 80 = 2000B) | (linked list)     |  16B     |(linked| space |(rev)| 4B  |
|                   |  grows up ->      |  fixed   | list) |       |(<-) |     |
+-------------------+-------------------+----------+-------+-------+-----+-----+
^                   ^                   ^          ^       ^       ^     ^
editscreen          prgbase             prgend     varbase varend  strend strbase
                    |<-- program ------>|          |<-var->|       |<str>|
                    grows UP when lines             grows UP       grows DOWN
                    are inserted                    when vars      when strings
                    (shifts var area)               created        allocated
```

All seven pointers (`editscreen`, `prgbase`, `prgend`, `varbase`, `varend`, `strbase`, `strend`) are global longwords defined in DATA.S and shared across all modules.

### Initial Memory Partitioning

The `Init` routine in HEADER.S (line 181) receives a contiguous memory block (a0 = base, d0 = size) and partitions it:

```
1.  editscreen = a0                        Editor screen buffer (25 × 80 = 2000 bytes)
2.  a0 += 2000; d0 -= 2000                Skip editor buffer
3.  if d0 < 2048: return error (-1)        Minimum 2KB required for program/vars/strings
4.  prgbase = a0                           Program storage base
5.  prgend  = a0                           Empty program (no lines yet)
6.  a0 += 16                               16-byte fixed gap
7.  varbase = a0                           Variable list starts here
8.  varend  = a0                           Empty variable list
9.  strbase = a0 + d0 - 16 - 1            String heap upper boundary (16-byte + 1-byte margin)
10. strend  = strbase                      Empty string heap (grows downward)
```

Source: `HEADER.S:181-194`. The string base is set 17 bytes below the top of the memory block (16-byte safety margin + 1 for alignment). The editor buffer `ed_clrmem` fills the screen buffer with spaces ($20).

After initialization, the free space is the gap between `varend` and `strend`. This space is shared: variables grow upward into it, and strings grow downward into it. When they meet, memory is exhausted.

### The 16-Byte Gap

A fixed 16-byte gap always exists between `prgend` and `varbase`. It is:
- Created at initialization: `add.l #16,a0` before setting `varbase` (HEADER.S:188)
- Preserved on CLR: `move.l prgend,d0 / add.l #16,d0 / move.l d0,varbase` (BASIC_COMMENTS.S:5734-5736)
- Written with 12 bytes of zeros after CLR (BASIC_COMMENTS.S:5739-5741), serving as a safety buffer for 12-byte float writes

This gap prevents off-by-one errors when program data and variable data are adjacent, and provides a sentinel/alignment zone.

### Program Storage

Programs are stored as a singly-linked list. Each line has the structure:

```
Offset  Size  Content
0       4     Next-line pointer (absolute address; 0 = end of program)
4       4     Line number (32-bit integer)
8       N     Tokenized line data (variable length, null-terminated)
```

Lines are kept sorted by line number. The next-line pointer of the last line is 0, and a sentinel value of `$FFFFFFFF` (-1) is written after the final null to mark the absolute end.

#### Program Growth: Line Insertion (`basic20`, BASIC_COMMENTS.S:649)

When a new line is inserted (or an existing line is replaced with a longer version):

1. **Measure** the new line's tokenized data length, round up to even (word-aligned), add 8 bytes for the header (next-pointer + line number).
2. **Overflow check:** Verify `varend + new_bytes + 32 < strend`. If not, raise "out of program space" (BASIC_COMMENTS.S:714-716).
3. **Shift variables UP:** Copy the entire variable area (from `varend` down to the insertion point) upward by the displacement, using a backwards byte copy (`move.b -(a2),-(a3)`) (BASIC_COMMENTS.S:721-723).
4. **Update pointers:** `prgend += displacement`, `varbase += displacement`, `varend += displacement` (BASIC_COMMENTS.S:688-690).
5. **Relink program:** Walk the program linked list from the modified line forward, adjusting each next-pointer by the displacement (BASIC_COMMENTS.S:694-698).
6. **Relink variables:** Walk the entire variable linked list from `varbase`, adjusting each next-pointer by the same displacement (BASIC_COMMENTS.S:636-644, via `basic3c`/`lll3`).
7. **Copy** the new tokenized data into the gap created at the insertion point (BASIC_COMMENTS.S:728-736).

When replacing an existing line with a **shorter** version, the displacement is negative and the variable area shifts **down** instead. The same relink procedure applies.

#### Program Shrinkage: Line Deletion (`delline2`, BASIC_COMMENTS.S:605)

When a line is deleted:

1. **Measure** the deleted line's length: `d0 = next_line_ptr - this_line_ptr`.
2. **Shift everything down:** Copy all bytes from the next line through `varend` downward by `d0` bytes, using a forward byte copy (`move.b (a2)+,(a1)+`) (BASIC_COMMENTS.S:616-618).
3. **Update pointers:** `prgend -= d0`, `varbase -= d0`, `varend -= d0` (BASIC_COMMENTS.S:621-623).
4. **Relink program:** Walk the program linked list, subtracting `d0` from each next-pointer (BASIC_COMMENTS.S:627-631).
5. **Relink variables:** Walk the variable linked list from `varbase`, subtracting `d0` from each next-pointer (BASIC_COMMENTS.S:636-644).

**Key insight:** `varbase` and `varend` are **relocated** every time a program line is inserted or deleted. The variable data is physically moved in memory. This is why the variable linked list must be fully relinked after every program edit.

### Variable Storage

Variables form a separate singly-linked list starting at `varbase`:

```
Offset  Size  Content
0       4     Next-variable pointer (absolute address; 0 = end)
4       2     Type word (FLOAT=1, INT=2, STRING=4, with flag bits: ARRAYTYP=$8000,
              FNTYP=$4000, DEFFNTYP=$2000, PROCTYP=$1000, plus procnr in bits 3-11)
6       N     Variable name (null-terminated bytes, padded to even address)
6+N     M     Value: 4 bytes for INT, 12 bytes for FLOAT, 4 bytes for STRING (pointer),
              or array header + elements for arrays
```

#### Variable Growth (`create_var`, BASIC_COMMENTS.S:1469)

New variables are appended at `varend` (the end of the linked list):

1. **Overflow check:** `varend + 32 < strend`. Raises "out of variable space" if not (BASIC_COMMENTS.S:1473-1476).
2. **Build record** at `varend`: skip 4 bytes (next-pointer), write type word, copy variable name (with word-alignment padding), then write initial value (zeros: 4 bytes for INT/STRING, 12 bytes for FLOAT).
3. **For arrays:** Additionally write the dimension count, dimension sizes, and zero-fill all elements. A second overflow check ensures the array data fits (BASIC_COMMENTS.S:1534-1537).
4. **Update `varend`:** Set `varend` to the byte after the new variable's value storage. Write NULL to terminate the list (`clr.l (a2)`) (BASIC_COMMENTS.S:1548-1550).
5. **Link:** The previous last variable's next-pointer is set to point to the new variable (BASIC_COMMENTS.S:1548).

Variables only grow (never shrink during execution). CLR is the only way to reclaim variable space.

### String Storage

Strings grow **downward** from `strbase` toward `strend`. Critically, **strings are stored in reverse byte order** in memory. The `strend` pointer moves downward as new strings are allocated. When `strend` approaches `varend`, the interpreter is out of memory and triggers garbage collection.

#### String Allocation (`resv_str`/`copy_str`, BASIC_COMMENTS.S:7516-7636)

When a string is stored:

1. **Space check:** Compute `projected_strend = strend - string_length - 32`. If `projected_strend < varend`, trigger garbage collection first (BASIC_COMMENTS.S:7584-7598).
2. **Copy data** into the heap, growing downward. String constants (quoted literals) are copied forward-to-backward; string variables (already reversed) are copied backward-to-backward (BASIC_COMMENTS.S:7606-7630).
3. **Update `strend`:** Decremented to point below the newly stored string data (BASIC_COMMENTS.S:7633-7635).

#### Dead Strings and the $FF Marker

When a string variable is reassigned, the old string becomes unreachable but still occupies space in the heap. `mark_str` (BASIC_COMMENTS.S:1277) writes a `$FF` byte at the beginning (lowest address) of a string to mark it as dead. The garbage collector later reclaims this space.

#### Garbage Collection (`garbage`, BASIC_COMMENTS.S:8751)

The garbage collector compacts the string heap by removing dead strings:

1. **Save state:** Push `pgarbend`, `str_ptr`, `strend` onto the `qlist` protection stack. Save all registers to `savereg` (BASIC_COMMENTS.S:8755-8770).
2. **Scan downward** from `strbase`: For each string, check if it starts with `$FF` (dead). Live strings (starting with `$00` NUL terminator) are skipped (BASIC_COMMENTS.S:8772-8782).
3. **On dead string found:** Measure its size. Shift all strings below it **upward** by that amount (closing the gap). This is a byte-by-byte backwards copy (BASIC_COMMENTS.S:8788-8806).
4. **Update all string pointers** that pointed into the moved region, by adding the shift offset:
   - `garb_var` (line 8860): Walks the entire variable linked list, adjusting string-type variable pointers and array string elements.
   - `garb_reg` (line 8839): Adjusts the 7 saved address registers (a0-a6) in `savereg`.
   - `garb_qlist` (line 8823): Adjusts all entries in the `qlist` protection stack.
5. **Continue scanning** until `pgarbend` is reached.
6. **Restore state:** Pop `strend`, `str_ptr`, `pgarbend` from `qlist` (adjusted if moved). Restore all registers (BASIC_COMMENTS.S:8879-8896).

After GC, `strend` may have moved upward, freeing space between `varend` and `strend`.

### CLR and NEW: Memory Reset

**NEW** (BASIC_COMMENTS.S:5651): Clears the program, then calls CLR:
- Sets `prgend = prgbase` (empty program), writes end markers (NULL + sentinel -1).
- Falls through to `Clr1`.

**Clr1** (BASIC_COMMENTS.S:5733): Full variable/string clear:
- `strend = strbase` (discard all strings)
- `varbase = prgend + 16` (re-establish the 16-byte gap)
- `varend = varbase` (empty variable list)
- Calls `init_tbls` to reset FOR/GOSUB/IF/PROC stacks
- Zeros 12 bytes at `varbase` (safety buffer for float writes)
- Clears 4 sentinel bytes at `strbase` (NUL terminators for reverse string scanning)
- Resets `fncnt` and `anzprocs` to 0

### Memory Dynamics Summary

| Pointer | Set By | Moves When | Direction |
|---------|--------|------------|-----------|
| `editscreen` | Init | Never | Fixed |
| `prgbase` | Init | Never | Fixed |
| `prgend` | Line insert/delete, NEW | Up on insert, down on delete | Tracks end of program |
| `varbase` | Init, CLR, line insert/delete | **Relocated** with program changes | Follows prgend + 16 |
| `varend` | Variable creation, CLR, line insert/delete | Up on create, **relocated** on program changes | Tracks end of variables |
| `strbase` | Init | Never | Fixed |
| `strend` | String allocation, GC, CLR | Down on allocation, up on GC, reset on CLR | Tracks bottom of string heap |

**What is relocated vs. what grows:**
- `varbase` and `varend` are **relocated** (physically moved in memory along with all variable data) whenever the program area changes size. They also grow when new variables are created.
- `strend` **grows downward** independently as strings are allocated, and **moves back up** when garbage collection compacts dead strings.
- `prgbase` and `strbase` are **fixed** after initialization and never change.
- The free space between `varend` and `strend` is shared by both variables (growing up) and strings (growing down). When they collide, either GC is triggered (for strings) or an "out of memory" error is raised (for variables/program).

### Stack

A 5000-longword (20,000 byte) stack at `sp_base`/`stack` is used for the BASIC interpreter's own call stack, separate from the system stack. This is initialized at the start of program execution with `lea stack,sp`. This stack is in the BSS section and is **not** part of the dynamic memory layout above -- it exists at a fixed location determined by the linker.

### Pseudo-Code: Line Insertion (`basic20`, BASIC_COMMENTS.S:649)

Line insertion is the most mechanically complex operation in the interpreter because it must maintain two independent linked lists (program lines and variables) that share contiguous memory. When a line is inserted or resized, everything above the insertion point -- including all variable data -- must be physically shifted in memory, and every pointer in both linked lists must be relinked. This is why editing a program is slow on large programs: a single line edit triggers an O(n) memory move plus an O(n) pointer fixup. The 32-byte safety margin check prevents the program area from colliding with the string heap.

```
function basic20(line_number, tokenized_data):
    """Insert or replace a numbered program line."""
    data_len = length(tokenized_data)
    round_up_to_even(data_len)

    insertion_point = find_line_position(line_number)  # poszeile

    if line exists at insertion_point:
        # --- Replace existing line ---
        old_len = old_line.data_length
        if old_len > data_len:
            # Old line longer: shift program+vars DOWN by (old_len - data_len)
            displacement = -(old_len - data_len)
            shift_bytes_down(insertion_point, varend, displacement)
        elif old_len < data_len:
            # Old line shorter: shift program+vars UP by (data_len - old_len)
            displacement = data_len - old_len
            check: varend + displacement + 32 < strend  # else "out of program space"
            shift_bytes_up(insertion_point, varend, displacement)
        else:
            # Same length: just overwrite data
            copy(tokenized_data → insertion_point.data)
            return
    else:
        # --- New line: need 8 + data_len bytes ---
        displacement = 8 + data_len
        check: varend + displacement + 32 < strend  # else "out of program space"
        shift_bytes_up(insertion_point, varend, displacement)

    # --- Update global pointers ---
    prgend  += displacement
    varbase += displacement
    varend  += displacement

    # --- Relink program linked list ---
    # Starting from modified line, recompute each next-pointer:
    line = insertion_point
    line.next_ptr = address_of(line) + 8 + line.data_length
    while line.next_ptr != 0:
        line.next_ptr += displacement    # adjust for shift
        line = line.next

    # --- Relink variable linked list ---
    var = varbase
    while var < varend:
        var.next_ptr -= abs(displacement)  # adjust each pointer
        var = var.next

    # --- Copy new line data ---
    insertion_point.line_number = line_number
    copy(tokenized_data → insertion_point.data)
    mark end of program: prgend.next_ptr = 0, sentinel = $FFFFFFFF
```

**68000 Implementation Notes:** The memory safety check uses a single LEA instruction (`lea -32(a2,d1.l),a3` at line 714) that computes `varend + displacement - 32` in one cycle -- the 68000's indexed addressing mode with displacement combines base register, index register, and constant offset. The data length rounding (`btst #0,d1; beq ...; addq.l #1,d1` at lines 657-659) ensures word alignment, required because the 68000 raises an Address Error exception on unaligned word/long accesses. The program end sentinel (`move.l #-1,(a0)` at line 736) uses $FFFFFFFF, which cannot be a valid next-pointer, as a reliable end-of-program marker.

---

## 3. Token System

### Token Groups

Tokens are encoded as two-byte sequences. The first byte identifies the token group, the second byte is the token index within that group:

| Group | Intro Byte | Range | Description |
|-------|-----------|-------|-------------|
| TOKEN1 | `$01` | `$0100`-`$0170` | Main commands and functions (113 tokens) |
| TOKEN2 | `$02` | `$0200` | Extended commands (LINE2) |
| TOKEN3 | `$03` | `$0300` | Extended commands (LINE3) |

### Complete Token List (TOKEN1: $01xx)

| Hex | Index | Keyword | Hex | Index | Keyword |
|-----|-------|---------|-----|-------|---------|
| $0100 | 00 | PRINT | $0101 | 01 | DIM |
| $0102 | 02 | LIST | $0103 | 03 | SAVE |
| $0104 | 04 | LOAD | $0105 | 05 | RUN |
| $0106 | 06 | CLR | $0107 | 07 | GOTO |
| $0108 | 08 | INT | $0109 | 09 | FOR |
| $010A | 0A | TO* | $010B | 0B | STEP* |
| $010C | 0C | NEXT | $010D | 0D | ENDPROC |
| $010E | 0E | GOSUB | $010F | 0F | RETURN |
| $0110 | 10 | IF | $0111 | 11 | THEN* |
| $0112 | 12 | ELSE* | $0113 | 13 | FRE |
| $0114 | 14 | CREATE | $0115 | 15 | STRFRE |
| $0116 | 16 | MERGE | $0117 | 17 | REM |
| $0118 | 18 | STOP | $0119 | 19 | HELP |
| $011A | 1A | NEW | $011B | 1B | DEF |
| $011C | 1C | FN | $011D | 1D | INPUT |
| $011E | 1E | ON | $011F | 1F | OPEN |
| $0120 | 20 | CLOSE | $0121 | 21 | SPC |
| $0122 | 22 | TAB | $0123 | 23 | DATA* |
| $0124 | 24 | READ | $0125 | 25 | RESTORE |
| $0126 | 26 | GET | $0127 | 27 | LEN |
| $0128 | 28 | STR$ | $0129 | 29 | VAL |
| $012A | 2A | FUNCTION | $012B | 2B | ASC |
| $012C | 2C | CHR$ | $012D | 2D | LEFT$ |
| $012E | 2E | RIGHT$ | $012F | 2F | MID$ |
| $0130 | 30 | POS | $0131 | 31 | NOT |
| $0132 | 32 | CMD | $0133 | 33 | POKE |
| $0134 | 34 | PEEK | $0135 | 35 | SIN |
| $0136 | 36 | COS | $0137 | 37 | SQR |
| $0138 | 38 | LOG | $0139 | 39 | LN |
| $013A | 3A | EXP10 | $013B | 3B | TAN |
| $013C | 3C | ATN | $013D | 3D | EXP |
| $013E | 3E | SGN | $013F | 3F | ABS |
| $0140 | 40 | RND | $0141 | 41 | SYS |
| $0142 | 42 | CONT | $0143 | 43 | CLS |
| $0144 | 44 | WPEEK (DPEEK) | $0145 | 45 | WPOKE (DPOKE) |
| $0146 | 46 | LPEEK | $0147 | 47 | LPOKE |
| $0148 | 48 | ATANPT | $0149 | 49 | MOD |
| $014A | 4A | GEMDOS | $014B | 4B | BIOS |
| $014C | 4C | XBIOS | $014D | 4D | VARPTR |
| $014E | 4E | DIR | $014F | 4F | HEX$ |
| $0150 | 50 | BIN$ | $0151 | 51 | CURSOR |
| $0152 | 52 | PROC | $0153 | 53 | END |
| $0154 | 54 | LOCAL | $0155 | 55 | DELETE |
| $0156 | 56 | INKEY$ | $0157 | 57 | WAIT |
| $0158 | 58 | SWAP | $0159 | 59 | TRON |
| $015A | 5A | TROFF | $015B | 5B | INSTR$ |
| $015C | 5C | CALL | $015D | 5D | AESCTRL |
| $015E | 5E | AESINTIN | $015F | 5F | AESINTOUT |
| $0160 | 60 | AESADRIN | $0161 | 61 | AESADROUT |
| $0162 | 62 | VDICTRL | $0163 | 63 | VDIINTIN |
| $0164 | 64 | VDIINTOUT | $0165 | 65 | VDIPTSIN |
| $0166 | 66 | VDIPTSOUT | $0167 | 67 | AES |
| $0168 | 68 | VDI | $0169 | 69 | CONVERT |
| $016A | 6A | DUMP | $016B | 6B | TRACE* |
| $016C | 6C | AND* | $016D | 6D | OR* |
| $016E | 6E | EOR* | $016F | 6F | AUTO |
| $0170 | 70 | EDTAB | | | |

*Tokens marked with \* are not standalone commands -- they are used as operators or modifiers parsed by other commands (TO/STEP by FOR, THEN/ELSE by IF, DATA by READ, AND/OR/EOR by the expression evaluator, TRACE by ON).

### TOKEN2 and TOKEN3: Extended Command Classes

**TOKEN2 ($02xx):**

| Hex | Keyword String | Handler |
|-----|---------------|---------|
| $0200 | `line2` | `line` (Line-A draw line) |

**TOKEN3 ($03xx):**

| Hex | Keyword String | Handler |
|-----|---------------|---------|
| $0300 | `line3` | `line` (Line-A draw line) |

#### Architecture

TOKEN2 and TOKEN3 are **secondary and tertiary token classes** providing a mechanism for extending the keyword set beyond 256 entries per class. The entire interpreter infrastructure fully supports all three classes identically -- the tokenizer (`konv_inpuf`), detokenizer (`listlines`), command dispatcher (`exec_line`), expression evaluator (`get_fkt`), and trace handler all check for TOKEN1, TOKEN2, and TOKEN3:

```asm
cmp.b   #TOKEN1,d0      ; $01?
beq     exec2
cmp.b   #TOKEN2,d0      ; $02?
beq     exec2
cmp.b   #TOKEN3,d0      ; $03?
beq     exec2
```

The dispatch uses a shared 4-entry index table: `comadr[0]` is unused, `comadr[1/2/3]` point to `comadr1`/`comadr2`/`comadr3` respectively. Likewise `tokenadr[1/2/3]` point to `token1adr`/`token2adr`/`token3adr`. The token class byte directly indexes these tables (multiplied by 4 for longword access).

#### TOKEN2/TOKEN3: The LINE Command

Both TOKEN2 and TOKEN3 contain a single entry each, both dispatching to the same `line` handler (Line-A drawing at BASIC_COMMENTS.S:9385). Their keyword strings are `"line2"` and `"line3"`. There is no LINE entry in TOKEN1 (which has 113 entries, $00-$70).

**The user must type `LINE2` (or `LINE3`), not simply `LINE`.** The tokenizer compares character-by-character: typing `LINE 10,20,...` matches 4 characters of `"line2"` but then '2' ≠ ' ' (space), causing a mismatch. The full 5-character `LINE2` is required for the match to succeed. When listed, the detokenizer outputs `LINE2` (from the token string with bit 7 cleared).

Both token classes dispatch to the same handler, suggesting TOKEN2/TOKEN3 were planned for different LINE variants (2D vs. 3D?) but the distinction was never implemented. The date comment "7.11.88" on these definitions marks them as late additions (one week after the 31.10.88 base date). The architecture supports 3 × 256 = 768 keywords, but only 115 are defined -- TOKEN2/TOKEN3 are infrastructure for extensions never populated.

### Tokenizer Algorithm (konv_inpuf)

The tokenizer (`konv_inpuf`) processes the `input_puf` buffer in a single pass:

1. **Quote tracking:** A flag `d7` toggles on `"` and `'` characters. Inside quotes, no tokenization occurs.

2. **Command detection:** When a letter is encountered outside quotes, the tokenizer checks if it could be the start of a command (and not part of a variable name by calling `isvarn` on the preceding character).

3. **Token matching:** The input is compared against `tokenstr`, a table of all keyword strings. Matching is case-insensitive (lowercase input is compared against lowercase token strings).

4. **Abbreviation via bit 7:** In the `tokenstr` table, each keyword has specific uppercase letters that mark abbreviation points. During `b_init`, all uppercase letters in token strings are converted to lowercase with bit 7 set. For example, `"dIm"` becomes `"d"`, `chr(0x69|0x80)`, `"m"`. When the user types an abbreviated form in lowercase (e.g., `"di"`), the tokenizer matches up to the first bit-7-marked character and accepts it as a complete match. The uppercase letter marks the minimum point where abbreviation is accepted. For example:
   - `"dIm"` -- typing `di` suffices (the uppercase `I` marks the abbreviation point)
   - `"print"` -- no uppercase letters, so the full word must be typed (but `?` is a special shortcut)
   - `"gOto"` -- `go` suffices

5. **Token insertion:** When a match is found, the original keyword text is replaced in the buffer with the two-byte token value (from `tokennr` table), and remaining characters are shifted.

### Complete Keyword Abbreviation Table

The abbreviation system is encoded directly in the `tokenstr` table in the source code. Each keyword string uses mixed case where the **first uppercase letter** marks the minimum abbreviation point: all characters up to (but not including) the first uppercase letter must be typed. Keywords that are entirely lowercase (or only 2 characters long) cannot be abbreviated and must be typed in full.

| tokenstr | Full Keyword | Minimum | | tokenstr | Full Keyword | Minimum |
|----------|-------------|---------|---|----------|-------------|---------|
| `print` | PRINT | print | | `dIm` | DIM | di |
| `lIst` | LIST | li | | `sAve` | SAVE | sa |
| `lOad` | LOAD | lo | | `rUn` | RUN | ru |
| `clr` | CLR | clr | | `gOto` | GOTO | go |
| `inT` | INT | int | | `fOr` | FOR | fo |
| `to` | TO | to | | `sTep` | STEP | st |
| `nExt` | NEXT | ne | | `eNdproc` | ENDPROC | en |
| `goSub` | GOSUB | gos | | `reTurn` | RETURN | ret |
| `if` | IF | if | | `tHen` | THEN | th |
| `eLse` | ELSE | el | | `fRe` | FRE | fr |
| `cReate` | CREATE | cr | | `strFre` | STRFRE | strf |
| `mErge` | MERGE | me | | `rEm` | REM | re |
| `stOp` | STOP | sto | | `hElp` | HELP | he |
| `nEw` | NEW | ne | | `dEf` | DEF | de |
| `fn` | FN | fn | | `iNput` | INPUT | in |
| `on` | ON | on | | `oPen` | OPEN | op |
| `cLose` | CLOSE | cl | | `sPc` | SPC | sp |
| `tAb` | TAB | ta | | `dAta` | DATA | da |
| `reAd` | READ | rea | | `reStore` | RESTORE | res |
| `gEt` | GET | ge | | `lEn` | LEN | le |
| `stR$` | STR$ | str | | `vAl` | VAL | va |
| `fUnction` | FUNCTION | fu | | `aSc` | ASC | as |
| `cHr$` | CHR$ | ch | | `leFt$` | LEFT$ | lef |
| `rIght$` | RIGHT$ | ri | | `mId$` | MID$ | mi |
| `pos` | POS | pos | | `nOt` | NOT | no |
| `cMd` | CMD | cm | | `pOke` | POKE | po |
| `pEek` | PEEK | pe | | `sIn` | SIN | si |
| `cos` | COS | cos | | `sQr` | SQR | sq |
| `log` | LOG | log | | `ln` | LN | ln |
| `exP10` | EXP10 | exp | | `tAn` | TAN | ta |
| `aTn` | ATN | at | | `eXp` | EXP | ex |
| `sGn` | SGN | sg | | `aBs` | ABS | ab |
| `rNd` | RND | rn | | `sYs` | SYS | sy |
| `cOnt` | CONT | co | | `cls` | CLS | cls |
| `wpEek` | WPEEK | wpe | | `wpOke` | WPOKE | wpo |
| `lpEek` | LPEEK | lpe | | `lpOke` | LPOKE | lpo |
| `atAnpt` | ATANPT | ata | | `mOd` | MOD | mo |
| `geMdos` | GEMDOS | gem | | `bIos` | BIOS | bi |
| `xBios` | XBIOS | xb | | `varPtr` | VARPTR | varp |
| `dir` | DIR | dir | | `heX$` | HEX$ | hex |
| `bIn$` | BIN$ | bi | | `cUrsor` | CURSOR | cu |
| `prOc` | PROC | pro | | `end` | END | end |
| `loCal` | LOCAL | loc | | `deLete` | DELETE | del |
| `inKey$` | INKEY$ | ink | | `wAit` | WAIT | wa |
| `sWap` | SWAP | sw | | `tRon` | TRON | tr |
| `trOff` | TROFF | tro | | `inStr$` | INSTR$ | ins |
| `cAll` | CALL | ca | | `aesCtrl` | AESCTRL | aesc |
| `aesintIn` | AESINTIN | aesinti | | `aesintOut` | AESINTOUT | aesinto |
| `aesadrIn` | AESADRIN | aesadri | | `aesadrOut` | AESADROUT | aesadro |
| `vdiCtrl` | VDICTRL | vdic | | `vdiintIn` | VDIINTIN | vdiinti |
| `vdiintOut` | VDIINTOUT | vdiinto | | `vdiptsIn` | VDIPTSIN | vdiptsi |
| `vdiptsOut` | VDIPTSOUT | vdiptso | | `aEs` | AES | ae |
| `vDi` | VDI | vd | | `coNvert` | CONVERT | con |
| `dUmp` | DUMP | du | | `trAce` | TRACE | tra |
| `aNd` | AND | an | | `or` | OR | or |
| `eOr` | EOR | eo | | `aUto` | AUTO | au |
| `eDtab` | EDTAB | ed | | | | |

**Disambiguation note:** Several abbreviations collide in their shortest form. The tokenizer resolves this by matching the **longest** token first (it scans the token table in order, and the first complete match wins). For example, `st` matches STEP before STOP because STEP appears earlier in the table. Similarly, `ne` matches NEXT before NEW.

### Detokenization (LIST/TRACE)

The LIST command (`listlines`) and TRACE handler reverse the process. When a token intro byte (`$01`, `$02`, or `$03`) is encountered in program data:

1. The intro byte selects the token group via `tokenadr` (a table of pointers to per-group name tables: `token1adr`, `token2adr`, `token3adr`).
2. The second byte indexes into the name table to find the keyword string pointer.
3. The keyword is copied to the output buffer with bit 7 cleared and letters converted to uppercase.

### Pseudo-Code: Tokenizer (`konv_inpuf`, BASIC_COMMENTS.S:828)

The tokenizer operates in a single left-to-right pass over the input buffer, replacing keyword text with 2-byte token sequences in-place. This means the buffer can shrink (keywords like `PRINT` become 2 bytes) or stay the same size, but never grows -- the `shift_buffer` operation compacts the buffer after each replacement. A critical guard: keywords are only matched when preceded by a non-variable-name character, preventing partial matches inside variable names (e.g., `format` must not match `for`). The abbreviation system uses bit 7 in the token string to mark the minimum acceptance point -- once the tokenizer has matched past a bit-7 character and the input ends (non-letter follows), the abbreviation is accepted even though the full keyword wasn't typed.

```
function konv_inpuf(input_puf):
    """Convert keywords in input buffer to 2-byte tokens in-place."""
    pos = 0
    in_quotes = false

    while input_puf[pos] != NUL:
        ch = input_puf[pos]

        if in_quotes:
            if ch == '"': in_quotes = false
            pos++; continue

        if ch == '?':                    # PRINT shortcut
            shift_buffer_right(pos+1, 1) # make room for 2-byte token
            insert PRINT token at pos
            pos += 2; continue

        if ch == '\'' (single quote):    # REM shortcut
            in_quotes = true             # rest of line is comment
            pos++; continue

        if ch == '"':
            in_quotes = true
            pos++; continue

        # Only try keyword match if ch is a letter AND
        # the preceding character is NOT a variable-name character
        if ch is letter AND (pos == 0 OR prev_char is not varname_char):
            match = try_match_keyword(input_puf, pos)
            if match found:
                keyword_len = matched characters consumed
                token_bytes = 2          # [class_byte, index_byte]
                shift_buffer(pos, keyword_len → token_bytes)
                write token at pos
                pos += 2; continue

        pos++

function try_match_keyword(buf, pos) → (token_index, chars_consumed):
    """Try to match input at pos against all keywords in tokenstr."""
    for each token in tokenstr (index 0..N):
        match_pos = pos
        token_pos = 0

        while token_char = tokenstr[token][token_pos]:
            input_char = tolower(buf[match_pos])
            compare_char = token_char with bit7 cleared

            if input_char != compare_char:
                break                    # mismatch

            match_pos++; token_pos++

            # Check for valid abbreviation:
            # If input ends here (non-letter follows) and we have reached
            # or passed the first bit7-marked character → abbreviation accepted
            if buf[match_pos] is not a letter:
                if any bit7-marked char was already seen: MATCH
                if token_char had bit7 set: MATCH

        if reached end of token string:  MATCH (full keyword typed)

    return no match
```

**68000 Implementation Notes:** The quote flag is toggled with `not.w d7` (line 864), a single instruction that flips all bits -- since the flag is tested with `tst.w d7`, any non-zero value counts as "in quotes". Case-insensitive comparison works by setting bit 5 of the input character (`bset #5,d0`, which forces lowercase) or clearing bit 7 of the token character -- the token strings have bit 7 set on the minimum-abbreviation character, so the comparison clears it with `bclr #7` before matching. The PRINT shorthand `?` replacement (lines 889-892) shifts the buffer rightward byte-by-byte in a loop (`konvprl`), because a single `?` character must expand to a 2-byte token -- the buffer grows by 1 byte at that point.

---

## 4. Type System

### Fundamental Types

| Type | Flag Value | Storage Size | Description |
|------|-----------|-------------|-------------|
| FLOAT | 1 | 12 bytes (3 longs) | BCD floating-point, ~22 digits precision |
| INT | 2 | 4 bytes (1 long) | 32-bit signed integer |
| STRING | 4 | 4 bytes (1 pointer) | Pointer to reverse-stored, null-terminated string |

### Float Register Format

Floats are passed in registers d0-d3:

- **d0:** Bits 31 = sign (0=positive, 1=negative), bits 15-0 = exponent biased by `$4000`
- **d1:** Upper BCD mantissa digits (4 bits per digit)
- **d2:** Middle BCD mantissa digits
- **d3:** Lower BCD mantissa digits (often zero, used for extended precision)

Example: The value 1.0 is represented as `d0=$00004001, d1=$00010000, d2=0, d3=0` (sign=0, exponent=$4001 meaning 10^1, mantissa=0001...).

The constant `pi` is stored as: `$00004001, $00031415, $92653589, $79323800`.

### Type Flag Bits

The type word stored with each variable combines the base type with modifier flags:

| Flag | Value | Meaning |
|------|-------|---------|
| ARRAYTYP | `$8000` | Bit 15: variable is an array |
| FNTYP | `$4000` | Bit 14: DEF FN argument variable |
| DEFFNTYP | `$2000` | Bit 13: DEF FN function variable |
| PROCTYP | `$1000` | Bit 12: procedure variable |
| (bits 3-11) | | Procedure number (procnr, multiplied by 8) for local scoping |

### Type Coercion Rules

- **INT <-> FLOAT:** Automatic conversion in either direction. `ltor_` converts long integer to float; `rpkl` converts float to packed long integer.
- **STRING <-> numeric:** Incompatible. Attempting to mix strings with numeric types raises error 1 (type mismatch). Explicit conversion requires `VAL()` (string to numeric) or `STR$()` (numeric to string).
- **INT -> FLOAT promotion:** When a binary operation involves one INT and one FLOAT operand, the INT is promoted to FLOAT via `ltor_` before the operation.

See also Section 5 for type promotion behavior during expression evaluation.

---

## 5. Expression Evaluator

### Recursive Descent Parser

The expression evaluator uses recursive descent with operator-precedence parsing. The call hierarchy is:

```
get_term / get_defterm / gets_term
  -> get1_term          (entry: clears typ2flag, initializes fac1)
    -> get3_term        (loop: element, then check for operators)
      -> get_element    (atoms: variables, constants, functions, parenthesized subexpressions)
      -> get_operator   (reads operator, returns priority)
      -> get2_term      (second operand, handles priority via recursion)
      -> exec_operation (dispatches to operator routine)
```

### Operator Table

There are 13 operators, ordered by ascending priority:

| Priority | Symbol | Operation | Routine |
|----------|--------|-----------|---------|
| 1 | `{` | Shift left | `ShL` |
| 2 | `}` | Shift right | `ShR` |
| 3 | `~` / `EOR` | Bitwise XOR | `Xor` |
| 4 | `&` / `AND` | Bitwise AND | `And` |
| 5 | `\|` / `OR` | Bitwise OR | `Or` |
| 6 | `<` | Less than | `Lower` |
| 7 | `=` | Equal | `Equal` |
| 8 | `>` | Greater than | `Higher` |
| 9 | `+` | Addition / string concatenation | `Add` |
| 10 | `-` | Subtraction | `Sub` |
| 11 | `*` | Multiplication | `Mul` |
| 12 | `/` | Division | `Div` |
| 13 | `^` | Exponentiation | `Exponent` |

Comparison operators support compound forms: `<=`, `>=`, `<>` (not equal). These are detected by examining the `follchar` (the character following the first comparison operator).

AND, OR, and EOR are recognized as token-based operators by `get_operator` when a TOKEN1 intro byte is seen, mapping them to priorities 3-5 respectively.

### Priority Handling

When the evaluator encounters an operator of higher priority than the current one, it recursively calls `get2_term` via `to_next_op`, pushing the pending lower-priority operation onto the CPU stack. This ensures correct mathematical precedence: `2 + 3 * 4` evaluates as `2 + (3 * 4)`.

### Type Promotion During Evaluation

Type promotion during expression evaluation follows the rules defined in Section 4 (Type Coercion Rules). In `exec_operation`, mixed INT/FLOAT operands trigger promotion via `ltor_`; integer overflow triggers late conversion via `lateconv`.

### Integer Arithmetic with Transparent Float Fallback

The arithmetic operators (Add, Sub, Mul, Div) attempt integer operations first and **transparently promote to float on overflow**:

- **Add/Sub:** Use the 68000's `bvs` (branch on overflow) instruction to detect signed 32-bit overflow, then jump to `SOVER_` which converts both operands to float and retries the operation with `radd_`/`rsub_`.
- **Mul:** Performs `imul` (integer multiply), then checks `fl1work` for overflow. If set, calls `lateconv` to convert both operands to float and retries with `rmul_`.
- **Div:** Performs integer division, checks for remainder. If nonzero, falls back to `rdiv_` for exact float division.

This means the programmer never sees type promotion -- `3 * 1000000000` silently returns a float when the 32-bit integer result would overflow. The `bvs` instruction checks the 68000's V (overflow) flag, which is set by ADD/SUB when the signed result cannot be represented in 32 bits.

### Bitwise Operator Type Handling (convint/reconvint)

All bitwise operators (ShL, ShR, And, Or, Xor) share a common wrapper pattern:

1. `convint`: If operands are FLOAT, convert both to INT via `rpkl` (truncating the fractional part). If STRING, raise type mismatch.
2. Perform the integer bitwise operation.
3. `reconvint`: If the original type was FLOAT, convert the result back to FLOAT via `ltor_`.

This means `3.7 AND 5.2` works: both are truncated to integers (3 AND 5 = 1), and the result is returned as a float (1.0) if the expression context requires it. The pattern ensures bitwise operations always work on integers internally, regardless of the programmer's variable types.

### String Concatenation

The `+` operator handles string concatenation. String operands are detected in `get1_term` when `typ2flag` is STRING. The evaluator copies the first string into the string heap via `resv_str`, then appends subsequent strings via `copy_str`. Since strings are stored in reverse, `copy_str` handles the correct byte ordering.

### Element Parsing (get_element / get_var_konst)

The `get_element` routine handles:
- Parenthesized subexpressions: `(` triggers recursive `get3_term`
- Functions: token intro bytes dispatch to `get_fkt`
- String constants: `"..."` via `get_strkonst`
- Hex literals: `$...` via `get_hexvar`
- Binary literals: `%...` via `get_binvar`
- Variables: recognized by `isvarname`, fetched via `get_var`
- Numeric literals: parsed by `rlda_` (ASCII to float) with possible demotion to INT if the value fits
- Unary minus: detected and applied after the element is parsed

### FUNCTION -- Expression Evaluator (Alias for VAL)

`FUNCTION(string_expr)`

Despite its name, this is **not** related to DEF FN function definitions. It takes a string expression, mirrors it from reverse to forward storage, then evaluates it as a numeric expression using `get_term`. Returns the numeric result. Unlike `VAL()` which performs simple numeric conversion, FUNCTION evaluates full expressions (e.g., `FUNCTION("2+3*4")` returns 14).

**Implementation:** `Function` at BASIC_COMMENTS.S:3833.

### Pseudo-Code: Expression Evaluator (`get1_term` / `get2_term` / `to_next_op`, BASIC_COMMENTS.S:7154)

The expression evaluator is the most algorithmically intricate part of the interpreter. It uses recursive-descent parsing with operator-precedence climbing: when it encounters an operator with higher priority than the current one, it recursively evaluates the higher-priority subexpression first. The `onqlist`/`offqlist` calls around recursive evaluation are essential -- without them, string pointers held during the outer expression could be invalidated by garbage collection triggered during the inner evaluation. The precedence climbing happens in `get2_term`/`to_next_op`: the evaluator peeks at the next operator, and if it binds tighter, pushes the current state onto the CPU stack and recurses. This is more efficient than a Pratt parser for this use case because the 68000's stack operations are fast.

```
function get_term(expected_type) → value:
    """Main entry: evaluate expression and convert to expected type."""
    result = get1_term()
    if expected_type != result.type:
        result = convert(result, expected_type)  # konvfl/konvint/konvstr
    return result

function get1_term() → value:
    """Core evaluation: element { operator element }*"""
    fac1 = 0                             # initialize accumulator
    typ2flag = NONE                      # no first operand type yet

    # --- get3_term: fetch first element ---
    element = get_element()
    if element is NONE: return fac1      # empty expression
    typ2flag = element.type
    if element.type != STRING:
        fac1 = element.value             # store in accumulator

    # --- Operator loop ---
    loop:
        op = get_operator()              # look for +, -, *, /, ^, <, =, >, etc.
        if op is NONE: return fac1       # no more operators → done

        if typ2flag == STRING:
            if op is not '+' and not comparison: return fac1
            # string comparison: save strend for later

        # --- get2_term: fetch second operand ---
        save(follchar, operator, typ2flag)   # push to stack
        protect_strings(onqlist)
        element2 = get_element()
        if element2 is NONE: error "syntax"
        restore(follchar, operator, typ2flag)
        unprotect_strings(offqlist)

        fac2 = element2.value

        # --- Precedence climbing ---
        next_op = peek_operator()        # look ahead at next operator
        if next_op exists AND next_op.priority > op.priority:
            # Higher precedence: defer current op, recurse
            push(fac1, op, typ2flag)     # save current state on stack
            fac1 = fac2                  # second operand becomes first
            operator = next_op           # next op becomes current
            call get2_term()             # recurse for higher-priority subexpr
            fac2 = fac1                  # recursion result is second operand
            pop(fac1, op, typ2flag)      # restore deferred state

        # --- Type coercion and execute ---
        if fac1.type != fac2.type:
            coerce both to FLOAT         # INT+FLOAT → both FLOAT
        result = exec_operation(op, fac1, fac2)   # dispatch via optabl
        fac1 = result
        continue loop
```

**68000 Implementation Notes:** The accumulator `fac1` is initialized to zero with `movem.l zero_,d0-d3` (line 7158), which loads 4 longwords (16 bytes, of which 12 are used) from the `zero_` constant in a single instruction -- `movem.l` is the 68000's bulk register load/store, transferring multiple registers in one bus cycle sequence. The recursion state (follchar, operator, typ2flag) is saved to the CPU stack with individual `move.w` pushes (lines 7207-7209), maintaining the correct order for later restoration. The `work1` variable serves double duty: it holds the string comparison base pointer (`strend` at the time of comparison start), and its zero/non-zero state indicates whether a string comparison is in progress.

### Pseudo-Code: Element Dispatch (`get_var_konst`, BASIC_COMMENTS.S:7664)

Element dispatch is the leaf level of the expression evaluator -- it resolves one atomic value (number, string, variable, function call, or parenthesized subexpression). The dispatch is character-based: token intro bytes route to function handlers, `"` to string constants, `$`/`%` to hex/binary literals, letters to variable lookup, `(` to recursive subexpression evaluation, and digits to the `rlda_` float-to-ASCII parser. Unary minus is handled as a wrapper: the element is parsed first, then negated. For integers this is a simple `neg.l`; for floats it subtracts from zero via `rsub_`.

```
function get_var_konst(a0) → (value, type):
    """Parse one atomic element: number, string, variable, function, or subexpr."""
    ch = current_char()

    # Check for unary minus
    if ch == '-':
        negate = true
        advance()
        ch = next_char()
    else:
        negate = false

    # Dispatch based on first character
    result = match ch:
        TOKEN1, TOKEN2, TOKEN3 → get_fkt()          # function call
        '"'                    → get_strkonst()       # string literal "hello"
        '$'                    → get_hexvar()         # hex number $FF00
        '%'                    → get_binvar()         # binary number %1010
        letter (a-z, A-Z)     → get_var()            # variable lookup
        '('                    → get_klammerarg()     # parenthesized (sub-expr)
        digit or '.'           → no_var()            # decimal number via rlda_

    # Apply unary minus if pending
    if negate:
        if result.type == INT:
            result.value = -result.value             # neg.l d0
        elif result.type == FLOAT:
            result.value = 0.0 - result.value        # rsub_ from zero

    return result
```

**68000 Implementation Notes:** The unary minus flag is pushed as a word onto the stack (`move.w #-1,-(sp)` at line 7671 for true, `clr.w -(sp)` at line 7678 for false), then tested later with `tst.w (sp)+` (line 7740), which both tests and pops in one instruction. For float negation, the assembly moves d0-d3 (the parsed value) to d4-d7, loads `zero_` into d0-d3, then calls `rsub_` which computes `(d0-d3) - (d4-d7)` = `0.0 - value` (lines 7753-7759). The `savea0` checkpoint (line 7666) saves the program pointer before dispatch so that `no_var` (numeric literal parsing) can restore the position if the first character turned out to be a digit rather than a variable name.

---

## 6. Variable System

### Variable Name Parsing

Variable names are parsed by `tst_var` / `tst2_var`:

1. Leading spaces are skipped.
2. Characters matching `isvarname` (letters a-z, A-Z, underscore, digits after first character) are collected into `var_name` (80 bytes max).
3. A type suffix determines the variable type:
   - `$` suffix -> STRING
   - `%` suffix -> INT
   - `!` suffix -> FLOAT (explicit)
   - No suffix -> FLOAT (default)
4. If `(` follows the name, the variable is flagged as an array (`arrayfl`).
5. If `#` is encountered after the name characters but before the type suffix, it signals explicit global access (see below).

The full parse order within a variable token is: `name_chars` + `#` (optional) + `type_suffix` (optional: `$`, `%`, `!`) + `(` (optional: array subscript). Examples: `x#%` (global integer), `a#(0)` (global array element), `name#$` (global string), `val#` (global float with default type).

### Variable Lookup and Scope Resolution

Variables are searched via linear scan of the linked list starting at `varbase`. The search compares both the type word (including scope flags) and the name string byte-by-byte. If a variable is not found, `tst_vend` returns d0=0, and the caller typically creates it via `create2_var`.

The scope resolution logic is the most subtle part of the variable system. Three distinct contexts can be active: global scope (normal execution), procedure scope (inside a DEF PROC), and FN argument scope (inside a DEF FN evaluation). The `#` operator adds a fourth path: forced global access from within any scope. The key insight is that scope is encoded in the type word itself -- a local variable `x%` inside procedure 3 has `procnr=24` (3×8) OR'd into its type word, making it a different variable from the global `x%` (which has `procnr=0`). This means the linked list contains both versions side by side, and scope resolution is just a matter of which type word to search for.

```
function tst_var(name) → (found, pointer):
    """Look up a variable by name with scope resolution."""
    fnvarfl = 0                          # default: global scope
    return tst2_var(name)

function tst2_var(name) → (found, pointer):
    fnvarfl = scope_flag                 # 0=global, procnr=local, FNTYP=FN-arg

    # --- FN argument mode (inside DEF FN evaluation) ---
    if argfl != 0:
        save position
        fnvarfl = FNTYP                  # search FN-local first
        result = tv41(name)
        if found: return (FOUND_LOCAL, pointer)
        if fnvarfl was cleared by #:     # user forced global
            return (NOT_FOUND)           # don't fall through to global
        restore position
        fnvarfl = original               # try again with original scope
        goto tv41

    # --- Procedure scope (inside DEF PROC) ---
    if procnr != 0:
        save position
        fnvarfl = procnr                 # search procedure-local first
        result = tv41(name)
        if found: return (FOUND_LOCAL, pointer)
        if fnvarfl was cleared by #:     # user forced global
            return (NOT_FOUND)           # skip global fallback
        restore position
        fnvarfl = 0                      # fall through to global search

    # --- Global scope (or fallback) ---
    return tv41(name)

function tv41(name) → (found, pointer):
    """Core: parse name, determine type, search linked list."""
    parse variable name characters into buffer
    if '#' encountered:
        remove '#' from name buffer
        if fnvarfl == procnr or FNTYP:
            fnvarfl = 0                  # force global lookup
    parse type suffix: '$'→STRING, '%'→INT, '!'→FLOAT, default→FLOAT
    if '(' follows: set arrayfl

    # Check system variables (pi, ti, ti$)
    if name matches "pi": return pi constant (sysvar=-1)
    if name matches "ti": return VBL counter (sysvar=-2)
    if name matches "ti$": return time string (sysvar=-3)

    # Search variable linked list
    type_word = base_type | fnvarfl | (ARRAYTYP if array)
    var = varbase
    while var != NULL:
        if var.type_word == type_word AND var.name == name:
            return (FOUND, var.value_ptr)
        var = var.next
    return (NOT_FOUND)
```

**68000 Implementation Notes:** The scope flag save/restore pattern uses the CPU stack: `move.w fnvarfl,-(sp)` saves the current scope, and `move.w (sp)+,d1` restores it after the local search (lines 1610-1613). The variable linked list search (tv2 loop at line 1778) compares the type word first (`cmp.w d4,(a1)`) before comparing the name bytes -- this is an optimization because type mismatch is the common case and avoids the expensive byte-by-byte name comparison. Reading system variable `ti` requires supervisor mode because `_frclock` at $466 is in protected low memory; the assembly uses GEMDOS $20 (`Super`) to temporarily switch to supervisor mode, reads the longword, then returns to user mode.

### Array System

Arrays support up to 10 dimensions. The DIM statement:
1. Parses dimension sizes into `arraylen[0..9]`.
2. Creates a variable with `ARRAYTYP` ($8000) set in the type word.
3. The array header stores: `[dimension count].l {[dimension size].l}...`
4. Array elements follow the header as a flat block of values.

If an array variable is used without a prior DIM, it is auto-created with 1 dimension and 11 elements (indices 0-10) via `create2_var`.

Array element access uses row-major (C-style) linearization: for an array `A(d0, d1, d2)`, the linear index is `i0 * (d1_max * d2_max) + i1 * d2_max + i2`. The multiplier is accumulated right-to-left through the dimension sizes.

```
function posarray(array_ptr) → element_ptr:
    """Compute linear offset for multi-dimensional array access."""
    dims = array_ptr.dimension_count
    for i = 0 to dims-1:
        index[i] = evaluate next subscript expression (INT)
        if index[i] < 0: error "no negative arg allowed"
        if index[i] > dim_max[i]: error "bad subscript"

    # Row-major linearization (last dimension varies fastest)
    offset = 0
    multiplier = 1
    for i = dims-1 downto 0:
        offset += index[i] * multiplier
        multiplier *= dim_max[i]

    # Convert to byte offset
    element_size = 12 if FLOAT, 4 if INT or STRING
    return array_data_start + offset * element_size
```

**68000 Implementation Notes:** The dimension sizes are copied from the array header to the `array2len` buffer using `move.l (a1)+,(a2,d1)` with d1 incrementing by 4 (lines 1315-1318) -- the post-increment on a1 walks the header while the indexed addressing on a2 fills the buffer. The multiplier accumulation loop processes dimensions from last to first using `subq.l #4,d0` to walk backward through the `array2len` buffer (lines 1354-1363). Negative index detection uses `bmi negdimerr` (branch if minus, line 1334), which catches negative values because the 68000's N flag reflects the sign of the last tested value. Element size defaults to 4 bytes (`moveq.l #4,d0`, line 1370), with a type check overriding to 12 for FLOAT -- the common case (INT/STRING) takes the fast path.

### System Variables

Three system variables are recognized by name during `tst_var`:

| Name | Type | sysvar Code | Description |
|------|------|-------------|-------------|
| `pi` | FLOAT | -1 | Mathematical constant pi (3.14159265358979323800) |
| `ti` | INT | -2 | VBL frame counter (read from $466 = `_frclock`, ~70 Hz) |
| `ti$` | STRING | -3 | Time string "HH:MM:SS" (computed from `_frclock` via divide/multiply by 70) |

`pi` is read-only. `ti` and `ti$` are read-write: assigning to `ti` sets the VBL frame counter at $466 (`_frclock`); assigning to `ti$` parses "HH:MM:SS" and converts to ~70 Hz ticks. The counter is read/written inside a `Super` mode call (GEMDOS $20) to access the protected memory location. Note: `$466` is the VBL frame counter (`_frclock`, ~70 Hz on monochrome, ~50 Hz on PAL color), NOT the 200 Hz system timer (which is at `$4BA` = `_hz_200`).

See Section 9 for string storage details.

### SWAP -- Variable Exchange with Type Conversion

`SWAP var1, var2`

Swaps the values of two variables. Handles mixed types with automatic conversion:

| Combination | Behavior |
|-------------|----------|
| INT <-> INT | Simple 4-byte swap |
| FLOAT <-> FLOAT | 12-byte swap (3 longwords) |
| STRING <-> STRING | 4-byte pointer swap |
| INT <-> FLOAT | Converts each value to the other's type, then swaps |
| STRING <-> INT/FLOAT | **Type mismatch error** |

String variables are temporarily unmarked from GC protection (via clearing the `mark_str` byte) during the swap to avoid interference with the garbage collector.

**Implementation:** `Swapvars` at BASIC_COMMENTS.S:3739. Uses `rpkl` for float-to-int and `ltor_` for int-to-float conversion.

---

## 7. Procedure System

### Definition: DEF PROC

Procedures are defined with `DEF PROC name(params)` and terminated with `ENDPROC`. During `RUN`, the `get_procs` routine scans the entire program for DEF PROC statements before execution begins:

1. Each procedure is assigned a unique `procnr` (multiples of 8, starting at 8).
2. A procedure variable is created (type = `PROCTYP | STRING`).
3. Parameter variables are created with the `procnr` stamped into their type word (bits 3-11), making them local to that procedure.
4. The procedure's string value stores: `[procnr].w [coded-ptr-to-next-line].l {[param-type].w [coded-ptr-to-value].l}... $0000.w`

Pointers stored in procedure/function strings are encoded via `code_ptr`/`decode_ptr` (at line 4808) to avoid `$FF` bytes, since `$FF` is the garbage collection dead-string marker. The encoding works by saving the low byte, left-shifting the 32-bit value by 1 bit (multiply by 2), then restoring the low byte. In a 24-bit Atari ST address like `$00 01 FF 88`, only byte 2 (`$FF`) is problematic. Left-shifting transforms it to `$00 03 FE 88` (low byte preserved separately), eliminating the `$FF`. Decoding reverses the process: save low byte, right-shift by 1, restore low byte. This is safe because the 68000's 24-bit address bus means bit 24 is always 0, so the left-shift never loses data.

### Pseudo-Code: Procedure Discovery Pre-Scan (`get_procs`, BASIC_COMMENTS.S:5165)

The pre-scan is necessary because BASIC allows forward references: `PROC myproc` can appear before `DEF PROC myproc` in the source. Without a pre-scan, forward-referenced procedures would fail with "procedure not defined". The scan also collects parameter metadata (types and value pointers) into string space, using the `code_ptr` encoding to avoid `$FF` bytes that would confuse the garbage collector. The `procnr` numbering scheme (multiples of 8, stored in bits 3-11 of the type word) allows up to 511 procedures. Each procedure's LOCAL variables inherit its `procnr`, creating implicit scope isolation without a separate namespace mechanism.

```
function get_procs():
    """Pre-scan program for all DEF PROC definitions before execution."""
    procnr = 8                           # first procedure number (1×8)
    line = prgbase                       # start of program

    while line.next_ptr != NULL:
        token = read_2byte_token(line.data)
        if token != DEF: goto next_line
        sub_token = read_2byte_token()
        if sub_token != PROC: goto next_line

        # --- Found a DEF PROC ---
        parse procedure name
        if already defined: error "re-define"
        create procedure variable (type = PROCTYP | STRING)

        # Build definition string in buffer:
        buf[0..1] = procnr               # procedure number
        buf[2..5] = code_ptr(line.next)  # encoded pointer to body

        # Parse parameter list (if any)
        if next_char == '(':
            for each parameter:
                parse parameter name and type
                create parameter variable (type = base_type | procnr)
                buf[n] = param_type      # type without procnr
                buf[n+2..n+5] = code_ptr(param.value_ptr)
            expect ')'
        buf[end] = $0000                 # end-of-parameters marker

        # Store definition string in string heap
        copy buf → string_heap (strend grows downward)
        proc_variable.value = string_pointer

        procnr += 8                      # next procedure
        if procnr >= 512*8: error "procedure overflow"

    next_line:
        line = line.next

    anzprocs = (procnr / 8) - 1         # total procedure count
    procnr = 0                           # reset to global scope
```

**68000 Implementation Notes:** The `code_ptr` encoding (line 5197) solves a subtle conflict: procedure definition strings are stored in the string heap alongside normal strings, but the heap uses `$FF` as a dead-string marker for garbage collection. A raw 24-bit Atari ST address like `$01FF88` contains a `$FF` byte that would be misidentified as dead. The encoding left-shifts the value by 1 bit (effectively multiplying by 2), transforming `$FF` bytes into `$FE` bytes. The low byte is preserved separately because the shift would corrupt it. On the 68000's 24-bit address bus, this encoding is reversible without loss. The final procedure count is computed with `lsr.w #3,d0; subq.w #1,d0` (lines 5279-5280): right-shift by 3 divides the `procnr` value by 8, and subtracting 1 accounts for the initial `procnr = 8` (which represents "procedure 1").

### Procedure Table

The procedure call stack (`proctbl`) holds 100 entries of 14 bytes each:

| Offset | Size | Content |
|--------|------|---------|
| 0 | 4 | Caller's line number (`akt_zeile`) |
| 4 | 4 | Caller's line address (`akt_adr`) |
| 8 | 4 | Caller's execution pointer (a0) |
| 12 | 2 | Caller's procedure number (`procnr`) |

`proctblptr` points to the next free entry. Maximum nesting depth is 100.

### Calling Convention (PROC command)

When `PROC name(args)` is executed:

1. The procedure variable is looked up via `tst_dprcvar`.
2. The procedure string is decoded to extract the `procnr` and line pointer.
3. Arguments are evaluated and written to the parameter variables via `write_var`.
4. The current execution state is pushed onto `proctbl`.
5. The caller's `procnr` is saved and replaced with the procedure's `procnr`.
6. Execution jumps to the line following DEF PROC.

Procedures can also be called by simply typing their name (without the PROC keyword). The `var_def` routine detects this case: if no `=` sign is found before `:` or end-of-line, it branches to `Proc`.

**GC protection during argument passing:** When passing string arguments, the evaluated string values must not be garbage-collected between evaluation time and the time they are written to the procedure's local variables. `mark_str` (BASIC_COMMENTS.S:1277) writes a `$FF` byte just before the string data in the heap, making the GC treat it as a live string boundary. After the argument is safely written, the `$FF` is cleared. Without this protection, a GC triggered by evaluating the second argument could invalidate the first argument's string pointer.

### ENDPROC

`Endproc` pops the procedure call stack, restores the caller's line number, address, execution pointer, and `procnr`, then continues execution.

### LOCAL Variables

`LOCAL var1, var2, ...` creates variables stamped with the current `procnr`. These shadow any global variables of the same name. `LOCAL DIM a(n)` creates a local array.

See Section 9 for `qlist` string protection during procedure calls.

---

## 8. Control Flow Structures

### FOR/NEXT

The FOR table (`fortable`) holds up to 100 entries of 42 bytes each:

| Offset | Size | Content |
|--------|------|---------|
| 0 | 4 | Pointer to loop variable's value |
| 4 | 2 | Type (INT or FLOAT) |
| 6 | 12 | TO value (3 longs, FLOAT format; or first long for INT) |
| 18 | 12 | STEP value (same format) |
| 30 | 4 | Line number of the FOR statement |
| 34 | 4 | Address of the FOR line |
| 38 | 4 | Address of the statement after FOR/TO/STEP |

`foreptr` points to the next free entry. On NEXT:
1. The loop variable is incremented by the STEP value.
2. The result is compared against the TO value.
3. If the STEP is negative, the comparison direction is reversed.
4. If the limit has not been reached, execution returns to the statement after FOR.
5. Otherwise, the FOR entry is popped and execution continues after NEXT.

If no STEP is specified, the default is 1 (INT) or 1.0 (FLOAT).

The STEP direction handling is the subtlest part: negative STEP reverses the exit comparison. For integers, the sign bit of the STEP value (bit 31) selects the comparison direction. For floats, the sign is in bit 7 of the first BCD byte (the exponent/sign word). This means `FOR i=10 TO 1 STEP -1` correctly counts down and exits when `i < 1`, while `FOR i=1 TO 10` exits when `i > 10`. Both directions include the endpoint.

```
function For():
    """FOR var = start TO end [STEP increment]"""
    var_ptr, var_type = parse "var = start" (assigns start value)
    if var_type == STRING: error "type mismatch"

    # Allocate 42-byte FOR table entry
    if foreptr >= endfortbl: error "for-next overflow"
    entry.var_ptr = var_ptr
    entry.type = var_type

    entry.to_value = evaluate TO expression (12 bytes, FLOAT format)

    if STEP keyword present:
        entry.step_value = evaluate STEP expression
    else:
        entry.step_value = 1 (INT) or 1.0 (FLOAT)

    entry.line_number = akt_zeile
    entry.line_address = akt_adr
    entry.resume_ptr = current program pointer (a0)
    foreptr += 42

function Next():
    """NEXT [var] -- increment and test loop variable."""
    entry = foreptr - 42                 # current FOR entry
    if entry < fortable: error "next without for"
    var_ptr = entry.var_ptr

    if entry.type == INT:
        value = *var_ptr + entry.step_value
        *var_ptr = value
        if entry.step_value >= 0:        # positive STEP
            if value > entry.to_value: goto loop_done
        else:                            # negative STEP
            if value < entry.to_value: goto loop_done
    else:                                # FLOAT
        value = radd_(*var_ptr, entry.step_value)
        *var_ptr = value
        if entry.step_value sign >= 0:   # check bit 7 of exponent word
            if rcmp_(value, entry.to_value) > 0: goto loop_done
        else:
            if rcmp_(value, entry.to_value) < 0: goto loop_done

    # Continue loop: restore execution point to statement after FOR
    akt_zeile = entry.line_number
    akt_adr = entry.line_address
    a0 = entry.resume_ptr
    return

loop_done:
    foreptr -= 42                        # pop FOR entry
    return                               # continue after NEXT
```

**68000 Implementation Notes:** The default FLOAT STEP value 1.0 is encoded as `$4001, $00010000, $0000` (lines 4356-4358) -- this is the BCD floating-point representation where `$4001` is the exponent+sign word (exponent=1, sign=positive) and `$00010000` is the mantissa (1.0 in BCD). The STEP direction detection at NEXT time tests bit 7 of the first STEP longword (`btst #7,...` at lines 4270, 4284), which is the sign bit of the BCD exponent word. For INT loops, the direction check tests bit 31 of the 32-bit STEP value (the standard signed integer sign bit). The FOR table overflow check uses `cmp.l #endfortbl-42,a1; bhi forflow` (lines 4318-4319) -- comparing against `endfortbl-42` ensures there's room for one more 42-byte entry. The `sysallow` flag (cleared at line 4312) prevents system variables (`pi`, `ti`, `ti$`) from being used as loop variables, because writing to `pi` is prohibited and `ti`/`ti$` have special read/write behavior that would interfere with loop semantics.

### GOSUB/RETURN

The GOSUB table (`gostabl`) holds up to 100 entries of 12 bytes:

| Offset | Size | Content |
|--------|------|---------|
| 0 | 4 | Caller's line number |
| 4 | 4 | Caller's line address |
| 8 | 4 | Return address (pointer into tokenized line) |

RETURN pops the top entry and resumes execution at the saved address. If bit 31 of the return address is set, this was a TRACE GOSUB return, and the trace mode is re-enabled.

### IF/THEN/ELSE

The IF table (`iftbl`) holds up to 100 entries of 4 bytes each, storing the truth value (0 or non-zero) of the IF condition.

**Algorithm:**
1. IF evaluates its condition expression.
2. `tstelse` performs a look-ahead: it checks whether the next program line begins with ELSE.
3. If an ELSE exists on the next line, the condition result is pushed onto `iftbl`.
4. If true: execution continues with the statements after THEN on the current line.
5. If false: execution skips to the next line (`iffalse` -> `exec_end`).
6. When ELSE is encountered (on the next line), it pops the `iftbl` entry and inverts the logic: if the original IF was true, ELSE skips; if false, ELSE executes.

The `ifcnt` counter tracks nested IFs within a single line; ELSE look-ahead only works for the outermost IF in a line. This is a pragmatic limitation: supporting nested ELSE would require matching IF/ELSE pairs across lines, which the simple stack-based approach cannot do. In practice, nested IF/THEN on the same line with ELSE on the next line always pairs ELSE with the outermost IF.

```
function If():
    """IF condition THEN statements"""
    condition = evaluate expression (INT)
    has_else = tstelse()                 # look ahead to next line for ELSE

    if has_else:
        if ifendptr >= endiftbl: error "if-then-else overflow"
        *ifendptr = condition            # push condition result
        ifendptr += 4

    if next token != THEN: error "missing <then>"

    if condition != 0:                   # TRUE
        return                           # continue executing after THEN
    else:                                # FALSE
        skip to end of line              # statements after THEN are skipped

function Else():
    """ELSE statements (must be on line immediately following IF/THEN)"""
    ifendptr -= 4                        # pop condition from iftbl
    condition = *ifendptr

    if condition != 0:                   # original IF was TRUE → skip ELSE
        skip to end of line
    else:                                # original IF was FALSE → execute ELSE
        return                           # continue with ELSE statements

function tstelse() → boolean:
    """Check if next program line starts with ELSE token."""
    if b_modus == 0: return false        # no ELSE in direct mode
    ifcnt += 1
    if ifcnt > 1: return false           # nested IF → no ELSE support
    next_line = akt_adr.next_ptr
    if next_line.first_token == ELSE: return true
    return false
```

**68000 Implementation Notes:** The IF handler uses `addq.l #4,sp` (line 4196) to pop the return address from the stack, which causes execution to skip back to the `exec_line` main loop rather than returning to the statement that called IF. This is a controlled stack manipulation: by discarding the return address, the IF handler effectively "takes over" the execution flow. The `iftbl` stores 4-byte entries but only uses the value as a boolean (0 or non-zero) -- using longwords rather than bytes avoids alignment issues on the 68000. The `tstelse` look-ahead (lines 4209-4231) reads the next program line's first token by skipping 8 bytes past the next-pointer (`addq.l #8,a0` at line 4220) to reach the tokenized data, then comparing the 2-byte token against the ELSE token code.

### ON expr GOTO/GOSUB

`ON` evaluates an integer expression, then scans a comma-separated list of line numbers. The N-th line number (1-based) is selected. With GOTO, execution jumps directly; with GOSUB, the return address is saved first.

### ON TRACE GOSUB

A special form: `ON TRACE GOSUB line` sets up a trace callback. When TRACE is active (TRON), before each statement executes, the interpreter displays the current statement text and then performs a GOSUB to the trace line. The trace flag is temporarily disabled during the GOSUB and re-enabled on RETURN (detected by bit 31 in the return address).

### Loop Structures

There is no DO/LOOP construct. The only loop structure is FOR/NEXT. Infinite loops must be constructed with `FOR i=0 TO 1 STEP 0` or `GOTO`.

### Pseudo-Code: RUN Loop (`Run` / `runcont`, BASIC_COMMENTS.S:5897)

The RUN loop is straightforward: it walks the program's linked list, executing each line via `exec_line`. The interesting parts are at the boundaries. Before execution starts, `Clr1` wipes all variables and `get_procs` pre-scans for procedures -- this is why RUN always takes a moment on large programs. After execution ends (NULL next-pointer), the interpreter validates that all control structures are closed: unclosed FOR, GOSUB, or PROC generate errors at program end rather than silently disappearing. The `runcont` entry point is used by CONT; it skips the CLR/get_procs setup and resumes from the saved line.

```
function Run(optional line_number):
    contline = -1                        # disable CONT
    Clr1()                               # clear all variables and tables
    restore_data_pointer()               # reset READ/DATA
    get_procs()                          # pre-scan program for all PROC definitions

    if line_number specified:
        line = find_line(line_number)    # poszeile → linked list search
        if not found: error "line not found"
    else:
        line = first_line()              # start from beginning

    b_modus = -1                         # program mode
    akt_zeile = line.number
    reset_stack()                        # lea stack,sp

    # --- Main execution loop ---
    while line.next_ptr != NULL:         # not past end of program
        akt_adr = address_of(line)       # save for error reporting
        a0 = line.data                   # pointer to tokenized code (offset 8)
        ifcnt = 0                        # reset IF nesting for this line

        exec_line(a0)                    # execute all statements on this line

        line = line.next                 # follow linked list
        akt_zeile = line.number          # update current line number

    # --- Program end reached: validate all structures closed ---
    if foreptr != fortable:  error "FOR without NEXT"
    if goseptr != gostabl:   error "GOSUB without RETURN"
    if proctblptr != proctbl: error "PROC without ENDPROC"
    goto basic1                          # return to direct mode
```

**68000 Implementation Notes:** The `reset_stack` at the start of RUN (`lea stack,sp` at line 5906) is critical: it discards any stale stack frames from previous direct-mode commands or aborted programs, giving the new program a clean stack. The program end validation checks three separate stack pointers against their base addresses (`foreptr` vs `fortable`, `goseptr` vs `gostabl`, `proctblptr` vs `proctbl`), catching unclosed structures that the programmer might not notice. The `get_procs` pre-scan is what makes this BASIC dialect support forward procedure references -- most BASIC dialects require procedures to be defined before use, but because `get_procs` scans the entire program before execution begins, `PROC myproc` on line 10 can call `DEF PROC myproc` on line 200.

---

## 9. String Management

### Reverse Storage

All strings in the string heap are stored **in reverse byte order**. If the logical string is "HELLO", it is stored in memory as:

```
$00  'O'  'L'  'L'  'E'  'H'
```

The null terminator is at the lowest address, and the first logical character is at the highest address. The string pointer points to the last byte (the first logical character, 'H').

This unusual design likely optimizes string concatenation: appending to a string means growing downward in memory toward lower addresses, which is the natural direction of the heap.

### Output: putstrreverse

The `putstrreverse` routine outputs strings correctly by iterating from the pointer backward to the null terminator. It uses a clever trick: it temporarily zeroes each byte after reading it, outputs the character, then restores it.

### mirror_str

When a string must be passed to system calls (which expect normal byte order), `mirror_str` creates a forward copy in `mirrorpuf` (512 bytes). It reads from the string pointer backward to the null terminator and writes forward into the mirror buffer.

### String Heap Operations

- **`resv_str`:** Allocates space on the string heap by setting `str_ptr` to `strend` (the current top of the heap). Sets a flag bit to indicate a new allocation.

- **`copy_str` / `copy2_str`:** Copies string data into the heap. For string constants (from program text), bytes are copied forward into the heap growing downward. For variable strings (already reversed), bytes are copied in reverse. The `strend` pointer is decremented accordingly.

- **Garbage collection trigger:** Before allocating, `cstr3` checks if `strend - string_length < varend`. If so, `garbage` is called. If there is still not enough space after collection, error 56 (out of string space) is raised.

### Garbage Collection

Dead strings are marked with `$FF` at their start (lowest address) by `mark_str`. This happens when a string variable is reassigned: the old string is marked dead before the new value is stored.

The garbage collector (`garbage`):

1. Saves all registers to `savereg` and pushes critical pointers (`pgarbend`, `str_ptr`, `strend`) onto `qlist` via `onqlist`.
2. Scans from `strbase` downward.
3. For each string: if it starts with `$FF`, it is dead. The collector compacts the heap by copying all data below the dead string upward by the dead string's length.
4. After compacting, all string pointers must be adjusted. The collector updates:
   - **Variables:** scans the variable linked list for STRING-type entries (including arrays).
   - **Registers:** updates saved register values in `savereg` (since A-registers may hold string pointers).
   - **qlist:** updates all entries in the cross-reference list.
5. The `linkstr` subroutine checks if a pointer falls within the affected range and adjusts it by the compaction distance.

### onqlist / offqlist

These routines implement a pointer preservation stack for GC safety:

- `onqlist`: pushes `spstr` onto the `qlist` array (250 entries max) and advances `qlistptr`.
- `offqlist`: pops the top entry back into `spstr` and decrements `qlistptr`.

Any string pointer that must survive a potential garbage collection is pushed via `onqlist` before the operation and popped via `offqlist` afterward. The GC updates all entries in `qlist` during compaction.

### Pseudo-Code: Garbage Collector (`garbage`, BASIC_COMMENTS.S:8751)

The garbage collector is a compacting collector -- it physically moves live strings upward to fill gaps left by dead strings, then adjusts every pointer that referenced the moved data. This is expensive (O(n×m) for n strings and m variables) but simple to implement and avoids fragmentation entirely. The `$FF` dead-string marker is the trigger: when a string variable is reassigned, `mark_str` writes `$FF` at the old string's start address, flagging it for collection. The three categories of pointer adjustment (variables, saved registers, qlist) reflect the three places string pointers can hide during execution. The `savereg` adjustment is particularly notable: it handles the case where a register held a string pointer when GC was triggered mid-expression.

```
function garbage():
    """Compact string heap, remove dead strings, update all pointers."""
    # Phase 1: Save state
    save d0-d7 to stack
    save a0-a6 to savereg[]
    push pgarbend, str_ptr, strend onto qlist  # GC-safe protection

    # Phase 2: Scan from top of heap downward
    scan_ptr = strbase                   # start at top (highest address)

    while scan_ptr >= pgarbend:          # scan until limit
        scan_ptr++                       # advance into string body
        while true:
            byte = *(--scan_ptr)         # read downward
            if byte == $00: break        # NUL → end of live string, skip
            if byte == $FF:              # dead string marker!
                # --- Compact: remove dead string ---
                dead_top = remember_top
                dead_size = dead_top - scan_ptr
                bytes_to_move = scan_ptr - pgarbend

                # Shift all strings BELOW upward by dead_size
                for i = 0 to bytes_to_move:
                    *(dead_top - i) = *(scan_ptr - i)

                # Update all pointers in the moved region
                for each string variable in varbase..varend:
                    if var.string_ptr is in moved region:
                        var.string_ptr += dead_size
                for each array string element:
                    same adjustment
                for each saved register in savereg[a0..a6]:
                    if in moved region: adjust
                for each entry in qlist:
                    if in moved region: adjust

                scan_ptr += dead_size    # skip past compacted area
                break                    # continue scanning

    # Phase 3: Restore
    pop strend, str_ptr from qlist       # may have been adjusted by compaction
    # Note: pgarbend is NOT restored (assembly line 8891 has this commented out)
    restore d0-d7 from stack
    restore a0-a6 from savereg
```

**68000 Implementation Notes:** The backwards byte-by-byte copy uses `move.b -(a2),-(a3)` (line 8802) -- the 68000's pre-decrement addressing mode decrements both pointers before the move, implementing a downward copy in a single instruction per byte. This is necessary because the strings grow downward in memory, so compaction must shift data upward (toward higher addresses) while preserving order. The assembly emits a short beep via key tone output (lines 8766-8770) at the start of GC as a "working" indicator to the user -- a thoughtful touch in an era when GC pauses could be noticeable. The three pointer-adjustment subroutines (`garb_var` at line 8860, `garb_reg` at line 8839, `garb_qlist` at line 8823) each use `linkstr` to check whether a pointer falls within the compacted region and adjust it by the compaction distance. An important detail: `pgarbend` was originally intended to be restored from the qlist but this is commented out in the source (line 8891), meaning the GC scan boundary is not adjusted after compaction -- this appears intentional, as the boundary only needs to mark the lowest point reached during the current GC pass.

---

## 10. File I/O

### Handle Table

The handle table (`handtab`) has 100 entries of 4 bytes each:

| Bytes 0-1 | Bytes 2-3 |
|-----------|-----------|
| BASIC logical handle | GEMDOS physical handle |

Handles 0-5 are reserved system devices:

| Handle | Device |
|--------|--------|
| 0 | Standard input (CON:) |
| 1 | Standard output (CON:) |
| 2 | Standard error |
| 3 | Standard auxiliary (RS-232) |
| 4 | Printer (PRN:) |
| 5 | (reserved) |

### File Commands

- **`OPEN handle, "filename"`:** Opens an existing file for read/write (GEMDOS `Fopen`, function `$3D`, mode 2). The BASIC handle is stored in `handtab` along with the returned GEMDOS handle.
- **`CREATE handle, "filename"`:** Creates a new file (GEMDOS `Fcreate`, function `$3C`, attribute 0).
- **`CLOSE handle`:** Closes the file (GEMDOS `Fclose`, function `$3E`) and clears the handle table entry. Handles 0-5 cannot be closed.

### I/O Operations

- **`f_read`:** GEMDOS `Fread` ($3F). Parameters: handle, length, buffer pointer. Returns bytes read in d0.
- **`f_write`:** GEMDOS `Fwrite` ($40). Parameters: handle, length, buffer pointer.
- **`PRINT #handle`:** Sets `filefl` to redirect output through `f_write` instead of the screen. The `put_string` routine checks `filefl` and routes output accordingly. Line feeds (LF, $0A) are automatically added after carriage returns (CR, $0D).
- **`INPUT #handle`:** Reads from a file. Fields are delimited by TAB ($09), CR ($0D), or null ($00). LF ($0A) is skipped.
- **`CMD handle`:** Sets persistent output redirection. Both `cmdfl` and `filefl` are set to -1. Output remains redirected until another file operation resets `filefl`.

### Binary .BAS Format

Programs are saved in a binary format with a magic header:

**Header:** `"HEAD"` = `$48454144` (4 bytes)

**Save process:**
1. Write the 4-byte header.
2. Convert absolute next-line pointers to relative offsets by subtracting the program base address.
3. Write the program data (from the selected line range).
4. Re-link pointers back to absolute addresses.

**Load process:**
1. Verify the 4-byte header.
2. Read all program data into memory starting at `prgbase`.
3. Call `new_link` to convert relative offsets back to absolute addresses by adding `prgbase` to each next-line pointer.

The SAVE command supports optional line range parameters: `SAVE "file", startline, endline`.

### MERGE and CONVERT

- **`MERGE "filename"`:** Loads a binary .BAS file and inserts its lines into the current program (using the normal line insertion mechanism `basic20`).
- **`CONVERT "filename"`:** Reads a plain text file line by line, tokenizes each line with `konv_inpuf`, and inserts it as if typed at the keyboard. This converts ASCII BASIC listings into tokenized programs.

### DIR -- Directory Listing

`DIR [path]`

Lists files and directories. Without a path argument, lists `*.*` in the current directory. Subdirectories are displayed in uppercase, regular files in lowercase. Each entry shows: `"filename"` padded to 14 chars, file size (right-aligned), and attribute indicator. Drive selection supported: `DIR "A:*.BAS"` changes to drive A before listing.

Uses GEMDOS `Fsfirst` ($4E) and `Fsnext` ($4F) with search attribute $31 (all files + subdirs).

**Implementation:** `Dir` at BASIC_COMMENTS.S:2051. Uses `dta_puf` (50 bytes) as the DTA buffer, `mirror_str` to convert the backwards string path to forward.

---

## 11. System Integration

### GEMDOS/BIOS/XBIOS Calls

The interpreter provides unified access to all three TOS trap interfaces through `GEMDOS(fno, args...)`, `BIOS(fno, args...)`, and `XBIOS(fno, args...)`.

**Parameter descriptor tables:** Each trap has a master table (`gemdtbl`, `biostbl`, `xbiostbl`) structured as:

```
[entry count].w
[pointer to function 0 descriptor].l
[pointer to function 1 descriptor].l
...
```

Each per-function descriptor is a sequence of `(type, size)` word pairs terminated by `0`:

| Type word | Meaning |
|-----------|---------|
| STRING (4) | String argument (pointer, reverse-to-forward mirrored) |
| INT (2) | Integer argument |

| Size word | Meaning |
|-----------|---------|
| 0 | Push as word (.w) |
| 1 | Push as longword (.l) |

A descriptor value of -1 means the function number is not supported.

**Execution flow (`callsys`):**
1. The function number is read and validated against the table size.
2. Parameters are read left-to-right using `get_term`, with string arguments mirrored to forward byte order via `mirror_str`.
3. Parameters are pushed onto the system stack in reverse order (right-to-left, as TOS expects).
4. The appropriate trap is executed via a **self-modifying instruction** -- the trap number is patched into the `calltrap` opcode at runtime:
   ```
   and.w  #$fff0,calltrap    ; Clear low nibble of the trap instruction
   or.w   d0,calltrap         ; Patch in the trap number (1, 13, or 14)
   ...
   calltrap: trap  #0         ; THIS INSTRUCTION IS PATCHED AT RUNTIME
   ```
   The 68000 `trap #N` instruction encodes N in bits 0-3 of its opcode word ($4E40+N). Since the 68000 has no instruction cache, the modified opcode is immediately visible to the fetch unit. When executed, the CPU pushes PC and SR, switches to supervisor mode, and vectors through `$80 + 4*N` (GEMDOS at $84, BIOS at $B4, XBIOS at $B8).
5. The return value is placed in d0 as an INT.

String pointers are temporarily preserved via `onqlist`/`offqlist` during the trap call.

The most surprising aspect of this implementation is the self-modifying trap instruction: rather than having three separate code paths for GEMDOS, BIOS, and XBIOS, a single `trap #0` instruction has its operand byte patched at runtime to become `trap #1`, `trap #13`, or `trap #14`. This works because the 68000 `trap #N` instruction encodes N in bits 0-3 of the opcode word. The descriptor-driven parameter handling means adding a new GEMDOS function requires only a new table entry, not new code.

```
function callsys(trap_number, descriptor_table):
    """Unified GEMDOS/BIOS/XBIOS call handler."""
    # Patch trap instruction
    calltrap = (calltrap AND $FFF0) OR trap_number

    # Read and validate function number
    func_no = evaluate expression (INT)
    if func_no > table.max or descriptor[func_no] == -1:
        error "improper function number"

    # Read parameters left-to-right per descriptor
    desc = descriptor[func_no]
    param_buf = inputpuf
    while desc.type != 0:                # end-of-params marker
        value = evaluate expression (desc.type)
        if desc.type == STRING:
            mirror_str(value → mirrorpuf)  # reverse BASIC string to C string
            value = pointer_to_mirrored_string
        if desc.size == 0:               # word parameter
            store value as .w in param_buf
        else:                            # longword parameter
            store value as .l in param_buf
        desc = next descriptor entry

    # Execute trap with parameters on stack
    save a0; onqlist()
    push parameters from param_buf onto stack (reverse order)
    execute patched calltrap instruction   # trap #1, #13, or #14
    offqlist(); restore a0
    return d0 as INT                     # system call return value
```

**68000 Implementation Notes:** The self-modifying trap instruction is the centerpiece: `and.w #$fff0,calltrap` clears bits 0-3 of the `trap` opcode word, then `or.w d0,calltrap` patches in the trap number (1 for GEMDOS, 13 for BIOS, 14 for XBIOS). This works because the 68000 `trap #N` instruction is encoded as opcode `$4E40+N`, with N in bits 0-3. The 68000 has no instruction cache, so the modified instruction is immediately visible to the instruction fetch unit -- this technique would fail on later processors (68020+) with caches. The right-to-left parameter push uses `move.w -(a2),-(sp)` in a loop (line 2484-2486), which walks backward through the `inputpuf` buffer while pushing to the system stack -- this implements the C calling convention expected by TOS trap handlers. When a TRAP instruction executes, the 68000 automatically pushes PC and SR to the supervisor stack and switches to supervisor mode, then vectors through the exception table at `$80 + 4*N` (address $84 for GEMDOS, $B4 for BIOS, $B8 for XBIOS). String parameters require special handling because BASIC stores strings in reverse byte order internally; `mirror_str` (called at line 2461) copies the string backward-to-forward into `mirrorpuf`, producing the null-terminated C-style string that TOS expects. The `mirptr` pointer (initialized at line 2454) tracks the current position in the 512-byte mirror buffer, allowing multiple string parameters in a single call.

### AES Interface

AES (Application Environment Services) is accessed through direct array manipulation:

- **`AESCTRL offset, value`** -- Set/read AES control array entries
- **`AESINTIN offset, value`** -- Set AES integer input array
- **`AESINTOUT(offset)`** -- Read AES integer output array
- **`AESADRIN offset, value`** -- Set AES address input array
- **`AESADROUT(offset)`** -- Read AES address output array
- **`AES [ctrl0, ctrl1, ...]`** -- Execute AES call via `trap #2` with `AESPB` parameter block

The `AESPB` parameter block contains pointers to all five arrays: `AESctrl`, `AESglobal`, `AESintin`, `AESintout`, `AESadrin`, `AESadrout`.

When used as a command, AESCTRL sets values. When used as a function (via the `cmdfktfl` flag and bit 28 in the command table), it reads values.

### VDI Interface

VDI (Virtual Device Interface) follows the same pattern:

- **`VDICTRL offset, value`** / `VDICTRL(offset)` -- VDI control array
- **`VDIINTIN offset, value`** -- VDI integer input
- **`VDIINTOUT(offset)`** -- VDI integer output
- **`VDIPTSIN offset, value`** -- VDI points input
- **`VDIPTSOUT(offset)`** -- VDI points output
- **`VDI [ctrl0, ctrl1, ...]`** -- Execute VDI call via `trap #2` with `VDIPB` parameter block

### Line-A Graphics

The `LINE2 x1, y1, x2, y2` command draws lines using the Line-A interface:

1. Coordinates are written to Line-A variables: `X1` (offset 38/$26), `Y1` (offset 40/$28), `X2` (offset 42/$2A), `Y2` (offset 44/$2C).
2. The `$A003` opcode (Line-A `A_abline` -- arbitrary line) is executed via the special 68000 opcode mechanism.

Line-A variables are initialized during `Init` (HEADER.S:122-125) using symbolic offsets from the Line-A variable block (see `atari-tos-main/doc/additional_material/atari.s` for the full offset table):

| Offset | Symbol | Init Value | Meaning |
|--------|--------|-----------|---------|
| 24/$18 | `COLBIT0` | 1 | Foreground color plane 0 (1 = black in mono) |
| 32/$20 | `LSTLIN` | -1 | Draw last pixel flag (-1 = yes) |
| 34/$22 | `LNMASK` | $FFFF | Line style mask (solid line) |
| 36/$24 | `WMODE` | 1 | Write mode (0=replace, 1=XOR, 2=transparent, 3=reverse transparent) |

The Line-A variable block base address is obtained at startup via the `$A000` (A_init) trap and stored in `la_variablen`. All drawing operations reference offsets from this base. Key BIOS system variables used by the interpreter (from `atari.s`):

| Address | Symbol | Description |
|---------|--------|-------------|
| $466 | `_frclock` | VBL frame counter (~70 Hz), used by `ti` and `ti$` |
| $452 | `vblsem` | VBL semaphore (referenced indirectly via Vsync in WAIT) |

### CALL -- Machine Code Interface with Register Passing

`CALL address [, d0 [, d1 ... [, *a0 [, *a1 ...]]]]`

Calls a machine language subroutine with full 68000 register control:

- **Data registers (d0-d7):** Specified as bare integer values, assigned left-to-right.
- **Address registers (a0-a6):** Prefixed with `*` (asterisk), e.g., `CALL addr, *$FF8240`.
- **Overflow:** If more than 8 data-register values are given, extras overflow into address registers automatically.
- **Skipping registers:** A double comma `,,` or closing `)` skips a register, leaving it at its default (0).
- **Return value:** d0 is returned as an INT result.
- **Recursive:** Supports nested CALL by saving/restoring the register buffers (`calltbld0`/`calltbla0`) on the stack.

The register overflow mechanism is the clever part: rather than requiring the user to explicitly label each parameter as data or address, the interpreter fills d0-d7 first (left to right), and when all 8 data registers are full, any additional unmarked parameters automatically overflow into a0-a6. The `*` prefix forces an address register regardless of position. Double comma `,,` leaves a register at its default value (0), enabling sparse register patterns like `CALL addr, 42,, *$FF8240` which sets d0=42, skips d1, and sets a0=$FF8240.

```
function Call(address):
    """Call machine code with register passing. Returns d0."""
    # Save previous register state (supports recursive CALL)
    push calltbld0[0..7] onto stack
    push calltbla0[0..6] onto stack

    target = evaluate address expression (INT)
    d_count = 0; a_count = 0             # register counters

    while comma separator present:
        ch = peek next character
        if ch == '*':                    # explicit address register
            consume '*'
            a_count++
            if a_count > 7: error "too many args"
            value = evaluate expression (INT)
            calltbla0[a_count-1] = value
        elif ch == ',' or ch == ')':     # skip (double comma or end)
            d_count++                    # leave register at 0
        else:                            # data register (or overflow)
            value = evaluate expression (INT)
            if d_count < 8:
                calltbld0[d_count] = value
                d_count++
            else:                        # overflow to address registers
                calltbla0[a_count] = value
                a_count++

    # Execute
    load d0-d7 from calltbld0
    load a0-a6 from calltbla0
    JSR target                           # via self-modifying jumpfac1
    save d0-d7 back to calltbld0         # preserve return state
    save a0-a6 back to calltbla0

    # Restore previous state
    pop calltbla0, calltbld0 from stack
    return d0 as INT
```

**68000 Implementation Notes:** The bulk register save/restore uses `movem.l`, the 68000's multi-register transfer instruction: `movem.l d0-d7,calltbld0` stores all 8 data registers (32 bytes) in a single instruction, and `movem.l calltbld0,d0-d7` loads them back. This is both compact and fast compared to 8 individual `move.l` instructions. The actual subroutine call goes through `jumpfac1` (line 2684), which is another self-modifying code pattern: the target address from `fac1` is written into a JMP instruction's operand field, then the JMP is executed. This is necessary because the 68000 has no "JSR to address in data register" instruction -- the address must be in memory or an address register. The recursive CALL support works by pushing the old register buffer contents onto the stack before the call, then restoring them afterward (lines 2616-2619 save, 2689-2692 restore). The `*` prefix for address registers is detected by checking the next input character against `'*'` before evaluating the parameter expression.

### SYS -- Simple Machine Code Jump

`SYS address`

Jumps to a machine code address and executes it. Unlike CALL, there is no register passing or return value. The address is evaluated as an INT expression.

**Implementation:** `Sys` at BASIC_COMMENTS.S:2704. Uses self-modifying code via `jumpfac1` to patch a JMP instruction's target address at runtime.

---

## 12. Floating-Point Library (BLIBF.S)

### BCD Format

The library uses Binary Coded Decimal (BCD) representation, not IEEE 754. Each digit occupies 4 bits (one nibble), with two digits packed per byte. This provides approximately 22 digits of decimal precision.

### Register Layout

```
d0: [sign (bit 31)] [unused bits 30-16] [exponent (bits 15-0, biased by $4000)]
d1: [BCD mantissa, upper 8 digits]
d2: [BCD mantissa, middle 8 digits]  
d3: [BCD mantissa, lower 8 digits (often 0)]
```

The exponent bias is `$4000`. An exponent of `$4001` means 10^1, `$4002` means 10^2, etc.

### Constants

| Name | Value | Stored as (d0, d1, d2) |
|------|-------|------------------------|
| `zero_` | 0.0 | `$0000, $00000000, $00000000` |
| `one_` | 1.0 | `$4001, $00010000, $00000000` |
| `pi_` | 3.14159... | `$4001, $00031415, $92653589` |
| `halfpi_` | 1.57079... | `$4001, $00015707, $96326794` |
| `loge_` | 0.43429... | `$4000, $00043429, $44819032` |
| `ln10_` | 2.30258... | `$4001, $00023025, $85092994` |

### Arithmetic Operations

| Routine | Operation | Method |
|---------|-----------|--------|
| `radd_` | A + B | BCD addition using 68000 `ABCD` instruction chains. Operands are denormalized to the same exponent, then mantissa bytes are added with carry. |
| `rsub_` | A - B | Negates B (flips bit 31) then calls `radd_`. BCD subtraction uses `SBCD` instruction chains. |
| `rmul_` | A * B | Pseudo-multiplication via repeated shift-and-add in BCD. Uses `psrmul_` with intermediate storage in `fl1work`/`fl2work`. |
| `rdiv_` | A / B | Pseudo-division via repeated compare-and-subtract in BCD. |
| `rcmp_` | Compare A, B | Compares sign bits first, then exponents, then mantissa longwords. Returns condition codes for BEQ/BLT/BGT. |

### Transcendental Functions

| Routine | Function | Algorithm |
|---------|----------|-----------|
| `rsin_` | sin(x) | Computes via tangent half-angle: calls `rtanr_` then `sincos_` |
| `rcos_` | cos(x) | Same as sin but with quadrant flag flipped |
| `rtan_` | tan(x) | Calls `rtanr_` (tangent ratio) then `rdiv_` |
| `ratan_` | atan(x) | Calls `ratan2_` with B=1 |
| `ratan2_` | atan2(y,x) | CORDIC-like pseudo-division (`psatan_`) with tabulated arctangent values (`Fatntab_`) |
| `rexp_` | e^x | Computes as `rexp10_(x * log10(e))` |
| `rexp10_` | 10^x | Radix conversion + pseudo-multiplication with log table |
| `rlog_` | ln(x) | Computes as `rlog10_(x) * ln(10)` |
| `rlog10_` | log10(x) | Pseudo-division by log table (`pslog_` + `psmullog_`) |
| `rsqrt_` | sqrt(x) | Iterative pseudo-square-root (`pssqrt_`) with denormalization |
| `rrand_` | random | Linear congruential generator using BCD pseudo-multiplication |
| `rmod_` | A mod B | Modulo operation via division and remainder extraction |

### Conversion Routines

| Routine | Conversion | Description |
|---------|-----------|-------------|
| `rlda_` | ASCII -> float | Parses decimal number string from (a0), returns float in d0-d3. Sets `typflag` to FLOAT if a decimal point is present or the number exceeds INT range. |
| `rpka_` | float -> ASCII | Converts d0-d3 to decimal string in `ascii` buffer. Returns pointer in a2 (string stored in reverse for `putstrreverse`). |
| `ipka_` | int -> ASCII | Converts d0 (32-bit signed integer) to decimal ASCII string. Returns pointer in a2. |
| `ltor_` | long -> float | Converts d4 (signed 32-bit integer) to BCD float in d0-d3. |
| `rpkl` | float -> long | Converts d0-d3 BCD float to signed 32-bit integer in d0. |

### Integer Arithmetic

| Routine | Operation | Description |
|---------|-----------|-------------|
| `imul` | d0 * d4 | 32-bit signed multiplication. Sets `fl1work` non-zero on overflow (signals late conversion to float). |
| `idiv` | d0 / d4 | 32-bit signed division. Returns 0 in d0 if divisor is zero (triggers late float conversion for exact division). |

---

## 13. Editor Subsystem

### Overview

The editor provides a full-screen character-based editing interface. It maintains an internal character buffer (25 rows x 80 columns by default, configurable via the STAD structure) separate from the pixel framebuffer.

### Screen Coordinate System

- `ed_x`: Visible cursor column (0-based, relative to horizontal scroll offset)
- `ed_y`: Cursor row (0-based)
- `ed_xoffs`: Horizontal scroll offset (0 when no scrolling)
- Actual column in buffer = `ed_x + ed_xoffs`
- Pixel X = `ed_x * 8 + edi_x` (window offset)
- Pixel Y = `ed_y << edi_y_shft + edi_y` (window offset)

### Character Rendering and Storage (`ed_store`)

Characters are rendered via the `edi_print` callback (set to `_g_char` in standalone mode). The `_g_char` routine:

1. Calculates the screen memory address: `w_base + (y_pixel * w_screen) + (x_pixel / 8)`
2. Looks up the glyph in the GEM font data: `fontdat + char_code`
3. Copies one byte per scan line using an **unrolled loop** (16 iterations for 8x16 font, 8 for 8x8 font), advancing by `fontoffs` bytes in the font and `w_screen` bytes on screen between lines.

The `ed_store` routine (EDITOR.S:630) is the fundamental editor primitive -- every character typed flows through it. It performs three steps in sequence:

1. **Buffer store:** writes the character to `editscreen` at position `(ed_y * maxspalten) + ed_x + ed_xoffs`, accounting for horizontal scroll.
2. **Render:** computes pixel coordinates (`column * 8 + edi_x`, `row << edi_yshft + edi_y`) and calls the `edi_print` callback.
3. **Advance:** calls `ed_rechts` to move the cursor one position right, which may trigger horizontal scrolling.

### Cursor

The cursor is drawn by XOR-inverting (NOT) each byte in the character cell column for the full font height. Since XOR is self-inverting, `ed_curon` and `ed_curoff` are the same routine.

### Key Handling

The editor loop (`ed_edit`) reads keys via GEMDOS `Crawcin` (function 7) and dispatches:

| Key | Scan Code | ASCII | Action |
|-----|-----------|-------|--------|
| Left arrow | $4B | - | `ed_links`: move cursor left |
| Right arrow | $4D | - | `ed_rechts`: move cursor right |
| Up arrow | $48 | - | `ed_hoch`: move up / scroll up |
| Down arrow | $50 | - | `ed_runter`: move down / scroll down |
| Insert | $52 | - | `ed_insert`: insert space at cursor |
| Delete | $53 | - | `ed_delask`: delete char (CTRL+DEL = clear line) |
| Backspace | - | 8 | `ed_backspace` (= `ed_links`, just moves left) |
| Tab | - | 9 | `ed_tab`: jump to next tab stop |
| CLR/HOME | $47 | - | `ed_clrask`: HOME (SHIFT = clear screen) |
| ESC | - | $1B | Exit editor |
| RETURN | - | 13 | Send line to BASIC interpreter |
| ALT+UNDO | $61 | - | Break (stop program, checked by `chk_stop`) |

### Insert and Delete

`ed_insert` (EDITOR.S:502) and `ed_delete` (EDITOR.S:541) use opposite copy directions to avoid overwriting data during the shift:

- **Insert:** copies **right-to-left** (`move.b -(a0),1(a0)` at line 522) to shift characters one position to the right. Starting from the end of the line and working backward ensures each character is moved before its destination is overwritten. The rightmost character is dropped. A space is placed at the cursor position.
- **Delete:** copies **left-to-right** (`move.b 1(a0),(a0)+` at line 561) to shift characters one position to the left. Starting from the cursor and working forward ensures correctness. A space fills the vacated end position.

Both routines call `ed_prline` afterward to redraw the affected line.

### Scrolling

**Vertical scrolling** (`ed_runter`/`ed_hoch`, EDITOR.S:678/750): When the cursor moves past the bottom/top of the visible area, the entire character buffer is shifted by one row. The algorithm for scrolling down (`ed_runter`):

1. `delay` is called first -- checks BIOS `Kbshift` (trap #13, function 11) for modifier keys: **CTRL** pauses scrolling in a busy-wait loop until released; **SHIFT** inserts a delay (~163,840 iterations at `$28000`). Neither held = no delay.
2. `ed_chkstop` checks for ALT+UNDO (program break during output scrolling).
3. `ed_scrline` is cleared to 0 (no scroll yet).
4. If the cursor is at the bottom row: copy all rows up by one (`move.b (a1)+,(a0)+` loop, line 706); call `edi_predown` callback (BASIC provides the new bottom line content); fill the new bottom row with spaces; redraw the entire screen; set `ed_scrline` to the new line's buffer address.
5. After the move/no-move decision: if `ed_scrline` is non-zero (scroll happened), call `edi_down` callback to update BASIC's line tracking.

Scrolling up (`ed_hoch`) mirrors this with reversed copy direction (last row to first) and `edi_preup`/`edi_up` callbacks.

**Horizontal scrolling:** When a line exceeds the visible width, `ed_xoffs` is incremented and the line is re-rendered at the new offset. Moving left past column 0 decrements `ed_xoffs`.

### Editor State Flags

Three state variables (EDITOR.S:1098-1104) control editor behavior:

| Variable | Type | Purpose |
|----------|------|---------|
| `ed_mode` | word | 1 = in editor loop (BASIC line scrolling active); 0 = not in editor (e.g., during `b_enter` execution). Cleared before calling `b_enter`, set on return. |
| `ed_nlfl` | word | Newline flag: 0 = auto-wrap at end of line; 1 = stop at end (prevents PRINT output from wrapping beyond the visible line). |
| `ed_scrline` | long | Non-zero if a vertical scroll just occurred (holds pointer to new line in buffer). Used to conditionally invoke post-scroll callbacks. Cleared at the start of each scroll attempt. |

### Integration with BASIC

The `ed_editor` main loop (EDITOR.S:98-117) orchestrates the editor/interpreter interaction:

1. Set `ed_mode = 1` (enable BASIC line scrolling).
2. Call `ed_edit` (the key-reading loop). Returns on RETURN (Z=0) or ESC (Z=1).
3. On ESC: exit the editor entirely (`rts`).
4. On RETURN: clear `ed_mode = 0` (disable scrolling during interpreter execution).
5. If `edi_retprg` callback is set (STAD mode): call it with the line text.
6. If zero (standalone): call `b_enter` to process the line. A negative return from `b_enter` exits the editor (the `!` quit command returns -1).
7. Loop back to step 1.

### AUTO -- Automatic Line Numbering

`AUTO [start [, increment]]`

Enables auto line numbering mode. The editor automatically prepends line numbers when entering code. Default: start=100, increment=10. Uses `$7FFFFFFF` as sentinel to distinguish "not specified" from "zero specified". Disabled by entering a blank line or a command without a line number.

**State variables:** `autozeile` (current line number), `autoadd` (increment), `autofl` (active flag).

**Implementation:** `Auto` at BASIC_COMMENTS.S:3295.

### EDTAB -- Editor Tab Width

`EDTAB(n)`

A function that sets the editor's tab width to `n` tab stops and returns the previous value as INT. Operates by repeatedly calling `ed_tab` to advance the cursor. Has no effect when output is redirected to a file (`filefl` set).

**Implementation:** `Edtab` at BASIC_COMMENTS.S:5533.

---

## 14. Error Handling

### Error Handler

The central error handler at label `error` receives an error code in d0 (0-63):

1. If the CONVERT command was active (`convfl` != 0), the source file is closed first.
2. The current line number (`akt_zeile`) is saved.
3. If the error is code 26 (STOP/break) and execution is in program mode, the CONT state is saved:
   - `contline` = current line number
   - `contladr` = current line address
   - `contadr` = current execution pointer
4. Output is reset to screen (clears `filefl`).
5. The error message is printed: `? <message> error`
6. In program mode, ` in line N` is appended, followed by a listing of the offending line.
7. Execution returns to `basic1` (the interactive command loop).

### CONT Mechanism

After a STOP error (error 26), the user can type `CONT` to resume execution:

1. `contline` is checked (must be >= 0; -1 means no CONT possible).
2. `akt_zeile` is restored from `contline`.
3. `akt_adr` is restored from `contladr`.
4. Execution resumes from `contadr` (the saved execution pointer) via `runcont`.

Any program modification (line insert/delete) invalidates CONT by setting `contline` to -1.

### Key Error Codes

| Code | Label | Condition |
|------|-------|-----------|
| 0 | `syntaxerr` | Malformed statement |
| 1 | `typemis` | Type mismatch (e.g., string where number expected) |
| 6 | (from BLIBF) | Arithmetic overflow |
| 8 | (from BLIBF) | Division by zero |
| 9 | `badsubscr` | Array subscript out of range |
| 10 | `outvarmem` | Out of variable space |
| 13 | `outprgmem` | Out of program space |
| 26 | `stoperr` | Program stopped (STOP command or ALT+UNDO) |
| 56 | `outstrspc` | Out of string space |

For the complete table of all 64 error codes and messages, see BASIC-MANUAL.md Section 19 (Error Messages). Assembly label names for each error code are listed in BASIC-SYMBOLS.md.

### DUMP -- Variable Inspector

`DUMP [bitmask]`

A variable inspection tool with fine-grained filtering. The optional bitmask argument controls what to display:

| Bit | Value | Effect |
|-----|-------|--------|
| 0 | 1 | Show FLOAT variables |
| 1 | 2 | Show INT variables |
| 2 | 4 | Show STRING variables |
| 3 | 8 | Include ARRAY variables (otherwise skipped) |
| 4 | 16 | Only show occupied values (skip zeros and empty strings) |

Default (no argument): bitmask = 31 (all types + arrays + non-zero filter).

**Output format:** `varname! = value` (with `!` for FLOAT, `%` for INT, `$` for STRING). Arrays are iterated element by element, showing full subscripts like `arr(0,1,2)`.

FN/DEFFN/PROC variables are always skipped (filtered out by checking bits 12-14 of the type word). The dump can be interrupted with the break key.

The three-pass design is an interesting trade-off: rather than sorting output by type, it walks the entire linked list three times, once per base type (FLOAT, INT, STRING). This groups output by type (all floats first, then all ints, then all strings) at the cost of three full traversals. For multi-dimensional arrays, the element iteration uses a carry-cascade counter that increments the last dimension and propagates overflows leftward -- essentially treating the subscripts as a multi-digit counter.

```
function Dump(optional bitmask):
    """Display filtered variable values."""
    if bitmask not given: bitmask = $1F  # all types + non-zero filter
    type_filter = 1                      # start with FLOAT

    while type_filter <= 4:              # iterate: 1=FLOAT, 2=INT, 4=STRING
        if not (bitmask AND type_filter):
            type_filter <<= 1; continue  # skip this type

        var = varbase
        while var.next_ptr != NULL:
            var = var.next
            if var.type has FN/DEFFN/PROC bits: continue  # skip internal vars
            if (var.base_type AND type_filter) == 0: continue  # wrong type

            if var.type has ARRAYTYP:
                if not (bitmask AND 8): continue  # arrays filtered out
                dump_array(var, bitmask)
            else:
                dump_scalar(var, bitmask)

            check_for_break()            # user can interrupt with ALT+UNDO

        type_filter <<= 1               # next type: 1→2→4→done

function dump_scalar(var, bitmask):
    if (bitmask AND 16):                 # occupied-only filter
        if var is zero/empty: return     # skip
    print var.name + suffix + " = " + formatted_value

function dump_array(var, bitmask):
    """Iterate all elements using carry-cascade counter."""
    indices[0..n] = 0                    # initialize all subscripts to 0
    total_elements = product of all dimension sizes
    for each element:
        if (bitmask AND 16) and element is zero/empty: skip
        print var.name + "(" + indices + ")" + suffix + " = " + value
        # Increment counter: last dimension first, carry left
        indices[n]++
        if indices[n] > dim_max[n]:
            indices[n] = 0; indices[n-1]++
            # cascade carries leftward as needed
```

**68000 Implementation Notes:** The type iteration uses `lsl.b #1,dump2fl` (logical shift left by 1) to advance through the type values: 1 (FLOAT) → 2 (INT) → 4 (STRING) → 8 (exit condition). This is a compact bit-shift counter that avoids any conditional branching for type selection. The FN/DEFFN/PROC variable filter uses `and.w #$7FF8,d6` (line 3503) to mask the type word against the `procnr` field (bits 3-11) -- if non-zero, the variable belongs to a procedure/function scope and is hidden from DUMP. The type suffix is appended by overwriting the name's null terminator with `!`, `%`, or `$` (lines 3519-3527), then writing a new null terminator after it. The occupied-only filter (bit 4) compares FLOAT values against the `zero_` constant using `facscmp` (the float comparison routine), checks INT values with `tst.l`, and checks STRING pointers with `tst.l` for null/empty -- three different comparison methods for three different types.

**Implementation:** `Dump` at BASIC_COMMENTS.S:3466.

---

## 15. Build Process

The build process uses three tools from the Atari ST development toolchain, as documented in `BUILD.TXT`:

### Step 1: Assembly

```
as68 -l -u basic.s
as68 -l -u blibf.s
as68 -l -u data.s
as68 -l -u editor.s
as68 -l -u header.s
```

`as68` is the Motorola 68000 assembler. Each `.S` source file is assembled into a `.O` relocatable object file. The `-l` flag generates a listing, `-u` treats undefined symbols as external references.

### Step 2: Linking

```
link68 [u,s,l] basic.68k = header.o,basic.o,blibf.o,editor.o,data.o
```

`link68` combines the five object files into a single `basic.68k` executable. The link order matters: **HEADER.O must be first** because it contains the program entry point (the first instructions executed). The `[u,s,l]` flags control undefined symbol handling, symbol table output, and listing.

### Step 3: Relocation

```
relmod basic.68k basic.prg
```

`relmod` converts the linked `basic.68k` file into a relocatable Atari ST `.PRG` executable. This adds the TOS program header and relocation table, allowing the program to be loaded at any memory address.

### Step 4: Cleanup and Run

```
rm basic.68k
basic
```

The intermediate `.68k` file is deleted, and the resulting `basic.prg` is executed.

### Module Dependencies

```
HEADER.S exports: edibase, initcode, editcode, runcode, la_variablen, bsc_font
HEADER.S imports: b_init, b_runcode, b_preup, b_predown, b_up, b_down, ipka_,
                  ed_editor, ed_clrmem, editscreen, prgbase, prgend, varbase,
                  varend, strbase, strend

BASIC_COMMENTS.S exports:  b_init, b_enter, b_runcode, chk_stop, ed_chkstop,
                  b_up, b_down, b_preup, b_predown, charget6, error,
                  typflag, typ2flag, typ3flag, str_ptr, work1
BASIC_COMMENTS.S imports:  edibase, editscreen, la_variablen, bsc_font (from HEADER.S)
                  All BLIBF routines, All EDITOR routines, All DATA globals

BLIBF.S exports:  All math routines (radd_, rsub_, rmul_, rdiv_, etc.),
                  conversion routines (rlda_, rpka_, ipka_, ltor_, rpkl),
                  comparison (facscmp, rcmp_), constants (zero_, one_, pi_),
                  working storage (fac1, fac2, fl1work, iout)
BLIBF.S imports:  typflag, typ2flag, typ3flag, str_ptr, work1, error, charget6

EDITOR.S exports: ed_editor, ed_clrmem, ed_display, ed_edit, ed_getkey,
                  ed_curon, ed_curoff, ed_newline, ed_clr, ed_clrhome,
                  ed_backspace, ed_insert, ed_delete, ed_tab, ed_store,
                  ed_runter, ed_hoch, ed_links, ed_rechts, ed_prline,
                  ed_print, ed_pos, ed_x, ed_y, ed_xoffs, edi_yshft,
                  ed_scrline, ed_nlfl, ed_mode, ed_clrline, ed_delask
EDITOR.S imports: edibase, editscreen, b_enter, ed_chkstop

DATA.S exports:   editscreen, prgbase, prgend, varbase, varend, strbase, strend
DATA.S imports:   (none -- pure data definitions)
```

---

## 16. Notable 68000 Idiom

### The BEQ Float/Int Dispatch Convention

The arithmetic operator routines (Add, Sub, Mul, Div, Exponent) use an elegant convention that exploits the 68000's condition code persistence across subroutine dispatch. `exec_operation` sets the Z flag from `cmp.w #FLOAT,typ2flag` **before** calling the operator via the jump table. The operator's first instruction is:

```
Add:    beq  radd_     ; Z set = FLOAT -> delegate to float library
        add.l d4,d0    ; Z clear = INT -> integer add
```

This avoids each operator having to re-check the type. A single branch instruction at the top of each routine dispatches to the appropriate path, costing zero overhead for the common integer case. The trick works because the 68000's JSR instruction (used by `exec_operation` to call the operator) does **not** modify the condition codes -- the Z flag from the `cmp.w` survives across the jump table dispatch into the operator routine. This is a deliberate design choice in the 68000 architecture: only arithmetic/logic instructions modify CCR, not control flow instructions. The result is that type dispatch is "free" -- the caller sets the flag, the callee branches on it, with no redundant type check.
