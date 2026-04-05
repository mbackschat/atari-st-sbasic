# BASIC Program Examples

Decoded from tokenized binary `.BAS` / `FBAS.TXT` files using the token table from the interpreter source.

**Note on decoding:** These files store programs in tokenized binary format (with "HEAD" magic header). Keywords like PRINT, FOR, VDI are stored as 2-byte tokens. The tokenizer also converts keywords found inside REM comments, so some comments have tokenization artifacts in the raw binary (e.g., "polyline" becomes "poly" + LINE token). The listings below show the reconstructed intended source.

---

## Example 1: VDI Graphics Demo (00527-FBAS.TXT)

### Full Listing

```basic
10  AES 10,0,1,0,0:REM appl_init
20  AES 77,0,5,0,0:REM graf_handle
30  handle = AESINTOUT(0)
40  FOR x = 0 TO 9:VDIINTIN x,1:NEXT:VDIINTIN x,2
50  VDI 100,0,,11, , ,handle:REM open v_wrk
60  VDI 3,  0,,0 , , ,handle:REM clear v_wrk
70  VDIINTIN 0,1:VDI 17, 0,,1 , , ,handle:REM polyline farbe
80  VDIPTSIN 0,1, 1,1, 2,638, 3,1, 4,638, 5,398, 6,1, 7,398, 8,1, 9,1
90  VDI 6,  5,,0 , , ,handle:REM polyline
100  END
```

### Line-by-Line Explanation

**Line 10: `AES 10,0,1,0,0` -- Initialize the AES application**

Calls AES function **appl_init** (opcode 10). The AES control array is set to:
- `control[0]` = 10 (appl_init)
- `control[1]` = 0 (no integer inputs)
- `control[2]` = 1 (one integer output: the application ID)
- `control[3]` = 0 (no address inputs)
- `control[4]` = 0 (no address outputs)

This registers the program with the GEM Application Environment Services. The application ID is returned in `AESINTOUT(0)` but is not used here.

**Line 20: `AES 77,0,5,0,0` -- Get the VDI workstation handle**

Calls AES function **graf_handle** (opcode 77). This returns the handle of the physical VDI workstation (the screen) along with character cell dimensions:
- `AESINTOUT(0)` = VDI workstation handle
- `AESINTOUT(1)` = character width in pixels
- `AESINTOUT(2)` = character height in pixels
- `AESINTOUT(3)` = character cell width (including spacing)
- `AESINTOUT(4)` = character cell height (including spacing)

**Line 30: `handle = AESINTOUT(0)` -- Store the VDI handle**

Reads the VDI workstation handle from the AES output array and stores it in the variable `handle`. This handle is needed for all subsequent VDI calls.

**Line 40: `FOR x = 0 TO 9:VDIINTIN x,1:NEXT:VDIINTIN x,2` -- Set up work_in parameters**

Prepares the `work_in` array for opening a virtual VDI workstation. The VDI function `v_opnvwk` (opcode 100) expects 11 integer input values:
- `VDIINTIN(0)` through `VDIINTIN(9)` are set to 1 (default device parameters: device ID, line type, line color, marker type, marker color, text font, text color, fill interior, fill color, fill perimeter)
- `VDIINTIN(10)` is set to 2 (RC coordinate mode: coordinates are in raster/pixel units)

The loop sets indices 0-9 to 1, then index 10 (which is the loop variable `x` after the loop ends at 10) to 2.

**Line 50: `VDI 100,0,,11, , ,handle` -- Open a virtual VDI workstation**

Calls VDI function **v_opnvwk** (opcode 100). The VDI control array is:
- `contrl[0]` = 100 (v_opnvwk)
- `contrl[1]` = 0 (no coordinate input points)
- `contrl[3]` = 11 (11 integer inputs from VDIINTIN)
- `contrl[6]` = handle (physical workstation handle)

After this call, the program has a virtual VDI workstation open on the screen. The returned handle (potentially updated in `contrl[6]`) is used for all drawing.

**Line 60: `VDI 3,  0,,0 , , ,handle` -- Clear the workstation**

Calls VDI function **v_clrwk** (opcode 3) which clears the entire workstation (fills with background color). No inputs or outputs beyond the handle.

**Line 70: `VDIINTIN 0,1:VDI 17, 0,,1 , , ,handle` -- Set polyline color**

First sets `VDIINTIN(0) = 1` (color index 1 = black in monochrome, or first non-background color). Then calls VDI function **vsl_color** (opcode 17) to set the polyline drawing color:
- `contrl[0]` = 17 (vsl_color)
- `contrl[3]` = 1 (one integer input: the color index)

