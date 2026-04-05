# Atari ST BASIC Interpreter -- User Manual

*Reverse-engineered from the 68000 assembly source code (dated 31.10.88)*

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [The Editor](#2-the-editor)
3. [Program Management](#3-program-management)
4. [Data Types and Variables](#4-data-types-and-variables)
5. [Arrays](#5-arrays)
6. [Operators](#6-operators)
7. [Control Flow](#7-control-flow)
8. [Procedures and Functions](#8-procedures-and-functions)
9. [String Functions](#9-string-functions)
10. [Math Functions](#10-math-functions)
11. [Input/Output](#11-inputoutput)
12. [File I/O](#12-file-io)
13. [DATA/READ/RESTORE](#13-datareadrestore)
14. [Memory and System Access](#14-memory-and-system-access)
15. [GEMDOS/BIOS/XBIOS](#15-gemdosbiosxbios)
16. [AES/VDI Access](#16-aesvdi-access)
17. [Graphics](#17-graphics)
18. [Debugging](#18-debugging)
19. [Error Messages](#19-error-messages)
20. [Quick Reference](#20-quick-reference)
21. [Cheat Sheet](#21-cheat-sheet)

---

## 1. Getting Started

### Loading and Running the Interpreter

This BASIC interpreter runs on the Atari ST family of computers. It is designed to operate within a host environment (STAD) that provides the screen drawing routines, font rendering, and keyboard input. When launched, the interpreter initializes its internal state, clears all variables, and enters the editor loop.

### Editor Mode vs. Direct Mode

The interpreter operates in two primary modes:

- **Editor mode**: The full-screen editor is active. You can type program lines, navigate with arrow keys, and edit text freely. Pressing RETURN sends the current line to the interpreter for processing.

- **Direct mode**: When you press RETURN on a line in the editor, the interpreter processes it immediately. If the line begins with a line number, it is stored as part of the program listing. If it does not begin with a line number, it is executed immediately as a direct command.

- **Program mode**: When a program is running (after RUN), the interpreter executes stored program lines sequentially. The internal flag `b_modus` is set to -1 during program execution and 0 during direct mode.

### The "ready." Prompt

After initialization, and after every direct command completes, the interpreter prints:

```
ready.
```

This indicates the interpreter is ready to accept input. The prompt is suppressed when AUTO line numbering is active.

### Exiting

Type `!` (exclamation mark) on a blank line and press RETURN to exit the interpreter. Pressing ESC in the editor also exits back to the host environment.

### Keyword Abbreviations

Most BASIC keywords can be abbreviated to save typing. Each keyword has a **minimum form** -- the shortest prefix the tokenizer will accept. When you press RETURN, abbreviated keywords are automatically expanded to their full form in the stored program.

**How it works:** You can type any keyword using only its minimum prefix. The tokenizer matches the shortest unambiguous form. Keywords are case-insensitive (you can type in upper or lower case).

**Examples:**

| You type | Recognized as | Minimum form |
|----------|---------------|--------------|
| `pr` | PRINT | `print` (no abbreviation -- full word required) |
| `di` | DIM | `di` |
| `li` | LIST | `li` |
| `go` | GOTO | `go` |
| `gos` | GOSUB | `gos` |
| `in` | INPUT | `in` |
| `ru` | RUN | `ru` |
| `lo` | LOAD | `lo` |
| `sa` | SAVE | `sa` |
| `ne` | NEXT | `ne` |
| `re` | REM | `re` |
| `rea` | READ | `rea` |
| `res` | RESTORE | `res` |
| `ret` | RETURN | `ret` |
| `fo` | FOR | `fo` |
| `st` | STEP | `st` |
| `sto` | STOP | `sto` |
| `co` | CONT | `co` |
| `cl` | CLOSE | `cl` |
| `de` | DEF | `de` |
| `del` | DELETE | `del` |

Some keywords must be typed in full because they are too short or have no abbreviation point: `print`, `clr`, `to`, `if`, `fn`, `on`, `pos`, `cos`, `log`, `ln`, `cls`, `dir`, `end`, `or`.

The special shortcut `?` can be used for PRINT, and `'` (apostrophe) for REM.

A complete abbreviation table for all 113 keywords is provided in the [Quick Reference](#21-quick-reference).

---

## 2. The Editor

The interpreter includes a full-screen character-based editor that maintains an internal character buffer (typically 25 rows by 80 columns). Characters are rendered to the screen via a callback provided by the host environment.

### Navigation Keys

| Key | Action |
|-----|--------|
| Left Arrow | Move cursor one position left. If at column 0, no movement. |
| Right Arrow | Move cursor one position right. If at the end of the visible area, the display scrolls horizontally. |
| Up Arrow | Move cursor up one row. If at the top of the screen, the display scrolls up to show previous lines. |
| Down Arrow | Move cursor down one row. If at the bottom of the screen, the display scrolls down. |

### Editing Keys

| Key | Action |
|-----|--------|
| Insert | Insert a space at the cursor position, shifting all characters to the right. The rightmost character on the line is lost. |
| Delete | Delete the character at the cursor position, shifting all characters to the left. A space fills the vacated position at the end of the line. |
| Backspace | Move the cursor one position to the left (same as Left Arrow). Note: this does NOT delete the character -- it only repositions the cursor. |
| Tab | Jump to the next tab stop position. Tab stops are set at regular intervals (configured by the host environment via `edi_tab`). If the next tab stop is beyond the end of the line, the cursor wraps to the next line. |

### Screen Control Keys

| Key | Action |
|-----|--------|
| CLR/HOME | Move cursor to the home position (row 0, column 0). Resets horizontal scrolling. |
| SHIFT + CLR/HOME | Clear the entire screen. Fills the screen buffer with spaces, resets the cursor to home, and redraws. |
| CTRL + Delete | Clear the entire current line. Fills it with spaces and resets the cursor column to 0. |

### Command Keys

| Key | Action |
|-----|--------|
| RETURN | Send the current line to the BASIC interpreter for processing. If the line starts with a number, it is stored as a program line. Otherwise, it is executed immediately. |
| ESC | Exit the editor and return to the host environment. |
| ALT + UNDO | Stop a running program. This is checked during program execution and scrolling. The interpreter will halt with a "prg stopped" error. |

### Scrolling Behavior

When scrolling (either via arrow keys or during program output), the editor checks for modifier keys:

- **CTRL held**: Pauses scrolling until CTRL is released.
- **SHIFT held**: Slows scrolling by introducing a delay between each scroll step.

The scroll routines also call `ed_chkstop` to check for ALT+UNDO, allowing the user to interrupt a running program during output.

---

## 3. Program Management

### Line Numbers

Program lines must begin with a positive integer line number. Lines are stored in ascending order by line number. Entering a line with an existing line number replaces that line. Entering just a line number with no content deletes that line.

```
10 PRINT "Hello"
20 GOTO 10
```

Line numbers are stored internally as 32-bit integers, allowing a very large range.

### NEW

```
NEW
```

Erases the entire program from memory and clears all variables. This is a direct-mode-only command.

### CLR

```
CLR
CLR var1, var2, ...
```

Without arguments, CLR clears all variables, resets FOR/NEXT stacks, GOSUB stacks, IF tables, and procedure tables, while preserving the program listing. It also rescans the program for procedure definitions.

With arguments, CLR sets specific numeric variables to zero (integer variables to 0, float variables to 0.0). String variables cannot be individually cleared this way.

### RUN

```
RUN
RUN line_number
```

Starts program execution. Without an argument, execution begins at the first line. With a line number, execution begins at that specific line. RUN always performs a CLR first (clearing all variables), restores the DATA pointer, and scans for procedure definitions before starting execution.

### CONT

```
CONT
```

Continues execution after a STOP statement or after an ALT+UNDO break. CONT is only available if the program was stopped in a resumable state. It is a direct-mode-only command. If the program has been modified since it was stopped, CONT will fail with "can't continue."

### STOP

```
STOP
```

Halts program execution and returns to direct mode. The program state is preserved so that CONT can resume execution.

### END

```
END
```

Terminates program execution and returns to direct mode. Functionally equivalent to reaching the end of the program listing.

### LIST

```
LIST
LIST start
LIST start, end
LIST , end
```

Displays the program listing. Without arguments, the entire program is listed. With one argument, only that line is listed. With two arguments, lines from `start` to `end` (inclusive) are listed. With a comma and end number only (`,end`), lines from the beginning up to `end` are listed.

During listing, keywords are displayed in uppercase.

### DELETE

```
DELETE
DELETE start
DELETE start, end
DELETE , end
```

Deletes program lines. The argument syntax is the same as LIST. DELETE also performs a CLR (clearing all variables). This is a direct-mode-only command.

### SAVE

```
SAVE "filename"
SAVE "filename", start, end
```

Saves the program to disk in a proprietary binary format. The file begins with a 4-byte header ("HEAD"). With optional `start` and `end` parameters, only lines within that range are saved. During saving, the message "saving..." is displayed.

### LOAD

```
LOAD "filename"
```

Loads a program from disk (in the proprietary binary format created by SAVE). The current program is erased first. During loading, the message "loading..." is displayed. If executed from within a running program, execution continues from the first line of the newly loaded program.

The file must begin with the "HEAD" header; otherwise, a "no BASIC file format" error occurs.

### MERGE

```
MERGE "filename"
```

Merges a saved program file into the current program. Existing lines with the same line numbers are replaced. Lines in the file with new line numbers are inserted. The file must be in the proprietary binary format. During merging, "merging..." is displayed. All variables are cleared during the merge.

### CONVERT

```
CONVERT "filename"
```

Imports an ASCII text file containing BASIC source code. Each line of the text file must begin with a line number followed by BASIC statements, just as you would type them at the keyboard. The file is read line by line; each line is tokenized and inserted into the program listing. Lines without line numbers trigger a "line numbers missing" error. Tabs in the source file are converted to spaces. The message "converting..." is displayed during import.

### AUTO

```
AUTO
AUTO start
AUTO start, increment
```

Enables automatic line numbering. After each RETURN, the next line number is automatically displayed. The default start is 100, and the default increment is 10. Entering an empty line or modifying/deleting a program line turns AUTO off. This is a direct-mode-only command.

---

## 4. Data Types and Variables

### Data Types

The interpreter supports three data types:

| Type | Suffix | Description |
|------|--------|-------------|
| Float | `!` (or no suffix) | BCD floating-point number with approximately 22 digits of precision. This is the default type for variables without a suffix. Stored internally as 12 bytes (three 32-bit words). |
| Integer | `%` | 32-bit signed integer. Range: -2,147,483,648 to 2,147,483,647. Stored as 4 bytes. |
| String | `$` | Character string. Strings are stored in a heap that grows downward from the top of available memory. Maximum length is limited only by available string space. |

Type conversion between float and integer is automatic when required by context. Assigning a float value to an integer variable truncates the fractional part. String types cannot be automatically converted to or from numeric types (use VAL and STR$ instead).

### Variable Names

Variable names begin with a letter (a-z or A-Z) or underscore, followed by any combination of letters, digits, and underscores. The type suffix ($, %, or !) follows the name. Variable names are case-sensitive.

```
x = 3.14          REM Float variable (default)
x! = 3.14         REM Float variable (explicit)
count% = 42       REM Integer variable
name$ = "Atari"   REM String variable
```

### System Variables

The interpreter provides three built-in system variables:

| Variable | Type | Description |
|----------|------|-------------|
| `pi` | Float | The constant pi (3.14159265358979...). Read-only. |
| `ti` | Integer | System timer counter. Reads the VBL frame counter at address $466 (`_frclock`), which increments at approximately 70 Hz (tied to the vertical blank interrupt). Readable and writable. To convert to seconds, divide by 70. |
| `ti$` | String | Current time as a string in `HH:MM:SS` format (e.g., `"14:30:25"` for 2:30:25 PM). Readable and writable. When written, the string is parsed as hours, minutes, seconds with `:` separators (e.g., `ti$ = "09:15:00"`). Internally, `ti$` converts to/from `ti` using a divisor of 70. |

Attempting to assign a value to `pi` or to use system variables improperly will raise an "improper use of system variable" error.

### The # Operator for Global Access

Inside a procedure, variables are looked up in local scope first. To force access to a global variable, insert `#` between the variable name and its type suffix: `x#%`, `a#(0)`, `name#$`. See Section 8 for full details and examples.

### Numeric Literals

| Format | Example | Description |
|--------|---------|-------------|
| Decimal | `42`, `3.14`, `-7` | Standard decimal notation. |
| Hexadecimal | `$FF`, `$1A2B` | Prefixed with `$`. Up to 8 hex digits (32-bit). |
| Binary | `%10110`, `%11111111` | Prefixed with `%`. Up to 32 binary digits. |

### String Literals

String literals are enclosed in double quotes:

```
"Hello, World!"
```

---

## 5. Arrays

### DIM Statement

```
DIM variable(size)
DIM variable(size1, size2, ...)
DIM a%(10), b$(5,5), c!(3,3,3)
```

Declares an array with explicit dimensions. Arrays can have up to 10 dimensions. Each dimension is indexed from 0 to the specified size, so `DIM a(10)` creates 11 elements (indices 0 through 10).

Multiple arrays can be declared in a single DIM statement, separated by commas.

### Auto-Creation

If you access an array variable that has not been explicitly dimensioned, the interpreter automatically creates it as a one-dimensional array with 11 elements (indices 0 through 10). This is equivalent to `DIM variable(10)`.

### CREATE Statement

```
CREATE "filename"
```

CREATE is used as a file operation (see File I/O section). In the context of arrays, all array storage is handled through DIM.

### LOCAL DIM

Inside a procedure, you can declare local arrays:

```
100 DEF PROC test
110   LOCAL DIM a(20)
120   a(5) = 42
130 ENDPROC
```

A local DIM creates an array that is scoped to the procedure and does not affect any global array of the same name. If a local array with the same name and identical dimensions already exists, no error occurs. If the dimensions differ, a "re-define" error is raised.

### Errors

- Accessing an index outside the declared bounds raises "bad subscript."
- Declaring more than 10 dimensions raises "dim" error.
- Re-dimensioning an existing array (outside of LOCAL DIM in procedures) raises "re-define."
- Negative indices raise "no negative arg allowed."

---

## 6. Operators

The interpreter supports 13 levels of operator precedence. Higher numbers bind more tightly.

| Priority | Operator | Symbol | Description |
|----------|----------|--------|-------------|
| 1 | Shift Left | `{` | Bitwise shift left (integer). `a{b` shifts `a` left by `b` bits. |
| 2 | Shift Right | `}` | Bitwise shift right (integer). `a}b` shifts `a` right by `b` bits. |
| 3 | XOR / EOR | `~` or `EOR` | Bitwise exclusive OR (integer). |
| 4 | AND | `&` or `AND` | Bitwise AND (integer). |
| 5 | OR | `\|` or `OR` | Bitwise OR (integer). |
| 6 | Less Than | `<`, `<=`, `<>` | Comparison. Returns 1 (true) or 0 (false). `<>` means not equal. |
| 7 | Equal | `=` | Comparison. Returns 1 (true) or 0 (false). Also `=<` (same as `<=`) and `=>` (same as `>=`). |
| 8 | Greater Than | `>`, `>=` | Comparison. Returns 1 (true) or 0 (false). Also `><` means not equal. |
| 9 | Addition | `+` | Numeric addition or string concatenation. |
| 10 | Subtraction | `-` | Numeric subtraction. Also unary negation. |
| 11 | Multiplication | `*` | Numeric multiplication. |
| 12 | Division | `/` | Numeric division. Integer division that cannot produce an exact result is automatically promoted to float. |
| 13 | Exponentiation | `^` | Raises left operand to the power of right operand. Always computed via logarithms in float. |

### Logical Operators as Keywords

The keywords AND, OR, and EOR (exclusive or) can be used as alternatives to `&`, `|`, and `~` respectively. They perform bitwise operations on integer values. If the operands are floats, they are first converted to integers.

### Comparison Operators

Comparison operators work on integers, floats, and strings:

- For numeric types, standard numeric comparison is performed.
- For strings, a byte-by-byte comparison is performed.
- The result is always an integer: 1 for true, 0 for false. (In float context, the result is 1.0 or 0.0.)

Compound comparisons are supported: `<=`, `>=`, `<>`, `=<`, `=>`, `><`.

### Parentheses

Parentheses `()` override normal precedence rules. Expressions in parentheses are evaluated first.

### Operator Examples

```
10 REM --- Shift operators (priority 1-2) ---
20 PRINT 1 { 8            : REM 256  (shift left: 1 * 2^8)
30 PRINT 256 } 4           : REM 16   (shift right: 256 / 2^4)
40 REM --- Bitwise operators (priority 3-5) ---
50 PRINT $FF ~ $0F         : REM 240  (XOR: $F0)
60 PRINT $FF & $0F         : REM 15   (AND: $0F)
70 PRINT $F0 | $0F         : REM 255  (OR: $FF)
80 PRINT $FF EOR $0F       : REM 240  (keyword form of ~)
90 PRINT $FF AND $0F       : REM 15   (keyword form of &)
100 PRINT $F0 OR $0F       : REM 255  (keyword form of |)
110 REM --- Comparison operators (priority 6-8) ---
120 PRINT 3 < 5            : REM 1 (true)
130 PRINT 5 > 3            : REM 1 (true)
140 PRINT 5 = 5            : REM 1 (true)
150 PRINT 3 <= 5           : REM 1 (less or equal)
160 PRINT 5 >= 5           : REM 1 (greater or equal)
170 PRINT 3 <> 5           : REM 1 (not equal)
180 REM --- Arithmetic operators (priority 9-13) ---
190 PRINT "Hello" + " World" : REM string concatenation with +
200 PRINT 50 - 17          : REM 33
210 PRINT 6 * 7            : REM 42
220 PRINT 10 / 3           : REM 3.33... (int division -> float)
230 PRINT 2 ^ 10           : REM 1024 (exponentiation, highest priority)
240 PRINT 3 + 2 ^ 3        : REM 11  (^ binds tighter: 3 + 8, not 5^3)
```

---

## 7. Control Flow

### IF...THEN...ELSE

```
IF expression THEN statement(s)
ELSE statement(s)
```

If `expression` evaluates to a non-zero value (true), the statements after THEN are executed. If it evaluates to zero (false), execution skips to the next line.

**Important**: ELSE must appear on the line immediately following the IF/THEN line. It cannot be on the same line as the IF. ELSE is only recognized if there is exactly one IF in the preceding line.

```
10 IF x > 5 THEN PRINT "big"
20 ELSE PRINT "small"
```

Nested IFs are supported, but only the outermost IF/ELSE pair is matched. Up to 100 levels of IF nesting are supported before an "if-then-else overflow" error occurs.

The keyword THEN is mandatory. Omitting it causes a "missing &lt;then&gt;" error.

### FOR...NEXT

```
FOR variable = start TO end
FOR variable = start TO end STEP increment
...
NEXT
NEXT variable
```

Executes a loop. The variable is set to `start`, and the loop body is executed. After each iteration, the variable is incremented by `increment` (default 1). The loop continues as long as the variable has not exceeded `end`. With a negative STEP, the loop continues as long as the variable is not less than `end`.

The loop variable can be integer or float (not string). Up to 100 nested FOR/NEXT loops are supported.

NEXT optionally takes a variable name, but the interpreter always matches the most recent FOR regardless.

System variables (pi, ti, ti$) cannot be used as FOR loop variables.

```
10 FOR i% = 1 TO 10
20   PRINT i%
30 NEXT i%
```

### GOSUB / RETURN

```
GOSUB line_number
...
RETURN
```

GOSUB saves the current execution position and jumps to the specified line number. RETURN resumes execution at the statement following the GOSUB.

Up to 100 nested GOSUB calls are supported. GOSUB can be used in both direct mode and program mode. RETURN is program-mode only.

### GOTO

```
GOTO line_number
```

Unconditionally jumps to the specified line number. If the line does not exist, a "can't find line number" error occurs.

A bare line number can also be used as a shorthand for GOTO:

```
100 PRINT "loop"
110 100
```

This is equivalent to `110 GOTO 100`.

### ON...GOTO / ON...GOSUB

```
ON expression GOTO line1, line2, line3, ...
ON expression GOSUB line1, line2, line3, ...
```

Evaluates `expression` as an integer. If the value is 1, control transfers to the first line number; if 2, the second; and so on. If the value does not match any listed line number (out of range), execution continues with the next statement.

### ON TRACE GOSUB

```
ON TRACE GOSUB line_number
```

Sets a trace handler. When tracing is enabled (via TRON), before each statement is executed, the interpreter calls the specified subroutine via GOSUB. The trace subroutine can inspect the current state. See the Debugging section for details.

### Hands-On: Number Guessing Game

The computer picks a random number between 1 and 100; you guess with "too high" / "too low" feedback.

```basic
10  REM === Number Guessing Game ===
20  secret% = INT(RND(ti) * 100) + 1
30  guesses% = 0
40  PRINT "I'm thinking of a number (1-100)."
50  INPUT "Your guess: "; g%
60  guesses% = guesses% + 1
70  IF g% = secret% THEN GOTO 120
80  IF g% < secret% THEN PRINT "Too low!"
90  ELSE PRINT "Too high!"
100 IF guesses% >= 10 THEN PRINT "No more tries! It was"; secret%: END
110 GOTO 50
120 PRINT "Correct in"; guesses%; "guesses!"
```

**What to try:** Change the range to 1-1000 (line 20). Add a best-score tracker using a global variable. Use `ti` to time how long the player takes.

### Hands-On: Menu with ON...GOSUB

A numbered menu dispatches to subroutines using ON...GOSUB, with `ti$` for clock readout.

```basic
10  REM === Menu Dispatcher ===
20  CLS
30  PRINT "=== Main Menu ==="
40  PRINT "1. Greet"
50  PRINT "2. Show Time"
60  PRINT "3. Quit"
70  INPUT "Choice (1-3): "; c%
80  IF c% = 3 THEN PRINT "Goodbye!": END
90  ON c% GOSUB 200, 300
100 PRINT: GOTO 20
200 PRINT "Hello from Atari ST BASIC!"
210 RETURN
300 PRINT "The time is "; ti$
310 PRINT "VBL ticks: "; ti
320 RETURN
```

**What to try:** Add more menu options and corresponding GOSUB targets. Use ON...GOTO instead of ON...GOSUB and observe the difference (no RETURN needed, but no way back to the menu without GOTO).

---

## 8. Procedures and Functions

### DEF PROC / ENDPROC

```
DEF PROC name
  ...statements...
ENDPROC

DEF PROC name(param1, param2$, param3%, ...)
  ...statements...
ENDPROC
```

Defines a named procedure. Procedure definitions are scanned at RUN time (or CLR time) before execution begins, so procedures can be defined anywhere in the program and called from anywhere.

Parameters are passed by value. Each parameter creates a local variable within the procedure scope, initialized to the value passed by the caller. Up to 511 procedures can be defined.

When the interpreter encounters a DEF PROC during normal execution flow, it automatically skips over the procedure body to the line after ENDPROC.

### Calling Procedures

```
PROC name
PROC name(arg1, arg2$, arg3%, ...)
name(arg1, ...)
```

Calls a previously defined procedure. Arguments are matched positionally to parameters. Type mismatches raise errors.

A procedure can also be called by simply writing its name without the PROC keyword; the interpreter recognizes the syntax and dispatches to the procedure.

Procedures can be called recursively. The interpreter maintains a procedure call stack (`proctbl`) of 100 entries (14 bytes each). Exceeding 100 nested calls triggers error 24 ("procedure overflow"). In practice, algorithms like binary search on 100 elements need at most 7 levels, well within the limit. For algorithms needing deep recursion (e.g., quicksort on large arrays), consider an iterative approach with explicit stack arrays.

### LOCAL

```
LOCAL var1, var2$, var3%, ...
LOCAL DIM array(size)
```

Declares local variables within a procedure. Local variables shadow any global variables of the same name for the duration of the procedure. LOCAL is program-mode only and must appear within a DEF PROC...ENDPROC block.

LOCAL integer variables are initialized to 0, LOCAL float variables to 0.0, and LOCAL string variables to the empty string.

LOCAL DIM creates a local array that shadows any global array of the same name.

### The # Operator for Global Access

Inside a procedure, variables are normally looked up in local scope first. To force access to a global variable, insert `#` between the variable name and its type suffix. The `#` is not stored as part of the name -- it is a parsing directive that forces the interpreter to bypass local scope.

| Local form | Global form | Meaning |
|------------|-------------|---------|
| `x%` | `x#%` | Integer variable |
| `name$` | `name#$` | String variable |
| `val!` | `val#!` | Float variable (explicit) |
| `val` | `val#` | Float variable (default -- no suffix) |
| `a(0)` | `a#(0)` | Array element |

```
100 DEF PROC test
110   LOCAL x%
120   x% = 10         REM Sets local x%
130   x#% = 20        REM Sets global x%
140 ENDPROC
```

### ENDPROC

```
ENDPROC
```

Marks the end of a procedure definition and returns control to the caller. If encountered without a matching PROC call, an "endproc without proc" error occurs.

### DEF FN / FN

```
DEF FN name(param) = expression
DEF FN name(param1, param2) = expression
DEF FN name = expression
```

Defines a single-line user function. The function body is a single expression that is evaluated and returned when the function is called. Parameters create temporary variables (stored with a special type flag) that exist only during the function evaluation.

```
10 DEF FN square(x) = x * x
20 PRINT FN square(5)
```

**Calling a function**:

```
FN name(arg)
FN name(arg1, arg2)
```

FN is treated as a function (it returns a value). The return type matches the type of the expression. Array variables cannot be used as function parameters (doing so raises "no arg allowed").

Functions defined with DEF FN can reference global variables and call other functions. They support recursive calls via the argument variable mechanism.

### Parameter Passing

Both procedures and functions pass parameters by value. The caller's expression is evaluated, and the result is written to the parameter variable. Changes to the parameter variable within the procedure/function do not affect the caller's original variable. To modify a global variable from inside a procedure, use the `#` operator (see "The # Operator for Global Access" above).

### Hands-On: Temperature Conversion Table

Defines two conversion functions with DEF FN and prints a Celsius-to-Fahrenheit table. Shows DEF FN with parameters, calling FN in expressions, and TAB for column alignment.

```basic
10  REM === Temperature Conversion Table ===
20  DEF FN c2f(c) = c * 9 / 5 + 32
30  DEF FN f2c(f) = (f - 32) * 5 / 9
40  PRINT "  Celsius"; TAB(15); "Fahrenheit"
50  PRINT "  -------"; TAB(15); "----------"
60  FOR c% = 0 TO 100 STEP 10
70    PRINT TAB(5); c%; TAB(18); FN c2f(c%)
80  NEXT c%
90  PRINT
100 PRINT "Check: 212 F = "; FN f2c(212); " C"
```

**What to try:** Add a FN for Kelvin conversion. Change the STEP to 5 for a finer table.

### Hands-On: Binary Search (Recursive Procedure)

Searches a sorted array using a recursive DEF PROC with LOCAL variables and the `#` operator for writing results to globals.

```basic
10  REM === Binary Search (Recursive) ===
20  DIM a%(20)
30  FOR i% = 1 TO 20
40    READ a%(i%)
50  NEXT i%
60  INPUT "Search for: "; target%
70  found% = 0 : where% = 0
80  PROC bsearch(1, 20)
90  IF found% = 1 THEN PRINT "Found at position"; where%
100 ELSE PRINT "Not found."
110 END
200 DEF PROC bsearch(lo%, hi%)
210   LOCAL mid%
220   IF lo% > hi% THEN ENDPROC
230   mid% = (lo% + hi%) / 2
240   IF a%(mid%) = target#% THEN found#% = 1 : where#% = mid% : ENDPROC
250   IF target#% < a%(mid%) THEN PROC bsearch(lo%, mid% - 1)
260   ELSE PROC bsearch(mid% + 1, hi%)
270 ENDPROC
300 DATA 3,7,12,18,25,31,38,42,49,55
310 DATA 60,67,73,79,84,88,91,95,98,100
```

Expected output (searching for 42):
```
Search for: 42
Found at position 8
```

In line 240, `target#%`, `found#%`, and `where#%` use the `#` operator to access global variables from inside the procedure (see "The # Operator for Global Access" above). Binary search on 20 elements needs at most 5 levels of recursion.

**What to try:** Search for a value not in the array (e.g., 50). Increase the array to 100 elements. Add a `count%` variable to count how many comparisons the search makes.

### Demo Program: Variable Scoping (00529-CONVERT.TXT)

This program was decoded from one of the original tokenized demo files shipped with the interpreter. It demonstrates LOCAL DIM array shadowing and the `#` operator in a single concise example.

```basic
5 a(0)=10:a(1)=20:a(2)=30
10 proc show("Hallo")
20 proc show("-----")
30 end
100 def proc show(s$)
105 local dim a(10)
106 rem  a(0)=1:a(1)=2:a(2)=3
110 print tab(60-len(s$));s$
115 print a(0),a(1),a(2)
116 print a#(0),a#(1),a#(2)
120 endproc
```

**Line 5** sets global array `a` to 10, 20, 30 (auto-created by first use). **Line 105** declares a LOCAL DIM `a(10)` inside the procedure, shadowing the global. **Line 115** prints the local `a` (all zeros). **Line 116** uses `a#(0)` to print the global `a` (10, 20, 30). **Line 106** is commented out -- uncommenting it would set the local array to 1, 2, 3.

Expected output:
```
                                                       Hallo
 0             0             0
 10            20            30
                                                       -----
 0             0             0
 10            20            30
```

---

## 9. String Functions

### LEN(string$)

Returns the length of a string as an integer.

```
PRINT LEN("Hello")     REM prints 5
```

### MID$(string$, position, length)

Returns a substring starting at `position` (1-based) with the given `length`. If the position is beyond the string, a "position not within string" error occurs.

```
PRINT MID$("Hello World", 7, 5)   REM prints "World"
```

### LEFT$(string$, count)

Returns the leftmost `count` characters of a string.

```
PRINT LEFT$("Hello", 3)   REM prints "Hel"
```

### RIGHT$(string$, count)

Returns the rightmost `count` characters of a string.

```
PRINT RIGHT$("Hello", 3)   REM prints "llo"
```

### INSTR$(search$, target$)
### INSTR$(search$, target$, start_position)

Searches for `target$` within `search$`. Returns the 1-based position of the first occurrence, or 0 if not found. An optional third argument specifies the starting position for the search (1-based).

```
PRINT INSTR$("Hello World", "World")      REM prints 7
PRINT INSTR$("Hello World", "xyz")        REM prints 0
PRINT INSTR$("aabaa", "a", 3)             REM prints 4
```

### ASC(string$)

Returns the ASCII code of the first character of a string as an integer.

```
PRINT ASC("A")   REM prints 65
```

### CHR$(code%)

Returns a one-character string with the specified ASCII code.

```
PRINT CHR$(65)   REM prints "A"
```

### VAL(string$)

Converts a string to its numeric value (float). The string is parsed as a floating-point number.

```
PRINT VAL("3.14")   REM prints 3.14
```

### STR$(expression)

Converts a numeric expression (integer or float) to its string representation.

```
PRINT STR$(42)       REM prints " 42"
PRINT STR$(3.14)     REM prints " 3.14"
```

Numbers are preceded by a space (for the sign position).

### HEX$(expression)

Converts an integer expression to a hexadecimal string prefixed with `$`. Leading zeros are suppressed.

```
PRINT HEX$(255)   REM prints "$FF"
PRINT HEX$(16)    REM prints "$10"
```

### BIN$(expression)

Converts an integer expression to a binary string prefixed with `%`. Leading zeros are suppressed.

```
PRINT BIN$(10)    REM prints "%1010"
```

### INKEY$

Reads a single character from the keyboard without waiting. Returns an empty string if no key is pressed. Returns a one-character string if a key is available in the keyboard buffer.

```
10 a$ = INKEY$
20 IF a$ <> "" THEN PRINT "You pressed: "; a$
```

INKEY$ uses GEMDOS function 7 (Crawcin) to read the character.

### Hands-On: Word Analyzer

Reads a word from the user, then reverses it, counts vowels, and converts to uppercase.

```basic
10  REM === Word Analyzer ===
20  INPUT "Enter a word: "; w$
30  PRINT "Length: "; LEN(w$)
40  REM --- Reverse ---
50  r$ = ""
60  FOR i% = LEN(w$) TO 1 STEP -1
70    r$ = r$ + MID$(w$, i%, 1)
80  NEXT i%
90  PRINT "Reversed: "; r$
100 REM --- Count vowels ---
110 v% = 0
120 FOR i% = 1 TO LEN(w$)
130   IF INSTR$("aeiouAEIOU", MID$(w$, i%, 1)) > 0 THEN v% = v% + 1
140 NEXT i%
150 PRINT "Vowels: "; v%
160 REM --- Uppercase ---
170 u$ = ""
180 FOR i% = 1 TO LEN(w$)
190   c% = ASC(MID$(w$, i%, 1))
200   IF c% >= 97 AND c% <= 122 THEN c% = c% - 32
210   u$ = u$ + CHR$(c%)
220 NEXT i%
230 PRINT "Uppercase: "; u$
```

Expected output (for input "Atari"):
```
Enter a word: Atari
Length:  5
Reversed: iratA
Vowels:  3
Uppercase: ATARI
```

**What to try:** Add a palindrome check (compare `w$` with `r$`). Count consonants. Handle numbers and special characters in the uppercase conversion.

---

## 10. Math Functions

All trigonometric functions use radians.

### INT(expression)

Converts a numeric expression to an integer by truncating the fractional part.

```
PRINT INT(3.7)    REM prints 3
PRINT INT(-3.7)   REM prints -3
```

### ABS(expression)

Returns the absolute value of a numeric expression. Works with both integers and floats, preserving the type.

```
PRINT ABS(-5)     REM prints 5
PRINT ABS(3.14)   REM prints 3.14
```

### SGN(expression)

Returns the sign of a numeric expression: 1 for positive, -1 for negative, 0 for zero. The result is always an integer.

```
PRINT SGN(-42)    REM prints -1
PRINT SGN(0)      REM prints 0
PRINT SGN(3.14)   REM prints 1
```

### SQR(expression)

Returns the square root. The argument must be a float. Negative arguments raise "square root of negative."

```
PRINT SQR(144)    REM prints 12
```

### SIN(expression)

Returns the sine of the argument (in radians).

```
PRINT SIN(pi/2)   REM prints 1
```

### COS(expression)

Returns the cosine of the argument (in radians).

```
PRINT COS(0)      REM prints 1
```

### TAN(expression)

Returns the tangent of the argument (in radians).

```
PRINT TAN(pi/4)   REM prints 1
```

### ATN(expression)

Returns the arc tangent (inverse tangent) of the argument. Result is in radians.

```
PRINT ATN(1)      REM prints 0.785398... (pi/4)
```

### ATANPT(y, x)

Returns the arc tangent of the point (x, y), equivalent to `atan2(y, x)`. This is a two-argument form that returns the angle in radians, correctly handling all four quadrants.

```
PRINT ATANPT(1, 1)   REM prints 0.785398... (pi/4)
```

### LOG(expression)

Returns the base-10 logarithm. The argument must be positive; negative or zero arguments raise "log of negative number."

```
PRINT LOG(100)    REM prints 2
```

### LN(expression)

Returns the natural logarithm (base e). The argument must be positive.

```
PRINT LN(2.718281828)   REM prints approximately 1
```

### EXP(expression)

Returns e raised to the power of the argument.

```
PRINT EXP(1)      REM prints 2.71828...
```

### EXP10(expression)

Returns 10 raised to the power of the argument.

```
PRINT EXP10(2)    REM prints 100
```

### RND(expression)

Returns a pseudo-random number.

- `RND(0)` returns the most recently generated random number (unchanged).
- `RND(1)` returns the next random number in the sequence (unchanged).
- `RND(x)` for any other `x` returns a new random number, using `x` as a multiplier seed.

The random number generator is implemented via a multiplication algorithm on the BCD floating-point representation.

```
10 x = RND(12345)        : REM Seed generator and get first number
20 PRINT RND(1)           : REM Next random number in sequence
30 PRINT RND(1)           : REM Another random number
40 PRINT RND(0)           : REM Repeat last number (unchanged)
```

### MOD(x, y)

Returns the remainder of `x` divided by `y` (floating-point modulo). Both arguments are floats.

```
PRINT MOD(10, 3)   REM prints 1
```

### NOT(expression)

Performs a bitwise NOT on an integer expression. Each bit is inverted. The argument is forced to integer type.

```
PRINT NOT(0)       REM prints -1  ($FFFFFFFF)
PRINT NOT(-1)      REM prints 0
```

Note: NOT does not require parentheses -- it reads the next integer expression directly.

### Hands-On: BCD Precision and Trig Table

Showcases the BCD floating-point precision (~22 significant digits) and prints a trigonometric table.

```basic
10  REM === BCD Precision Demo ===
20  PRINT "Pi at full precision:"
30  PRINT pi
40  PRINT
50  PRINT "SIN(pi)       = "; SIN(pi)
60  PRINT "SQR(2)^2 - 2  = "; SQR(2) * SQR(2) - 2
70  PRINT "1/3 * 3        = "; (1 / 3) * 3
80  PRINT
90  PRINT "Deg"; TAB(10); "SIN"; TAB(28); "COS"
100 PRINT "---"; TAB(10); "---"; TAB(28); "---"
110 FOR d% = 0 TO 90 STEP 15
120   r = d% * pi / 180
130   PRINT d%; TAB(10); SIN(r); TAB(28); COS(r)
140 NEXT d%
```

Expected output (approximate -- BCD precision gives ~22 significant digits):
```
Pi at full precision:
 3.14159265358979323846

SIN(pi)       =  0
SQR(2)^2 - 2  =  0
1/3 * 3        =  1

Deg      SIN                      COS
---      ---                      ---
 0        0                        1
 15       0.258819045102520762     0.965925826289068286
 30       0.5                      0.866025403784438646
 45       0.707106781186547524     0.707106781186547524
 60       0.866025403784438646     0.5
 75       0.965925826289068286     0.258819045102520762
 90       1                        0
```

*Note: The exact number of digits printed depends on the interpreter's PRINT formatting for BCD floats. The key demonstration is that SIN(pi) and SQR(2)^2-2 yield exactly 0 (no floating-point drift), and 1/3*3 yields exactly 1 -- results impossible with binary IEEE 754 floats.*

**What to try:** Add TAN to the table. Compute EXP(1) and compare to the known value of e. Try `PRINT 1/7*7` and `PRINT 1/49*49`.

---

## 11. Input/Output

### PRINT

```
PRINT expression
PRINT expression1; expression2
PRINT expression1, expression2
PRINT #handle, expression
? expression
```

Outputs values to the screen (or to a file if `#handle` is specified).

- Expressions separated by `;` are printed with no space between them.
- Expressions separated by `,` are printed with a tab between them (the cursor advances to the next tab stop).
- Numeric values are preceded by a space (for the sign position).
- A trailing `;` suppresses the newline at the end of the PRINT statement.
- `?` can be used as a shorthand for PRINT.

```
10 PRINT "Hello"; " "; "World"
20 PRINT 1, 2, 3
30 PRINT "No newline";
```

### INPUT

```
INPUT variable
INPUT variable1, variable2, ...
INPUT "prompt text"; variable
INPUT #handle, variable
INPUT #handle, variable1, variable2, ...
```

Reads values from the keyboard (or from a file if `#handle` is specified).

For keyboard input:
- The interpreter displays `?` and waits for the user to type a response.
- If a prompt string is provided (in quotes, followed by `;`), it is displayed instead of `?`.
- Multiple variables can be read from a single input line, separated by commas.
- String input is terminated by a comma or end of line.
- Numeric input is parsed as an expression.

For file input:
- Values are read from the file, separated by commas, tabs, or newlines.
- Line feed characters (ASCII 10) are skipped; carriage return (ASCII 13) terminates a value.

### GET

```
GET variable$
GET #handle, variable$
```

Reads a single character from the keyboard (or from a file). For keyboard input, GET first checks if a character is available in the buffer (using GEMDOS function $0B, Cconis). If no character is available, the string variable is set to an empty string. If a character is available, it is read (using GEMDOS function 7) and stored as a one-character string.

For file input, one byte is read from the file.

The variable must be a string variable.

### TAB(column)

```
PRINT TAB(10); "Hello"
```

Moves the cursor to the specified column (1-based). When used in a PRINT statement, TAB positions the cursor absolutely on the screen. When file output is active, TAB behaves like SPC (outputs spaces).

The column must be a positive integer (1 or greater). Values exceeding the screen width cause a "cursor out of range" error.

### SPC(count)

```
PRINT SPC(5); "Hello"
```

Outputs the specified number of spaces. The count must be a positive integer (1 or greater).

### EDTAB(count)

```
PRINT EDTAB(3); "Hello"
```

Advances the cursor by the specified number of editor tab stops. The cursor column is first reset to 0, then the tab key action is simulated `count` times. Only works for screen output (not file output).

### CURSOR

```
CURSOR column, row
CURSOR
```

Without arguments, moves the cursor to the home position (0,0). With arguments, positions the cursor at the specified column and row (1-based). Values outside the screen bounds cause a "cursor out of range" error.

### CLS

```
CLS
```

Clears the editor screen and resets the cursor to the home position.

### POS(expression)

Returns the current cursor column position as an integer. The argument is evaluated but ignored (included for compatibility).

```
PRINT POS(0)   REM prints current cursor column
```

### CMD

```
CMD handle
```

Redirects all subsequent PRINT output to the specified file handle (no `#` prefix). Output continues to the file until the file handle is changed or closed.

```
10 CREATE 10, "OUTPUT.TXT"
20 CMD 10                    : REM Redirect output to file
30 PRINT "This goes to the file"
40 CLOSE 10                  : REM Closing the handle ends CMD mode
```

### Hands-On: Formatted Price List

A neatly formatted price list using CLS, CURSOR, TAB, SPC, and POS for screen positioning.

```basic
10  REM === Formatted Price List ===
20  CLS
30  CURSOR 20, 1: PRINT "*** ATARI ST SHOP ***"
40  CURSOR 1, 3
50  PRINT "Item"; TAB(25); "Price"
60  PRINT "----"; TAB(25); "-----"
70  PRINT "Floppy disk (10 pack)"; TAB(25); "19.90"
80  PRINT "Mouse mat"; TAB(25); " 9.95"
90  PRINT "Dust cover"; TAB(25); "14.50"
100 PRINT "Joystick"; TAB(25); "24.95"
110 PRINT
120 PRINT SPC(20); "----------"
130 PRINT SPC(17); "Total: 69.30"
140 PRINT
150 PRINT "Cursor at column"; POS(0)
```

Expected output (screen positions approximate):
```
                    *** ATARI ST SHOP ***

Item                    Price
----                    -----
Floppy disk (10 pack)   19.90
Mouse mat                9.95
Dust cover              14.50
Joystick                24.95

                    ----------
                 Total: 69.30

Cursor at column 16
```

**What to try:** Use DATA/READ to store the items and prices, then print them in a loop. Add a running total computed with a variable.

### Hands-On: Bouncing Ball Animation

Animates a character bouncing across the screen. Press any key to quit.

```basic
10  REM === Bouncing Ball ===
20  CLS
30  x% = 1: y% = 1: dx% = 1: dy% = 1
40  CURSOR x%, y%: PRINT " ";
50  x% = x% + dx% : y% = y% + dy%
60  IF x% <= 1 OR x% >= 78 THEN dx% = -dx%
70  IF y% <= 1 OR y% >= 23 THEN dy% = -dy%
80  CURSOR x%, y%: PRINT "o";
90  WAIT 2
100 k$ = INKEY$
110 IF k$ <> "" THEN CLS: PRINT "Stopped.": END
120 GOTO 40
```

**What to try:** Change the ball character to `"*"`. Add a second ball with separate variables. Adjust `WAIT 2` to `WAIT 1` for faster movement or `WAIT 5` for slower.

---

## 12. File I/O

### OPEN

```
OPEN handle, "filename"
```

Opens an existing file for reading and writing. `handle` is a user-chosen integer identifier (greater than 5) used to refer to this file in subsequent operations. Handles 0-5 are reserved for system devices (0=keyboard, 1=screen, 2=serial, 3=printer, etc.).

Up to 100 files can be open simultaneously.

If the file does not exist, a "file open" error occurs. If the handle is already in use, an "already open" error occurs.

### CREATE

```
CREATE handle, "filename"
```

Creates a new file (or overwrites an existing one) and opens it for writing. The handle works the same as OPEN.

If the file cannot be created, a "file create" error occurs.

### CLOSE

```
CLOSE handle
```

Closes a previously opened file. Note: unlike `PRINT #handle` and `INPUT #handle`, the CLOSE command does not use a `#` prefix. Handles 0-5 (system devices) are not actually closed.

### PRINT #handle

```
PRINT #handle, expression
PRINT #handle, expression1; expression2
```

Writes output to the file identified by `handle`. The formatting rules are the same as for screen PRINT. A carriage return outputs both CR (13) and LF (10) to the file.

### INPUT #handle

```
INPUT #handle, variable
INPUT #handle, variable1, variable2, ...
```

Reads values from a file. Values are delimited by commas, tabs, carriage returns, or null bytes. See the INPUT description above for details.

### GET #handle

```
GET #handle, variable$
```

Reads a single byte from a file into a string variable.

### File Names and Drive Letters

File names can include a drive letter prefix (e.g., `"A:MYFILE.BAS"`). If a drive letter followed by `:` is provided, the current drive is set accordingly using GEMDOS Dsetdrv before the file operation.

### DIR

```
DIR
DIR "path"
DIR "A:*.BAS"
```

Displays a directory listing. Without arguments, lists all files in the current directory (`*.*`). With a path, lists matching files. Supports wildcards. The listing shows the filename (in quotes, lowercase), file attributes (P for write-protected, bell character for subdirectories), and file size.

### Hands-On: Mini Notepad

Type lines, save to disk, then read them back -- the complete file I/O cycle.

```basic
10  REM === Mini Notepad ===
20  PRINT "Type lines of text. Enter DONE to save."
30  CREATE 10, "NOTES.TXT"
40  count% = 0
50  INPUT "> "; l$
60  IF l$ = "DONE" THEN GOTO 100
70  PRINT #10, l$
80  count% = count% + 1
90  GOTO 50
100 CLOSE 10
110 PRINT: PRINT "Saved"; count%; "lines. Reading back:"
120 PRINT "---"
130 OPEN 10, "NOTES.TXT"
140 FOR i% = 1 TO count%
150   INPUT #10, r$
160   PRINT r$
170 NEXT i%
180 CLOSE 10
190 PRINT "---"
```

**BASIC file handles and GEMDOS:** The handle number 10 in `CREATE 10, "NOTES.TXT"` is a BASIC-level logical handle chosen by the programmer. Internally, the interpreter maintains a 100-entry translation table (`handtab`, 4 bytes per entry) that maps each BASIC handle to the actual GEMDOS file handle returned by the OS. When you use `PRINT #10`, the interpreter looks up handle 10 in this table and passes the corresponding GEMDOS handle to the `Fwrite` trap call.

Handles 0-5 are reserved for standard system devices and map directly to their GEMDOS equivalents without translation:

| Handle | Device |
|--------|--------|
| 0 | CON: (keyboard input) |
| 1 | CON: (screen output) |
| 2 | Standard error |
| 3 | AUX: (RS-232 serial) |
| 4 | PRN: (parallel printer) |
| 5 | (reserved) |

This is why user file handles must be >5. Using `PRINT #3, "text"` would send output to the serial port, not to a file. Up to 100 files can be open simultaneously (handles 6-105). Note the syntax difference: `OPEN`/`CREATE`/`CLOSE`/`CMD` take the handle as a bare number, while `PRINT#`/`INPUT#`/`GET#` require the `#` prefix.

**What to try:** Use `PRINT #4, "text"` to send output to the printer. Write a second program that reads back NOTES.TXT without knowing the line count (use GET# to read byte-by-byte until the file is exhausted).

---

## 13. DATA/READ/RESTORE

### DATA

```
DATA value1, value2, value3, ...
```

Stores constant values for use with READ. DATA statements are not executed; they are skipped during normal program flow. Values can be numeric (integer or float) or string. Multiple DATA statements can appear throughout the program, and they are read sequentially.

### READ

```
READ variable
READ variable1, variable2, ...
```

Reads the next value from the DATA statements and assigns it to the variable. The values are read in the order they appear in the program (from the first DATA statement onward). Each READ advances the internal data pointer to the next value.

If there are no more DATA values to read, an "out of data" error occurs.

### RESTORE

```
RESTORE
RESTORE line_number
```

Resets the DATA pointer. Without an argument, the pointer is reset to the beginning of the program (the first DATA value). With a line number, the pointer is set to the specified line, so subsequent READs begin from that line's DATA.

If the specified line does not exist, a "can't find line number" error occurs.

### Hands-On: High Score Table

Reads high scores from DATA statements, sorts them with bubble sort using SWAP, and displays a ranked table. Demonstrates mixed-type DATA (strings and integers), DIM, nested FOR/NEXT loops, and TAB formatting.

```basic
10  REM === High Score Table ===
20  n% = 5
30  DIM name$(n%), score%(n%)
40  FOR i% = 1 TO n%
50    READ name$(i%), score%(i%)
60  NEXT i%
70  REM --- Sort descending ---
80  FOR i% = 1 TO n% - 1
90    FOR j% = 1 TO n% - i%
100     IF score%(j%) < score%(j%+1) THEN SWAP score%(j%),score%(j%+1): SWAP name$(j%),name$(j%+1)
110   NEXT j%
120 NEXT i%
130 PRINT "=== HIGH SCORES ==="
140 FOR i% = 1 TO n%
150   PRINT i%; ". "; name$(i%); TAB(18); score%(i%)
160 NEXT i%
170 DATA "Alice",4200,"Bob",3800,"Carol",5100
180 DATA "Dave",2900,"Eve",4700
```

Expected output:
```
=== HIGH SCORES ===
 1. Carol            5100
 2. Eve              4700
 3. Alice            4200
 4. Bob              3800
 5. Dave             2900
```

**What to try:** Add more players to the DATA lines. Use RESTORE to re-read the original (unsorted) data and print it for comparison. Store the sorted results to a file with CREATE/PRINT#.

---

## 14. Memory and System Access

### PEEK(address)

Returns the byte value at the specified memory address as an integer (-128 to 127, sign-extended).

```
PRINT PEEK($FF8260)   REM Read video mode register
```

### POKE address, value

Writes a byte value to the specified memory address. Only the lowest 8 bits of `value` are written.

```
POKE $FF8260, 0   REM Set low resolution
```

Note: POKE does not require the address to be even-aligned.

### WPEEK(address)

Returns the 16-bit word value at the specified memory address as an integer (-32768 to 32767, sign-extended). The address must be even; odd addresses raise "odd address access."

```
PRINT WPEEK($FF8240)   REM Read color palette register 0 (color0)
```

### WPOKE address, value

Writes a 16-bit word to the specified memory address. The address must be even. Only the lowest 16 bits of `value` are written.

```
WPOKE $FF8240, $777     REM Set color 0 to light grey ($RGB)
```

### LPEEK(address)

Returns the 32-bit long word value at the specified memory address. The address must be even.

```
PRINT "$"; HEX$(LPEEK($44E))   REM Read _v_bas_ad (screen base address)
```

### LPOKE address, value

Writes a 32-bit long word to the specified memory address. The address must be even.

```
LPOKE addr%, $12345678   REM Write 32-bit value to address
```

### VARPTR(variable)

Returns the memory address where a variable's value is stored. For string variables, returns the address of the string data pointer. For array elements, the specific element's address is returned.

```
PRINT VARPTR(x%)       REM Address of integer variable x%
PRINT VARPTR(a$(3))    REM Address of array element
```

The variable must already be defined; otherwise, a "variable not yet defined" error occurs.

### FRE(expression)

Returns the number of free bytes in the variable/string storage area.

- `FRE(1)` returns the free space without performing garbage collection.
- `FRE(0)` or any other argument performs garbage collection first, then returns the free space.

Garbage collection reclaims space from strings that have been marked as invalid (superseded by new assignments).

```
PRINT FRE(0)    REM Free bytes after garbage collection
PRINT FRE(1)    REM Free bytes without garbage collection (faster)
```

### STRFRE(expression)

Returns the number of free bytes in the string storage area specifically (as opposed to variable storage). Always performs garbage collection first.

```
PRINT STRFRE(0)   REM Free bytes in string heap
```

### SWAP

```
SWAP variable1, variable2
```

Exchanges the values of two variables. Both variables must be of compatible types (both numeric, or both strings). Swapping a string with a numeric variable raises "type mismatch."

When swapping an integer variable with a float variable, **automatic type conversion occurs**: the float value is truncated to integer and stored in the integer variable, while the integer value is converted to float and stored in the float variable. Each variable retains its own type -- only the values are exchanged and converted.

```
10 a% = 1 : b% = 2
20 SWAP a%, b%
30 PRINT a%, b%   REM prints 2  1
```

### WAIT

```
WAIT count
```

Pauses program execution for the specified number of vertical blank frames. One frame is approximately 1/70th of a second on monochrome (71 Hz) or 1/50th of a second on PAL color (50 Hz). Internally calls XBIOS Vsync (#37) in a loop.

```
10 PRINT "Starting..."
20 WAIT 70               : REM Pause ~1 second (monochrome)
30 PRINT "One second later!"
```

### SYS(address)

Calls a machine language routine at the specified memory address. The address must be even. The routine should end with an RTS instruction.

```
SYS($FC0000)   REM Call ROM routine
```

### CALL(address [, [*]value, ...])

Calls a machine language routine at the specified address, with the ability to pass values in 68000 CPU registers. Arguments are loaded into **data registers (D0-D7)** in order. Prefix an argument with `*` to load it into an **address register (A0-A6)** instead.

After the routine returns, the value of D0 is available as the integer return value of CALL.

```
result% = CALL($FC0000, 5, *$FF8000)
```

This calls the routine at $FC0000 with D0=5 and A0=$FF8000, and stores the returned D0 value in `result%`.

**Register assignment rules:**
- Up to 8 data registers (D0-D7) and 7 address registers (A0-A6) can be loaded.
- Data registers fill first, left to right. If more than 8 data-register values are given, **extras automatically overflow into address registers**.
- Use `*` prefix to explicitly target an address register: `CALL addr, 1, 2, *$8000` sets D0=1, D1=2, A0=$8000.
- Empty parameter slots (consecutive commas `,,` or trailing `)`) leave the register at its default value (0).
- CALL supports **recursive/nested calls**: register state is saved and restored on the stack.

```
10 REM Set D0=1, D1=2, D2=3 (all data regs)
20 x% = CALL(addr%, 1, 2, 3)
30 REM Skip D1 (leave at 0), set A0 explicitly
40 x% = CALL(addr%, 100,, *$FF8240)
```

### FUNCTION(string$)

Evaluates the contents of a string as a numeric expression and returns the result. This is functionally identical to VAL but named FUNCTION for clarity when the string contains a mathematical expression rather than a simple number.

```
PRINT FUNCTION("2+3*4")   REM Evaluates the expression
```

### Hands-On: System Info Display

Reads Atari ST system variables from memory and displays them with HEX$ and BIN$ formatting.

```basic
10  REM === System Info ===
20  PRINT "=== Atari ST System ==="
30  PRINT "Screen base:  $"; HEX$(LPEEK($44E))
40  PRINT "Phystop:      $"; HEX$(LPEEK($42E))
50  PRINT "VBL counter:  "; LPEEK($466)
60  PRINT
70  PRINT "=== BASIC Memory ==="
80  PRINT "Free variables: "; FRE(0); " bytes"
90  PRINT "Free strings:   "; STRFRE(0); " bytes"
100 x% = 42
110 PRINT "Address of x%:  $"; HEX$(VARPTR(x%))
120 PRINT
130 PRINT "=== Number Formats ==="
140 PRINT "255 = "; HEX$(255); " = "; BIN$(255)
150 PRINT "$FF AND $0F = "; HEX$($FF AND $0F)
```

Expected output (addresses vary by machine configuration):
```
=== Atari ST System ===
Screen base:  $78000
Phystop:      $100000
VBL counter:  83472

=== BASIC Memory ===
Free variables:  48320 bytes
Free strings:    32768 bytes
Address of x%:  $A1234

=== Number Formats ===
255 = $FF = %11111111
$FF AND $0F = $F
```

*Note: Screen base, phystop, VBL counter, free memory, and variable addresses are machine-dependent and will differ on each run. The number format conversions are deterministic.*

**What to try:** Read other system variables: `LPEEK($4BA)` (`_hz_200`, 200 Hz timer), `PEEK($424)` (NVRAM byte). Compare `FRE(0)` vs `FRE(1)` to see the cost of garbage collection. Create many string variables and watch `STRFRE(0)` decrease.

---

## 15. GEMDOS/BIOS/XBIOS

The interpreter provides direct access to the three Atari ST system trap interfaces. For a complete function reference with all parameter details, see **BASIC-GEMDOS_BIOS_XBIOS.md**.

### GEMDOS(function_number, arg1, arg2, ...)

Calls a GEMDOS function (trap #1). The function number is the first argument. The interpreter knows the parameter types and sizes for each function from a built-in descriptor table, so you pass arguments naturally:

```
PRINT GEMDOS($19)                         REM Dgetdrv - get current drive (0=A, 1=B, 2=C...)
handle% = GEMDOS($3D, "A:TEST.TXT", 0)   REM Fopen - open file for reading
```

GEMDOS accepts function numbers $00 through $57 (88 possible numbers). Of these, 51 functions have parameter descriptors and are callable; the remaining function numbers are unsupported and raise "improper function number for gemdos/bios/xbios." See **BASIC-GEMDOS_BIOS_XBIOS.md** for the complete list of supported functions.

### BIOS(function_number, arg1, arg2, ...)

Calls a BIOS function (trap #13). Supports functions 0 through 11.

```
key% = BIOS(2, 2)       REM Bconin - read from console (device 2)
stat% = BIOS(8, 2)      REM Bcostat - console output status
state% = BIOS(11, -1)   REM Kbshift - read shift key state
```

BIOS device codes: 0 = printer, 1 = RS-232 (aux), 2 = console, 3 = MIDI, 4 = keyboard.

### XBIOS(function_number, arg1, arg2, ...)

Calls an XBIOS function (trap #14). Supports functions 0 through 39.

```
rez% = XBIOS(4)          REM Getrez - screen resolution (0=low, 1=med, 2=high)
r% = XBIOS(17)           REM Random - 24-bit random number
XBIOS(7, 0, $700)        REM Setcolor - set color 0 to red ($RGB format)
```

### Return Values and Errors

- The return value is always a 32-bit integer (the full D0 register after the trap call).
- **A negative return value indicates an error.** Common GEMDOS errors: -33 = file not found, -34 = path not found, -35 = too many open files, -36 = access denied, -39 = insufficient memory. Always check the return value.
- BASIC error 32 ("improper function number") is raised if the function number is not in the supported range.

```
10 handle% = GEMDOS($3D, "NOFILE.TXT", 0)
20 IF handle% < 0 THEN PRINT "Error: "; handle%: STOP
```

### String and Buffer Parameters

- **String parameters** are automatically converted from BASIC's internal backward storage to forward C strings before being passed to the OS. You simply pass a string variable or literal.
- **Buffer addresses** (for functions like Fread, Fwrite, Dfree): Use `VARPTR(variable)` to obtain the memory address of a BASIC variable. Alternatively, use `GEMDOS($48, size)` (Malloc) to allocate a dedicated buffer.

```
10 REM Write a string to a file
20 a$ = "Hello, World!"
30 result% = GEMDOS($40, handle%, LEN(a$), VARPTR(a$))  : REM Fwrite
```

### Practical Examples

```
10 REM === Create, write, and close a file ===
20 handle% = GEMDOS($3C, "OUTPUT.TXT", 0)   : REM Fcreate (attr=0: normal)
30 IF handle% < 0 THEN PRINT "Create error!": STOP
40 msg$ = "Hello from BASIC!"
50 result% = GEMDOS($40, handle%, LEN(msg$), VARPTR(msg$))  : REM Fwrite
60 result% = GEMDOS($3E, handle%)             : REM Fclose
```

```
10 REM === Get and display system date ===
20 date% = GEMDOS($2A)                : REM Tgetdate (packed DOS format)
30 day% = date% AND 31                : REM bits 0-4
40 month% = (date% / 32) AND 15       : REM bits 5-8
50 year% = (date% / 512) + 1980       : REM bits 9-15
60 PRINT day%; "/"; month%; "/"; year%
```

```
10 REM === Play a tone via PSG sound chip ===
20 result% = XBIOS(28, 200, 0)    : REM Giaccess: reg 0 = fine tune
30 result% = XBIOS(28, 0, 1)      : REM reg 1 = coarse tune
40 result% = XBIOS(28, $3E, 7)    : REM reg 7 = mixer (enable tone A)
50 result% = XBIOS(28, 15, 8)     : REM reg 8 = channel A volume = max
60 WAIT 200                         : REM play for ~2.8 sec (mono) or ~4 sec (PAL color)
70 result% = XBIOS(28, 0, 8)      : REM volume = 0 (silence)
```

### Hands-On: Melody Player (PSG Sound)

Plays a rising musical scale (8 notes) through the YM2149 PSG sound chip using XBIOS Giaccess. Each note's pitch and duration are stored in DATA statements.

```basic
10  REM === Musical Scale (PSG) ===
20  REM Note: fine_tune, coarse_tune, duration
30  DATA 239,0,25, 213,0,25, 190,0,25, 179,0,25
40  DATA 159,0,25, 142,0,25, 127,0,25, 119,0,50
50  result% = XBIOS(28, $3E, 7)  : REM Mixer: tone A on
60  result% = XBIOS(28, 15, 8)   : REM Volume: max
70  FOR n% = 1 TO 8
80    READ fine%, coarse%, dur%
90    result% = XBIOS(28, fine%, 0)   : REM Fine tune
100   result% = XBIOS(28, coarse%, 1) : REM Coarse tune
110   WAIT dur%
120 NEXT n%
130 result% = XBIOS(28, 0, 8)    : REM Silence
140 PRINT "Done!"
```

**What to try:** Change the DATA values to create different melodies. Use channels B and C (registers 2-3 and 4-5) for chords. Add an envelope effect using registers 11-13.

---

## 16. AES/VDI Access

The interpreter provides comprehensive access to the GEM Application Environment Services (AES) and Virtual Device Interface (VDI) through dedicated control arrays. For a complete function reference with all AES opcodes, VDI functions, and Line-A variable offsets, see **BASIC-GEM_VDI_LINEA.md**.

### AES Arrays

| Command/Function | Direction | Size | Description |
|------------------|-----------|------|-------------|
| `AESCTRL index, value` | Write | 10 words | AES control array: [0]=opcode, [1]=sintin, [2]=sintout, [3]=saddrin, [4]=saddrout |
| `AESCTRL(index)` | Read | | Read back a control array value |
| `AESINTIN index, value` | Write | 128 words | Integer input parameters for the AES call |
| `AESINTOUT(index)` | Read | 128 words | Integer output results from the AES call |
| `AESADRIN index, value` | Write | 128 longs | Address (pointer) input parameters |
| `AESADROUT(index)` | Read | 128 longs | Address (pointer) output results |
| `AES` | Execute | | Invoke the AES call (trap #2, opcode $C8) |

### VDI Arrays

| Command/Function | Direction | Size | Description |
|------------------|-----------|------|-------------|
| `VDICTRL index, value` | Write | 12 words | VDI control: [0]=opcode, [1]=ptsin count, [3]=intin count, [5]=sub-function, [6]=handle |
| `VDICTRL(index)` | Read | | Read back a control value |
| `VDIINTIN index, value` | Write | 128 words | Integer input parameters |
| `VDIINTOUT(index)` | Read | 128 words | Integer output results |
| `VDIPTSIN index, value` | Write | 128 words | Coordinate input (x,y pairs) |
| `VDIPTSOUT(index)` | Read | 128 words | Coordinate output results |
| `VDI` | Execute | | Invoke the VDI call (trap #2, opcode $73) |

### Command/Function Duality

All array commands (AESCTRL, AESINTIN, VDICTRL, etc.) are **dual-purpose**:
- **As a command** (standalone statement): writes values to the array.
- **As a function** (in an expression): reads values from the array.

```
AESCTRL 0, 10          REM Command: sets control[0] = 10
x% = AESCTRL(0)        REM Function: reads control[0] into x%
```

### Index and Value Format

All array commands accept pairs of arguments: `index, value [, index, value, ...]`. The index is 0-based. Multiple pairs can be specified in one statement:

```
VDICTRL 0, 6, 1, 2, 6, handle%   REM Sets control[0]=6, control[1]=2, control[6]=handle%
```

### AES Control Array Format

The AES control array tells GEM which function to call and how many parameters to expect:

| Index | Meaning |
|-------|---------|
| 0 | AES function opcode (e.g., 10 = appl_init, 52 = form_alert) |
| 1 | Number of integer inputs (entries used in AESINTIN) |
| 2 | Number of integer outputs (entries returned in AESINTOUT) |
| 3 | Number of address inputs (entries used in AESADRIN) |
| 4 | Number of address outputs (entries returned in AESADROUT) |

### VDI Control Array Format

| Index | Meaning |
|-------|---------|
| 0 | VDI function opcode (e.g., 6 = v_pline, 8 = v_gtext) |
| 1 | Number of input coordinate pairs (entries in VDIPTSIN) |
| 2 | (Output) Number of output coordinate pairs (filled by VDI) |
| 3 | Number of integer inputs (entries in VDIINTIN) |
| 4 | (Output) Number of integer outputs (filled by VDI) |
| 5 | Sub-function number (e.g., 1 for v_bar, v_circle, etc.) |
| 6 | VDI workstation handle |

### AES Examples

```
10 REM === Initialize AES application ===
20 AESCTRL 0, 10, 1, 0, 2, 1, 3, 0, 4, 0  : REM appl_init: 0 in, 1 out
30 AES
40 ap_id% = AESINTOUT(0)                     : REM Application ID returned
50 PRINT "App ID:"; ap_id%
```

```
10 REM === Display an alert box ===
20 a$ = "[1][Hello from BASIC!|Line 2 of alert][OK|Cancel]"
30 AESCTRL 0, 52, 1, 1, 2, 1, 3, 1, 4, 0   : REM form_alert
40 AESINTIN 0, 1                              : REM Default button = 1
50 AESADRIN 0, VARPTR(a$)                     : REM Pointer to alert string
60 AES
70 button% = AESINTOUT(0)                     : REM 1=OK, 2=Cancel
80 PRINT "Button pressed:"; button%
```

```
10 REM === Get mouse position (no wait) ===
20 AESCTRL 0, 79, 1, 0, 2, 5, 3, 0, 4, 0   : REM graf_mkstate
30 AES
40 PRINT "X:"; AESINTOUT(1); " Y:"; AESINTOUT(2); " Buttons:"; AESINTOUT(3)
```

### VDI Examples

```
10 REM === Draw a polyline (2 points = 1 line segment) ===
20 VDICTRL 0, 6, 1, 2, 6, handle%   : REM v_pline, 2 points
30 VDIPTSIN 0, 10                     : REM x1
40 VDIPTSIN 1, 10                     : REM y1
50 VDIPTSIN 2, 200                    : REM x2
60 VDIPTSIN 3, 150                    : REM y2
70 VDI
```

```
10 REM === Draw a filled rectangle (v_bar) ===
20 VDICTRL 0, 11, 1, 2, 5, 1, 6, handle%   : REM v_bar (func 11, sub 1)
30 VDIPTSIN 0, 50                     : REM x1 (top-left)
40 VDIPTSIN 1, 50                     : REM y1
50 VDIPTSIN 2, 200                    : REM x2 (bottom-right)
60 VDIPTSIN 3, 150                    : REM y2
70 VDI
```

```
10 REM === Output text at position (v_gtext) ===
20 msg$ = "Hello"
30 VDICTRL 0, 8, 1, 1, 3, LEN(msg$), 6, handle%  : REM v_gtext
40 VDIPTSIN 0, 50                     : REM x position
50 VDIPTSIN 1, 100                    : REM y position
60 FOR i% = 0 TO LEN(msg$) - 1
70   VDIINTIN i%, ASC(MID$(msg$, i%+1, 1))    : REM character codes
80 NEXT i%
90 VDI
```

---

## 17. Graphics

### LINE / LINE2

```
LINE2 x1, y1, x2, y2
```

Draws a line from point (x1, y1) to point (x2, y2) using the Atari ST Line-A interface (opcode $A003). All coordinates are integers representing pixel positions.

**Token system note:** In the source code, the LINE command is defined in the TOKEN2 extended command class with keyword string `"line2"`. Analysis of the tokenizer suggests that typing `LINE2` (with the digit) may be required. `LINE3` also works (TOKEN3, same handler). If `LINE` alone does not work, use `LINE2`. See BASIC-ANALYSIS.md Section 3 for the technical details.

```
10 LINE2 0, 0, 319, 199   REM Diagonal across the screen
20 LINE2 0, 199, 319, 0   REM Second diagonal (X shape in XOR mode)
```

### Default Line-A Settings

The interpreter initializes Line-A at startup with these settings:

| Setting | Value | Effect |
|---------|-------|--------|
| Foreground color | 1 | Black (in monochrome mode) |
| Line style mask | $FFFF | Solid line (no pattern/dashing) |
| Write mode | 1 (XOR) | Drawing twice on the same pixels erases the line |
| Last pixel | -1 (draw) | Draw the final pixel of the line |

**Important:** The default XOR write mode means that drawing the same line twice will erase it (the pixels are toggled). This is useful for rubber-band drawing but may be unexpected if you want persistent lines.

### Changing Line-A Settings with LPOKE

The Line-A variable block is initialized at startup and its base address is stored internally. To modify drawing settings, use WPOKE (16-bit write) on the Line-A variable offsets:

| Offset | Setting | Values |
|--------|---------|--------|
| $22 | Line style mask | $FFFF = solid, $FF00 = dashed, $F0F0 = dotted, etc. |
| $24 | Write mode | 0 = replace (overwrite), 1 = XOR (toggle), 2 = transparent, 3 = reverse transparent |
| $18 | Foreground color plane 0 | 0 or 1 |

**Note:** To access Line-A variables from BASIC, you need the base address of the Line-A variable block, which the interpreter stores internally. Advanced users can obtain it via `XBIOS(38, ...)` (Supexec) or by reading it from the interpreter's memory.

For a complete reference of all Line-A opcodes ($A000-$A00F) and variable offsets, see **BASIC-GEM_VDI_LINEA.md**, Section 4.

### Drawing Shapes

Since only a line-drawing primitive is built in, rectangles and other shapes must be composed from individual LINE2 calls:

```
10 REM Draw a rectangle
20 LINE2 50, 50, 200, 50    : REM Top
30 LINE2 200, 50, 200, 150  : REM Right
40 LINE2 200, 150, 50, 150  : REM Bottom
50 LINE2 50, 150, 50, 50    : REM Left
```

For filled shapes, circles, arcs, and other advanced graphics, use the VDI functions (see Section 16 and **BASIC-GEM_VDI_LINEA.md**).

### Hands-On: Starburst Pattern

Draws a starburst of lines radiating from the screen center using LINE2 and trigonometry. Run it twice without CLS to see the XOR erase effect.

```basic
10  REM === Starburst ===
20  CLS
30  cx% = 319 : cy% = 199
40  FOR d% = 0 TO 350 STEP 10
50    r = d% * pi / 180
60    ex% = cx% + INT(COS(r) * 180)
70    ey% = cy% + INT(SIN(r) * 180)
80    LINE2 cx%, cy%, ex%, ey%
90  NEXT d%
100 REM --- Border ---
110 LINE2 0, 0, 639, 0
120 LINE2 639, 0, 639, 399
130 LINE2 639, 399, 0, 399
140 LINE2 0, 399, 0, 0
```

**What to try:** Change STEP 10 to STEP 5 for a denser pattern. Run the program twice without CLS to see the XOR erase effect (the starburst disappears). Change the radius from 180 to a variable and animate it in a loop.

---

## 18. Debugging

### TRON

```
TRON
```

Enables trace mode. When tracing is active, before each statement is executed, the interpreter displays the current line number and the text of the current command at the top of the screen (row 0), then waits for a keypress before continuing. Pressing ALT+UNDO during a trace step stops the program.

### TROFF

```
TROFF
```

Disables trace mode.

### TRACE

TRACE is used in conjunction with ON TRACE GOSUB (see Control Flow section). It is not a standalone command. The TRACE keyword appears in the token list as part of the ON TRACE GOSUB syntax.

When a trace GOSUB is active:
1. The current line number and statement text are displayed.
2. The interpreter performs GOSUB to the trace handler line.
3. When RETURN is executed in the trace handler, tracing resumes.

### DUMP

```
DUMP
DUMP flags%
```

Displays the values of all defined variables. Without an argument, all variable types are dumped. With a flags argument, specific types can be selected using a bitmask:

| Bit | Value | Type |
|-----|-------|------|
| 0 | 1 | Float variables |
| 1 | 2 | Integer variables |
| 2 | 4 | String variables |
| 3 | 8 | Array variables |
| 4 | 16 | Only show variables with non-zero/non-empty values |

Examples:
- `DUMP` -- Default: bitmask 31 = show all types including arrays, but **only non-zero/non-empty values** (bit 4 is set by default)
- `DUMP 7` -- Show all float, int, and string variables (including zeros), but skip arrays
- `DUMP 1` -- Show only float variables (including zeros)
- `DUMP 2` -- Show only integer variables (including zeros)
- `DUMP 4` -- Show only string variables (including empty strings)
- `DUMP 8` -- Show only array variables (including zero elements)
- `DUMP 16+1` -- Show only non-zero float variables
- `DUMP 31` -- Same as bare `DUMP`: all types, non-zero filter on

**Note:** The default `DUMP` (no argument) includes the non-zero filter (bit 4 = 16). To see variables with zero values, use a bitmask without bit 4, e.g., `DUMP 7` for all scalar types including zeros.

Output format: `varname! = value` (with `!` for float, `%` for integer, `$` for string). Array variables are displayed element by element with full subscripts, e.g., `arr(0,1,2)! = 3.14`. Procedure, function, and DEF FN internal variables are always hidden.

The dump can be interrupted with ALT+UNDO.

### HELP

```
HELP
```

Lists all available keywords, operators, and special symbols. The output includes all token names, system variable names, operators, and special command forms (like `PRINT#`, `INPUT#`, `GET#`). Keywords are displayed at tab stops for readability.

### Hands-On: Interactive Calculator with DUMP

A simple expression calculator that evaluates user input as math expressions using FUNCTION, stores results in an array, and uses DUMP to inspect all variable state. Demonstrates the debugging workflow.

```basic
10  REM === Calculator with DUMP ===
20  PRINT "Enter expressions (or DUMP, QUIT)."
30  count% = 0
40  DIM results(20)
50  INPUT "calc> "; e$
60  IF e$ = "QUIT" THEN END
70  IF e$ = "DUMP" THEN DUMP: GOTO 50
80  count% = count% + 1
90  results(count%) = FUNCTION(e$)
100 PRINT "= "; results(count%)
110 GOTO 50
```

**What to try:** Enter expressions like `2^10`, `SIN(pi/4)`, `SQR(2)`. Type `DUMP` to see all variables and their values. Try `DUMP 2` to show only integer variables, or `DUMP 4` for only strings (see Section 18 reference above for the bitmask flags).

---

## 19. Error Messages

When an error occurs, the interpreter displays:

```
? <error text> error
```

If the error occurred during program execution, it also shows:

```
 in line <number>
```

followed by a listing of the offending line.

### Complete Error Code Reference

| Code | Message | Description |
|------|---------|-------------|
| 0 | syntax | General syntax error. The interpreter could not parse the statement. |
| 1 | type mismatch | Operation attempted between incompatible types (e.g., adding a string to a number). |
| 2 | invalid operand | The floating-point emulator encountered an invalid operand. |
| 3 | inexact result | The floating-point result could not be represented exactly. |
| 4 | square root of negative | SQR was called with a negative argument. |
| 5 | log of negative number | LOG or LN was called with a non-positive argument. |
| 6 | overflow | A numeric operation produced a result too large to represent. |
| 7 | underflow | A numeric operation produced a result too small to represent (treated as zero). |
| 8 | division by zero | A division by zero was attempted. |
| 9 | bad subscript | An array index is out of the declared bounds. |
| 10 | out of variable space | No more memory available for storing variables. The variable/string heap is full. |
| 11 | re-define | Attempted to DIM an array or DEF FN/PROC that is already defined. |
| 12 | dim | Too many dimensions in a DIM statement (more than 10). |
| 13 | out of program space | No more memory available for storing program lines. |
| 14 | file create | A GEMDOS file creation operation failed. |
| 15 | file write | A GEMDOS file write operation failed. |
| 16 | file open | A GEMDOS file open operation failed (file not found or permission denied). |
| 17 | file read | A GEMDOS file read operation failed. |
| 18 | illegal direct | A program-only command was used in direct mode (e.g., RETURN, ELSE, DATA, RESTORE, LOCAL, ENDPROC). |
| 19 | next without for | NEXT was encountered without a matching FOR. |
| 20 | for-next overflow | Too many nested FOR/NEXT loops (more than 100). |
| 21 | illegal prg. mode | A direct-mode-only command was used in a running program (e.g., NEW, CONT, DELETE, AUTO). |
| 22 | return without gosub | RETURN was encountered without a matching GOSUB. |
| 23 | gosub-return overflow | Too many nested GOSUB calls (more than 100). |
| 24 | procedure overflow | Too many nested procedure calls, or too many procedures defined (limit 511). |
| 25 | if-then-else overflow | Too many nested IF statements (more than 100). |
| 26 | prg stopped | Program was halted by STOP statement or ALT+UNDO. |
| 27 | too many files open | More than 100 files are open simultaneously. |
| 28 | already open | Attempted to OPEN a handle that is already in use. |
| 29 | out of data | READ was executed but no more DATA values are available. |
| 30 | can't continue | CONT was attempted but the program cannot be resumed (program was modified or never stopped). |
| 31 | improper use of system variable | Attempted to write to a read-only system variable (pi), or used a system variable in a disallowed context. |
| 32 | improper function number | The function number passed to GEMDOS, BIOS, or XBIOS is out of the supported range. |
| 33 | variable not yet defined | VARPTR was called on a variable that has not been assigned a value. |
| 34 | procedure not defined | Attempted to call a procedure that has not been defined with DEF PROC. |
| 35 | endproc without proc | ENDPROC was encountered without a matching procedure call. |
| 36 | line numbers missing | During CONVERT, a line without a line number was encountered. |
| 37 | line too long | During CONVERT, a line exceeded the maximum allowed length. |
| 38 | no negative arg allowed | A function received a negative argument where only non-negative values are permitted (e.g., negative array index, negative DIM size). |
| 39 | no arg allowed | An argument was provided where none is permitted (e.g., array parameter in FN definition). |
| 40 | too many args | More arguments were provided than the function/procedure/AES/VDI array can accept. |
| 41 | out of field range | An AES or VDI array index is out of the permitted range. |
| 42 | arg < 1 | An argument that must be at least 1 was 0 or negative (e.g., TAB, SPC, EDTAB). |
| 43 | cursor out of range | CURSOR or TAB was given coordinates outside the screen bounds. |
| 44 | odd address access | WPEEK, WPOKE, LPEEK, LPOKE, or SYS was called with an odd (non-word-aligned) address. |
| 45 | position not within string | MID$, LEFT$, RIGHT$, or INSTR$ was given a position that exceeds the string length. |
| 46 | can't find line number | GOTO, GOSUB, RUN, or RESTORE referenced a line number that does not exist in the program. (Note: the actual message displayed has a typo: "cant't" with a double apostrophe.) |
| 47 | arg too big | A numeric argument exceeded the maximum allowed value (e.g., file handle > 65535). |
| 48 | fn not defined | FN was called for a function that has not been defined with DEF FN. |
| 49 | missing arg(s) | A function or procedure was called with too few arguments. |
| 50 | local definition | Attempted to define a LOCAL variable with an invalid name (array, system variable, etc.). |
| 51 | illegal use as command | A function-only keyword was used as a command (without using its return value). |
| 52 | else without for | ELSE was encountered without a matching IF on the previous line. (Note: the error string says "for" but it means "if".) |
| 53 | missing then | An IF statement was written without the required THEN keyword. |
| 54 | missing to | A FOR statement was written without the required TO keyword. |
| 55 | illegal use as function | A command-only keyword was used in an expression context. |
| 56 | out of string space | The string heap is full and garbage collection could not free enough space. |
| 57 | for without next | The program ended with an open FOR loop that was never closed by NEXT. |
| 58 | gosub without return | The program ended with a pending GOSUB that was never closed by RETURN. |
| 59 | proc without endproc | The program ended with a procedure call that was never closed by ENDPROC. |
| 60 | missing gosub | ON TRACE was used without GOSUB following it. |
| 61 | no such handle known | CLOSE was called with a handle that is not in the open file table. |
| 62 | no BASIC file format | LOAD or MERGE encountered a file that does not begin with the "HEAD" header. |
| 63 | improper procedure definition | DEF PROC was followed by invalid syntax (not a proper procedure definition). |

---

## 20. Quick Reference

### Program Control ([Section 7](#7-control-flow))

| Keyword | Type | Syntax / Result | Description |
|---------|------|-----------------|-------------|
| RUN | Command | `RUN [line]` | Start execution (from line, or first line). Clears all variables first |
| STOP | Command | `STOP` | Halt program, preserving state for CONT |
| END | Command | `END` | Terminate program |
| CONT | Direct only | `CONT` | Continue after STOP or ALT+UNDO |
| NEW | Direct only | `NEW` | Erase program and all variables |
| CLR | Command | `CLR [var, ...]` | Clear all variables (or listed variables to zero) |
| GOTO | Command | `GOTO line` | Unconditional jump |
| GOSUB | Command | `GOSUB line` | Call subroutine; paired with RETURN |
| RETURN | Program only | `RETURN` | Return from GOSUB |
| IF...THEN | Command | `IF expr THEN stmt` | Execute stmt if expr is non-zero. ELSE must be on the next line |
| ELSE | Program only | `ELSE stmt` | Alternative branch (must follow IF/THEN on preceding line) |
| FOR...TO...STEP | Command | `FOR v=s TO e [STEP i]` | Counting loop; default STEP is 1. Max 100 nested |
| NEXT | Command | `NEXT [var]` | End of FOR loop |
| ON | Command | `ON expr GOTO/GOSUB l1,l2,...` | Computed branch: value 1 -> first line, 2 -> second, etc. |

### Procedures and Functions ([Section 8](#8-procedures-and-functions))

| Keyword | Type | Syntax / Result | Description |
|---------|------|-----------------|-------------|
| DEF PROC | Command | `DEF PROC name[(p1, p2$, ...)]` | Define named procedure. Max 511 procedures |
| PROC | Command | `PROC name[(args)]` or `name(args)` | Call procedure. Parameters passed by value |
| ENDPROC | Program only | `ENDPROC` | End procedure, return to caller |
| LOCAL | Program only | `LOCAL var1, ...` / `LOCAL DIM a(n)` | Declare local variables/arrays (shadow globals) |
| DEF FN | Command | `DEF FN name[(params)] = expr` | Define single-line function |
| FN | Function | `FN name[(args)]` -> value | Call user function; returns expression result |

### Program Management ([Section 3](#3-program-management))

| Keyword | Type | Syntax / Result | Description |
|---------|------|-----------------|-------------|
| LIST | Command | `LIST [start[, end]]` | Display program listing |
| DELETE | Direct only | `DELETE [start[, end]]` | Delete lines; also clears variables |
| SAVE | Command | `SAVE "file"[, start, end]` | Save program (binary "HEAD" format) |
| LOAD | Command | `LOAD "file"` | Load program (replaces current) |
| MERGE | Command | `MERGE "file"` | Merge file into current program |
| CONVERT | Command | `CONVERT "file"` | Import ASCII text BASIC source |
| AUTO | Direct only | `AUTO [start[, incr]]` | Auto line numbering (default 100, 10) |
| REM | Command | `REM text` or `' text` | Comment (rest of line ignored) |

### Input/Output ([Section 11](#11-inputoutput))

| Keyword | Type | Syntax / Result | Description |
|---------|------|-----------------|-------------|
| PRINT | Command | `PRINT [#h,] expr[; expr][, expr]` | Output values. `;` = no separator, `,` = tab. `?` = shorthand |
| INPUT | Command | `INPUT [#h,] ["prompt";] var[, ...]` | Read values from keyboard or file |
| GET | Command | `GET [#h,] var$` | Read single character (non-blocking for keyboard) |
| CLS | Command | `CLS` | Clear screen, cursor to home |
| CURSOR | Command | `CURSOR [col, row]` | Position cursor (1-based); no args = home |
| TAB | Function | `TAB(col)` -> positions cursor | Move to absolute column (1-based) in PRINT |
| SPC | Function | `SPC(n)` -> outputs spaces | Output n spaces in PRINT |
| EDTAB | Function | `EDTAB(n)` -> advances cursor | Advance n editor tab stops in PRINT |
| POS | Function | `POS(x)` -> int | Current cursor column (arg ignored) |
| CMD | Command | `CMD handle` | Redirect PRINT output to file handle |

### String Functions ([Section 9](#9-string-functions))

| Keyword | Type | Syntax / Result | Description |
|---------|------|-----------------|-------------|
| LEN | Function | `LEN(s$)` -> int | String length |
| MID$ | Function | `MID$(s$, pos, len)` -> string | Substring (1-based position) |
| LEFT$ | Function | `LEFT$(s$, n)` -> string | Leftmost n characters |
| RIGHT$ | Function | `RIGHT$(s$, n)` -> string | Rightmost n characters |
| INSTR$ | Function | `INSTR$(s$, t$[, start])` -> int | Find t$ in s$; returns position or 0 |
| ASC | Function | `ASC(s$)` -> int | ASCII code of first character |
| CHR$ | Function | `CHR$(n)` -> string | Character from ASCII code |
| VAL | Function | `VAL(s$)` -> float | Parse string as number |
| STR$ | Function | `STR$(n)` -> string | Number to string (with leading space) |
| HEX$ | Function | `HEX$(n)` -> string | Integer to hex string (prefixed `$`) |
| BIN$ | Function | `BIN$(n)` -> string | Integer to binary string (prefixed `%`) |
| INKEY$ | Function | `INKEY$` -> string | Read key without waiting; `""` if none |

### Math Functions ([Section 10](#10-math-functions))

| Keyword | Type | Syntax / Result | Description |
|---------|------|-----------------|-------------|
| INT | Function | `INT(x)` -> int | Truncate to integer |
| ABS | Function | `ABS(x)` -> same type | Absolute value |
| SGN | Function | `SGN(x)` -> int | Sign: -1, 0, or 1 |
| SQR | Function | `SQR(x)` -> float | Square root (x must be >= 0) |
| SIN | Function | `SIN(x)` -> float | Sine (radians) |
| COS | Function | `COS(x)` -> float | Cosine (radians) |
| TAN | Function | `TAN(x)` -> float | Tangent (radians) |
| ATN | Function | `ATN(x)` -> float | Arc tangent (result in radians) |
| ATANPT | Function | `ATANPT(y, x)` -> float | Two-argument arc tangent (all quadrants) |
| LOG | Function | `LOG(x)` -> float | Log base 10 (x must be > 0) |
| LN | Function | `LN(x)` -> float | Natural log (x must be > 0) |
| EXP | Function | `EXP(x)` -> float | e^x |
| EXP10 | Function | `EXP10(x)` -> float | 10^x |
| RND | Function | `RND(x)` -> float | Random: 0=repeat last, 1=next, other=seed |
| MOD | Function | `MOD(x, y)` -> float | Floating-point remainder |
| NOT | Function | `NOT(x)` -> int | Bitwise NOT (32-bit) |

### File I/O ([Section 12](#12-file-io))

| Keyword | Type | Syntax / Result | Description |
|---------|------|-----------------|-------------|
| OPEN | Command | `OPEN handle, "file"` | Open existing file (handle > 5, no `#` prefix) |
| CREATE | Command | `CREATE handle, "file"` | Create/overwrite file (handle > 5, no `#` prefix) |
| CLOSE | Command | `CLOSE handle` | Close file (no `#` prefix; handles 0-5 ignored) |
| DIR | Command | `DIR ["path"]` | Directory listing (supports wildcards) |

### Data Statements ([Section 13](#13-datareadrestore))

| Keyword | Type | Syntax / Result | Description |
|---------|------|-----------------|-------------|
| DATA | Program only | `DATA v1, v2, ...` | Store constants (numeric or string) for READ |
| READ | Command | `READ var[, var, ...]` | Read next DATA value into variable |
| RESTORE | Program only | `RESTORE [line]` | Reset DATA pointer (to start or specific line) |

### Memory and System ([Section 14](#14-memory-and-system-access))

| Keyword | Type | Syntax / Result | Description |
|---------|------|-----------------|-------------|
| PEEK | Function | `PEEK(addr)` -> int | Read byte (-128..127, sign-extended) |
| POKE | Command | `POKE addr, val` | Write byte (low 8 bits) |
| WPEEK | Function | `WPEEK(addr)` -> int | Read 16-bit word (even addr required) |
| WPOKE | Command | `WPOKE addr, val` | Write 16-bit word (even addr required) |
| LPEEK | Function | `LPEEK(addr)` -> int | Read 32-bit long (even addr required) |
| LPOKE | Command | `LPOKE addr, val` | Write 32-bit long (even addr required) |
| VARPTR | Function | `VARPTR(var)` -> int | Memory address of variable's storage |
| FRE | Function | `FRE(x)` -> int | Free variable space; 0=with GC, 1=without GC |
| STRFRE | Function | `STRFRE(x)` -> int | Free string heap space (always runs GC) |
| SWAP | Command | `SWAP var1, var2` | Exchange values (auto type-converts int/float) |
| SYS | Command | `SYS(addr)` | Call machine code at addr (must end with RTS) |
| CALL | Function | `CALL(addr[, val, ..., *adr, ...])` -> int | Call machine code with D0-D7/A0-A6 registers; returns D0 |
| FUNCTION | Function | `FUNCTION(s$)` -> float | Evaluate string as numeric expression |
| WAIT | Command | `WAIT n` | Pause n VBL frames (~1/70s mono, ~1/50s PAL) |

### System Calls ([Section 15](#15-gemdosbiosxbios); see BASIC-GEMDOS_BIOS_XBIOS.md for full function tables)

| Keyword | Type | Syntax / Result | Description |
|---------|------|-----------------|-------------|
| GEMDOS | Function | `GEMDOS(fn[, args])` -> int | Call GEMDOS trap #1. 51 functions. Negative return = error |
| BIOS | Function | `BIOS(fn[, args])` -> int | Call BIOS trap #13. Functions 0-11 |
| XBIOS | Function | `XBIOS(fn[, args])` -> int | Call XBIOS trap #14. Functions 0-39 |

### AES/VDI ([Section 16](#16-aesvdi-access); see BASIC-GEM_VDI_LINEA.md for full function reference)

| Keyword | Type | Syntax / Result | Description |
|---------|------|-----------------|-------------|
| AESCTRL | Cmd/Fn | `AESCTRL idx,val[,...]` / `AESCTRL(idx)` -> int | AES control array (10 words): [0]=opcode, [1]=sintin, [2]=sintout, [3]=saddrin, [4]=saddrout |
| AESINTIN | Command | `AESINTIN idx, val[, ...]` | AES integer input array (128 words) |
| AESINTOUT | Function | `AESINTOUT(idx)` -> int | AES integer output array (128 words) |
| AESADRIN | Command | `AESADRIN idx, val[, ...]` | AES address input array (128 longs) |
| AESADROUT | Function | `AESADROUT(idx)` -> int | AES address output array (128 longs) |
| AES | Command | `AES` | Execute AES call (trap #2, opcode $C8) |
| VDICTRL | Cmd/Fn | `VDICTRL idx,val[,...]` / `VDICTRL(idx)` -> int | VDI control (12 words): [0]=opcode, [1]=ptsin, [3]=intin, [5]=sub, [6]=handle |
| VDIINTIN | Command | `VDIINTIN idx, val[, ...]` | VDI integer input array (128 words) |
| VDIINTOUT | Function | `VDIINTOUT(idx)` -> int | VDI integer output array (128 words) |
| VDIPTSIN | Command | `VDIPTSIN idx, val[, ...]` | VDI coordinate input array (128 words, x/y pairs) |
| VDIPTSOUT | Function | `VDIPTSOUT(idx)` -> int | VDI coordinate output array (128 words) |
| VDI | Command | `VDI` | Execute VDI call (trap #2, opcode $73) |

### Graphics ([Section 17](#17-graphics); see BASIC-GEM_VDI_LINEA.md Section 4 for Line-A details)

| Keyword | Type | Syntax / Result | Description |
|---------|------|-----------------|-------------|
| LINE2 / LINE3 | Command | `LINE2 x1, y1, x2, y2` | Draw line via Line-A ($A003). Default: solid, XOR mode, black |

### Debugging ([Section 18](#18-debugging))

| Keyword | Type | Syntax / Result | Description |
|---------|------|-----------------|-------------|
| TRON | Command | `TRON` | Enable trace mode (step through with keypress) |
| TROFF | Command | `TROFF` | Disable trace mode |
| TRACE | Keyword | `ON TRACE GOSUB line` | Register trace handler subroutine |
| DUMP | Command | `DUMP [flags%]` | Display variables. Flags bitmask: 1=float, 2=int, 4=string, 8=array, 16=non-zero only |
| HELP | Command | `HELP` | List all keywords and operators |

### Operators

| Symbol | Priority | Description |
|--------|----------|-------------|
| `{` | 1 | Shift left |
| `}` | 2 | Shift right |
| `~` / `EOR` | 3 | Bitwise XOR |
| `&` / `AND` | 4 | Bitwise AND |
| `\|` / `OR` | 5 | Bitwise OR |
| `<` `<=` `<>` | 6 | Less than / less-equal / not-equal |
| `=` | 7 | Equal |
| `>` `>=` | 8 | Greater than / greater-equal |
| `+` | 9 | Add / concatenate |
| `-` | 10 | Subtract |
| `*` | 11 | Multiply |
| `/` | 12 | Divide |
| `^` | 13 | Exponentiate |

### System Variables

| Name | Type | Description |
|------|------|-------------|
| `pi` | Float (read-only) | 3.14159265358979... |
| `ti` | Integer (read/write) | VBL frame counter (~70 Hz, from $466 = _frclock) |
| `ti$` | String (read/write) | Time as HH:MM:SS (with colons) |

### Special Syntax

| Syntax | Meaning |
|--------|---------|
| `?` | Shorthand for PRINT |
| `'` | Shorthand for REM |
| `#` between name and type suffix | Force global scope in procedure (`x#%`, `a#(0)`, `val#`) |
| `$` prefix on number | Hexadecimal literal |
| `%` prefix on number | Binary literal |
| `!` on empty line | Exit interpreter |

### Complete Keyword Abbreviation Table

Most keywords can be abbreviated. The **Min** column shows the shortest accepted form. Keywords marked with `(full)` must be typed in full.

| Keyword | Min | | Keyword | Min | | Keyword | Min |
|---------|-----|---|---------|-----|---|---------|-----|
| ABS | ab | | AES | ae | | AESADRIN | aesadri |
| AESADROUT | aesadro | | AESCTRL | aesc | | AESINTIN | aesinti |
| AESINTOUT | aesinto | | AND | an | | ASC | as |
| ATANPT | ata | | ATN | at | | AUTO | au |
| BIN$ | bi | | BIOS | bi | | CALL | ca |
| CHR$ | ch | | CLOSE | cl | | CLR | (full) |
| CLS | (full) | | CMD | cm | | CONT | co |
| CONVERT | con | | COS | (full) | | CREATE | cr |
| CURSOR | cu | | DATA | da | | DEF | de |
| DELETE | del | | DIM | di | | DIR | (full) |
| DUMP | du | | EDTAB | ed | | ELSE | el |
| END | (full) | | ENDPROC | en | | EOR | eo |
| EXP | ex | | EXP10 | exp | | FN | (full) |
| FOR | fo | | FRE | fr | | FUNCTION | fu |
| GEMDOS | gem | | GET | ge | | GOSUB | gos |
| GOTO | go | | HELP | he | | HEX$ | hex |
| IF | (full) | | INKEY$ | ink | | INPUT | in |
| INSTR$ | ins | | INT | int | | LEFT$ | lef |
| LEN | le | | LINE | *(special)* | | LIST | li |
| LN | (full) | | LOAD | lo | | LOCAL | loc |
| LOG | (full) | | LPEEK | lpe | | LPOKE | lpo |
| MERGE | me | | MID$ | mi | | MOD | mo |
| NEW | ne | | NEXT | ne | | NOT | no |
| ON | (full) | | OPEN | op | | OR | (full) |
| PEEK | pe | | POKE | po | | POS | (full) |
| PRINT | (full) | | PROC | pro | | READ | rea |
| REM | re | | RESTORE | res | | RETURN | ret |
| RIGHT$ | ri | | RND | rn | | RUN | ru |
| SAVE | sa | | SGN | sg | | SIN | si |
| SPC | sp | | SQR | sq | | STEP | st |
| STOP | sto | | STR$ | str | | STRFRE | strf |
| SWAP | sw | | SYS | sy | | TAB | ta |
| TAN | ta | | THEN | th | | TO | (full) |
| TRACE | tra | | TROFF | tro | | TRON | tr |
| VAL | va | | VARPTR | varp | | VDI | vd |
| VDICTRL | vdic | | VDIINTIN | vdiinti | | VDIINTOUT | vdiinto |
| VDIPTSIN | vdiptsi | | VDIPTSOUT | vdiptso | | WAIT | wa |
| WPEEK | wpe | | WPOKE | wpo | | XBIOS | xb |

**Note:** Some abbreviations share a prefix. The tokenizer matches keywords in table order, so the first match wins. For example, `ne` matches NEXT (not NEW) because NEXT appears earlier in the token table. To type NEW, you must use `new` in full. Similarly, `st` matches STEP (not STOP or STR$), so use `sto` for STOP and `str` for STR$.

---

## 21. Cheat Sheet

Condensed syntax reference. For keyword descriptions, see Section 20. For error details, see Section 19.

### Command Syntax

| Category | Syntax |
|----------|--------|
| **Run** | `RUN [line]`  `CONT`  `STOP`  `END` |
| **Edit** | `NEW`  `CLR [vars]`  `LIST [s[,e]]`  `DELETE [s[,e]]`  `AUTO [s[,inc]]` |
| **File** | `SAVE "f"[,s,e]`  `LOAD "f"`  `MERGE "f"`  `CONVERT "f"` |
| **I/O** | `OPEN h,"f"`  `CREATE h,"f"`  `CLOSE h`  `DIR ["path"]`  `CMD h` |
| **Print** | `PRINT [#h,] expr`  `? expr`  `CLS`  `CURSOR [c,r]` |
| **Input** | `INPUT [#h,] ["prompt";] var`  `GET [#h,] var$` |
| **Flow** | `GOTO ln`  `GOSUB ln`  `RETURN`  `ON expr GOTO/GOSUB ln,ln,...` |
| **Cond** | `IF expr THEN stmt` / next line: `ELSE stmt` |
| **Loop** | `FOR v=s TO e [STEP i]` ... `NEXT [v]` |
| **Proc** | `DEF PROC name[(params)]` ... `ENDPROC`  `PROC name[(args)]`  `LOCAL vars` |
| **Func** | `DEF FN name[(params)] = expr`  `FN name[(args)]` |
| **Data** | `DATA v,v,...`  `READ var[,var,...]`  `RESTORE [line]` |
| **Mem** | `PEEK(a)`  `POKE a,v`  `WPEEK(a)`  `WPOKE a,v`  `LPEEK(a)`  `LPOKE a,v` |
| **Sys** | `SYS(addr)`  `CALL(addr[,val,...,*addr,...])`  `SWAP v1,v2`  `WAIT n` |
| **Trap** | `GEMDOS(fn,args)`  `BIOS(fn,args)`  `XBIOS(fn,args)` |
| **GEM** | `AES`/`VDI` + ctrl/intin/intout/adrin/adrout/ptsin/ptsout arrays |
| **Gfx** | `LINE2 x1,y1,x2,y2` |
| **Debug** | `TRON`  `TROFF`  `ON TRACE GOSUB ln`  `DUMP [flags]`  `HELP` |

### Function Syntax

| Category | Functions |
|----------|-----------|
| **String** | `LEN(s$)` `MID$(s$,p,n)` `LEFT$(s$,n)` `RIGHT$(s$,n)` `INSTR$(s$,t$[,p])` |
| **Convert** | `ASC(s$)` `CHR$(n)` `VAL(s$)` `STR$(n)` `HEX$(n)` `BIN$(n)` |
| **Math** | `INT(x)` `ABS(x)` `SGN(x)` `SQR(x)` `MOD(x,y)` `NOT(x)` |
| **Trig** | `SIN(x)` `COS(x)` `TAN(x)` `ATN(x)` `ATANPT(y,x)` |
| **Log/Exp** | `LOG(x)` `LN(x)` `EXP(x)` `EXP10(x)` |
| **Other** | `RND(x)` `FRE(x)` `STRFRE(x)` `VARPTR(v)` `FUNCTION(s$)` `POS(x)` `INKEY$` |
| **Output** | `TAB(col)` `SPC(n)` `EDTAB(n)` |

### Key Error Codes

| Code | Message | Code | Message |
|------|---------|------|---------|
| 0 | syntax | 19 | next without for |
| 1 | type mismatch | 22 | return without gosub |
| 8 | division by zero | 26 | prg stopped |
| 9 | bad subscript | 29 | out of data |
| 10 | out of variable space | 34 | procedure not defined |
| 13 | out of program space | 44 | odd address access |
| 16 | file open | 46 | can't find line number |
| 18 | illegal direct | 56 | out of string space |

### Memory Layout

```
[program] [16B gap] [variables →] free [← strings]
```

Variables grow upward, strings grow downward. File handles 0-5 are system devices; user handles > 5 (max 100 open). `OPEN`/`CREATE`/`CLOSE`/`CMD`: no `#` prefix. `PRINT#`/`INPUT#`/`GET#`: require `#` prefix.

---

*This manual was reverse-engineered from the 68000 assembly source code of the BASIC interpreter (BASIC_COMMENTS.S, originally BASIC.S) and editor (EDITOR.S), dated 31.10.88.*