**Line 80: `VDIPTSIN 0,1, 1,1, 2,638, 3,1, 4,638, 5,398, 6,1, 7,398, 8,1, 9,1` -- Define rectangle coordinates**

Loads 5 coordinate pairs into the VDI point input array, defining a closed rectangle (the screen border):

| Index | Value | Meaning |
|-------|-------|---------|
| 0, 1 | 1, 1 | Point 1: top-left (1,1) |
| 2, 3 | 638, 1 | Point 2: top-right (638,1) |
| 4, 5 | 638, 398 | Point 3: bottom-right (638,398) |
| 6, 7 | 1, 398 | Point 4: bottom-left (1,398) |
| 8, 9 | 1, 1 | Point 5: back to top-left (closes the rectangle) |

This defines a rectangle that is essentially the full screen border on a 640x400 monochrome display (with 1-pixel margin).

**Line 90: `VDI 6,  5,,0 , , ,handle` -- Draw the polyline**

Calls VDI function **v_pline** (opcode 6) to draw the polyline through all 5 points:
- `contrl[0]` = 6 (v_pline)
- `contrl[1]` = 5 (5 coordinate pairs from VDIPTSIN)
- `contrl[3]` = 0 (no integer inputs needed)

This draws the rectangular border on the screen using the color set in line 70.

**Line 100: `END` -- Terminate the program**

### What This Program Does

This is a **minimal GEM VDI graphics demo** that:
1. Registers as a GEM application (appl_init)
2. Gets the physical workstation handle (graf_handle)
3. Opens a virtual VDI workstation with default settings
4. Clears the screen
5. Sets the drawing color to black
6. Draws a rectangle border around the full 640x400 screen
7. Ends

It demonstrates the essential pattern for any GEM graphics program: **AES init -> get handle -> open workstation -> draw -> end**.

### Key Concepts

- **AES before VDI:** You must call `appl_init` and `graf_handle` before making VDI calls.
- **v_opnvwk work_in:** The 11 integer parameters configure the workstation defaults.
- **Coordinate system:** Points 1-638 horizontally, 1-398 vertically (640x400 monochrome).
- **Closed polyline:** To draw a closed shape, the last point must equal the first point.

---

## Example 2: Scrolling Text Animation (00540-FBAS.TXT)

### Full Listing

```basic
2   TROFF
5   CLS
10  t$="videoman the best copies of the world!"
20  FOR z%=1 TO LEN(t$):a$=MID$(t$,z%,1)
30  FOR t%=40 TO z% STEP -1:CURSOR 6,2:PRINT TAB(t%);a$;" ":NEXT:NEXT
40  END
100 b$=INKEY$:GOSUB 200:RETURN
200 CLS:DUMP:RETURN
```

### Line-by-Line Explanation

**Line 2: `TROFF` -- Disable trace mode**

Turns off any active TRON trace debugging. This ensures the program runs at full speed without trace output.

**Line 5: `CLS` -- Clear the screen**

Clears the editor screen, providing a blank canvas for the animation.

**Line 10: `t$="videoman the best copies of the world!"` -- Define the message string**

Stores the text to be animated in string variable `t$`. This is a 39-character message that will be displayed with a scrolling animation effect.

**Line 20: `FOR z%=1 TO LEN(t$):a$=MID$(t$,z%,1)` -- Outer loop: iterate over each character**

The outer loop iterates through each character of the string:
- `z%` goes from 1 to 39 (the length of `t$`)
- `a$` is extracted as the single character at position `z%` using `MID$`
- The `%` suffix on `z%` forces it to be an integer variable (faster than float)

**Line 30: `FOR t%=40 TO z% STEP -1:CURSOR 6,2:PRINT TAB(t%);a$;" ":NEXT:NEXT` -- Inner loop: animate each character sliding in**

This is the animation engine, packed into a single line with two nested loops:

1. **`FOR t%=40 TO z% STEP -1`** -- The inner loop moves the character from column 40 (right side) to its final position `z%` (where it belongs in the string), stepping backwards by 1 column each iteration. This creates a **slide-in-from-right** effect.

2. **`CURSOR 6,2`** -- Positions the cursor at column 6, row 2. This sets the vertical position for the text output (row 2 = near the top of the screen).

3. **`PRINT TAB(t%);a$;" "`** -- Prints the character at the current horizontal position:
   - `TAB(t%)` moves to column `t%` (which decreases each iteration, moving left)
   - `a$` is the current character being animated
   - `" "` (space) erases the character's previous position (one column to the right)

4. **`NEXT:NEXT`** -- Closes both the inner loop (`t%`) and the outer loop (`z%`).

**The animation effect:** Each character appears at column 40 and slides leftward to its final resting position. The first character slides to column 1, the second to column 2, etc. The trailing space erases the ghost of the previous position. The result is a typewriter-like effect where each letter flies in from the right.

**Line 40: `END` -- Terminate the program**

Normal program execution ends here. Lines 100 and 200 are subroutines that are only called if explicitly invoked.

**Lines 100-200: Utility subroutines (not called by main program)**

```basic
100 b$=INKEY$:GOSUB 200:RETURN
200 CLS:DUMP:RETURN
```

These are debugging utility subroutines:
- **Line 100:** Reads a keypress into `b$` (waits for no key, just checks), then calls the subroutine at line 200, then returns.
- **Line 200:** Clears the screen and dumps all variables (DUMP shows all defined variables with their current values), then returns.

These could be called during development by inserting `GOSUB 100` at any point in the program to inspect the program state. They are not called during the normal animation run.

### What This Program Does

This is a **character-by-character scrolling text animation**:
1. Clears the screen
2. For each character in the message string:
   - Animates it sliding from column 40 to its target position
   - The slide happens by repeatedly printing the character at decreasing column positions
3. The result: the message "videoman the best copies of the world!" appears letter by letter, with each letter flying in from the right side of the screen

### Key Concepts

- **Nested FOR loops for animation:** The outer loop selects characters, the inner loop handles the sliding motion.
- **CURSOR for positioning:** Sets the output row (useful for placing text at specific screen locations).
- **TAB() for horizontal position:** Controls where each character is printed within the PRINT statement.
- **Trailing space for erasure:** `" "` after the character erases the previous frame of the animation.
- **STEP -1:** Counts backwards (right-to-left motion).
- **Integer variables (`z%`, `t%`):** Using `%` suffix for loop counters is faster than the default float type.
- **Unused subroutines:** Lines 100-200 are debugging aids left in the program, demonstrating GOSUB/RETURN and DUMP for variable inspection.

### Animation Visualization

```
Frame 1:  character 'v' slides from col 40 to col 1
          Col: 40  39  38  ...  2   1
               v   v   v  ...  v   v      <- 'v' arrives at position 1

Frame 2:  character 'i' slides from col 40 to col 2
          Col: 40  39  38  ...  3   2
               i   i   i  ...  i   i      <- 'i' arrives at position 2
          Screen now shows: "vi"

Frame 3:  character 'd' slides from col 40 to col 3
          ...
          Screen now shows: "vid"

... continues until all 39 characters have arrived ...

Final:    "videoman the best copies of the world!"
```


## Example 3: Variable Scoping with LOCAL (00511.BAS)

### Full Listing

```basic
5   a=10:b=20:c=30
10  PROC show("Hallo")
20  PROC show("-----")
30  END
100 DEF PROC show(s$)
105 LOCAL a,b,c
106 a=1:b=2:c=3
110 PRINT TAB(60-LEN(s$));s$
115 PRINT a,b,c
120 ENDPROC
```

### Explanation

This is a companion to the array-based scoping demo (00529-CONVERT.TXT, documented in BASIC-MANUAL.md Section 20). Here the same concept is demonstrated with **simple scalar variables** instead of arrays.

**Line 5:** Sets three global float variables: `a=10`, `b=20`, `c=30`.

**Lines 10-20:** Calls the `show` procedure twice with different string arguments.

**Line 100: `DEF PROC show(s$)`** -- Defines a procedure accepting one string parameter.

**Line 105: `LOCAL a,b,c`** -- Declares three local float variables that **shadow** the global `a`, `b`, `c`. The local variables are initialized to 0.0.

**Line 106: `a=1:b=2:c=3`** -- Assigns values to the **local** copies. The global variables remain unchanged at 10, 20, 30.

**Line 110:** Prints the string right-aligned at column 60 (same technique as the array demo).

**Line 115: `PRINT a,b,c`** -- Prints the **local** values (1, 2, 3), not the globals.

### Expected Output

```
                                                       Hallo
 1             2             3
                                                       -----
 1             2             3
```

### Key Differences from 00529-CONVERT.TXT (Array Demo)

| Feature | 00511 (this program) | 00529/00513 (array demo) |
|---------|---------------------|--------------------------|
| Variable type | Simple scalars (`a`, `b`, `c`) | Array elements (`a(0)`, `a(1)`, `a(2)`) |
| Local declaration | `LOCAL a,b,c` | `LOCAL DIM a(10)` |
| Global access | Not shown | Uses `a#(0)` with `#` prefix |
| Local initialization | Explicit (`a=1:b=2:c=3`) | Default (0, with assignment commented out) |

**Note:** 00513-BAS.TXT is the same program as 00529-CONVERT.TXT (the Section 20 demo in BASIC-MANUAL.md), stored in tokenized binary format rather than ASCII.

---

## Example 4: Scrolling Text with Trace (00535.BAS)

### Full Listing

```basic
2   TRON:ON TRACE GOSUB 100
5   CLS
10  t$="videoman the best copies of the world!"
20  FOR z%=1 TO LEN(t$):a$=MID$(t$,z%,1)
30  FOR t%=39 TO z%-1 STEP -1:CURSOR 6,2:PRINT TAB(t%);a$;" ":NEXT:NEXT
40  END
100 b$=INKEY$:GOSUB 200:RETURN
200 CLS:DUMP:RETURN
```

### Explanation

This is a **debug-instrumented variant** of the scrolling text animation (00540-FBAS.TXT, documented as Example 2). The core animation logic (lines 5-40) is nearly identical, but this version adds **trace debugging**.

**Line 2: `TRON:ON TRACE GOSUB 100`** -- The key addition. This enables trace mode (`TRON`) and registers a trace handler at line 100. With this active, **before every statement**, the interpreter:
1. Displays the current line number and statement text at the top of the screen
2. Calls `GOSUB 100` (the trace handler)
3. Waits for the trace handler to RETURN before continuing

**Line 30:** The inner loop counts from 39 (not 40 as in 00540), a minor variation.

**Line 100: `b$=INKEY$:GOSUB 200:RETURN`** -- The trace handler. On each trace step, it reads any pending keypress into `b$`, then calls the diagnostic subroutine at line 200 before returning to the traced program.

**Line 200: `CLS:DUMP:RETURN`** -- The diagnostic subroutine. Clears the screen and displays all variable values using `DUMP`, then returns. This provides a snapshot of program state at every single statement execution.

### Key Concepts

- **ON TRACE GOSUB:** Registers a custom subroutine that is called at every statement during TRON tracing. This allows programmatic inspection of execution state.
- **DUMP for inspection:** Shows all variables and their current values, enabling step-by-step debugging.
- **INKEY$ in trace handler:** Allows the programmer to observe the trace output without blocking; pressing a key could be used to trigger special behavior.
- **Relationship to 00540:** Same animation algorithm, but wrapped in debug instrumentation -- demonstrates how to add tracing to an existing program.

---

## Example 5: String Performance Benchmark (00523.BAS)

### Full Listing

```basic
0   INPUT "wieviel dims? >"; b
10  DIM a$(b)
15  ti=0
20  FOR a=0 TO b:a$(a)="12345678901234567890:"+STR$(a)+"":NEXT
25  PRINT "Zeit für Zuweisung: "; ti/70.0; " Sekunden"
30  ti=0
40  PRINT FRE(0)
50  PRINT "Zeit für fre(0): "; ti/70.0; " Sekunden"
```

*Note: German prompts. "wieviel dims?" = "how many dimensions?", "Zeit für Zuweisung" = "time for assignment", "Zeit für fre(0)" = "time for fre(0)".*

### Explanation

A **performance benchmark** that measures string assignment speed and garbage collection overhead.

**Line 0: `INPUT "wieviel dims? >"; b`** -- Asks the user how many array elements to create. Note the unusual line number 0, which is valid (line numbers are stored as 32-bit integers).

**Line 10: `DIM a$(b)`** -- Dynamically dimensions a string array with `b+1` elements (indices 0 to `b`). The size is determined at runtime from user input.

**Line 15: `ti=0`** -- Resets the VBL frame counter to zero. The system variable `ti` reads/writes the `_frclock` counter at address $466, which increments at ~70 Hz (monochrome) or ~50 Hz (PAL color).

**Line 20:** Fills the array in a loop. Each element gets a 20-character string concatenated with the string representation of the index. The `+""` at the end is a no-op concatenation (possibly leftover from editing). The string operations exercise:
- String concatenation (`+`)
- STR$ conversion (number to string)
- String heap allocation (each assignment allocates new string space)

**Line 25:** Calculates elapsed time by dividing `ti` by 70.0 (converting VBL frames to seconds at monochrome refresh rate). Displays: "Time for assignment: X seconds".

**Lines 30-50:** Resets the timer, then calls `FRE(0)`. `FRE(0)` triggers **garbage collection** -- it scans the string heap, marks all valid strings, and compacts them by eliminating dead strings. The time to complete this is then displayed.

### Key Concepts

- **Dynamic DIM:** Array size determined at runtime from a variable.
- **`ti` for benchmarking:** Writing `ti=0` resets the counter; reading `ti` later gives elapsed VBL frames. Dividing by 70.0 converts to seconds (monochrome).
- **String heap pressure:** Creating many strings fills the heap; old copies accumulate as "dead" strings.
- **FRE(0) vs FRE(1):** `FRE(0)` runs garbage collection first (slow but accurate); `FRE(1)` returns free space without GC (fast but may include reclaimable dead space).
- **Line number 0:** Demonstrates that line number 0 is valid in this interpreter.

---

## Example 6: Memory Block Copy with PEEK/POKE (00542.BAS)

### Full Listing

```basic
10  DIM a(50),b(50)
20  bmove(VARPTR(a(0)),VARPTR(b(0)),5)
30  REM
40  REM
50  DEF PROC bmove(adr1,adr2,anz%)
60  FOR i% = 0 TO anz%
70  POKE adr2+i%,PEEK(adr1+i%)
80  NEXT
90  ENDPROC
```

### Explanation

Demonstrates a **memory block copy routine** implemented as a reusable procedure using low-level PEEK/POKE operations.

**Line 10: `DIM a(50),b(50)`** -- Creates two float arrays, each with 51 elements (indices 0-50). Each float element occupies 12 bytes of memory (BCD format), so each array consumes 612 bytes.

**Line 20: `bmove(VARPTR(a(0)),VARPTR(b(0)),5)`** -- Calls the `bmove` procedure, passing:
- `VARPTR(a(0))` -- the memory address of the first element of array `a`
- `VARPTR(b(0))` -- the memory address of the first element of array `b`
- `5` -- the number of bytes to copy

This copies 6 bytes (indices 0-5) from `a`'s memory to `b`'s memory. Note that 5 bytes is less than one full BCD float (12 bytes), so this only partially copies the first element. To copy a complete float element, `anz%` would need to be 11 (for 12 bytes, indices 0-11).

**Lines 30-40:** Empty REM lines (spacers separating the main program from the procedure definition).

**Line 50: `DEF PROC bmove(adr1,adr2,anz%)`** -- Defines the copy procedure with three parameters:
- `adr1` -- source memory address (float, to hold a 32-bit address)
- `adr2` -- destination memory address
- `anz%` -- number of bytes to copy (integer, used as loop limit)

**Lines 60-80:** The copy loop. For each byte index from 0 to `anz%`:
- `PEEK(adr1+i%)` reads one byte from the source address
- `POKE adr2+i%,value` writes that byte to the destination address

This is a byte-by-byte copy, similar to the C `memcpy` function or the Atari ST's native `Blitmode`/block copy routines.

### Key Concepts

- **VARPTR for address passing:** `VARPTR(a(0))` returns the actual memory address where array element `a(0)` is stored. This allows direct memory manipulation of array data.
- **PEEK/POKE for memory access:** The fundamental byte-level memory read/write operations. Together with VARPTR, they enable low-level data manipulation that bypasses BASIC's type system.
- **Procedure as utility:** The `bmove` procedure encapsulates a reusable memory operation, demonstrating how DEF PROC can be used to build a library of helper routines.
- **Address arithmetic:** `adr1+i%` demonstrates that memory addresses are just numbers that can be manipulated with normal arithmetic.
- **Naming convention:** "bmove" alludes to the 68000 block move instruction and the TOS `Blitmode` routines. A more complete version would use WPEEK/WPOKE (16-bit) or LPEEK/LPOKE (32-bit) for faster word-aligned copies.

---

## Decoding Notes

These programs were stored in tokenized binary format. The decoder script (`tmp/decode_basic.py`) processes the binary file format:

1. Skip the 4-byte "HEAD" magic header
2. Walk the linked list: each line = `[4-byte next_ptr][4-byte line_number][tokenized data...]`
3. In the tokenized data, 2-byte sequences `$01 xx`, `$02 xx`, `$03 xx` are token codes that map to BASIC keywords via the `tokenstr` table
4. All other bytes are literal characters (variable names, operators, numbers, string contents)

**Tokenization quirk:** The tokenizer processes keywords even inside REM comments. For example, the word "polyline" in a REM comment gets "line" tokenized, and "open" becomes the OPEN token. When detokenized (by LIST or this decoder), the original comment text is reconstructed from the tokens, but it appears in uppercase where keywords were found.
