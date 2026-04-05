*==============================================================================
* BASIC.S - Main Interpreter for Atari ST BASIC
* Date: 31.10.88 / 7.11.88
*
* This is the core interpreter module of a BASIC interpreter for the
* Atari ST, written in Motorola 68000 assembly language.
*
* ARCHITECTURE OVERVIEW:
* - Program lines stored as a linked list (prgbase..prgend)
*   Each line: [4-byte next ptr][4-byte line number][tokenized data]
* - Variables stored as a linked list (varbase..varend)
* - Strings stored BACKWARDS in memory, growing downward from strend
* - Three type system: FLOAT=1, INT=2, STRING=4
* - Token system with 3 token classes ($01xx, $02xx, $03xx)
* - Command dispatch via comadr tables with bit flags for cmd/fkt distinction
* - Editor integration via edi_base structure for screen I/O
*
* KEY MEMORY LAYOUT (low to high):
*   [program lines: prgbase..prgend]
*   [variables: varbase..varend]
*   ... free space ...
*   [strings: strend..strbase] (grows downward)
*==============================================================================

*==============================================================================
* SECTION 1: Editor Structure Offsets and Token/Type Definitions
*==============================================================================

******************************************************************************
* 31.10.88
* struct        fuer Editor
* These EQU definitions mirror the editor's internal data structure.
* The editor module (EDITOR.S) maintains a block of data starting at
* edi_base; these offsets allow BASIC.S to access editor fields such as
* screen dimensions, cursor position, and callback routines.
******************************************************************************
edi_base        equ     0               * Screenadresse (base address of screen memory)
edi_screen      = edi_base+4            * Screenbreite in Bytes (screen width in bytes)
edi_plan        = edi_screen+4          * unused (reserved)
edi_x           = edi_plan+2            * X coordinate of window's top-left corner
edi_y           = edi_x+2              * Y coordinate of window's top-left corner
edi_ext         = edi_y+2              * extent/extra data (4 bytes)
edi_breit       = edi_ext+4             * window width in pixels (Pixelkoord)
edi_hoch        = edi_breit+2           * window height in pixels (Pixelkoord)
edi_maxzeilen   = edi_hoch+2            * max. lines in editor (constant)
edi_maxspalten  = edi_maxzeilen+2      * max. columns in editor (constant)
edi_tab         = edi_maxspalten+2     * tab stop width
edi_print       = edi_tab+2             * Output routine for a single character
*                                         d0=character, d1/d2=pixel coordinates
edi_pgblock     = edi_print+4           * Start address of page layout routines
edi_vrblock     = edi_pgblock+4         * Start address of the variable block
edi_retprg      = edi_vrblock+4         * Program pointer after RET (0=return to basic)
edi_preup		 = edi_retprg+4        * pre-scroll-up callback
edi_up		 = edi_preup+4             * scroll-up callback
edi_predown	 = edi_up+4                * pre-scroll-down callback
edi_down		 = edi_predown+4       * scroll-down callback
edi_font        = edi_down+4          * Font header address pointer
edi_y_shft      = edi_font+4          * Y shift value for font rendering

******************************************************************************
* Global symbols exported for use by other modules (EDITOR.S, BLIBF.S)
******************************************************************************
.globl  ed_chkstop
.globl  b_init,b_enter,b_runcode,chk_stop,b_up,b_down,b_preup,b_predown
.globl  charget6        * fuer blibf (alternate charget returning result in d6)

*==============================================================================
* Constants
*==============================================================================
anzops = 13	* There are 13 operators (+ - * / ^ < = > { } ~ & |)
                * See optoktabl for the complete list
HEADER = $48454144	* Magic number "HEAD" - header marker before BASIC programs on disk

*==============================================================================
* Type flag bit masks for variable type system
* The type word of each variable encodes both its data type (bits 0-2)
* and special flags (bits 12-15) for arrays, functions, and procedures.
*==============================================================================
		ARRAYTYP	=	$8000	* bit 15 - variable is an array
		FNTYP	=	$4000     * bit 14 - variable is a FN argument (local to DEF FN)
		DEFFNTYP  =	$2000	* bit 13 - variable is a DEF FN function definition
		PROCTYP	=	$1000	* bit 12 - variable is a PROC definition

*==============================================================================
* Data type codes (stored in typflag, typvalid, typ2flag)
*==============================================================================
          STRING    =    4         * String type (pointer to backwards-stored string)
          INT       =    2         * 32-bit signed integer
          FLOAT     =    1         * Extended precision floating point (3 longwords: 12 bytes)


*==============================================================================
* Token class intro bytes
* Each tokenized keyword is stored as a 2-byte sequence:
*   byte 1 = TOKEN1/TOKEN2/TOKEN3 (identifies which command table)
*   byte 2 = index within that table
*==============================================================================
		TOKEN1	= 	1		* Token intro byte for primary command set ($01xx)
		TOKEN2	=	2		* Token intro byte for secondary command set ($02xx)
		TOKEN3	=	3		* Token intro byte for tertiary command set ($03xx)

*==============================================================================
* Token Definitions - All 113 BASIC keywords
* Format: TOKEN_NAME = $XXYY where XX=token class, YY=index
*
* Token class 1 ($01xx): Main BASIC commands and functions
* Token class 2 ($02xx): Extended drawing commands
* Token class 3 ($03xx): Additional drawing commands
*
* The command dispatch table (comadr1) uses bit flags in the address:
*   bit 31 ($80000000) = function (returns a value, not a statement)
*   bit 30 ($40000000) = program-only command (illegal in direct mode)
*   bit 29 ($20000000) = direct-mode-only command (illegal in programs)
*   bit 28 ($10000000) = dual command/function (can be used as either)
*   bit 27 ($08000000) = no parenthesis check (function without mandatory '(')
*==============================================================================

* --- I/O and display commands ---
          PRINT     =    $0100    * PRINT - output to screen or file
          CMD       =    $0132    * CMD - redirect output to file handle
          CLS       =    $0143    * CLS - clear screen
          CURSOR    =    $0151    * CURSOR - position cursor at x,y
          SPC       =    $0121    * SPC - output N spaces
          TAB       =    $0122    * TAB - move to column position
          INPUT     =    $011d    * INPUT - read user input into variables
          GET       =    $0126    * GET - read single character from keyboard/file

* --- Variable and memory commands ---
          DIM       =    $0101    * DIM - dimension an array variable
          POKE      =    $0133    * POKE - write byte to memory address
          PEEK      =    $0134    * PEEK - read byte from memory address (function)
          DPOKE     =    $0145    * DPOKE - write word (16-bit) to memory address
          DPEEK     =    $0144    * DPEEK - read word from memory address (function)
          LPOKE     =    $0147    * LPOKE - write longword (32-bit) to memory address
          LPEEK     =    $0146    * LPEEK - read longword from memory address (function)
          VARPTR    =    $014d    * VARPTR - return address of a variable's storage
          FRE       =    $0113    * FRE - return free variable memory (with optional garbage collection)
          STRFRE    =    $0115    * STRFRE - return free string memory

* --- Program storage commands ---
          LIST      =    $0102    * LIST - display program listing
          SAVE      =    $0103    * SAVE - save program to disk
          LOAD      =    $0104    * LOAD - load program from disk
          MERGE     =    $0116    * MERGE - merge program from disk into current
          DELETE	=	$0155    * DELETE - delete range of program lines
          NEW       =    $011a    * NEW - clear program and all variables

* --- Flow control commands ---
          RUN       =    $0105    * RUN - execute program from beginning or specified line
          CLR       =    $0106    * CLR - clear all variables (or specific ones)
          GOTO      =    $0107    * GOTO - unconditional jump to line number
          FOR       =    $0109    * FOR - begin counted loop
          TO        =    $010A    * TO - separator in FOR...TO...STEP
          STEP      =    $010B    * STEP - optional increment in FOR loop
          NEXT      =    $010C    * NEXT - end of FOR loop, increment and test
          GOSUB     =    $010E    * GOSUB - call subroutine at line number
          RETURN    =    $010F    * RETURN - return from GOSUB
          IF        =    $0110    * IF - conditional execution
          THEN      =    $0111    * THEN - required after IF condition
          ELSE      =    $0112    * ELSE - alternative branch of IF (must be on next line)
          ON        =    $011e    * ON - computed GOTO/GOSUB (ON x GOTO/GOSUB lines...)
          STOP      =    $0118    * STOP - halt program execution (can CONT)
          END		=	$0153    * END - end program execution
          CONT      =    $0142    * CONT - continue after STOP

* --- Data commands ---
          DATA      =    $0123    * DATA - inline data values for READ
          READ      =    $0124    * READ - read next DATA value into variable
          RESTORE   =    $0125    * RESTORE - reset DATA pointer to beginning or line

* --- Numeric functions ---
          INT_FKT   =    $0108    * INT() - convert to integer (truncate toward zero)
          SIN       =    $0135    * SIN() - sine (radians)
          COS       =    $0136    * COS() - cosine (radians)
          SQR       =    $0137    * SQR() - square root
          LOG       =    $0138    * LOG() - base-10 logarithm
          LN        =    $0139    * LN() - natural logarithm
          EXP10     =    $013a    * EXP10() - 10^x
          TAN       =    $013b    * TAN() - tangent (radians)
          ATN       =    $013c    * ATN() - arctangent (radians)
          EXP       =    $013d    * EXP() - e^x
          SGN       =    $013e    * SGN() - sign of number (-1, 0, or 1)
          ABS       =    $013f    * ABS() - absolute value
          RND       =    $0140    * RND() - random number
          NOT       =    $0131    * NOT - bitwise NOT (integer)
          POS       =    $0130    * POS() - current cursor column position
          MOD       =    $0149    * MOD() - modulo (positive remainder)
          ATNPT     =    $0148    * ATNPT() - arctangent of point (atan2)

* --- String functions ---
          LEN       =    $0127    * LEN() - length of string
          STRFKT    =    $0128    * STR$() - convert number to string
          VAL       =    $0129    * VAL() - convert string to number
          FUNCTION  =    $012a    * FUNCTION() - alias for VAL
          ASC       =    $012b    * ASC() - ASCII code of first character
          CHR       =    $012c    * CHR$() - character from ASCII code
          LEFT      =    $012d    * LEFT$() - leftmost N characters
          RIGHT     =    $012e    * RIGHT$() - rightmost N characters
          MID       =    $012f    * MID$() - substring from position
          INSTR	=	$015b    * INSTR() - find substring position
          INKEY	=	$0156    * INKEY$() - read key without waiting (function)
          HEX       =    $014f    * HEX$() - convert integer to hex string
          BIN       =    $0150    * BIN$() - convert integer to binary string

* --- Procedure/Function definition ---
          DEFFN     =    $011b    * DEF FN / DEF PROC - define function or procedure
          FN        =    $011c    * FN - call user-defined function
		PROC		=	$0152    * PROC - call user-defined procedure
		ENDPROC   =    $010D    * ENDPROC - end of procedure body
		LOCAL	=	$0154    * LOCAL - declare local variables in a procedure

* --- File I/O ---
          CREATE    =    $0114    * CREATE - create and open a new file
          OPEN      =    $011f    * OPEN - open existing file
          CLOSE     =    $0120    * CLOSE - close file handle

* --- System interface ---
          SYS       =    $0141    * SYS - jump to machine code address
          GEMDOS    =    $014a    * GEMDOS() - call GEMDOS trap #1 function
          BIOS      =    $014b    * BIOS() - call BIOS trap #13 function
          XBIOS     =    $014c    * XBIOS() - call XBIOS trap #14 function
		CALL		=	$015c    * CALL() - call machine code with register parameters
          DIR       =    $014e    * DIR - display directory listing

* --- AES/VDI GEM interface ---
		AESCTRL	=	$015d    * AESCTRL - read/write AES control array
		AESINTIN	=	$015e    * AESINTIN - write AES integer input array
		AESINTOUT	=	$015f    * AESINTOUT - read AES integer output array
		AESADRIN	=	$0160    * AESADRIN - write AES address input array
		AESADROUT	=	$0161    * AESADROUT - read AES address output array
		VDICTRL	=	$0162    * VDICTRL - read/write VDI control array
		VDIINTIN	=	$0163    * VDIINTIN - write VDI integer input array
		VDIINTOUT	=	$0164    * VDIINTOUT - read VDI integer output array
		VDIPTSIN	=	$0165    * VDIPTSIN - write VDI points input array
		VDIPTSOUT	=	$0166    * VDIPTSOUT - read VDI points output array
		AES		=	$0167    * AES - execute AES call with inline parameters
		VDI		=	$0168    * VDI - execute VDI call with inline parameters

* --- Miscellaneous ---
          HELP      =    $0119    * HELP - list all available commands
          REM       =    $0117    * REM - remark/comment (rest of line ignored)
		CONVERT	=	$0169    * CONVERT - import ASCII text file as BASIC program
		DUMP		=	$016a    * DUMP - display all variables and their values
		TRACE	=	$016b    * TRACE - used with ON TRACE GOSUB for debugging
		SWAP		=	$0158    * SWAP - exchange values of two variables
		WAIT		=	$0157    * WAIT - pause for N/70 seconds
		TRON		=	$0159    * TRON - enable trace mode (show each line before execution)
		TROFF	=	$015a    * TROFF - disable trace mode
		AUTO		=	$016f    * AUTO - automatic line numbering mode
		EDTAB	=	$0170    * EDTAB - set editor tab stops

* --- Logical operators (handled specially in expression parser) ---
		AND		=	$016c    * AND - bitwise AND operator
		OR		=	$016d    * OR - bitwise OR operator
		EOR		=	$016e    * EOR - bitwise exclusive OR operator

*==============================================================================
* Token class 2 and 3 - Extended commands (drawing)
*==============================================================================
          LINE2     =    $0200          * 7.11.88 - LINE drawing command (class 2)
          LINE3	=	$0300          * LINE drawing command (class 3)

*==============================================================================
* SECTION 2: Output Routing, Break Detection, Initialization, Main Loop
*==============================================================================
.text

*==============================================================================
* ROUTINE: tab_
* Purpose: Output a TAB character, routing to screen or file as appropriate
* Parameters: none (uses filefl to determine output destination)
* Returns:    nothing
* Modifies:   d0-d2, a0-a2 (saved/restored if file output)
*==============================================================================
tab_:
          tst.w     filefl              * Is output redirected to a file?
          beq       ed_tab              * No -> use editor's tab routine
          movem.l   d0-d2/a0-a2,-(sp)  * Save registers for file I/O
          moveq.l   #1,d0              * Write 1 byte
          move.b    #9,key              * TAB character (ASCII 9)
          lea       key,a1              * Point to the byte to write
          bsr       f_write             * Write TAB to file via GEMDOS Fwrite
          movem.l   (sp)+,d0-d2/a0-a2  * Restore registers
          rts

*==============================================================================
* ROUTINE: putstrreverse
* Purpose: Output a string that is stored BACKWARDS in memory.
*          Strings in this BASIC are stored with the first character at the
*          highest address and a NUL terminator at the lowest address.
*          This routine outputs them character by character, working from
*          high address to low, temporarily zeroing each byte after reading
*          it and restoring it after output.
* Parameters: a0 = pointer to NUL terminator at start (low end) of string
* Returns:    nothing
* Modifies:   d1, a0 (preserved via stack)
*==============================================================================
putstrreverse:
          movem.l   d1/a0,-(sp)        * Save registers
          addq.l    #1,a0              * Move past the NUL terminator to first data byte
putrvl9:
          move.b    (a0),d1            * Save current character
          clr.b     (a0)               * Temporarily zero it (makes a valid C-string for put_string)
          subq.l    #1,a0              * Move pointer down (toward string start)
          bsr       put_string          * Output the substring from here to the zeroed byte
          move.b    d1,1(a0)           * Restore the character we zeroed
          tst.b     (a0)               * Have we reached the NUL terminator?
          bne       putrvl9            * No -> continue with next character
          movem.l   (sp)+,d1/a0        * Restore registers
          rts


*==============================================================================
* ROUTINE: put_string
* Purpose: Output a NUL-terminated string, routing to screen or file.
*          When outputting to a file, carriage returns (13) are preceded
*          by a linefeed (10) for proper line endings.
* Parameters: a0 = pointer to NUL-terminated string
* Returns:    nothing
* Modifies:   d0-d2, a0-a2 (saved/restored during file output)
*==============================================================================
put_string:
          tst.w     filefl              * Is output redirected to file?
          beq       ed_print            * No -> use editor's print routine

* --- File output path ---
          movem.l   d0-d2/a0-a2,-(sp)  * Save registers
          movem.l   d0-d2/a0-a2,-(sp)  * (duplicate save - original code artifact)
          move.l    a0,a1              * a1 = string pointer for f_write
          moveq.l   #1,d0              * Always write one byte at a time
prfl2:
          move.b    (a1),d1            * Get next character
          beq       hsoend              * NUL -> end of string
          movem.l   d0/a1,-(sp)        * Save byte count and string pointer
          cmp.b     #13,d1             * Is it a carriage return?
          bne       prfl1              * No -> just write the character
          move.b    #10,key2           * Yes -> first output a linefeed (LF)
          lea       key2,a1            * Point to LF byte
          bsr       f_write            * Write LF to file
          movem.l   (sp)+,d0/a1        * Restore registers
          movem.l   d0/a1,-(sp)        * Save again for the CR write
prfl1:
          bsr       f_write            * Write the actual character via GEMDOS Fwrite
          movem.l   (sp)+,d0/a1        * Restore registers
          addq.l    #1,a1              * Advance to next character
          bra       prfl2              * Loop for next character
hsoend:
          movem.l   (sp)+,d0-d2/a0-a2  * Restore registers
          rts

*==============================================================================
* ROUTINE: ed_chkstop / chk_stop
* Purpose: Check for user break request (ALT+UNDO key combination).
*          ed_chkstop is called from the editor's scroll routines and only
*          checks when in direct mode. chk_stop is the general entry point.
*          Uses BIOS Kbshift ($0B via trap #13) to read modifier key state,
*          then GEMDOS Crawcin to read the actual key if ALT is pressed.
* Parameters: none
* Returns:    Returns normally if no break; jumps to stoperr if ALT+UNDO pressed
* Modifies:   d0
*==============================================================================
ed_chkstop:	* Called from editor scroll routine
		tst.w	b_modus			* Only interruptible in direct mode!
		beq		chk_stop       * b_modus=0 means direct mode -> check
		rts                        * In program mode -> don't interrupt scrolling

chk_stop:
          move.l    a0,-(sp)           * Save a0
		move.w	#-1,-(sp)          * Parameter: -1 = just read current state
		move.w	#11,-(sp)          * BIOS function $0B = Kbshift (read keyboard shift state)
		trap		#$d            * BIOS trap #13
		addq.l	#4,sp              * Clean up stack (4 bytes: function# + parameter)
		and.w	#%1000,d0          * Isolate bit 3 = ALT key
          beq		nostoperr          * ALT not pressed -> no stop

		* ALT is pressed, now check if UNDO key was also pressed
		move.w	#7,-(sp)           * Character to output: BEL (bell/beep)
		move.w	#2,-(sp)           * Device #2 = console
		move.w	#3,-(sp)           * BIOS function #3 = Bconout
		trap		#13            * BIOS trap #13 - output bell character
		addq.l	#6,sp              * Clean up stack (6 bytes)
		move.w	#7,-(sp)           * GEMDOS function #7 = Crawcin (read char, wait)
		trap		#1             * GEMDOS trap #1
		addq.l	#2,sp              * Clean up stack
		swap		d0             * Swap to get scan code in low word
		cmp.b	#$61,d0            * Scan code $61 = UNDO key
		bne		nostoperr          * Not UNDO -> no stop
		move.l	(sp)+,a0           * Restore a0
		bra		stoperr            * Jump to STOP error handler (halts program)
nostoperr:
		move.l	(sp)+,a0           * Restore a0
          rts


*==============================================================================
* ROUTINE: b_init
* Purpose: One-time BASIC initialization. Called at startup.
*          1. Reads max columns from editor structure
*          2. Preprocesses token strings: converts uppercase letters to
*             lowercase with bit 7 set (abbreviation system). This allows
*             users to abbreviate keywords by typing the uppercase letter.
*             E.g., "lIst" -> typing "LI" matches because 'I' has bit 7 set.
*          3. Initializes BASIC state (NEW + CLR)
* Parameters: none (reads edibase global)
* Returns:    Falls through to basic_ which does NEW+CLR
*==============================================================================
b_init:
		move.l	edibase,a0         * Get pointer to editor data structure
		clr.l	d0
		move.w	edi_maxspalten(a0),d0  * Read max columns from editor
		move.l	d0,maxspalten     * Store as BASIC's max line length

* --- Preprocess token strings: uppercase chars get bit 7 set ---
* The token abbreviation system works like this:
* In the token string table, uppercase letters mark where abbreviation
* is allowed. After this preprocessing, those letters become lowercase
* with bit 7 set ($80). During tokenization (konv_inpuf), when the user
* types an uppercase letter, the tokenizer sets bit 7 and compares -
* if it matches, the abbreviation is accepted.
          lea       token1adr,a0       * a0 = table of pointers to token name strings
basicl1:  tst.l     (a0)               * End of table? (NULL pointer)
          beq       basic_              * Yes -> all commands preprocessed, continue init
          move.l    (a0)+,a1             * a1 = pointer to current token's name string
basicl2:  move.b    (a1)+,d0            * Get next character from token name
          beq       basicl1             * NUL -> end of this token name, go to next
          cmp.b     #'Z',d0            * Is it above 'Z'?
          bhi       basicl2            * Yes -> not uppercase, skip
          cmp.b     #'A',d0             * Is it below 'A'?
          blt       basicl2            * Yes -> not uppercase, skip
          add.b     #$20,d0             * Convert 'A'-'Z' to 'a'-'z' (lowercase)
          bset      #7,d0               * Set bit 7 (marks as abbreviation point)
          move.b    d0,-1(a1)           * Write modified character back
          bra       basicl1            * Continue with next token

basic_:                                 * Real BASIC initialization starts here
          move.l    #-1,contline        * CONT not allowed (no stopped program)
		move.l	#-1,traceline      * No trace line set
		bsr		New1               * Initialize program space (empty program)
          bra       Clr1               * Clear all variables and structures

*==============================================================================
* ROUTINE: basic1 / basic2  (Befehlszeileneingabeschleife = Command Line Input Loop)
* Purpose: Main interpreter loop. Displays "ready." prompt, handles AUTO
*          line numbering, then returns to the editor to accept input.
*          basic1 = entry with "ready." prompt
*          basic2 = entry without prompt (used after AUTO numbering)
*
* The loop works by returning control to the editor (via posquit/quit).
* When the user presses RETURN, the editor calls b_enter with the line.
*==============================================================================
basic1:
          bsr       clrfilefl          * Reset file output flag (output to screen)
		tst.w	autofl 			* AUTO mode active? If so, skip "ready."
		bne		basic2
          lea       ready,a0            * a0 = "ready." string
          bsr       put_string          * Display the prompt
basic2:
          bsr       clrfilefl          * Ensure output goes to screen
          bsr       restore            * Reset DATA pointer to program start
          clr.w     argfl              * Clear argument flag (not in FN argument context)
          clr.w     b_modus             * Set to direct mode (0 = direct, -1 = program)
          clr.w     ifcnt              * Reset IF counter for the line
          bsr       init_tbls           * Clear FOR/NEXT, GOSUB, IF tables
		tst.l	contline           * Can we CONT? (>=0 means yes)
		bpl		quit2              * Yes -> don't clear akt_zeile
		clr.l	akt_zeile          * No CONT -> clear current line number
quit2:
* --- AUTO line numbering ---
* If AUTO mode is active, output the next line number and a space,
* then increment the line counter for the next iteration.
		tst.w	autofl             * AUTO mode active?
		beq		posquit            * No -> return to editor normally
		move.w	ed_x,d0
		add.w	ed_xoffs,d0        * Test if cursor is at line start
		beq		quit2a             * At column 0 -> ok
		bsr		ed_newline         * Not at start -> output newline first
quit2a:
		move.l	autozeile,d0       * Get current AUTO line number
		move.l	d0,-(sp)           * Save it
		bsr		ipka_              * Convert integer to ASCII string (-> a2)
		move.w	filefl,-(sp)       * Save file flag
		clr.w	filefl             * Force output to screen (not file)
		lea		-1(a2),a0          * Skip sign character in ASCII output
		bsr		putstrreverse      * Display the line number
		lea		key,a0
		move.w	#$2000,(a0)        * SPACE + NUL terminator
		bsr		put_string         * Output a space after the line number
		move.w	(sp)+,filefl       * Restore file flag
		move.l	(sp)+,d0           * Restore current line number
		add.l	autoadd,d0         * Add AUTO increment (e.g., 10)
		bpl		quit2b             * Still positive -> ok
		clr.w	autofl             * Line counter overflowed -> turn off AUTO
quit2b:
		move.l	d0,autozeile       * Store next AUTO line number

*==============================================================================
* ROUTINE: posquit / quit
* Purpose: Return control to the editor.
*          posquit: returns d0=0 (normal return, editor shows cursor)
*          quit: returns d0=-1 (exit signal, e.g., after '!' command)
* Parameters: none
* Returns:    d0.l = 0 (posquit) or -1 (quit)
*==============================================================================
posquit:
          move.l    oldstack,sp        * Restore stack pointer saved at entry
          moveq.l   #0,d0              * Return code 0 = normal (continue editing)
          rts
quit:
          move.l    oldstack,sp        * Restore stack pointer
          moveq.l   #-1,d0             * Return code -1 = exit
          rts

oldstack:
          .ds.l     1                  * Saved stack pointer (set by b_enter/b_runcode)

*==============================================================================
* SECTION 3: Entry Points, Input Handling, Tokenizer, Line Management
*==============================================================================

*==============================================================================
* ROUTINE: b_enter / b_runcode
* Purpose: Entry point called by the editor when user presses RETURN.
*          b_enter: a0 points into the editor screen buffer, d0 = line length
*          b_runcode: a0 points to a smaller buffer (d0 already set to length)
*
*          The routine:
*          1. Copies input to work buffer, stripping leading/trailing spaces
*          2. Tokenizes the input (keyword recognition)
*          3. If input starts with a digit -> line management (insert/delete)
*          4. If input starts with '!' -> exit
*          5. Otherwise -> execute directly
* Parameters: a0 = pointer to input text, d0 = max line length
* Returns:    jumps to basic1/basic2 or quit
*==============================================================================
b_enter:
          move.l    d0,maxspalten      * Set max line length from editor
b_runcode:
          move.l    sp,oldstack        * Save current stack pointer for posquit/quit
          lea       stack,sp           * Switch to BASIC's own stack
          bsr       copy_inpuf         * Copy input to input_puf, strip spaces
          bsr       konv_inpuf         * Tokenize: convert keywords to token bytes
          bsr       ed_newline          * Move to new line on screen
          lea       input_puf,a0       * Point to tokenized input buffer

          bsr       charget            * Get first non-space character
		bne		b_runc1            * Not empty -> process it
		clr.w	autofl             * Empty line -> turn off AUTO mode
          bra       basic2             * Return to main loop (no "ready.")
b_runc1:
          cmp.b     #'!',d0            * '!' = exit command
		bne		b_runc2
		clr.w	autofl             * Turn off AUTO
          bra       quit               * Exit to editor/calling program
b_runc2:
          cmp.b     #'0',d0            * Does line start with a digit?
          blt       exec_puf           * No (below '0') -> execute directly
          cmp.b     #'9',d0
          bhi       exec_puf           * No (above '9') -> execute directly

          * Line starts with a digit -> it's a numbered line to store/delete
		subq.l	#1,a0              * Back up to include the first digit
		bsr		zeilenverwaltung   * Line management: insert/delete/replace
		bra		basic2             * Return to main loop

*==============================================================================
* ROUTINE: zeilenverwaltung (Line Management)
* Purpose: Handle insertion, deletion, and replacement of numbered program lines.
*          The program is stored as a singly-linked list where each node is:
*          [4-byte pointer to next line][4-byte line number][tokenized data...]
*
*          If only a line number is entered (no code after it) -> delete that line.
*          If code follows the line number -> insert or replace that line.
*
*          After modifying the program, variable pointers (varbase, varend)
*          must be adjusted because variables are stored immediately after
*          the program in memory.
*
* Parameters: a0 = pointer to tokenized input (starting at line number digits)
* Returns:    nothing (program memory modified in place)
* Modifies:   Many registers; program/variable memory
*==============================================================================
zeilenverwaltung:
          move.l    #-1,contline        * Program modified -> CONT no longer valid
		move.l	#-1,traceline      * Clear trace line too
          tst.w     fncnt               * Only clear variables if FN definitions exist
          bne       zv1
		tst.w	anzprocs           * ...or if procedures have been defined
		beq		insline            * Neither -> skip CLR, just insert the line
zv1:
          bsr       Clr1               * Clear all variables (FN/PROC defs invalidated)

insline:  * --- Insert line into program listing ---
          bsr       get_int             * Parse integer line number from input -> d0.l
          tst.b     (a0)                * Is there any code after the line number?
          bne       basic20            * Yes -> insert/replace the line

delline:  * --- Delete line (only line number was entered) ---
		tst.w	autofl
		beq		delline1
		clr.w	autofl             * Deleting a line -> turn off AUTO
		bra		endezv             * Return without doing anything
delline1:
          bsr       poszeile           * Find position in linked list for this line number
                                       * -> a1 = pointer to line at or before d0
delline2:	* d0 = line number, a1 = pointer to line node
          cmp.l     4(a1),d0            * Does this line actually exist (number matches)?
          bne       endezv              * No match -> nothing to delete, return

          * --- Remove the line node from the linked list ---
          move.l    a1,a3              * a3 = start of line to delete
          move.l    (a1),a2            * a2 = pointer to next line
          move.l    a2,d0
          sub.l     a1,d0               * d0 = length of line being deleted (in bytes)

          * Shift all data after the deleted line downward to fill the gap
basic3:   move.b    (a2)+,(a1)+        * Copy byte by byte
          cmp.l     varend,a2          * Until we've copied past the end of variables
          bne       basic3

          * Update global pointers: subtract the deleted length
basic3b:  sub.l     d0,prgend          * Program end moves down
          sub.l     d0,varbase         * Variable base moves down
          sub.l     d0,varend          * Variable end moves down
          clr.l     (a1)                * Terminate the list

          * Relink program lines (update next-line pointers)
basic3a:  tst.l     (a3)               * Is this the last line (next=0)?
          beq       basic3c            * Yes -> done with program relink
          sub.l     d0,(a3)            * Adjust this line's next pointer
          move.l    (a3),a3            * Follow to next line
          bra       basic3a

basic3c:  * --- Relink variable chain ---
          * Variables are also a linked list; their next-pointers must be
          * adjusted by the same displacement as the program data.
          move.l    varbase,a1         * Start of variable list
lll3:
		cmp.l	varend,a1          * Reached end of variables?
          beq       endezv              * Yes -> done, return to interpreter
          move.l    (a1),d1            * Get next-variable pointer
          sub.l     d0,d1              * Adjust by displacement
          move.l    d1,(a1)            * Write back
          move.l    d1,a1              * Follow to next variable
          bra       lll3

* --- Insert new line ---
* D0 = line number
* A0 = pointer to tokenized line data (after the line number)
basic20:
          move.l    a0,a1
basic2a:  tst.b     (a1)+               * Find end of line (double-NUL terminated)
          bne.s     basic2a
          tst.b     (a1)+               * Second NUL marks absolute end
          bne.s     basic2a
          move.l    a1,d1
          sub.l     a0,d1               * d1 = length of new line data (bytes)
          btst      #0,d1               * Is length odd?
          beq       basic2b
          addq.l    #1,d1              * Make it even (word-aligned)
basic2b:
          move.l    d1,d3               * d3 = save length for later
          bsr       poszeile            * Find insertion point -> a1
          cmp.l     4(a1),d0            * Does a line with this number already exist?
          bne       basic2c             * No -> must create entirely new entry

          * --- Replace existing line (same line number) ---
          move.l    (a1),d2             * d2 = pointer to next line
          lea       8(a1),a2           * a2 = start of old line's data (after 8-byte header)
          sub.l     a2,d2               * d2 = length of old tokenized data
          cmp.l     d1,d2               * Compare old length with new length
          ble       basic2d             * Old >= new -> need to insert extra space

          * Old line is LONGER than new line -> remove excess bytes
          sub.l     d1,d2               * d2 = bytes to remove
          move.l    a2,a3
          add.l     d2,a3              * a3 = source (shifted right by d2)
basic2e:  move.b    (a3)+,(a2)+        * Shift program+variables down
          cmp.l     varend,a3           * Copy until end of variables
          bne       basic2e
          clr.l     (a2)               * Terminate
          neg.l     d2                  * Negate (for add operations below)

basic2f:  * --- Relink program line pointers ---
          move.l    a1,a2               * Start from the modified line
          move.l    a2,(a2)            * Initialize: point to self
          addq.l    #8,(a2)             * Add header size (8 bytes)
          add.l     d3,(a2)             * Add data length -> points to next line
          add.l     d2,prgend           * Update program end pointer
          add.l     d2,varbase          * Update variable base
          add.l     d2,varend           * Update variable end
          move.l    prgend,a4
          clr.l     (a4)                * Mark end of program (NULL terminator)
          bra       basic2f2
basic2f1: move.l    a2,a3               * Save current position
          add.l     d2,(a2)             * Adjust next-line pointer
basic2f2: move.l    (a2),a2             * Follow to next line
          cmp.l     a2,d2               * Was pointer zero (end of list)?
          bne       basic2f1           * No -> continue relinking

          bsr       basic2h             * Copy the new line data
          move.l    d2,d0
          neg.l     d0
          bra       basic3c             * Relink variables and return

basic2d:  * --- Old line is SHORTER or EQUAL -> append extra space ---
          sub.l     d2,d1               * d1 = extra bytes needed
          bne       basic2c2            * Not equal -> need to expand
          bsr       basic2h             * Equal length -> just copy new data over old
          bra       endezv

basic2c:  * --- Create entirely new line entry at position a1 ---
          addq.l    #8,d1               * Add 8 bytes for the line header (next ptr + line#)
basic2c2: move.l    varend,a2
          lea       -32(a2,d1.l),a3    * Check if there's enough memory (32-byte margin)
          cmp.l     strend,a3          * Would we collide with string space?
          bge       outprgmem          * Yes -> "out of program space" error
          add.l     #32,a3
		clr.l	(a3)               * Clear safety margin

          * Shift program and variables UP to make room for the new line
basic2g:  move.b    -(a2),-(a3)         * Copy backwards (high to low)
          cmp.l     a1,a2              * Until we reach the insertion point
          bhi       basic2g

basic2j:  move.l    d1,d2               * d2 = displacement for relinking
          bra       basic2f            * Go relink and finish

basic2h:  * --- Copy new line data into the program ---
          addq.l    #4,a1               * Skip past next-line pointer (already set)
          move.l    d0,(a1)+            * Write line number
basic2i:  move.b    (a0)+,(a1)+        * Copy tokenized data byte by byte
          subq.l    #1,d3              * Decrement length counter
          bne       basic2i
          move.l    prgend,a0
          clr.l     (a0)+               * Mark end of program
          move.l    #-1,(a0)           * Sentinel value after program end
endezv:
          rts


*==============================================================================
* ROUTINE: new_line
* Purpose: Output a carriage return character (start new line on screen/file)
* Parameters: none
* Returns:    nothing
*==============================================================================
new_line:
          move.l    a0,-(sp)           * Save a0
          lea       key,a0
          move.b    #$0d,(a0)          * CR character
          bsr       put_string         * Output it
          move.l    (sp)+,a0           * Restore a0
          rts

*==============================================================================
* ROUTINE: clrfilefl
* Purpose: Clear the file output flag, but only if CMD mode is not active.
*          When CMD is active, output stays directed to the file.
* Parameters: none (reads cmdfl)
* Returns:    nothing
*==============================================================================
clrfilefl:
          tst.w     cmdfl               * Is CMD mode active?
          bne       clrfend            * Yes -> don't clear file flag
          clr.w     filefl             * No -> output goes back to screen
clrfend:  rts

*==============================================================================
* ROUTINE: copy_inpuf
* Purpose: Copy input from editor line buffer to BASIC's work buffer (input_puf),
*          stripping leading and trailing spaces.
* Parameters: a0 = pointer to source line, d0 = max line length
* Returns:    input_puf filled with trimmed input, double-NUL terminated
* Modifies:   d0, d7, a0-a2
*==============================================================================
copy_inpuf:
          * A0 = pointer to source line
          * D0 = max line length
          move.l    a0,a1              * a1 = source pointer
          lea       input_puf,a0       * a0 = destination (BASIC's input buffer)
* A1 source pointer, D0 max length, A0 destination buffer
copya1_ina0:
		ext.l	d0                 * Sign-extend d0 to longword
          lea       0(a1,d0),a2        * a2 = pointer to end of source line
coi1:     moveq     #0,d7
seek_st:                               * --- Skip leading spaces ---
          addq.l    #1,d7              * Count characters skipped
          cmp.b     d0,d7              * Reached max length?
          beq.s     seekend            * Yes -> line is all spaces, done
          cmp.b     #$20,(a1)+         * Is current char a space?
          beq.s     seek_st            * Yes -> skip it
          subq.l    #1,a1              * Back up to first non-space
          move.l    d0,d7
          addq.l    #1,d7
seek_end:                              * --- Skip trailing spaces ---
          subq.l    #1,d7              * Count characters from end
          beq.s     seekend            * Reached beginning -> empty result
          move.b    -(a2),d0           * Read from end
          cmp.b     #$20,d0            * Is it a space?
          beq.s     seek_end           * Yes -> skip it
          addq.l    #1,a2              * Point past last non-space
seek1:    move.b    (a1)+,(a0)+        * Copy trimmed content to destination
          cmp.l     a1,a2              * Reached end of trimmed content?
          bne.s     seek1              * No -> continue copying
seekend:  bsr       clrendpuf          * Append NUL terminators to output buffer
          rts

*==============================================================================
* ROUTINE: konv_inpuf (Tokenizer)
* Purpose: Convert BASIC keywords in the input buffer (input_puf) to their
*          2-byte token representation. This is the tokenizer/lexer.
*
*          The algorithm:
*          1. Scan input character by character
*          2. Skip content inside quoted strings (between " marks)
*          3. When a letter or '?' is found, attempt to match against tokenstr
*          4. Two matching modes:
*             a. UPPERCASE input: clear bit7 of token char, compare lowercase
*             b. lowercase input: if token char has bit7 set, abbreviation match
*          5. After match, verify next char is not a variable name char
*             (to avoid matching "list" inside "mylist")
*          6. Replace matched text with 2-byte token, shift remaining text
*
* Parameters: none (reads/writes input_puf)
* Returns:    input_puf contains tokenized line
* Modifies:   d0-d7, a0-a3
*==============================================================================
konv_inpuf:
          lea       input_puf,a0       * a0 = pointer into input buffer
          clr.w     d7                  * d7 = quote flag (0=outside quotes)
konv0:
		move.b    (a0)+,d0          * Get next character
		beq		konvend            * NUL -> end of input, finish up
          tst.w     d7                 * Are we inside a quoted string?
          bne.s     konv1              * Yes -> don't try to match keywords

		cmp.b     #'?',d0             * Special case: '?' is shorthand for PRINT
          beq       konvcmd            * Treat as a command match

		cmp.l	#input_puf+1,a0    * Is this the first character in the buffer?
		beq		konv0a             * Yes -> don't check preceding char
		move.b	d0,d1              * Save current char
		move.b	-2(a0),d0          * Get preceding character
		bsr		isvarn             * Could preceding char be part of a variable name?
		beq		konv0              * Yes -> this letter is inside a varname, skip
		move.b	d1,d0              * Restore current char

konv0a:
		cmp.b	#'A',d0            * Is it an uppercase letter?
		blo		konv1              * Below 'A' -> not a keyword start
		cmp.b	#'Z',d0
		bls		konvCmd            * 'A'-'Z' -> try matching as uppercase command
          cmp.b     #'a',d0            * Is it a lowercase letter?
          blo		konv1              * Below 'a' -> not a keyword start
          cmp.b     #'z',d0
          bls       konvcmd            * 'a'-'z' -> try matching as lowercase command

konv1:
          * --- Check for quote characters that toggle string context ---
		cmp.b	#$27,d0            * Is it a single quote ' (REM shorthand)?
		bne		konv1a
		tst.w	d7                 * If already inside "..." then ignore
		bne		konv2
		not.w	d7                 * Toggle quote flag (enters comment mode)
		bra		konv2
konv1a:
		cmp.b     #$22,d0             * Is it a double quote "?
          bne.s     konv2
          not.w     d7                 * Toggle quote flag
konv2:
		bra		konv0              * Continue scanning


*--- Attempt to match a keyword (uppercase input) ---
konvCmd:
		moveq.l	#1,d1              * d1=1: input is UPPERCASE
		bra		konvcmd1
*--- Attempt to match a keyword (lowercase input) ---
konvcmd:
		clr.l	d1                 * d1=0: input is lowercase
konvcmd1:
          lea    	-1(a0),a1           * a1 = save position of match start
          moveq     #0,d6               * d6 = current token index (0-based)
          cmp.b     #'?',d0             * Is it the PRINT shorthand '?'?
          bne       konv3              * No -> try normal matching

          * '?' matched -> insert space and jump to token found
		lea		inpuf2_end-2,a2
konvprl:
		move.b	-(a2),1(a2)        * Shift buffer right by 1 to make room
		cmp.l	a0,a2
		bne		konvprl
          bra       token2found        * '?' -> PRINT token

konv3:
          * --- Compare input against token string table ---
		lea       tokenstr,a2        * a2 = pointer into token name strings
konv5:
          move.b    (a2)+,d2           * Get next char from token definition string
		tst.b	d1                 * Is input uppercase (d1=1) or lowercase (d1=0)?
		beq		inklein            * lowercase input path

* --- UPPERCASE input comparison ---
		bclr		#7,d2          * Clear bit7 (token abbreviation marker)
		or.b		#$20,d0        * Convert input to lowercase for comparison
		cmp.b	d0,d2              * Compare
		bne		nexttoken          * Mismatch -> try next token
		bra		nextcmp            * Match -> continue comparing

* --- lowercase input comparison (inklein = "to lowercase") ---
inklein:
		btst		#5,d0          * Is the input char shifted (uppercase)?
		bne		konv5a             * No (bit5=1 means lowercase) -> normal compare
		bset		#7,d0          * Set bit7 (to match abbreviated token char)
		or.b		#$20,d0        * Also make lowercase
		cmp.b     d0,d2             * Does it match the shortform (bit7-marked char)?
		beq		tokenfound         * Yes -> abbreviation matched!
		bra		nexttoken          * No -> try next token
konv5a:
		bclr		#7,d2          * Clear bit7 from token char
		cmp.b	d0,d2              * Normal comparison
		bne		nexttoken          * Mismatch -> next token

nextcmp:                               * --- Continue comparing rest of token ---
		tst.b	(a2)               * End of token string?
		beq		tokenfound         * Yes -> full match!
		move.b	(a0)+,d0           * Get next input character
		bne		konv5              * Not end of input -> keep comparing
		beq		nexttoken          * End of input without full match -> next token

konvback:
		lea		1(a1),a0           * Reset to one char past match start
		bra		konv0              * Try again from next position

nexttoken:                             * --- Advance to the next token in the table ---
          move.l    a1,a0              * Reset input pointer to match start
nt1:
		tst.b     (a2)+            * Skip to end of current token name (find NUL)
          bne.s     nt1
          addq.l    #1,d6              * Increment token index
          tst.b     (a2)               * Is this the end of all tokens (double NUL)?
          beq       konvback           * Yes -> no match, try from next input position
		move.b	(a0)+,d0           * Re-read first input character for next comparison
		bra		konv5              * Compare against next token

tokenfound:
          * --- Verify the character after the match is not a varname char ---
          * This prevents matching "list" inside a variable name like "mylist"
		move.b	(a0),d0
		bsr		isvarn             * Is next char a valid variable name character?
		beq		konvback           * Yes -> false positive, try next position

token2found:
          * --- Token matched! Replace text with 2-byte token ---
          move.l    #inpuf2_end-2,d0   * Calculate how many bytes to shift
          sub.l     a0,d0
          lsl.l     #1,d6              * d6 * 2 (token numbers are words in tokennr table)
          lea       tokennr,a3         * Token number lookup table
          move.b    (a3,d6.l),(a1)+    * Write token high byte (class: TOKEN1/2/3)
          move.b    1(a3,d6.l),(a1)+   * Write token low byte (command index)
          move.l    a1,a2              * a2 = destination for remaining text
          tst.w     d0
          beq       tf3                * No remaining text
		cmp.l	a2,a0
		ble		tf3                * Source <= dest -> no shift needed
tf1:      move.b    (a0)+,d1           * Shift remaining buffer content left
          move.b    d1,(a2)+
          dbf       d0,tf1
          clr.b     (a2)               * NUL terminate
tf3:
		move.l	a1,a0              * Continue tokenizing from after the token
		bra		konv2              * (not konv0, because we already have the position)

konvend:
*==============================================================================
* ROUTINE: clrendpuf
* Purpose: Terminate the input buffer with 4 NUL bytes (double-NUL end marker)
* Parameters: a0 = pointer to end of buffer content
* Returns:    a0 advanced past the NUL bytes
*==============================================================================
clrendpuf:
          clr.b     (a0)+              * Four NUL bytes ensure the tokenizer
          clr.b     (a0)+              * and line parser can safely detect
          clr.b     (a0)+              * end-of-line in all cases.
          clr.b     (a0)+
          rts

*==============================================================================
* ROUTINE: isvarn / isvarname
* Purpose: Test if a character can be part of a variable name.
*          isvarn: tests if d0.b can be ANY character of a variable name
*                  (letters, digits, underscore, or chars with bit7 set)
*          isvarname: tests if d0.b can be the FIRST character
*                  (same as isvarn but excludes digits)
* Parameters: d0.b = character to test
* Returns:    BEQ (Z flag set) if character IS valid for a variable name
*             BNE (Z flag clear) if character is NOT valid
* Modifies:   nothing
*==============================================================================
isvarn:
		cmp.b	#'0',d0            * Is it below '0'?
		blo		isvarname          * Yes -> check non-digit characters
		cmp.b	#'9',d0            * Is it a digit '0'-'9'?
		bls		isvarpos           * Yes -> valid in variable name (not first char)

isvarname:
		tst.b	d0                 * Is bit 7 set (token/special char)?
		bmi		isvarpos           * Yes -> valid (allows extended chars in names)

		cmp.b	#'a',d0            * Check lowercase 'a'-'z'
		blo		isvn1
		cmp.b	#'z',d0
		bls		isvarpos           * Lowercase letter -> valid

isvn1:
		cmp.b	#'A',d0            * Check uppercase 'A'-'Z'
		blo		isvn2
		cmp.b	#'Z',d0
		bls		isvarpos           * Uppercase letter -> valid

isvn2:
		cmp.b	#$5f,d0            * Check underscore '_' ($5F)
		bne		isvarneg           * Not underscore -> invalid

isvarpos:
		cmp.b	d0,d0              * Set Z flag (BEQ = valid)
		rts
isvarneg:
		cmp.b	#'a',d0            * Clear Z flag by comparing with 'a'
                                       * (d0 != 'a' since we already checked that)
		rts


*==============================================================================
* SECTION 4: Execution Loop, Token Dispatch
*==============================================================================

*==============================================================================
* ROUTINE: exec_puf
* Purpose: Execute the contents of input_puf as a direct-mode command.
*          Turns off AUTO mode and calls exec_line, then returns to basic1.
*==============================================================================
exec_puf:
		clr.w	autofl             * Turn off AUTO mode
          lea       input_puf,a0       * Point to tokenized input
          bsr       exec_line          * Execute the line
          bra       basic1             * Return to "ready." prompt

*==============================================================================
* ROUTINE: exec_line / exec1
* Purpose: Execute one line of tokenized BASIC code.
*          Processes commands separated by ':' until end of line (NUL byte).
*          Supports trace mode: if tracefl=1, calls trace routine before
*          each command to display the current line being executed.
*
* Parameters: a0 = pointer to tokenized line data
* Returns:    when line is fully executed (NUL or error)
* Modifies:   d0, d1, a0-a2 and whatever the executed commands modify
*==============================================================================
exec_line:
exec1:
          bsr       chk_stop            * Check for ALT+UNDO break
          bsr       charget             * Get next non-space character
          beq       exec_end           * NUL -> end of line

          * --- Trace support ---
		tst.b	b_modus            * Are we in program mode?
		beq		execnotrace        * No (direct mode) -> no trace
		cmp.w	#1,tracefl         * Is trace mode ON (=1)?
		bne		notrace            * No -> skip trace
		bsr		trace              * Display trace info (d0=current token, a0=after it)
		bra		execnotrace
notrace:
		cmp.w	#2,tracefl         * Was tracefl=2 (just returned from trace gosub)?
		bne		execnotrace
		move.w	#1,tracefl         * Yes -> re-enable trace for next command

execnotrace:
          * --- Determine command type ---
          cmp.b     #TOKEN1,d0         * Is high byte a token intro?
          beq       exec2              * TOKEN1 ($01) -> dispatch via command table
		cmp.b	#TOKEN2,d0
		beq		exec2              * TOKEN2 ($02) -> dispatch
		cmp.b	#TOKEN3,d0
		beq		exec2              * TOKEN3 ($03) -> dispatch

          * --- Not a token: check for special characters and implicit commands ---
          subq.l    #1,a0               * Back up to the character
		cmp.b	#'&'+1,d0          * Is it the character after '&' (= single quote)?
		bne		exec0c
		move.w	#REM,d0            * ' (single quote) is shorthand for REM
		bra		exec0b

exec0c:
		cmp.b	#'0',d0            * Is it a digit?
		blt		exec0a
		cmp.b	#'9',d0
		bhi		exec0a
		move.w	#GOTO,d0           * Bare number -> implicit GOTO (e.g., "100" means "GOTO 100")
		bra		exec0b

exec0a:
          * --- Not a token, not a number: must be a variable assignment ---
          move.w    #-1,sysallow        * Allow system variable definitions
          bsr       var_def             * Handle "variable = expression"
          bra       exec3              * Continue after assignment

exec2:
          * --- Token dispatch ---
          move.b    (a0)+,d1            * Read token low byte (command index)
		bra		exec0ba            * Continue to dispatch
exec0b:
          * --- Entry for implicit commands (GOTO/REM from special chars) ---
		move.b	d0,d1              * d1 = low byte of command token
		lsr.w	#8,d0              * d0 = high byte (token class)
exec0ba:
		and.w	#$ff,d0            * Isolate token class (1, 2, or 3)
		lsl.w	#2,d0              * *4 for longword table index
		lea		comadr,a1          * comadr = array of 4 pointers to command tables
		move.l	(a1,d0),a1         * a1 = pointer to the correct command table
		and.w	#$ff,d1            * Isolate command index
          lsl.w     #2,d1              * *4 for longword index into command table
          move.l    (a1,d1),d0         * d0 = command address with flag bits

          * --- Check flag bits in the command address ---
          btst      #31,d0              * Bit 31: is this a function-only entry?
          beq		onlyexec           * No -> it can be executed as a command
		btst		#28,d0         * Bit 28: dual command/function?
		beq		nocmderr           * No -> "illegal use as command" error
		clr.w	cmdfktfl           * 0 = called as command (not as function)

onlyexec:
          btst      #30,d0              * Bit 30: program-mode-only?
          beq       exec2a
          tst.w     b_modus            * Are we in program mode?
          beq       dircterr            * No -> "illegal direct" error

exec2a:   btst      #29,d0              * Bit 29: direct-mode-only?
          beq       exec2b
          tst.w     b_modus            * Are we in program mode?
          bne       prgmerr            * Yes -> "illegal program mode" error

exec2b:   and.l     #$00ffffff,d0      * Mask off flag bits, keep 24-bit address
          move.l    d0,a2              * a2 = actual routine address
          jsr       (a2)               * Call the command routine

exec3:
          * --- After command execution, check for command separator or end ---
          bsr       chargot             * Re-read the last character
          beq       exec_end            * NUL -> end of line
          cmp.b     #':',d0             * Colon = command separator?
          bne       syntaxerr           * No -> syntax error (unexpected character)
          bra       exec1              * Yes -> execute next command on this line
exec_end:
          rts

*==============================================================================
* SECTION 5: Variable System
*==============================================================================

*==============================================================================
* ROUTINE: var_def
* Purpose: Handle variable assignment (e.g., "a = expr" or "a$(1) = expr").
*          Also detects and dispatches procedure calls (when no '=' is found).
*
*          First scans ahead to determine if this is a variable assignment
*          (contains '=') or a procedure call (ends with ':' or line end).
*          Handles system variables (ti, ti$) as special cases.
*
* Parameters: a0 = pointer to variable name in tokenized line
* Returns:    variable is assigned the evaluated expression
* Modifies:   many registers
*==============================================================================
var_def:
		move.l	a0,-(sp)           * Save starting position
		clr.w	d7                 * d7 = quote flag for scanning

tstvarproc:
		move.b	(a0)+,d0           * Read next character
		beq		isproc             * End of line without '=' -> procedure call
		cmp.b	#'"',d0            * Quote mark?
		bne		tst2varproc
		not.w	d7                 * Toggle string context flag

tst2varproc:
		tst.w	d7                 * Inside a string?
		bne		tstvarproc         * Yes -> don't check for = or :
		cmp.b	#'=',d0            * Found '='?  -> this is a variable assignment
		beq		isvar
		cmp.b	#':',d0            * Found ':'?  -> this is a procedure call
		bne		tstvarproc         * Neither -> keep scanning

isproc:
		move.l	(sp)+,a0           * Restore original position
		bra		Proc               * Jump directly to Proc command handler

isvar:
		move.l	(sp)+,a0           * Restore original position

          bsr       tst_var             * Look up the variable (name -> a1, type -> typflag)
          move.w    sysvar,-(sp)       * Save system variable flag
          bsr       var3_def            * Get or create the variable -> a1 points to value
          move.l    a6,-(sp)           * Save possible mark_str pointer
          cmp.l     #0,a6               * Was string marked for garbage collection?
          beq       ll10
          clr.b     (a6)                * Temporarily unmark string (keep it valid during assignment)
ll10:
          move.l    a1,-(sp)           * Save value pointer
          bsr       charget
          cmp.b     #'=',d0            * Verify '=' follows
          bne       syntaxerr
          bsr       get_defterm         * Evaluate the right-hand side expression
          move.l    (sp)+,a1           * Restore value pointer
          move.l    (sp)+,a6            * Restore mark_str pointer
          cmp.l     #0,a6
          beq       ll10a
          move.b    #$ff,(a6)           * Re-mark old string for garbage collection
ll10a:
          move.w    (sp)+,d0            * Restore sysvar flag
          bpl       def_cont            * Positive -> not a system variable
          tst.w     sysallow            * Are system variable assignments allowed?
          beq       syserr              * No -> error
          cmp.w     #-2,d0             * sysvar = -2 -> ti (integer)
          beq       setti
          cmp.w     #-3,d0             * sysvar = -3 -> ti$ (string)
          beq       settistr
          tst.w     d0                  * pi and other read-only sysvars -> error
          bmi       syserr
def_cont: bra       write_var          * Write the evaluated value to the variable

*==============================================================================
* ROUTINE: var2_def / var3_def
* Purpose: Helper routines for variable definition.
*          var2_def: looks up variable, checks for system var, creates if needed
*          var3_def: entry point after system var check
* Parameters: a0 = pointer to variable reference in tokenized line
* Returns:    a1 = pointer to variable's value storage
*             typvalid = type of the variable
*             a6 = mark_str pointer (if old string needs garbage collection)
*==============================================================================
var2_def:
          bsr       tst_var             * Look up the variable
          bsr       tstsysvar          * Error if it's a system variable
var3_def: * Entry point after sysvar test
          move.w    typflag,typvalid   * Set expected type from variable's type
          move.w    d0,-(sp)            * Save found/not-found flag
          tst.w     d0
          bne       def_v1              * Non-zero -> variable already exists
          bsr       create2_var        * Zero -> create the variable
def_v1:
          tst.b     arrayfl            * Is it an array access?
          beq       def_v2
          bsr       posarray            * Yes -> calculate array element position -> a1
          bsr       chk_klammer        * Verify closing ')'
def_v2:
          move.w    (sp)+,d0            * Was the variable old or newly created?
          tst.w     d0
          beq       def_v3             * New -> no old string to mark
          move.b    typvalid+1,d0       * Get type (low byte)
          cmp.b     #STRING,d0
          bne       def_v3             * Not a string -> no marking needed
          bsr       mark_str            * Old string variable -> mark old string for GC
          rts
def_v3:
          clr.l     a6                 * No string to mark
          rts

*==============================================================================
* ROUTINE: mark_str
* Purpose: Mark a string as invalid for garbage collection.
*          Finds the NUL terminator at the base of the backwards-stored string
*          and writes $FF there, signaling that this string can be reclaimed.
* Parameters: a1 = pointer to string variable's value (contains string pointer)
* Returns:    a6 = pointer to the $FF marker byte (so caller can undo it)
* Modifies:   a6
*==============================================================================
mark_str:
          move.l    (a1),a6             * Get the string pointer from the variable
          cmp.l     #zero_+4,a6        * Is it pointing to the empty string constant?
          beq       markend
          cmp.l     #0,a6              * Is it a null pointer?
          beq       markend             * Don't mark null/empty strings
		addq.l	#1,a6              * Start above the string data
markstr1:
          tst.b     -(a6)              * Scan downward to find the NUL terminator
          bne       markstr1
          move.b    #-1,(a6)           * Write $FF as garbage collection marker
          rts
markend:
          clr.l     a6                 * Return NULL (nothing to unmark later)
          rts

*==============================================================================
* ROUTINE: posarray
* Purpose: Calculate the memory offset for a multi-dimensional array element.
*          Reads index expressions separated by commas from the BASIC line,
*          validates bounds, then computes the linear offset using
*          row-major order (last dimension varies fastest).
*
* Parameters: a1 = pointer to array info header (dimension count, then sizes)
* Returns:    a1 = pointer to the array element's value storage
* Modifies:   d0-d7, a2-a6 (saved/restored)
*==============================================================================
posarray:
          movem.l   d0-d7/a2-a6,-(sp)   * Save all registers
          move.w    typflag,-(sp)
          move.w    typ2flag,-(sp)
          move.w    typvalid,-(sp)
          move.l    (a1)+,d0           * Read number of dimensions
          move.l    d0,arraydeep       * Store dimension count
          moveq     #0,d1
          lsl.l     #2,d0              * *4 for longword array of dimension sizes
          lea       array2len,a2       * a2 = buffer to store max sizes
posa0:
          move.l    (a1)+,(a2,d1)      * Copy dimension max sizes
          addq.l    #4,d1
          cmp.l     d0,d1
          bne       posa0

          moveq     #0,d0               * Start with dimension 0
posa2:
          move.l    d0,-(sp)           * Save current dimension index
          move.l    a1,-(sp)           * Save pointer past array header
          bsr       get_aterm          * Evaluate index expression -> fac1 (integer)
          move.l    (sp)+,a1
          move.l    (sp)+,d0

          move.l    d0,d1
          lsl.l     #2,d1              * d1 = offset into size arrays
		lea		array2len,a3       * a3 = max sizes array
          lea       arraylen,a2        * a2 = current indices array

          move.l    fac1,d3            * d3 = index value for this dimension
		bmi		negdimerr          * Negative index -> error
          cmp.l     (a3,d1),d3          * Compare index to max allowed
          bcc       badsubscr           * Index >= max -> "bad subscript" error
          move.l    d3,(a2,d1)          * Store index for this dimension
          addq.l    #1,d0              * Next dimension
          cmp.l     arraydeep,d0        * All dimensions processed?
          beq       posa1              * Yes -> compute linear offset

          move.w    d0,d7
          bsr       chk_komma          * Verify comma separates indices
          move.w    d7,d0
          bra       posa2              * Process next dimension

posa1:
          * --- Compute linear offset from multi-dimensional indices ---
          * Uses row-major ordering: offset = sum(index[i] * product(size[i+1..n]))
          lsl.l     #2,d0               * d0 = total dimensions * 4
		clr.l	d1                 * d1 = accumulated offset
		move.l	#1,fac2            * fac2 = running size multiplier

posa1a:
          subq.l    #4,d0              * Process dimensions from last to first
          bmi		posa1b              * All dimensions processed?
          move.l    (a2,d0),fac1       * Get index for this dimension
          bsr       submul             * fac1 = index * multiplier
		add.l	fac1,d1            * Add to total offset
		move.l	(a3,d0),fac1       * Get max size for this dimension
		bsr		submul             * Update multiplier = multiplier * size
		move.l	fac1,fac2          * Store new multiplier
          bra       posa1a

posa1b:
          * --- Convert element offset to byte offset ---
          move.w    (sp)+,typvalid
          move.w    (sp)+,typ2flag
          move.w    (sp)+,typflag
          moveq.l   #4,d0              * Default element size = 4 bytes (INT or STRING pointer)
          cmp.w     #FLOAT,typflag
          bne       posa1e
          moveq.l   #12,d0            * FLOAT elements are 12 bytes (3 longwords)
posa1e:
          move.l    d1,fac1            * Element index
          move.l    d0,fac2            * Element size
          bsr       submul             * fac1 = element_index * element_size
          add.l     fac1,a1            * Offset a1 to point to the element's storage
          movem.l   (sp)+,d0-d7/a2-a6 * Restore all registers
          rts


*==============================================================================
* ROUTINE: write_var
* Purpose: Write a value (from fac1 or str_ptr) into a variable's storage.
* Parameters: a1 = pointer to variable's value storage
*             typvalid = type to write (INT, FLOAT, or STRING)
*             fac1 = integer or float value; str_ptr = string pointer
* Returns:    a1 = pointer past the written value
*             a2 = pointer to the value (before advancing)
*==============================================================================
write_var:
          movem.l   d0-d7/a3-a6,-(sp)
          move.l    a1,a2              * a2 = value pointer (for caller)
          move.w    typvalid,d4         * Type to write
          cmp.w     #STRING,d4          * String?
          beq       write_str
          movem.l   fac1,d0-d3         * Load value from fac1 (up to 3 longwords)
          cmp.w     #FLOAT,d4           * Float?
          beq       write_fl
write_int:
          move.l    d0,(a1)+           * Write 4-byte integer value
          bra       write_end
write_fl:
          movem.l   d0-d2,(a1)         * Write 12-byte float value (3 longwords)
          add.l     #12,a1              * Advance a1 past the float
          bra       write_end
write_str:
          move.l    str_ptr,(a1)+      * Write string pointer (4 bytes)
write_end:movem.l   (sp)+,d0-d7/a3-a6
          rts

*==============================================================================
* ROUTINE: read_var
* Purpose: Read a variable's value into registers.
* Parameters: a1 = pointer to variable's value storage
*             typflag = type of variable (INT, FLOAT, or STRING)
* Returns:    For INT: d0.l = integer value
*             For FLOAT: d0-d2 = float value (d3 cleared)
*             For STRING: a1 = pointer to string data
*==============================================================================
read_var:
          movem.l   d4-d7/a2-a6,-(sp)
          move.w    typflag,d0
          cmp.w     #STRING,d0          * String?
          beq       read_str
          cmp.w     #FLOAT,d0           * Float?
          beq       read_fl
read_int:
          move.l    (a1),d0            * Read 4-byte integer
          bra       read_end
read_fl:
          movem.l   (a1),d0-d2         * Read 12-byte float
          moveq     #0,d3              * Clear d3 (guard word)
          bra       read_end
read_str:
          move.l    (a1),a1            * Dereference string pointer
          cmp.l     #0,a1               * NULL pointer?
          bne       read_end
          lea       leer_str+2,a1      * Point to empty string constant
read_end:
          movem.l   (sp)+,d4-d7/a2-a6
          rts

*==============================================================================
* ROUTINE: create2_var / create_var
* Purpose: Create a new variable in the variable storage area.
*          create2_var: creates with automatic array defaults (1D, 11 elements)
*          create_var: creates with current arrayfl/arraydeep/arraylen settings
*
*          Variable layout in memory:
*          [4-byte next-var pointer][2-byte type word][name bytes][NUL][.even]
*          [value: 4 bytes for INT/STRING, 12 bytes for FLOAT]
*          For arrays: [4-byte dim count][4-byte size per dim...][element data...]
*
* Parameters: var_name = variable name string
*             typvalid = type (with possible ARRAYTYP/FNTYP/PROCTYP flags)
*             arrayfl, arraydeep, arraylen = array parameters if applicable
* Returns:    a1 = pointer to variable's value storage
*==============================================================================
create2_var:
          tst.b     arrayfl             * Is this an array variable being auto-created?
          beq       cr2_v1
          move.l    #1,arraydeep        * Auto-create as 1-dimensional
          move.l    #11,arraylen        * With 11 elements (indices 0-10)
cr2_v1:
*         bra       create_var          * Fall through to create_var

create_var:
          movem.l   d0-d7/a2-a6,-(sp)
          move.l    varend,a1           * a1 = end of variable area (where new var goes)
          lea       var_name,a3        * a3 = variable name to store
          move.l    strend,a4
          sub.l     #32,a4             * Safety margin from string space
          cmp.l     a4,a1               * Would new var collide with strings?
          bge       outvarmem          * Yes -> "out of variable space" error
          move.l    a1,a4               * Save start of new variable record
          addq.l    #4,a1              * Skip past next-pointer (filled in at end)
          move.w    typvalid,d1        * Type word for this variable
          tst.b     arrayfl
          beq       cv3a
          bset      #15,d1              * Set ARRAYTYP bit if it's an array
cv3a:     move.w    d1,(a1)+            * Write type word

          * --- Copy variable name ---
cv3:
          move.b    (a3)+,(a1)+         * Copy name bytes including NUL terminator
          bne       cv3
          move.l    a1,d0
          btst      #0,d0              * Is address odd?
          beq       cv4                 * No -> word-aligned, ok
          clr.b     (a1)+              * Yes -> add padding byte for alignment
cv4:
          move.l    a1,a2              * a2 = start of value storage
          moveq     #1,d2               * Default: 1 longword for value (INT or STRING ptr)
          btst      #13,d1              * Is it a DEF FN function variable?
          bne       cv4c                * Yes -> just store a pointer
		btst		#12,d1         * Is it a PROC variable?
		bne		cv4c               * Yes -> just store a pointer
		and.w	#INT+FLOAT+STRING,d1  * Mask off proc/fn bits for type check
          cmp.b     #FLOAT,d1           * Float type?
          bne       cv4d
          moveq     #3,d2              * Float needs 3 longwords (12 bytes)
cv4d:
          tst.b     arrayfl             * Is this an array?
          beq       cv4c               * No -> just clear the value storage

* --- Array variable initialization ---
* Store array metadata and zero-fill all elements
          move.l    arraydeep,d1        * Number of dimensions
          move.l    d1,(a2)+           * Write dimension count
          lea       arraylen,a3        * Dimension sizes array
cv4c1:    move.l    (a3)+,d3
          addq.l    #1,d3               * Stored size = specified size + 1 (0-based indexing)
          move.l    d3,fac1
          move.l    d3,(a2)+           * Write this dimension's size
          subq.l    #1,d1
          beq       cv4c2              * Last dimension -> compute total elements
cv4c3:    move.l    (a3)+,d3
          addq.l    #1,d3
          move.l    d3,fac2
          move.l    d3,(a2)+           * Write dimension size
          bsr       submul             * fac1 = fac1 * fac2 (running product)
          subq.l    #1,d1
          bne       cv4c3
cv4c2:
          move.l    d2,fac2            * d2 = longwords per element (1 or 3)
          bsr       submul             * fac1 = total elements * longs per element
          move.l    fac1,d0             * d0 = total longwords to allocate
          move.l    d0,d1
          lsl.l     #2,d1               * d1 = total bytes
          lea       (a2,d1.l),a3       * a3 = end of array data
          move.l    a4,-(sp)
          move.l    strend,a4
          sub.l     #32,a4
          cmp.l     a4,a3                 * Check if array fits in memory
          bge       outvarmem
          move.l    (sp)+,a4
cv4c4:    clr.l     (a2)+              * Zero-fill array elements
          subq.l    #1,d0
          bne       cv4c4
          bra       cv5

* --- Normal (non-array) variable value initialization ---
cv4a:     clr.l     (a2)+               * Clear one longword of value
cv4c:     dbf       d2,cv4a            * Repeat for d2 longwords
cv5:
          move.l    a2,(a4)             * Set next-variable pointer (points to free space)
          move.l    a2,varend           * Update end-of-variables pointer
          clr.l     (a2)               * NULL-terminate the variable list
          movem.l   (sp)+,d0-d7/a2-a6
          rts

*==============================================================================
* ROUTINE: tst_var / tst2_var and related lookup routines
* Purpose: Look up a variable by name in the variable list.
*          Handles multiple scoping contexts:
*          - tst_var: normal variable lookup (fnvarfl=0)
*          - tst2_var: lookup with specific scope (fnvarfl=FNTYP/PROCTYP/etc.)
*          - tst_fnvar: lookup for FN argument variables
*          - tst_prcvar: lookup for PROC-local variables
*          - tst_dprcvar: lookup for PROC definition variables
*
*          Variable scoping: When inside a PROC (procnr != 0), local variables
*          are searched first (matching procnr in type word), then global.
*          The '#' character in a variable name forces global scope.
*
* Parameters: a0 = pointer to variable name in tokenized line
*             d0 = scope flag for tst2_var (0=normal, FNTYP, PROCTYP, etc.)
* Returns:    d0.w = 0 if not found, 1 if found, -1 if found as local
*             a1 = pointer to variable's value storage (if found)
*             typflag = variable's data type
*             arrayfl = 1 if it's an array access (followed by '(')
*             sysvar = system variable code (0=none, -1=pi, -2=ti, -3=ti$)
*==============================================================================
tst_prcvar:
		move.w	procnr,d0          * Use current procedure number as scope
		bra		tstspecVar

tst_dprcvar:
          move.w	#PROCTYP,d0        * Look up PROC definition variable
		bra		tstspecVar

tst_dfnvar:
          move.w    #DEFFNTYP,d0       * Look up DEF FN definition variable
tstspecVar:
          bsr       tst2_var            * Do the lookup with specific scope
          bra       tstsysvar           * Error if it turned out to be a system variable

tst_fnvar:     * Lookup for FN argument variables (FNTYP scope)
          move.w    #FNTYP,d0
          bsr       tst2_var
tstsysvar:     * Error if system variable was found where not allowed
          tst.w     sysvar
          bne       syserr
          rts

*==============================================================================
* tst_var / tst2_var - Main variable lookup implementation
*==============================================================================
tst_var:
          clr.w     d0                 * No special scope (normal variable)
tst2_var:
		move.w	d0,fnvarfl         * Store scope flag

          * --- Handle argument variables (inside FN) ---
          tst.w     argfl               * Are we in FN argument mode?
          beq       tv41proc           * No -> check for procedure scope
          move.l    a0,work2           * Save current position
          move.w    fnvarfl,-(sp)
          move.w    #FNTYP,fnvarfl      * First search FN-local variables
          bsr       tv41               * Do the lookup
          move.w    (sp)+,d1
          tst.w     d0
          bne       tv41found          * Found as FN argument -> return it
		tst.w	fnvarfl            * Was scope cleared (# used)?
		beq		tv41back           * Yes -> only look globally, return not-found
		move.w	d1,fnvarfl         * Restore original scope
          move.l    work2,a0           * Restore position
          bra       tv41                * Try again as normal variable
tv41found:
		moveq.l	#-1,d0             * Return -1 = found as local
tv41back:
		rts

tv41proc:	* When inside a procedure, search local scope first
		move.w	procnr,d1          * Get current procedure number
		beq		tv41               * 0 = main program -> just search normally
		tst.w	d0
		beq		tv41ok             * Called from tst_var -> search local first
		cmp.w	d1,d0
		bne		tv41               * Called with different scope -> search normally
tv41ok:
		move.l	a0,work2           * Save position
		move.w	d1,fnvarfl         * Search with procedure scope
		bsr		tv41
		tst.w	d0
		bne		tv41found          * Found locally -> return -1
		tst.w	fnvarfl            * Was '#' used to force global?
		beq		tv41back           * Yes -> return not-found
		move.l	work2,a0           * Restore position
		clr.w	fnvarfl            * Search globally
		bra		tv41

*==============================================================================
* tv41 - Core variable name parsing and lookup
* Purpose: Parse variable name from input, determine type from suffix
*          ($=STRING, %=INT, !=FLOAT), then search the variable linked list.
*          Also checks for system variables (ti, ti$, pi).
*==============================================================================
tv41:
		cmp.b	#$20,(a0)          * Skip leading spaces
		bne		tva1
		addq.l	#1,a0
		bra		tv41
tva1:
          clr.w     sysvar              * Default: not a system variable
          movem.l   d1-d7/a2-a6,-(sp)
          move.w    #FLOAT,typflag      * Default type is FLOAT (note: comment says "integer" but code says FLOAT)
          clr.b     arrayfl            * Not an array access yet
          lea       var_name,a3        * Destination buffer for variable name
          move.l    a3,a5              * Save start of name buffer
tv4:
          move.b    (a0)+,d0            * Read next character
          move.b    d0,(a3)+           * Copy to name buffer
          beq       tv3a               * NUL -> end of name
		bsr		isvarn             * Is it a valid variable name character?
		beq		tv4                * Yes -> continue reading name
tv4c:
		cmp.b	#'#',d0            * '#' = force global scope?
		bne		tv4noglobl
		subq.l	#1,a3              * Don't store '#' in the name
		move.w	fnvarfl,d0
		beq		tv4                * If already global scope -> ignore
		cmp.w	procnr,d0          * Is scope = current proc number?
		beq		tva1change
		cmp.w	#FNTYP,d0         * Or FNTYP?
		bne		tv4
tva1change:
		clr.w	fnvarfl            * Clear scope -> force global lookup
		bra		tv4

tv4noglobl:
          cmp.b     #'$',d0            * '$' suffix = STRING type
          bne       tv4a
          move.w    #STRING,typflag
          bra       tv3a
tv4a:     cmp.b     #'%',d0            * '%' suffix = INT type
          bne       tv4b
          move.w    #INT,typflag
          bra       tv3a
tv4b:     cmp.b     #'!',d0            * '!' suffix = FLOAT type
          bne       tv4d
          move.w    #FLOAT,typflag
          bra       tv3a
tv4d:

tv3:
          subq.l    #1,a0              * Back up (character was not part of name)
tv3a:
          clr.b     -(a3)              * NUL-terminate the name (overwrite last copied char)

          * Build the full type word including scope flags
		move.w	fnvarfl,d2
		move.w	d2,d0
		and.w	#ARRAYTYP+FNTYP+DEFFNTYP+PROCTYP,d0
          beq		tv3b1               * No special flags -> check for array access
          cmp.w     #FNTYP,d2           * Is it an FN argument lookup?
          bne       tv3STRING           * No -> PROC/DEFFN uses STRING type for storage

          bsr       charget             * Check if array syntax follows
          subq.l    #1,a0
          cmp.b     #'(',d0             * '(' after FN arg name?
          beq       noargerr            * Error: arrays not allowed as FN arguments
          bra       tv3b

tv3STRING:
		move.w	typflag,fntyp      * Remember actual type for later
		move.w	#STRING,typflag    * PROCs and DEFFNs store definitions as strings
		bra		tv3b

tv3b1:    bsr       charget            * Check if array access follows
          subq.l    #1,a0
          cmp.b     #'(',d0             * Parenthesis = array access
          bne       tv3b
          addq.l    #1,a0              * Skip past '('
          bset      #0,arrayfl         * Set array flag

tv3b:     * --- Check for system variables (ti, ti$, pi) ---
          btst      #0,arrayfl
          bne       nosysvar            * Arrays can't be system variables

          lea       var_name,a1         * Check variable name against known sysvars
          move.b    (a1)+,d0
          cmp.b     #'t',d0             * Starts with 't'? -> could be ti/ti$
          bne       sysvar1
          cmp.b     #'i',(a1)+         * Second char 'i'?
          bne       nosysvar
          tst.b     (a1)               * Third char must be NUL (name = "ti")
          bne       nosysvar
          cmp.w     #STRING,typflag    * ti$ (string) or ti (integer)?
          beq       TiString

TiInt:    move.w    #INT,typflag        * ti is always integer
          move.w    #-2,sysvar          * Mark as system variable ti
		bsr		readtime           * Read VBL frame counter ($466 = _frclock) via supervisor mode
		lea		tiint,a1           * Point to storage for ti value
		move.l	d0,(a1)            * Store current time value
          bra       tvar2_found         * Return as found

TiString: move.w    #-3,sysvar         * Mark as system variable ti$
          bsr       clctistr            * Calculate time string (HH:MM:SS)
		lea		tisptr,a1          * Pointer to ti$ string descriptor
          bra       tvar2_found

sysvar1:  cmp.b     #'p',d0             * Starts with 'p'? -> could be pi
          bne       nosysvar
          cmp.b     #'i',(a1)+
          bne       nosysvar
          tst.b     (a1)               * Name must be exactly "pi"
          bne       nosysvar
          cmp.w     #STRING,typflag    * pi$ would be nonsense
          beq       nosysvar
PiInt:    move.w    #FLOAT,typflag     * pi is always float
          move.w    #-1,sysvar         * Mark as system variable pi (read-only)
          lea       pi_,a1              * Point to stored pi constant value
          bra       tvar2_found

nosysvar:
          * --- Search the variable linked list ---
          move.l    varbase,a1          * Start of variable list
		move.w	typflag,d4         * Build the type word we're looking for
		or.w		fnvarfl,d4     * Include scope flags
		tst.b	arrayfl
		beq		tv2
		or.w		#ARRAYTYP,d4   * Include array flag if applicable

tv2:		* d4 = complete type word to match
          move.l    (a1)+,a2           * a2 = next-variable pointer
          cmp.l     #0,a2
          beq       tst_vend            * NULL -> end of list, not found
          move.l    a5,a3              * a3 = our variable name to match
          move.w    (a1)+,d0           * Read this variable's type word
		cmp.w	d4,d0              * Does type match exactly?
          bne       tv7                 * No -> skip to next variable

          * --- Compare variable names character by character ---
tv1:
          move.b    (a1)+,d0           * Char from stored variable name
          move.b    (a3)+,d1           * Char from name we're looking for
          beq       tv6                * Our name ended -> check if stored name also ended
          tst.b     d0
          beq       tv7                * Stored name ended first -> mismatch
          bra       tv5
tv6:
          tst.b     d0
          beq       tvar_found         * Both names ended -> match!
          bne       tv7                * Stored name has more chars -> mismatch
tv5:
          cmp.b     d0,d1
          beq       tv1                 * Characters match -> continue
tv7:
          move.l    a2,a1              * Follow next-pointer to next variable
          bra       tv2                 * Try next variable

tvar_found:
          * --- Variable found! Align a1 to even address ---
          move.l    a1,d0
          btst      #0,d0               * Is address odd?
          beq       tvar2_found         * No -> aligned, done
          addq.l    #1,a1              * Yes -> skip padding byte
tvar2_found:
          moveq.l   #1,d0              * Return 1 = found
          movem.l   (sp)+,d1-d7/a2-a6
          rts
tst_vend:
          moveq     #0,d0              * Return 0 = not found
          movem.l   (sp)+,d1-d7/a2-a6
          rts


*==============================================================================
* SECTION 6: System Variables, HEX$/BIN$, DIR, VARPTR, AES/VDI,
*            GEMDOS/BIOS/XBIOS, Math Functions
*==============================================================================

*==============================================================================
* ROUTINE: setti / settistr
* Purpose: Set the system timer when user assigns to ti or ti$.
*          ti is stored at $466 (_frclock, Atari ST VBL frame counter, ~70 Hz).
* Parameters: fac1 = new value for ti; str_ptr = new value for ti$
*==============================================================================
setti
		move.l	fac1,d0            * Get integer value to set
		bra		writetime          * Write to system timer

settistr:
          move.l    str_ptr,a2          * Get string pointer for ti$
		addq.l	#1,a2              * Adjust for backwards string format
          bsr       readtistr           * Read hours (2 digits from end of string via -(a2))
          move.w    d1,d0
          mulu      #3600,d0           * Hours -> seconds
          bsr       readtistr           * Read minutes
          mulu      #60,d1             * Minutes -> seconds
          add.l     d1,d0
          bsr       readtistr           * Read seconds
          add.l     d1,d0              * d0 = total seconds

          * Convert seconds to 70Hz ticks (Atari ST timer frequency)
		moveq.l	#0,d1
		move.w	d0,d1              * Low word of seconds
		clr.w	d0
		swap		d0             * High word of seconds
		mulu		#70,d0         * High * 70
		swap		d0
		mulu		#70,d1         * Low * 70
		add.l	d1,d0              * d0 = total ticks
          bra		writetime

*==============================================================================
* ROUTINE: readtistr
* Purpose: Read a 2-digit decimal number from the ti$ string (read backwards).
*          Also skips the separator character (':').
* Parameters: a2 = pointer into string (reads via -(a2))
* Returns:    d1.l = parsed 2-digit number
*==============================================================================
readtistr:
          moveq     #0,d1
          move.b    -(a2),d1           * Read ones digit
          sub.b     #'0',d1            * Convert ASCII to value
          move.l    d1,d2
          lsl.l     #3,d1              * d1 = ones * 8
          lsl.l     #1,d2              * d2 = ones * 2
          add.l     d2,d1               * d1 = ones * 10
          moveq     #0,d2
          move.b    -(a2),d2           * Read tens digit
          sub.b     #'0',d2
          add.l     d2,d1               * d1 = tens*10 + ones
          subq.l    #1,a2               * Skip separator character (':')
          rts


*==============================================================================
* ROUTINE: readtime / writetime
* Purpose: Read or write the Atari ST VBL frame counter at address $466 (_frclock, ~70 Hz).
*          Must enter supervisor mode (GEMDOS Super, function $20) to
*          access the protected memory location.
*==============================================================================
readtime:
		movem.l	d7/a0,-(sp)
		clr.l	-(sp)              * Parameter 0 = enter supervisor mode
		move.w	#$20,-(sp)         * GEMDOS function $20 = Super
		trap		#1             * GEMDOS trap
		addq.l	#6,sp              * Clean stack
		move.l	d0,-(sp)           * Save old SSP (to restore later)
		move.l	$466,d7            * Read _frclock (VBL frame counter, ~70 Hz)
		move.w	#$20,-(sp)         * GEMDOS Super again
		trap		#1             * (with old SSP to exit supervisor mode)
		addq.l	#6,sp
		move.l	d7,d0              * Return timer value in d0
		movem.l	(sp)+,d7/a0
		rts


writetime:
		movem.l	d7/a0,-(sp)
		move.l	d0,d7              * Save value to write
		clr.l	-(sp)              * Enter supervisor mode
		move.w	#$20,-(sp)         * GEMDOS Super
		trap		#1
		addq.l	#6,sp
		move.l	d0,-(sp)           * Save old SSP
		move.l	d7,$466            * Write to _frclock (VBL frame counter, ~70 Hz)
		move.w	#$20,-(sp)         * Exit supervisor mode
		trap		#1
		addq.l	#6,sp
		movem.l	(sp)+,d7/a0
		rts


*==============================================================================
* ROUTINE: clctistr
* Purpose: Calculate the ti$ time string from the VBL counter at $466 (_frclock, ~70 Hz).
*          Converts VBL tick count (~70 Hz) to "HH:MM:SS" format, stored backwards
*          in the tistring buffer.
* Parameters: none (reads system timer)
* Returns:    tistring buffer filled with time string
*==============================================================================
clctistr:
		bsr		readtime           * Read system timer -> d0
          lea       tistrend,a1        * a1 = end of time string buffer (write backwards)
		clr.l	d1
clctis2:
		cmp.l	#70*3600*12,d0     * Is it >= 12 hours worth of ticks?
		blo		clctis1
		sub.l	#70*3600*12,d0     * Subtract 12 hours
		add.w	#12,d1             * Add 12 to hour count
		bra		clctis2            * Check again (handles 24+ hour wrap)
clctis1:
		divu		#70,d0         * Convert ticks to seconds (70 ticks/sec)
		and.l	#$ffff,d0          * Keep only quotient (seconds)
		divu		#3600,d0       * Divide by 3600 -> hours in low word
		add.w	d1,d0              * Add the 0/12 hour offset
		swap		d0             * Remainder (seconds within hour) to low word
		moveq.l	#0,d1
		move.w	d0,d1              * d1 = remaining seconds
		swap		d0             * d0 = hours
		divu		#60,d1         * d1 low = minutes, d1 high = remaining seconds

          bsr       wr_tistr            * Write hours as 2 digits into -(a1)
          move.b    #':',-(a1)          * Separator ':'
          move.w    d1,d0
          bsr       wr_tistr            * Write minutes
          move.b    #':',-(a1)
          swap		d1
          move.w	d1,d0
          bsr       wr_tistr           * Write seconds
          clr.b     -(a1)              * NUL terminator at string base
          rts


*==============================================================================
* ROUTINE: wr_tistr
* Purpose: Write a 2-digit number into the time string buffer (backwards).
* Parameters: d0.w = number (0-59)
*             a1 = write position (writes via -(a1))
* Returns:    a1 decremented by 2, digits written
*==============================================================================
wr_tistr:
          moveq     #0,d4
          move.w    d0,d4
          divu      #10,d4              * d4 low = tens digit, d4 high = ones digit
          move.w    d4,d5               * d5 = tens digit
          swap      d4                  * d4 = ones digit
          add.b     #'0',d5
          move.b    d5,-(a1)            * Write tens digit
          add.b     #'0',d4
          move.b    d4,-(a1)            * Write ones digit
          rts


********************************************************************************
* BEFEHLE (Commands):
********************************************************************************

*==============================================================================
* ROUTINE: Hex (HEX$ function)
* Purpose: Convert an integer to a hexadecimal string representation.
* Parameters: Takes integer expression from BASIC line
* Returns:    typflag=STRING, a1=string pointer, a2=dummy (zero_+4)
*==============================================================================
Hex:
          move.w    #INT,typvalid      * We need an integer argument
          bsr       get_term           * Evaluate expression
          lea       iout,a1            * Output buffer
          move.w    #7,d1               * 8 hex digits max (for 32-bit value)
          move.b    #'$',d3            * Prefix character
          move.w    #4,d4              * Bits per hex digit
          move.w    #$f,d5             * Mask per hex digit
* Shared entry point for HEX$ and BIN$
* d3 = prefix char ('$' or '%')
* d1 = number of digits - 1
* d4 = bits to shift per digit
* d5 = mask per digit ($f or $1)
hexbin:
		lea       hextab,a2          * Hex digit lookup table "0123456789abcdef"
		clr.b	(a1)+              * NUL terminator (string stored backwards)
          move.l    fac1,d0            * Get the integer value
hex1:     move.l    d0,d2
          and.w     d5,d2              * Isolate lowest digit
          move.b    0(a2,d2),(a1)+     * Look up and store hex/bin digit
          lsr.l     d4,d0              * Shift right by 4 (hex) or 1 (bin)
          dbf       d1,hex1            * Repeat for all digits

hex2:     tst.b     -1(a1)            * Strip leading zeros
          beq       hex2a              * Already at start -> keep at least "$0"
          cmp.b     #'0',-(a1)          * Is it a leading zero?
          beq       hex2               * Yes -> strip it
hex2a:
		addq.l	#1,a1
	     move.b    d3,(a1)            * Write prefix character ('$' or '%')
          lea       zero_+4,a2         * Dummy end pointer
          move.w    #STRING,typflag    * Result is a string
          rts

*==============================================================================
* ROUTINE: Bin (BIN$ function)
* Purpose: Convert an integer to a binary string representation.
* Parameters: Takes integer expression from BASIC line
* Returns:    typflag=STRING, a1=string pointer, a2=dummy
*==============================================================================
Bin:
          move.w    #INT,typvalid
          bsr       get_term
          lea       inputpuf,a1        * Use input buffer (needs more space for 32 binary digits)
          move.w    #31,d1             * 32 binary digits
          move.b    #'%',d3            * Prefix character
          move.w    #1,d4              * 1 bit per digit
          move.w    #1,d5              * Mask = 1
          bra       hexbin             * Share conversion code with HEX$

*==============================================================================
* ROUTINE: Dir (DIR command)
* Purpose: Display directory listing using GEMDOS Fsfirst ($4E) and Fsnext ($4F).
*          If a path argument is given, uses it; otherwise defaults to "*.*".
*          Displays filenames with size and attributes (P=protected, 7=subdir).
*          Directory names shown in brackets, regular names lowercased.
* Parameters: Optional string path expression
* Returns:    nothing (output to screen/file)
*==============================================================================
Dir:
		move.l	a0,-(sp)           * Save program pointer
		bsr		charget
		beq		nopath             * No argument -> use default "*.*"
		cmp.b	#':',d0
		beq		nopath
		subq.l	#1,a0
		move.w	#STRING,typvalid
		bsr		get_term           * Evaluate path string expression
		subq.l	#1,a0              * Adjust (charget will be called at end)
		move.l	a0,(sp)            * Update saved a0
		move.l	str_ptr,a1         * Get string pointer
		bsr		setdrv             * Check for drive letter (e.g., "A:") and set drive
		move.l	a1,str_ptr
		move.l	#mirrorpuf,mirptr  * Set up mirror buffer for string reversal
		bsr		mirror_str         * Reverse the backwards string -> normal C string in mirrorpuf
		move.l	d0,mirptr          * Update mirror pointer
		move.l	d0,a1
		tst.b	(a1)               * Is the path just a drive letter with no pattern?
		bne		Dir2               * No -> use as-is
		move.b	#'*',(a1)+         * Yes -> append "*.*" wildcard
		move.b	#'.',(a1)+
		move.b	#'*',(a1)+
		clr.b	(a1)
		bra		Dir2
nopath:
		move.l	#joker,mirptr      * Use default wildcard "*.*"

Dir2:
          movem.l   a1-a6,-(sp)         * Save registers

          * Set DTA (Disk Transfer Address) for Fsfirst/Fsnext
          pea       dta_puf             * Push DTA buffer address
          move.w    #$1a,-(sp)         * GEMDOS function $1A = Fsetdta
          trap      #1
          addq.l    #6,sp

          * Search for first matching file
          move.w    #$31,-(sp)          * Search attribute $31 (all files + subdirs)
          move.l	mirptr,-(sp)       * Push path/pattern string
          move.w    #$4e,-(sp)         * GEMDOS function $4E = Fsfirst
          trap      #1
          addq.l    #8,sp
          tst.l     d0                 * Found any files?
          bne       dirend             * No -> done

dirl1:
          * --- Format and display one directory entry ---
		lea       30+dta_puf,a1     * a1 = filename in DTA buffer (offset 30)
          lea       inputpuf,a0         * a0 = output formatting buffer
          move.l    a0,a2
		move.b	#$22,(a2)+         * Opening quote mark '"'

		cmp.b	#$10,dta_puf+21    * Is it a subdirectory? (attr byte at offset 21)
		bne		c2dirname          * No -> lowercase the filename

          * Subdirectory: copy name as-is
dirl2:
		move.b	(a1)+,(a2)+        * Copy dirname character
		bne		dirl2              * Until NUL
		subq.l	#1,a2              * Back up over NUL
		bra		cdir

c2dirname:
          * Regular file: copy name, converting uppercase to lowercase
		move.b    (a1)+,d0
		beq		cdir               * End of name
		cmp.b	#'A',d0
		blo		c2d                * Not uppercase
		cmp.b	#'Z',d0
		bhi		c2d
		add.b	#$20,d0            * Convert to lowercase
c2d:
		move.b	d0,(a2)+
          bra		c2dirname

cdir:
		move.b	#$22,(a2)+         * Closing quote mark '"'

          * Pad filename to 14 characters with spaces
          move.l    a2,d0
          sub.l     a0,d0               * Length of name so far
          move.w    #14,d1
          sub.w     d0,d1               * Number of spaces needed
dirl3:    move.b    #' ',(a2)+
          dbf       d1,dirl3

		move.b	#':',(a2)+         * Separator
		move.b	#$27,(a2)+         * Single quote (') for REM-like appearance
		move.b	#' ',(a2)+

          * Display file attribute character
          move.b    dta_puf+21,d0       * File attribute byte
          bne       dirj1
dirj0:    move.b    #' ',d0            * No attributes -> space
          bra       dirl4
dirj1:    btst      #5,d0               * Bit 5 = archive (opened and closed)
          bne       dirj0              * Archive only -> show space
          cmp.b     #1,d0               * Attribute 1 = write-protected
          bne       dirj3
          move.b    #'P',d0            * Show 'P' for protected
          bra       dirl4
dirj3:    cmp.b     #$10,d0             * Attribute $10 = subdirectory
          bne       nextdir            * Other -> skip (undefined attribute)
          move.b    #7,d0              * Show bell char (ASCII 7) for directories (visual marker)
dirl4:
		move.b    d0,(a2)+           * Write attribute character
          move.w    #2,d0              * 3 trailing spaces
dirl5:    move.b    #' ',(a2)+
          dbf       d0,dirl5
		clr.b	(a2)               * NUL terminate

		bsr		tab_               * Tab to column
		bsr		put_string         * Output the formatted line
          move.l    dta_puf+26,d0       * File size (longword at offset 26 in DTA)
          bsr       ipka_               * Convert to ASCII string (-> a2)
          lea       -1(a2),a0            * Skip sign character
          bsr       putstrreverse      * Display file size
          bsr       new_line           * Newline after each entry

nextdir:
          * --- Search for next matching file ---
          move.w    #$4f,-(sp)         * GEMDOS function $4F = Fsnext
          trap      #1
          addq.l    #2,sp
          tst.l     d0                 * More files?
          beq       dirl1              * Yes -> format and display next entry

dirend:   movem.l   (sp)+,a1-a6        * Restore registers
		move.l	(sp)+,a0           * Restore program pointer
          bra       charget            * Advance past the command

*==============================================================================
* ROUTINE: Varptr (VARPTR function)
* Purpose: Return the memory address of a variable's value storage.
* Parameters: Variable name expression
* Returns:    d0.l = address, typflag = INT
*==============================================================================
Varptr:
          bsr       tst_var             * Look up the variable
          bsr       tstsysvar          * Not allowed for system variables
          move.w    typflag,typvalid
          tst.w     d0
          beq       varperr             * Not yet defined -> error
          tst.b     arrayfl
          beq       varp2
          bsr       posarray            * For arrays: position to element
          bsr       chk_klammer        * Verify closing ')'
varp2:    bsr       charget
          cmp.w     #STRING,typvalid   * For strings: dereference the pointer
          bne       varp1
          move.l    (a1),a1            * Get the actual string address
varp1:    move.l    a1,d0              * Return address as integer
          move.w    #INT,typflag
          rts


*==============================================================================
* ROUTINE: Aes / Vdi
* Purpose: Execute an AES or VDI call with parameters specified inline.
*          Parameters are read as comma-separated integers and placed
*          sequentially into the control/intin arrays. The AES/VDI call
*          is then made via trap #2 with the appropriate parameter block.
* Parameters: Comma-separated integer parameters from BASIC line
* Returns:    nothing
*==============================================================================
Aes:
		moveq.l	#0,d0              * Flag: AES (0)
		lea		AESctrl,a1         * Control array
		lea		AESctrl+20,a2      * Max 10 integers (5 words * 2 bytes, but stored as words)
		bra		execaes
Vdi:
		moveq.l	#1,d0              * Flag: VDI (1)
		lea		VDIctrl,a1
		lea		VDIctrl+24,a2      * Max 12 integers
execaes:
		move.w	d0,-(sp)           * Save AES/VDI flag

		move.l	a0,work1           * Save program pointer
		bsr		charget
		beq		eaesend            * No parameters -> just call
		cmp.b	#':',d0
		beq		eaesend
		bra		eaes3              * Start reading parameters
eaes1:
		move.l	work1,a0
		movem.l	a1/a2,-(sp)
		move.w	#INT,typvalid
		bsr		get_term           * Read integer parameter
		movem.l	(sp)+,a1/a2
		cmp.l	a2,a1
		bge		manyargerr         * Too many parameters -> error
		move.w	fac1+2,(a1)+       * Store parameter word in control/intin array
eaes2:
		bsr		chargot
		beq		eaesend
		cmp.b	#':',d0
		beq		eaesend
		cmp.b	#',',d0            * Comma separates parameters
		bne		syntaxerr
		move.l	a0,work1
		bsr		charget
eaes3:
		cmp.b	#',',d0            * Double comma -> skip one slot (leave default)
		bne		eaes1
		cmp.l	a2,a1
		bge		manyargerr
		addq.l	#2,a1              * Skip one word in array
		bra		eaes2
eaesend:
		tst.w	(sp)+              * Check AES/VDI flag
		beq		aesaes             * 0 = AES

		* VDI call
		move.l	#VDIPB,d1          * VDI parameter block address
		move.w	#$73,d0            * VDI trap code
aesvdi:
		pea		(a0)               * Save a0 (trap may destroy it)
		trap		#2             * GEM trap #2
		move.l	(sp)+,a0           * Restore a0
		rts
aesaes
		move.l	#AESPB,d1          * AES parameter block address
		move.w	#$c8,d0            * AES trap code
		bra		aesvdi


*==============================================================================
* ROUTINES: Aesctrl, Aesintin, Aesintout, Aesadrin, Aesadrout
*           Vdictrl, Vdiintin, Vdiintout, Vdiptsin, Vdiptsout
* Purpose: Direct read/write access to AES and VDI parameter arrays.
*          When used as a command: set array element (offset, value pairs)
*          When used as a function: read array element (offset -> return value)
*          The aesdecide routine checks cmdfktfl to determine read vs write.
*
* Parameters: offset, value (for set); offset (for read)
* Returns:    For read: d0 = value at offset, typflag = INT
*==============================================================================
Aesctrl:
		moveq.l	#1,d1              * Element size: word (lsl 1)
		move.l	#10,d2             * Max 10 entries (0-9)
		lea		AESctrl,a1
		bra		aesdecide

Aesintin:
		moveq.l	#1,d1
		move.l	#128,d2            * Max 128 entries
		lea		AESintin,a1
		bra		setaes

Aesintout:
		moveq.l	#1,d1
		move.l	#128,d2
		lea		AESintout,a1
		bra		readaes

Aesadrin:
		moveq.l	#2,d1              * Element size: longword (lsl 2)
		move.l	#128,d2
		lea		AESadrin,a1
		bra		setaes

Aesadrout:
		moveq.l	#2,d1
		move.l	#128,d2
		lea		AESadrout,a1
		bra		readaes


Vdictrl:
		moveq.l	#1,d1
		move.l	#12,d2             * Max 12 entries
		lea		VDIctrl,a1
		bra		aesdecide

Vdiintin:
		moveq.l	#1,d1
		move.l	#128,d2
		lea		VDIintin,a1
		bra		setaes

Vdiintout:
		moveq.l	#1,d1
		move.l	#128,d2
		lea		VDIintout,a1
		bra		readaes

Vdiptsin:
		moveq.l	#1,d1
		move.l	#128,d2
		lea		VDIptsin,a1
		bra		setaes

Vdiptsout:
		moveq.l	#1,d1
		move.l	#128,d2
		lea		VDIptsout,a1
		bra		readaes


*==============================================================================
* Subroutines for AES/VDI array access
*==============================================================================

* aesdecide: Check if being called as command (set) or function (read)
aesdecide:
		tst.w	cmdfktfl           * 0=command, nonzero=function
		bne		readaes            * Function -> read mode

* setaes: Write values to an AES/VDI array
* Parameters: d1 = element shift (1=word, 2=long), d2 = max entries, a1 = array base
setaes:
		movem.l	d1/d2/a1,-(sp)
		move.w	#INT,typvalid
		bsr		get_term           * Get array offset
		movem.l	(sp)+,d1/d2/a1
		move.l	fac1,d0
		bmi		negerr             * Negative offset -> error
		cmp.l	d2,d0
		bpl		aesrangeerr        * Offset >= max -> error
		lsl.l	d1,d0              * Multiply by element size
		pea		0(a1,d0)           * Push address of element
		bsr		chk_komma          * Verify comma
		movem.l	d1/d2/a1,-(sp)
		move.w	#INT,typvalid
		bsr		get_term           * Get value to write
		movem.l	(sp)+,d1/d2/a1
		move.l	(sp)+,a2           * Pop element address
		move.w	fac1+2,(a2)        * Write value (word)
		bsr		chargot
		cmp.b	#',',d0            * More offset,value pairs?
		bne		setaes1
		addq.l	#1,a0              * Skip comma
		bra		setaes             * Read next pair
setaes1:
		rts

* readaes: Read a value from an AES/VDI array
readaes:
		movem.l	d1/d2/a1,-(sp)
		move.w	#INT,typvalid
		bsr		get_term           * Get array offset
		movem.l	(sp)+,d1/d2/a1
		move.l	fac1,d0
		bmi		negerr
		cmp.l	d2,d0
		bpl		aesrangeerr
		lsl.l	d1,d0              * Multiply by element size
		move.w	#INT,typflag       * Result is integer
		cmp.w	#1,d1              * Word-sized elements?
		beq		readwaes
		move.l	0(a1,d0),d0        * Read longword
		rts
readwaes:
		move.w	0(a1,d0),d0        * Read word
		ext.l	d0                 * Sign-extend to longword
		rts

*==============================================================================
* ROUTINE: Gemdos / Bios / Xbios
* Purpose: Call an Atari ST operating system function by number.
*          Uses parameter descriptor tables (gemdtbl, biostbl, xbiostbl)
*          that describe each function's parameters (type and size).
*          Parameters are read from the BASIC line, pushed onto the stack,
*          and the appropriate trap instruction is executed.
*
*          The descriptor tables have the format:
*          [max_function_number].w
*          [pointer to descriptor for each function...].l
*          Each descriptor: {[type].w [size_flag].w}... [0].w
*          type = INT or STRING
*          size_flag = 0 for .w (word), 1 for .l (longword)
*
* Parameters: Function number, then parameters as specified by descriptor
* Returns:    d0.l = return value from trap, typflag = INT
*==============================================================================
mirptr	.ds.l	1                  * Pointer for mirror_str buffer management

Gemdos:
          moveq.l   #1,d0               * Trap #1
          lea       gemdtbl,a1          * GEMDOS parameter descriptor table
          bra       callsys
Bios:     moveq.l   #13,d0              * Trap #13
          lea       biostbl,a1          * BIOS parameter descriptor table
          bra       callsys
Xbios:    moveq.l   #14,d0              * Trap #14
          lea       xbiostbl,a1         * XBIOS parameter descriptor table
callsys:
          and.w     #$fff0,calltrap    * Clear low nibble of trap instruction
          or.w      d0,calltrap         * Set trap number (1, 13, or 14)
          move.l    a1,-(sp)
          move.w    #INT,typvalid       * First parameter: function number (integer)
          bsr       get_term
          move.l    (sp)+,a1
          move.l    fac1,d0            * Function number
          cmp.w     (a1)+,d0            * Compare with max allowed function number
          bpl       callerr             * Too high -> error
          lea       inputpuf,a2         * Use inputpuf as temporary stack data buffer
          move.w    d0,(a2)+            * Store function number as first stack word
          lsl.l     #2,d0               * *4 for longword pointer table
          move.l    0(a1,d0),d0        * Get pointer to this function's parameter descriptor
          bmi		callerr            * Negative (-1) = function not supported
          move.l	d0,a1              * a1 = parameter descriptor
		move.l	#mirrorpuf,mirptr  * Initialize mirror buffer for string params
          bra       calls4              * Start reading parameters

calls0:   move.w    (a1)+,typvalid     * Read parameter type from descriptor
          move.l    a1,-(sp)
          move.l    a2,-(sp)
          bsr       get_term            * Evaluate the parameter expression
          cmp.w     #STRING,typvalid    * Was it a string parameter?
          bne       calls1
		bsr		mirror_str         * Yes -> reverse the backwards string to normal C string
          bra       calls2

calls1:   move.l    fac1,d0            * Integer parameter value
calls2:   move.l    (sp)+,a2
          move.l    (sp)+,a1
          tst.w     (a1)+               * Read size flag: 0=word, 1=longword
          beq       calls3              * Word parameter
          move.l    d0,(a2)+           * Store as longword
          bra       calls4
calls3:   move.w    d0,(a2)+            * Store as word

calls4:   tst.w     (a1)                * Check if more parameters expected (0 = end)
          beq       calls5
          bsr       chk_komma          * Verify comma between parameters
          bra       calls0             * Read next parameter

calls5:   * --- All parameters read, now push them onto the real stack ---
          move.l    a0,-(sp)            * Save BASIC program pointer
          move.l    sp,spstr           * Save stack pointer for restoration
          bsr       onqlist            * Save state on cross-reference list
calls6    move.w    -(a2),-(sp)         * Push parameters in reverse order (right to left)
          cmp.l     #inputpuf,a2       * Pushed all data?
          bne       calls6

calltrap: trap      #0                  * This instruction is self-modifying!
                                       * The trap number was patched to 1, 13, or 14
          bsr       offqlist           * Restore state from cross-reference list
          move.l    spstr,sp           * Restore stack pointer
          move.l    (sp)+,a0           * Restore BASIC program pointer
          move.w    #INT,typflag       * Return type is integer
          rts

*==============================================================================
* ROUTINE: mirror_str
* Purpose: Reverse a backwards-stored BASIC string into a normal C string.
*          Used when passing strings to GEMDOS/BIOS/XBIOS functions,
*          which expect normal forward strings.
*          Copies into the mirrorpuf buffer area, advancing mirptr.
* Parameters: str_ptr = pointer to backwards string
* Returns:    d0.l = pointer to the mirrored (forward) string
*             mirptr updated past the copied string
*==============================================================================
mirror_str:
		movem.l	d1/a0-a2,-(sp)

		move.l	str_ptr,a0
		addq.l	#1,a0              * Point past the end of backwards string
		move.l	a0,a2              * Save for reverse copy
		moveq.l	#0,d1              * Count string length
mir_tstlen:
		addq.l	#1,d1
		tst.b	-(a0)              * Scan backwards to find NUL terminator
		bne		mir_tstlen

		cmp.l	#mirrorpend-mirrorpuf,d1  * Would string overflow mirror buffer?
		bpl		outvarmem          * Yes -> error

		move.l	mirptr,d0          * d0 = destination in mirror buffer
		move.l	d0,a1
		add.l	d1,mirptr          * Advance mirptr past this string
mir_copy:
		move.b	-(a2),(a1)+        * Copy in reverse (backwards -> forward)
		subq.l	#1,d1
		bne		mir_copy

		movem.l	(sp)+,d1/a0-a2
		rts


*==============================================================================
* ROUTINE: Cursor
* Purpose: Position the cursor at a given column and row (1-based).
*          If no arguments, acts as HOME (move to 0,0).
* Parameters: column, row (both 1-based integers)
*==============================================================================
Cursor:
          bsr       tstnxtarg          * Is there a next argument?
          bne       Home               * No -> just do HOME
          move.w    #INT,typvalid
          bsr       get_term           * Get column
		subq.l	#1,fac1            * Convert 1-based to 0-based
		bmi		start1err          * Was 0 -> error (must be >= 1)
          move.l    fac1,-(sp)
          bsr       chk_komma
          move.w    #INT,typvalid
          bsr       get_term           * Get row
		subq.l	#1,fac1
		bmi		start1err
          move.l    fac1,d1            * Row
          move.l    (sp)+,d0           * Column
          move.l    edibase,a1
          move.w    edi_breit(a1),d2   * Window width in pixels
          lsr.w     #4,d2              * Divide by 16 (assuming 8-pixel font with some math)

          cmp.l     maxspalten,d0      * Validate column
          bge       cposerr
          cmp.w     d2,d1              * Validate row
          bge       cposerr
          bra       ed_pos             * Position cursor via editor routine

*==============================================================================
* ROUTINE: Home
* Purpose: Move cursor to position 0,0 (top-left corner)
*==============================================================================
Home:     bsr       ed_clrhome          * Clear and home via editor routine
          bra       charget

*==============================================================================
* ROUTINE: Cls
* Purpose: Clear the editor screen
*==============================================================================
Cls:
          bsr       ed_clr             * Call editor clear-screen routine
          bra       charget

*==============================================================================
* ROUTINE: Cont
* Purpose: Continue program execution after a STOP.
*          Restores the saved program position and re-enters program mode.
*==============================================================================
Cont:
          move.l    contline,d0        * Is there a saved CONT position?
          bmi       conterr             * Negative -> "can't continue"
          move.l    d0,akt_zeile       * Restore line number
          move.l    contladr,akt_adr   * Restore line address
          move.l    contadr,a0         * Restore program pointer
          move.w    #-1,b_modus        * Re-enter program mode
          bra       runcont            * Continue execution

*==============================================================================
* ROUTINE: Stop
* Purpose: Stop program execution. Allows CONTinuation later.
*==============================================================================
Stop:
          bsr       charget             * Advance past STOP token
          bra       stoperr            * Jump to stop error handler

*==============================================================================
* ROUTINE: Call
* Purpose: Call machine code at an address with optional register parameters.
*          Syntax: CALL(address [,d0_val] [,d1_val]... [,*a0_val] [,*a1_val]...)
*          The '*' prefix marks address register parameters.
*          Supports up to 8 data registers (d0-d7) and 7 address registers (a0-a6).
* Parameters: address, optional register values
* Returns:    d0 = return value in d0 after the call, typflag = INT
*==============================================================================
calltbld0:	.ds.l	8		* Storage for d0-d7 register values
calltbla0:	.ds.l	7      * Storage for a0-a6 register values
calltblend:
Call:
		* Save current register state (supports recursive CALL)
		lea		calltbld0,a1
		movem.l	(a1)+,d0-d7        * Load current d0-d7 from storage
		movem.l	d0-d7,-(sp)        * Push onto stack
		movem.l	(a1)+,d0-d6        * Load current a0-a6 from storage
		movem.l	d0-d6,-(sp)        * Push onto stack

		* Read call address
		move.w	#INT,typvalid
		bsr		get_term
		move.l	fac1,-(sp)         * Save target address on stack
		clr.w	d6                 * d6 = data register counter
		clr.w	d7                 * d7 = address register counter
		lea		calltbld0,a5       * a5 = data register value buffer
		lea		calltbla0,a6       * a6 = address register value buffer

callgetregs:
		bsr		tst_komma          * Is there another parameter?
		bne		nocallparam        * No -> done reading parameters
		move.l	a0,d1              * Save position
		bsr		charget
		cmp.b	#'*',d0            * '*' prefix = address register
		bne		noadrreg

useadrregs:
		addq.w	#1,d7              * Increment address register count
		cmp.w	#7,d7              * Max 7 address registers
		bhi		manyargerr
		moveq.l	#1,d5              * d5=1 -> store in address register buffer
		bra		call1

noadrreg
		move.l	d1,a0              * Restore position (no '*' found)
		cmp.w	#8,d6              * All 8 data regs full?
		bge		useadrregs         * Yes -> overflow to address registers
		addq.w	#1,d6
		moveq.l	#0,d5              * d5=0 -> store in data register buffer

call1:
		move.l	a0,d1
		bsr		charget
		cmp.b	#',',d0            * Double comma (,,) -> skip this register (keep default)
		beq		call1c
		cmp.b	#')',d0            * Closing paren -> also skip (end of params)
		bne		call1a
call1c
		clr.l	fac1               * Default value = 0
		bra		call1b
call1a:
		move.l	d1,a0              * Restore position
		movem.l	d5/d6/d7/a5/a6,-(sp)
		move.w	#INT,typvalid
		bsr		get_term           * Evaluate register value
		movem.l	(sp)+,d5/d6/d7/a5/a6
call1b:
		tst.w	d5                 * Data or address register?
		beq		callwrd0
callwra0:
		move.l	fac1,(a6)+         * Store in address register buffer
		bra		callgetregs
callwrd0:
		move.l	fac1,(a5)+         * Store in data register buffer
		bra		callgetregs

nocallparam:
		* --- Execute the call ---
		move.l	(sp)+,fac1         * Target address
		move.l	a0,-(sp)           * Save BASIC program pointer
		movem.l	calltbld0,d0-d7    * Load d0-d7 with specified values
		movem.l	calltbla0,a0-a6    * Load a0-a6 with specified values
		bsr		jumpfac1           * JSR to the target address
		move.l	(sp)+,a0           * Restore BASIC program pointer

		* Save returned register values
		lea		calltblend,a1
		movem.l	(sp)+,d1-d7        * Restore previous a0-a6 from stack
		movem.l	d1-d7,-(a1)       * Save current a0-a6 state
		movem.l	(sp)+,d1-d7/a2     * Restore previous d0-d7 from stack
		movem.l	d1-d7/a2,-(a1)    * Save current d0-d7 state
		move.w	#INT,typflag       * Return value is integer (d0)
		rts


*==============================================================================
* ROUTINE: Sys
* Purpose: Jump to a memory address and execute machine code there.
*          Simpler than CALL - no register parameter passing.
* Parameters: Integer expression = target address
* Returns:    nothing (whatever the called code returns in d0)
*==============================================================================
Sys:
          move.w    #INT,typvalid
          bsr       get_term
          move.l    a0,-(sp)           * Save BASIC program pointer
		bsr		jumpfac1           * Jump to the address
          move.l    (sp)+,a0           * Restore program pointer
          rts

*==============================================================================
* ROUTINE: jumpfac1
* Purpose: Execute a JSR to the address stored in fac1.
*          Uses self-modifying code to set the jump target.
* Parameters: fac1 = target address
* Returns:    whatever the called routine returns
*==============================================================================
jumpfac1:
		btst		#0,fac1+3      * Check if address is odd
		bne		oddadrerr          * Odd address -> error (68000 requires even)
		move.l	fac1,jumptomem+2   * Patch the JMP instruction's address
jumptomem:
		jmp		$12345678          * Self-modifying: address is patched above

*==============================================================================
* ROUTINE: Rnd (RND function)
* Purpose: Generate a random number.
*          RND(0) -> return last random number (unchanged)
*          RND(1) -> generate new random number using seed
*          RND(x) -> multiply current random by x and regenerate
* Parameters: Float expression
* Returns:    d0-d3 = float result, typflag = FLOAT
*==============================================================================
Rnd:
          lea       rrand_,a1          * Load address of random number generator routine
          bsr       trig_arg           * Evaluate argument (float)
		movem.l	fac1,d4-d7
		lea		zero_,a1           * Compare with 0.0
		cmp.l	(a1)+,d4
		bne		rndnozero
		cmp.l	(a1)+,d5
		bne		rndnozero
		cmp.l	(a1),d6
		bne		rndnozero
		rts                        * x=0 -> return current random (no change)
rndnozero:
		lea		one_,a1            * Compare with 1.0
		cmp.l	(a1)+,d4
		bne		rndnoone
		cmp.l	(a1)+,d5
		bne		rndnoone
		cmp.l	(a1),d6
		bne		rndnoone
		rts                        * x=1 -> return current random (already generated)
rndnoone:
		move.l	a0,-(sp)
		bsr		rmul_              * Multiply random by argument
		move.l	(sp)+,a0
		rts

*==============================================================================
* ROUTINE: Sgn (SGN function)
* Purpose: Return the sign of a number: -1, 0, or 1.
*          Works with both INT and FLOAT types.
* Parameters: Numeric expression (accepts STRING typvalid to detect any type)
* Returns:    d0.l = -1, 0, or 1; typflag = INT
*==============================================================================
Sgn:
          move.w    #STRING,typvalid   * Accept any type (STRING typvalid = accept all)
          bsr       gets_term          * Evaluate expression
          move.w    #INT,typflag        * Return type is integer
		move.w	typ2flag,d0        * What type was the expression?
		cmp.b	#STRING,d0
		beq		NADDI_             * String -> type mismatch
		cmp.b	#INT,d0
		beq		sgnint
sgnfloat:
		movem.l	fac1,d0-d2         * Load float value
		lea		zero_,a1           * Compare with 0.0
		cmp.l	(a1)+,d0
		bne		sgnfl1
		cmp.l	(a1)+,d1
		bne		sgnfl1
		cmp.l	(a1),d2
		beq		sgnequal           * All zero -> result is 0
sgnfl1:
		btst		#31,d0         * Test sign bit of float
		beq		sgnpos
		bra		sgnneg
sgnint:
		move.l	fac1,d0
		beq		sgnequal           * Zero
		bmi		sgnneg             * Negative
sgnpos:
          moveq.l   #1,d0              * Positive -> return 1
		rts
sgnneg
		moveq.l	#-1,d0             * Negative -> return -1
		rts
sgnequal:
		moveq.l	#0,d0              * Zero -> return 0
		rts


*==============================================================================
* ROUTINE: Abs (ABS function)
* Purpose: Return the absolute value of a number.
* Parameters: Numeric expression
* Returns:    d0(-d2) = absolute value, typflag = same as input type
*==============================================================================
Abs:
          move.w    #STRING,typvalid   * Accept any type
          bsr       gets_term
          movem.l   fac1,d0-d3
          move.w    typ2flag,typflag   * Preserve input type
          cmp.w     #FLOAT,typ2flag
          beq       absfloat
          cmp.w     #INT,typ2flag
          bne       typemis            * String -> type mismatch
absint:   btst      #31,d0              * Is integer negative?
          beq       absend             * No -> already positive
          neg.l     d0                 * Yes -> negate it
absend:   rts
absfloat: bclr      #31,d0              * Clear sign bit of float (make positive)
          rts

*==============================================================================
* Math function wrappers
* Each of these loads the address of the corresponding floating-point
* routine and calls trig_arg, which evaluates the argument and calls
* the math function.
*==============================================================================

Sqr:      * SQR() - square root
          lea       rsqrt_,a1
          bra       trig_arg
Ln:       * LN() - natural logarithm
          lea       rlog_,a1
          bra       trig_arg
Log:      * LOG() - base-10 logarithm
          lea       rlog10_,a1
          bra       trig_arg
Exp10:    * EXP10() - 10^x
          lea       rexp10_,a1
          bra       trig_arg
Exp:      * EXP() - e^x
          lea       rexp_,a1
          bra       trig_arg
Tan:      * TAN() - tangent
          lea       rtan_,a1
          bra       trig_arg

*==============================================================================
* ROUTINE: Mod (MOD function)
* Purpose: Compute the positive remainder: x MOD y.
*          Takes two arguments separated by comma.
*==============================================================================
Mod:
          lea       rmod_,a1
          bra       trig3_arg          * Two-argument math function

*==============================================================================
* ROUTINE: Atnpt (ATNPT function)
* Purpose: Compute arctangent of a point (atan2(x,y)).
*          Takes two arguments separated by comma.
*==============================================================================
Atnpt:
          lea       ratan2_,a1

*==============================================================================
* ROUTINE: trig3_arg
* Purpose: Helper for two-argument math functions: func(x, y)
*          Evaluates both arguments, places them in d0-d3 and d4-d7,
*          then calls the math routine.
*==============================================================================
trig3_arg:move.l    a1,-(sp)            * Save function address
          move.w    #FLOAT,typvalid
          bsr       get_term           * Evaluate first argument (x)
          movem.l   fac1,d0-d3
          movem.l   d0-d3,-(sp)        * Save first argument
          bsr       chk_komma          * Verify comma
          move.w    #FLOAT,typvalid
          bsr       get_term           * Evaluate second argument (y)
          movem.l   fac1,d4-d7         * y in d4-d7
          movem.l   (sp)+,d0-d3        * x in d0-d3
          move.l    (sp)+,a1           * Restore function address
          bra       trig2_arg          * Call the function

Atn:      * ATN() - arctangent
          lea       ratan_,a1
          bra       trig_arg
Cos:      * COS() - cosine
          lea       rcos_,a1
          bra       trig_arg
Sin:      * SIN() - sine
          lea       rsin_,a1

*==============================================================================
* ROUTINE: trig_arg / trig2_arg
* Purpose: Helper for single-argument math functions.
*          trig_arg: evaluate argument, load into d0-d3, call function
*          trig2_arg: just call function (d0-d3 and d4-d7 already loaded)
* Parameters: a1 = address of math routine
* Returns:    d0-d3 = result, typflag = FLOAT
*==============================================================================
trig_arg: move.w    #FLOAT,typvalid
          move.l    a1,-(sp)
          bsr       get_term             * Evaluate argument
          move.l    (sp)+,a1
          movem.l   fac1,d0-d3         * Load argument into d0-d3
trig2_arg:move.w    #FLOAT,typflag     * Result is always float
          move.l    a0,-(sp)           * Save BASIC program pointer
          jsr       (a1)               * Call the math routine
          move.l    (sp)+,a0           * Restore program pointer
          rts

*==============================================================================
* ROUTINES: Lpeek, Dpeek, Peek - Memory read functions
* Purpose: Read 32-bit, 16-bit, or 8-bit values from memory addresses.
* Parameters: Integer expression = memory address
* Returns:    d0.l = value, typflag = INT
*==============================================================================
Lpeek:    * LPEEK(addr) - read 32-bit longword
          move.w    #INT,typvalid
          bsr       get_term            * Get address
          move.l    fac1,a1
          move.l    a1,d0
          btst      #0,d0               * Check for odd address
          bne       oddadrerr           * 68000 requires even addresses for word/long access
          move.l    (a1),d0            * Read longword
          move.w    #INT,typflag
          rts

Dpeek:    * DPEEK(addr) - read 16-bit word (sign-extended)
          move.w    #INT,typvalid
          bsr       get_term
          move.l    fac1,a1
          move.l    a1,d0
          btst      #0,d0
          bne       oddadrerr
          move.w    (a1),d0            * Read word
          ext.l     d0                  * Sign-extend to longword
          move.w    #INT,typflag
          rts

Peek:     * PEEK(addr) - read 8-bit byte (sign-extended)
          move.w    #INT,typvalid
          bsr       get_term
          move.l    fac1,a1
extbyte:  move.b    (a1),d0            * Read byte
          ext.w     d0                  * Sign-extend to word
          ext.l     d0                  * Sign-extend to longword
          move.w    #INT,typflag
          rts

*==============================================================================
* ROUTINES: Lpoke, Dpoke, Poke - Memory write commands
* Purpose: Write 32-bit, 16-bit, or 8-bit values to memory addresses.
* Parameters: address, value (both integers, comma-separated)
*==============================================================================
Lpoke:    * LPOKE addr, value - write 32-bit longword
          bsr       get_poke            * Get address and value
          move.l    d0,(a1)            * Write longword
          rts

*==============================================================================
* ROUTINE: get_poke
* Purpose: Helper to read address and value parameters for POKE commands.
* Parameters: Two comma-separated integer expressions
* Returns:    a1 = address, d0 = value
*==============================================================================
get_poke:
          move.w    #INT,typvalid
          bsr       get_term           * Get address
          move.l    fac1,-(sp)          * Save address
          bsr       chk_komma
          move.w    #INT,typvalid
          bsr       get_term           * Get value
          move.l    (sp)+,a1           * Restore address
          move.l    a1,d0
          btst      #0,d0
          bne       oddadrerr           * Odd address error for word/long
          move.l    fac1,d0            * Return value in d0
          rts

Dpoke:    * DPOKE addr, value - write 16-bit word
          bsr       get_poke
          move.w    d0,(a1)
          rts

Poke:     * POKE addr, value - write 8-bit byte
          move.w    #INT,typvalid
          bsr       get_term
          move.l    fac1,-(sp)
          bsr       chk_komma
          move.w    #INT,typvalid
          bsr       get_term
          move.l    (sp)+,a1
          move.l    fac1,d0
          move.b    d0,(a1)             * Write byte (no alignment check needed)
          rts

*==============================================================================
* ROUTINE: Cmd
* Purpose: Redirect all output to a file handle until the next file operation.
*          Syntax: CMD #handle
* Parameters: File handle (via get_handle)
*==============================================================================
Cmd:
          bsr       get_handle         * Read and validate file handle
          move.w    #-1,cmdfl                * Enable CMD mode
          move.w    #-1,filefl               * Redirect output to file
          rts

*==============================================================================
* SECTION 7: NOT, POS, String Functions, WAIT, AUTO, TRACE, DUMP,
*            GET, RESTORE, READ/DATA, REM, IF/THEN/ELSE, FOR/NEXT,
*            CLOSE, OPEN/CREATE, ON...GOTO/GOSUB, INPUT
*==============================================================================

*==============================================================================
* ROUTINE: Not (NOT function)
* Purpose: Bitwise NOT of an integer value.
* Parameters: Integer expression
* Returns:    d0.l = bitwise complement, typflag = INT
*==============================================================================
Not:
          move.w    #INT,typvalid
          bsr       get_term
          move.w    #INT,typflag
          move.l    fac1,d0
          not.l     d0                 * Bitwise complement
          subq.l    #1,a0               * Back up one character (for expression parser)
          rts

*==============================================================================
* ROUTINE: Pos (POS function)
* Purpose: Return the current cursor column position (0-based).
* Parameters: Dummy argument (ignored, for BASIC syntax compatibility)
* Returns:    d0.l = cursor column, typflag = INT
*==============================================================================
Pos:
          move.w    #INT,typvalid
          bsr       get_term            * Read and discard the dummy argument
          move.w    #INT,typflag
          moveq     #0,d0
          move.w    ed_x,d0            * Current cursor X position
          add.w     ed_xoffs,d0        * Plus any horizontal scroll offset
          rts

*==============================================================================
* ROUTINE: Mid (MID$ function)
* Purpose: Extract a substring starting at a given position with given length.
*          Syntax: MID$(string$, start, length)
*          Positions are 1-based.
* Parameters: String, start position (integer), length (integer)
* Returns:    a1 = modified string pointer, typflag = STRING
*==============================================================================
Mid:
          bsr       strpos             * Get string pointer (a1) and position (d0)
		addq.l	#1,d0              * Adjust position
          lea       0(a1,d0.l),a1       * Point to start of substring
          bsr       chk_komma
          move.l    a1,spstr           * Save string pointer
		bsr		onqlist            * Push to cross-reference list
          move.w    #INT,typvalid
          bsr       get_term           * Get length parameter
		bsr		offqlist           * Pop from cross-reference list
          move.l    spstr,a1           * Restore string pointer
          move.l    fac1,d0
          neg.l     d0                 * Negate (for backwards string offset)
          move.w    #STRING,typflag
          move.l    a1,a2
          addq.l    #1,a2
mid1:     tst.b     -(a2)               * Find string length
          bne       mid1
          sub.l     a1,a2
          cmp.l     d0,a2
          bgt       strposerr           * Position out of range
          lea       zero_+4,a2          * Dummy end pointer
          clr.b     0(a1,d0.l)         * Truncate string at start+length
          rts

*==============================================================================
* ROUTINE: Right (RIGHT$ function)
* Purpose: Return the rightmost N characters of a string.
*          Syntax: RIGHT$(string$, count)
* Parameters: String, count (integer)
* Returns:    a1 = pointer to rightmost portion, typflag = STRING
*==============================================================================
Right:
          bsr       strpos             * Get string pointer and position
          sub.l     d0,a3               * Calculate start of rightmost N chars
          move.l    a3,a1              * Return pointer to that position
          rts

*==============================================================================
* ROUTINE: Left (LEFT$ function)
* Purpose: Return the leftmost N characters of a string.
*          Syntax: LEFT$(string$, count)
* Parameters: String, count (integer)
* Returns:    a1 = string pointer with truncation, typflag = STRING
*==============================================================================
Left:
          bsr       strpos             * Get string pointer and position
          clr.b     0(a1,d0.l)          * Truncate string at position N
          rts

*==============================================================================
* ROUTINE: Instr (INSTR function)
* Purpose: Find the position of one string within another.
*          Syntax: INSTR(haystack$, needle$ [,startpos])
*          Returns 0 if not found, 1-based position if found.
* Parameters: Two strings and optional start position
* Returns:    d0.l = position (1-based) or 0, typflag = INT
*==============================================================================
Instr:
		move.l	strend,spstr       * Save string end pointer
		bsr		onqlist
		bsr		initstrpos         * Get first string (haystack)
		bsr		chk_komma
		move.l	str_ptr,spstr
		bsr		onqlist
		bsr		initstrpos         * Get second string (needle)
		move.l	str_ptr,spstr
		bsr		onqlist
		moveq.l	#0,d1              * Default start position = 0
		bsr		tst_komma          * Optional third parameter?
		bne		noinstrpos
		move.w	#INT,typvalid
		bsr		get_term           * Get start position
		move.l	fac1,d1
		bmi		start1err          * Negative -> error
		subq.l	#1,d1              * Convert 1-based to 0-based
		bmi		start1err
noinstrpos:
		neg.l	d1                 * Negate for backwards string offset
		bsr		offqlist           * Get needle string
		move.l	spstr,a1
		bsr		offqlist           * Get haystack string
		move.l	spstr,a2
		move.l	a2,a5              * Save haystack base
		lea		0(a2,d1.l),a3      * a3 = starting search position
		tst.l	d1                 * If start=0, skip position validation
		beq		instr2
		addq.l	#1,a2
instr1:
		tst.b	-(a2)              * Validate start position is within string
		beq		strposerr          * Reached NUL before position -> error
		cmp.l	a2,a3
		bne		instr1

instr2:
		* --- Main search loop ---
		tst.b	(a3)               * End of haystack?
		beq		instrend           * Yes -> not found
		move.l	a3,a2              * Current haystack position
		move.l	a1,a4              * Needle pointer
		addq.l	#1,a2
		addq.l	#1,a4
instr3:
		move.b	-(a4),d0           * Next needle char (reading backwards)
		beq		instrfound         * Reached NUL -> full needle matched!
		move.b	-(a2),d1           * Next haystack char
		beq		instrend           * End of haystack without full match
		cmp.b	d0,d1
		beq		instr3             * Chars match -> continue
instrnotfound:
		subq.l	#1,a3              * Move to next position in haystack
		bra		instr2             * Try again

instrend:
		moveq.l	#0,d0              * Return 0 = not found
		bra		instr4
instrfound:
		sub.l	a3,a5              * Calculate position (backwards offset)
		move.l	a5,d0
		addq.l	#1,d0              * Convert to 1-based
instr4:
		move.w	#INT,typflag
		bsr		offqlist           * Restore string end
		move.l	spstr,strend
		rts


*==============================================================================
* ROUTINE: initstrpos
* Purpose: Helper for string functions - evaluate a string expression.
*==============================================================================
initstrpos:
		move.w	#STRING,typvalid
		bsr		get_defterm        * Evaluate string expression
		cmp.b	#STRING,typvalid+1
		bne		NADDI_             * Not a string -> type mismatch
		rts

*==============================================================================
* ROUTINE: strpos
* Purpose: Helper for RIGHT$, LEFT$, MID$ - get string and position.
*          Evaluates the string argument and integer position argument.
* Returns:    a1 = string pointer, a3 = end of string, d0 = negated position
*==============================================================================
strpos:
          move.l    strend,spstr       * Save string end
          bsr       onqlist             * Push to cross-reference list
		bsr		initstrpos         * Get the string
          bsr       chk_komma
          move.l    str_ptr,spstr
          bsr       onqlist
          move.w    #INT,typvalid
          bsr       get_term           * Get the position
          bsr       offqlist
          move.l    spstr,a1           * Restore string pointer
          bsr       offqlist
          move.l    spstr,strend       * Restore string end
          move.l    fac1,d0
          move.w    #STRING,typflag
          move.l    a1,a2
          addq.l    #1,a2
strp1:    tst.b     -(a2)                    * Find length of string
          bne       strp1
          move.l    a2,a3              * a3 = base (start) of string
          sub.l     a1,a2
          neg.l     d0                 * Negate position for backwards offset
          cmp.l     d0,a2
          bgt       strposerr           * Position beyond string length -> error
          lea       zero_+4,a2          * Dummy end pointer
          rts


*==============================================================================
* ROUTINE: Chr (CHR$ function)
* Purpose: Return a single-character string from an ASCII code.
* Parameters: Integer expression = ASCII code
* Returns:    a1 = string pointer, typflag = STRING
*==============================================================================
Chr:
          move.w    #INT,typvalid
          bsr       get_term
          move.l    fac1,d0             * ASCII code
storebyte:
          * Store a single byte as a backwards string at strend
          move.l    strend,a1
          move.l    a1,a2
          move.b    d0,(a2)             * Write the character (at top of string area)
          clr.b     -(a2)              * NUL terminator below it
          lea       zero_+4,a2         * Dummy end pointer
          move.w    #STRING,typflag
          rts

*==============================================================================
* ROUTINE: Inkey (INKEY$ function)
* Purpose: Read a single character from the keyboard without waiting.
*          Returns the character as a 1-character string.
* Parameters: none
* Returns:    String with the character (or empty if no key pressed)
*==============================================================================
Inkey:
		move.l	a0,-(sp)
		move.w	#7,-(sp)           * GEMDOS function #7 = Crawcin
		trap		#1             * Wait for and read a character
		addq.l	#2,sp
		move.l	(sp)+,a0
		bra		storebyte          * Convert to single-char string


*==============================================================================
* ROUTINE: Wait
* Purpose: Pause execution for N/70 seconds.
*          Uses XBIOS Vsync (function 37) which waits for one vertical blank
*          (approximately 1/70 second on PAL, 1/60 on NTSC).
* Parameters: Integer expression = number of 1/70-second ticks
*==============================================================================
Wait:
		move.w	#INT,typvalid
		bsr		get_term           * Get tick count
		move.l	a0,-(sp)           * Save program pointer
wait1:
		move.w	#37,-(sp)          * XBIOS function #37 = Vsync
		trap		#14            * XBIOS trap
		addq.l	#2,sp
		subq.l	#1,fac1            * Decrement counter
		bpl		wait1              * Still positive -> wait more
		move.l	(sp)+,a0           * Restore program pointer
		rts


*==============================================================================
* ROUTINE: Auto
* Purpose: Enable automatic line numbering mode.
*          Syntax: AUTO [startline [,increment]]
*          Default start=100, default increment=10
*==============================================================================
Auto:
		bsr		getoptparam        * Read optional start and increment parameters
		tst.l	d6                 * Start line = 0?
		bne		auto1
		moveq.l	#100,d6            * Default start = 100
auto1:
		tst.l	d7
		beq		start1err          * Increment must not be 0
		cmp.l	#$7fffffff,d7      * Was increment not specified (default)?
		bne		auto2
		moveq.l	#10,d7             * Default increment = 10
auto2:
		move.l	d6,autozeile       * Store start line number
		move.l	d7,autoadd         * Store increment

		move.w	#1,autofl          * Enable AUTO mode
		rts


*==============================================================================
* ROUTINE: Tron / Troff
* Purpose: Enable or disable trace mode.
*          When trace is on (tracefl=1), each command is displayed before
*          execution, showing the line number and the command text.
*==============================================================================
tracefl:	.dc.w	0		* Trace flag: 0=off, 1=on, 2=returning from trace gosub
Tron:
		move.w	#1,tracefl         * Enable trace
		bra		charget
Troff:
		clr.w	tracefl            * Disable trace
		bra		charget

*==============================================================================
* ROUTINE: trace
* Purpose: Display trace information for the current command.
*          Shows "line_number: command_text" on the first line of screen
*          (or on a new line if output goes to file).
*          If traceline is set (via ON TRACE GOSUB), performs a GOSUB
*          to the trace handler routine.
*
* Parameters: d0 = current token byte, a0 = pointer after token
* Returns:    nothing (output to screen/file)
*==============================================================================
trace:
		movem.l	d0/a0-a2,-(sp)     * Save registers
		move.l	a0,work1           * Save program pointer
		lea		var2_name,a1       * Output buffer
		move.b	#':',(a1)+         * Format: ": command..."
		move.b	#' ',(a1)+
		clr.b	d1                 * d1 = quote tracking flag
		bra		trace1

trace2:
		move.b	(a0)+,d0           * Read next byte from line
		beq		traceend           * NUL -> end of line
trace1:
		cmp.b	#':',d0            * Colon = command separator
		bne		trace1a
		tst.b	d1                 * But only if not inside a string
		beq		traceend           * Outside string -> stop here
trace1a:
		cmp.b	#TOKEN1,d0         * Token intro byte?
		beq		trtoken
		cmp.b	#TOKEN2,d0
		beq		trtoken
		cmp.b	#TOKEN3,d0
		bne		trnotoken

trtoken:
		* Expand token to its keyword name
		and.w	#$ff,d0
		lsl.w	#2,d0              * Index into token address table
		lea		tokenadr,a2
		move.l	(a2,d0),a2         * Get token name string table for this class
		move.b	(a0)+,d0           * Token index
		lsl.w	#2,d0
		move.l	(a2,d0.w),a2       * Get pointer to token name string

trtoken1:
		move.b	(a2)+,d0           * Copy token name to output buffer
		beq		trace2             * End of name -> continue with next byte
		bclr		#7,d0          * Clear abbreviation bit
		cmp.b	#'a',d0
		bmi		tr2aa
		cmp.b	#'z'+1,d0
		bpl		tr2aa
		sub.b	#$20,d0            * Convert lowercase to uppercase for display
tr2aa:
		move.b	d0,(a1)+           * Write character to output buffer
		bra		trtoken1

trnotoken:
		cmp.b	#'"',d0            * Quote -> toggle string tracking
		bne		trnotok2
		not.b	d1
trnotok2:
		move.b	d0,(a1)+           * Copy non-token character to output
		bra		trace2

traceend:
		move.b	d0,(a1)+           * Write final character (: or NUL)
		clr.b	(a1)               * NUL-terminate output
		move.l	akt_zeile,d0       * Current line number
		bsr		ipka_              * Convert to ASCII
		move.l	a2,a0
		subq.l	#1,a0              * Skip sign character

		tst.w	filefl             * Output to file?
		bne		notrhome
		move.w	ed_y,try           * Save cursor position
		move.w	ed_x,d0
		add.w	ed_xoffs,d0
		move.w	d0,trx
		clr.w	ed_y               * Position to top of screen
		bsr		ed_clrline         * Clear the trace display line
		bra		trhome
notrhome:
		bsr		new_line           * For file output: just newline
trhome:
		bsr		putstrreverse      * Display line number
		lea		var2_name,a0
		bsr		put_string         * Display ": command_text"

		* Check if ON TRACE GOSUB is active
		move.l	traceline,d0
		bmi		notrgos            * Negative -> no trace gosub
		bsr		new_line
		move.l	work1,d1           * Current program pointer
		subq.l	#1,d1              * Back to token intro byte
		bset		#31,d1         * Set bit 31: flag for trace return
		move.l	d1,a0
		move.l	d0,fac1            * Trace gosub target line
		clr.w	tracefl            * Disable trace during gosub (re-enabled on return)
		lea		stack,sp
		bra		Gosub1             * Execute GOSUB to trace handler

notrgos:
		tst.w	filefl
		bne		notr2home
		move.w	trx,d0             * Restore cursor position
		move.w	try,d1
		bsr		ed_pos
notr2home:

		* Wait for keypress (allows user to single-step)
		move.w	#7,-(sp)           * GEMDOS Crawcin
		trap		#1
		addq.l	#2,sp
		swap		d0
		cmp.b	#$61,d0            * UNDO key?
		beq		stoperr            * Yes -> stop program

		movem.l	(sp)+,d0/a0-a2     * Restore registers
		rts


*==============================================================================
* ROUTINE: Dump
* Purpose: Display all defined variables and their current values.
*          Syntax: DUMP [bitmask]
*          Bitmask bits: 1=FLOAT, 2=INT, 4=STRING, 8=arrays, 16=only non-zero
*          Default (no argument) = 31 (show all types including non-zero check)
* Parameters: Optional integer bitmask
* Returns:    nothing (output to screen/file)
*==============================================================================
dumpfl:	.ds.b	1                  * Dump filter bitmask
dump2fl:	.ds.b	1              * Current type being dumped (1, 2, 4)
dmpstr1:	.dc.b	" = ",0        * Separator string
dmpa0:	.ds.l	1                  * Saved program pointer for break checking

Dump:
		move.l	a0,work1
		bsr		charget
		beq		dmpnoarg           * No argument -> dump all
		cmp.b	#':',d0
		beq		dmpnoarg
		move.l	work1,a0
		move.w	#INT,typvalid
		bsr		get_term           * Read bitmask
		move.l	fac1,d0
		bra		dmparg
dmpnoarg:
		moveq.l	#1+2+4+8+16,d0    * Default: all types + arrays + only-occupied filter
dmparg:
		move.b	d0,dumpfl          * Store filter bitmask
		move.b	#1,dump2fl         * Start with type 1 (FLOAT)
		move.l	a0,dmpa0           * Save program pointer for break checking

dmp2:
		move.b	dump2fl,d0
		and.b	dumpfl,d0          * Is current type requested?
		bne		dmp1               * Yes -> scan variables
dmp2a:
		move.b	dump2fl,d0
		lsl.b	d0                 * Next type (1->2->4)
		move.b	d0,dump2fl
		cmp.b	#8,dump2fl         * All basic types done? (1,2,4 -> next would be 8)
		beq		dumpend
		bra		dmp2

dmp1:
		move.l	varbase,a1         * Start scanning variable list
dumploop:
		move.l	(a1)+,d7           * Next-variable pointer
		beq		dmp2a              * End of list -> next type
		move.w	(a1)+,d0           * Type word
		move.w	d0,d6              * Save full type
		and.w	#$7ff8,d0          * Check for FN/DEFFN/PROC flags
		bne		dumpnext           * Skip function/procedure variables
		cmp.b	dump2fl,d6         * Matches current dump type?
		bne		dumpnext           * No -> skip

		* Copy variable name to output buffer
		lea		var2_name,a2
dmp3:
		move.b	(a1)+,(a2)+        * Copy name
		bne		dmp3
		move.l	a1,d0
		btst		#0,d0          * Align to even address
		beq		dmpeven
		addq.l	#1,a1
dmpeven:
		* Add type suffix to name
		move.b	#'!',d0            * Default: '!' for FLOAT
		cmp.b	#INT,d6
		bne		dmp4
		move.b	#'%',d0            * '%' for INT
		bra		dmp5
dmp4:
		cmp.b	#STRING,d6
		bne		dmp5
		move.b	#'$',d0            * '$' for STRING
dmp5:
		move.b	d0,-1(a2)          * Append suffix to name
		clr.b	(a2)               * NUL terminate

		btst		#15,d6         * Is it an array?
		bne		dumparray          * Yes -> special array dump
		bsr		dmpvar             * No -> dump single variable
		bra		dumpnext

*==============================================================================
* dmpvar - Display a single variable's value
* Parameters: d6 = type, a1 = pointer to value (advanced past value on return)
*==============================================================================
dmpvar:
		movem.l	d6/d7/a2-a6,-(sp)
		cmp.b	#STRING,d6
		bne		dmpnostr

		* String variable
		move.l	(a1)+,d0           * Get string pointer
		tst.l	d0
		beq		dumprts            * NULL -> skip
		btst		#4,dumpfl      * Bit 4: only show non-empty?
		beq		dmpstr
		cmp.l	#zero_+4,d0        * Empty string constant?
		beq		dumprts
		move.l	d0,a0
		tst.b	(a0)               * Empty content?
		beq		dumprts
dmpstr:
		bsr		dumptext           * Output "varname = "
		lea		key,a0
		move.w	#$2200,(a0)        * Output opening quote '"'
		bsr		put_string
		move.l	d0,a0
		bsr		putstrreverse      * Output string value (backwards)
		lea		key,a0
		bsr		put_string         * Output closing quote '"'
dumprts:
		movem.l	(sp)+,d6/d7/a2-a6
		rts

dmpnostr:
		cmp.b	#INT,d6
		bne		dmpnoint
		* Integer variable
		move.l	(a1)+,d0
		btst		#4,dumpfl      * Only non-zero?
		beq		dmpint
		tst.l	d0
		beq		dumprts            * Zero -> skip
dmpint:
		bsr		dumptext           * Output "varname = "
		move.l	a1,-(sp)
		bsr		ipka_              * Convert integer to ASCII
dmpfloat:
		move.l	(sp)+,a1
		move.l	a2,a0
		bsr		putstrreverse      * Output the number
		bra		dumprts

dmpnoint:
		* Float variable
		movem.l	(a1)+,d0-d2        * Read 3 longwords
		clr.l	d3
		btst		#4,dumpfl      * Only non-zero?
		beq		dmpfl
		lea		zero_,a0           * Compare with 0.0
		cmp.l	(a0)+,d0
		bne		dmpfl
		cmp.l	(a0)+,d1
		bne		dmpfl
		cmp		(a0),d2
		beq		dumprts            * Zero -> skip
dmpfl:
		bsr		dumptext           * Output "varname = "
		move.l	a1,-(sp)
		bsr		rpka_              * Convert float to ASCII
		bra		dmpfloat

dumpnext:
		move.l	d7,a1              * Follow next-variable pointer
		bsr		dmpchkstop         * Check for user break
		bra		dumploop

*==============================================================================
* dumptext - Output variable name and " = " separator
* For arrays, also outputs the current index in parentheses.
*==============================================================================
dumptext:
		btst		#15,d6         * Array?
		bne		dtarray
		bsr		new_line
		lea		var2_name,a0
		bsr		put_string         * Output variable name
		lea		dmpstr1,a0
		bra		put_string         * Output " = "

dtarray:
		bsr		new_line
		lea		var2_name,a0
		bsr		put_string         * Output array name
		lea		key,a0
		move.w	#$2800,(a0)        * Output '('
		bsr		put_string
		move.b	#',',(a0)          * Prepare comma separator
		movem.l	d0-d3/a1-a6,-(sp)

		lea		inputpuf+100,a1    * Current index values buffer
dta1:
		move.l	(a1)+,d0           * Get current dimension index
		bmi		dtaend             * -1 = sentinel -> done
		move.l	a1,-(sp)
		bsr		ipka_              * Convert index to ASCII
		move.l	(sp)+,a1
		lea		-1(a2),a0
		bsr		putstrreverse      * Output index number
		tst.l	(a1)               * More dimensions?
		bmi		dtaend
		lea		key,a0
		bsr		put_string         * Output comma between indices
		bra		dta1
dtaend:
		lea		key,a0
		move.w	#$2900,(a0)        * Output ')'
		bsr		put_string

		movem.l	(sp)+,d0-d3/a1-a6
		lea		dmpstr1,a0
		bra		put_string         * Output " = "


*==============================================================================
* dumparray - Iterate through all elements of an array and dump each one.
* Uses the dimension information to generate all index combinations.
*==============================================================================
dumparray:
		btst		#3,dumpfl      * Bit 3: interested in arrays?
		beq		dumpnext           * No -> skip
		lea		inputpuf,a2
		move.l	a2,a4              * a4 = max dimension values
		lea		inputpuf+100,a3    * a3 = current index values
		move.l	a3,a5
		move.l	(a1)+,d0           * Number of dimensions
		move.l	d0,d2
		subq.l	#1,d2              * Last dimension index (0-based)
		lsl.l	#2,d2              * *4 for longword offset
		move.l	d2,(a2)+           * Store offset to last dimension
dmpa1:
		move.l	(a1)+,d2           * Read dimension max size
		subq.l	#1,d2              * Convert to 0-based max index
		move.l	d2,(a2)+           * Store max index
		clr.l	(a3)+              * Initialize current index to 0
		subq.l	#1,d0
		bne		dmpa1
		moveq.l	#-1,d0
		move.l	d0,(a2)            * Sentinel after max values
		move.l	d0,(a3)            * Sentinel after current indices

dmpanext:
		move.l	(a4),d0            * Offset to last dimension
dmpa3:
		lea		0(a5,d0),a2        * Point to current index for this dimension
		move.l	4(a4,d0),d2        * Max value for this dimension
		cmp.l	(a2),d2            * Has last dimension reached max?
		bge		dmpaok             * No -> dump this element
dmpa2:
		clr.l	(a2)+              * Reset this dimension to 0
		cmp.l	#-1,(a2)           * Was this the first dimension?
		bne		dmpa2              * No -> reset all trailing dimensions
		subq.l	#4,d0              * Move to previous dimension
		bmi		dumpnext           * All dimensions exhausted -> done
		lea		(a5,d0),a2
		addq.l	#1,(a2)            * Increment previous dimension
		move.l	4(a4,d0),d2
		cmp.l	(a2),d2
		blt		dmpa2              * Previous dim also at max -> carry
		bsr		dmpvar             * Dump the element
		move.l	(a4),d0
		addq.l	#1,(a5,d0)         * Increment last dimension
		bra		dmpa2ok
dmpaok:
		bsr		dmpvar             * Dump the current element
		addq.l	#1,(a2)            * Increment last dimension index
dmpa2ok:
		bsr		dmpchkstop         * Check for user break
		bra		dmpanext           * Next element

*==============================================================================
* dmpchkstop - Check for break during DUMP operation
*==============================================================================
dmpchkstop:
		movem.l	d0-a6,-(sp)
		move.l	dmpa0,a0
		bsr		chk_stop           * Check ALT+UNDO
		movem.l	(sp)+,d0-a6
		rts

dumpend:
		move.l	dmpa0,a0           * Restore program pointer
		rts



*==============================================================================
* ROUTINE: Swapvars (SWAP command)
* Purpose: Exchange the values of two variables of compatible types.
*          Handles INT<->INT, FLOAT<->FLOAT, STRING<->STRING,
*          and INT<->FLOAT with automatic conversion.
* Parameters: Two variable references separated by comma
*==============================================================================
Swapvars:
		bsr		var2_def           * Get first variable -> a1
		cmp.l	#0,a6              * Cancel any mark_str
		beq		swap1
		clr.b	(a6)               * Unmark string (prevent GC during swap)
swap1:
		move.l	a1,-(sp)           * Save first variable pointer
		move.w	typvalid,-(sp)     * Save first variable type
		bsr		charget            * Skip comma
		bsr		var2_def           * Get second variable -> a1
		cmp.l	#0,a6
		beq		swap2
		clr.b	(a6)               * Unmark second string too
swap2:
		move.w	(sp)+,d0           * First variable type
		move.l	(sp)+,a2           * First variable pointer
		move.w	typvalid,d1        * Second variable type

		cmp.b	#INT,d0
		beq		swapint
		cmp.b	#FLOAT,d0
		beq		swapfloat

swapstr:   * STRING <-> STRING swap
		cmp.b	#STRING,d1
		bne		NADDI_             * String + non-string -> type mismatch
swap1int:  * Simple 4-byte swap (works for INT and STRING)
		move.l	(a1),d0
		move.l	(a2),(a1)
		move.l	d0,(a2)
		bra		charget

swapint:   * INT <-> INT or INT <-> FLOAT
		cmp.b	#STRING,d1
		beq		NADDI_             * INT + STRING -> mismatch
		cmp.b	#INT,d1
		beq		swap1int           * INT + INT -> simple swap
		* INT + FLOAT -> convert and swap
		movem.l	(a1),d0-d2         * Read float from var2
		clr.l	d3
		bsr		rpkl               * Convert float to int -> d0
		move.l	(a2),d4            * Read int from var1
		move.l	d0,(a2)            * Write converted int to var1
		bsr		ltor_              * Convert old int to float -> d0-d2
		movem.l	d0-d2,(a1)         * Write float to var2
		bra		charget

swapfloat: * FLOAT <-> FLOAT or FLOAT <-> INT
		cmp.b	#STRING,d1
		beq		NADDI_
		cmp.b	#FLOAT,d1
		beq		swap1float         * FLOAT + FLOAT -> 12-byte swap
		* FLOAT + INT -> convert and swap
		move.l	(a1),d4            * Read int from var2
		bsr		ltor_              * Convert to float -> d0-d2
		movem.l	(a2),d4-d6         * Read float from var1
		movem.l	d0-d2,(a2)         * Write converted float to var1
		move.l	d4,d0
		move.l	d5,d1
		move.l	d6,d2
		clr.l	d3
		bsr		rpkl               * Convert old float to int -> d0
		move.l	d0,(a1)            * Write int to var2
		bra		charget

swap1float: * Pure FLOAT <-> FLOAT swap (3 longwords each)
		movem.l	(a1),d4-d6
		movem.l	(a2),d0-d2
		movem.l	d4-d6,(a2)
		movem.l	d0-d2,(a1)
		bra		charget


*==============================================================================
* ROUTINE: Asc (ASC function)
* Purpose: Return the ASCII code of the first character of a string.
* Parameters: String expression
* Returns:    d0.l = ASCII code (sign-extended), typflag = INT
*==============================================================================
Asc:
          move.w    #STRING,typvalid
          bsr       get_term
          move.l    str_ptr,a1         * Get string pointer
          bra       extbyte             * Read and sign-extend first byte

*==============================================================================
* ROUTINE: Val / Function (VAL function)
* Purpose: Convert a string to its numeric value.
*          The string is first reversed (from backwards to forward),
*          then parsed as a numeric expression.
* Parameters: String expression
* Returns:    d0-d3 = float value, typflag = FLOAT
*==============================================================================
Val:
Function:
          move.w    #STRING,typvalid
          bsr       get_term            * Get string -> str_ptr
          move.l    a0,-(sp)           * Save program pointer

          * Reverse the backwards string in-place to make it forward
          move.l    str_ptr,a0
          addq.l    #1,a0
          move.l    a0,a1              * a1 = end of string
lll1:
          tst.b     -(a0)              * Find NUL base of backwards string
          bne       lll1
          move.l    a0,a2              * a2 = start (NUL end)
lll2:
          move.b    (a2),d0            * Swap characters from both ends
          move.b    -(a1),(a2)+
          move.b    d0,(a1)
          cmp.l     a2,a1
          bgt       lll2               * Continue until pointers meet

          * Now parse the forward string as a number
          move.w    #FLOAT,typvalid
          bsr       get_term            * Parse the number

          move.l    (sp)+,a0           * Restore program pointer
          move.w    #FLOAT,typflag
          movem.l   fac1,d0-d3
          rts

*==============================================================================
* ROUTINE: Str (STR$ function)
* Purpose: Convert a numeric expression to its string representation.
* Parameters: Numeric expression (INT or FLOAT)
* Returns:    String result, typflag = STRING
*==============================================================================
Str:
          move.w    #STRING,typvalid    * Accept any type
          bsr       gets_term           * Evaluate expression
          move.l    a0,-(sp)            * Save program pointer
          move.w    typ2flag,d0         * What type was evaluated?
          beq       misargerr           * No expression -> error
          cmp.w     #FLOAT,d0
          beq       strfl
          cmp.w     #INT,d0
          bne       NADDI_              * String input not allowed
          move.l    fac1,d0
          bsr       ipka_               * Integer to ASCII -> a2
          bra       str1a
strfl:    movem.l   fac1,d0-d3
          bsr       rpka_              * Float to ASCII -> a2

str1a:    * Copy the ASCII representation into string space (backwards)
          move.l    strend,a1           * Current string end
          move.l    a1,a3
          addq.l    #1,a3
str1b:    move.b    -(a2),-(a3)        * Copy ASCII chars into string space (reversing)
          bne       str1b              * Until NUL terminator
          move.l    (sp)+,a0           * Restore program pointer
          lea       zero_+4,a2          * Dummy end pointer
          move.w    #STRING,typflag
          rts

*==============================================================================
* ROUTINE: Len (LEN function)
* Purpose: Return the length of a string.
* Parameters: String expression
* Returns:    d0.l = string length, typflag = INT
*==============================================================================
Len:
          move.w    #STRING,typvalid
          bsr       get_term
          move.w    #INT,typflag
          move.l    str_ptr,a1         * String pointer (points to end of backwards string)
          move.l    a1,a2
		addq.l	#1,a2
len1:     tst.b     -(a2)              * Scan backwards to find NUL base
          bne       len1
          sub.l     a2,a1              * Length = end - base
          move.l    a1,d0
          rts

*==============================================================================
* ROUTINE: Get (GET command)
* Purpose: Read a single character from keyboard or file into a string variable.
*          Syntax: GET var$ (keyboard) or GET #handle, var$ (file)
*          For keyboard: non-blocking (returns empty string if no key available)
*          For file: blocking read of one byte
* Parameters: Optional file handle, then string variable
*==============================================================================
Get:
          move.l    a0,work2
          bsr       charget
          cmp.b     #'#',d0             * File input?
          bne       Getkey

          * --- File GET ---
          bsr       get_handle          * Read file handle
          bsr       chk_komma
          bsr       getI               * Get string variable -> a1
          bsr		getII              * Allocate/prepare string storage
          move.l    a1,-(sp)
Get1:     lea       key,a1
          moveq.l   #1,d0              * Read 1 byte
          bsr       f_read              * Read from file via GEMDOS Fread ($3F)
          move.b    key,d0
          cmp.b     #10,d0              * Linefeed (LF)?
          beq       Get1               * Yes -> skip it (CR+LF handling)
          move.l    (sp)+,a1
          bra       Get2               * Store the character

* --- Keyboard GET (non-blocking) ---
Getkey:   move.l    work2,a0
          bsr       getI               * Get string variable -> a1
		move.w	d0,work2           * Save getI result flag

		move.l	a0,-(sp)
		move.l	a1,-(sp)
		move.w	#$b,-(sp)          * GEMDOS function $0B = Cconis (console input status)
		trap		#1
		addq.l	#2,sp
		move.l	(sp)+,a1
		move.l	(sp)+,a0
		tst.w	d0                 * Any character available?
		bne		charavailable      * Yes -> read it

		* No character available -> return empty string
		tst.w	work2
		beq		getkey1            * Variable was new -> already has empty string
		bsr		mark_str           * Mark old string for GC
getkey1:
		move.l	#zero_+4,(a1)      * Set to empty string
		bra		charget

charavailable:
		tst.w	work2              * Prepare string storage
		bsr		getII
		move.l	a0,-(sp)
          move.l    a1,-(sp)
          move.w    #7,-(sp)           * GEMDOS function #7 = Crawcin
          trap      #1                  * Read the character
          addq.l    #2,sp
          move.l    (sp)+,a1
		move.l	(sp)+,a0

Get2:     move.l    (a1),a1            * Dereference string pointer
          move.b    d0,(a1)            * Store the character
          clr.b     -(a1)              * NUL terminator below it
          bra       charget


*==============================================================================
* getI / getII - Helper routines for GET command
* getI: Look up or create the string variable
* getII: Prepare string storage (allocate if new, reuse if possible)
*==============================================================================
getI:
          bsr       tst_var             * Look up variable
          bsr       tstsysvar          * Not allowed for system variables
          move.w    typflag,typvalid
          cmp.w     #STRING,typvalid    * Must be a string variable
          bne       NADDI_
          move.w    d0,-(sp)           * Save found/not-found flag
          tst.w     d0
          bne       get1                * Already defined
          bsr       create2_var        * Create it
get1:
          tst.b     arrayfl
          beq       get2
          bsr       posarray            * Position to array element
          bsr       chk_klammer
get2:
          move.w    (sp)+,d0            * Return found/not-found flag
		rts

getII:	* Note: status register from getI still valid
          bne       get3               * Variable was already defined
get3a:
          move.l    strend,(a1)        * Point variable to current string end
          subq.l    #2,strend           * Allocate 2 bytes (char + NUL)
          move.l    strend,d0
          sub.l     #32,d0             * Safety margin
          cmp.l     varend,d0
          bmi       outvarmem          * Out of memory
          bra       get4
get3:
          move.l    (a1),a2            * Get existing string pointer
		cmp.l	#0,a2
		beq		get3a              * NULL -> allocate new
		tst.b	(a2)               * Empty/dummy string?
		beq		get4a
          tst.b     -1(a2)              * Can we reuse existing 1-char string?
		beq		get4               * Yes -> reuse it
get4a:
		bsr		mark_str           * Mark old string for GC
          bra       get3a              * Allocate new
get4:
          rts

*==============================================================================
* ROUTINE: restore (lowercase) / Restore (uppercase)
* Purpose: Reset the DATA pointer.
*          restore (internal): reset to program start
*          Restore (BASIC command): optionally reset to a specific line
*==============================================================================
restore:
          moveq.l   #-1,d0
          move.l    d0,dataptr         * -1 = need to search for DATA
          move.l    d0,dataadr         * No DATA line known yet
          move.l    prgbase,restadr    * Start searching from program beginning
          rts

Restore:
          bsr       restore            * First do the default reset
          bsr       tstnxtarg          * Is there a line number argument?
          bne       rest1               * No -> done
          move.w    #INT,typvalid
          bsr       get_term           * Get line number
          move.l    fac1,d0
          bsr       poszeile           * Find the line
          tst.l     (a1)                * Does the line exist?
          beq       nolineerr          * No -> error
          move.l    a1,restadr         * Set restore address to this line
          rts
rest1:    bra       charget

*==============================================================================
* ROUTINE: posdata
* Purpose: Search for the next DATA statement starting from a given line.
*          Scans through program lines looking for the DATA token.
* Parameters: a1 = pointer to first line to search
* Returns:    BNE if found (dataptr and dataadr updated)
*             BEQ if not found (no more DATA in program)
*==============================================================================
posdata:
          move.l    a0,a6              * Save program pointer
          move.l    a1,a0
posd2:    move.l    (a0),d7            * Next-line pointer
          beq       posd2end                 * NULL -> end of program, no DATA
          move.l    a0,a1              * Save line start
          addq.l    #8,a0                    * Skip header (next ptr + line number)
posd1:    bsr       charget                  * Read token intro byte
          lsl.w     #8,d0                    * Shift to high byte
          move.b    (a0)+,d0                 * Read token index
          cmp.w     #DATA,d0                 * Is it a DATA token?
          beq       posdend                  * Yes -> found!
          bsr       dtonxtcmd                * No -> skip to next command (respecting strings)
          tst.b     -1(a0)
          bne       posd1                    * Not end of line -> check next command
posdnl:   move.l    d7,a0                    * End of line -> go to next line
          bra       posd2

posdend:  move.l    a0,dataptr               * Save pointer to data after DATA token
          move.l    a1,dataadr               * Save pointer to the DATA line
          move.l    a6,a0                    * Restore program pointer
          moveq.l   #1,d0                    * Return BNE (found)
          rts

posd2end: move.l    #-1,dataptr              * No more DATA
          clr.l     dataadr
          move.l    a6,a0
          moveq     #0,d0                    * Return BEQ (not found)
          rts

*==============================================================================
* ROUTINE: Read (READ command)
* Purpose: Read values from DATA statements into variables.
*          Maintains dataptr/dataadr to track current position in DATA.
*          Automatically searches for the next DATA when current is exhausted.
* Syntax: READ var1 [,var2...]
*==============================================================================
Read:
readmore: tst.l     dataptr             * Is there a known DATA position?
          bpl       read1                    * Yes (>=0) -> use it
          tst.l     dataadr                  * Any DATA lines remaining?
          beq       nodataerr               * No -> "out of data" error
          move.l    restadr,a1               * Start searching from restore address
          bsr       posdata                  * Find next DATA
          beq       nodataerr               * None found -> error

read1:    bsr       var2_def                 * Get target variable -> a1, typvalid
          move.l    a0,-(sp)                 * Save BASIC program pointer
          move.l    a1,-(sp)                 * Save variable value pointer
          move.l    dataptr,a0               * Point to DATA values
          bsr       get_defterm              * Evaluate next DATA value
          move.l    (sp)+,a1
          bsr       write_var                * Write value to variable
          bsr       tst_komma                * Is there another DATA value?
          beq       read2                    * Yes -> save position
          * No more values on this DATA line -> find next DATA
          move.l    dataadr,a1               * Current DATA line
          move.l    (a1),d7                  * Next-line pointer
          tst.b     d0                       * Was it end of line (NUL)?
          beq       read4                    * Yes -> search from next line
          cmp.b     #':',d0                  * Colon -> more commands on this line
          bne       syntaxerr
          bsr       posd1                    * Search for DATA on rest of this line
          bra       read3
read4:    bsr       posdnl                   * Search from next line
          bra       read3

read2:    move.l    a0,dataptr               * Save position within DATA for next READ
read3:    move.l    (sp)+,a0                 * Restore BASIC program pointer
          bsr       charget
          cmp.b     #',',d0                  * More variables to read?
          beq       readmore                * Yes -> read next
          rts

*==============================================================================
* ROUTINE: Rem (REM command)
* Purpose: Program comment. Rest of line is ignored.
*          Implemented by jumping to iffalse which skips to end of line.
*==============================================================================
Rem
          bra       iffalse            * Skip to end of line

*==============================================================================
* ROUTINE: Else
* Purpose: Alternative branch for IF...THEN...ELSE.
*          Pops the IF result from the IF table and acts inversely:
*          if IF was true (executed THEN), skip ELSE; if false, execute ELSE.
*==============================================================================
Else:
          move.l    ifendptr,a1        * Get IF table pointer
          cmp.l     #iftbl,a1          * Is table empty?
          beq       elseerr            * Yes -> "else without if" error
          subq.l    #4,a1              * Pop one entry
          move.l    a1,ifendptr
          move.l    (a1),d0             * Get IF condition result (0 or 1)
          beq       iftrue              * IF was false -> execute ELSE (= "true" here)
          bra       iffalse            * IF was true -> skip ELSE

*==============================================================================
* ROUTINE: If (IF command)
* Purpose: Conditional execution: IF expr THEN commands [ELSE commands]
*          Evaluates the expression; if true (non-zero), executes THEN part.
*          If false (zero), skips to end of line (or ELSE on next line).
*
*          The ELSE mechanism: if an ELSE exists on the next line, the IF
*          result is pushed onto the iftbl so ELSE can check it.
*==============================================================================
If:
          move.w    #INT,typvalid
          bsr       get_term            * Evaluate condition expression
          bsr       tstelse             * Check if next line starts with ELSE
          bne       if1                 * No ELSE -> don't need to save result
          * ELSE exists -> save IF result on stack for ELSE to check
          move.l    ifendptr,a1
          cmp.l     #endiftbl-4,a1      * Table full?
          bge       ifflow             * Yes -> "if overflow" error
          move.l    fac1,(a1)+         * Push IF result (0 or non-zero)
          move.l    a1,ifendptr

if1:      tst.l     fac1                * Check condition: true (non-zero) or false (0)?
          beq       iffalse             * False -> skip rest of line

          * True -> verify THEN keyword and execute
          bsr       chargot             * Read next token
          move.b    d0,d1
          lsl.w     #8,d1              * Build 16-bit token
          move.b    (a0)+,d1
          cmp.w     #THEN,d1           * Must be THEN
          bne       thenerr             * Missing THEN -> error

iftrue:   addq.l    #4,sp               * Pop return address (skip back to exec_line's JSR)
          bra       exec1              * Continue executing commands on this line

iffalse:  addq.l    #4,sp               * Pop return address
          bra       exec_end            * Skip to end of line (execute next line)

*==============================================================================
* ROUTINE: tstelse
* Purpose: Check if the line AFTER the current one starts with ELSE.
*          Only checks when in program mode, and only for the first IF
*          on a line (nested IFs don't get ELSE support).
* Returns:    BEQ if ELSE found, BNE if not
*==============================================================================
tstelse:
          move.l    a0,-(sp)
          tst.w     b_modus            * In program mode?
          beq       noelse             * No (direct mode) -> no ELSE possible
          addq.w    #1,ifcnt            * Count IFs on this line
          cmp.w     #1,ifcnt            * More than 1 IF on this line?
          bne       noelse             * Yes -> don't support ELSE for nested IFs
          move.l    akt_adr,a0         * Current line address
          move.l    (a0),a0            * Next line
          tst.l     (a0)                * Does next line exist?
          beq       noelse
          addq.l    #8,a0               * Skip to line content
          bsr       charget            * Read first token
          lsl.w     #8,d0
          move.b    (a0),d0
          cmp.w     #ELSE,d0           * Is it ELSE?
          bne       noelse
          move.l    (sp)+,a0           * Restore and return BEQ
          moveq     #0,d0
          rts
noelse:   move.l    (sp)+,a0
          moveq.l   #-1,d0            * Return BNE
          rts

*==============================================================================
* ROUTINE: Next (NEXT command)
* Purpose: End of FOR loop. Increments the loop variable by STEP value
*          and compares with the TO value. If not done, jumps back to
*          the statement after FOR.
*
*          FOR/NEXT structure (42 bytes per entry in fortable):
*          Offset  0: pointer to loop variable's value
*          Offset  4: type (INT or FLOAT)
*          Offset  6: TO value (12 bytes)
*          Offset 18: STEP value (12 bytes)
*          Offset 30: line number of FOR statement
*          Offset 34: line address of FOR statement
*          Offset 38: program pointer to resume after FOR...STEP
*==============================================================================
Next:
          bsr       tonxtcmd            * Skip to end of current command
          move.l    foreptr,a1         * Get FOR table pointer
          cmp.l     #fortable,a1        * Any FOR entries?
          beq       nexterr             * No -> "next without for" error
          sub.l     #42,a1              * Point to top FOR entry
          move.l    (a1),a2             * a2 = pointer to loop variable
          cmp.w     #INT,4(a1)          * Is loop variable integer?
          beq       nextint

nextfloat:
          * --- Float loop variable ---
          movem.l   (a2),d0-d2         * Read current value
          moveq     #0,d3
          moveq     #0,d7
          movem.l   18(a1),d4-d6       * Read STEP value
          movem.l   a0-a2,-(sp)         * Save registers (float add may use them)
          bsr       radd_               * Float add: value = value + step
          movem.l   (sp)+,a0-a2
          movem.l   d0-d2,(a2)          * Write back updated value
          moveq     #0,d7
          movem.l   6(a1),d4-d6         * Read TO value
          btst      #7,18(a1)           * Is STEP negative? (check sign bit)
          bne       next2
          bsr       rcmp_               * Compare value with TO value
          bhi       nextend             * value > TO -> loop done
          bra       nextcont
next2:    bsr       rcmp_               * Negative step: compare
          bmi       nextend             * value < TO -> loop done
          bra       nextcont

nextint:
          * --- Integer loop variable ---
          move.l    (a2),d0            * Read current value
          add.l     18(a1),d0           * Add STEP value
          move.l    d0,(a2)            * Write back
          btst      #7,18(a1)           * Is STEP negative?
          bne       next3
          cmp.l     6(a1),d0            * Compare with TO value
          beq       nextcont           * Equal -> continue (loop includes endpoint)
          bpl       nextend            * Greater -> done
          bra       nextcont
next3:    cmp.l     6(a1),d0
          bmi       nextend            * Less than TO (with neg step) -> done

nextcont:
          * --- Loop continues: restore position to after FOR ---
          move.l    30(a1),akt_zeile    * Restore line number
          move.l    34(a1),akt_adr      * Restore line address
          move.l    38(a1),a0           * Restore program pointer to after FOR...STEP
          rts

nextend:
          * --- Loop finished: remove FOR entry ---
          sub.l     #42,foreptr         * Pop the FOR entry from table
          rts

*==============================================================================
* ROUTINE: For (FOR command)
* Purpose: Begin a counted loop: FOR var = start TO end [STEP increment]
*          Creates a 42-byte entry in the FOR table (fortable).
*          Default STEP is 1 (integer) or 1.0 (float).
*==============================================================================
For:
          clr.w     sysallow            * Don't allow system variables as loop vars
          bsr       var_def             * Evaluate "var = start" (creates and assigns)
          clr.b     typvalid            * Clear array flag from type
          cmp.w     #STRING,typvalid    * String loop variable?
          beq       typemis            * Yes -> type mismatch error
          move.l    foreptr,a1          * Get FOR table pointer
          cmp.l     #endfortbl-42,a1    * Table full?
          bhi       forflow             * Yes -> "for overflow" error

          * Build the FOR table entry
          move.l    a2,(a1)+           * Store pointer to loop variable's value
          move.w    typvalid,(a1)+     * Store type (INT or FLOAT)
          bsr       chargot            * Read next token (should be TO)
          lsl.w     #8,d0
          move.b    (a0)+,d0
          cmp.w     #TO,d0              * Must be TO
          bne       toerr

          move.l    a1,-(sp)
          bsr       get_term            * Evaluate TO expression
          move.l    (sp)+,a1
          movem.l   fac1,d0-d2
          movem.l   d0-d2,(a1)          * Store TO value (12 bytes)
          add.l     #12,a1

          * Check for optional STEP clause
          bsr       chargot
          cmp.b     #TOKEN1,d0 		* Token intro byte?
          bne       nostep             * No -> default step
          lsl.w     #8,d0
          move.b    (a0)+,d0
          cmp.w     #STEP,d0            * Is it STEP?
          bne       syntaxerr          * No -> syntax error (unexpected token)

          move.l    a1,-(sp)
          bsr       get_term            * Evaluate STEP expression
          move.l    (sp)+,a1
          movem.l   fac1,d0-d2
          bra       for1

nostep:   * --- Default STEP value ---
          cmp.w     #INT,typvalid       * Integer loop?
          beq       intstep
          * Float default: 1.0 in extended format
          move.l    #$4001,d0          * Exponent + sign for 1.0
          move.l    #$00010000,d1      * Mantissa high
          moveq.l   #0,d2              * Mantissa low
          bra       for1
intstep:  moveq.l   #1,d0              * Integer default: 1

for1:     movem.l   d0-d2,(a1)          * Store STEP value (12 bytes)
          add.l     #12,a1
          move.l    akt_zeile,(a1)+     * Store current line number
          move.l    akt_adr,(a1)+       * Store current line address
          move.l    a1,-(sp)            * Save pointer for program position

          * Verify that FOR statement ends properly (: or end of line)
          subq.l    #1,a0               * Back up (get_term advanced past last char)
          bsr       tstnxtarg           * Must be end of statement
          beq       syntaxerr          * More arguments -> syntax error
          addq.l    #1,a0

          move.l    (sp)+,a1
          move.l    a0,(a1)+            * Store program pointer (resume point for NEXT)
          move.l    a1,foreptr         * Update FOR table pointer
          rts

*==============================================================================
* ROUTINE: Close (CLOSE command)
* Purpose: Close a file handle and remove its entry from the handle table.
*          Handles 0-5 are system devices and are not actually closed.
* Parameters: File handle number (via get_handle)
*==============================================================================
Close:
          bsr       get_handle         * Read and look up the handle
          cmp.w     #5,handle          * System device handle (0-5)?
          ble       close1             * Yes -> don't actually close
          clr.l     (a1)                * Clear the handle table entry
          bra       f_close            * Close via GEMDOS Fclose ($3E)
close1:   rts

*==============================================================================
* ROUTINE: get_handle
* Purpose: Read a logical file handle number from the BASIC line and look it
*          up in the handle table to find the corresponding GEMDOS handle.
* Parameters: Integer expression = BASIC handle number
* Returns:    handle = GEMDOS file handle, a1 = handle table entry
*==============================================================================
get_handle:
          clr.w     cmdfl              * Clear CMD mode
          clr.w     handle             * Default handle = 0
          move.w    #INT,typvalid
          bsr       get_term           * Read handle number
          move.l    fac1,d0
		bmi		negerr             * Negative -> error
          cmp.l     #$ffff,d0           * Too large?
          bpl       toobigerr
          cmp.w     #5,d0              * System device (0-5)?
          ble       get_h1              * Yes -> use directly

          * Search handle table for this BASIC handle
          lea       handtab,a1          * Handle table
cl2:      cmp.w     (a1),d0             * Found matching entry?
          beq       cl1
          addq.l    #4,a1
          cmp.l     #endhtab,a1         * Past end of table?
          bge       notopenerr         * Yes -> "no such handle" error
          bra       cl2

cl1:      move.w    2(a1),handle        * Extract GEMDOS handle from table entry
          rts
get_h1:   move.w    d0,handle           * Use system handle directly (0-5)
          rts

*==============================================================================
* ROUTINE: Open / Create
* Purpose: Open or create a file and add it to the handle table.
*          Syntax: OPEN handle, filename$ / CREATE handle, filename$
*          Handles 0-5 are system devices and need no filename.
*
*          Handle table format: each entry is 4 bytes:
*          [2-byte BASIC handle][2-byte GEMDOS handle]
*==============================================================================
Create:
		clr.w	-(sp)              * Flag: 0 = create
		bra		openfile
Open:
		move.w	#1,-(sp)           * Flag: 1 = open
openfile:
          move.w    #INT,typvalid
          bsr       get_term            * Read BASIC handle number
          move.l    fac1,d0
		bmi		negerr
          cmp.l     #$ffff,d0           * Too large?
          bpl       toobigerr
          cmp.w     #5,d0               * System device?
          ble       open0123            * Yes -> no file operations needed

* Check if handle is already in use
          lea       handtab,a1
open0:    cmp.w     (a1),d0             * Already open?
          beq       alropen             * Yes -> "already open" error
          addq.l    #4,a1
          cmp.l     #endhtab,a1
          blt       open0

* Find an empty slot in the handle table
          lea       handtab,a1
open2:    tst.w     (a1)                * Empty slot (0)?
          beq       open1              * Yes -> use it
          addq.l    #4,a1
          cmp.l     #endhtab,a1         * Past end?
          bge       handflow           * Yes -> "too many files open" error
          bra       open2

open1:
		move.w	d0,-(sp)           * Save BASIC handle
          bsr       chk_komma
          move.w    #STRING,typvalid    * Read filename string
          move.l    a1,-(sp)           * Save table slot pointer
 		move.l    strend,spstr
		bsr       onqlist
          bsr       get_defterm         * Evaluate filename
		bsr       offqlist
		move.l    spstr,strend

		tst.w	6(sp)              * Check create/open flag (offset 6 because a1 and handle on stack)
		beq		open3
          bsr       f_open              * Open existing file (GEMDOS Fopen $3D)
		bra		open4
open3:
		bsr		f_create           * Create new file (GEMDOS Fcreate $3C)
open4:
		move.l    (sp)+,a1            * Restore table slot pointer
		move.w	(sp)+,(a1)+        * Write BASIC handle to table
          move.w    handle,(a1)         * Write GEMDOS handle to table
open0123:
		addq.l	#2,sp              * Remove create/open flag from stack
		rts

*==============================================================================
* ROUTINE: On (ON command)
* Purpose: Computed jump: ON expr GOTO/GOSUB line1, line2, ...
*          Also handles: ON TRACE GOSUB line (set trace handler)
* Parameters: Integer expression, then GOTO/GOSUB keyword, then line numbers
*==============================================================================
On:
		move.l	a0,work1
		bsr		charget
		lsl.w	#8,d0
		bsr		charget
		cmp.w	#TRACE,d0          * Is it ON TRACE?
		bne		OnX

		* ON TRACE GOSUB line - set trace handler
		bsr		charget
		lsl.w	#8,d0
		bsr		charget
		cmp.w	#GOSUB,d0          * Must be GOSUB after TRACE
		bne		trgoserr
		move.w	#INT,typvalid
		bsr		get_term           * Get target line number
		move.l	fac1,d0
		bsr		poszeile           * Find the line
		cmp.l	4(a1),d0           * Does it exist?
		bne		nolineerr
		move.l	fac1,traceline     * Store trace handler line
		bra		charget

OnX:
		* ON expr GOTO/GOSUB line1, line2, ...
		move.l	work1,a0           * Restore position
          move.w    #INT,typvalid
          bsr       get_term           * Evaluate index expression
          move.l    fac1,onarg          * Save argument (1-based)
		subq.l	#1,onarg           * Convert to 0-based
          bsr       chargot
          lsl.w     #8,d0
          move.b    (a0)+,d0
          move.w    d0,oncmd            * Save GOTO or GOSUB token

on2:      bsr       tstnxtarg           * Is there another line number?
          bne       syntaxerr           * No arguments -> error
          bsr       get_term            * Read line number
          subq.l    #1,a0
          tst.l     onarg               * Is this the target index?
          beq       onfound             * Yes (reached 0)
          cmp.b     #',',(a0)+          * Comma separating line numbers?
          bne       onend               * No more -> value not in range
          subq.l    #1,onarg           * Decrement counter
          bra       on2

onfound:  move.w    oncmd,d0
          cmp.w     #GOTO,d0
          beq       ongoto
          cmp.w     #GOSUB,d0
          bne       syntaxerr
ongosub:  bsr       tonxtcmd            * Skip rest of ON command (important for GOSUB return)
          bra       Gosub1             * Execute GOSUB to the found line
ongoto:   bra       Run1               * Execute GOTO to the found line
onend:    rts                          * Value out of range -> fall through (no jump)

*==============================================================================
* ROUTINE: Input (INPUT command)
* Purpose: Read values from the keyboard or a file into variables.
*          Syntax: INPUT [#handle,] ["prompt";] var1 [,var2...]
*
*          For keyboard input: displays "?" prompt (and optional text),
*          then hands control back to the editor. When the user presses
*          RETURN, the editor calls inputentry to process the input.
*
*          For file input: reads values line by line from the file,
*          parsing them according to variable types.
*==============================================================================
Input:
          move.l    a0,work2
          bsr       charget
          cmp.b     #'#',d0             * File input (#handle)?
          bne       Input1

          * --- File INPUT ---
          bsr       get_handle          * Read file handle
          bsr       chk_komma

finpnext: bsr       var2_def            * Get target variable -> a1/typvalid
          move.l    a0,-(sp)           * Save BASIC program pointer
          lea       inputpuf,a0        * Temporary buffer for file data
          move.l    a0,inptr
          move.l    a1,-(sp)            * Save variable pointer
          move.l    a0,a1

          * Read bytes from file until delimiter
finp1:    moveq     #1,d0              * Read 1 byte
          move.l    a1,-(sp)
          bsr       f_read              * GEMDOS Fread ($3F)
          move.l    (sp)+,a1
          tst.l     d0                  * End of file?
          beq       finp1end
          move.b    (a1)+,d0
          beq       finp1end            * NUL byte -> end
          cmp.l     #inputpuf+254,a1    * Buffer almost full?
          beq       finp1end
          cmp.b     #9,d0               * TAB -> delimiter
          beq       finp1end
          cmp.b     #10,d0              * LF -> skip (part of CR+LF)
          bne       finp1b
          subq.l    #1,a1              * Don't store LF
          bra       finp1
finp1b:   cmp.b     #13,d0              * CR -> delimiter
          bne       finp1               * Other char -> continue reading

finp1end: clr.b     (a1)               * NUL terminate the buffer
          move.l    a1,d0              * d0 = end of data
          move.l    (sp)+,a1            * Restore variable pointer
          cmp.w     #STRING,typvalid
          bne       finp3               * Not string -> parse as number

          * String variable: copy file data into string space (backwards)
          sub.l     #inputpuf,d0       * d0 = length of data
          move.l    strend,d1
          sub.l     #32,d1             * Safety margin
          sub.l     d0,d1
* --- Store string value into backwards string space ---
*         The string data is in inputpuf, length in d0.
*         strend has already been adjusted; now copy bytes in reverse.
          cmp.l     varend,d1           * Check: would string overlap variable area?
          bmi       outvarmem

*         sub.l     d0,strend
          move.l    strend,a0             * a0 = current end of string space
          move.l    a0,str_ptr            * str_ptr = start of this new string
          addq.l    #1,a0                 * step past strend (strings stored below it)
          lea       inputpuf,a2           * a2 = source: the input buffer
          subq.l    #1,d0                 * adjust count for dbf loop (dbf counts down to -1)
          bra       ll2                   * enter loop at bottom (test first)
ll1:
          move.b    (a2)+,-(a0)           * copy one byte from buffer into string space (reversed)
ll2:
          dbf       d0,ll1                * decrement d0 and loop until d0 = -1
          clr.b     -(a0)                 * write NUL terminator below the string data
          subq.l    #1,a0                 * adjust pointer (leave room for terminator)
          move.l    a0,strend             * update strend to reflect new allocation
          bra       finp4                 * jump to write_var to store the string pointer

* --- Numeric variable from file INPUT ---
finp3:
          move.l    a1,-(sp)              * save variable pointer (a1) across get_term call
          bsr       get_term              * evaluate the numeric expression in inputpuf
          move.l    (sp)+,a1              * restore variable pointer

* --- Write value to variable and advance to next ---
finp4:    bsr       write_var             * write INT/FLOAT value to variable at a1
          move.l    a0,inptr              * save updated input parse pointer
          move.l    (sp)+,a0              * restore BASIC program pointer (next variable)
          bsr       charget               * get next character from program text
          cmp.b     #',',d0               * comma means another variable follows in the INPUT list
          beq       finpnext              * loop back to parse the next variable
          rts                             * no more variables -> return

*==============================================================================
* ROUTINE: Input1 (INPUT from keyboard)
* Purpose: Handle INPUT command for keyboard entry. Displays "?" prompt and
*          an optional user-supplied prompt string, then transfers control to
*          the editor. When the user presses RETURN, the editor calls back
*          via edi_retprg -> inputentry, which copies the editor buffer into
*          inputpuf and parses comma-delimited values into variables by type.
* Entry:   a0 = pointer into BASIC program text (from work2)
*          a1 = copy of work2
*==============================================================================
Input1:   * Normal input from keyboard...
          move.l    work2,a0              * a0 = start of INPUT statement arguments
          move.l    a0,a1                 * a1 = save copy for later
          lea       fragez,a0             * a0 = "?" prompt string
          bsr       put_string            * display the "?" prompt on screen
          move.l    a1,a0                 * restore program pointer
          bsr       charget               * read next character
          subq.l    #1,a0                 * back up (charget advances past char)
          cmp.b     #'"',d0               * quote? then a user prompt string follows
          bne       inp1                  * no quote -> skip to argument list

          * --- Display optional user prompt string ---
          move.w    #STRING,typvalid      * tell evaluator we expect a string result
          bsr       get_term              * evaluate the quoted string expression
          move.l    a0,-(sp)              * save program pointer
          move.l    str_ptr,a0            * a0 = pointer to the evaluated string (reversed)
          bsr       putstrreverse         * output the reversed string to screen
          move.l    (sp)+,a0              * restore program pointer
          bsr       chargot               * re-read current char (without advancing)
          cmp.b     #';',d0               * semicolon must follow the prompt string
          bne       syntaxerr             * missing semicolon -> syntax error

* --- Set up editor callback for keyboard input ---
inp1:     * The argument list of variables to read follows
          move.l    a0,-(sp)              * save program pointer on stack

          moveq.l   #0,d0                 * clear d0
          move.w    ed_xoffs,d0           * d0 = editor X offset (column origin)
          add.w     ed_x,d0              * add current cursor X position
          move.l    d0,-(sp)              * save current cursor column on stack
          move.l    edibase,a1            * a1 = editor structure base
          move.l    #inputentry,edi_retprg(a1)  * set editor return callback to inputentry
          * When the user presses RETURN in the editor, it will call inputentry.
          * We save SP into inputpuf so inputentry can restore the stack frame.
          move.l    sp,inputpuf           * save stack pointer for later restoration
          bra       posquit               * return to editor loop (position cursor and wait)

*==============================================================================
* ROUTINE: inputentry (INPUT keyboard callback)
* Purpose: Called by the editor when RETURN is pressed during INPUT.
*          Copies the editor line buffer into inputpuf, then parses
*          comma-separated values into the target variables.
* Entry:   a0 = editor line buffer, d0 = number of characters entered
*==============================================================================
inputentry:         * Text has been entered, RETURN was pressed!
          move.l    edibase,a1            * a1 = editor structure base
          clr.l     edi_retprg(a1)        * clear the callback (one-shot)
          move.l    inputpuf,sp           * restore stack pointer saved before editor call
          move.l    (sp)+,d1              * d1 = saved cursor X position from before
          add.l     d1,a0                 * advance past prompt portion of line buffer
          sub.l     d1,d0                 * adjust character count (subtract prompt width)

          * --- Copy editor buffer to inputpuf ---
	move.l	a0,a1                         * a1 = source (editor buffer after prompt)
	lea		inputpuf,a0                   * a0 = destination buffer
          move.l    a0,inptr              * inptr = start of input data for parsing
          bsr       copya1_ina0           * copy string from a1 to a0 (NUL-terminated)
          move.l    (sp)+,a0              * restore BASIC program pointer (variable list)

* --- Parse input values into variables ---
inpnext:  bsr       var2_def              * parse variable name from program -> a1/typvalid
          move.l    a0,-(sp)              * save program pointer
          move.l    inptr,a0              * a0 = current position in input data buffer
          cmp.w     #STRING,typvalid      * is this a string variable?
          bne       inp3                  * no -> parse as numeric with get_term

          * --- String variable: copy input text into backwards string space ---
          move.l    strend,a2             * a2 = current bottom of string space
          move.l    a2,str_ptr            * str_ptr = this string's reference pointer
          addq.l    #1,a2                 * step past strend boundary

inp2b:    move.b    (a0)+,d0              * read next byte from input buffer
          beq       inp2a                 * NUL -> end of this value
*          cmp.b     #':',d0              * (commented out: colon was once a delimiter)
*          beq       inp2a
          cmp.b     #',',d0               * comma separates multiple input values
          beq       inp2a                 * comma -> end of this value
          move.b    d0,-(a2)              * store byte into string space (growing downward/reversed)
          move.l    a2,a3
          sub.l     #32,a3                * a3 = strend - 32 (safety margin)
          cmp.l     varend,a3             * check if string space overlaps variable space
          bmi       outvarmem             * out of memory -> error
          bra       inp2b                 * continue copying bytes

inp2a:    clr.b     -(a2)                 * write NUL terminator below the string
          subq.l    #1,a2                 * adjust for alignment
          move.l    a2,strend             * update strend to reflect new allocation
          bra       inp4                  * jump to write variable

* --- Numeric variable: evaluate expression from input buffer ---
inp3:
          move.l    a1,-(sp)              * save variable pointer across get_term
          bsr       get_term              * evaluate numeric expression from input buffer
          move.l    (sp)+,a1              * restore variable pointer

inp4:     bsr       write_var             * write INT/FLOAT/STRING value to variable at a1
          bsr       tst_komma             * test if a comma follows in the input buffer
          bne       inpend                * no comma -> done with input values
          move.l    a0,inptr              * save updated input parse position
          move.l    (sp)+,a0              * restore BASIC program pointer
          bsr       charget               * get next character from program text
          cmp.b     #',',d0               * comma in program text means another variable
          beq       inpnext               * yes -> loop back for next variable
          bra       syntaxerr             * input data has comma but program doesn't -> error

* --- End of keyboard INPUT ---
inpend:
          bsr       new_line              * output a newline to screen
          move.l    (sp)+,a0              * restore BASIC program pointer
          bra       charget               * advance past current token and return



*==============================================================================
* ROUTINE: code_ptr / decode_ptr (Pointer encoding for FN definition strings)
* Purpose: Encode/decode 32-bit pointers so they never contain a $FF byte.
*          The garbage collector uses $FF as a "dead string" marker, so any
*          FN/PROC definition string containing embedded pointers must avoid
*          $FF bytes. The trick: multiply the 32-bit value by 2 (left shift),
*          which shifts the problematic middle byte, then preserve the low byte
*          unchanged. On decode, shift right by 1 and restore the low byte.
*
*          Example: pointer $00 01 FF 88
*            code_ptr:   save low byte ($88), shift left (*2) -> $00 03 FF 10,
*                        restore low byte -> $00 03 FF 88... but actually the
*                        shift makes $FF become $01 FE, eliminating the $FF.
*                        Result: $00 03 FE 88 (no $FF byte!)
*            decode_ptr: save low byte, shift right (/2), restore low byte
*                        -> original $00 01 FF 88
*
* Parameters: d0.l = pointer value to encode/decode
* Returns:    d0.l = encoded/decoded pointer value
* Destroys:   d1
*==============================================================================

*****************************************
* The FN definition block is stored in string space. It cannot contain $FF
* bytes because the garbage collector interprets $FF as a dead/invalid string
* marker. Since the FN block contains embedded pointers to argument variables,
* those pointers must be encoded to avoid $FF bytes.
*
* Encoding trick: only the third byte of a 24-bit Atari ST address can be $FF
* (addresses are 00 0x yy zz where yy could be $FF). Doubling the 32-bit
* value shifts yy left, eliminating any $FF. The low byte is preserved
* separately since it would be corrupted by the shift.
*****************************************

code_ptr:
          move.b    d0,d1                 * save low byte in d1
          add.l     d0,d0                 * multiply pointer by 2 (shift left 1 bit)
          move.b    d1,d0                 * restore original low byte -> d0 = encoded pointer
          rts

decode_ptr:
          move.b    d0,d1                 * save low byte in d1
          lsr.l     #1,d0                 * divide pointer by 2 (shift right 1 bit)
          move.b    d1,d0                 * restore original low byte -> d0 = decoded pointer
          rts

* FN definition string layout:
*   [return_type.w]                         - type of the function's return value (default: FLOAT)
*   { [arg_type.w] [encoded_arg_ptr.l] }... - pairs of argument type and encoded pointer
*   [$0000.w]                               - end-of-arguments marker (zero word)
*   [function_body_ascii_text...]           - the expression text to evaluate

*==============================================================================
* ROUTINE: Fn (FN function call)
* Purpose: Evaluate a user-defined FN function. Saves string state on the
*          protection stack (qlist), resolves the FN variable, reads the
*          return type and argument definitions from the FN string, evaluates
*          each argument expression and writes it to the argument variable,
*          then evaluates the function body expression and returns the result.
* Entry:   a0 = program pointer (after FN token, pointing to function name)
* Returns: result in fac1/d0-d3, type in typflag
*          a0 = updated program pointer
*==============================================================================

*****************************************
* FN
*****************************************
* Treated as a function -> fn(arg1,...)
Fn:
          move.l    str_ptr,spstr         * save current str_ptr into spstr temp
          bsr       onqlist               * push spstr (str_ptr) onto protection stack
          * This protects str_ptr from being corrupted during recursive evaluation
          move.l    strend,spstr          * save current strend into spstr temp
          bsr       onqlist               * push spstr (strend) onto protection stack
          * This protects strend from being corrupted during recursive evaluation
          bsr       tst_dfnvar            * test if FN variable exists (DEFFNTYP bit set)
          * Returns: d0 = nonzero if found, a1 = pointer to variable's value field
          tst.w     d0                    * was the function defined?
          beq       fndeferr              * not defined -> "function not defined" error
          move.l    (a1),a2               * a2 = pointer to the FN definition string in string space
	move.w	(a2)+,-(sp)               * push the return type word onto the CPU stack
          tst.w     (a2)                  * check first argument type word: 0 = no arguments
          beq       fn1                   * no arguments -> skip argument parsing (no parentheses needed)

          * --- Parse function arguments ---
          bsr       charget               * get next char from program text
          cmp.b     #'(',d0               * must be opening parenthesis
          bne       misargerr             * missing arguments -> error

fn2:      move.w    (a2)+,typvalid        * read expected type of this argument from FN string
          move.l    a2,-(sp)              * save FN string pointer across evaluation
          bsr       get_defterm           * evaluate argument expression (like get_term but for FN args)
          * Result is in fac1/d0-d3, type in typflag
          move.l    (sp)+,a2              * restore FN string pointer
          move.l    (a2)+,d0              * read encoded pointer to argument variable's value
          bsr       decode_ptr            * decode the pointer (undo the $FF avoidance encoding)
          move.l    d0,a1                 * a1 = pointer to argument variable's value storage
          move.l    a2,-(sp)              * save FN string pointer across write
          bsr       write_var             * write the evaluated argument value into the variable
          move.l    (sp)+,a2              * restore FN string pointer
          tst.w     (a2)                  * check next argument type: 0 = end of argument list
          beq       fn1a                  * all arguments processed -> close parenthesis
          bsr       tst_komma             * test for comma separator between arguments
          bne       misargerr             * no comma -> missing argument error
          bra       fn2                   * loop back for next argument

fn1a:     bsr       chk_klammer           * check and consume closing parenthesis ')'

fn1: * Now all function arguments are initialized, execute the function body
          move.w    (sp)+,typvalid        * pop the expected return type from CPU stack
          move.l    a0,-(sp)              * save BASIC program pointer (caller's position)
          addq.l    #2,a2                 * skip the $0000 end-of-args marker word
          move.l    a2,a0                 * a0 = function body text (ASCII expression)
          move.w    argfl,-(sp)           * save current argfl state
          move.w    #-1,argfl             * set argfl = -1 (flag: evaluating inside FN body)
          bsr       get_term              * evaluate the function body expression
          * Result is in fac1/d0-d3, type in typflag
          move.w    (sp)+,argfl           * restore previous argfl state
          move.w    typvalid,typflag      * set typflag to the expected return type

          * --- Save result and restore string state ---
          move.l    str_ptr,a1            * a1 = current str_ptr (may have changed during eval)
          lea       zero_+4,a2            * a2 = pointer past zero constant (used as safe ref)
          movem.l   fac1,d0-d3            * save function result (fac1) into d0-d3
          move.l    (sp)+,a0              * restore caller's BASIC program pointer
          bsr       offqlist              * pop strend from protection stack -> spstr
          move.l    spstr,strend          * restore strend to pre-FN-call value
          bsr       offqlist              * pop str_ptr from protection stack -> spstr
          move.l    spstr,str_ptr         * restore str_ptr to pre-FN-call value
          rts                             * return with result in d0-d3/fac1, type in typflag

*==============================================================================
* ROUTINE: Deffn (DEF FN command)
* Purpose: Define a user function. Creates the function variable with
*          DEFFNTYP (bit13=$2000) in its type word. Creates argument
*          variables with FNTYP (bit14=$4000) so they are distinct from
*          normal variables. Builds a definition string in the var2_name
*          buffer containing:
*            [return_type.w] {[arg_type.w] [encoded_arg_ptr.l]}... [$0000.w]
*            [function_body_ascii_text]
*          Then copies this definition string into string space (growing
*          downward), word-aligns strend, and stores the pointer in the
*          function variable.
* Entry:   a0 = program pointer (after DEF token)
*==============================================================================

*****************************************
* DEFFN
*****************************************
* Prepares the function variable in memory. Arguments are stored as normal
* variables but with bit14=1 (FNTYP=$4000) so they are not confused with
* regular variables. The function variable itself has bit13=1 (DEFFNTYP=$2000).
Deffn:
          bsr       charget               * read first byte of keyword after DEF
          move.b    d0,d1                 * d1 = first byte
          lsl.w     #8,d1                 * shift to high byte of word
          bsr       charget               * read second byte
          move.b    d0,d1                 * d1 = two-byte token (e.g., FN=$011C)
          cmp.w     #FN,d1                * is it DEF FN?
          bne       checkforproc          * no -> check if it's DEF PROC instead

          * --- Create the function variable ---
          bsr       tst_dfnvar            * test if FN variable already exists, get address in a1
          move.w    typflag,typvalid      * typvalid = base type (without DEFFNTYP bit)
          or.w      #$2000,typvalid       * set bit13 (DEFFNTYP) to mark as function variable
          tst.w     d0                    * does the variable already exist?
          bne       redef                 * yes -> "redefinition" error
          bsr       create2_var           * create the function variable -> a1 = pointer to value field
          addq.w    #1,fncnt              * increment function definition counter
* -> a1 points to the value field of the new function variable

          * --- Build definition string in var2_name buffer ---
          lea       var2_name,a2          * a2 = temporary build buffer (normally used by DIM)
	move.w	fntyp,(a2)+               * write return type word (FLOAT/INT/STRING) as first entry
          * fntyp holds the detected return type of the function name

          move.l    a1,-(sp)              * save function variable value pointer
          bsr       charget               * read next character
          cmp.b     #'=',d0               * '=' means no arguments, function body follows directly
          beq       def_f3                * skip argument list
          cmp.b     #'(',d0               * '(' means argument list follows
          bne       syntaxerr             * anything else -> syntax error

          * --- Parse argument list ---
def_f6:   move.l    a2,-(sp)              * save build buffer pointer
          bsr       tst_fnvar             * test if FN argument variable exists, get address in a1
          move.w    typflag,typvalid      * typvalid = base type of argument
          or.w      #$4000,typvalid       * set bit14 (FNTYP) to mark as FN argument variable
          tst.w     d0                    * does the argument variable already exist?
          bne       def_f4                * yes -> already defined, skip creation
          bsr       create2_var           * create the argument variable -> a1 = value pointer

def_f4:
          move.l    (sp)+,a2              * restore build buffer pointer
          move.w    typflag,(a2)+         * write argument type word into definition string
          move.l    a1,d0                 * d0 = pointer to argument variable's value storage
          bsr       code_ptr              * encode pointer to avoid $FF bytes in string space
          move.l    d0,(a2)+              * write encoded pointer into definition string
          bsr       charget               * read next character
          cmp.b     #')',d0               * closing parenthesis -> end of argument list
          beq       def_f3a               * done with arguments
          cmp.b     #',',d0               * comma separates arguments
          beq       def_f6                * loop back for next argument
          bra       syntaxerr             * anything else -> syntax error

def_f3a:  bsr       charget               * read character after closing parenthesis
          cmp.b     #'=',d0               * '=' must follow the argument list
          bne       syntaxerr             * missing '=' -> syntax error

def_f3:
          clr.w     (a2)+                 * write $0000 end-of-arguments marker

          * --- Copy function body text into definition string ---
def_f7:   move.b    (a0)+,d0              * read next byte from program text
          beq       def_f8                * NUL -> end of line, function body complete
          cmp.b     #':',d0               * colon -> end of statement, function body complete
          beq       def_f8
          move.b    d0,(a2)+              * copy byte into definition string buffer
          bra       def_f7                * continue copying

def_f8:   clr.b     (a2)+                 * NUL terminator for function body text
          clr.b     (a2)+                 * extra NUL for safety padding
          clr.b     (a2)+                 * another extra NUL for safety (3 NULs total)

          * --- Calculate string length and allocate in string space ---
          lea       var2_name,a3          * a3 = start of definition string buffer
          sub.l     a3,a2                 * a2 = length of the complete definition string
          move.l    a2,d0                 * d0 = string length

          move.l    strend,a1             * a1 = current bottom of string space
          clr.b     (a1)                  * clear byte at strend (safety)
          sub.l     #32,a1                * subtract 32-byte safety margin
          sub.l     d0,a1                 * subtract string length
          cmp.l     varend,a1             * does it fit? (would it overlap variable space?)
          bmi       outvarmem             * no room -> out of variable memory error
          sub.l     d0,strend             * allocate space: move strend down by string length

          * --- Word-align strend ---
          btst      #0,strend+3           * test bit 0 of low byte of strend (odd address check)
          bne       wrdalligned           * if odd (bit=1), already word-aligned after sub? No:
          * Actually: if bit 0 is set, the address is odd -> already needs no adjustment.
          * If bit 0 is clear, the address is even, but we want odd+1=even alignment.
          * The logic: btst #0 tests if strend is odd. If NOT odd (bne not taken),
          * subtract 1 to ensure word alignment.
          subq.l    #1,strend             * adjust strend down by 1 for word alignment

wrdalligned:
          move.l    strend,a1             * a1 = final strend (word-aligned)
	addq.l	#1,a1                         * a1 = first byte of allocated string space
          move.l    a1,a4                 * a4 = save start address for later
          subq.w    #1,d0                 * adjust count for dbf loop (d0-1 iterations)

          * --- Copy definition string from buffer to string space ---
ll4:
          move.b    (a3)+,(a1)+           * copy one byte from var2_name buffer to string space
          dbf       d0,ll4                * loop until all bytes copied (dbf decrements, loops until -1)

          * --- Store pointer to definition string in function variable ---
          move.l    (sp)+,a1              * restore function variable's value pointer (saved earlier)
          move.l    a4,(a1)               * store pointer to definition string as the variable's value
          rts                             * DEF FN complete
*==============================================================================
* PROCEDURE SYSTEM - DEF PROC, PROC, ENDPROC, LOCAL
*==============================================================================
*
* Procedure Routines for DEF PROC, PROC name
*
* Layout of a PROC variable:
*   Variable record: [nextptr].l [type PROC&STRING].w [NAME].b .even [PTR TO STRING].l
*
* The procedure's string value is structured as:
*   [PROCNR (x8) 8,16,...].w [Ptr to next line (after DEFPROC)].l
*   {[arg type (incl. procnr)].w [ptr to arg value].l}... (same as FN's)
*   $0000.w   (end-of-argument-list marker)
*
*   All pointers are encoded via code_ptr because a string must not
*   contain $FF bytes (which the garbage collector uses as dead markers).
*

* --- Procedure System Global Variables ---

anzprocs	.dc.w	0                   * Total number of procedures found by get_procs
procnr	.ds.w	1                       * Current procedure number (multiples of 8, bits 3-11 of type word)

*==============================================================================
* LOCAL Command
*------------------------------------------------------------------------------
* Purpose:  Defines local variables for the current procedure scope.
*           LOCAL a,b,c creates variables with the current procnr OR'd
*           into their type word, making them local to the procedure.
*           Each local variable is initialized to zero.
* Syntax:   LOCAL var1, var2, ... or LOCAL DIM arrayvar(...)
* Notes:    System variables and arrays cannot be declared LOCAL (without DIM).
*           INT locals are cleared to 0, FLOAT locals get zero_ (12 bytes of 0),
*           STRING locals get a pointer to the empty string (zero_+4).
*==============================================================================
Local:
		move.l	a0,-(sp)            * Save program pointer on stack
		bsr		charget             * Read next character from program
		lsl.w	#8,d0               * Shift first token byte to high byte
		bsr		charget             * Read second token byte -> d0 = full token
		cmp.w	#DIM,d0             * Is it LOCAL DIM?
		beq		localdim            * Yes -> handle local array dimension
* --- LOCAL a,b,c,... (simple local variables) ---
		move.l	(sp)+,a0            * Restore program pointer (not LOCAL DIM)
localget:
		bsr		tst_var             * Parse and look up variable name
		bmi		localfound          * If negative (already exists as local) -> skip creation
		tst.b	arrayfl             * Is it an array variable?
		bne		locdeferr           * Yes -> error: cannot use LOCAL without DIM for arrays
		tst.w	sysvar              * Is it a system variable (pi, ti, ti$)?
		bne		locdeferr           * Yes -> error: system vars cannot be local
		move.w	typflag,d1          * Get the variable's base type
		or.w		procnr,d1           * OR in current procedure number (bits 3-11)
		move.w	d1,typvalid         * Store as the type to create with
		bsr		create2_var         * Create the local variable in variable list
* --- Initialize the new local variable to zero ---
		move.w	typflag,d0          * Get the type of the newly created variable
		cmp.b	#INT,d0             * Is it an integer?
		bne		locnoint            * No -> check float
		clr.l	(a1)                * INT: clear 4 bytes (set to 0)
		bra		localfound          * Done initializing
locnoint:
		cmp.b	#FLOAT,d0           * Is it a float?
		bne		locnofl             * No -> must be string
		movem.l	zero_,d0-d2         * FLOAT: load 12 bytes of zeros from zero_ constant
		movem.l	d0-d2,(a1)          * Store 12 zero bytes into float variable value
		bra		localfound          * Done initializing
locnofl:
		move.l	#zero_+4,(a1)       * STRING: point to empty string (zero_+4 = ptr to null)
localfound:
		bsr		charget             * Read next character
		cmp.b	#',',d0             * Is there another variable in the list?
		beq		localget            * Yes -> parse next local variable
		rts                         * No more -> return

localdim:
		addq.l	#4,sp               * Discard saved a0 from stack (no longer needed)
		bra		Localdim            * Branch to LOCAL DIM handler (array local creation)


*==============================================================================
* checkforproc - Skip Over a DEF PROC Body During Execution
*------------------------------------------------------------------------------
* Purpose:  When DEF FN encounters a PROC token instead of FN during
*           execution, we must skip the entire PROC body. This routine
*           scans forward line by line until ENDPROC is found, then
*           continues execution after it.
* Entry:    d1 = token that was found (must be PROC)
*           akt_adr = current line address
* Exit:     Execution continues at the line after ENDPROC
*==============================================================================
checkforproc:
		cmp.w	#PROC,d1            * Verify it really is PROC token
		bne		syntaxerr           * If not -> syntax error
		move.l	akt_adr,a0          * Start scanning from current line
cfp1:
		move.l	(a0),a1             * a1 = pointer to next line
		tst.l	(a1)                * Is next line the end of program (null ptr)?
		beq		basic1			    * End of listing reached without ENDPROC -> return to prompt
		addq.l	#8,a0               * Skip past next-ptr (4) and line-number (4) to line content
		bsr		charget             * Read first token byte of this line
		lsl.w	#8,d0               * Shift to high byte
		bsr		charget             * Read second token byte -> d0 = full 16-bit token
		cmp.w	#ENDPROC,d0         * Is this line ENDPROC?
		beq		cfpend1             * Yes -> found the end of the procedure body
		move.l	a1,a0               * No -> advance to next line
		bra		cfp1		        * Continue scanning
cfpend1:
		move.l	a1,akt_adr          * Set current line address to the ENDPROC's next line
		move.l	4(a1),akt_zeile     * Set current line number from next line's header
		lea		8(a1),a0            * Point a0 to the content of the next line
		addq.l	#4,sp			    * Discard JSR return address (from CMD dispatch in exec_line)
		bra		exec_line           * Continue execution at the line after ENDPROC


*==============================================================================
* get_procs - Pre-scan Program for DEF PROC Declarations (Called Before RUN)
*------------------------------------------------------------------------------
* Purpose:  Scans the entire program for DEF PROC statements before
*           execution begins. For each procedure found:
*           - Creates a procedure variable (type = PROCTYP | base_type)
*           - Assigns a unique procnr (multiples of 8, starting at 8)
*           - Builds a definition string containing the encoded line
*             pointer and parameter type/pointer pairs
*           - Copies the definition string to string space
*           Maximum 511 procedures allowed.
* Entry:    Program loaded at prgbase
* Exit:     All procedure variables created, anzprocs set to count,
*           procnr reset to 0 for execution
*==============================================================================
get_procs:
		movem.l	a0/a1,-(sp)         * Save registers
		move.w	#1*8,procnr         * Start procedure numbering at 8 (procnr=1*8)
		lea		prgbase,a0          * Point to start of program listing
proctstnxt:
		move.l	(a0),d0             * d0 = pointer to next line (0 = end of program)
		beq		endgetproc          * End of program -> finish scanning
		move.l	d0,-(sp)			* Save pointer to next line on stack
		addq.l	#8,a0			    * Skip past next-ptr and line-number to line content
		bsr		charget             * Read first token byte
		lsl.w	#8,d0               * Shift to high byte
		bsr		charget             * Read second token byte -> full token in d0
		cmp.w	#DEFFN,d0           * Is this a DEF (FN/PROC) statement?
		bne		procnxtline         * No -> skip to next line
		bsr		charget             * Read next token byte
		lsl.w	#8,d0               * Shift to high byte
		bsr		charget             * Read second byte -> d0 = sub-token
		cmp.w	#PROC,d0            * Is it DEF PROC (not DEF FN)?
		bne		procnxtline         * No -> skip to next line

* --- Found a DEF PROC statement ---

          bsr       tst_dprcvar         * Test if proc variable already exists, get address
          move.w    typflag,typvalid    * Copy type flag (without PROCTYP bit set yet)
          or.w      #PROCTYP,typvalid   * Set bit 12 to mark as procedure type
          tst.w     d0                  * Does this variable already exist?
          bne       redef               * Yes -> "already defined" error
          bsr       create2_var         * Create the procedure variable
* -> a1 points to the variable's value pointer
          lea       var2_name,a2        * Use var2_name buffer to build proc definition string
		move.w	procnr,(a2)+		* Store procedure number (x8, bits 3-11) at start of string
		move.l	(sp),d0			    * Get pointer to next line (= line after DEF PROC)
		bsr		code_ptr            * Encode pointer to avoid $FF bytes in string
		move.l	d0,(a2)+            * Store encoded next-line pointer in definition string

* --- Parse procedure parameters ---

          move.l    a1,-(sp)            * Save pointer to variable's value field
          bsr       charget             * Read next character after proc name
		beq		proc_f3             * End of line -> no parameters, finalize
          cmp.b     #'(',d0             * Opening parenthesis for parameter list?
		beq		proc_f6             * Yes -> parse parameters
		cmp.b	#':',d0             * Statement separator?
		beq		proc_f3             * Yes -> no parameters, finalize
		bsr		Clr1                * Clear partially created variable
		bra		defprerr            * Error: invalid syntax after DEF PROC name

* --- Parameter parsing loop ---
proc_f6:
		move.l    a2,-(sp)            * Save current position in definition string buffer
          bsr       tst_prcvar          * Parse parameter variable name and look up
		move.w	typflag,d1          * Get parameter's base type
		move.w	d1,-(sp)            * Save base type on stack
		or.w		procnr,d1			* OR procedure number into type (makes it local)
		move.w	d1,typflag          * Set modified type for variable creation
		bsr		var3_def			* Create parameter variable (uses existing typflag with procnr)
		move.w	(sp)+,d1            * Restore base type (without procnr)
          move.l    (sp)+,a2            * Restore definition string buffer pointer

          move.w    d1,(a2)+			* Store parameter type (without procnr) in definition string
          move.l    a1,d0               * Get pointer to parameter variable's value
          bsr       code_ptr            * Encode pointer to avoid $FF bytes
          move.l    d0,(a2)+            * Store encoded pointer to parameter value
          bsr       charget             * Read next character
          cmp.b     #')',d0             * End of parameter list?
          beq       proc_f3             * Yes -> finalize definition string
          cmp.b     #',',d0             * Comma separator between parameters?
          beq       proc_f6             * Yes -> parse next parameter
          bra       syntaxerr           * Neither ) nor , -> syntax error

* --- Finalize procedure definition string ---
proc_f3:
          clr.w     (a2)+               * Write $0000 end-of-argument-list marker

* --- Copy definition string to string space ---

          lea       var2_name,a3        * Point to start of definition string in buffer
          sub.l     a3,a2               * Calculate string length (a2 - a3)
          move.l    a2,d0               * d0 = string length in bytes

          move.l    strend,a1           * a1 = current end of string space (grows downward)
          clr.b     (a1)                * Null-terminate
          sub.l     #32,a1              * Safety margin of 32 bytes
          sub.l     d0,a1               * Subtract string length
          cmp.l     varend,a1           * Does the string fit? (strend must stay above varend)
          bmi       outvarmem           * No -> out of variable memory error
          sub.l     d0,strend           * Allocate space by moving strend down

          btst      #0,strend+3         * Test bit 0 of strend (odd address check)
          bne       Wrdalligned         * If odd (bit 0 set) -> already word-aligned after sub
          subq.l    #1,strend           * Even address: subtract 1 to ensure word alignment
Wrdalligned:
          move.l    strend,a1           * Get updated strend
		addq.l	#1,a1               * Skip past the alignment byte
          move.l    a1,a4               * a4 = destination start (for storing in variable later)
          subq.w    #1,d0               * Adjust count for dbf loop (length - 1)
copyprc:
          move.b    (a3)+,(a1)+         * Copy one byte from buffer to string space
          dbf       d0,copyprc          * Loop until all bytes copied

          move.l    (sp)+,a1            * Restore pointer to proc variable's value field
          move.l    a4,(a1)             * Set variable's value to point to the definition string
		addq.w	#1*8,procnr		    * Increment procedure number by 8 for next proc
		cmp.w	#512*8,procnr		* Check if maximum (511 procs) exceeded
		beq		toomanyprocs        * Yes -> error: too many procedures

* --- Advance to next program line ---
procnxtline:
		move.l	(sp)+,a0            * Restore pointer to next line
		bra		proctstnxt          * Continue scanning

* --- Finish procedure scanning ---
endgetproc:
		move.w	procnr,d0           * Get final procnr value
		lsr.w	#3,d0               * Divide by 8 to get actual count
		subq.w	#1,d0               * Subtract 1 (numbering started at 1, not 0)
		move.w	d0,anzprocs         * Store total number of procedures found
		clr.w	procnr              * Reset procnr to 0 (global scope) for execution
		movem.l	(sp)+,a0/a1         * Restore registers
		rts


*==============================================================================
* PROC Command - Execute a Procedure Call
*------------------------------------------------------------------------------
* Purpose:  Calls a previously defined procedure. Resolves the procedure
*           variable, decodes the line pointer from the proc string,
*           evaluates and passes arguments (marking strings for GC safety),
*           pushes a 14-byte frame onto proctbl to save the caller's state,
*           and jumps to the procedure body.
*
* Proctbl entry layout (14 bytes):
*   Offset 0:  akt_zeile.l   (caller's line number)
*   Offset 4:  akt_adr.l     (caller's line address; 0 if called from direct mode)
*   Offset 8:  a0.l          (caller's execution pointer / return address in code)
*   Offset 12: procnr.w      (caller's procedure number)
*
* Entry:    a0 points to program text after PROC token
* Exit:     Execution jumps to procedure body via contwithrun
*==============================================================================
Proc:
		move.w	b_modus,-(sp)       * Save current mode (0=direct, -1=program) on stack
		move.w	#-1,b_modus         * Force program mode (procedures always run in program mode)
          bsr       tst_dprcvar         * Look up procedure variable; d0!=0 if found, a1=value ptr
          tst.w     d0                  * Was the procedure found?
          beq       procnotfound        * No -> "procedure not found" error
          move.l    (a1),a2             * a2 = pointer to procedure definition string
		move.w	(a2)+,-(sp)		    * Push procedure number (x8) from definition string
		move.l	(a2)+,d0			* Get encoded line pointer from definition string
		bsr		decode_ptr          * Decode pointer (reverse of code_ptr encoding)
		move.l	d0,-(sp)			* Save decoded line pointer (will use at end)

* --- Check if procedure expects arguments ---

          tst.w     (a2)                * Is first argument type word non-zero?
		bne		cproc2a             * Yes -> procedure has parameters, expect arguments
		move.l	a0,d1               * Save current program pointer
		bsr		charget             * Read next character from program
		move.l	d1,a0               * Restore program pointer (don't consume the char)
		tst.b	d0                  * End of line?
          beq       cproc1              * Yes -> no args needed, none given -> OK
		cmp.b	#':',d0             * Statement separator?
		beq		cproc1              * Yes -> no args given -> OK
		bra		manyargerr		    * Arguments given but proc expects none -> error

* --- Parse opening parenthesis for argument list ---
cproc2a:
          bsr       charget             * Read next character (should be '(')
          cmp.b     #'(',d0             * Is it opening parenthesis?
          bne       misargerr           * No -> "missing arguments" error

* --- Argument passing loop ---
cproc2:   move.w    (a2)+,typvalid      * Read expected argument type from definition string
          move.l    a2,-(sp)            * Save position in definition string
          bsr       get_defterm         * Evaluate argument expression (using typvalid as expected type)
          move.l    (sp)+,a2            * Restore definition string position
          move.l    (a2)+,d0            * Read encoded pointer to parameter variable's value
          bsr       decode_ptr          * Decode the pointer
          move.l    d0,a1               * a1 = pointer to parameter variable's value storage
          move.l    a2,-(sp)            * Save definition string position again
		cmp.w	#STRING,typvalid    * Is this argument a string?
		bne		nocprocmark         * No -> skip string marking
		bsr		mark_str            * Mark string to protect it from garbage collection
nocprocmark:
          bsr       write_var           * Write the evaluated argument value to the parameter variable
          move.l    (sp)+,a2            * Restore definition string position
          tst.w     (a2)                * More arguments in definition?
          beq       cproc1a             * No (end marker $0000) -> done with arguments
          bsr       tst_komma           * Check for comma separator between arguments
          bne       misargerr           * No comma found -> "missing arguments" error
          bra       cproc2              * Parse next argument

* --- Close parenthesis and set up procedure call frame ---
cproc1a:  bsr       chk_klammer         * Verify and consume closing parenthesis ')'

cproc1: * Now that all function arguments are initialized, execute the procedure
		move.l	(sp)+,a1			* Pop decoded line pointer (target line of proc body)
		tst.l	(a1)				* Is it end of program (null next-line pointer)?
		beq		noeprcerr           * Yes -> error: no ENDPROC found
		move.w	(sp)+,d0			* Pop procedure number

* --- Push 14-byte frame onto proctbl stack ---

		move.l	proctblptr,a2       * a2 = current top of procedure call stack
		cmp.l	#procetbl-14,a2     * Is there room for another 14-byte entry?
		bhi		toomanyprocs        * No -> error: too many nested procedure calls

		move.l	akt_zeile,(a2)+     * Save caller's current line number
		tst.w	(sp)+			    * Test and discard saved b_modus; was it direct mode (0)?
		bne		itsprg              * Non-zero -> was program mode, keep akt_adr
		clr.l	akt_adr             * Direct mode: clear akt_adr (signals direct mode return)
itsprg:
		move.l	akt_adr,(a2)+       * Save caller's line address (0 if from direct mode)
		move.l	a0,(a2)+            * Save caller's execution pointer (return point)
		move.w	procnr,(a2)+        * Save caller's procedure number
		move.l	a2,proctblptr       * Update proctbl stack pointer to new top

		move.w	d0,procnr           * Set new procedure number (activates local variable scope)
		move.l	a1,akt_adr          * Set current line address to procedure's first line
		move.l	4(a1),akt_zeile     * Set current line number from that line's header
		lea		8(a1),a0            * Point a0 to the line's content (past next-ptr and line-nr)

* --- Entry point: reset stack and continue running in program mode ---
contwithrun:
		lea		stack,sp            * Reset SP to interpreter's base stack (clear any leftover)
		move.w	#-1,b_modus         * Ensure program mode is set
		bra		runcont             * Continue execution at current a0 position


*==============================================================================
* ENDPROC - Return From Procedure
*------------------------------------------------------------------------------
* Purpose:  Pops the procedure call stack, restoring the caller's line
*           number, line address, execution pointer, and procedure number.
*           If the procedure was called from direct mode (akt_adr=0),
*           returns to the BASIC prompt via exec_line. Otherwise
*           continues program execution via runcont.
* Entry:    proctblptr points past the current frame
* Exit:     Execution resumes at the caller's saved position
*==============================================================================
Endproc:
          move.l    proctblptr,a1       * Get current top of procedure call stack
          cmp.l     #proctbl,a1         * Is the stack empty (at base)?
          beq       procerr             * Yes -> error: ENDPROC without matching PROC
          sub.l     #14,a1              * Back up 14 bytes to the current frame
          move.l    a1,proctblptr       * Update stack pointer (pop the frame)
          move.l    (a1)+,akt_zeile     * Restore caller's line number
          move.l    (a1)+,akt_adr       * Restore caller's line address (0 if direct mode)
          move.l    (a1)+,a0            * Restore caller's execution pointer
		move.w	(a1)+,procnr        * Restore caller's procedure number
		bsr		charget             * Advance past any remaining characters on ENDPROC line
		lea		stack,sp            * Reset SP to interpreter's base stack
		tst.l	akt_adr             * Was caller in direct mode? (akt_adr=0)
		bne		endprocprg          * No -> return to program mode execution
endprocdirekt:
		clr.w	b_modus             * Set direct mode (b_modus=0)
		pea		basic1              * Push BASIC prompt address as return address
		bra		exec_line			* Execute any remaining statement, then return to basic1
endprocprg:
		move.w	#-1,b_modus         * Ensure program mode is set
		bra		runcont             * Continue program execution at restored position

*==============================================================================
* HELP Command
*==============================================================================
* Purpose:  Lists all available BASIC commands/keywords.
*           Iterates through the helpnadr table (array of pointers to
*           keyword name strings). Each keyword string has bit 7 set on
*           characters after the minimum abbreviation point. This routine
*           temporarily clears bit 7 for display, then restores it.
* Entry:    a0 = program pointer (saved/restored)
* Exit:     All keywords printed, a0 restored
*==============================================================================
Help:
          movem.l   a0,-(sp)            * Save program pointer
          lea       helpnadr,a1         * a1 = pointer to table of command name pointers
help1:    move.l    (a1)+,d0            * Load next pointer from table (0 = end of table)
          beq       helpend             * Null pointer -> done listing
          move.l    d0,a0               * a0 = pointer to keyword name string
          move.l    a0,a2               * a2 = copy for scanning/restoring bit 7
help2:    addq.l    #1,a2               * Advance a2 to next character
          move.b    (a2),d0             * Read character at a2
          beq       help2a              * Null terminator -> end of string, print it
          bpl       help2               * Bit 7 clear -> normal char, keep scanning
          bclr      #7,(a2)             * Bit 7 set -> clear it temporarily for clean display
help2a:   bsr       put_string          * Print the keyword string (now with bit 7 cleared)
          move.b    d0,(a2)             * Restore original byte at a2 (with bit 7 if it was set)
          move.l    a1,-(sp)            * Save table pointer
          bsr       tab_                * Output a tab character for column formatting
          move.l    (sp)+,a1            * Restore table pointer
          bra       help1               * Process next keyword
helpend:  bsr       new_line            * Print final newline
          move.l    (sp)+,a0            * Restore program pointer
          bra       charget             * Read next character and return

*==============================================================================
* VARFRE / PRGFRE - Free Variable/Program Memory
*==============================================================================
* Purpose:  Returns the number of free bytes in variable/program space as INT.
*           FRE(0), FRE(2), FRE(3), etc. runs garbage collection first.
*           FRE(1) skips garbage collection.
*           Computes: strend - varend - 32 (32-byte safety margin).
* Entry:    Expression argument in parentheses
* Returns:  Result in fac1 as INT, typflag=INT
*==============================================================================
Prgfre:
Varfre:   move.w    #INT,typvalid       * Expect an INT argument
          bsr       get_term            * Evaluate the argument expression
		cmp.l	#1,fac1             * Is argument value 1?
		beq		nofregarb           * Yes -> skip garbage collection
		move.l	strend,pgarbend     * Set garbage collection end to current string end
		bsr		garbage             * Run garbage collector to reclaim dead strings
nofregarb:
          move.w    #INT,typflag        * Result type is INT
          move.l    strend,d0           * d0 = end of string space (top of free area)
          sub.l     #32,d0              * Subtract 32-byte safety margin
          sub.l     varend,d0           * Subtract end of variable space = free bytes
          rts                           * Return with free byte count in d0/fac1


*==============================================================================
* STRFRE - Free String Space
*==============================================================================
* Purpose:  Returns the number of free bytes in string space after
*           garbage collection. Computes: strbase - strend
*           (since strings grow downward from strbase toward strend).
* Entry:    Expression argument in parentheses
* Returns:  Result in fac1 as INT, typflag=INT
*==============================================================================
Strfre:   move.w    #INT,typvalid       * Expect an INT argument
          bsr       get_term            * Evaluate the argument expression
          move.l    strend,pgarbend     * Set garbage collection end to current string end
          bsr       garbage             * Always run garbage collector for string space
          move.w    #INT,typflag        * Result type is INT
          move.l    strbase,d0          * d0 = base of string space (highest address)
          sub.l     strend,d0           * Subtract current string end = free string bytes
          rts                           * Return with free byte count in d0/fac1
*==============================================================================
* This section implements:
*   - Edtab    : Editor TAB command (moves cursor by tab stops)
*   - Tab      : TAB() function in PRINT (positions cursor at absolute column)
*   - get_tab  : Helper to validate TAB/SPC argument
*   - Spc      : SPC() function (outputs N spaces)
*   - Int      : INT() function (converts float to integer)
*   - New      : NEW command (clears program and all variables)
*   - Clr      : CLR command (clears variables, optionally selective)
*   - Return   : RETURN from GOSUB
*   - Gosub    : GOSUB to subroutine
*   - Goto     : GOTO line number
*   - Run      : RUN command (starts program execution)
*
* Key data structures:
*   gostabl  - Stack of 12-byte GOSUB entries: [akt_zeile.l][akt_adr.l][return_a0.l]
*   fortable - Stack of 42-byte FOR entries
*   iftbl    - Stack of 4-byte IF entries
*   proctbl  - Stack of PROC entries
*==============================================================================


*==============================================================================
* Edtab - Editor TAB Command
*==============================================================================
* Purpose: Moves the editor cursor forward by N tab stops.
*          Evaluates an integer expression for the number of tab stops
*          to advance.  Does nothing if output is directed to a file.
* Parameters: Expression on BASIC input stream (number of tab stops)
* Returns: Nothing (cursor is repositioned)
*==============================================================================
Edtab:
          move.w    #INT,typvalid       * Request integer result type
          bsr       get_term            * Evaluate expression -> fac1
          move.w    #INT,typflag        * Result is integer
		tst.w	filefl              * Is output directed to a file?
		bne		edtabend			* Yes -> no editor tab possible, just return
          move.l    fac1,d0             * d0 = number of tab stops requested
		bmi		start1err           * Negative value -> illegal argument error
		beq		start1err           * Zero value -> illegal argument error
		clr.w	ed_x                * Reset cursor X position to column 0
		clr.w	ed_xoffs            * Reset horizontal scroll offset to 0
edtab1:
		bsr		ed_tab              * Advance cursor by one tab stop
		subq.w	#1,d0               * Decrement tab stop counter
		bne		edtab1              * Loop until all tab stops processed
edtabend:
		rts

* --- Tab - TAB() Function in PRINT ---
*==============================================================================
* Tab - TAB() Function for PRINT Statement
*==============================================================================
* Purpose: Positions the cursor at an absolute column position.
*          TAB(n) moves the cursor to column n (1-based).
*          If file output is active, falls through to Spc (outputs spaces
*          instead, since file output has no cursor positioning).
* Parameters: Expression on BASIC input stream (target column, 1-based)
* Returns: Nothing (cursor is repositioned, or spaces are output)
*==============================================================================
Tab:
          tst.w     filefl              * Is file output active?
          bne       Spc                 * Yes -> treat like SPC (output spaces)
          bsr       get_tab             * Get and validate TAB argument -> d0 (0-based)
          move.w    ed_x,d1             * d1 = current cursor X position
          add.w     ed_xoffs,d1         * Add horizontal scroll offset to get true column
          add.w     d0,d1               * d1 = target absolute column position
          cmp.l     maxspalten,d1       * Compare against maximum columns
          bge       cposerr             * Target >= max columns -> cursor position error
          move.w    d1,d0               * d0 = X position for ed_pos
          move.w    ed_y,d1             * d1 = current Y position (keep same row)
          bra       ed_pos              * Position cursor at (d0, d1) and return

*==============================================================================
* get_tab - Validate and Retrieve TAB/SPC Argument
*==============================================================================
* Purpose: Subroutine that evaluates and validates the argument for
*          TAB() and SPC() functions.  The argument must be >= 1 and
*          less than maxspalten (maximum columns).
* Parameters: Expression on BASIC input stream
* Returns: d0.l = validated argument, decremented by 1 (0-based)
*==============================================================================
get_tab:
          move.w    #INT,typvalid       * Request integer result type
          bsr       get_term            * Evaluate expression -> fac1
          move.w    #INT,typflag        * Result is integer
          move.l    fac1,d0             * d0 = TAB/SPC argument
		bmi		start1err           * Negative -> illegal argument error
		beq		start1err           * Zero -> illegal argument error
		subq.l	#1,d0               * Convert from 1-based to 0-based
          cmp.l     maxspalten,d0       * Compare against maximum columns
          bge       cposerr             * Argument >= max columns -> cursor position error
          rts

*==============================================================================
* Spc - SPC() Function
*==============================================================================
* Purpose: Outputs a specified number of space characters.
*          As a function, it also returns the count.
*          Builds a string of spaces in inputpuf and outputs it via
*          put_string.
* Parameters: Expression on BASIC input stream (number of spaces)
* Returns: d0.l = number of spaces (for use as a function return value)
*==============================================================================
* Outputs the specified number of spaces; as a function returns that count
Spc:
          bsr       get_tab             * Get and validate argument -> d0 (0-based count)
          move.l    d0,d1               * d1 = save space count for later return
          beq       spc1                * If zero spaces, skip output
          move.l    a0,a2               * Save a0 (BASIC program pointer) in a2
          lea       inputpuf,a0         * a0 = address of temporary input buffer
          move.l    a0,a1               * a1 = write pointer into buffer
spc2:     move.b    #' ',(a1)+          * Write a space character to the buffer
          subq.l    #1,d0               * Decrement space counter
          bne       spc2                * Loop until all spaces written
          clr.b     (a1)                * Null-terminate the space string
          bsr       put_string          * Output the string of spaces
          move.l    a2,a0               * Restore BASIC program pointer from a2
spc1:     move.l    d1,d0               * d0 = space count (function return value)
          rts

*==============================================================================
* Int - INT() Function
*==============================================================================
* Purpose: Returns the integer value of any numeric variable or expression.
*          Technically redundant since the interpreter auto-converts between
*          float and int, but provided for BASIC compatibility.
*          Calls get_term which handles float-to-int conversion via rpkl
*          when typvalid is set to INT.
* Parameters: Expression on BASIC input stream
* Returns: d0.l = integer value, typflag = INT
*==============================================================================
Int:
          move.w    #INT,typvalid       * Request integer result type (forces conversion)
          bsr       get_term            * Evaluate expression with int conversion
          move.l    fac1,d0             * d0 = integer result from fac1
          move.w    #INT,typflag        * Ensure type flag is set to INT
          rts

*==============================================================================
* New - NEW Command
*==============================================================================
* Purpose: Clears the BASIC program from memory AND all variables/state.
*          Like CLR, but also erases the program text.
*          Calls New1 to clear program area, then Clr1 to clear variables
*          and reset all control flow tables.
* Parameters: None
* Returns: Nothing (program and variables are cleared)
*==============================================================================
New:
		bsr		New1                * Clear the program area
		bsr		charget             * Consume any trailing character
		bra		Clr1                * Clear all variables and tables, then return

* --- New1 - Clear Program Area Only ---
*==============================================================================
* New1 - Clear Program Area
*==============================================================================
* Purpose: Resets the program storage to empty.  Sets prgend = prgbase,
*          then writes end-of-program markers:
*            offset 0: $00000000 (null next-pointer = end of linked list)
*            offset 4: $FFFFFFFF (line number -1 = sentinel)
* Parameters: None
* Returns: Nothing (program area is cleared)
*==============================================================================
New1:
		move.l	prgbase,a1          * a1 = start of program memory
		move.l	a1,prgend           * Set program end = program base (empty program)
		clr.l	(a1)                * Write null next-pointer (end of linked list)
		move.l	#-1,4(a1)           * Write sentinel line number ($FFFFFFFF)
		rts

*==============================================================================
* Clr - CLR Command
*==============================================================================
* Purpose: Clears variables and resets interpreter state.
*          Two modes:
*            1) CLR with no arguments (or followed by ':') -> full clear
*               via simpleclr, which calls Clr1 and re-scans procedures.
*            2) CLR varname [, varname ...] -> selectively clear named
*               variables (set INT vars to 0, FLOAT vars to 0.0).
* Parameters: Optional comma-separated list of variable names
* Returns: Nothing
*==============================================================================
Clr:
          bsr       charget             * Get next character from input
		beq		simpleclr           * End of statement -> full clear
		cmp.b	#':',d0             * Colon (statement separator)?
		beq		simpleclr           * Yes -> full clear
		subq.l	#1,a0               * Back up one character (re-read the var name)

* --- Selective CLR: clear specific variables ---
readclrnext:
		bsr		var2_def            * Look up/create variable -> a1=address, typvalid=type
		move.w	typvalid,d0         * d0 = variable type
		cmp.b	#INT,d0             * Is it an integer variable?
		beq		clrint              * Yes -> clear as integer
		cmp.b	#FLOAT,d0           * Is it a float variable?
		beq		clrfl               * Yes -> clear as float
clrint:
		clr.l	(a1)                * Clear integer variable (set to 0)
		bra		clrnext             * Check for more variables
clrfl:
		movem.l	zero_,d0-d2         * Load float zero constant (0.0) into d0-d2
		movem.l	d0-d2,(a1)          * Store 0.0 into the float variable (12 bytes)
*		bra		clrnext             * (fall through)
clrnext:
		bsr		charget             * Get next character
		bsr		tst_komma           * Test for comma separator
		beq		readclrnext		    * Comma found -> read and clear next variable
		rts                             * No comma -> done, return

* --- simpleclr - Full Clear (used by CLR with no args and CONT) ---
simpleclr:
		bsr		Clr1                * Full clear of all variables and tables
		bra		get_procs			* Re-scan program for procedure definitions, then return

* --- Clr1 - Full Variable and Table Clear ---
*==============================================================================
* Clr1 - Full Clear of Variables and Control Flow State
*==============================================================================
* Purpose: Resets all variable storage and control flow tables:
*          - Sets strend = strbase (clear string heap)
*          - Sets varbase = varend = prgend + 16 (clear variable list)
*          - Calls init_tbls to reset FOR/GOSUB/IF/PROC stacks
*          - Zeros the first 12 bytes at varbase (safety buffer)
*          - Clears the first 4 bytes of string space
*          - Resets fncnt (DEF FN count) and anzprocs (PROC count)
* Parameters: None
* Returns: Nothing
*==============================================================================
Clr1:     move.l    strbase,strend      * Reset string heap: strend = strbase (empty)
          move.l    prgend,d0           * d0 = end of program area
          add.l     #16,d0              * Add 16-byte gap between program and variables
          move.l    d0,varbase          * Set variable list base
          move.l    d0,varend           * Set variable list end (empty list)
          bsr       init_tbls           * Reset all FOR/GOSUB/IF/PROC tables
          movem.l   zero_,d0-d2         * Load 12 bytes of zeros (float zero constant)
          move.l    varbase,a1          * a1 = start of variable area
          movem.l   d0-d2,(a1)          * Zero the first 12 bytes (safety buffer)
          move.l    strbase,a1          * a1 = base of string heap
          clr.b     (a1)                * Clear 4 bytes at string base
          clr.b     -(a1)               *   (these serve as sentinel/terminator
          clr.b     -(a1)               *    bytes for the reverse-stored string
          clr.b     -(a1)               *    heap)
          clr.w     fncnt               * Reset count of defined DEF FN(x) functions
		clr.w	anzprocs			* Reset count of defined PROCedures
          rts

*==============================================================================
* init_tbls - Initialize All Control Flow Tables
*==============================================================================
* Purpose: Resets all control flow table pointers to their base addresses,
*          effectively clearing the FOR, GOSUB, IF, and PROC stacks.
*          Also resets trace state: if tracefl == 2 (trace paused for
*          exec buffer), reset it to 1 (TRON active).
*          Skips the reset if contline >= 0 (CONT is active and valid).
* Parameters: None
* Returns: Nothing
*==============================================================================
init_tbls:
          tst.l     contline            * Is CONT possible? (contline >= 0 means yes)
          bpl       init_tend           * If CONT active, skip table reset to preserve state
          move.l    #fortable,foreptr   * Reset FOR stack pointer to base (empty)
          move.l    #gostabl,goseptr    * Reset GOSUB stack pointer to base (empty)
          move.l    #iftbl,ifendptr     * Reset IF stack pointer to base (empty)
		move.l	#proctbl,proctblptr * Reset PROC stack pointer to base (empty)
		clr.w	procnr              * Reset current procedure nesting counter
		cmp.w	#2,tracefl          * Is trace flag == 2 (paused during exec buffer)?
		bne		init_tend           * No -> done
		move.w	#1,tracefl          * Yes -> restore to 1 (TRON active)
init_tend:rts

*==============================================================================
* Return - RETURN from GOSUB
*==============================================================================
* Purpose: Returns from a subroutine call (GOSUB).
*          Pops a 12-byte entry from the GOSUB stack (gostabl):
*            [0] akt_zeile  (4 bytes) - caller's line number
*            [4] akt_adr    (4 bytes) - caller's line node address
*            [8] return_a0  (4 bytes) - return address in tokenized line
*          If bit 31 of return_a0 is set, this was a TRACE GOSUB:
*            - Clear bit 31 to get the real return address
*            - Restore trace cursor position (trx, try)
*            - Set tracefl = 2 (skip next cmd in exec buffer)
*          If akt_adr == 0, the GOSUB was from direct mode.
* Parameters: None
* Returns: Resumes execution at the saved return address
*==============================================================================
Return:
          move.l    goseptr,a1          * a1 = current GOSUB stack pointer
          cmp.l     #gostabl,a1         * Is the stack empty (pointer at base)?
          beq       goserr              * Yes -> RETURN without GOSUB error
          sub.l     #12,a1              * Back up 12 bytes to the top entry
          move.l    a1,goseptr          * Update GOSUB stack pointer (pop entry)
          move.l    (a1)+,akt_zeile     * Restore caller's line number
          move.l    (a1)+,akt_adr       * Restore caller's line node address
          move.l    (a1),d0             * d0 = return address (possibly with bit 31 flag)
		btst		#31,d0              * Was this a TRACE GOSUB? (bit 31 set?)
		beq		return              * No -> normal return

		bclr		#31,d0              * Clear the TRACE flag bit to get real address
		move.l	d0,a0		        * a0 = real return address in tokenized line
		move.w	trx,d0              * d0 = saved trace cursor X position
		move.w	try,d1              * d1 = saved trace cursor Y position
		bsr		ed_pos              * Restore cursor to trace display position
		move.w	#2,tracefl		    * Set tracefl = 2: skip next cmd in exec buffer
		bra		return2             * Jump to common return path

return:
		move.l	d0,a0               * a0 = return address in tokenized line
return2:
		tst.l	akt_adr             * Was the GOSUB from direct mode? (akt_adr == 0?)
		beq		endprocdirekt       * Yes -> return to direct mode handler
		bne		endprocprg          * No -> return to program mode handler


*==============================================================================
* Gosub - GOSUB Command
*==============================================================================
* Purpose: Calls a subroutine at the specified line number.
*          Pushes a 12-byte entry onto the GOSUB stack (gostabl):
*            [0] akt_zeile  (4 bytes) - current line number (caller)
*            [4] akt_adr    (4 bytes) - current line address (caller)
*                 In direct mode, akt_adr is set to 0 as a flag.
*            [8] a0         (4 bytes) - return address (position after GOSUB)
*          Then transfers control to the target line.
*          Gosub1 is a shared entry point also used by ON...GOSUB
*          (fac1 already contains the target line number).
* Parameters: Line number expression on BASIC input stream
* Returns: Execution continues at the target line
*==============================================================================
* GOSUB structure (12 bytes per entry):
*   offset 0: line number of the GOSUB statement
*   offset 4: line address of the GOSUB statement
*   offset 8: return address (pointer after GOSUB command)
Gosub:
          move.w    #INT,typvalid       * Request integer result type
          bsr       get_term            * Evaluate line number expression -> fac1

* --- Gosub1 - Shared Entry (also used by ON...GOSUB) ---
Gosub1:   move.l    fac1,d0             * d0 = target line number
          bsr       poszeile            * Find line in program -> a1 = line node address
          cmp.l     4(a1),d0            * Does the line actually exist? (compare line numbers)
          bne       nolineerr           * Line not found -> "line not found" error
          move.l    goseptr,a2          * a2 = current GOSUB stack pointer
          cmp.l     #endgostabl-12,a2   * Room for another 12-byte entry?
          bhi       gosflow             * No -> GOSUB stack overflow error
          move.l    akt_zeile,(a2)+     * Push caller's line number onto stack
		tst.w	b_modus             * Check execution mode
		bne		gosprg              * If program mode (b_modus != 0) -> skip direct mode handling
		clr.l	akt_adr			    * Direct mode: set akt_adr = 0 as marker
gosprg:
          move.l    akt_adr,(a2)+       * Push caller's line address (0 if direct mode)
          move.l    a0,(a2)+            * Push return address (position after GOSUB)
          move.l    a2,goseptr          * Update GOSUB stack pointer to new top
          move.l    d0,akt_zeile        * Set current line number to target
          lea       8(a1),a3            * a3 = skip past next-ptr and line# (point to code)
          move.l    a1,akt_adr          * Set current line address to target line node
          move.l    a3,a0               * a0 = execution pointer at start of target line code

		bra		contwithrun         * Continue execution in the run loop


*==============================================================================
* Goto - GOTO Command
*==============================================================================
* Purpose: Unconditional jump to the specified line number.
*          Pops the return address off the hardware stack (discards the
*          caller's frame from the BSR that dispatched this command),
*          then falls into Run2 to evaluate the line number and jump.
* Parameters: Line number expression on BASIC input stream
* Returns: Execution continues at the target line (does not return)
*==============================================================================
Goto:
          addq.l    #4,sp               * Discard return address from stack (we won't return)
          bra       Run2                * Jump to Run2 to parse line number and start there

*==============================================================================
* Run - RUN Command
*==============================================================================
* Purpose: Starts (or restarts) program execution.
*          1. Sets contline = -1 (disable CONT)
*          2. Sets traceline = -1 (disable trace line)
*          3. Calls Clr1 to clear all variables and control flow tables
*          4. Calls restore to reset DATA pointer
*          5. Calls get_procs to pre-scan for procedure definitions
*          6. If a line number argument is given, starts from that line;
*             otherwise starts from the beginning of the program.
*          The main execution loop (run1/runcont) then processes each
*          line: exec_line executes the current line's statements,
*          then the loop advances to the next line via the linked list.
* Parameters: Optional line number on BASIC input stream
* Returns: Does not return normally; runs until program ends or error
*==============================================================================
Run:
          move.l    #-1,contline        * Disable CONT (cannot continue after RUN)
		move.l	#-1,traceline       * Disable trace line
          bsr       Clr1                * Clear all variables and control flow tables
          bsr       restore             * Reset DATA read pointer to beginning
		bsr		get_procs			* Pre-scan program for all PROC definitions
          bsr       tstnxtarg           * Test if a line number argument follows (BEQ = yes)
          bne       run3                * No argument -> start from line 0 (beginning)

* --- Run2 - Parse Line Number and Jump ---
* This entry point is also used by GOTO to parse a target line number.
Run2:     move.w    #INT,typvalid       * Request integer result type
          bsr       get_term            * Evaluate line number expression -> fac1

* --- Run1 - Start Execution at Line in fac1 ---
* This entry point is used when fac1 already contains the target line.
Run1:     move.l    fac1,d0             * d0 = target line number
          bsr       poszeile            * Find line in program linked list -> a1
          cmp.l     4(a1),d0            * Does the line actually exist?
          beq       run3a               * Yes -> proceed to start execution
          bra       nolineerr           * No -> "line not found" error

* --- run3 - Start from Beginning ---
run3:     moveq.l   #0,d0               * Default: start from line 0 (first line)
          bsr       poszeile            * Find first line -> a1 = first line node

* --- run3a - Enter Main Execution Loop ---
run3a:    move.w    #-1,b_modus         * Set program mode (b_modus = -1)
		move.l	4(a1),a2			* a2 = line number of the starting line
          move.l    a2,akt_zeile		* Set current line number precisely

		lea		stack,sp			* Reset SP to initial stack level (clean stack)

* --- run1 - Main Execution Loop ---
* Processes one line at a time: check for end, execute, advance to next.
run1:     tst.l     (a1)                * Test next-pointer: is this the end of program?
          beq       run2a2              * Null next-pointer -> end of program listing
          move.l    a1,akt_adr          * Save address of current line node
          lea       8(a1),a0            * a0 = pointer to tokenized code (skip 4-byte next + 4-byte line#)
          clr.w     ifcnt               * Reset IF nesting counter for this line

* --- runcont - Execute Current Statement and Advance ---
* This is the main run loop continuation point.
* After exec_line returns, we follow the linked list to the next line.
runcont:  bsr       exec_line           * Execute one statement (or chain of statements on the line)
          move.l    akt_adr,a1          * a1 = current line node address
          move.l    (a1),a1             * a1 = follow next-pointer to the next line
		move.l	akt_zeile,a2		* a2 = save current line number (for error reporting at end)
          move.l    4(a1),akt_zeile     * Update akt_zeile to the next line's number
          bra       run1                * Loop back to process the next line

* --- run2a2 - Program End Reached ---
* When the program runs off the end of the listing, check that all
* control flow structures (FOR, GOSUB, PROC) have been properly closed.
run2a2:
		move.l	a2,akt_zeile		* Remember last line number (for error messages)
run2:
		cmp.l	#fortable,foreptr	* Are all FOR loops closed? (pointer at base?)
		bne		nonxterr            * No -> "FOR without NEXT" error
		cmp.l	#gostabl,goseptr	* Are all GOSUBs returned? (pointer at base?)
		bne		noreterr            * No -> "GOSUB without RETURN" error
		cmp.l	#proctbl,proctblptr	* Are all PROCs ended? (pointer at base?)
		bne		noeprcerr           * No -> "PROC without ENDPROC" error
		bra		basic1              * All clean -> return to BASIC direct mode prompt

*==============================================================================
* SECTION: LOAD / MERGE / CONVERT / SAVE
*==============================================================================
* This section implements the four BASIC commands for program file I/O:
*   - tst_prgheader: validates the "HEAD" magic number on a loaded file
*   - Merge:   merges lines from a tokenized file into the current program
*   - Convert: imports an ASCII text file, tokenizing each line
*   - Load:    loads a complete tokenized program from disk
*   - Save:    saves the current program (or a line range) to disk
*
* File format: [4-byte HEADER magic "HEAD"][linked-list program data]
* Program lines in memory: [next_ptr.l][line_number.l][tokenized data...]
* On disk the next_ptr values are stored as relative offsets from the start
* of the saved block, so the file is position-independent.
*==============================================================================

*==============================================================================
* LOAD
*==============================================================================

*==============================================================================
* tst_prgheader -- Validate BASIC program file header
*
* Purpose:   Reads the first 4 bytes from the currently open file and
*            verifies they match the HEADER constant ($48454144 = "HEAD").
*            If the magic does not match, closes the file and raises a
*            header error.
*
* Parameters: File must already be open (handle set by f_open)
* Returns:    Falls through on success; branches to headerr on failure
* Destroys:   D0, A1
*==============================================================================
tst_prgheader:
		lea		work1,a1			* A1 -> temporary work buffer
		moveq	#4,d0				* D0 = 4 bytes to read (size of magic)
		bsr		f_read				* Read 4 bytes from file into work1
		move.l	work1,d0			* D0 = the 4 bytes we just read
		cmp.l	#HEADER,d0			* Compare against HEADER magic ($48454144)
		beq		tst_hok				* Branch if valid header -> success
		bsr		f_close				* Invalid header: close the file first
		bra		headerr				* Then raise "header error"
tst_hok:
		rts							* Header is valid, return to caller

*==============================================================================
* Merge -- MERGE command
*
* Purpose:   Opens a tokenized BASIC file and merges its lines one by one
*            into the current program. Each line is read individually and
*            inserted via basic20 (the same routine used by the editor to
*            insert/replace a line). Existing lines with the same number
*            are replaced; new lines are inserted in order.
*
* Parameters: Current parse position points to filename string expression
* Returns:    Returns to caller (A0 restored from stack)
* Destroys:   D0-D2, A0-A1
*==============================================================================
Merge:
		move.w	#STRING,typvalid	* Expect a STRING type for the filename
		bsr		get_term			* Evaluate expression -> str_ptr has filename
		move.l	a0,-(sp)			* Save parse pointer on stack
		bsr		f_open				* Open file (str_ptr -> filename, sets handle)
		bsr		tst_prgheader		* Validate "HEAD" magic at start of file
		lea		mergetext,a0		* A0 -> "merging..." status message
		bsr		put_string			* Display the status message

		move.l	#-1,contline		* Disable CONT (no valid continuation point)
		move.l	#-1,traceline		* Disable TRACE
		bsr		Clr1				* Clear all variables and strings
		bsr		restore				* Reset DATA pointer and variable state

* --- Read and insert lines one at a time ---
		clr.l	d1					* D1 = file offset of current line (starts at 0)
merge:
		lea		inputpuf,a1			* A1 -> input buffer for reading
		moveq.l	#4,d0				* D0 = 4 bytes to read (the next-line offset)
		bsr		f_read				* Read next-line offset from file
		tst.l	d0					* Check bytes actually read
		beq		mergeend			* If 0 bytes read, end of file reached
		move.l	(a1),d2				* D2 = next-line offset (absolute file position)

		move.l    d2,d0				* D0 = next-line offset
		sub.l	d1,d0				* Subtract previous offset -> length of this line's data
		subq.l	#4,d0				* Subtract 4 because we already read the next-ptr
		lea		inputpuf,a1			* A1 -> buffer for line data
		bsr		f_read				* Read the rest of the line (line number + tokens)
		move.l	(a1)+,d0			* D0 = line number (first 4 bytes of line data)
		move.l	a1,a0				* A0 -> tokenized data (after line number)
		move.l	d2,-(sp)			* Save next-line offset on stack
		bsr		basic20				* Insert/replace line in program (D0=line#, A0=data)
		move.l	(sp)+,d1			* Restore next-line offset as new "previous offset"
		bra		merge				* Loop to read next line

* --- Merge complete ---
mergeend:
		bsr		f_close				* Close the file
		bsr		get_procs			* Re-scan program for PROCEDURE/FUNCTION definitions
		move.l	(sp)+,a0			* Restore parse pointer
		rts							* Return to caller

*==============================================================================
* Convert -- CONVERT command
*
* Purpose:   Converts an ASCII text file (.TXT) into tokenized BASIC lines.
*            Reads the file byte-by-byte, assembles characters into lines
*            in the input buffer. CR (13) marks end of line, LF (10) is
*            skipped, TAB (9) is replaced by a space. Each completed line
*            is tokenized via konv_inpuf and inserted via zeilenverwaltung.
*            Lines that do not start with a digit (0-9) are skipped.
*            The convfl flag is set during conversion so the error handler
*            knows to close the file if an error occurs.
*
* Parameters: Current parse position points to filename string expression
* Returns:    Branches to Loadend (resets state and returns)
* Destroys:   D0, A0-A1
*==============================================================================

* --- Convert-active flag (word) ---
* Wandelt ASCII-Datei in Basiczeilen		* "Converts ASCII file to BASIC lines"
convfl:	.dc.w	0						* 0 = not converting, 1 = conversion active

Convert:
		move.w	#STRING,typvalid		* Expect STRING type for the filename
		bsr		get_term				* Evaluate expression -> str_ptr has filename
		bsr		f_open					* Open the ASCII file for reading
		move.w	#1,convfl				* Set convert-active flag (conv aktiv!)
		lea		convtext,a0				* A0 -> "converting..." status message
		bsr		put_string				* Display the status message
		bsr		New1					* Clear current program (NEW without reset)
		bsr		Clr1					* Clear variables and strings

* --- Read file byte by byte, building lines in inputpuf ---
convnext:
		lea		inputpuf,a1				* A1 -> start of raw input buffer
		move.l	a1,a0					* A0 = write cursor into buffer
convrepeat:
		moveq.l	#1,d0					* D0 = 1 byte to read
		move.l	a1,-(sp)				* Save write cursor on stack
		bsr		f_read					* Read one byte from file
		move.l	(sp)+,a1				* Restore write cursor
		tst.l	d0						* Check bytes actually read
		beq		convend					* 0 bytes -> end of file
		move.b	(a1),d0					* D0 = the byte we just read
		beq		convend					* NUL byte -> treat as end of file
		cmp.b	#13,d0					* Is it CR (carriage return)?
		beq		convlend				* Yes -> end of this line
		cmp.b	#10,d0					* Is it LF (line feed)?
		beq		convrepeat				* Yes -> skip it (CR already handled line end)
		cmp.b	#9,d0					* Is it TAB?
		bne		convnotab				* No -> keep character as-is
		move.b	#' ',(a1)				* Yes -> replace TAB with space
convnotab:
		addq.l	#1,a1					* Advance write cursor
		cmp.l	#inputepuf,a1			* Past end of input buffer?
		beq		convovflerr				* Yes -> overflow error
		bra		convrepeat				* Continue reading bytes

* --- End of line: tokenize and insert if it starts with a digit ---
convlend:
		sub.l	a0,a1					* A1 = length of line (end - start)
		move.l	a1,d0					* D0 = line length
		tst.l	d0						* Is the line empty?
		beq		convnext				* Empty line -> skip, read next line
		bsr		copy_inpuf				* Copy raw input to working buffer
		bsr		konv_inpuf				* Tokenize the input line
		lea		input_puf,a0			* A0 -> tokenized line
		move.b	(a0),d0					* D0 = first character of the line
		cmp.b	#'0',d0					* Is it below '0'?
		bmi		convnoerr				* Yes -> not a numbered line, skip
		cmp.b	#'9',d0					* Is it above '9'?
		bhi		convnoerr				* Yes -> not a numbered line, skip
		bsr		zeilenverwaltung		* Tokenize and insert line into program
		bra		convnext				* Process next line

* --- Conversion complete ---
convend:
		bsr		f_close					* Close the ASCII file
		clr.w	convfl					* Clear convert-active flag
		lea		input_puf,a0			* A0 -> input buffer
		clr.l	(a0)					* Clear the input buffer
		bra		Loadend					* Jump to common load-end cleanup

*==============================================================================
* Load -- LOAD command
*
* Purpose:   Loads a complete tokenized BASIC program from disk.
*            The file must start with the HEADER magic ("HEAD").
*            After the 4-byte header, the entire program is read in one
*            Fread call into prgbase. The stored relative next-pointers
*            are then converted to absolute addresses via new_link.
*            If ":run" follows the filename, the program is executed.
*
* Parameters: Current parse position points to filename string expression
* Returns:    Returns to caller, or branches to run3 if ":run" follows
* Destroys:   D0, A0-A2
*==============================================================================

* Laedt prg relativ von disk				* "Loads program (relative) from disk"
Load:
          move.w    #STRING,typvalid    * Expect STRING type for the filename
          bsr       get_term			* Evaluate expression -> str_ptr has filename
          move.l    a0,-(sp)            * Save parse pointer on stack
          bsr       f_open              * Open file (str_ptr -> name, handle set)
		bsr		tst_prgheader		* Validate "HEAD" magic header
          lea       loadtext,a0			* A0 -> "loading..." status message
          bsr       put_string			* Display the status message
		bsr		New1				* Clear current program (sets prgend = prgbase)
          move.l    #$fffff,d0          * D0 = max read size (1MB-1); actual length unimportant
          bsr       f_read              * Read program data into prgbase; D0 = bytes read
          add.l     d0,prgend			* Advance prgend by number of bytes read
          bsr       f_close				* Close the file
          bsr       new_link            * Convert relative offsets to absolute pointers
          move.l    (sp)+,a0			* Restore parse pointer

* --- Common cleanup for Load and Convert ---
Loadend:
          move.l    #-1,contline        * Disable CONT (no valid continuation point)
		move.l	#-1,traceline		* Disable TRACE
          bsr       Clr1				* Clear all variables and strings
          bsr       restore             * Reset DATA pointer and variable state
		bsr		get_procs			* Re-scan program for PROC/FN definitions
          tst.w     b_modus             * Check execution mode: 0=direct, -1=program
          beq       loadend				* If direct mode -> just return
		lea		stack,sp			* In program mode: reset stack pointer
          bra       run3				* Branch to run handler (execute ":run" suffix)
loadend:
          rts							* Return to caller (direct mode)

*==============================================================================
* SAVE
*==============================================================================

*==============================================================================
* Save -- SAVE command
*
* Purpose:   Saves the current program (or a specified line range) to disk
*            as a tokenized BASIC file. The file format is:
*              [4 bytes: HEADER magic "HEAD"]
*              [program lines with relative next-pointers]
*            Before writing, absolute next-pointers in the linked list are
*            converted to relative offsets (from the start of the saved
*            block). After writing, they are converted back to absolute.
*            Optional arguments: SAVE "file",startline,endline
*
* Parameters: Parse position -> filename [,startline [,endline]]
* Returns:    Returns to caller (A0 restored from stack)
* Destroys:   D0-D2, D6-D7, A0-A5
*==============================================================================

* Speichert prg relativ auf disk			* "Saves program (relative) to disk"
Save:
          move.w    #STRING,typvalid    * Expect STRING type for the filename
          bsr       get_term			* Evaluate expression -> str_ptr has filename

* --- Parse optional line range arguments ---
		clr.l	d6					* D6 = start line (default: 0 = first line)
		move.l	#$7fffffff,d7		* D7 = end line (default: max int = all lines)
		bsr		tst_komma			* Test for comma after filename
		bne		save0				* No comma -> save entire program
		move.l	d6,-(sp)			* Save D6 (start line = 0) on stack
		move.w	#INT,typvalid		* Expect INT type for first line number arg
		bsr		get_term			* Evaluate expression -> fac1 = value
		move.l	(sp)+,d6			* Restore D6
		move.l	fac1,d7				* D7 = end line (first numeric arg)
		bsr		tst_komma			* Test for second comma
		bne		save0				* No second comma -> save from 0 to D7
		move.l	d7,-(sp)			* Two args: first arg was start line; save it
		move.w	#INT,typvalid		* Expect INT type for second arg
		bsr		get_term			* Evaluate expression -> fac1 = end line
		move.l	(sp)+,d6			* D6 = start line (was first arg)
		move.l	fac1,d7				* D7 = end line (second arg)

* --- Create file and write header ---
save0:
		bsr		tstlinenr			* Validate line number range
          move.l    a0,-(sp)            * Save parse pointer on stack
          bsr       f_create            * Create file (str_ptr -> name, handle set)
          lea       savetext,a0			* A0 -> "saving..." status message
          bsr       put_string			* Display the status message
		lea		work1,a1			* A1 -> temporary work buffer
		move.l	#HEADER,(a1)		* Store HEADER magic ($48454144) in buffer
		moveq.l	#4,d0				* D0 = 4 bytes to write
		bsr		f_write				* Write the BASIC program file header

* --- Find start line in program (walk linked list) ---
save1:
		move.l	prgend,a2			* A2 = default start = prgend (no lines found)
		move.l	prgbase,a0			* A0 = pointer to first program line
save3b:
		move.l	(a0),d0				* D0 = next-pointer (0 = end of program)
		beq		save3				* If 0 -> end of listing, use default
		cmp.l	4(a0),d6			* Compare start line (D6) with this line's number
		bls		save3a				* If start <= line number -> found start line
		move.l	d0,a0				* Move to next line in linked list
		bra		save3b				* Continue searching

save3a:
		move.l	a0,a2				* A2 = address of first line to save

* --- Find end line in program (walk linked list from start) ---
save3:
		move.l	prgend,a3			* A3 = default end = prgend (save to end)
		move.l	a2,a0				* A0 = start from the first line to save
save4b:
		move.l	(a0),d0				* D0 = next-pointer (0 = end of program)
		beq		save4				* If 0 -> end of listing reached
		cmp.l	4(a0),d7			* Compare end line (D7) with this line's number
		blt		save4a				* If end < line number -> past last line to save
		move.l	d0,a0				* Move to next line in linked list
		bra		save4b				* Continue searching

save4a:
		move.l	a0,a3				* A3 = address just past last line to save

* --- Convert absolute pointers to relative offsets ---
* Each line's next-pointer is converted from an absolute memory address
* to a relative offset from the start of the save block (A2). This makes
* the file position-independent so it can be loaded at any address.
save4:
		move.l	a2,a4				* A4 = current line pointer (walk start)
		move.l	a3,a5				* A5 = end pointer (stop here)
		move.l	a2,d0				* D0 = base address to subtract (makes offsets relative)
save6:
		cmp.l	a4,a5				* Have we reached the end?
		beq		save5				* Yes -> done converting
		move.l	(a4),d1				* D1 = absolute next-pointer of current line
		move.l	d1,d2				* D2 = save original absolute pointer
		sub.l	d0,d1				* D1 = relative offset (absolute - base)
		move.l	d1,(a4)				* Store relative offset back into the line
		move.l	d2,a4				* Advance A4 to next line (using saved absolute ptr)
		bra		save6				* Continue loop

* --- Write program data to file ---
save5:
		move.l	a2,a1				* A1 = buffer pointer (start of data to write)
		move.l	a3,d0				* D0 = end address
		sub.l	a2,d0				* D0 = byte count (end - start)
          bsr       f_write             * Write program data to file (A1=buf, D0=len)
          bsr       f_close				* Close the file

* --- Convert relative offsets back to absolute pointers ---
* Now that the file is written, restore the in-memory linked list
* back to absolute pointers so the program can continue running.
		move.l	a2,a4				* A4 = current line pointer (walk start)
		move.l	a3,a5				* A5 = end pointer (stop here)
		move.l	a2,d0				* D0 = base address to add back (restores absolute)
save7:
		cmp.l	a4,a5				* Have we reached the end?
		beq		save8				* Yes -> done restoring
		move.l	(a4),d1				* D1 = relative offset of current line
		add.l	d0,d1				* D1 = absolute pointer (relative + base)
		move.l	d1,(a4)				* Store absolute pointer back into the line
		move.l	d1,a4				* Advance A4 to next line (now absolute again)
		bra		save7				* Continue loop

* --- Save complete ---
save8:
          move.l    (sp)+,a0			* Restore parse pointer from stack
          rts							* Return to caller

*==============================================================================
* SECTION: LIST / Editor Scroll Support
*==============================================================================
* This section implements the LIST and DELETE commands, as well as the
* editor scroll callbacks (b_preup, b_predown, b_up, b_down) that allow
* the screen editor to scroll through the program listing. It also contains
* the DIM command for array declarations and the PRINT command with all its
* output formatting logic.
*
* Key data structures:
*   - Program lines: linked list starting at prgbase.
*     Each line: [4-byte next ptr][4-byte line number][tokenized data]
*   - Token system: TOKEN1=$01, TOKEN2=$02, TOKEN3=$03 intro bytes
*     followed by a 1-byte index into tokenadr name tables.
*   - tokenadr: table of pointers to keyword string tables (one per token class)
*   - Keyword strings: lowercase, with bit7 set on chars past minimum abbreviation
*==============================================================================

*==============================================================================
* VARIABLE: scrline
* Purpose: Holds the line number extracted from the top or bottom screen line
*          by b_preup/b_predown. Used by b_up/b_down to know which BASIC
*          program line is currently at the edge of the screen.
*          Set to -1 if no valid line number could be read.
*==============================================================================
scrline:	.ds.l	1

*==============================================================================
* ROUTINE: b_preup / b_predown (Editor pre-scroll callbacks)
* Purpose: Called by the editor BEFORE a scroll-up or scroll-down occurs.
*          Reads the line number from the top (pre-up) or bottom (pre-down)
*          screen line so that b_up/b_down know which BASIC line to display
*          after the scroll completes.
* Entry:   ed_scrline = pointer to the first character of the relevant screen line
*          ed_mode = 1 if in editor mode, 0 otherwise
* Exit:    scrline = extracted line number, or -1 if none found
*==============================================================================
b_preup:
b_predown:
		movem.l	d0-a6,-(sp)          * save all registers
		moveq.l	#-1,d0               * default: no line number found (-1)
		move.l	d0,scrline           * store default into scrline
		tst.w	ed_mode              * 1=editor mode -> ok to proceed
		beq		nolinenr             * not in editor mode -> skip

		move.l	ed_scrline,a0        * a0 = pointer to start of screen line
		bsr		charget              * read first character into d0
		cmp.b	#'0',d0              * is it a digit (>= '0')?
		blt		nolinenr             * no -> no line number on this line
		cmp.b	#'9',d0              * is it a digit (<= '9')?
		bhi		nolinenr             * no -> no line number on this line

		subq.l	#1,a0                * back up: charget advanced past the char
		bsr		get_int              * parse the integer from the screen text -> d0
		move.l	d0,scrline           * store extracted line number
nolinenr:
		movem.l	(sp)+,d0-a6          * restore all registers
		rts

*==============================================================================
* ROUTINE: b_up (Editor scroll-up callback)
* Purpose: Called by the editor AFTER scrolling up. Displays the program line
*          that should appear at the new top of the screen. Uses scrline
*          (set by b_preup) to locate the current top line, then finds the
*          PREVIOUS line in the linked list and displays it.
* Entry:   scrline = line number of the former top screen line (or -1)
* Uses:    poszeile to find the line, preline to get the previous line
*==============================================================================
b_up:
		tst.l	scrline              * was a valid line number found?
		bmi		b_scrend             * -1 = no valid line -> do nothing
		movem.l	d0-a6,-(sp)          * save all registers

		move.l	scrline,d0           * d0 = current top line number
		bsr		poszeile             * find this line in the linked list
		move.l	preline,d0           * d0 = address of the PREVIOUS line (set by poszeile)
		beq		nochange             * no previous line (at start of program) -> nothing to do

		move.w	ed_x,-(sp)           * save editor cursor X position
		move.w	ed_xoffs,-(sp)       * save editor X scroll offset
		clr.w	ed_x                 * reset cursor to column 0 for output
		clr.w	ed_xoffs             * reset scroll offset to 0
		move.l	d0,a0                * a0 = pointer to previous line's header
		move.l	4(a0),d6             * d6 = line number of previous line (offset 4 in header)
		bra		listoneline          * display this single line

*==============================================================================
* ROUTINE: b_down (Editor scroll-down callback)
* Purpose: Called by the editor AFTER scrolling down. Displays the program line
*          that should appear at the new bottom of the screen. Uses scrline
*          (set by b_predown) to locate the current bottom line, then finds
*          the NEXT line in the linked list and displays it.
* Entry:   scrline = line number of the former bottom screen line (or -1)
* Uses:    poszeile with scrline+1 to find the next line
*==============================================================================
b_down:
		tst.l	scrline              * was a valid line number found?
		bmi		b_scrend             * -1 = no valid line -> do nothing
		movem.l	d0-a6,-(sp)          * save all registers
		move.w	ed_x,-(sp)           * save editor cursor X position
		move.w	ed_xoffs,-(sp)       * save editor X scroll offset
		clr.w	ed_x                 * reset cursor to column 0
		clr.w	ed_xoffs             * reset scroll offset to 0
		move.l	scrline,d0           * d0 = bottom screen line number
		addq.l	#1,d0                * d0 = line number + 1 (to find the NEXT line)
		bsr		poszeile             * find this line; a1 = line at or after d0

		move.l	a1,a0                * a0 = pointer to the next line's data
		move.l	d0,d6                * d6 = line number (for listoneline's range check)

*==============================================================================
* ROUTINE: listoneline
* Purpose: Display a single program line on the editor screen. Sets d7 to
*          max value so listlines will stop after one line. After display,
*          checks if the X scroll offset changed; if so, redraws the line.
* Entry:   a0 = pointer to program line (first byte of line header)
*          d6 = start line number for range check
*          Stack: saved ed_xoffs, ed_x (pushed by b_up or b_down)
* Uses:    listlines with count=1 and d7=$7FFFFFFF (no upper limit)
*==============================================================================
listoneline:
		move.l	#$7fffffff,d7        * d7 = no upper line limit (show any line >= d6)
		moveq.l	#1,d0                * d0 = 1: flag for SCROLL mode (not LIST mode)
		bsr		listlines            * display the line(s) via the main listing routine

		move.w	ed_xoffs,d0          * d0 = current X offset after listing
		move.w	(sp)+,ed_xoffs       * restore original X scroll offset
		move.w	(sp)+,ed_x           * restore original cursor X position
		cmp.w	ed_xoffs,d0          * did the X offset change during listing?
		beq		nochange             * no change -> skip redraw
          jsr		ed_prline            * offset changed -> redraw the current editor line
nochange:
		movem.l	(sp)+,d0-a6          * restore all registers
b_scrend:
		rts


*==============================================================================
* ROUTINE: Delete (DELETE command)
* Purpose: Delete program lines within an optional range [d6..d7].
*          Parses optional start,end parameters via getoptparam, then walks
*          the linked list from prgbase, removing lines whose numbers fall
*          within the specified range by calling delline2 for each.
* Syntax:  DELETE [start][,end]
* Entry:   a0 = pointer into BASIC program text
* Uses:    getoptparam -> d6=start line, d7=end line
*          Clr1 clears runtime state
*          delline2 unlinks and removes one program line
*==============================================================================
* Delete command - see LIST for related range parsing
Delete:
		bsr		getoptparam          * parse optional start,end line numbers -> d6, d7
		bsr		Clr1                 * clear runtime state (variables, etc.)
		move.l	prgbase,a1           * a1 = start of program linked list
delLoop:
		tst.l     (a1)                * is the next-pointer zero (end of program)?
          beq       delend               * yes -> done deleting
delloop:
          move.l    4(a1),d0             * d0 = line number of current line (offset 4)
          cmp.l     d6,d0                * is line number >= start of range?
          blt       del1                 * no (less than start) -> skip to next line
          cmp.l     d7,d0                * is line number > end of range?
          bhi       delend               * yes (past end) -> stop deleting
		movem.l	d6/d7/a0/a1,-(sp)    * save range and pointers across delline2 call
		bsr		delline2             * unlink and delete the current line
		movem.l	(sp)+,d6/d7/a0/a1   * restore range and pointers
		tst.l	(a1)                 * did delline2 leave a valid next pointer?
		bne		delloop              * yes -> check the next line (a1 now points to next)
		beq		delend               * no -> end of program reached
del1:
		move.l	(a1),a1              * a1 = follow next-pointer to the next line
		bra		delLoop              * continue scanning
delend:
		rts


*==============================================================================
* ROUTINE: List (LIST command)
* Purpose: List program lines to the screen. Parses optional start,end range,
*          then calls listlines to iterate through the program and output
*          each line (line number + detokenized content).
* Syntax:  LIST [start][,end]
* Entry:   a0 = pointer into BASIC program text
*==============================================================================
* List command: LIST (n)(,)(n)
List:
		bsr		getoptparam          * parse optional start,end line numbers -> d6, d7
		move.l    a0,-(sp)             * save program text pointer
          move.l    prgbase,a0           * a0 = start of program (first line in linked list)
		clr.w	d0                   * d0 = 0: LIST mode (not scroll mode)
		bsr		listlines            * call the core listing routine
          bsr       new_line             * output a final newline after the listing
          move.l    (sp)+,a0             * restore program text pointer
          rts


*==============================================================================
* ROUTINE: tstlinenr
* Purpose: Validate that the line range parameters d6 and d7 are non-negative.
*          Called after getoptparam to catch negative line numbers.
* Entry:   d6 = start line number, d7 = end line number
* Exit:    Returns normally if both >= 0; jumps to negerr on error
*==============================================================================
tstlinenr:
		tst.l	d6                   * is start line number negative?
		bmi		negerr               * yes -> report "negative number" error
		tst.l	d7                   * is end line number negative?
		bmi		negerr               * yes -> report "negative number" error
		rts


*==============================================================================
* ROUTINE: getoptparam
* Purpose: Parse optional comma-separated start and end line number parameters
*          for LIST, DELETE, and similar commands.
*          Handles all forms: LIST / LIST n / LIST n,m / LIST ,m / LIST n,
* Entry:   a0 = pointer into BASIC program text
* Exit:    d6 = start line number (0 if omitted)
*          d7 = end line number ($7FFFFFFF if omitted, or = d6 if only one given)
* Uses:    get_ckterm to evaluate integer expressions
*          tst_komma to check for comma separator
*          chargot to peek at the next character
*==============================================================================
* -> d6/d7 = [...] line numbers
getoptparam:
          move.l    #$7fffffff,fac1      * default: no operand (sentinel value)
          move.w    #INT,typvalid        * expect integer type for line numbers
          bsr       get_ckterm           * try to evaluate first operand -> fac1
          cmp.l     #$7fffffff,fac1      * was a first operand found?
          bne       list1b               * yes -> process it
          bsr       tst_komma            * no operand -> check if there's a comma (e.g., LIST ,100)
          bne       list1d               * no comma either -> list entire program
          clr.l     fac1                 * comma found with no first operand -> start = 0
          bra       list1b               * proceed to parse second operand
list1d:   moveq     #0,d6                * no parameters at all: start = 0
          move.l    fac1,d7              * end = $7FFFFFFF (entire program)
          bra       list1c               * jump to validation
list1b:   move.l    fac1,-(sp)           * save first operand on stack
          move.l    #$7fffffff,fac1      * default for second operand = infinity
          bsr       chargot              * peek at next character without advancing
          beq       list1e               * NUL terminator -> no second operand
          cmp.b     #':',d0              * colon (statement separator)?
          beq       list1e               * yes -> no second operand
          move.w    #INT,typvalid        * expect integer for second operand
          bsr       get_ckterm           * evaluate second operand -> fac1
list1e:   move.l    (sp)+,d6             * d6 = start line (first operand)
          cmp.l     #$7fffffff,fac1      * was a second operand provided?
          bne       list1a               * yes -> use it as end line
          cmp.b     #',',-2(a0)          * check if a trailing comma was present (e.g., LIST 100,)
          beq       list1a               * yes -> end = $7FFFFFFF (infinity), which is already in fac1
          move.l    d6,fac1              * no comma -> single line number: end = start
list1a:   move.l    fac1,d7              * d7 = end line number
list1c:
		bra		tstlinenr            * validate both d6 and d7 are non-negative


*==============================================================================
* ROUTINE: listlines (Core listing loop)
* Purpose: Iterate through the program linked list and output each line whose
*          number falls within the range [d6..d7]. For each line, outputs the
*          line number (via ipka_ + putstrreverse) and then detokenizes the
*          tokenized content back into readable BASIC text.
*
* Detokenization algorithm:
*   - Scan bytes of the tokenized line data.
*   - If a byte is TOKEN1/TOKEN2/TOKEN3 ($01/$02/$03), it is a token intro byte.
*     The next byte is the token index. Use the intro byte to select the correct
*     tokenadr sub-table, then look up the keyword string at the token index.
*     Copy the keyword characters, converting lowercase to uppercase and stripping
*     bit7 (which marks characters past the minimum abbreviation point).
*   - If a byte is a normal character, copy it directly to the output buffer.
*
* Entry:   a0 = pointer to first line in linked list to examine
*          d0 = mode flag: 0 = LIST mode (outputs newlines), 1 = SCROLL mode (single line)
*          d6 = start line number
*          d7 = end line number
* Uses:    var2_name as output buffer for detokenized line text
*          ipka_ to convert line number to ASCII
*          putstrreverse to output the reversed number string
*          put_string to output the detokenized line text
*==============================================================================
* a0 points to first line
* d0 flag: LIST(0) or SCROLL(1)
* d6 is start line [
* d7 is end line ]
listfl:	.ds.w	1                    * storage for mode flag (LIST=0, SCROLL=1)
listlines:
		move.w	#1,ed_nlfl           * disable line-wrap in editor (1 = no wrapping)
		move.w	d0,listfl            * save mode flag

* --- Main listing loop: iterate over linked list ---
list1:
		tst.l     (a0)                * is next-pointer zero (end of program)?
          beq       listend              * yes -> listing complete
          move.l    (a0)+,a6             * a6 = next-line pointer; a0 advances past it
          move.l    (a0)+,d0             * d0 = line number; a0 now points to tokenized data
          cmp.l     d6,d0                * is line number >= start of requested range?
          blt       list3a               * no -> skip this line (jump to advance to next)
          cmp.l     d7,d0                * is line number > end of requested range?
          bhi       listend              * yes -> stop listing
          move.l    a0,-(sp)             * save pointer to tokenized data on stack

* --- Convert line number to ASCII and output it ---
          bsr       ipka_                * convert integer d0 to ASCII string at a2 (reversed)
		tst.w	listfl               * are we in SCROLL mode?
		bne		nonewline            * yes -> don't output newline before the line
          bsr       new_line             * LIST mode: output CR/newline to start a new line
nonewline:
          move.l    a2,a0                * a0 = pointer to reversed digit string
          subq.l    #1,a0                * skip the sign byte (ipka_ puts sign at end)
          bsr       putstrreverse        * output the line number (reversed string -> forward)

* --- Detokenize the tokenized line data ---
          move.l    (sp)+,a1             * a1 = pointer to tokenized data (restored from stack)
          lea       var2_name,a0         * a0 = output buffer for detokenized text
list4:
          cmp.l     a1,a6                * has a1 reached the end of this line (a6 = next line)?
          beq       list3                * yes -> output the completed line
		moveq.l	#0,d0                * clear d0 (ensure upper bytes are zero)
          move.b    (a1)+,d0             * d0 = next byte from tokenized data
          cmp.b     #TOKEN1,d0           * is it token class 1 intro byte ($01)?
          beq       list2                * yes -> handle token
		cmp.b	#TOKEN2,d0           * is it token class 2 intro byte ($02)?
		beq		list2                * yes -> handle token
		cmp.b	#TOKEN3,d0           * is it token class 3 intro byte ($03)?
		beq		list2                * yes -> handle token
          move.b    d0,(a0)+             * not a token -> copy literal character to output buffer
          bra       list4                * continue scanning

* --- Token detokenization ---
list2:    * Token processing: look up the keyword string and copy it to output
		move.w	d0,d1                * d1 = token class intro byte ($01/$02/$03)
		lsl.w	#2,d1                * d1 *= 4 (tokenadr is a .long table, 4 bytes per entry)
          move.b    (a1)+,d0             * d0 = token index byte (follows the intro byte)
          lsl.l     #2,d0                * d0 *= 4 (each keyword address is a .long)
		lea		tokenadr,a2          * a2 = base of token name address tables
          move.l    (a2,d1),a2           * a2 = pointer to the keyword table for this token class
          move.l    0(a2,d0),a2          * a2 = pointer to the actual keyword string

* --- Copy keyword characters to output, converting to uppercase ---
list2a:   move.b    (a2)+,d0             * d0 = next character of keyword string
		bclr		#7,d0                * clear bit 7 (abbreviation marker flag)
		cmp.b	#'a',d0              * is it a lowercase letter?
		bmi		list2aa              * no (less than 'a') -> copy as-is
		cmp.b	#'z'+1,d0            * is it past 'z'?
		bpl		list2aa              * yes -> copy as-is
		sub.b	#$20,d0              * convert lowercase to uppercase (ASCII difference = $20)
list2aa:
          move.b    d0,(a0)+             * store the (uppercased) character in output buffer
          tst.b     (a2)                 * is the next byte a NUL terminator?
          bne       list2a               * no -> continue copying keyword characters
          bra       list4                * keyword complete -> resume scanning tokenized data

* --- Output the detokenized line and advance to next ---
list3:    * Line complete: NUL-terminate the output buffer and display it
          clr.b     (a0)                 * NUL-terminate the detokenized string
          lea       var2_name,a0         * a0 = start of the output buffer
          bsr       put_string           * output the detokenized line to screen/file
list3a:   move.l    a6,a0                * a0 = next-line pointer (advance to next line)
		tst.w	listfl               * are we in SCROLL mode (single line)?
		bne		listend              * yes -> stop after one line
          bra       list1                * LIST mode -> continue with next line
listend:
		clr.w	ed_nlfl              * re-enable line wrapping in editor
		rts

*==============================================================================
* SECTION: DIM Command
*==============================================================================

*==============================================================================
* ROUTINE: Dim / DimA / Localdim
* Purpose: Implement the DIM statement for declaring arrays.
*          Parses the variable name, reads dimension sizes in parentheses
*          (up to 10 dimensions), and creates an array variable with the
*          ARRAYTYP ($8000) bit set in its type word. Allocates storage equal
*          to the product of all dimension sizes times the element size.
*
* Localdim: Variant used inside PROCedures. If the array already exists in
*           the current proc scope, verifies that the new dimensions match
*           the existing ones (same count and same sizes). If they don't match,
*           raises a "redefined" error.
*
* Syntax:  DIM varname(dim1[,dim2[,...dim10]])
* Entry:   a0 = pointer into BASIC program text (past the DIM token)
* Exit:    Array variable created in variable space
* Uses:    tst_var to parse variable name
*          create_var to allocate the variable (sets ARRAYTYP flag internally)
*          arraydeep = number of dimensions
*          arraylen = array of dimension sizes (up to 10 entries)
*==============================================================================
* DIM command
* Expects pointer past token in a0
dimtypext:	.ds.w	1              * type extension: 0 for global DIM, procnr for LOCAL DIM
dimcmpfl:		.ds.w	1          * flag: nonzero if local array already existed (need dim comparison)
dimcmpadr:	.ds.l	1              * pointer to existing array header (for dimension comparison)

Dim:
		clr.w	dimtypext            * global DIM: type extension = 0
		bra		DimA                 * continue with common DIM logic

*==============================================================================
* ROUTINE: Localdim (LOCAL DIM variant)
* Purpose: DIM inside a PROC. Sets dimtypext to procnr so create_var marks
*          the variable as local to the current procedure scope.
*==============================================================================
Localdim:
		move.w	procnr,dimtypext     * set type extension to current procedure number

* --- Common DIM logic ---
DimA:
		clr.w	dimcmpfl             * clear "comparison needed" flag
          bsr       tst_var              * parse variable name, check if it exists -> d0, a1
          bsr       tstsysvar            * ensure it's not a read-only system variable
          move.w    typflag,-(sp)        * save the variable's type on the stack
		tst.w	dimtypext            * is this a local DIM (inside a PROC)?
		beq		hauptdim             * no -> standard (global) DIM processing
		tst.w	d0                   * local DIM: does this variable already exist?
		bpl		ldimok               * d0 >= 0 means new variable (not yet defined) -> ok
		addq.w	#1,dimcmpfl          * variable exists -> set flag to compare dimensions later
		move.l	a1,dimcmpadr         * save pointer to existing array header for comparison
		bra		ldimok               * proceed (don't error on redefinition yet)

* --- Global DIM: error if variable already exists ---
hauptdim:
          tst.w     d0                   * does the variable already exist?
          bne       redef                * yes -> "redefined variable" error
ldimok:
          bsr       save_vname           * save the variable name for later use by create_var
          lea       arraylen,a4          * a4 = pointer to dimension size storage array
          clr.l     arraydeep            * arraydeep = 0 (dimension counter)
          bra       dim1a                * enter dimension parsing loop (skip comma check first time)

* --- Parse each dimension size ---
dim1:
          bsr       chk_komma            * require and consume a comma separator between dimensions
dim1a:    addq.l    #1,arraydeep         * increment dimension counter
          move.l    a4,-(sp)             * save arraylen pointer across expression evaluation
          bsr       get_aterm            * evaluate dimension size expression -> fac1
          move.l    (sp)+,a4             * restore arraylen pointer
          cmp.l     #11,arraydeep        * have we reached 11 dimensions (max is 10)?
          beq       dimerr               * yes -> "too many dimensions" error
          move.l    fac1,d0              * d0 = dimension size
		bmi		negdimerr            * negative dimension size -> error
		move.l	d0,(a4)+             * store dimension size in arraylen array; advance pointer
          bsr       chargot              * peek at next character
          cmp.b     #')',d0              * closing parenthesis (end of dimension list)?
          bne.s     dim1                 * no -> parse another dimension (expects comma next)

* --- For LOCAL DIM: verify dimensions match existing array if it was redefined ---
		tst.w	dimcmpfl             * was this a local redefinition that needs comparison?
		beq		nolocredef           * no -> skip dimension verification
		move.l	dimcmpadr,a5         * a5 = pointer to existing array header to compare
		move.l	arraydeep,d0         * d0 = number of dimensions we just parsed
		cmp.l	(a5)+,d0             * does dimension count match existing array?
		bne		redef                * no -> "redefined" error (mismatched dimensions)
		lea		arraylen,a4          * a4 = our newly parsed dimension sizes
tstlocredef:
		move.l	(a4)+,d1             * d1 = newly parsed dimension size
		addq.l	#1,d1                * add 1 (dimension stored as size+1 in variable storage)
		cmp.l	(a5)+,d1             * does it match the existing dimension?
		bne		redef                * no -> "redefined" error
		subq.l	#1,d0                * decrement dimension counter
		bne		tstlocredef          * more dimensions to check -> loop

* --- Create the array variable ---
nolocredef:
          bsr       load_vname           * restore the saved variable name
          move.w    (sp)+,d0             * d0 = variable type (from stack, saved earlier)
		or.w		dimtypext,d0         * OR in proc number (0 for global, procnr for local)
		move.w	d0,typvalid          * set as the type for create_var
          bsr       create_var           * create the array variable in variable storage
          bsr       charget              * get next character after closing parenthesis
          cmp.b     #',',d0              * comma? -> another array declaration follows (DIM a(5),b(3))
          beq       DimA                 * yes -> parse the next array declaration
          rts                            * done

*==============================================================================
* SECTION: PRINT Command
*==============================================================================

*==============================================================================
* ROUTINE: Print
* Purpose: Implement the PRINT statement. Handles optional file output via
*          #handle prefix, evaluates and outputs expressions (string, integer,
*          or float), and processes format separators:
*            ;  = concatenate (no separator between items)
*            ,  = advance to next tab stop
*            end of statement = output newline
*          Also handles TAB(), SPC(), and EDTAB() functions within PRINT.
*
* Syntax:  PRINT [#handle,] [expr [{;|,} expr]...]
* Entry:   a0 = pointer into BASIC program text (past the PRINT token)
* Uses:    filefl/handle for file output redirection
*          ipka_ for integer-to-ASCII conversion
*          rpka_ for float-to-ASCII conversion
*          putstrreverse for reversed-string output
*          tab_ for tab stop advancement
*==============================================================================
* PRINT command
* Expects pointer past token in a0
Print:
          bsr       clrfilefl            * default: no file output (clear filefl and handle)
          move.l    a0,work2             * save program text pointer in work2
          bsr       charget              * get next character
          cmp.b     #'#',d0              * is it '#'? (PRINT #handle,...)
          bne       Print1               * no -> normal screen output

* --- File output: parse file handle ---
          bsr       get_handle           * parse and resolve the logical file handle
          move.w    #-1,filefl           * set filefl = -1 (output directed to file)
          bsr       chk_komma            * require and consume comma after handle
          bra       Print1a              * continue to expression evaluation

* --- Normal PRINT (no file handle) ---
Print1:   move.l    work2,a0             * restore program text pointer (charget advanced it)

* --- Main PRINT expression loop ---
Print1a:  move.l    a0,work2             * save current position
          bsr       charget              * peek at next character
          cmp.b     #TOKEN1,d0           * is it a token class 1 intro byte?
          bne       Print1aa             * no -> evaluate as general expression

* --- Check for special PRINT functions (TAB, SPC, EDTAB) ---
          lsl.w     #8,d0                * shift intro byte to high byte of d0.w
          move.b    (a0),d0              * d0.w = full 16-bit token ID (intro << 8 | index)
          cmp.w     #TAB,d0              * is it the TAB() function?
          bne       Print1ab             * no -> check SPC

* --- Handle TAB() / SPC() / EDTAB() ---
Printfkt: subq.l    #1,a0                * back up: point a0 to the token intro byte
          bsr       get_fkt              * execute the TAB/SPC/EDTAB function
          bsr       charget              * get next character after function call
          bra       print2               * jump to separator handling

Print1ab: cmp.w     #SPC,d0              * is it the SPC() function?
          beq       Printfkt             * yes -> handle it
		cmp.w	#EDTAB,d0            * is it the EDTAB() function?
		beq		Printfkt             * yes -> handle it

* --- Evaluate a general expression ---
Print1aa: move.l    work2,a0             * restore program text pointer
          move.w    #STRING,typvalid     * allow STRING, FLOAT, and INT results
          bsr       gets_term            * evaluate the expression -> result in fac1/str_ptr
          move.l    a0,a6                * a6 = save updated program pointer
          move.w    typ2flag,d0          * d0 = actual result type of the expression
          beq       print2               * type = 0 means no expression found -> check separator
          cmp.w     #FLOAT,d0            * is the result a float?
          beq       printfl              * yes -> format and print float
          cmp.w     #INT,d0              * is the result an integer?
          beq       printint             * yes -> format and print integer

* --- Print a string value ---
printstr:
          move.l    str_ptr,a0           * a0 = pointer to the string to output (stored backwards)
          bra       print1               * jump to output routine

* --- Print an integer value ---
printint:
          move.l    fac1,d0              * d0 = integer value
          bsr       ipka_                * convert to ASCII string at a2 (stored in reverse)
          bra       print1a              * jump to add leading space and output

* --- Print a float value ---
printfl:
          movem.l   fac1,d0-d3           * load all 4 longwords of BCD float into d0-d3
          bsr       rpka_                * convert float to ASCII string at a2 (stored in reverse)

* --- Add leading space for positive numbers and output ---
print1a:  move.b    #' ',1(a2)           * place a space before the number (positive numbers get a
          addq.l    #1,a2                *   leading space; negative numbers have '-' already)
          move.l    a2,a0                * a0 = pointer to the reversed output string
print1:
          bsr       putstrreverse        * output the reversed string (displays it forward)

* --- Handle format separators after the printed expression ---
          move.l    a6,a0                * a0 = restore program text pointer
print2:   bsr       tst_komma            * is the next character a comma?
          bne       print2a              * no -> check for semicolon
          bsr       tab_                 * comma found: advance cursor to next tab stop
          bra       Print2               * then evaluate the next expression

* --- Check for semicolon ---
print2a:
          cmp.b     #';',d0              * is it a semicolon?
          beq       Print2               * yes -> concatenate (no spacing), evaluate next expression

* --- End of PRINT statement: output newline ---
print2b:  bsr       new_line             * no more separators -> output CR/newline
printend: bra       clrfilefl            * clear file output flag and return

* --- Check if more arguments follow ---
Print2:   bsr       tstnxtarg            * test if another argument exists after separator
          beq       Print1a              * yes (not end of statement) -> loop to evaluate next expr
          bsr       clrfilefl            * no more arguments -> clear file output flag
          bra       charget              * advance pointer past ':' or NUL terminator and return

*==============================================================================
* SECTION: Expression Evaluator - Term Fetching, Type Conversion,
*          Core Evaluation Loop, Element Dispatch, and String Operations
*==============================================================================
*
* This is the HEART of the expression evaluator and operator-precedence
* climbing parser. It contains:
*
*   1. Helper term-fetching wrappers (get_aterm, gets_term, get_ckterm,
*      get_defterm, get_term) that set up context and call get1_term.
*   2. Type conversion helpers (konvint, konvfl, konvstr) to coerce the
*      result of an expression to the type expected by typvalid.
*   3. get1_term / get3_term - the core recursive-descent evaluation loop
*      with operator-precedence climbing.
*   4. get_element - element dispatch (parenthesized subexpressions,
*      variables, constants, functions).
*   5. String handling (get_str, resv_str, copy_str, copy2_str) including
*      forward copy for string constants and backward copy for string
*      variables (since strings are stored reversed in memory).
*   6. get_var_konst - variable/constant dispatch by first character,
*      with unary minus handling.
*
* Key data structures:
*   fac1/fac2  - 16-byte (4 longword) float accumulators. For INT, only
*                the first longword is used.
*   typ2flag   - type of the first operand at current expression level
*   typflag    - type of the most recently fetched element
*   typvalid   - expected/required result type for the current context
*   operator   - current operator number (1-13)
*   optabl     - jump table of 13 operation routines
*   oppriotabl - priority table (1=lowest for ShL, 13=highest for Exponent)
*==============================================================================

*==============================================================================
* get_aterm - Get Array Term (preserving array context)
*==============================================================================
* Purpose: Evaluate an expression as INT, while saving and restoring all
*          array-related state (arrayfl, arraylen, arraydeep). Used when
*          parsing array subscript expressions so nested array accesses
*          don't corrupt the outer array's dimensions.
*
* Parameters:
*   A0 = pointer to term in tokenized source
*   A2 = pointer to possible assignment string name (or 0)
*
* Returns:
*   fac1 = integer result of the evaluated expression
*   Array state fully restored
*==============================================================================
get_aterm:     * get array term (save important vars)
          move.w    arrayfl,-(sp)
          movem.l   arraylen,d0-d7/a5-a6     * save array data onto stack!
          movem.l   d0-d7/a5-a6,-(sp)
          move.l    arraydeep,-(sp)
          move.l    str_ptr,spstr
          bsr       onqlist             * push str_ptr onto protection stack
          move.w    #INT,typvalid       * we need an INT result in fac1
          bsr       get_term            * evaluate the expression
          bsr       offqlist            * pop str_ptr from protection stack
          move.l    spstr,str_ptr
          move.l    (sp)+,arraydeep
          movem.l   (sp)+,d0-d7/a5-a6
          movem.l   d0-d7/a5-a6,arraylen
          move.w    (sp)+,arrayfl
          rts

*==============================================================================
* gets_term - Get String-safe Term (no new string creation)
*==============================================================================
* Purpose: Evaluate an expression while protecting the current string space.
*          After evaluation, strend is restored so that any strings created
*          during the evaluation are discarded. Used when the caller only
*          needs the expression value, not any string side effects.
*
* Parameters:
*   A0 = pointer to term in tokenized source
*
* Returns:
*   Result in fac1/d0-d3, strend restored to pre-call value
*==============================================================================
gets_term:
          move.l    strend,spstr        * strings must not be permanently created
          bsr       onqlist             * protect current str_ptr
          bsr       get1_term           * evaluate any expression
          bsr       offqlist            * restore str_ptr
          move.l    spstr,strend        * discard any newly created strings
          rts

*==============================================================================
* get_ckterm - Check-then-Evaluate Term
*==============================================================================
* Purpose: First checks whether there is actually an expression to parse.
*          If the next character is NUL, comma, or colon, returns immediately
*          (no expression). Otherwise backs up and calls get_term normally.
*          Used for optional expression arguments.
*
* Parameters:
*   A0 = pointer into tokenized source (before charget)
*
* Returns:
*   If no expression: returns via ckt2 (rts)
*   Otherwise: falls through to get_term
*==============================================================================
ckt2:     rts                             * early return: no expression found
get_ckterm:
          bsr       charget             * fetch next character
          beq       ckt2                * NUL code -> no expression, return
          cmp.b     #',',d0
          beq       ckt2                * comma -> no expression, return
          cmp.b     #':',d0
          beq       ckt2                * colon -> no expression, return
          lea       -1(a0),a0           * back up: let get_term re-read this char
          bra       get_term

*==============================================================================
* get_defterm - Get Term for Function Definitions
*==============================================================================
* Purpose: Evaluate a term for use in DEF FN bodies. Calls get1_term directly
*          (without the onqlist/offqlist string protection) and then falls
*          through to get_1 for type conversion.
*
* Returns:
*   float -> fac1, int -> fac1, string -> str_ptr
*==============================================================================
get_defterm:        * important for string definitions
          bsr       get1_term           * evaluate expression
          bra       get_1               * skip to type conversion logic

*==============================================================================
* get_term - Main Term Evaluation Entry Point
*==============================================================================
* Purpose: The primary entry point for expression evaluation. Protects the
*          string space with onqlist/offqlist, evaluates the expression via
*          get1_term, then converts the result to match typvalid.
*
* Parameters:
*   A0 = pointer to term in tokenized source
*   typvalid = required result type (FLOAT, INT, or STRING)
*
* Returns:
*   fac1 = result (float or int)
*   str_ptr/strend = string result (if STRING)
*   typ2flag = set to typvalid on success
*==============================================================================
get_term:
          move.l    strend,spstr
          bsr       onqlist             * protect current str_ptr on stack
          bsr       get1_term           * evaluate the full expression
          bsr       offqlist            * restore str_ptr
          move.l    spstr,strend        * discard temporary strings

* --- get_1: Type conversion to match typvalid ---
get_1:    move.w    typ2flag,d0         * d0 = actual result type
          beq       get_t2              * no expression found? just return
          move.w    typvalid,d1         * d1 = expected/required type
          cmp.w     d0,d1
          beq       get_t1              * types already match -> done
          cmp.w     #FLOAT,d1           * caller wants FLOAT?
          beq       konvfl
          cmp.w     #INT,d1             * caller wants INT?
          beq       konvint

*==============================================================================
* konvstr - String Type Validation
*==============================================================================
* Purpose: If typvalid is STRING, verify the result is STRING. Float and
*          int cannot be converted to string implicitly -> type mismatch.
*==============================================================================
konvstr:
          cmp.w     #STRING,d0          * float and int cannot be converted here
          bne       typemis             * not STRING -> type mismatch error
          beq       get_t1              * is STRING -> success

*==============================================================================
* konvint - Convert FLOAT Result to INT
*==============================================================================
* Purpose: Convert a floating-point result in fac1 to integer format.
*          Only FLOAT can be converted to INT; STRING causes type mismatch.
*
* Uses: rpkl (BLIBF.S) - float to packed long integer conversion
*==============================================================================
konvint:
          cmp.w     #FLOAT,d0
          bne       typemis             * only FLOAT can become INT
          movem.l   fac1,d0-d3          * load float value from fac1
          bsr       rpkl                * convert float (d0-d3) to int (d0)
          move.l    d0,fac1             * store integer result in fac1
          bra       get_t1

*==============================================================================
* konvfl - Convert INT Result to FLOAT
*==============================================================================
* Purpose: Convert an integer result in fac1 to floating-point format.
*          Only INT can be converted to FLOAT; STRING causes type mismatch.
*
* Uses: ltor_ (BLIBF.S) - long integer (d4) to float (d0-d3) conversion
*==============================================================================
konvfl:
          cmp.w     #INT,d0
          bne       typemis             * strings cannot become floats
          move.l    fac1,d4             * d4 = integer value for ltor_
          bsr       ltor_               * convert int to float -> d0-d3
          movem.l   d0-d3,fac1          * store float result in fac1

get_t1:   move.w    typvalid,typ2flag   * set result type to expected type
get_t2:   rts

*==============================================================================
* get1_term - Core Expression Evaluation Loop
*==============================================================================
* Purpose: The heart of the recursive-descent expression parser with
*          operator-precedence climbing. Evaluates an arbitrary expression
*          and returns the result in fac1 with the type in typ2flag.
*
* Algorithm:
*   1. Initialize fac1 to zero, clear type flags
*   2. get3_term: fetch first element via get_element
*   3. Store element in fac1 (if numeric), set typ2flag
*   4. Look for an operator via get_operator
*   5. If string type: handle '+' for concatenation or comparison operators
*   6. get2_term: fetch second operand via get_element
*   7. Type-coerce both operands (promote INT to FLOAT if mixed)
*   8. to_next_op: if next operator has HIGHER priority than current,
*      push current state to stack, recurse into get2_term
*   9. exec_operation: dispatch via optabl jump table
*  10. Loop back to check for more operators
*
* Parameters:
*   A0 = pointer into tokenized source
*
* Returns:
*   fac1 = result value
*   d0-d3 = copy of fac1
*   typ2flag = result type (FLOAT, INT, or STRING)
*==============================================================================
get1_term:
          clr.w     typ2flag            * clear result type (no expression yet)
          clr.w     typflag             * clear element type
          clr.l     work1               * clear string comparison base pointer
          movem.l   zero_,d0-d3         * load 12 bytes of zeros
          movem.l   d0-d3,fac1          * initialize fac1 to zero

* --- get3_term: Fetch first element and enter operator loop ---
get3_term:
          bsr       get_element         * fetch an element (atom)
          beq       gtend               * no expression found -> return
          move.w    typflag,d7          * d7 = type of fetched element
          move.w    d7,typ2flag         * remember as first operand type
          cmp.w     #STRING,d7
          beq.s     no_numeric          * strings already handled, skip fac1 store
          movem.l   d0-d3,fac1          * store numeric value (float/int) in fac1

* --- no_numeric: Look for operator after element ---
no_numeric:
          bsr       get_operator        * look for operator -> d0 = operator number
          beq       gtend               * no operator found -> end of expression
          move.w    d0,operator         * save operator number
          cmp.w     #STRING,typflag
          bne       get2_term           * numeric -> proceed to get second operand

* --- String operator handling ---
* For strings, only '+' (concatenation) and comparison operators are valid.
* Comparison operators set follchar to the second character (e.g., '=' in '<=').
          clr.l     work1               * clear string comparison pointer
          tst.b     follchar            * was follchar set? (comparison op: =,<,>)
          beq       gt6                 * no -> check for '+'
          move.l    strend,work1        * save strend for later string comparison
          bra       get2_term           * proceed to get second operand

* --- gt6: For strings, only '+' continues; anything else ends expression ---
gt6:      bsr       chargot             * re-read current character
          cmp.b     #'+',d0             * is it '+' (string concatenation)?
          beq       get2_term           * yes -> get second string operand
          subq.l    #1,a0               * back up: this char is not part of expr
          bra       gtend               * end of string expression

*==============================================================================
* get2_term - Get Second Operand and Process
*==============================================================================
* Purpose: Fetch the second operand of a binary operation. Saves the current
*          operator context (follchar, operator, typ2flag) on the stack,
*          gets the next element, then restores context and processes the
*          operation. This is the main continuation point for the operator
*          precedence climbing algorithm.
*==============================================================================
get2_term:
          move.l    work1,spstr         * save string comparison pointer
          bsr       onqlist             * protect current str_ptr
          move.w    follchar,-(sp)      * save follchar (destroyed by get_element)
          move.w    operator,-(sp)      * save current operator
          move.w    typ2flag,-(sp)      * save first operand type
          bsr       get_element         * fetch second element (atom)
          beq       syntaxerr           * no element after operator -> syntax error!
          move.w    (sp)+,typ2flag      * restore first operand type
          move.w    (sp)+,operator      * restore operator
          move.w    (sp)+,follchar      * restore follchar
          bsr       offqlist            * restore str_ptr
          move.l    spstr,work1         * restore string comparison pointer
          move.w    typflag,d7          * d7 = type of second element
          cmp.w     #STRING,d7          * is second operand a string?
          bne       gt5                 * no -> numeric processing

* --- String processing after second operand ---
* If both operands are strings and work1 is not set, this is concatenation.
* If work1 is set, this is a string comparison operation.
          move.w    typ2flag,d6         * d6 = first operand type
          move.w    d7,typ2flag         * update typ2flag to string
          cmp.w     d6,d7               * e.g. a$<b$+5 -> type mismatch
          bne       typemis             * mixed string/numeric -> error
          tst.l     work1               * is work1 set? (comparison pending)
          beq       no_numeric          * no -> concatenation, loop for more ops

* --- String comparison: collect second string complex, then compare ---
          move.w    follchar,-(sp)      * save follchar
          move.l    work1,spstr         * save comparison base
          bsr       onqlist             * protect str_ptr
          move.w    operator,-(sp)      * save operator
          bsr       no_numeric          * recursively collect second string complex
          move.w    (sp)+,operator      * restore operator
          bsr       offqlist            * restore str_ptr
          move.l    spstr,work1         * restore comparison base
          move.w    (sp)+,follchar      * restore follchar
          tst.w     workop              * was there a pending operator?
          bne       gt5d                * yes -> don't back up
          subq.l    #1,a0               * back up one character

* --- gt5d: Execute string comparison and check for further operators ---
gt5d:     cmp.w     #STRING,typvalid    * is caller expecting STRING?
          bne       gt5a                * no -> use typvalid as result type
          move.w    #INT,d7             * comparison result is always INT
          bra       gt5b
gt5a:     move.w    typvalid,d7         * use caller's expected type
gt5b:     move.w    d7,typ3flag         * will be copied to typ2flag after compare
          bsr       exec_operation      * execute the string comparison
          movem.l   d0-d3,-(sp)         * save comparison result
          move.l    a0,a6               * save source pointer
          bsr       get_operator        * look for another operator
          bne       gt5e                * found one -> continue with more operations

* --- No more operators after string comparison ---
          movem.l   (sp)+,d0-d3         * restore comparison result
          movem.l   d0-d3,fac1          * store in fac1
          bra       gtend2              * return (skip fac1->d0-d3 copy)

* --- gt5e: More operators follow the string comparison result ---
gt5e:     move.w    d0,-(sp)            * save new operator
          move.w    typvalid,-(sp)      * save original typvalid
          move.w    typ2flag,typvalid   * set typvalid to current result type
          bsr       get_term            * evaluate the rest of the expression
          move.w    typ2flag,d0
          cmp.w     typvalid,d0         * verify at least 1 element was found
          bne       typemis             * type mismatch
          move.w    (sp)+,typvalid      * restore original typvalid
          move.w    (sp)+,operator      * restore operator
          movem.l   (sp)+,d0-d3         * old result -> fac2, new result in fac1
          movem.l   d0-d3,fac2
          bsr       exec_operation      * execute the deferred operation
          movem.l   d0-d3,fac1          * store final result
          bra       gtend2              * return

*==============================================================================
* gt5 - Numeric (INT/FLOAT) Processing After Second Operand
*==============================================================================
* Purpose: Handle the case where the second operand is numeric. Checks for
*          type compatibility, stores fac2, then looks ahead for the next
*          operator to determine if precedence climbing is needed.
*==============================================================================
gt5:
	cmp.w	#STRING,typ2flag	* string and int/float don't mix!
	beq		typemis             * first was STRING, second numeric -> error
	movem.l	d0-d3,fac2		* store second operand in fac2
          move.l    a0,a6               * save current source address
          move.w    follchar,-(sp)      * save follchar for possible comparison op
          bsr       get_operator        * look ahead for next operator
          beq       gt4                 * no more operators -> execute current op

* --- Operator Precedence Comparison ---
* get_operator returns the operator's priority-encoded number in d0.
* We compare it against the current operator. If the NEW operator has
* STRICTLY HIGHER priority (bhi = unsigned higher), the current operation
* must be deferred and we recurse into to_next_op.
* Example: for "2 + 3 * 4", when processing '+' and we see '*',
* '*' has higher priority so we defer '+' and handle '*' first.
          cmp.w     operator,d0         * compare priorities: new vs current
          bhi       to_next_op          * new op higher priority -> recurse deeper

* --- gt4: Execute current operation (no higher-priority op ahead) ---
gt4:      move.l    a6,a0               * restore source pointer (back up past op)
          move.w    (sp)+,follchar      * restore follchar

* --- gt7: Type coercion and operation execution ---
* Before executing the operation, both operands must have the same type.
* If one is INT and the other FLOAT, promote the INT to FLOAT via ltor_.
gt7:
	move.w	typflag,d7		* d7 = type of second operand
          cmp.w     #FLOAT,d7           * is second operand FLOAT?
          beq       gt2                 * yes -> check if first needs promotion

* --- Second operand is INT ---
          cmp.w     typ2flag,d7         * compare: first type == second type?
          beq       no2_numeric         * both INT -> proceed directly
          move.l    fac2,d4			* first is FLOAT, second is INT -> promote fac2
          bsr       ltor_               * convert int (d4) to float (d0-d3)
          movem.l   d0-d3,fac2          * store promoted FLOAT in fac2
          bra       no2a                * set type to FLOAT

* --- gt2: Second operand is FLOAT, check first ---
gt2:
          cmp.w     typ2flag,d7         * first type == FLOAT too?
          beq       no2_numeric         * both FLOAT -> proceed directly
          move.l    fac1,d4             * first operand is INT -> promote fac1
          bsr       ltor_               * convert int to float
          movem.l   d0-d3,fac1          * store promoted FLOAT in fac1

no2a:     move.w    #FLOAT,d7           * result type is now FLOAT

* --- no2_numeric: Execute the operation ---
no2_numeric:
	move.w	d7,typflag          * set current element type
	move.w	d7,typ2flag         * set first-operand type (for next iteration)
	bsr       exec_operation      * dispatch operation via jump table
          bra       no_numeric          * loop back to check for more operators


*==============================================================================
* to_next_op - Operator Precedence Climbing (Higher Priority Detected)
*==============================================================================
* Purpose: Implements the critical operator-precedence climbing algorithm.
*          When a higher-priority operator is found ahead, the current
*          (lower-priority) operation is deferred by pushing its state
*          onto the CPU stack. The second operand (fac2) becomes the new
*          first operand (fac1), and the higher-priority operator becomes
*          the current operator. We then recurse into get2_term to fetch
*          and process the higher-priority sub-expression.
*
*          After get2_term returns, the result is in fac1. We then:
*          - Move fac1 -> fac2 (it's the RHS of the deferred operation)
*          - Pop the saved fac1 (original LHS) and operator from the stack
*          - Continue at gt7 to type-coerce and execute the deferred op
*
* Example: Parsing "2 + 3 * 4 - 1"
*   1. fac1=2, operator='+' (priority 9), fac2=3
*   2. Look ahead: '*' has priority 11 > 9 -> enter to_next_op
*   3. Push fac1=2 and operator='+' onto stack
*   4. fac1=3, operator='*', call get2_term -> fetches 4
*   5. get2_term sees '-' (priority 10 < 11) -> executes 3*4=12 in fac1
*   6. Pop: fac2=12, fac1=2, operator='+'
*   7. Execute 2+12=14, then continue with '-' operator
*==============================================================================
to_next_op:
	move.w	typ2flag,-(sp)		* save first operand type
          movem.l   fac1,d1-d4
          movem.l   d1-d4,-(sp)         * push first operand (fac1) onto stack
          move.w    operator,-(sp)      * push current (lower-priority) operator
          movem.l   fac2,d1-d4
          movem.l   d1-d4,fac1          * second operand becomes new first operand
          move.w    d0,operator         * higher-priority op becomes current
	move.w	typflag,typ2flag	* second operand's type becomes first's type
          bsr       get2_term           * recurse: evaluate higher-priority subexpr
          movem.l   fac1,d1-d4
          movem.l   d1-d4,fac2          * result of recursion -> fac2 (RHS)
          move.w    (sp)+,operator      * pop deferred operator
          movem.l   (sp)+,d1-d4
          movem.l   d1-d4,fac1          * pop deferred first operand -> fac1 (LHS)
	move.w	(sp)+,typ2flag      * pop deferred first operand type
          move.w    (sp)+,follchar      * restore follchar
          subq.l    #1,a0               * back up past the operator we peeked at
          bra       gt7                 * go to type coercion and execute deferred op

*==============================================================================
* exec_operation - Dispatch Operation via Jump Table
*==============================================================================
* Purpose: Execute the arithmetic/logical/comparison operation indicated by
*          the 'operator' variable. The operator number (1-13) is converted
*          to an index into optabl (a table of 13 longword routine addresses).
*          Registers d0-d3 are loaded from fac1, d4-d7 from fac2, and the
*          operation routine is called. The result is returned in d0-d3
*          and stored back to fac1.
*
* Operators (1-13):
*   1=ShL, 2=ShR, 3=Xor, 4=And, 5=Or, 6=Lower, 7=Equal, 8=Higher,
*   9=Add, 10=Sub, 11=Mul, 12=Div, 13=Exponent
*
* The EQ flag from typ2flag comparison with FLOAT is passed through to the
* operation routine, so it can determine whether to use float or int logic.
*==============================================================================
exec_operation:
          move.w    operator,d0         * d0 = operator number (1-13)
          sub.w     #1,d0               * make zero-based
          lsl.w     #2,d0               * multiply by 4 (longword offset)
          lea       optabl,a1           * a1 = base of operation jump table
          move.l    0(a1,d0),a1         * a1 = address of operation routine
          movem.l   a0-a6,-(sp)         * save all important address registers
          cmp.w     #FLOAT,typ2flag     * set EQ flag if operands are FLOAT
          movem.l   fac1,d0-d3          * d0-d3 = first operand (fac1)
          movem.l   fac2,d4-d7          * d4-d7 = second operand (fac2)
          jsr       (a1)                * call the operation routine
          movem.l   (sp)+,a0-a6         * restore address registers
          movem.l   d0-d3,fac1          * store result (int or float) back to fac1
          rts

* --- gtend: Normal expression end - load fac1 into d0-d3 for caller ---
gtend:    movem.l   fac1,d0-d3          * after ')' the value is expected in d0-d3
gtend2:   rts                             * also used as direct return (fac1 already set)

*==============================================================================
* get_element - Element Dispatch (Atoms and Parenthesized Subexpressions)
*==============================================================================
* Purpose: Fetch a single element (atom) of an expression. An element can be:
*   - A parenthesized subexpression: '(' triggers recursive get3_term
*   - A variable, constant, or function call: dispatched via get_var_konst
*   - End of expression: NUL, ':', ',', ';' return with BEQ set
*
* Parameters:
*   A0 = pointer into tokenized source
*
* Returns:
*   d0-d3 = value (if numeric)
*   typflag = type of element
*   BEQ set if no element found (end condition)
*   BNE set if element was successfully fetched
*==============================================================================
get_element:
          bsr       charget             * fetch next character, skip spaces
          beq       ge2                 * NUL -> end of line, no element
          cmp.b     #':',d0             * termination conditions
          beq       ge2                 * colon -> statement separator, no element
          cmp.b     #',',d0
          beq       ge2                 * comma -> argument separator, no element
          cmp.b     #';',d0
          beq       ge2                 * semicolon -> print separator, no element
          cmp.b     #'(',d0             * opening parenthesis marks subexpression
          bne       ge1                 * not '(' -> try variable/constant

* --- get_klammerarg: Parenthesized subexpression handler ---
* Recursively evaluates the expression inside parentheses by calling
* get3_term. Saves/restores fac1 and operator across the recursion.
* After get3_term returns, expects a closing ')' via chk_klammer.
get_klammerarg
          movem.l   fac1,d0-d3          * save current fac1
          movem.l   d0-d3,-(sp)
          move.w    operator,-(sp)      * save current operator
          bsr       get3_term           * recursively evaluate subexpression
          move.w    d0,d7               * save subexpression result type
          bsr       chk_klammer         * verify and consume closing ')'
          move.w    d7,d0               * restore result type
          move.w    (sp)+,operator      * restore outer operator
          movem.l   (sp)+,d4-d7
          movem.l   d4-d7,fac1          * restore outer fac1
          moveq     #1,d7               * clear BEQ flag (element was found)
          rts

* --- ge1: Not a parenthesis - try variable/constant/function ---
ge1:
          move.w    typflag,d7          * save current typflag
          bsr       get_var_konst       * dispatch to variable/constant handler
          cmp.w     #STRING,typflag     * is the result a string?
          beq       get_str             * yes -> handle string element
ge2:      rts                             * return (BEQ set if no element)

*==============================================================================
* get_str - Handle String Element
*==============================================================================
* Purpose: Process a string element. If this is the first string in the
*          expression (typ2flag != STRING), allocate fresh string space
*          via resv_str. If a string was already started (typ2flag == STRING),
*          concatenate by copying into existing space via copy_str.
*
* Parameters:
*   A1 = pointer to string data
*   A2 = pointer to position in source (for string constant quote handling)
*   d1 = character before string data (e.g., $22 for quote)
*
* Returns:
*   d1 = 1 (BNE set, indicating element was found)
*==============================================================================
get_str:
          move.b    -(a2),d1            * read char before string (quote for consts)
          clr.b     (a2)                * temporarily null-terminate
          move.w    typflag,d7
          cmp.w     typ2flag,d7         * was there already a string type before?
          beq       gs1                 * yes -> just copy/concatenate
          bsr       resv_str            * no -> reserve new string space
          bra       gs2
gs1:      bsr       copy_str            * concatenate to existing string
gs2:      move.b    d1,(a2)+            * restore the original character
          moveq     #1,d1               * BNE -> element found!
          rts

*==============================================================================
* resv_str - Reserve String Space
*==============================================================================
* Purpose: Initialize the string pointer for a new string. Sets str_ptr to
*          the current strend (the bottom of free string space). Sets bit 0
*          of d7 as a flag to indicate this is a fresh reservation (used by
*          copy2_str to skip the empty-string check).
*==============================================================================
resv_str:
          move.l    strend,str_ptr      * point str_ptr to free string space
          bset      #0,d7               * set flag: this is a reservation, not append
          bra       copy2_str           * fall through to copy the string data

*==============================================================================
* copy_str / copy2_str - Copy String Data Into String Space
*==============================================================================
* Purpose: Copy string data into the string heap. Handles two cases:
*
*   1. String CONSTANTS (d1 = $22, quote character):
*      Stored forward in the source. Copied forward from a1 until NUL.
*      The string grows downward in memory (stored at decreasing addresses).
*
*   2. String VARIABLES (d1 != $22):
*      Variable strings are stored BACKWARDS in memory (a convention of this
*      BASIC interpreter where strings grow downward from strend). The copy
*      starts at a1+1 and moves backward (decrementing) until NUL is found.
*
*   In both cases, the string is written into the heap at strend, growing
*   downward. If insufficient space exists, garbage collection is triggered.
*
* Parameters:
*   A1 = pointer to string source data
*   d1 = type indicator ($22 = constant, other = variable)
*   d7 bit 0 = 1 if resv_str (fresh allocation), 0 if concatenation
*
* Returns:
*   strend updated to new bottom of string data
*==============================================================================
copy_str:
          bclr      #0,d7               * clear resv_str flag (this is concatenation)

copy2_str:
          cmp.b     #$22,d1             * is it a string constant (quote char)?
          bne       warstring           * no -> it's a string variable

* --- String constant: measure length by scanning forward for NUL ---
          move.l    a1,a4               * a4 = start of string constant
ll5:
          tst.b     (a4)+               * scan forward for NUL terminator
          bne       ll5
          sub.l     a1,a4               * a4 = length + 1 (includes NUL)
          bra       ll6                 * proceed to space check and copy

* --- String variable: measure length by scanning backward for NUL ---
* String variables are stored reversed in memory. Starting from a1+1,
* we scan backward (decrementing) to find the NUL terminator, then
* compute the length as a negative offset (negated to get positive length).
warstring:
          move.l    a1,a4
          addq.l    #1,a4               * start one byte past a1
cstr1:
          tst.b     -(a4)               * scan backward for NUL terminator
          bne       cstr1
          sub.l     a1,a4               * a4 = negative offset
          move.l    a4,d0
          neg.l     d0                  * negate to get positive length
          addq.l    #1,d0               * +1 for NUL byte
          move.l    d0,a4               * a4 = string length (positive)

* --- ll6: Check if string space is sufficient, trigger GC if needed ---
ll6:
          btst      #0,d7               * is this resv_str (fresh allocation)?
          bne       cstrcont            * yes -> skip empty-string check
          cmp.l     #1,a4               * was the new string empty (length=1=just NUL)?
          beq       nocstr              * yes -> nothing to copy, return

cstrcont: move.l    strend,a3           * a3 = current bottom of string space
	add.l	#32,a4              * add 32 bytes safety margin
          sub.l     a4,a3               * a3 = projected new strend after copy
          cmp.l     varend,a3           * would it overlap the variable area?
          bpl       cstr3               * no -> enough space, proceed with copy

* --- Not enough space: trigger garbage collection ---
          move.l    strend,pgarbend     * set GC scan limit to entire string space
          bsr       garbage			* run garbage collector (saves d0-d7, adjusts a0-a6)
	move.l	strend,a3           * re-check: get new strend after GC
	sub.l	a4,a3               * projected new strend
	cmp.l	varend,a3           * still not enough space?
	bpl		cstr3               * enough now -> proceed
	move.b	d1,(a2)			* restore previously saved char back to source!
	bra		outstrspc           * out of string space error

* --- cstr3: Perform the actual string copy ---
cstr3:
          move.l    strend,a3           * a3 = current string space bottom
          cmp.b     #$22,d1             * string constant or variable?
          beq       warkonst            * quote -> constant (forward copy)

* --- String variable copy: copy BACKWARD from a1 into string space ---
* Variable strings are stored reversed. We read from a1 going backward
* and write into the heap going backward (pre-decrement on both).
          addq.l    #1,a1               * adjust source pointer
          addq.l    #1,a3               * adjust destination pointer
          btst      #0,d7               * is this resv_str?
          bne       ll7                 * yes -> don't skip extra byte
          addq.l    #1,a3               * skip NUL terminator of previous string
ll7:
          move.b    -(a1),-(a3)         * copy one byte (backward)
          bne       ll7                 * loop until NUL copied
          bra       ll8                 * done -> update strend

* --- warkonst: String constant copy: copy FORWARD from a1, write backward ---
* Constants are stored normally (forward). We read forward from a1 but
* write backward into the heap (pre-decrement), effectively reversing
* the string into the heap's downward-growing format.
warkonst:
          addq.l    #1,a3               * adjust destination pointer
          btst      #0,d7               * is this resv_str?
          bne       cstr2               * yes -> don't skip extra byte
          addq.l    #1,a3               * skip NUL of previous string in heap
cstr2:
          move.b    (a1)+,-(a3)         * copy one byte (read forward, write backward)
          bne       cstr2               * loop until NUL copied

* --- ll8: Update strend to reflect newly occupied string space ---
ll8:
          subq.l    #1,a3               * point past the last byte written
          move.l    a3,strend           * update strend to new bottom of string area
nocstr:   rts                             * return (no copy needed if empty string)

*==============================================================================
* get_var_konst - Variable/Constant Dispatch by First Character
*==============================================================================
* Purpose: Determine what kind of element we're looking at based on the
*          first character, and dispatch to the appropriate handler:
*
*   TOKEN1/TOKEN2/TOKEN3 ($01/$02/$03) -> get_fkt (built-in function call)
*   '"' ($22)                          -> get_strkonst (string literal)
*   '$'                                -> get_hexvar (hex number like $FF00)
*   '%'                                -> get_binvar (binary number like %10110)
*   Letter (via isvarname)             -> get_var (variable lookup)
*   '('                                -> get_klammerarg (parenthesized subexpr)
*   Otherwise                          -> no_var (numeric literal)
*
*   Also handles unary minus: if '-' precedes the element, a flag is pushed
*   on the stack and checked after the element is fetched (getvtstneg).
*
* Parameters:
*   A0 = points to first character of the element (after charget backup)
*
* Returns:
*   d0-d3 = value (if numeric)
*   typflag = type of element
*==============================================================================
savea0:	.ds.l	1                       * temporary storage for a0 backup

get_var_konst:
          move.b    -(a0),d0            * back up and re-read current char (chargot)
	move.l	a0,savea0           * save position for potential backtrack

* --- Check for unary minus ---
	cmp.b	#'-',d0			* is the number to be negated?
	bne		vkpos               * no -> positive number
	move.w	#1,-(sp)			* push flag: number is negative!
	addq.l	#1,a0               * advance past '-'
	bsr		charget             * get the character after '-'
	subq.l	#1,a0               * back up (will be re-read by handler)
	bra		getv0               * proceed to dispatch

vkpos:
	clr.w	-(sp)               * push flag: number is positive (no negate)

* --- getv0: Dispatch based on first character ---
getv0:
          cmp.b     #TOKEN1,d0 		* first byte of a function token?
	beq		getv0a              * yes -> function call
	cmp.b	#TOKEN2,d0          * second token class?
	beq		getv0a              * yes -> function call
	cmp.b	#TOKEN3,d0          * third token class?
	bne		getv1               * no -> try next possibility

getv0a:
          bsr       get_fkt             * call function handler
	bra		getvtstneg          * check for pending unary minus

getv1:
          cmp.b     #$22,d0             * '"' -> string constant?
	bne		getv2               * no -> try next
          bsr       get_strkonst        * parse string constant
	bra		getvtstneg          * check for pending unary minus

getv2:
          cmp.b     #'$',d0             * '$' -> hexadecimal number?
	bne		getv3               * no -> try next
          bsr       get_hexvar          * parse hex literal (e.g., $FF00)
	bra		getvtstneg          * check for pending unary minus

getv3:
          cmp.b     #'%',d0             * '%' -> binary number?
	bne		getv4               * no -> try next
          bsr       get_binvar          * parse binary literal (e.g., %10110)
	bra		getvtstneg          * check for pending unary minus

getv4:
          bsr		isvarname           * is it a variable name character?
          bne       getv5               * no -> try next
	bsr		get_var             * look up variable
 	bra		getvtstneg          * check for pending unary minus

getv5:
	cmp.b	#'(',d0			* parenthesized subexpression?
	beq		getv7               * yes -> handle it
	move.l	savea0,a0			* restore a0 (no_var handles negation itself)
	addq.l	#2,sp			* discard negate flag from stack
	bra		no_var              * must be a numeric literal

getv7:
	addq.l	#1,a0			* skip past opening parenthesis
	bsr		get_klammerarg      * evaluate parenthesized subexpression
*	bra		getvtstneg          * (fall through to getvtstneg)

*==============================================================================
* getvtstneg - Apply Pending Unary Minus
*==============================================================================
* Purpose: Check the negate flag that was pushed onto the stack by
*          get_var_konst. If the flag is non-zero (unary minus was present),
*          negate the result:
*   - INT: simple neg.l on d0
*   - FLOAT: compute 0 - x using rsub_ (reverse subtract from zero_)
*   - STRING: no negation (just return)
*==============================================================================
getvtstneg:
	tst.w	(sp)+               * pop and test the negate flag
	beq		getvend             * flag=0 -> no negation needed

* --- Negate INT ---
	cmp.w	#INT,typflag        * is the result an integer?
	bne		tstnegfloat         * no -> try float
	neg.l	d0                  * negate the integer value in d0
	rts

* --- Negate FLOAT ---
tstnegfloat:
	cmp.w	#FLOAT,typflag      * is the result a float?
	bne		getvend             * no (must be STRING) -> skip negation
	movem.l	d4-a6,-(sp)         * save registers (rsub_ uses many)
	move.l	d0,d4               * move float value to d4-d7
	move.l	d1,d5               *   (rsub_ computes d0-d3 minus d4-d7)
	move.l	d2,d6
	move.l	d3,d7
	movem.l	zero_,d0-d3         * d0-d3 = 0.0
	bsr		rsub_			* compute 0.0 - value = negated value
	movem.l	(sp)+,d4-a6         * restore registers

getvend:
	rts

*==============================================================================
* SECTION: Numeric Literal Parsing, Function Dispatch, Operator Lookup,
*          Comparison Operators, Bitwise Operators, and Arithmetic Add/Sub
*==============================================================================

*==============================================================================
* no_var - Parse a numeric literal from the input buffer
*
* Purpose:   Called when the current token is neither a string constant nor a
*            variable name -- it must be a numeric literal. Uses the BLIBF.S
*            routine rlda_ to parse ASCII digits into an extended float in
*            d0-d3. Then attempts to demote the result to INT if the value
*            fits within the 32-bit integer range.
*
* Entry:     a0 -> first character of the numeric literal in the input buffer
*
* Exit:      d0-d3 = parsed value (FLOAT format if typflag=FLOAT, or d0=INT)
*            typflag = FLOAT or INT depending on result
*            a0 -> character immediately after the parsed number
*
* Uses:      rlda_ (BLIBF.S ASCII-to-float converter)
*            rpkl  (BLIBF.S float-to-integer converter)
*==============================================================================

* Not a string constant, not a variable -> numeric literal input
no_var:
          bsr       rlda_     * Parse ASCII number -> d0-d3 as float (extended), a0 past number
* In rlda_, typflag is set to FLOAT if a radix point is found or number is too big
          subq.l    #1,a0     * Position to next character in buffer (back up one)
          cmp.w     #FLOAT,typflag
          beq       novarend  * Already marked as FLOAT by rlda_ -> keep it
          cmp.w     #FLOAT,typ2flag     * Is FLOAT required by the expression context?
          bne       intoint   * No -> try to keep as INT
intofl:
          move.w    #FLOAT,typflag      * Force type to FLOAT
          rts
intoint:
          cmp.w     #$4001,d0           * Is exponent within INT range? (exponent < 1?)
          blt       intofl              * Exponent too small (fractional) -> use FLOAT
          cmp.w     #$4009,d0
          bhi       intofl              * Exponent > 8 digits -> too large for INT, use FLOAT
          bsr       rpkl                * Convert float in d0-d3 to integer in d0
          move.w    #INT,typflag        * Mark result as INT type
novarend:
          rts

*==============================================================================
* get_var - Fetch a variable's value
*
* Purpose:   Looks up or creates a variable, handles array indexing if needed,
*            and reads the variable's value into d0-d3 / a1-a2.
*
* Entry:     a0 -> first character of the variable name
*
* Exit:      d0-d3 = variable value (for numeric types)
*            a1/a2 = string pointers (for STRING type)
*            a2 -> zero_+4 as a dummy value pointer (zero code already present)
*            typflag set to the variable's type
*==============================================================================
get_var:
          bsr       tst_var             * Test for variable and fetch address if defined
          tst.w     d0
          bne       get_v1              * Non-zero: variable already exists
	move.w	typvalid,-(sp)		* Save typvalid as a precaution
	move.w	typflag,typvalid    * Set typvalid from current typflag
          bsr       create2_var         * Create the variable (auto-create on first use)
	move.w	(sp)+,typvalid      * Restore original typvalid
get_v1:
          tst.b     arrayfl             * Is this an array variable?
          beq       get_v3              * No -> skip array indexing
          movem.l   fac1,d1-d4          * Save fac1 for possible recursion
          movem.l   d1-d4,-(sp)
          bsr       posarray            * Parse array subscript(s) and position -> a1
          movem.l   (sp)+,d1-d4
          movem.l   d1-d4,fac1          * Restore fac1
          move.w    d0,d7               * Save d0 across closing parenthesis check
          bsr       chk_klammer         * Check for closing parenthesis ')'
          move.w    d7,d0               * Restore d0
get_v3:
          bsr       read_var            * Read variable value into d0-d3 / a1-a2
          lea       zero_+4,a2          * Dummy value pointer (zero code already present)
          rts

*==============================================================================
* get_strkonst - Fetch a string constant
*
* Purpose:   Parses a quoted string constant from the input buffer.
*            Sets typflag to STRING and returns pointers to the string data.
*
* Entry:     a0 -> the opening quote character '"'
*
* Exit:      a1 -> first character of the string (after opening quote)
*            a2 -> character after closing quote (or after null terminator)
*            typflag = STRING
*==============================================================================
get_strkonst:
          move.w    #STRING,typflag     * Set type to STRING
          addq.l    #1,a0               * Skip past opening '"' to first ASCII character
          move.l    a0,a1               * a1 = start of string data
getsk1:
          move.b    (a0)+,d0            * Read next character
          beq       getskend            * Null terminator -> end of string (unterminated)
          cmp.b     #$22,d0             * Is it a closing quote '"' ($22)?
          bne       getsk1              * No -> continue scanning
getskend:
          move.l    a0,a2               * a2 = position after string (past quote or null)
          rts

*==============================================================================
* get_hexvar - Parse a hexadecimal literal (e.g., $FFFABFD)
*
* Purpose:   Parses a hexadecimal number prefixed with '$'. Accumulates
*            digits into a 32-bit integer. Overflow causes SOVER_ error.
*
* Entry:     a0 -> the '$' prefix character
*
* Exit:      d0.l = parsed integer value
*            typflag = INT
*            a0 -> character after the last hex digit
*==============================================================================
get_hexvar:
          moveq     #0,d1               * Clear accumulator
          addq.l    #1,a0               * Skip past '$' prefix
ghex3:    move.b    (a0)+,d0            * Fetch next digit character
	or.b		#$20,d0			* Force lowercase (a-z / A-Z -> a-z)
          cmp.b     #'0',d0
          blt       ghexend             * Below '0' -> not a hex digit, stop
          cmp.b     #'f',d0
          bhi       ghexend             * Above 'f' -> not a valid hex digit
          cmp.b     #'a',d0
          blt       ghex2               * Below 'a' -> might be '0'-'9'
          sub.b     #'a'-10,d0          * Convert 'a'-'f' to 10-15
          bra       ghex1               * Go accumulate
ghex2:    cmp.b     #'9',d0
          bhi       ghexend             * Between '9'+1 and 'a'-1 -> not a hex digit
          sub.b     #'0',d0             * Convert '0'-'9' to 0-9
ghex1:    lsl.l     #4,d1               * Shift accumulator left by 4 bits (one hex digit)
          bcs       SOVER_              * Carry set = overflow (number too large)
          or.b      d0,d1               * Merge new digit into accumulator
          bra       ghex3               * Continue parsing
ghexend:  move.w    #INT,typflag        * Result is always INT type
          move.l    d1,d0               * Move result to d0
          subq.l    #1,a0               * Back up: a0 past the non-hex char, rewind one
          rts

*==============================================================================
* get_binvar - Parse a binary literal (e.g., %10110)
*
* Purpose:   Parses a binary number prefixed with '%'. Accumulates bits
*            into a 32-bit integer. Overflow causes SOVER_ error.
*
* Entry:     a0 -> the '%' prefix character
*
* Exit:      d0.l = parsed integer value
*            typflag = INT
*            a0 -> character after the last binary digit
*            (Falls through to ghexend for the final steps)
*==============================================================================
get_binvar:
          moveq     #0,d1               * Clear accumulator
          addq.l    #1,a0               * Skip past '%' prefix
gbin1:    move.b    (a0)+,d0            * Fetch next character
          cmp.b     #'1',d0
          bhi       ghexend             * Above '1' -> not a binary digit, finish via ghexend
          cmp.b     #'0',d0
          blt       ghexend             * Below '0' -> not a binary digit, finish via ghexend
          sub.b     #'0',d0             * Convert '0'/'1' to 0/1
          lsl.l     #1,d1               * Shift accumulator left by 1 bit
          bcs       SOVER_              * Carry set = overflow (number too large)
          or.b      d0,d1               * Merge new bit into accumulator
          bra       gbin1               * Continue parsing

*==============================================================================
* get_fkt - Execute a function and return its result
*
* Purpose:   Universal function/command dispatcher. Reads a two-byte token
*            (group byte + index byte) to compute the handler address from
*            the comadr1/comadr2/comadr3 dispatch tables. Checks bit flags
*            in the address longword to determine how to call the handler.
*
*            The comadr table entries are longword addresses with embedded
*            bit flags in the upper byte:
*              bit 31 ($80000000): This is a FUNCTION (returns a value),
*                                  not a standalone command.
*              bit 28 ($10000000): Dual-use -- can be both a command and
*                                  a function (e.g., INSTR, POINT).
*              bit 27 ($08000000): No parenthesis check needed for this
*                                  function (e.g., NOT, INKEY$).
*
*            For functions: all expression evaluator state is saved on the
*            stack (fac1, fac2, operator, strend, str_ptr, follchar,
*            typ2flag) before calling the handler, then restored afterward.
*            The function's result is returned in d0-d3 with typflag set.
*
* Entry:     a0 -> the token intro byte (TOKEN1/TOKEN2/TOKEN3)
*
* Exit:      d0-d3 = function result
*            typflag = result type (FLOAT, INT, or STRING)
*            a0 updated past the function's arguments
*
* Errors:    syntaxerr if '(' expected but missing
*            nofkterr if a command token is used where a function is expected
*==============================================================================
get_fkt:
	moveq	#0,d0
	move.b	(a0)+,d0			* Read token group byte (1, 2, or 3)
	lsl.w	#2,d0               * Multiply by 4 (longword index)
	lea		comadr,a1           * Base of dispatch table pointer array
	move.l	(a1,d0),a1          * a1 -> appropriate comadr1/comadr2/comadr3 table

          move.b    (a0)+,d0            * Read index byte (low byte of token)
          lsl.w     #2,d0               * Multiply by 4 (longword offset)
          move.l    (a1,d0),d7		* Load handler address + flags; a0 must be advanced by handler
          btst      #31,d7              * Bit 31 set = this is a function (not a command)
	bne		onlyfkt             * Yes -> proceed as function
	btst		#28,d7			* Bit 28 set = dual-use (can be command or function)
	beq		nofkterr            * Neither bit set -> pure command used as function = error
	move.w	#1,cmdfktfl		* Set flag: calling this command as a function
onlyfkt:
          btst      #27,d7              * Bit 27 set = no parenthesis check needed?
          bne       gfkt1               * Yes -> skip '(' check (e.g., NOT, INKEY$)
          bsr       charget             * Get next non-space character
          cmp.b     #'(',d0             * Function must start with '('
          bne       syntaxerr           * Missing '(' -> syntax error

* --- Save all expression evaluator state on the stack ---
gfkt1:    move.w    typvalid,-(sp)      * Save expected type validity
          move.w    typ2flag,-(sp)      * Save current expression type context
          movem.l   fac1,d0-d3          * Save fac1 (accumulator 1)
          movem.l   d0-d3,-(sp)
          movem.l   fac2,d0-d3          * Save fac2 (accumulator 2)
          movem.l   d0-d3,-(sp)
          move.w    operator,-(sp)      * Save current operator
          move.l    strend,spstr        * Save string end pointer via onqlist
          bsr       onqlist             * Push spstr onto the string protection queue
          move.l    str_ptr,spstr       * Save string pointer via onqlist
          bsr       onqlist             * Push spstr onto the string protection queue
          move.l    d7,-(sp)            * Save handler address + flags on stack

* --- Call the function handler ---
          and.l     #$00ffffff,d7       * Mask off flag bits, keep only 24-bit address
          move.l    d7,a2               * Load handler address into a2
          jsr       (a2)                * Call function handler (sets typflag, result in d0-d3)

* --- Restore state after function returns ---
          move.l    (sp)+,d7            * Restore handler address + flags
          btst      #27,d7              * Was this a no-parenthesis function?
          bne       gfkt2               * Yes -> skip ')' check
          move.w    d0,d7               * Save d0 (part of result) across ')' check
          bsr       chk_klammer         * Check for closing parenthesis ')'
          move.w    d7,d0               * Restore d0
gfkt2:    bsr       offqlist            * Pop string pointer from protection queue
          move.l    spstr,str_ptr       * Restore str_ptr
          bsr       offqlist            * Pop string end from protection queue
          move.l    spstr,strend        * Restore strend
          move.w    (sp)+,operator      * Restore operator
          movem.l   (sp)+,d4-d7
          movem.l   d4-d7,fac2          * Restore fac2
          movem.l   (sp)+,d4-d7
          movem.l   d4-d7,fac1          * Restore fac1
          move.w    (sp)+,typ2flag      * Restore expression type context
          move.w    (sp)+,typvalid      * Restore expected type validity
          rts

*==============================================================================
* get_operator - Look up a BASIC operator and return its priority
*
* Purpose:   Reads the next token from the input buffer and determines if it
*            is a valid operator. Returns the operator's priority level (1-13)
*            or sets Z flag if no operator found (end of expression).
*
*            Operators can be either:
*            1. Token-based: AND ($01xx), OR ($01xx), EOR ($01xx) - these are
*               recognized by their token encoding and mapped to priorities 4, 5, 3.
*            2. Single-character: looked up in optoktabl
*               '{','}','~','&','|','<','=','>','+','-','*','/','^'
*               with priorities from oppriotabl: 1-13 respectively.
*
*            For comparison operators (priority 6-8: <, =, >), the routine
*            checks the NEXT character for compound operators (<=, >=, <>, etc.)
*            and stores it in follchar for the comparison handler to process.
*
* Entry:     a0 -> current position in the input buffer
*
* Exit:      d0.w = operator priority (1-13), or 0 if no operator
*            Z flag set if no operator found (end of expression / ')' / etc.)
*            workop = operator priority (saved copy)
*            follchar = second character of compound comparison (if any)
*            a0 updated past the operator token(s)
*==============================================================================
get_operator:
	moveq.l	#0,d0
          clr.w     follchar            * Initialize: no compound comparison character
          clr.w     workop              * Initialize: no operator yet
          bsr       charget             * Read next non-space character from buffer
	beq		koend2			* End of line -> return with Z set (no operator)
	cmp.b	#TOKEN1,d0		* Is it a token intro byte?
	bne		ko0                 * No -> check single-character operators

* --- Token-based operator check (AND, OR, EOR) ---
	lsl.w	#8,d0               * Shift intro byte to high byte of d0.w
	bsr		charget             * Read the token index byte
	cmp.w	#AND,d0             * Is it AND token?
	beq		ko_and
	cmp.w	#OR,d0              * Is it OR token?
	beq		ko_or
	cmp.w	#EOR,d0             * Is it EOR (XOR) token?
	beq		ko_eor
	subq.l	#2,a0			* Wrong token -> back up two bytes (undo both reads)
	clr.w	d0				* Set zero flag (no valid operator)
	bra		koend2              * Return with Z set

* --- Map token-based operators to their priority table index ---
ko_eor:
	moveq.l	#2,d1			* EOR -> table index 2 (priority 3 = XOR)
	bra		kofound
ko_or:
	moveq.l	#4,d1               * OR -> table index 4 (priority 5 = OR)
	bra		kofound
ko_and:
	moveq.l	#3,d1               * AND -> table index 3 (priority 4 = AND)
	bra		kofound

* --- Single-character operator lookup via optoktabl ---
ko0:
          lea       optoktabl,a5        * Table of operator characters: {,},~,&,|,<,=,>,+,-,*,/,^
          clr.w     d1                  * Start index at 0
ko1:
          cmp.b     (a5,d1),d0          * Compare input char with table entry
          beq       kofound             * Match found
          addq.w    #1,d1               * Next table entry
          cmp.w     #anzops,d1          * Reached end of table (total number of operators)?
          bne       ko1                 * Not yet -> keep searching
          bra       koend2              * No match -> return with Z set (no operator)

* --- Operator found: look up priority and check for compound comparisons ---
kofound:
	moveq.l	#0,d0
          lea       oppriotabl,a5       * Priority table (indexed same as optoktabl)
          move.b    (a5,d1),d0          * d0 = priority of found operator (1-13)
          cmp.b     #6,d0               * Priority 6-8 are comparison operators (<, =, >)
          blt       koend               * Below 6 -> not a comparison, done
          cmp.b     #8,d0
          bhi       koend               * Above 8 -> not a comparison, done

* --- Compound comparison check (<=, >=, <>, =<, =>, ><) ---
          move.b    (a0),follchar       * Peek at next char and store as potential compound
          move.b    (a0),d2             * Also load into d2 for comparison
          cmp.b     #'<',d2             * Is next char '<'?
          beq       koend1              * Yes -> compound comparison (e.g., >=, ><)
          cmp.b     #'>',d2             * Is next char '>'?
          beq       koend1              * Yes -> compound comparison (e.g., <=, <>)
          cmp.b     #'=',d2             * Is next char '='?
          bne       koend               * No -> single comparison operator only
koend1:   addq.l    #1,a0               * Advance past the second comparison character
koend:    move.w    d0,workop           * Save operator priority for later reference
koend2:   rts

*==============================================================================
* Comparison Operator Routines
*
* These routines implement the six comparison operations:
*   <, <=, <> (not equal), >, >=, =
*
* All use facscmp to compare fac1 vs fac2. facscmp handles both INT and
* FLOAT types and sets the N/Z/V condition flags:
*   N set (bmi) = fac1 < fac2
*   Z set (beq) = fac1 == fac2
*   neither (bpl+bne) = fac1 > fac2
*
* Compound comparisons are detected via follchar, which was set by
* get_operator when it found a second comparison character.
*
* Results: cmptrue returns 1 (INT) or 1.0 (FLOAT), cmpfalse returns 0.
*==============================================================================

*==============================================================================
* Lower - Less-than operator '<'
*
* Checks follchar for compound forms:
*   '<=' -> lowerequ (less than or equal)
*   '<>' -> unequal  (not equal)
*   '<<' -> syntax error
*   '<'  -> strict less than
*==============================================================================
Lower:
          cmp.b     #'=',follchar       * Is it '<='?
          beq       lowerequ
          cmp.b     #'<',follchar       * Is it '<<'? (invalid)
          beq       syntaxerr
          cmp.b     #'>',follchar       * Is it '<>'? (not equal)
          beq       unequal
          bsr       facscmp             * Compare fac1 vs fac2
          bmi       cmptrue             * fac1 < fac2 -> true
          bra       cmpfalse            * Otherwise -> false

* --- Less than or equal (<=) ---
lowerequ:
          bsr       facscmp
          bmi       cmptrue             * fac1 < fac2 -> true
          beq       cmptrue             * fac1 == fac2 -> true
          bra       cmpfalse            * fac1 > fac2 -> false

* --- Not equal (<> or ><) ---
unequal:
          bsr       facscmp
          bne       cmptrue             * fac1 != fac2 -> true
          bra       cmpfalse            * fac1 == fac2 -> false

*==============================================================================
* Higher - Greater-than operator '>'
*
* Checks follchar for compound forms:
*   '><' -> unequal   (not equal, alternative syntax)
*   '>=' -> higherequ (greater than or equal)
*   '>>' -> syntax error
*   '>'  -> strict greater than
*==============================================================================
Higher:
          cmp.b     #'<',follchar       * Is it '><'? (not equal, alternative)
          beq       unequal
          cmp.b     #'=',follchar       * Is it '>='?
          beq       higherequ
          cmp.b     #'>',follchar       * Is it '>>'? (invalid)
          beq       syntaxerr
          bsr       facscmp             * Compare fac1 vs fac2
          beq       cmpfalse            * fac1 == fac2 -> false
          bpl       cmptrue             * fac1 > fac2 (positive, non-zero) -> true
          bra       cmpfalse            * fac1 < fac2 -> false

* --- Greater than or equal (>=) ---
higherequ:
          bsr       facscmp
          bpl       cmptrue             * fac1 >= fac2 (positive or zero) -> true
          bra       cmpfalse            * fac1 < fac2 -> false

*==============================================================================
* Equal - Equality operator '='
*
* Checks follchar for compound forms:
*   '=<' -> lowerequ  (less than or equal, alternative syntax)
*   '=>' -> higherequ (greater than or equal, alternative syntax)
*   '==' -> syntax error
*   '='  -> strict equality
*==============================================================================
Equal:
          cmp.b     #'<',follchar       * Is it '=<'? (alternative for <=)
          beq       lowerequ
          cmp.b     #'>',follchar       * Is it '=>'? (alternative for >=)
          beq       higherequ
          cmp.b     #'=',follchar       * Is it '=='? (invalid)
          beq       syntaxerr
          bsr       facscmp             * Compare fac1 vs fac2
          bne       cmpfalse            * Not equal -> false

*==============================================================================
* cmptrue - Return boolean TRUE
*
* Returns 1 as INT, or 1.0 ($4001/$10000/0/0) as FLOAT, depending on
* the current expression type context (typ2flag).
*==============================================================================
cmptrue:
          cmp.w     #FLOAT,typ2flag     * Is the expression context FLOAT?
          beq       cmptr1              * Yes -> return 1.0 as float
          moveq.l   #1,d0               * Return integer 1 (TRUE)
          rts
cmptr1:   move.l    #$00004001,d0       * Float 1.0: exponent = $4001
          move.l    #$00010000,d1       * Float 1.0: mantissa high = $10000000 (normalized)
          moveq.l   #0,d2               * Float 1.0: mantissa mid = 0
          moveq.l   #0,d3               * Float 1.0: mantissa low = 0
          rts

*==============================================================================
* cmpfalse - Return boolean FALSE
*
* Returns 0 in all type contexts by loading from the zero_ constant.
*==============================================================================
cmpfalse:
          movem.l   zero_,d0-d3         * Load zero value (works for both INT and FLOAT)
          rts


*==============================================================================
* Bitwise and Shift Operators
*
* All bitwise/shift operators follow the same convint/reconvint pattern:
*
*   1. convint: If typ2flag=FLOAT, convert both fac1 and fac2 from float
*      to integer via rpkl. If typ2flag=STRING, raise type mismatch error.
*      If already INT, do nothing.
*
*   2. Perform the bitwise/shift operation on the integer values.
*
*   3. reconvint: If the original type was FLOAT (typ2flag=FLOAT), convert
*      the integer result back to float via ltor_ (d4=input -> d0-d3=float).
*      If INT, just return the integer result in d0.
*
* This pattern allows bitwise operations to work on both INT and FLOAT
* values by temporarily converting to integers and back.
*==============================================================================

*==============================================================================
* ShL - Shift Left operator '{'
*
* Computes: fac1 << fac2 (logical shift left)
* Both operands converted to INT, result optionally converted back to FLOAT.
*==============================================================================
ShL:
          bsr       convint             * Ensure both operands are integers
          move.l    fac1,d0             * d0 = left operand (value to shift)
	move.l	fac2,d1             * d1 = right operand (shift count)
          lsl.l     d1,d0               * Logical shift left d0 by d1 bits
          bra       reconvint           * Convert back to FLOAT if needed and return

*==============================================================================
* ShR - Shift Right operator '}'
*
* Computes: fac1 >> fac2 (logical shift right)
* Both operands converted to INT, result optionally converted back to FLOAT.
*==============================================================================
ShR:
          bsr       convint             * Ensure both operands are integers
          move.l    fac1,d0             * d0 = left operand (value to shift)
	move.l	fac2,d1             * d1 = right operand (shift count)
          lsr.l     d1,d0               * Logical shift right d0 by d1 bits
          bra       reconvint           * Convert back to FLOAT if needed and return

*==============================================================================
* Xor - Bitwise exclusive OR operator '~' / EOR
*
* Computes: fac1 XOR fac2
* Both operands converted to INT, result optionally converted back to FLOAT.
*==============================================================================
Xor:
          bsr       convint             * Ensure both operands are integers
          move.l    fac1,d0             * d0 = left operand
	move.l	fac2,d1             * d1 = right operand
          eor.l     d1,d0               * Bitwise XOR: d0 = d0 XOR d1
          bra       reconvint           * Convert back to FLOAT if needed and return

*==============================================================================
* And - Bitwise AND operator '&' / AND
*
* Computes: fac1 AND fac2
* Both operands converted to INT, result optionally converted back to FLOAT.
*==============================================================================
And:
          bsr       convint             * Ensure both operands are integers
          move.l    fac1,d0             * d0 = left operand
          and.l     fac2,d0             * Bitwise AND: d0 = d0 AND fac2
          bra       reconvint           * Convert back to FLOAT if needed and return

*==============================================================================
* Or - Bitwise OR operator '|' / OR
*
* Computes: fac1 OR fac2
* Both operands converted to INT, result optionally converted back to FLOAT.
*==============================================================================
Or:
          bsr       convint             * Ensure both operands are integers
          move.l    fac1,d0             * d0 = left operand
          or.l      fac2,d0             * Bitwise OR: d0 = d0 OR fac2
          bra       reconvint           * Convert back to FLOAT if needed and return

*==============================================================================
* reconvint - Convert integer result back to FLOAT if needed
*
* Purpose:   After a bitwise/shift operation, checks whether the expression
*            context requires FLOAT. If so, converts the integer result in
*            d0 back to float via ltor_.
*
* Entry:     d0.l = integer result
*            typ2flag = type context of the expression
*
* Exit:      d0(-d3) = result in appropriate type (INT or FLOAT)
*==============================================================================
reconvint:
          cmp.w     #FLOAT,typ2flag     * Was the expression context FLOAT?
          beq       reconv1             * Yes -> convert back to float
          rts                           * No -> return integer result in d0
reconv1:  move.l    d0,d4               * Move integer to d4 (input for ltor_)
          bra       ltor_               * Convert d4 to float in d0-d3 and return


*==============================================================================
* convint - Convert both fac1 and fac2 to integers for bitwise operations
*
* Purpose:   Prepares operands for bitwise/shift operations by converting
*            FLOAT values to INT. Raises type mismatch for STRING operands.
*
* Entry:     fac1, fac2 = operands (may be FLOAT or INT)
*            typ2flag = current type context
*
* Exit:      fac1, fac2 = integer values (converted if needed)
*            If STRING type, branches to typemis (type mismatch error)
*==============================================================================
convint:  cmp.w     #FLOAT,typ2flag     * Are operands FLOAT?
          beq       convfloat           * Yes -> convert both to integer
          cmp.w     #STRING,typ2flag    * Are operands STRING?
          beq       typemis             * Yes -> type mismatch error
          rts                           * Already INT -> nothing to do
convfloat:movem.l   fac1,d0-d3          * Load fac1 as float (extended format)
          bsr       rpkl                * Convert float to integer -> d0
          move.l    d0,fac1             * Store integer result back in fac1
          movem.l   fac2,d0-d3          * Load fac2 as float (extended format)
          bsr       rpkl                * Convert float to integer -> d0
          move.l    d0,fac2             * Store integer result back in fac2
          rts

*==============================================================================
* Add - Addition operator '+'
*
* Purpose:   Adds fac1 + fac2. Supports both FLOAT and INT operands.
*
*            The BEQ/BNE dispatch convention: before calling this routine,
*            exec_operation executes 'cmp.w #FLOAT,typ2flag'. If the Z flag
*            is set (BEQ), both operands are FLOAT and we delegate to radd_
*            (BLIBF.S floating-point addition). If Z is clear (BNE), the
*            operands are INT and we use integer addition with overflow check.
*
* Entry:     Z flag from 'cmp.w #FLOAT,typ2flag' (set=FLOAT, clear=INT)
*            For FLOAT: d0-d3 = fac1, d4-d7 = fac2 (extended float format)
*            For INT:   d0 = fac1, d4 = fac2 (32-bit integers)
*
* Exit:      d0(-d3) = result of addition
*            On integer overflow: branches to SOVER_ error handler
*==============================================================================
Add:
          beq       radd_               * Z set (FLOAT) -> delegate to BLIBF float add
          add.l     d4,d0               * Integer add: d0 = fac1 + fac2
          bvs       SOVER_              * Overflow -> numeric overflow error
          rts

*==============================================================================
* Sub - Subtraction operator '-'
*
* Purpose:   Subtracts fac1 - fac2. Supports both FLOAT and INT operands.
*            Uses the same BEQ float dispatch convention as Add (see above).
*
* Entry:     Z flag from 'cmp.w #FLOAT,typ2flag' (set=FLOAT, clear=INT)
*            For FLOAT: d0-d3 = fac1, d4-d7 = fac2 (extended float format)
*            For INT:   d0 = fac1, d4 = fac2 (32-bit integers)
*
* Exit:      d0(-d3) = result of subtraction
*            On integer overflow: branches to SOVER_ error handler
*==============================================================================
Sub:
          beq       rsub_               * Z set (FLOAT) -> delegate to BLIBF float subtract
          sub.l     d4,d0               * Integer subtract: d0 = fac1 - fac2
          bvs       SOVER_              * Overflow -> numeric overflow error
          rts

*==============================================================================
* SECTION: Exponentiation, Mul/Div, Utilities, Garbage Collector, File I/O,
*          Program Linking, and LINE Command
*==============================================================================

*==============================================================================
* SECTION: Exponentiation (x ^ y)
*==============================================================================
* Purpose:   Compute x raised to the power y (x^y).
* Algorithm: For float operands, uses log10(x)*y then 10^result.
*            For integer operands, converts to float first via lateconv.
*            Preserves sign: if base is negative and exponent is odd,
*            result is negative. The sgnfl flag tracks this.
* Parameters: d0-d3 = x (fac1, base), d4-d7 = y (fac2, exponent)
*             Z flag = 0 means integer mode, Z flag = 1 means float mode
* Returns:    d0-d3 = result (float)
* Uses:       rlog10_, rmul_, rexp10_ (BLIBF.S), rpkl (float->int), lateconv
*==============================================================================

sgnfl:	.ds.w	1                           * Sign flag: 0 = positive, -1 = negative result
Exponent:
          beq       exponent                * If float mode (Z=1), skip integer conversion
	move.l	d4,d5                       * Save fac2 low word in d5
	move.l	d0,d4                       * Move fac1 (integer) into d4 for lateconv
	bsr		lateconv                    * Convert both operands from int to float

* --- Main exponentiation logic (float path) ---
exponent:
	lea		zero_,a1                    * Point to float constant 0.0
	cmp.l	(a1)+,d0                    * Compare x (d0) with zero_ word 0
	bne		expon0                      * If d0 != 0, x is nonzero -> proceed
	cmp.l	(a1)+,d1                    * Compare d1 with zero_ word 1
	bne		expon0
	cmp.l	(a1)+,d2                    * Compare d2 with zero_ word 2
	bne		expon0
	cmp.l	(a1),d3                     * Compare d3 with zero_ word 3
	beq		expon3                      * x == 0.0 -> result is 0, return directly
expon0:
	clr.w	sgnfl                       * Assume positive result initially
	btst		#31,d0			            * Test sign bit of x (bit 31 of d0)
	beq		expon1                      * If positive, skip sign handling
	not.w	sgnfl                       * x is negative: set sgnfl to -1 (=$FFFF)
	bclr		#31,d0                      * Clear sign bit -> make x positive for log
expon1:
	movem.l	d4-d7,-(sp)		            * Push y (exponent) onto stack for later
	movem.l	d0-d3,-(sp)		            * Push x (base, now positive) onto stack
	move.l	d4,d0                       * Copy y into d0-d3 for rpkl conversion
	move.l	d5,d1
	move.l	d6,d2
	move.l	d7,d3
	bsr		rpkl				        * Convert y (float) to integer in d0
	btst		#0,d0			            * Test if y is odd (bit 0)
	bne		expon2                      * If odd, keep the negative sign flag
	clr.w	sgnfl                       * y is even: result is positive regardless
expon2:
	movem.l	(sp)+,d0-d3                 * Restore x (positive base) into d0-d3

          bsr       rlog10_                 * d0-d3 = log10(|x|)
          move.l    d0,d4                   * Move log10(|x|) result into fac2 (d4-d7)
          move.l    d1,d5
          move.l    d2,d6
          move.l    d3,d7
          movem.l   (sp)+,d0-d3		        * Restore y (exponent) from stack into d0-d3
          bsr       rmul_                   * d0-d3 = y * log10(|x|)
          bsr       rexp10_                 * d0-d3 = 10^(y * log10(|x|)) = |x|^y

	tst.w	sgnfl                       * Check if result should be negative
	beq		expon3                      * If sgnfl == 0, result is positive -> done
	bset		#31,d0                      * Set sign bit to make result negative
expon3:
	rts                                 * Return with result in d0-d3

*==============================================================================
* SECTION: Integer/Float Division
*==============================================================================
* Purpose:   Divide fac1 by fac2. Attempts integer division first;
*            if there is a remainder, falls back to float division.
* Parameters: d0 = fac1 (int) or d0-d3 = fac1 (float)
*             d4 = fac2 (int) or d4-d7 = fac2 (float)
*             Z flag: 0 = integer, 1 = float
* Returns:    d0 (int) or d0-d3 (float) = quotient
* Notes:      "BEQ bedeutet float-division" = Z=1 means float division
*==============================================================================
Div:
	beq		rdiv_			            * Float mode -> jump to BLIBF float division
	movem.l	d0/d4,-(sp)		            * Save fac1 and fac2 (integer values)
	bsr		idiv				        * Perform integer division d0/d4
	movem.l	(sp)+,d4/d5                 * Restore original fac1->d4, fac2->d5
	tst.l	d0                          * Check if division was exact (idiv returns 0 if not)
	bne		divnozero                   * Nonzero = exact integer result -> done
	bsr		lateconv                    * Remainder exists: convert both to float
	bra		rdiv_                       * Perform float division instead
divnozero:
	rts                                 * Return with integer quotient in d0

*==============================================================================
* SECTION: Late Conversion (Integer to Float)
*==============================================================================
* Purpose:   Convert both fac1 (d4) and fac2 (d5) from integer to float.
*            Used when an integer operation needs to fall back to float.
* Parameters: d4 = fac1 (int), d5 = fac2 (int)
* Returns:    d0-d3 = fac1 (float), d4-d7 = fac2 (float)
*             typ2flag set to FLOAT
*==============================================================================
lateconv:
	move.l	d5,-(sp)			        * Save fac2 integer value
	bsr		ltor_			            * Convert d4 (fac1 int) -> d0-d3 (float)
	move.l	(sp)+,d4                    * Restore fac2 int into d4
	movem.l	d0-d3,-(sp)                 * Save fac1 float on stack
	bsr		ltor_			            * Convert d4 (fac2 int) -> d0-d3 (float)
	move.l	d0,d4                       * Move fac2 float into d4-d7
	move.l	d1,d5
	move.l	d2,d6
	move.l	d3,d7
	movem.l	(sp)+,d0-d3                 * Restore fac1 float into d0-d3
	move.w	#FLOAT,typ2flag             * Mark operation type as FLOAT
	rts

*==============================================================================
* SECTION: Integer/Float Multiplication
*==============================================================================
* Purpose:   Multiply fac1 by fac2. Attempts integer multiply first;
*            if overflow occurs, falls back to float multiplication.
* Parameters: d0 = fac1 (int) or d0-d3 = fac1 (float)
*             d4 = fac2 (int) or d4-d7 = fac2 (float)
*             Z flag: 0 = integer, 1 = float
* Returns:    d0 (int) or d0-d3 (float) = product
* Notes:      imul sets fl1work nonzero on overflow
*==============================================================================
Mul:
	beq		rmul_			            * Float mode -> jump to BLIBF float multiply
	movem.l	d0/d4,-(sp)		            * Save fac1 and fac2 (integer values)
	bsr		imul				        * Perform integer multiply d0*d4
	movem.l	(sp)+,d4/d5                 * Restore original fac1->d4, fac2->d5
	tst.l	fl1work			            * Check overflow flag from imul
	beq		nooverflw                   * No overflow -> integer result is valid
	bsr		lateconv                    * Overflow: convert both to float
	bra		rmul_                       * Perform float multiplication instead
nooverflw:
	rts                                 * Return with integer product in d0

*==============================================================================
* SECTION: Subroutine-safe Integer Multiplication
*==============================================================================
* Purpose:   Integer multiplication that saves and restores ALL registers.
*            Used by subroutines that need multiplication without
*            disturbing any registers.
* Parameters: d0 = multiplicand, d4 = multiplier (same as imul)
* Returns:    Result in d0, all other registers preserved
*==============================================================================
submul:
          movem.l   d0-a6,-(sp)             * Save all registers (d0-d7, a0-a6)
          bsr       imul                    * Perform integer multiplication
          movem.l   (sp)+,d0-a6             * Restore all registers
          rts

*==============================================================================
* SECTION: Syntax Checking Helpers
*==============================================================================

*==============================================================================
* chk_klammer - Check for closing parenthesis
*==============================================================================
* Purpose:   Verify that the current character is ')'. If not, raise
*            a syntax error.
* Parameters: a0 = pointer into input buffer (past the character to check)
* Returns:    Returns normally if ')' found; jumps to syntaxerr otherwise
*==============================================================================
chk_klammer:
          bsr       chargot                 * Re-read current character (backs up a0 by 1)
          cmp.b     #')',d0                 * Is it a closing parenthesis?
          bne       syntaxerr               * No -> syntax error
          rts

*==============================================================================
* tst_komma - Test for comma (non-fatal)
*==============================================================================
* Purpose:   Check if current character is a comma. Sets Z flag accordingly.
* Parameters: a0 = pointer into input buffer
* Returns:    Z flag = 1 if comma found, Z = 0 if not
*==============================================================================
tst_komma:
          bsr       chargot                 * Re-read current character
          cmp.b     #',',d0                 * Is it a comma?
          rts                               * Return with Z flag set by cmp

*==============================================================================
* chk_komma - Require comma (fatal if missing)
*==============================================================================
* Purpose:   Verify that the current character is a comma. If not, raise
*            a syntax error.
* Parameters: a0 = pointer into input buffer
* Returns:    Returns normally if comma found; jumps to syntaxerr otherwise
*==============================================================================
chk_komma:
          bsr       chargot                 * Re-read current character
          cmp.b     #',',d0                 * Is it a comma?
          bne       syntaxerr               * No -> syntax error
          rts

*==============================================================================
* SECTION: Character Reading Routines
*==============================================================================

*==============================================================================
* chargot - Re-read current character
*==============================================================================
* Purpose:   Back up one position in the input buffer and read the character
*            there, skipping spaces. Used to re-examine the current token.
* Parameters: a0 = pointer one past current character in input buffer
* Returns:    d0 = character read (with spaces skipped)
*             Z flag set if d0 == 0 (end of line)
*             a0 updated to point past the returned character
*==============================================================================
chargot:
          subq.l    #1,a0                   * Back up to re-read current character

*==============================================================================
* charget - Read next non-space character
*==============================================================================
* Purpose:   Advance through the input buffer, skipping spaces, and return
*            the next meaningful character.
* Parameters: a0 = pointer into input buffer
* Returns:    d0 = next non-space character
*             Z flag set if d0 == 0 (end of line/statement)
*             a0 updated to point past the returned character
*==============================================================================
charget:
          move.b    (a0)+,d0                * Read next byte and advance pointer
          cmp.b     #$20,d0                 * Is it a space?
          beq.s     charget                 * Yes -> skip it, read next character
          tst.b     d0                      * Set Z flag (0 = end of line)
          rts

*==============================================================================
* charget6 - Read next non-space character into d6
*==============================================================================
* Purpose:   Same as charget but returns the result in d6 instead of d0.
*            Used by BLIBF.S callback routines that need d0 preserved.
* Parameters: a0 = pointer into input buffer
* Returns:    d6 = next non-space character
*             Z flag set if d6 == 0 (end of line/statement)
*             a0 updated to point past the returned character
*==============================================================================
charget6:
          move.b    (a0)+,d6                * Read next byte into d6
          cmp.b     #$20,d6                 * Is it a space?
          beq.s     charget                 * Yes -> skip (note: loops via charget)
          tst.b     d6                      * Set Z flag
          rts

*==============================================================================
* SECTION: String Pointer Protection (qlist)
*==============================================================================
* The qlist is a stack-like array (250 entries max) that protects string
* pointers (spstr/str_ptr) from being corrupted during recursive expression
* evaluation and garbage collection. When a string pointer must survive
* a call to get_term or other routines that may trigger GC, it is pushed
* onto qlist via onqlist. The garbage collector updates ALL qlist entries
* when compacting string space, ensuring pointers remain valid.
*==============================================================================

*==============================================================================
* onqlist - Push str_ptr onto the qlist protection stack
*==============================================================================
* Purpose:   Save the current spstr value onto the qlist array.
*            This protects the string pointer from being invalidated
*            by garbage collection during nested expression evaluation.
* Parameters: spstr = string pointer to protect
* Returns:    qlistptr advanced by 4 bytes
* Preserves:  a0
*==============================================================================
onqlist:
          move.l    a0,-(sp)                * Save a0
          move.l    qlistptr,a0             * Get current qlist stack pointer
          move.l    spstr,(a0)+             * Store spstr at current position, advance
          move.l    a0,qlistptr             * Update qlist stack pointer
          move.l    (sp)+,a0                * Restore a0
          rts

*==============================================================================
* offqlist - Pop str_ptr from the qlist protection stack
*==============================================================================
* Purpose:   Restore the previously saved spstr value from qlist.
*            Called after the protected operation (get_term, etc.) completes.
* Parameters: qlistptr = current top of qlist stack
* Returns:    spstr = restored string pointer value
*             qlistptr decremented by 4 bytes
* Preserves:  a0
*==============================================================================
offqlist:
          move.l    a0,-(sp)                * Save a0
          move.l    qlistptr,a0             * Get current qlist stack pointer
          subq.l    #4,a0                   * Back up one entry (4 bytes per pointer)
          move.l    (a0),spstr              * Restore spstr from qlist
          move.l    a0,qlistptr             * Update qlist stack pointer
          move.l    (sp)+,a0                * Restore a0
          rts

*==============================================================================
* SECTION: Garbage Collector
*==============================================================================
* The garbage collector compacts the string space by removing "dead" strings.
*
* STRING MEMORY LAYOUT:
*   String space grows DOWNWARD from strbase toward strend.
*   Each string is stored REVERSED (last char first) and terminated by a
*   zero byte ($00) for live strings, or a $FF byte for dead strings.
*   Dead strings are created by killstr when a string variable is reassigned.
*
* ALGORITHM:
*   1. Save all registers. Push pgarbend, str_ptr, strend onto qlist
*      so they will be updated during compaction.
*   2. Output a key tone ($0700) as a "working" indicator.
*   3. Scan from strbase downward toward pgarbend:
*      a. For each string, read bytes backward until hitting $00 or $FF.
*      b. If $00 (live string): skip to next string.
*      c. If $FF (dead string): COMPACT by copying all bytes below the
*         dead string upward by the dead string's length. Then update
*         ALL pointers that referenced the moved region:
*         - Variable descriptors (garb_var)
*         - Saved registers a0-a6 (garb_reg)
*         - qlist entries (garb_qlist)
*   4. After all strings processed: restore pgarbend, str_ptr, strend
*      from qlist. Restore all registers.
*
* KEY VARIABLES:
*   strbase   - Top of string space (highest address)
*   strend    - Current bottom of used string space (lowest used address)
*   pgarbend  - Lower bound of region to scan
*   d7        - Length of dead string being removed (compaction offset)
*   a0        - Current scan position in string space
*   a6        - Start (top) of current string being examined
*==============================================================================
garbage:
          movem.l   d0-d7,-(sp)             * Save all data registers on stack
          movem.l   a0-a6,savereg           * Save all address registers to savereg buffer

          * --- Protect critical pointers on qlist ---
          * These pointers reference string space and must be updated
          * if strings below them are compacted (shifted upward).
          move.l    pgarbend,spstr          * Push pgarbend onto qlist
          bsr       onqlist
          move.l    str_ptr,spstr           * Push str_ptr onto qlist
          bsr       onqlist
          move.l    strend,spstr            * Push strend onto qlist
          bsr       onqlist

          * --- Output key tone as "GC working" indicator ---
          move.w    #$0700,key              * Key tone frequency value
          pea       key                     * Push pointer to key value
          move.w    #9,-(sp)                * GEMDOS Cconws (function 9) - write string
          trap      #1                      * Call GEMDOS
          addq.l    #6,sp                   * Clean up stack (4 + 2 bytes)

          * --- Begin scanning string space from top (strbase) downward ---
          move.l    strbase,a0              * a0 = start at top of string space
garb1:
          move.l    a0,a6                   * a6 = remember start of this string
          addq.l    #1,a0                   * Advance past the string's first byte position
garb2:
          move.b    -(a0),d0                * Read byte moving downward through string
          beq       nextstrd                * $00 = end of live string -> skip to next
          cmp.b     #-1,d0                  * $FF = dead string marker?
          bne       garb2                   * Neither -> keep scanning this string

* --- killstr: Remove dead string and compact string space ---
* At this point:
*   a6 = top of dead string (its starting address in memory)
*   a0 = position of the $FF marker (bottom of dead string)
*   The dead string occupies bytes from a0 to a6 (inclusive)
killstr:
          move.l    a6,d7                   * d7 = top of dead string
          subq.l    #1,a0                   * Adjust a0 to point below the $FF marker
          sub.l     a0,d7                   * d7 = length of dead string (bytes to remove)

          * --- Shift all strings below the dead one upward by d7 bytes ---
          * This closes the gap left by the dead string.
          move.l    a0,a2                   * a2 = destination (copy target, moves upward)
          move.l    a6,a3                   * a3 = source start (top of dead string)
          move.l    a0,d0                   * Calculate number of bytes to move:
          sub.l     pgarbend,d0             *   d0 = distance from dead string to pgarbend
          addq.l    #1,a2                   * Adjust destination pointer
          addq.l    #1,a3                   * Adjust source pointer
garb4:
          move.b    -(a2),-(a3)             * Copy one byte upward (from lower to higher addr)
          subq.l    #1,d0                   * Decrement byte counter
          bne       garb4                   * Loop until all bytes moved

          * --- Update all pointers that reference the moved region ---
          * Any pointer that pointed into the region below the dead string
          * must be adjusted upward by d7 (the size of the removed string).
          bsr       garb_var                * Update variable string descriptors
          bsr       garb_reg                * Update saved address registers (a0-a6)
          bsr       garb_qlist              * Update qlist protection stack entries
          add.l     d7,a0                   * Adjust current scan pointer by compaction offset
          bra       nextstr                 * Continue scanning

*==============================================================================
* garb_qlist - Update string pointers in the qlist protection stack
*==============================================================================
* Purpose:   Walk all entries in the qlist array and adjust any pointer
*            that falls within the compacted region.
* Parameters: d7 = compaction offset, a0 = bottom of moved region
*             strend = lower bound of string space
*==============================================================================
garb_qlist:
          lea       qlist,a1                * a1 = base of qlist array
garbq1:   cmp.l     qlistptr,a1             * Have we reached the current top of qlist?
          bpl       garbrts                 * Yes -> done (a1 >= qlistptr)
          bsr       linkstr                 * Check and adjust this qlist entry if needed
          addq.l    #4,a1                   * Advance to next qlist entry (4 bytes each)
          bra       garbq1                  * Continue
          rts                               * (unreachable, but present in original)

*==============================================================================
* garb_reg - Update string pointers in saved address registers
*==============================================================================
* Purpose:   Walk the 7 saved address registers (a0-a6 stored in savereg)
*            and adjust any that point into the compacted region.
* Parameters: d7 = compaction offset, a0/strend for range check
*==============================================================================
garb_reg:
          moveq.l   #6,d6                   * Loop counter: 7 registers (0-6, using dbf)
          lea       savereg,a1              * a1 = base of saved register buffer
garbr1:   bsr       linkstr                 * Check and adjust this register if needed
          addq.l    #4,a1                   * Advance to next register (4 bytes each)
          dbf       d6,garbr1               * Decrement counter and loop
          rts

*==============================================================================
* garb_var - Update string pointers in all variables
*==============================================================================
* Purpose:   Walk the entire variable linked list starting at varbase.
*            For each STRING variable, adjust its string pointer if it
*            falls within the compacted region. Handles both simple
*            string variables and string arrays.
* Parameters: d7 = compaction offset, a0/strend for range check
* Structure:  Each variable entry:
*             [4-byte next_ptr][2-byte type_flags][name bytes...][0]
*             [alignment pad][value]
*             For arrays: value = [depth.l][dim1.l]...[dimN.l][elements...]
*==============================================================================
garb_var:
          move.l    varbase,a1              * Start at beginning of variable list
garb3:
          move.l    (a1)+,a5                * a5 = next variable pointer; advance past it
          cmp.l     #0,a5                   * Is next pointer null (end of list)?
          beq       garbrts                 * Yes -> done scanning variables
          move.w    (a1)+,d0                * Read type flags word
	and.w	#INT+FLOAT+STRING,d0        * Mask to keep only type bits
          cmp.w     #STRING,d0              * Is this a string variable?
          bne       garb5                   * No -> skip to next variable
garbok:   btst      #15,d0                  * Test array flag (bit 15 of type word)
          bne       garbarray               * If set, handle as array
          bra       garbstr                 * Otherwise, handle as simple string variable
garb5:
          move.l    a5,a1                   * Follow next pointer to next variable
          bra       garb3                   * Continue walking the list
garbrts:  rts                               * Return (shared exit point)

* --- nextstrd / nextstr: Advance to next string in string space ---
nextstrd:
          subq.l    #1,a0                   * Adjust for the zero byte we read
nextstr:
          cmp.l     pgarbend,a0             * Have we reached the bottom of scan region?
          bge       garb1                   * No -> continue scanning (go back to garb1)

          * --- Garbage collection complete: restore protected pointers ---
          bsr       offqlist                * Pop strend from qlist
          move.l    spstr,strend            * Restore strend
          bsr       offqlist                * Pop str_ptr from qlist
          move.l    spstr,str_ptr           * Restore str_ptr
          bsr       offqlist                * Pop pgarbend from qlist
*         move.l    spstr,pgarbend          * (commented out in original - not restored)

          * --- Restore all registers ---
          movem.l   (sp)+,d0-d7             * Restore data registers from stack
          movem.l   savereg,a0-a6           * Restore address registers from savereg
          rts

*==============================================================================
* garbstr - Update a simple string variable's pointer
*==============================================================================
* Purpose:   Find the value field of the current variable (past the name)
*            and adjust its string pointer if within the moved region.
*==============================================================================
garbstr:
          bsr       garbsearch              * Skip past variable name to value field -> a1
          bsr       linkstr                 * Adjust the string pointer if needed
          bra       garb5                   * Continue to next variable

*==============================================================================
* garbsearch - Skip past variable name to reach value field
*==============================================================================
* Purpose:   Variable names are stored as null-terminated strings.
*            This routine skips past the name bytes and any alignment
*            padding to reach the value longword.
* Parameters: a1 = pointer into variable (at start of name)
* Returns:    a1 = pointer to the value field (word-aligned)
*==============================================================================
garbsearch:
          tst.b     (a1)+                   * Read name byte and advance
          bne       garbsearch              * If nonzero, keep skipping name bytes
          move.l    a1,d0                   * Check alignment of pointer
          btst      #0,d0                   * Is address odd?
          beq       garbs1                  * No -> already word-aligned
          addq.l    #1,a1                   * Yes -> add 1 byte padding for alignment
garbs1:
          rts

*==============================================================================
* linkstr - Adjust a single string pointer if within the moved region
*==============================================================================
* Purpose:   Check if the longword at (a1) points into the region that
*            was shifted during compaction. If so, add the compaction
*            offset (d7) to bring it to its new location.
* Parameters: a1 = pointer to a longword containing a string address
*             a0 = top boundary of moved region
*             strend = bottom boundary of string space
*             d7 = compaction offset (bytes shifted upward)
* Returns:    (a1) adjusted if within range; unchanged otherwise
*==============================================================================
linkstr:
          move.l    (a1),d0                 * Read the string pointer value
          cmp.l     a0,d0                   * Is it above the moved region?
          bhi       garbs1                  * Yes -> not affected, skip
          cmp.l     strend,d0               * Is it below string space entirely?
          blt       garbs1                  * Yes -> not affected, skip
          add.l     d7,(a1)                 * Within range: adjust pointer upward by d7
          rts

*==============================================================================
* garbarray - Update string pointers in a string array
*==============================================================================
* Purpose:   Skip past the array header (dimension count and dimension
*            sizes) then walk all array elements, adjusting each string
*            pointer if within the moved region.
* Parameters: a1 = pointer into variable (at start of name)
*             a5 = pointer to next variable (marks end of this array's data)
*             d7 = compaction offset
*==============================================================================
garbarray:
          bsr       garbsearch              * Skip past variable name to array header
          move.l    (a1)+,d0                * d0 = number of dimensions (array depth)
garbar1:
          move.l    (a1)+,d1                * Skip dimension size entry
          subq.l    #1,d0                   * Decrement dimension counter
          bne       garbar1                 * More dimensions -> keep skipping
garbar2:
          bsr       linkstr                 * Adjust this array element's string pointer
          addq.l    #4,a1                   * Advance to next element (4 bytes per pointer)
          cmp.l     a1,a5                   * Have we reached the end of the array?
          bhi       garbar2                 * No -> process next element
          bra       garb5                   * Done with array, continue to next variable

*==============================================================================
* SECTION: Variable Name Copy Utilities
*==============================================================================

*==============================================================================
* save_vname - Copy variable name to backup buffer
*==============================================================================
* Purpose:   Copy the null-terminated variable name from var_name to
*            var2_name. Used before operations that might overwrite var_name.
* Preserves: a0, a1
*==============================================================================
save_vname:
          movem.l   a0-a1,-(sp)             * Save registers
          lea       var_name,a0             * Source: current variable name
          lea       var2_name,a1            * Destination: backup buffer
save_v2:
          move.b    (a0)+,(a1)+             * Copy one byte
          bne.s     save_v2                 * Loop until null terminator copied
          movem.l   (sp)+,a0-a1             * Restore registers
          rts

*==============================================================================
* load_vname - Restore variable name from backup buffer
*==============================================================================
* Purpose:   Copy the null-terminated variable name from var2_name back
*            to var_name. Reverses a previous save_vname call.
* Preserves: a0, a1
*==============================================================================
load_vname:
          movem.l   a0-a1,-(sp)             * Save registers
          lea       var2_name,a0            * Source: backup buffer
          lea       var_name,a1             * Destination: current variable name
          bra.s     save_v2                 * Reuse the copy loop (and its movem/rts)

*==============================================================================
* SECTION: Integer Parsing
*==============================================================================

*==============================================================================
* get_int - Parse a decimal integer from text
*==============================================================================
* Purpose:   Read consecutive ASCII digit characters from the input buffer
*            and convert them to a 32-bit integer value.
* Algorithm: Multiply-by-10 trick using shifts:
*            d0 * 10 = d0 * 8 + d0 * 2 = (d0 << 3) + (d0 << 1)
*            This avoids the slower mulu instruction.
* Parameters: a0 = pointer to first character to parse
* Returns:    d0 = parsed integer value
*             a0 = pointer past the last digit
* Clobbers:   d1, d2
*==============================================================================
get_int:
          moveq     #0,d0                   * Initialize result to 0
get_i1:
          moveq     #0,d1                   * Clear d1 for byte extension
          move.b    (a0),d1                 * Read current character (without advancing)
          cmp.b     #'0',d1                 * Is it below '0'?
          blt       get_iend                * Yes -> not a digit, done
          cmp.b     #'9',d1                 * Is it above '9'?
          bhi       get_iend                * Yes -> not a digit, done
          sub.b     #'0',d1                 * Convert ASCII digit to numeric value (0-9)
          move.l    d0,d2                   * d2 = copy of current result
          lsl.l     #3,d0                   * d0 = result * 8
          lsl.l     #1,d2                   * d2 = result * 2
          add.l     d2,d0                   * d0 = result * 8 + result * 2 = result * 10
          add.l     d1,d0                   * d0 = result * 10 + new digit
          addq.l    #1,a0                   * Advance past this digit
          bra.s     get_i1                  * Continue reading digits
get_iend:
          rts


*==============================================================================
* SECTION: Drive Selection
*==============================================================================

*==============================================================================
* setdrv - Parse and set drive letter from filename
*==============================================================================
* Purpose:   If the filename pointed to by a1 begins with a drive letter
*            followed by ':', call GEMDOS Dsetdrv to change the default
*            drive, and adjust a1 to skip past the "X:" prefix.
* Parameters: a1 = pointer to reversed filename string (points at last char)
* Returns:    a1 adjusted past drive prefix if present
*             Default drive changed via GEMDOS
* GEMDOS:    Dsetdrv ($0E) - Set default drive
*            Stack layout: [drive_number.w][$000E.w]
*            drive_number: 0=A, 1=B, 2=C, etc.
*==============================================================================
setdrv:
	cmp.b	#':',-1(a1)		            * Is the char before a1 a colon?
	bne		nodrv                       * No -> no drive prefix, skip
	moveq.l	#0,d0                       * Clear d0
	move.b	(a1),d0                     * Read the drive letter
	and.b	#$1f,d0                     * Mask to get letter index (A=1, B=2, etc.)
	subq.w	#1,d0                       * Convert to 0-based (A=0, B=1, C=2, etc.)
	move.w	d0,-(sp)                    * Push drive number (word)
	move.w	#$e,-(sp)                   * Push GEMDOS function $0E (Dsetdrv)
	trap		#1				            * Call GEMDOS
	addq.l	#4,sp                       * Clean up stack (2 + 2 bytes)
	subq.l	#2,a1                       * Adjust a1 past the "X:" prefix
nodrv:
	rts

*==============================================================================
* SECTION: File I/O Wrappers
*==============================================================================
* All file operations use GEMDOS trap #1 calls. Filenames come from str_ptr
* which points to a REVERSED string in string space. The filename must be
* reversed (copied backwards) into var2_name before passing to GEMDOS.
* Error checking: negative d0 return = GEMDOS error.
*==============================================================================

*==============================================================================
* f_create - Create a new file
*==============================================================================
* Purpose:   Create a file using GEMDOS Fcreate ($3C).
*            The filename is taken from str_ptr (reversed string),
*            copied forward into var2_name, then passed to GEMDOS.
* Parameters: str_ptr = pointer to reversed filename string
* Returns:    handle variable set to GEMDOS file handle
*             Jumps to createrr on error
* GEMDOS:    Fcreate ($3C) - Create file
*            Stack layout: [attr.w][filename_ptr.l][$003C.w]
*            attr: file attributes (0 = normal)
*            Returns: file handle (>= 0) or negative error code
*==============================================================================
f_create:
          move.l    a0,-(sp)                * Save a0 (interpreter position)
          clr.w     -(sp)                   * Push file attribute = 0 (normal file)
          move.w    #$3c,work2              * Store GEMDOS function code for create
          bra       fo2                     * Jump to shared open/create code

*==============================================================================
* f_open - Open an existing file
*==============================================================================
* Purpose:   Open a file using GEMDOS Fopen ($3D) in read/write mode.
*            The filename is taken from str_ptr (reversed string).
* Parameters: str_ptr = pointer to reversed filename string
* Returns:    handle variable set to GEMDOS file handle
*             Jumps to openerr on error
* GEMDOS:    Fopen ($3D) - Open file
*            Stack layout: [mode.w][filename_ptr.l][$003D.w]
*            mode: 0=read, 1=write, 2=read/write
*            Returns: file handle (>= 0) or negative error code
*==============================================================================
f_open:
          move.l    a0,-(sp)                * Save a0 (interpreter position)
          move.w    #2,-(sp)                * Push open mode = 2 (read/write)
          move.w    #$3d,work2              * Store GEMDOS function code for open

* --- Shared code for f_create and f_open ---
* Reverses the filename from str_ptr into var2_name (forward order),
* then calls the appropriate GEMDOS function.
fo2:
	move.l    str_ptr,a1                * a1 = pointer to reversed filename string
	bsr		setdrv                      * Check for drive prefix and set drive if present
          lea       var2_name,a2            * a2 = destination buffer for forward filename
          addq.l    #1,a1                   * Skip past string's zero terminator
fo1a:
          move.b    -(a1),(a2)+             * Copy byte from reversed string to forward buffer
          bne       fo1a                    * Loop until null terminator reached

          pea       var2_name               * Push pointer to forward filename (4 bytes)
          move.w    work2,-(sp)             * Push GEMDOS function code ($3C or $3D)
          trap      #1                      * Call GEMDOS
          addq.l    #8,sp                   * Clean up stack (2 + 4 + 2 from attr/mode)
          tst.w     d0                      * Check for error (negative = error)
          bmi       fo3                     * Error -> handle it
          move.w    d0,handle               * Store returned file handle
          move.l    (sp)+,a0                * Restore a0 (interpreter position)
          rts
fo3:      cmp.w     #$3c,work2              * Was this a create operation?
          beq       createrr                * Yes -> jump to create error handler
          bra       openerr                 * No -> jump to open error handler

*==============================================================================
* f_write - Write data to a file
*==============================================================================
* Purpose:   Write bytes to a file using GEMDOS Fwrite ($40).
* Parameters: d0 = number of bytes to write
*             a1 = pointer to data buffer
*             handle = GEMDOS file handle
* Returns:    d0 = number of bytes actually written
*             Jumps to writerr on error
* GEMDOS:    Fwrite ($40) - Write to file
*            Stack layout: [buf_ptr.l][count.l][handle.w][$0040.w]
*            Returns: bytes written (>= 0) or negative error code
*==============================================================================
f_write:
          move.l    a0,-(sp)                * Save a0 (interpreter position)
          move.l    a1,-(sp)                * Push buffer pointer (4 bytes)
          move.l    d0,-(sp)                * Push byte count (4 bytes)
          move.w    handle,-(sp)            * Push file handle (2 bytes)
          move.w    #$40,-(sp)              * Push GEMDOS function $40 (Fwrite)
          trap      #1                      * Call GEMDOS
          lea       12(a7),a7              * Clean up stack (2 + 2 + 4 + 4 = 12 bytes)
          tst.l     d0                      * Check for error (negative = error)
          bmi       writerr                 * Error -> jump to write error handler
          move.l    (sp)+,a0                * Restore a0 (interpreter position)
          rts

*==============================================================================
* f_read - Read data from a file
*==============================================================================
* Purpose:   Read bytes from a file using GEMDOS Fread ($3F).
* Parameters: d0 = number of bytes to read
*             a1 = pointer to destination buffer
*             handle = GEMDOS file handle
* Returns:    d0 = number of bytes actually read
*             Jumps to readerr on error
* GEMDOS:    Fread ($3F) - Read from file
*            Stack layout: [buf_ptr.l][count.l][handle.w][$003F.w]
*            Returns: bytes read (>= 0) or negative error code
*==============================================================================
f_read:
          move.l    a0,-(sp)                * Save a0 (interpreter position)
          move.l    a1,-(sp)                * Push buffer pointer (4 bytes)
          move.l    d0,-(sp)                * Push byte count (4 bytes)
          move.w    handle,-(sp)            * Push file handle (2 bytes)
          move.w    #$3f,-(sp)              * Push GEMDOS function $3F (Fread)
          trap      #1                      * Call GEMDOS
          lea       12(a7),a7              * Clean up stack (2 + 2 + 4 + 4 = 12 bytes)
          tst.l     d0                      * Check for error (negative = error)
          bmi       readerr                 * Error -> jump to read error handler
          move.l    (sp)+,a0                * Restore a0 (interpreter position)
          rts

*==============================================================================
* f_close - Close a file
*==============================================================================
* Purpose:   Close a file using GEMDOS Fclose ($3E).
* Parameters: handle = GEMDOS file handle to close
* Returns:    (no meaningful return value)
* GEMDOS:    Fclose ($3E) - Close file
*            Stack layout: [handle.w][$003E.w]
*==============================================================================
f_close:
          move.l    a0,-(sp)                * Save a0 (interpreter position)
          move.w    handle,-(sp)            * Push file handle (2 bytes)
          move.w    #$3e,-(sp)              * Push GEMDOS function $3E (Fclose)
          trap      #1                      * Call GEMDOS
          addq.l    #4,sp                   * Clean up stack (2 + 2 = 4 bytes)
          move.l    (sp)+,a0                * Restore a0 (interpreter position)
          rts

*==============================================================================
* SECTION: Program Linking
*==============================================================================

*==============================================================================
* new_link - Convert relative offsets to absolute pointers after load
*==============================================================================
* Purpose:   After loading a program from a .BAS file, the next-line
*            pointers in each program line are stored as relative offsets
*            (relative to the start of the file data). This routine walks
*            the linked list and converts each offset to an absolute
*            memory address by adding prgbase.
* Parameters: prgbase = base address of loaded program
*             prgend = address where end-of-program marker should be
* Returns:    All next-line pointers converted to absolute addresses
*==============================================================================
new_link:
          move.l    prgend,a2               * Get program end address
          clr.l     (a2)                    * Ensure null terminator at end of program
          move.l    prgbase,a2              * Start at program base
          move.l    a2,d1                   * d1 = base address (offset to add)
nlink1:   move.l    (a2),d0                 * Read next-line pointer/offset
          beq       nlinkend                * If zero, we've reached the end
          add.l     d1,(a2)                 * Convert: relative offset + base = absolute ptr
          add.l     d1,d0                   * Also compute absolute address in d0
          move.l    d0,a2                   * Move to the next line
          bra       nlink1                  * Continue linking
nlinkend: rts

*==============================================================================
* SECTION: Line Number Search
*==============================================================================

*==============================================================================
* poszeile - Find a program line by line number
*==============================================================================
* Purpose:   Walk the program linked list searching for a specific line
*            number. Returns a pointer to the matching line, or the
*            insertion point if the line is not found.
* Parameters: d0 = line number to search for
* Returns:    a1 = pointer to the found line (or insertion point)
*             preline = pointer to previous line (0 if no previous line)
* Clobbers:   d2, d3
* Structure:  Each program line:
*             [4-byte next_ptr][4-byte line_number][tokenized data...]
*==============================================================================
preline:	.ds.l	1	                    * Storage for previous line pointer (0 = none)
poszeile:
          movem.l   d2/d3,-(sp)             * Save working registers
          move.l    prgbase,a1              * Start at program base
	moveq.l	#0,d2                       * d2 = previous line pointer (none initially)
posz1:
          move.l    (a1),d3                 * d3 = next-line pointer
          beq       poszend                 * If null, end of program reached
	cmp.l	4(a1),d0			        * Compare target line# with this line's number
	ble		poszend                     * If target <= current line#, found position
	move.l	a1,d2			            * Remember this line as "previous"
          move.l    d3,a1                   * Follow link to next line
          bra       posz1                   * Continue searching
poszend:
	move.l	d2,preline                  * Store previous line pointer
          movem.l   (sp)+,d2/d3             * Restore working registers
          rts

*==============================================================================
* SECTION: Command Flow Utilities
*==============================================================================

*==============================================================================
* tstnxtarg - Test if another argument follows
*==============================================================================
* Purpose:   Check if there is another argument in the current statement.
*            An argument exists if the next non-space character is neither
*            ':' (command separator) nor $00 (end of line).
* Parameters: a0 = pointer into input buffer
* Returns:    d0 = 0 (BEQ) if argument present
*             d0 = -1 (BNE) if no more arguments
*             a0 preserved (restored from a1)
*==============================================================================
tstnxtarg:
          move.l    a0,a1                   * Save current position
          bsr       charget                 * Read next non-space character
          beq       nonxt                   * End of line -> no more arguments
          cmp.b     #':',d0                 * Command separator?
          beq       nonxt                   * Yes -> no more arguments
          move.l    a1,a0                   * Restore position (argument exists)
          moveq     #0,d0                   * Return 0 (BEQ = argument present)
          rts
nonxt:
          move.l    a1,a0                   * Restore position
          moveq.l   #-1,d0                  * Return -1 (BNE = no argument)
          rts

*==============================================================================
* tonxtcmd - Skip to next command
*==============================================================================
* Purpose:   Advance the input pointer past the current command to the
*            next ':' separator or end of line ($00).
*            Does NOT handle quoted strings - colons inside strings
*            will be treated as command separators.
* Parameters: a0 = pointer into input buffer
* Returns:    a0 = pointer at the ':' or $00 that ends the command
*==============================================================================
tonxtcmd:
          bsr       charget                 * Read next character
          beq       tonxt1                  * End of line -> done
          cmp.b     #':',d0                 * Command separator?
          beq       tonxt1                  * Yes -> done
          bra       tonxtcmd                * Neither -> keep scanning
tonxt1:   rts

*==============================================================================
* dtonxtcmd - Skip to next command (DATA-aware)
*==============================================================================
* Purpose:   Same as tonxtcmd but correctly handles quoted strings.
*            A ':' inside a string literal (between matching '"' chars)
*            is NOT treated as a command separator. Essential for the
*            DATA statement which may contain strings with colons.
* Parameters: a0 = pointer into input buffer
* Returns:    a0 = pointer at the ':' or $00 that ends the command
* Algorithm:  d1 is toggled (via NOT) each time a '"' is encountered.
*             When d1 is nonzero, we are inside a string and ':' is ignored.
*==============================================================================
dtonxtcmd:
          clr.w     d1                      * d1 = quote flag (0 = outside string)
dton3:    bsr       charget                 * Read next character
          beq       dtonend                 * End of line -> done
          cmp.b     #':',d0                 * Command separator?
          bne       dton2                   * No -> check for quote
          tst.w     d1                      * Are we inside a quoted string?
          beq       dtonend                 * No -> colon is a real separator, done
          bra       dton3                   * Yes -> colon is part of string, continue
dton2:    cmp.b     #'"',d0                 * Is it a double quote?
          bne       dton3                   * No -> continue scanning
          not.w     d1                      * Toggle quote flag (0->$FFFF or $FFFF->0)
          bra       dton3                   * Continue scanning
dtonend:  rts


********************************************************************************
* STAD-Befehle:
********************************************************************************


*==============================================================================
* SECTION: LINE Drawing Command (Line-A Graphics)
*==============================================================================

*==============================================================================
* line - BASIC LINE command
*==============================================================================
* Purpose:   Draw a line from (x1,y1) to (x2,y2) using the Atari ST
*            Line-A graphics interface.
* Syntax:    LINE x1, y1, x2, y2
* Algorithm:
*   1. Parse four integer coordinates using get_term.
*   2. Store coordinates in Line-A variable table:
*      Offset $26 = x1, $28 = y1, $2A = x2, $2C = y2
*   3. Execute Line-A opcode $A003 (draw line).
* Parameters: a0 = pointer into tokenized command arguments
* Returns:    (line drawn on screen)
* Notes:      la_variablen points to the Line-A variable block,
*             obtained during initialization via the $A000 trap.
*             The Line-A line style, color, and write mode must be
*             set up beforehand (done during Init).
*==============================================================================
line:
          bsr       tstnxtarg               * Check that arguments are present
          bne       misargerr               * No arguments -> missing argument error

          * --- Parse x1 coordinate ---
          move.w    #INT,typvalid           * Require integer result
          bsr       get_term                * Evaluate expression -> fac1
          movea.l   la_variablen,a2         * Get Line-A variables base pointer
          move.w    fac1+2,$26(a2)          * Store x1 at Line-A X1 (offset 38/$26)

          * --- Parse y1 coordinate ---
          bsr       chk_komma               * Require comma separator
          move.w    #INT,typvalid           * Require integer result
          bsr       get_term                * Evaluate expression -> fac1
          movea.l   la_variablen,a2         * Get Line-A variables base pointer
          move.w    fac1+2,$28(a2)          * Store y1 at Line-A Y1 (offset 40/$28)

          * --- Parse x2 coordinate ---
          bsr       chk_komma               * Require comma separator
          move.w    #INT,typvalid           * Require integer result
          bsr       get_term                * Evaluate expression -> fac1
          movea.l   la_variablen,a2         * Get Line-A variables base pointer
          move.w    fac1+2,$2a(a2)          * Store x2 at Line-A X2 (offset 42/$2A)

          * --- Parse y2 coordinate ---
          bsr       chk_komma               * Require comma separator
          move.w    #INT,typvalid           * Require integer result
          bsr       get_term                * Evaluate expression -> fac1
          movea.l   la_variablen,a2         * Get Line-A variables base pointer
          move.w    fac1+2,$2c(a2)          * Store y2 at Line-A Y2 (offset 44/$2C)
*
* Set line parameters and draw
*
          nop                               * (placeholder - no additional setup needed)
          move.l    a0,-(a7)                * Save a0 (Line-A trap may clobber it)
          .dc.w     $a003                   * Line-A A_abline opcode ($A003): draw arbitrary line
          move.l    (a7)+,a0                * Restore a0
          rts

*==============================================================================
* SECTION: Error Entry Points, Error Handler, Data Tables, and BSS Declarations
*
*   1. Error entry points (one per error code, #0..#63)
*   2. The main error handler routine
*   3. The .data section with all static tables (strings, dispatch, tokens,
*      system call parameter descriptors, AES/VDI parameter blocks)
*   4. The .bss section with all runtime variable storage
*==============================================================================

********************************************************************************
* Error Entry Points
* Each error entry point loads a unique error code (0..63) into d0 and
* branches to the common 'error' handler. The label names hint at the
* condition; the actual human-readable text comes from the error string table.
********************************************************************************
* "Syntaxfehler" = Syntax errors / error messages
.globl  error                           * Entry point for blibf (float library errors)


defprerr:                               * Error 63: "improper procedure definition"
		moveq.l	#63,d0
		bra		error
headerr:                                * Error 62: "no BASIC file format"
		moveq.l	#62,d0
		bra		error
notopenerr:                             * Error 61: "no such handle known"
		moveq.l	#61,d0
		bra		error
trgoserr:                               * Error 60: "missing gosub"
		moveq.l	#60,d0
		bra		error
noeprcerr:                              * Error 59: "proc without endproc"
		moveq.l	#59,d0
		bra		error
noreterr:                               * Error 58: "gosub without return"
		moveq.l	#58,d0
		bra		error
nonxterr:                               * Error 57: "for without next"
		moveq.l	#57,d0
		bra		error
outstrspc:                              * Error 56: "out of string space"
		moveq.l	#56,d0
		bra		error
nofkterr:                               * Error 55: "illegal use as function"
		moveq.l	#55,d0
		bra		error
toerr:                                  * Error 54: "missing <to>"
		moveq.l	#54,d0
		bra		error
thenerr:                                * Error 53: "missing <then>"
		moveq.l	#53,d0
		bra		error
elseerr:                                * Error 52: "else without for"
		moveq.l	#52,d0
		bra		error
nocmderr:                               * Error 51: "illegal use as command"
		moveq.l	#51,d0
		bra		error
locdeferr:                              * Error 50: "local definition"
		moveq.l	#50,d0
		bra		error
misargerr:                              * Error 49: "missing arg(s)"
		moveq.l	#49,d0
		bra		error
fndeferr:                               * Error 48: "fn not defined"
		moveq.l	#48,d0
		bra		error
toobigerr:                              * Error 47: "arg too big"
		moveq.l	#47,d0
		bra		error
nolineerr:                              * Error 46: "can't find line number"
		moveq.l	#46,d0
		bra		error
strposerr:                              * Error 45: "position not within string"
		moveq.l	#45,d0
		bra		error
oddadrerr:                              * Error 44: "odd address access"
		moveq.l	#44,d0
		bra		error
cposerr:                                * Error 43: "cursor out of range"
		moveq.l	#43,d0
		bra		error
start1err:                              * Error 42: "arg < 1"
		moveq.l	#42,d0
		bra		error
aesrangeerr:                            * Error 41: "out of field range"
		moveq.l	#41,d0
		bra		error
manyargerr:                             * Error 40: "too many args"
		moveq.l	#40,d0
		bra		error
noargerr:                               * Error 39: "no arg allowed"
		moveq.l	#39,d0
		bra		error
negerr:                                 * Error 38: "no negative arg allowed"
negdimerr:                              *   (also used for negative DIM arguments)
		moveq.l	#38,d0
		bra		error
convovflerr:                            * Error 37: "line too long"
		moveq.l	#37,d0
		bra		error
convnoerr:                              * Error 36: "line numbers missing"
		moveq.l	#36,d0
		bra		error
procerr:                                * Error 35: "endproc without proc"
		moveq.l	#35,d0
		bra		error
procnotfound:                           * Error 34: "procedure not defined"
		moveq.l	#34,d0
		bra		error
varperr:                                * Error 33: "variable not yet defined"
          moveq.l   #33,d0
          bra       error
callerr:                                * Error 32: "improper function number for gemdos/bios/xbios"
          moveq.l   #32,d0
          bra       error
syserr:                                 * Error 31: "improper use of system variable"
          moveq.l   #31,d0
          bra       error
conterr:                                * Error 30: "can't continue"
          moveq.l   #30,d0
          bra       error
nodataerr:                              * Error 29: "out of data"
          moveq.l   #29,d0
          bra       error
alropen:                                * Error 28: "already open"
          moveq.l   #28,d0
          bra       error
handflow:                               * Error 27: "too many files open"
          moveq.l   #27,d0
          bra       error
stoperr:                                * Error 26: "prg stopped" (STOP command or Ctrl-C)
          moveq.l   #26,d0
          bra       error
ifflow:                                 * Error 25: "if-then-else overflow"
          moveq.l   #25,d0
          bra       error
toomanyprocs:                           * Error 24: "procedure overflow"
		moveq.l	#24,d0
		bra		error
gosflow:                                * Error 23: "gosub-return overflow"
          moveq.l   #23,d0
          bra       error
goserr:                                 * Error 22: "return without gosub"
          moveq.l   #22,d0
          bra       error
prgmerr:                                * Error 21: "illegal prg. mode"
          moveq.l   #21,d0
          bra       error
forflow:                                * Error 20: "for-next overflow"
          moveq.l   #20,d0
          bra       error
nexterr:                                * Error 19: "next without for"
          moveq.l   #19,d0
          bra       error
dircterr:                               * Error 18: "illegal direct"
          moveq.l   #18,d0
          bra       error
readerr:                                * Error 17: "file read"
          moveq.l   #17,d0
          bra       error
openerr:                                * Error 16: "file open"
          moveq.l   #16,d0
          bra       error
writerr:                                * Error 15: "file write"
          moveq.l   #15,d0
          bra       error
createrr:                               * Error 14: "file create"
          moveq.l   #14,d0
          bra       error
outprgmem:                              * Error 13: "out of program space"
          moveq.l   #13,d0
          bra       error
dimerr:                                 * Error 12: "dim"
          moveq.l   #12,d0
          bra       error
redef:                                  * Error 11: "re-define"
          moveq.l   #11,d0
          bra       error
outvarmem:                              * Error 10: "out of variable space"
          moveq.l   #10,d0
          bra       error
badsubscr:                              * Error 9: "bad subscript"
          moveq.l   #9,d0
          bra       error
typemis:                        * Error 1: "type mismatch"  (errors 2-8 raised by float library)
          moveq     #1,d0
          bra       error
syntaxerr:                              * Error 0: "syntax"
          moveq.l   #0,d0

*==============================================================================
* ROUTINE: error  --  Main Error Handler
*
* Purpose: Central error handler for all BASIC errors. Displays the error
*          message, optionally shows the offending line number (in program
*          mode), attempts to list the offending line, then returns to the
*          editor prompt (basic1).
*
* Entry:   d0.l = error code (0..63)
*
* Flow:
*   1. If convfl is set (CONVERT command active), close the convert output
*      file and clear the flag before proceeding.
*   2. Save current line number (akt_zeile) on the stack.
*   3. Set contline = -1 (disable CONT command) UNLESS the error is #26
*      ("prg stopped") AND we are in program mode -- in that case, save
*      the continuation state (contline/contladr/contadr) so the user
*      can type CONT to resume.
*   4. Call clrfilefl to reset file output redirection.
*   5. Display: CR + "? " + <error message> + " error"
*   6. If in program mode (b_modus != 0) and line number is non-zero:
*      display " in line " + line_number (converted via ipka_).
*   7. Attempt to position to and list the offending line.
*   8. Branch to basic1 (return to editor/command prompt).
*==============================================================================
error:
		tst.w	convfl                  * Is CONVERT mode active?
		beq		error0                  * No -> skip file close
		move.l	d0,-(sp)                * Save error code
		bsr		f_close                 * Close the convert output file on error
		clr.w	convfl                  * Clear convert-active flag
		move.l	(sp)+,d0                * Restore error code
error0:
		move.l	akt_zeile,-(sp)         * Save current line number on stack
          move.l    #-1,contline        * Default: CONT not allowed (contline = -1)
          cmp.b     #26,d0              * Was the error "prg stopped" (#26)?
          bne       error1              * No -> skip CONT setup
          tst.w     b_modus             * Are we in program mode? (0=direct)
          beq       error1              * Direct mode -> CONT not possible either
          move.l    akt_zeile,contline  * Save line number for CONT
          move.l    akt_adr,contladr    * Save address of current line for CONT
          move.l    a0,contadr          * Save current parse pointer for CONT
		clr.l	akt_zeile               * Clear line number (0 -> suppress list)
error1:
		bsr       clrfilefl             * Reset file output flag (stop redirecting to file)
          lea       errormark,a0        * a0 -> CR + "? " prefix
          bsr       put_string          * Display error prefix
          lsl.w     #2,d0               * d0 = error_code * 4 (index into longword table)
          lea       errortab,a0         * a0 -> error message pointer table
          move.l    (a0,d0.w),a0        * a0 -> actual error message string
          bsr       put_string          * Display error message (e.g. "syntax")
          lea       errtxt1,a0          * a0 -> " error"
          bsr       put_string          * Display " error" suffix
          tst.w     b_modus             * Check for direct mode (0 = direct)
          beq       basic1              * Direct mode -> done, return to prompt
		tst.l	(sp)                    * Check saved line number on stack
		beq		error1a                 * If 0, don't display (0 is confusing as dummy line#)

          lea       errtxt2,a0          * a0 -> " in line " (program mode: show line number)
          bsr       put_string          * Display " in line "
          move.l    (sp)+,d0            * d0 = saved line number
          bsr       ipka_               * Convert line number to ASCII string (result in a2)
          lea       -1(a2),a0           * Skip the sign character (always positive)
          bsr       putstrreverse       * Display the reversed string (ipka_ stores reversed)
error1a:
		tst.l	akt_zeile               * If akt_zeile is 0, skip line listing
		beq		noerrlist
		move.l	akt_zeile,d0            * d0 = line number of offending line
		move.l	d0,d6                   * d6 = start line for listing range
		move.l	d0,d7                   * d7 = end line for listing range
		bsr		poszeile                * Try to position to that line (returns a1)
		cmp.l	akt_adr,a1              * Does found line address match expected?
		bne		noerrlist               * No match -> don't list (line may have been deleted)
		move.l	a1,a0                   * a0 = line address for listing
		clr.w	d0                      * d0 = 0 (list single line)
		bsr		listlines               * List the offending line
		bsr		new_line                * Output a newline
noerrlist:
          bra       basic1              * Return to editor/command prompt


********************************************************************************
**   Start of Data Section                                                    **
********************************************************************************
* Globals exported for blibf (float library):
.globl  typflag,typ2flag,typ3flag,str_ptr,work1
.data

* --- Hexadecimal digit lookup table (lowercase) ---
hextab    .dc.b   '0','1','2','3','4','5','6','7','8','9','a','b','c'
          .dc.b   'd','e','f'

* --- Pointers to key data structures ---
qlistptr  .dc.l     qlist          * Pointer to qlist (string protection stack in BSS)
tisptr	.dc.l	tistrend-1             * Pointer to end of TI$ string buffer (minus 1)

* --- Prompt and status strings ---
ready:    .dc.b     13,"ready.",13,0   * "ready." prompt displayed after commands

fragez:   .dc.b     "? ",0             * INPUT command prompt ("? ")
errormark:.dc.b     13,"? ",0          * Error message prefix: CR + "? "
errtxt1:  .dc.b     " error",0         * Error message suffix: " error"
errtxt2:  .dc.b     " in line ",0      * Appended in program mode: " in line "

*==============================================================================
* Error Message String Table
* errortab: 64 longword pointers to null-terminated error message strings.
* Each entry corresponds to an error code (0..63). The error handler
* displays: "? " + errortab[code] + " error" [+ " in line " + linenum]
*==============================================================================
.even
errortab: .dc.l     err0,err1,err2,err3,err4,err5,err6,err7,err8,err9,err10
          .dc.l     err11,err12,err13,err14,err15,err16,err17,err18,err19
          .dc.l     err20,err21,err22,err23,err24,err25,err26,err27,err28
          .dc.l     err29,err30,err31,err32,err33,err34,err35,err36,err37
		.dc.l	err38,err39,err40,err41,err42,err43,err44,err45,err46
		.dc.l	err47,err48,err49,err50,err51,err52,err53,err54,err55
		.dc.l	err56,err57,err58,err59,err60,err61,err62,err63

* --- Error message strings (0..63) ---
err0:     .dc.b     "syntax",0                    * #0:  syntax error
err1:     .dc.b     "type mismatch",0             * #1:  wrong data type for operation
err2:     .dc.b     "invalid operand",0           * #2:  float: invalid operand
err3:     .dc.b     "inexact result",0            * #3:  float: inexact result
err4:     .dc.b     "square root of negative",0   * #4:  float: SQR of negative number
err5:     .dc.b     "log of negative number",0    * #5:  float: LOG/LN of negative number
err6:     .dc.b     "overflow",0                  * #6:  float: numeric overflow
err7:     .dc.b     "underflow",0                 * #7:  float: numeric underflow
err8:     .dc.b     "division by zero",0          * #8:  float: division by zero
err9:     .dc.b     "bad subscript",0             * #9:  array subscript out of range
err10:    .dc.b     "out of variable space",0     * #10: variable memory exhausted
err11:    .dc.b     "re-define",0                 * #11: variable/array already defined
err12:    .dc.b     "dim",0                       * #12: DIM statement error
err13:    .dc.b     "out of program space",0      * #13: program memory exhausted
err14:    .dc.b     "file create",0               * #14: GEMDOS Fcreate failed
err15:    .dc.b     "file write",0                * #15: GEMDOS Fwrite failed
err16:    .dc.b     "file open",0                 * #16: GEMDOS Fopen failed
err17:    .dc.b     "file read",0                 * #17: GEMDOS Fread failed
err18:    .dc.b     "illegal direct",0            * #18: command not allowed in direct mode
err19:    .dc.b     "next without for",0          * #19: NEXT found without matching FOR
err20:    .dc.b     "for-next overflow",0         * #20: FOR/NEXT stack overflow (>100 nested)
err21:    .dc.b     "illegal prg. mode",0         * #21: command not allowed in program mode
err22:    .dc.b     "return without gosub",0      * #22: RETURN found without matching GOSUB
err23:    .dc.b     "gosub-return overflow",0     * #23: GOSUB stack overflow (>100 nested)
err24:	.dc.b	"procedure overflow",0            * #24: procedure call stack overflow (>100 nested)
err25:    .dc.b     "if-then-else overflow",0     * #25: IF nesting overflow (>100 nested)
err26:    .dc.b     "prg stopped",0               * #26: program halted by STOP or Ctrl-C
err27:    .dc.b     "too many files open",0       * #27: file handle table full (>100 open)
err28:    .dc.b     "already open",0              * #28: file handle already in use
err29:    .dc.b     "out of data",0               * #29: READ past end of DATA
err30:    .dc.b     "can't continue",0            * #30: CONT not possible (program modified etc.)
err31:    .dc.b     "improper use of system variable",0  * #31: illegal assignment to PI/TI/TI$
err32:    .dc.b     "improper function number for gemdos/bios/xbios",0  * #32: bad syscall number
err33:    .dc.b     "variable not yet defined",0  * #33: variable referenced before assignment
err34:	.dc.b	"procedure not defined",0         * #34: PROC called but not found
err35:	.dc.b	"endproc without proc",0          * #35: ENDPROC without matching PROC
err36:	.dc.b	"line numbers missing",0          * #36: CONVERT source has no line numbers
err37:	.dc.b	"line too long",0                 * #37: line exceeds maximum length during CONVERT
err38:	.dc.b	"no negative arg allowed",0       * #38: negative argument not permitted
err39:	.dc.b	"no arg allowed",0                * #39: function/command takes no arguments
err40:	.dc.b	"too many args",0                 * #40: too many arguments supplied
err41:	.dc.b	"out of field range",0            * #41: AES/VDI array index out of range
err42:	.dc.b	"arg < 1",0                       * #42: argument must be >= 1
err43:	.dc.b	"cursor out of range",0           * #43: CURSOR x,y position out of screen bounds
err44:	.dc.b	"odd address access",0            * #44: word/long access at odd address
err45:	.dc.b	"position not within string",0    * #45: MID$/LEFT$/RIGHT$ position beyond string
err46:	.dc.b	"cant't find line number",0       * #46: GOTO/GOSUB target line not found
err47:	.dc.b	"arg too big",0                   * #47: argument value exceeds valid range
err48:	.dc.b	"fn not defined",0                * #48: DEF FN function not defined
err49:	.dc.b	"missing arg(s)",0                * #49: required argument(s) not supplied
err50:	.dc.b	"local definition",0              * #50: LOCAL used outside procedure
err51:	.dc.b	"illegal use as command",0        * #51: function-only token used as command
err52:	.dc.b	"else without for",0              * #52: ELSE without matching IF
err53:	.dc.b	"missing <then>",0                * #53: IF without THEN
err54:	.dc.b	"missing <to>",0                  * #54: FOR without TO
err55:	.dc.b	"illegal use as function",0       * #55: command-only token used as function
err56:	.dc.b	"out of string space",0           * #56: backwards string storage exhausted
err57:	.dc.b	"for without next",0              * #57: FOR loop has no matching NEXT
err58:	.dc.b	"gosub without return",0          * #58: GOSUB subroutine has no RETURN
err59:	.dc.b	"proc without endproc",0          * #59: PROC definition has no ENDPROC
err60:	.dc.b	"missing gosub",0                 * #60: ON...GOSUB target missing
err61:	.dc.b	"no such handle known",0          * #61: file handle not in handle table
err62:	.dc.b	"no BASIC file format",0          * #62: file is not in BASIC tokenized format
err63:	.dc.b	"improper procedure definition",0 * #63: malformed PROC definition

* --- Status messages for file operations ---
.even
savetext: .dc.b     13,"saving...",0              * Displayed during SAVE
.even
loadtext: .dc.b     13,"loading...",0             * Displayed during LOAD
.even
mergetext:.dc.b	13,"merging...",0                * Displayed during MERGE
.even
convtext:	.dc.b	13,"converting...",0            * Displayed during CONVERT
.even
joker     .dc.b     "*.*",0                       * Wildcard pattern for DIR command
.even

*==============================================================================
* Operator Dispatch Tables
*
* optabl:      13 longword pointers to operator handler routines
* optoktabl:   13 bytes: the ASCII character for each operator token
* oppriotabl:  13 bytes: operator priority (1=lowest, 13=highest)
*
* Index:  0    1    2    3    4    5    6    7    8    9   10   11   12
* Op:    ShL  ShR  Xor  And  Or   <    =    >    +    -    *    /    ^
* Char:  {    }    ~    &    |    <    =    >    +    -    *    /    ^
* Prio:  1    2    3    4    5    6    7    8    9   10   11   12   13
*==============================================================================
optabl:
          .dc.l     ShL,ShR,Xor,And,Or,Lower,Equal,Higher,Add,Sub,Mul,Div,Exponent
optoktabl:
          .dc.b     '{','}','~','&','|','<','=','>','+','-','*','/','^',0
oppriotabl:
          .dc.b      1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13
*                                        -   -   - Comparison ops (<,=,>) are checked
*                                                  directly in code (cmp #6)!


*==============================================================================
* Command / Token Dispatch Tables
*
* comadr:   Index array [0..3] pointing to comadr1/2/3 (token class 1xx/2xx/3xx)
* tokenadr: Index array [0..3] pointing to token1adr/2adr/3adr (token name tables)
*
* comadr1:  Command/function dispatch table for token class $01xx.
*           Each entry is a longword: routine_address OR'd with bit flags:
*             $80000000 = function (requires parenthesized argument)
*             $40000000 = program-mode only (error if in direct mode)
*             $20000000 = direct-mode only (error if in program mode)
*             $10000000 = dual: can be used as both command and function
*             $08000000 = no-parenthesis function (e.g. NOT, INKEY$, FN)
*             $88000000 = function + no-paren ($80000000|$08000000)
*==============================================================================
.even
comadr:	.dc.l	0,comadr1,comadr2,comadr3       * Dispatch table index [0,1xx,2xx,3xx]
tokenadr:
		.dc.l	0,token1adr,token2adr,token3adr   * Token name table index [0,1xx,2xx,3xx]

comadr1:
          .dc.l     Print                          * $0100 PRINT      - command
          .dc.l     Dim                            * $0101 DIM        - command
          .dc.l     List                           * $0102 LIST       - command
          .dc.l     Save                           * $0103 SAVE       - command
          .dc.l     Load                           * $0104 LOAD       - command
          .dc.l     Run                            * $0105 RUN        - command
          .dc.l     Clr                            * $0106 CLR        - command
          .dc.l     Goto                           * $0107 GOTO       - command
          .dc.l     Int+$80000000  * funktion      * $0108 INT        - function (requires parens)
          .dc.l     For                            * $0109 FOR        - command
          .dc.l     syntaxerr                      * $010A TO         - keyword (not standalone)
          .dc.l     syntaxerr * called by For only * $010B STEP       - keyword (only from FOR)
          .dc.l     Next                           * $010C NEXT       - command
          .dc.l     Endproc+$40000000              * $010D ENDPROC    - program-mode only
          .dc.l     Gosub	* gosub always works!  * $010E GOSUB      - command (works in both modes)
          .dc.l     Return+$40000000               * $010F RETURN     - program-mode only
          .dc.l     If                             * $0110 IF         - command
          .dc.l     syntaxerr * checked inside If  * $0111 THEN       - keyword (handled by IF)
          .dc.l     Else+$40000000                 * $0112 ELSE       - program-mode only
          .dc.l     Varfre+$80000000               * $0113 FRE        - function (free memory)
          .dc.l     Create                         * $0114 CREATE     - command (create file)
          .dc.l     Strfre+$80000000               * $0115 STRFRE     - function (free string space)
          .dc.l     Merge                          * $0116 MERGE      - command
          .dc.l     Rem                            * $0117 REM        - command (remark/comment)
          .dc.l     Stop                           * $0118 STOP       - command
          .dc.l     Help                           * $0119 HELP       - command
          .dc.l     New+$20000000                  * $011A NEW        - direct-mode only
          .dc.l     Deffn                          * $011B DEF FN     - command
          .dc.l     Fn+$88000000   * fkt, no paren * $011C FN         - function, no-paren (user fn)
          .dc.l     Input                          * $011D INPUT      - command
          .dc.l     On                             * $011E ON         - command (ON..GOTO/GOSUB)
          .dc.l     Open                           * $011F OPEN       - command
          .dc.l     Close                          * $0120 CLOSE      - command
          .dc.l     Spc+$80000000                  * $0121 SPC        - function (spaces in PRINT)
          .dc.l     Tab+$80000000                  * $0122 TAB        - function (tab in PRINT)
          .dc.l     dtonxtcmd+$40000000      * skip DATA in execution  * $0123 DATA - prg-mode only
          .dc.l     Read                           * $0124 READ       - command
          .dc.l     Restore+$40000000              * $0125 RESTORE    - program-mode only
          .dc.l     Get                            * $0126 GET        - command (get char from file)
          .dc.l     Len+$80000000                  * $0127 LEN        - function (string length)
          .dc.l     Str+$80000000                  * $0128 STR$       - function (number to string)
          .dc.l     Val+$80000000                  * $0129 VAL        - function (string to number)
          .dc.l     Function+$80000000             * $012A FUNCTION   - function
          .dc.l     Asc+$80000000                  * $012B ASC        - function (char to ASCII code)
          .dc.l     Chr+$80000000                  * $012C CHR$       - function (ASCII code to char)
          .dc.l     Left+$80000000                 * $012D LEFT$      - function
          .dc.l     Right+$80000000                * $012E RIGHT$     - function
          .dc.l     Mid+$80000000                  * $012F MID$       - function
          .dc.l     Pos+$80000000                  * $0130 POS        - function (cursor position)
          .dc.l     Not+$88000000                  * $0131 NOT        - function, no-paren
          .dc.l     Cmd                            * $0132 CMD        - command (redirect output)
          .dc.l     Poke                           * $0133 POKE       - command
          .dc.l     Peek+$80000000                 * $0134 PEEK       - function (read byte)
          .dc.l     Sin+$80000000                  * $0135 SIN        - function
          .dc.l     Cos+$80000000                  * $0136 COS        - function
          .dc.l     Sqr+$80000000                  * $0137 SQR        - function (square root)
          .dc.l     Log+$80000000                  * $0138 LOG        - function (log base 10)
          .dc.l     Ln+$80000000                   * $0139 LN         - function (natural log)
          .dc.l     Exp10+$80000000                * $013A EXP10      - function (10^x)
          .dc.l     Tan+$80000000                  * $013B TAN        - function
          .dc.l     Atn+$80000000                  * $013C ATN        - function (arctangent)
          .dc.l     Exp+$80000000                  * $013D EXP        - function (e^x)
          .dc.l     Sgn+$80000000                  * $013E SGN        - function (sign)
          .dc.l     Abs+$80000000                  * $013F ABS        - function (absolute value)
          .dc.l     Rnd+$80000000                  * $0140 RND        - function (random number)
          .dc.l     Sys                            * $0141 SYS        - command (system call)
          .dc.l     Cont+$20000000                 * $0142 CONT       - direct-mode only (continue)
          .dc.l     Cls                            * $0143 CLS        - command (clear screen)
          .dc.l     Dpeek+$80000000                * $0144 WPEEK      - function (read word)
          .dc.l     Dpoke                          * $0145 WPOKE      - command (write word)
          .dc.l     Lpeek+$80000000                * $0146 LPEEK      - function (read longword)
          .dc.l     Lpoke                          * $0147 LPOKE      - command (write longword)
          .dc.l     Atnpt+$80000000                * $0148 ATANPT     - function (atan2, 2-arg arctan)
          .dc.l     Mod+$80000000                  * $0149 MOD        - function (modulo)
          .dc.l     Gemdos+$80000000               * $014A GEMDOS     - function (GEMDOS trap #1)
          .dc.l     Bios+$80000000                 * $014B BIOS       - function (BIOS trap #13)
          .dc.l     Xbios+$80000000                * $014C XBIOS      - function (XBIOS trap #14)
          .dc.l     Varptr+$80000000               * $014D VARPTR     - function (variable address)
          .dc.l     Dir                            * $014E DIR        - command (directory listing)
          .dc.l     Hex+$80000000                  * $014F HEX$       - function (int to hex string)
          .dc.l     Bin+$80000000                  * $0150 BIN$       - function (int to binary str)
          .dc.l     Cursor                         * $0151 CURSOR     - command (set cursor pos)
		.dc.l	Proc                               * $0152 PROC       - command (procedure call)
		.dc.l	run2                               * $0153 END        - command (end program)
		.dc.l	Local+$40000000                    * $0154 LOCAL      - program-mode only
		.dc.l	Delete+$20000000                   * $0155 DELETE     - direct-mode only
		.dc.l	Inkey+$88000000                    * $0156 INKEY$     - function, no-paren
		.dc.l	Wait                               * $0157 WAIT       - command
		.dc.l	Swapvars                           * $0158 SWAP       - command (swap two variables)
		.dc.l	Tron                               * $0159 TRON       - command (trace on)
		.dc.l	Troff                              * $015A TROFF      - command (trace off)
		.dc.l	Instr+$80000000                    * $015B INSTR      - function (search in string)
		.dc.l	Call+$80000000                     * $015C CALL       - function (call machine code)
		.dc.l	Aesctrl+$10000000                  * $015D AESCTRL    - dual cmd/fkt (AES control)
		.dc.l	Aesintin                           * $015E AESINTIN   - command (set AES intin)
		.dc.l	Aesintout+$80000000                * $015F AESINTOUT  - function (read AES intout)
		.dc.l	Aesadrin                           * $0160 AESADRIN   - command (set AES addrin)
		.dc.l	Aesadrout+$80000000                * $0161 AESADROUT  - function (read AES addrout)
		.dc.l	Vdictrl+$10000000                  * $0162 VDICTRL    - dual cmd/fkt (VDI control)
		.dc.l	Vdiintin                           * $0163 VDIINTIN   - command (set VDI intin)
		.dc.l	Vdiintout+$80000000                * $0164 VDIINTOUT  - function (read VDI intout)
		.dc.l	Vdiptsin                           * $0165 VDIPTSIN   - command (set VDI ptsin)
		.dc.l	Vdiptsout+$80000000                * $0166 VDIPTSOUT  - function (read VDI ptsout)
		.dc.l	Aes                                * $0167 AES        - command (invoke AES call)
		.dc.l	Vdi                                * $0168 VDI        - command (invoke VDI call)
		.dc.l	Convert                            * $0169 CONVERT    - command (convert file)
		.dc.l	Dump                               * $016A DUMP       - command (dump variables)
		.dc.l	syntaxerr		* trace            * $016B TRACE      - reserved/unimplemented
		.dc.l	syntaxerr		* and              * $016C AND        - keyword (logical, parsed in expr)
		.dc.l	syntaxerr		* or               * $016D OR         - keyword (logical, parsed in expr)
		.dc.l	syntaxerr		* eor              * $016E EOR        - keyword (logical, parsed in expr)
		.dc.l	Auto+$20000000                     * $016F AUTO       - direct-mode only (auto line#)
		.dc.l	Edtab+$80000000                    * $0170 EDTAB      - function (editor tab setting)

* --- Token class $02xx dispatch (one entry) ---
comadr2:
          .dc.l     line                           * $0200 LINE (class 2) - internal line marker
* --- Token class $03xx dispatch (one entry) ---
comadr3:
		.dc.l	line                               * $0300 LINE (class 3) - internal line marker

*==============================================================================
* Token Number Table
* Lists the token constant values for all keywords, used by the tokenizer
* to map keyword strings to token codes. Three groups: 1xx, 2xx, 3xx.
*==============================================================================
*************** token 1xx
tokennr:
          .dc.w     PRINT,DIM,LIST,SAVE,LOAD,RUN,CLR,GOTO,INT_FKT,FOR,TO,STEP
          .dc.w     NEXT,ENDPROC,GOSUB,RETURN,IF,THEN,ELSE,FRE,CREATE,STRFRE
          .dc.w     MERGE,REM,STOP,HELP,NEW,DEFFN,FN,INPUT,ON,OPEN,CLOSE,SPC,TAB
          .dc.w     DATA,READ,RESTORE,GET,LEN,STRFKT,VAL,FUNCTION,ASC,CHR
          .dc.w     LEFT,RIGHT,MID,POS,NOT,CMD,POKE,PEEK,SIN,COS
          .dc.w     SQR,LOG,LN,EXP10,TAN,ATN,EXP,SGN,ABS,RND,SYS,CONT
          .dc.w     CLS,DPEEK,DPOKE,LPEEK,LPOKE,ATNPT,MOD,GEMDOS,BIOS,XBIOS
          .dc.w     VARPTR,DIR,HEX,BIN,CURSOR,PROC,END,LOCAL,DELETE,INKEY
		.dc.w	WAIT,SWAP,TRON,TROFF,INSTR,CALL
		.dc.w	AESCTRL,AESINTIN,AESINTOUT,AESADRIN,AESADROUT
		.dc.w	VDICTRL,VDIINTIN,VDIINTOUT,VDIPTSIN,VDIPTSOUT
		.dc.w	AES,VDI,CONVERT,DUMP,TRACE,AND,OR,EOR,AUTO,EDTAB
*************** token 2xx
          .dc.w     LINE2                          * Token class 2: LINE (variant 2)
*************** token 3xx
		.dc.w	LINE3                              * Token class 3: LINE (variant 3)
***************

*==============================================================================
* HELP Command Display Tables
* helpnadr: pointers to additional symbol strings shown by HELP command
* (operators, special syntax like "print#", "input#", "get#")
*==============================================================================
helpnadr: .dc.l     helpn1,helpn2,helpn3,helpn4,helpn5,helpn6,helpn7
          .dc.l     helpn8,helpn9,helpn10,helpn11,helpn12,helpn13
          .dc.l     helpn14,helpn15,helpn16,helpn17,helpn18,helpn19
          .dc.l	helpn20,helpn21

*==============================================================================
* Token Name Address Tables
* token1adr/2adr/3adr: arrays of pointers to the token name strings.
* Used by the tokenizer to match input text against keyword names,
* and by the de-tokenizer (LIST) to convert tokens back to text.
*==============================================================================
token1adr:
		* token 1xx
          .dc.l     comn1,comn2,comn3,comn4,comn5,comn6,comn7,comn8,comn9
          .dc.l     comn10,comn11,comn12,comn13,comn14,comn15,comn16
          .dc.l     comn17,comn18,comn19,comn20,comn21,comn22,comn23
          .dc.l     comn24,comn25,comn26,comn27,comn28,comn29,comn30
          .dc.l     comn31,comn32,comn33,comn34,comn35,comn36,comn37,comn38
          .dc.l     comn39,comn40,comn41,comn42,comn43,comn44,comn45
          .dc.l     comn46,comn47,comn48,comn49,comn50,comn51,comn52,comn53
          .dc.l     comn54,comn55,comn56,comn57,comn58,comn59,comn60,comn61
          .dc.l     comn62,comn63,comn64,comn65,comn66,comn67
          .dc.l     comn68,comn69,comn70,comn71,comn72,comn73,comn74
          .dc.l     comn75,comn76,comn77,comn78,comn79,comn80,comn81,comn82
		.dc.l	comn83,comn84,comn85,comn86,comn87,comn88,comn89
		.dc.l	comn90,comn91,comn92,comn93
		.dc.l	comn94,comn95,comn96,comn97,comn98,comn99
		.dc.l	comn100,comn101,comn102,comn103,comn104,comn105,comn106
		.dc.l	comn107,comn108,comn109,comn110,comn111,comn112,comn113
*************** token 2xx
token2adr:
          .dc.l     comn2_1                        * Token class 2: LINE (variant 2)
*************** token 3xx
token3adr:
		.dc.l	comn3_1                            * Token class 3: LINE (variant 3)
***************
          .dc.l     0                              * End-of-table sentinel


*==============================================================================
* HELP Command Symbol Strings
* These are special symbols and compound keywords displayed by HELP.
*==============================================================================
helpstr:
helpn1:   .dc.b     "$",0              * Hex prefix operator
helpn2:   .dc.b     "%",0              * Binary prefix operator
helpn3:   .dc.b     "pi",0             * PI system constant
helpn4:   .dc.b     "ti",0             * TI system variable (timer ticks)
helpn5:   .dc.b     "ti$",0            * TI$ system variable (time string)
helpn6:	.dc.b	"{",0                  * Shift-left operator
helpn7:	.dc.b	"}",0                  * Shift-right operator
helpn8:	.dc.b	"~",0                  * XOR operator
helpn9:   .dc.b     "&",0              * AND operator
helpn10:   .dc.b     "|",0             * OR operator
helpn11:   .dc.b     "<",0             * Less-than comparison
helpn12:   .dc.b     "=",0             * Equals comparison / assignment
helpn13:  .dc.b     ">",0              * Greater-than comparison
helpn14:  .dc.b     "+",0              * Addition operator
helpn15:  .dc.b     "-",0              * Subtraction / unary minus
helpn16:  .dc.b     "*",0              * Multiplication operator
helpn17:  .dc.b     "/",0              * Division operator
helpn18:  .dc.b     "^",0              * Exponentiation operator
helpn19:  .dc.b     "print#",0         * File PRINT command
helpn20:  .dc.b     "input#",0         * File INPUT command
helpn21:  .dc.b     "get#",0           * File GET command

*==============================================================================
* Token Name Strings
*
* ABBREVIATION ENCODING:
*   The first letter is always lowercase. Characters with bit 7 SET (>= $80)
*   mark the portion of the keyword that can be OMITTED when typing.
*   For example, "pRINT" means:
*     - Minimum abbreviation: "p" (just the first char, since 'R','I','N','T'
*       are all uppercase = mandatory displayed but bit7 chars mark optional)
*   Actually: lowercase first letter is always required. Uppercase letters
*   without bit7 are required. Letters with bit7 set ($80+char) are optional.
*   The tokenizer matches the minimum prefix.
*
*   Example: "dIm" -> 'd' required, 'I' has bit7 clear so 'I' is required
*            after 'd' ... actually the encoding is: first char lowercase =
*            always required, then uppercase chars after it form the rest.
*            Bit 7 set on a character means it is PAST the minimum abbreviation
*            point. So "lIst" means "l" is minimum, "IST" displayed but optional.
*==============================================================================
tokenstr:
******** token 1xx
comn1:    .dc.b     "print",0          * PRINT   - output to screen/file
comn2:    .dc.b     "dIm",0            * DIM     - dimension arrays (min: "dI")
comn3:    .dc.b     "lIst",0           * LIST    - list program lines (min: "lI")
comn4:    .dc.b     "sAve",0           * SAVE    - save program to file (min: "sA")
comn5:    .dc.b     "lOad",0           * LOAD    - load program from file (min: "lO")
comn6:    .dc.b     "rUn",0            * RUN     - execute program (min: "rU")
comn7:    .dc.b     "clr",0            * CLR     - clear all variables
comn8:    .dc.b     "gOto",0           * GOTO    - branch to line number (min: "gO")
comn9:    .dc.b     "inT",0            * INT     - truncate to integer (min: "inT")
comn10:   .dc.b     "fOr",0            * FOR     - begin FOR loop (min: "fO")
comn11:   .dc.b     "to",0             * TO      - FOR..TO keyword
comn12:   .dc.b     "sTep",0           * STEP    - FOR..STEP keyword (min: "sT")
comn13:   .dc.b     "nExt",0           * NEXT    - end of FOR loop (min: "nE")
comn14:   .dc.b     "eNdproc",0        * ENDPROC - end procedure definition (min: "eN")
comn15:   .dc.b     "goSub",0          * GOSUB   - call subroutine (min: "goS")
comn16:   .dc.b     "reTurn",0         * RETURN  - return from subroutine (min: "reT")
comn17:   .dc.b     "if",0             * IF      - conditional
comn18:   .dc.b     "tHen",0           * THEN    - IF..THEN keyword (min: "tH")
comn19:   .dc.b     "eLse",0           * ELSE    - IF..ELSE keyword (min: "eL")
comn20:   .dc.b     "fRe",0            * FRE     - free memory function (min: "fR")
comn21:   .dc.b     "cReate",0         * CREATE  - create file (min: "cR")
comn22:   .dc.b     "strFre",0         * STRFRE  - free string space function (min: "strF")
comn23:   .dc.b     "mErge",0          * MERGE   - merge program from file (min: "mE")
comn24:   .dc.b     "rEm",0            * REM     - remark/comment (min: "rE")
comn25:   .dc.b     "stOp",0           * STOP    - stop program execution (min: "stO")
comn26:   .dc.b     "hElp",0           * HELP    - display keyword list (min: "hE")
comn27:   .dc.b     "nEw",0            * NEW     - clear program and variables (min: "nE")
comn28:   .dc.b     "dEf",0            * DEF     - define function (DEF FN) (min: "dE")
comn29:   .dc.b     "fn",0             * FN      - call user-defined function
comn30:   .dc.b     "iNput",0          * INPUT   - read user input (min: "iN")
comn31:   .dc.b     "on",0             * ON      - ON..GOTO/GOSUB
comn32:   .dc.b     "oPen",0           * OPEN    - open file (min: "oP")
comn33:   .dc.b     "cLose",0          * CLOSE   - close file (min: "cL")
comn34:   .dc.b     "sPc",0            * SPC     - output spaces in PRINT (min: "sP")
comn35:   .dc.b     "tAb",0            * TAB     - tab to column in PRINT (min: "tA")
comn36:   .dc.b     "dAta",0           * DATA    - define inline data (min: "dA")
comn37:   .dc.b     "reAd",0           * READ    - read from DATA (min: "reA")
comn38:   .dc.b     "reStore",0        * RESTORE - reset DATA pointer (min: "reS")
comn39:   .dc.b     "gEt",0            * GET     - get single char from file (min: "gE")
comn40:   .dc.b     "lEn",0            * LEN     - string length function (min: "lE")
comn41:   .dc.b     "stR$",0           * STR$    - number to string function (min: "stR")
comn42:   .dc.b     "vAl",0            * VAL     - string to number function (min: "vA")
comn43:   .dc.b     "fUnction",0       * FUNCTION- function keyword (min: "fU")
comn44:   .dc.b     "aSc",0            * ASC     - character to ASCII code (min: "aS")
comn45:   .dc.b     "cHr$",0           * CHR$    - ASCII code to character (min: "cH")
comn46:   .dc.b     "leFt$",0          * LEFT$   - left substring (min: "leF")
comn47:   .dc.b     "rIght$",0         * RIGHT$  - right substring (min: "rI")
comn48:   .dc.b     "mId$",0           * MID$    - middle substring (min: "mI")
comn49:   .dc.b     "pos",0            * POS     - cursor position function
comn50:   .dc.b     "nOt",0            * NOT     - bitwise/logical NOT (min: "nO")
comn51:   .dc.b     "cMd",0            * CMD     - redirect output to file (min: "cM")
comn52:   .dc.b     "pOke",0           * POKE    - write byte to address (min: "pO")
comn53:   .dc.b     "pEek",0           * PEEK    - read byte from address (min: "pE")
comn54:   .dc.b     "sIn",0            * SIN     - sine function (min: "sI")
comn55:   .dc.b     "cos",0            * COS     - cosine function
comn56:   .dc.b     "sQr",0            * SQR     - square root function (min: "sQ")
comn57:   .dc.b     "log",0            * LOG     - base-10 logarithm function
comn58:   .dc.b     "ln",0             * LN      - natural logarithm function
comn59:   .dc.b     "exP10",0          * EXP10   - 10^x function (min: "exP")
comn60:   .dc.b     "tAn",0            * TAN     - tangent function (min: "tA")
comn61:   .dc.b     "aTn",0            * ATN     - arctangent function (min: "aT")
comn62:   .dc.b     "eXp",0            * EXP     - e^x function (min: "eX")
comn63:   .dc.b     "sGn",0            * SGN     - sign function (min: "sG")
comn64:   .dc.b     "aBs",0            * ABS     - absolute value function (min: "aB")
comn65:   .dc.b     "rNd",0            * RND     - random number function (min: "rN")
comn66:   .dc.b     "sYs",0            * SYS     - system call command (min: "sY")
comn67:   .dc.b     "cOnt",0           * CONT    - continue after STOP (min: "cO")
comn68:   .dc.b     "cls",0            * CLS     - clear screen
comn69:   .dc.b     "wpEek",0          * WPEEK   - read word from address (min: "wpE")
comn70:   .dc.b     "wpOke",0          * WPOKE   - write word to address (min: "wpO")
comn71:   .dc.b     "lpEek",0          * LPEEK   - read longword from address (min: "lpE")
comn72:   .dc.b     "lpOke",0          * LPOKE   - write longword to address (min: "lpO")
comn73:   .dc.b     "atAnpt",0         * ATANPT  - atan2 (two-argument arctangent) (min: "atA")
comn74:   .dc.b     "mOd",0            * MOD     - modulo function (min: "mO")
comn75:   .dc.b     "geMdos",0         * GEMDOS  - GEMDOS system call function (min: "geM")
comn76:   .dc.b     "bIos",0           * BIOS    - BIOS system call function (min: "bI")
comn77:   .dc.b     "xBios",0          * XBIOS   - XBIOS system call function (min: "xB")
comn78:   .dc.b     "varPtr",0         * VARPTR  - variable pointer function (min: "varP")
comn79:   .dc.b     "dir",0            * DIR     - directory listing command
comn80:   .dc.b     "heX$",0           * HEX$    - integer to hex string (min: "heX")
comn81:   .dc.b     "bIn$",0           * BIN$    - integer to binary string (min: "bI")
comn82:   .dc.b     "cUrsor",0         * CURSOR  - set cursor position (min: "cU")
comn83:	.dc.b	"prOc",0               * PROC    - call/define procedure (min: "prO")
comn84:	.dc.b	"end",0                * END     - end program
comn85:	.dc.b	"loCal",0              * LOCAL   - declare local variables (min: "loC")
comn86:	.dc.b	"deLete",0             * DELETE  - delete program lines (min: "deL")
comn87:	.dc.b	"inKey$",0             * INKEY$  - read key without waiting (min: "inK")
comn88:	.dc.b	"wAit",0               * WAIT    - pause execution (min: "wA")
comn89:	.dc.b	"sWap",0               * SWAP    - swap two variables (min: "sW")
comn90:	.dc.b	"tRon",0               * TRON    - trace on (min: "tR")
comn91:	.dc.b	"trOff",0              * TROFF   - trace off (min: "trO")
comn92:	.dc.b	"inStr$",0             * INSTR   - search string function (min: "inS")
comn93:	.dc.b	"cAll",0               * CALL    - call machine code (min: "cA")
comn94:	.dc.b	"aesCtrl",0            * AESCTRL - AES control array access (min: "aesC")
comn95:	.dc.b	"aesintIn",0           * AESINTIN  - AES intin array access (min: "aesintI")
comn96:	.dc.b	"aesintOut",0          * AESINTOUT - AES intout array access (min: "aesintO")
comn97:	.dc.b	"aesadrIn",0           * AESADRIN  - AES addrin array access (min: "aesadrI")
comn98:	.dc.b	"aesadrOut",0          * AESADROUT - AES addrout array access (min: "aesadrO")
comn99:	.dc.b	"vdiCtrl",0            * VDICTRL - VDI control array access (min: "vdiC")
comn100:	.dc.b	"vdiintIn",0       * VDIINTIN  - VDI intin array access (min: "vdiintI")
comn101:	.dc.b	"vdiintOut",0      * VDIINTOUT - VDI intout array access (min: "vdiintO")
comn102:	.dc.b	"vdiptsIn",0       * VDIPTSIN  - VDI ptsin array access (min: "vdiptsI")
comn103:	.dc.b	"vdiptsOut",0      * VDIPTSOUT - VDI ptsout array access (min: "vdiptsO")
comn104:	.dc.b	"aEs",0            * AES     - invoke AES call (min: "aE")
comn105:	.dc.b	"vDi",0            * VDI     - invoke VDI call (min: "vD")
comn106:	.dc.b	"coNvert",0        * CONVERT - convert file format (min: "coN")
comn107:	.dc.b	"dUmp",0           * DUMP    - dump variables (min: "dU")
comn108:	.dc.b	"trAce",0          * TRACE   - trace mode (unimplemented) (min: "trA")
comn109:	.dc.b	"aNd",0            * AND     - logical AND operator (min: "aN")
comn110:	.dc.b	"or",0             * OR      - logical OR operator
comn111:	.dc.b	"eOr",0            * EOR     - logical XOR operator (min: "eO")
comn112:	.dc.b	"aUto",0           * AUTO    - auto line numbering (min: "aU")
comn113:	.dc.b	"eDtab",0          * EDTAB   - editor tab setting (min: "eD")

*************** token 2xx
comn2_1:  .dc.b     "line2",0          * LINE (class 2) - internal line marker
*************** token 3xx
comn3_1:	.dc.b	"line3",0          * LINE (class 3) - internal line marker
***************
          .dc.b     0                  * End-of-table sentinel

*==============================================================================
* System Call Parameter Tables
*
* These tables describe the parameter signatures for GEMDOS, BIOS, and XBIOS
* calls so the interpreter can automatically push the correct types/sizes.
*
* TABLE FORMAT:
*   First word: number of entries (functions) in the table
*   Then N longword pointers to parameter descriptors (-1 = unsupported)
*   Each parameter descriptor is a sequence of words:
*     INT,0  = push a word-sized integer parameter
*     INT,1  = push a longword-sized integer parameter
*     STRING,1 = push a longword string pointer parameter
*     0      = end of parameter list (no more parameters)
*
* The BASIC interpreter reads these descriptors to know how many parameters
* to evaluate and how to push them onto the stack before executing TRAP.
*==============================================================================

.even
                .ds.w   1              * Alignment padding
.even
* Structure of gemdtbl, biostbl, xbiostbl entries: 1(STRING/INT), 2(0=.W/1=.L)

*------------------------------------------------------------------------------
* GEMDOS Function Parameter Table (TRAP #1)
* 0x58 = 88 entries, indexed by GEMDOS function number (0x00..0x57)
*------------------------------------------------------------------------------
gemdtbl:
     .dc.w     $58  * $58 (88) entries in this table
*    Pointers to parameter descriptors, indexed by GEMDOS function number:
*    Fn# $00    $01    $02    $03    $04    $05    $06    $07    $08    $09    $0A    $0B    $0C    $0D
     .dc.l     Gt1,Gt2,Gt3,Gt4,Gt5,Gt6,Gt7,Gt8,Gt9,Gt10,Gt11,Gt12,-1,-1
*    Fn# $0E    $0F    $10    $11    $12    $13    $14-$18                    $19    $1A
     .dc.l     Gt13,-1,Gt14,Gt15,Gt16,Gt17,-1,-1,-1,-1,-1,Gt18,Gt19
*    Fn# $1B-$1F                              $20    $21-$29                                      $2A    $2B
     .dc.l     -1,-1,-1,-1,-1,Gt20,-1,-1,-1,-1,-1,-1,-1,-1,-1,Gt21,Gt22
*    Fn# $2C    $2D    $2E    $2F    $30    $31    $32-$35                    $36
     .dc.l     Gt23,Gt24,-1,Gt25,Gt26,Gt27,-1,-1,-1,-1,Gt28,-1,-1,Gt29
*    Fn# $39    $3A    $3B    $3C    $3D    $3E    $3F    $40    $41    $42    $43    $44
     .dc.l     Gt30,Gt31,Gt32,Gt33,Gt34,Gt35,Gt36,Gt37,Gt38,Gt39,-1
*    Fn# $45    $46    $47    $48    $49    $4A    $4B    $4C    $4D    $4E    $4F
     .dc.l     Gt40,Gt41,Gt42,Gt43,Gt44,Gt45,Gt46,Gt47,Gt48,Gt49
*    Fn# $50-$55                                      $56    $57
     .dc.l     -1,-1,-1,-1,-1,-1,Gt50,Gt51

* --- Individual GEMDOS parameter descriptors ---
Gt1  .dc.w     0                           * $00 Pterm0    - Terminate process (no params)
Gt2  .DC.W     0                           * $01 Cconin    - Read char from stdin (no params)
Gt3  .DC.W     INT,0, 0                    * $02 Cconout   - Write char to stdout (word: char)
Gt4  .DC.W     0                           * $03 Cauxin    - Read char from AUX: (no params)
Gt5  .DC.W     INT,0, 0                    * $04 Cauxout   - Write char to AUX: (word: char)
Gt6  .DC.W     INT,0, 0                    * $05 Cprnout   - Write char to PRN: (word: char)
Gt7  .DC.W     INT,0, 0                    * $06 Crawcin   - Raw console I/O (word: char)
Gt8  .DC.W     0                           * $07 Crawcin(direct) - Direct console input (no params)
Gt9  .DC.W     0                           * $08 Cnecin    - Console input, no echo (no params)
Gt10 .DC.W     STRING,1, 0                 * $09 Cconws    - Write string to stdout (long: string ptr)
Gt11 .DC.W     INT,1, 0                    * $0A Cconrs    - Read edited string (long: buffer ptr)
Gt12 .DC.W     0                           * $0B Cconis    - Console input status (no params)
Gt13 .DC.W     INT,0, 0                    * $0E Dsetdrv   - Set default drive (word: drive#)
Gt14 .DC.W     0                           * $10 Cconos    - Console output status (no params)
Gt15 .DC.W     0                           * $11 Cprnos    - Printer output status (no params)
Gt16 .DC.W     0                           * $12 Cauxis    - AUX: input status (no params)
Gt17 .DC.W     0                           * $13 Cauxos    - AUX: output status (no params)
Gt18 .DC.W     0                           * $19 Dgetdrv   - Get default drive (no params)
Gt19 .DC.W     INT,1, 0                    * $1A Fsetdta   - Set DTA address (long: address)
Gt20 .DC.W     INT,1, 0                      * $20 Super   - Get/set supervisor mode (long: sp/flag)
Gt21 .DC.W     0                             * $2A Tgetdate - Get date (no params)
Gt22 .DC.W     INT,0, 0                      * $2B Tsetdate - Set date (word: date)
Gt23 .DC.W     0                             * $2C Tgettime - Get time (no params)
Gt24 .DC.W     INT,0, 0                      * $2D Tsettime - Set time (word: time)
Gt25 .DC.W     0                             * $2F Fgetdta  - Get DTA address (no params)
Gt26 .DC.W     0                             * $30 Sversion - Get GEMDOS version (no params)
Gt27 .DC.W     INT,1, INT,0, 0               * $31 Ptermres - Terminate & stay resident (long: keepcnt, word: retcode)
Gt28 .DC.W     INT,1, INT,0, 0               * $36 Dfree    - Get disk free space (long: buffer, word: drive)
Gt29 .DC.W     STRING,1, 0                   * $39 Dcreate  - Create directory (long: path string)
Gt30 .DC.W     STRING,1, 0                   * $3A Ddelete  - Delete directory (long: path string)
Gt31 .DC.W     STRING,1, 0                   * $3B Dsetpath - Set current directory (long: path string)
Gt32 .DC.W     STRING,1, INT,0, 0            * $3C Fcreate  - Create file (long: filename, word: attr)
Gt33 .DC.W     STRING,1, INT,0, 0            * $3D Fopen    - Open file (long: filename, word: mode)
Gt34 .DC.W     INT,0, 0                      * $3E Fclose   - Close file (word: handle)
Gt35 .DC.W     INT,0, INT,1, INT,1, 0        * $3F Fread    - Read from file (word: handle, long: count, long: buffer)
Gt36 .DC.W     INT,0, INT,1, INT,1, 0        * $40 Fwrite   - Write to file (word: handle, long: count, long: buffer)
Gt37 .DC.W     STRING,1, 0                   * $41 Fdelete  - Delete file (long: filename)
Gt38 .DC.W     INT,1, INT,0, INT,0, 0        * $42 Fseek    - Seek file pointer (long: offset, word: handle, word: mode)
Gt39 .DC.W     STRING,1, INT,0, INT,0, 0     * $43 Fattrib  - Get/set file attributes (long: fname, word: flag, word: attr)
Gt40 .DC.W     INT,0, 0                      * $45 Fdup     - Duplicate file handle (word: handle)
Gt41 .DC.W     INT,0 ,INT,0, 0               * $46 Fforce   - Force file handle (word: stdh, word: nonstdh)
Gt42 .DC.W     INT,1, INT,0, 0               * $47 Dgetpath - Get current directory (long: buffer, word: drive)
Gt43 .DC.W     INT,1, 0                      * $48 Malloc   - Allocate memory (long: amount)
Gt44 .DC.W     INT,1, 0                      * $49 Mfree    - Release memory (long: address)
Gt45 .DC.W     INT,0, INT,1, INT,1, 0        * $4A Mshrink  - Shrink allocated block (word: 0, long: addr, long: newsize)
Gt46 .DC.W     INT,0, STRING,1, STRING,1, STRING,1, 0  * $4B Pexec - Load/exec process (word: mode, long: fname, long: cmdline, long: envstr)
Gt47 .DC.W     INT,0, 0                      * $4C Pterm    - Terminate process (word: retcode)
Gt48 .DC.W     STRING,1, INT,0, 0            * $4E Fsfirst  - Search first (long: filespec, word: attr)
Gt49 .DC.W     0                             * $4F Fsnext   - Search next (no params)
Gt50 .DC.W     INT,0, STRING,1, STRING,1, 0  * $56 Frename  - Rename file (word: 0, long: oldname, long: newname)
Gt51 .DC.W     INT,0, INT,1, INT,0, 0        * $57 Fdatime  - Get/set file timestamp (word: handle, long: buffer, word: flag)

*------------------------------------------------------------------------------
* BIOS Function Parameter Table (TRAP #13)
* 12 entries, indexed by BIOS function number (0..11)
*------------------------------------------------------------------------------
biostbl:
     .dc.w     12   * 12 entries in this table
     .dc.l     bt1,bt2,bt3,bt4,bt5,bt6,bt7,bt8,bt9,bt10,bt11,bt12
bt1  .DC.W     INT,1, 0                      * #0  Getmpb   - Get memory parameter block (long: buffer)
bt2  .DC.W     INT,0, 0                      * #1  Bconstat - Char device input status (word: device)
bt3  .DC.W     INT,0, 0                      * #2  Bconin   - Read char from device (word: device)
bt4  .DC.W     INT,0, INT,0, 0               * #3  Bconout  - Write char to device (word: device, word: char)
bt5  .DC.W     INT,0, INT,1, INT,0, INT,0, INT,0, 0    * #4  Rwabs - Read/write disk sectors (word: rwflag, long: buf, word: count, word: recno, word: dev)
bt6  .DC.W     INT,0, INT,1, 0               * #5  Setexc   - Set exception vector (word: vecnum, long: vec)
bt7  .DC.W     0                             * #6  Tickcal  - Get timer calibration (no params)
bt8  .DC.W     INT,0, 0                      * #7  Getbpb   - Get BIOS parameter block (word: device)
bt9  .DC.W     INT,0, 0                      * #8  Bcostat  - Device output status (word: device)
bt10 .DC.W     INT,0, 0                      * #9  Mediach  - Inquire media change (word: device)
bt11 .DC.W     INT,1, 0                      * #10 Drvmap   - Return drive bitmap (long: dummy -- actually no params, but table says long)
bt12 .DC.W     INT,0, 0                      * #11 Kbshift  - Get/set shift key state (word: mode)

*------------------------------------------------------------------------------
* XBIOS Function Parameter Table (TRAP #14)
* 40 entries, indexed by XBIOS function number (0..39)
*------------------------------------------------------------------------------
xbiostbl:
     .dc.w     40   * 40 entries in this table
*    Pointers indexed by XBIOS function number:
*    #0      #1     #2     #3     #4     #5     #6     #7     #8     #9     #10    #11(-)  #12
     .dc.l     xt1,xt2,xt3,xt4,xt5,xt6,xt7,xt8,xt9,xt10,xt11,-1,xt12
*    #13     #14    #15    #16    #17    #18    #19    #20    #21    #22
     .dc.l     xt13,xt14,xt15,xt16,xt17,xt18,xt19,xt20,xt21,xt22
*    #23     #24    #25    #26    #27    #28    #29    #30    #31    #32
     .dc.l     xt23,xt24,xt25,xt26,xt27,xt28,xt29,xt30,xt31,xt32
*    #33     #34    #35    #36    #37    #38    #39
     .dc.l     xt33,xt34,xt35,xt36,xt37,xt38,xt39

* --- Individual XBIOS parameter descriptors ---
xt1  .DC.W     INT,0, INT,1, INT,1, 0        * #0  Initmouse  - Init mouse handler (word: type, long: param, long: vec)
xt2  .DC.W     INT,1, 0                      * #1  Ssbrk      - Reserve memory at top (long: amount)
xt3  .DC.W     0                             * #2  Physbase   - Get physical screen base (no params)
xt4  .DC.W     0                             * #3  Logbase    - Get logical screen base (no params)
xt5  .DC.W     0                             * #4  Getrez     - Get screen resolution (no params)
xt6  .DC.W     INT,1, INT,1, INT,0, 0        * #5  Setscreen  - Set screen addresses/rez (long: log, long: phys, word: rez)
xt7  .DC.W     INT,1, 0                      * #6  Setpalette - Set all palette registers (long: palette ptr)
xt8  .DC.W     INT,0, INT,0 ,0               * #7  Setcolor   - Set one palette register (word: reg, word: color)
xt9  .DC.W     INT,1, INT,1, INT,0, INT,0, INT,0, INT,0, INT,0, 0  * #8  Floprd - Read floppy sectors (long: buf, long: filler, word: dev, word: sect, word: track, word: side, word: count)
xt10 .DC.W     INT,1, INT,1, INT,0, INT,0, INT,0, INT,0, INT,0, 0  * #9  Flopwr - Write floppy sectors (long: buf, long: filler, word: dev, word: sect, word: track, word: side, word: count)
xt11 .DC.W     INT,1, INT,1, INT,0, INT,0, INT,0, INT,0, INT,0
     .dc.w     INT,1, INT,0, 0               * #10 Flopfmt   - Format floppy track (long: buf, long: filler, word: dev, word: spt, word: track, word: side, word: interlv, long: magic, word: virgin)
xt12 .DC.W     INT,0, INT,1, 0               * #12 Midiws    - Write string to MIDI (word: cnt, long: ptr) [#11 unused]
xt13 .DC.W     INT,0, INT,1, 0               * #13 Mfpint    - Set MFP interrupt vector (word: intnum, long: vector)
xt14 .DC.W     INT,0, 0                      * #14 Iorec     - Get I/O buffer record (word: device)
xt15 .DC.W     INT,0, INT,0, INT,0, INT,0, INT,0, INT,0, 0  * #15 Rsconf - Configure RS-232 (word: speed, word: flow, word: ucr, word: rsr, word: tsr, word: scr)
xt16 .DC.W     INT,1, INT,1, INT,1, 0        * #16 Keytbl    - Get/set keyboard tables (long: unshift, long: shift, long: caps)
xt17 .DC.W     0                             * #17 Random    - Get 24-bit random number (no params)
xt18 .DC.W     INT,1, INT,1, INT,0, INT,0, 0 * #18 Protobt   - Produce boot sector (long: buf, long: serial, word: disktype, word: execflag)
xt19 .DC.W     INT,1, INT,1, INT,0, INT,0, INT,0, INT,0, INT,0, 0  * #19 Flopver - Verify floppy sectors (long: buf, long: filler, word: dev, word: sect, word: track, word: side, word: count)
xt20 .DC.W     0                             * #20 Scrdmp    - Screen dump to printer (no params)
xt21 .DC.W     INT,0, INT,0, 0               * #21 Cursconf  - Configure text cursor (word: func, word: rate)
xt22 .DC.W     INT,1, 0                      * #22 Settime   - Set system date/time (long: datetime)
xt23 .DC.W     0                             * #23 Gettime   - Get system date/time (no params)
xt24 .DC.W     0                             * #24 Bioskeys  - Restore default keyboard tables (no params)
xt25 .DC.W     INT,0, INT,1, 0               * #25 Ikbdws    - Write to IKBD (word: count, long: buffer)
xt26 .DC.W     INT,0, 0                      * #26 Jdisint   - Disable MFP interrupt (word: intnum)
xt27 .DC.W     INT,0 ,0                      * #27 Jenabint  - Enable MFP interrupt (word: intnum)
xt28 .DC.W     INT,0, INT,0, 0               * #28 Giaccess  - Access sound chip (word: data, word: register)
xt29 .DC.W     INT,0, 0                      * #29 Offgibit  - Reset bit in GI port A (word: bitno)
xt30 .DC.W     INT,0, 0                      * #30 Ongibit   - Set bit in GI port A (word: bitno)
xt31 .DC.W     INT,0, INT,0, INT,0, INT,1, 0 * #31 Xbtimer  - Set MFP timer (word: timer, word: ctrl, word: data, long: vector)
xt32 .DC.W     INT,1, 0                      * #32 Dosound   - Set sound parameters (long: soundcmd ptr)
xt33 .DC.W     INT,0 ,0                      * #33 Setprt    - Configure printer (word: config)
xt34 .DC.W     0                             * #34 Kbdvbase  - Get keyboard vector table (no params)
xt35 .DC.W     INT,0, INT,0, 0               * #35 Kbrate    - Set keyboard repeat rate (word: initial, word: repeat)
xt36 .DC.W     INT,1, 0                      * #36 Prtblk    - Print graphics block (long: pblk ptr)
xt37 .DC.W     0                             * #37 Vsync     - Wait for vertical sync (no params)
xt38 .DC.W     INT,1, 0                      * #38 Supexec   - Execute in supervisor mode (long: code ptr)
xt39 .DC.W     0                             * #39 Puntaes   - Discard AES, free RAM (no params)

*==============================================================================
* Miscellaneous Data
*==============================================================================
.even
leer_str:      .dc.l    0          * Empty string content (4 zero bytes = empty reversed string)
.even

*==============================================================================
* AES and VDI Parameter Blocks
*
* AESPB: 6 longword pointers passed to AES via trap. Points to:
*   control, global, intin, intout, addrin, addrout arrays in BSS.
*
* VDIPB: 5 longword pointers passed to VDI via trap. Points to:
*   control, intin, ptsin, intout, ptsout arrays in BSS.
*==============================================================================
AESPB:	.dc.l	AESctrl,AESglobal,AESintin,AESintout,AESadrin,AESadrout
VDIPB:	.dc.l	VDIctrl,VDIintin,VDIptsin,VDIintout,VDIptsout


*==============================================================================
* BSS Section -- Uninitialized Runtime Variables
*
* All interpreter state variables, stacks, and buffers. Everything here
* is zeroed at startup and used at runtime.
*==============================================================================
.bss

* --- Array Handling State ---
arrayfl   .ds.b     1              * Flag: if set, current variable is an array
.even
arraydeep .ds.l     1              * Number of dimensions in current array access
arraylen  .ds.l     10             * Lengths of each dimension (max 10 dimensions)
array2len	.ds.l	10             * Copy of dimension lengths (used for element calculation)

* --- Output and Timer State ---
putfl     .ds.w     1              * Flag: if set, put_string ignores line overflow
          .ds.w     1              * (padding/alignment)
tiint:    .ds.l     1              * TI integer value (VBL frame counter from $466 = _frclock, ~70 Hz)
tistring: .ds.b     10             * TI$ string buffer (10 chars: "HH:MM:SS" + padding)
tistrend:                          * End marker for tistring (tisptr points here - 1)

* --- Type System State ---
typvalid: .ds.w     1              * Type validity flag (whether current type is known)
typflag   .ds.w     1              * Current expression type: FLOAT=1, INT=2, STRING=4
typ2flag  .ds.w     1              * Secondary type flag (used in binary operations)

* --- Expression Evaluator State ---
operator  .ds.w     1              * Current operator number (index into optabl)
handle    .ds.w     1              * Current file handle for I/O operations

* --- Execution Position ---
akt_zeile .ds.l     1                   * Current BASIC line number being executed
b_modus   .ds.w     1                   * BASIC mode: 0=direct mode, -1=program mode
akt_adr   .ds.l     1                   * Address of current line in program memory

* --- FOR/NEXT and GOSUB Stack Pointers ---
foreptr   .ds.l     1              * Pointer to current position in FOR/NEXT stack (fortable)
goseptr   .ds.l     1              * Pointer to current position in GOSUB stack (gostabl)

* --- Comparison and Work Variables ---
follchar  .ds.w     1                   * Character following a comparison operator
work1     .ds.l     1                   * Temp work area (e.g. copy of str_pufend)
typ3flag  .ds.w     1                   * Tertiary type flag (for multi-operand expressions)
workop    .ds.w     1                   * Saved operator during expression evaluation

* --- IF/THEN/ELSE State ---
ifendptr  .ds.l     1              * Pointer to current position in IF stack (iftbl)
ifcnt     .ds.w     1                   * Count of nested IFs in the current line

* --- Function/Argument Flags ---
fnvarfl   .ds.w     1                   * 0=normal variable, 13/14=DEF FN function variable
argfl     .ds.w     1                   * 0=normal var, -1=check argument variable first

* --- More Work/Temp Variables ---
work2     .ds.l     1                   * Temp work area (e.g. copy of a0)
inptr     .ds.l     1              * Pointer into input buffer during INPUT parsing
onarg     .ds.l     1              * ON..GOTO/GOSUB: the computed branch argument
oncmd     .ds.w     1              * ON..GOTO/GOSUB: which command (GOTO or GOSUB)

* --- File I/O State ---
filefl    .ds.w     1              * File output flag: if set, output goes to file
cmdfl     .ds.w     1              * CMD flag: if set, CMD is active (output redirected)

* --- DATA/READ Pointers ---
dataptr   .ds.l     1                   * Pointer to next DATA element to be read
dataadr   .ds.l     1                   * Address of the line containing current DATA element
restadr   .ds.l     1                   * Saved address for RESTORE command

* --- Trace and CONT State ---
traceline	.ds.l	1              * Line number being traced (TRON/TROFF)
contline  .ds.l     1              * CONT: saved line number (-1 = can't continue)
contladr  .ds.l     1              * CONT: saved line address
contadr   .ds.l     1              * CONT: saved parse pointer (a0)

* --- System Variable State ---
sysvar    .ds.w     1                   * System variable ID: 0=none, -1=PI, -2=TI, -3=TI$
sysallow  .ds.w     1              * System variable permission flag
spstr     .ds.l     1              * Temporary string pointer

* --- Garbage Collector State ---
savereg   .ds.l     16                  * Register save area during garbage collection (d0-d7/a0-a7)
pgarbend  .ds.l     1              * End of program area for garbage collector
sbase     .ds.l     1              * Saved stack base

* --- String Buffer Pointers ---
str_puf   .ds.l     1              * Start of temporary string assembly buffer
str_pufend .ds.l    1              * End of temporary string assembly buffer

str_ptr   .ds.l     1              * Pointer to most recently stored string in string space

* --- Keyboard Input ---
key:      .ds.l     1              * Last key press (longword: scancode+ASCII)
key2:     .ds.w     1              * Secondary key buffer

* --- DTA and Variable Name Buffers ---
dta_puf   .ds.b     50             * DTA buffer for Fsfirst/Fsnext (50 bytes = DTA structure)
var_name  .ds.b     80                  * Current variable name buffer (max 80 characters)
var2_name .ds.b     512                 * Copy of variable name (when expanded/qualified)

* --- Input Buffers ---
inputpuf  .ds.b     256            * Primary input buffer (256 bytes, used by INPUT/expressions)
inputepuf:.ds.w	1                  * End marker for inputpuf
input_puf .ds.b     256            * Secondary input buffer (256 bytes, used for file input)
inpuf_end .ds.w     1                   * End marker for a BASIC line buffer
          .ds.b     256                 * Extra 256 bytes for expanded abbreviated commands
inpuf2_end .ds.w    1              * End marker for expanded buffer

* --- Mirror Buffer (for reversed string operations) ---
mirrorpuf	.ds.b	512				* Buffer for storing reversed (mirrored) strings (512 bytes)
mirrorpend:                        * End marker for mirrorpuf

* --- Interpreter Stack ---
* 5000 longwords = 20000 bytes. The interpreter uses its own stack
* separate from the system stack for expression evaluation and control flow.
sp_base:  .ds.l     5000           * Interpreter stack base (20000 bytes = 5000 longs)
stack:    .ds.l     1              * Stack top marker
          .ds.l     1              * 4 zero bytes (safety margin / sentinel)

* --- FOR/NEXT Stack ---
* Each FOR entry is 42 bytes (variable ptr, step, limit, line addr, etc.)
* Supports up to 100 nested FOR/NEXT loops: 100 * 42 = 4200 bytes
fortable  .ds.b     100*42         * FOR/NEXT stack (100 entries x 42 bytes = 4200 bytes)
endfortbl      .ds.w     1        * End sentinel for fortable

* --- GOSUB Stack ---
* Each GOSUB entry is 12 bytes (return address, line number, parse ptr)
* Supports up to 100 nested GOSUBs: 100 * 12 = 1200 bytes
gostabl   .ds.b     100*12         * GOSUB stack (100 entries x 12 bytes = 1200 bytes)
endgostabl     .ds.w     1        * End sentinel for gostabl

* --- IF Stack ---
* Each IF entry is 4 bytes (pointer to ELSE/ENDIF)
* Supports up to 100 nested IFs: 100 * 4 = 400 bytes
iftbl:    .ds.b     100*4          * IF/THEN/ELSE stack (100 entries x 4 bytes = 400 bytes)
endiftbl:      .ds.w     1        * End sentinel for iftbl

* --- File Handle Table ---
* Each entry is 4 bytes (GEMDOS handle + flags)
* Supports up to 100 simultaneously open files: 100 * 4 = 400 bytes
handtab:  .ds.b     100*4          * File handle table (100 entries x 4 bytes = 400 bytes)
endhtab:       .ds.w     1        * End sentinel for handtab

* --- String Protection Stack (qlist) ---
* 250 longword entries for protecting strings from garbage collection.
* When a string is in use during expression evaluation, its address is
* pushed here so the garbage collector won't reclaim it.
qlist     .ds.l     250            * String protection stack (250 entries x 4 bytes = 1000 bytes)

* --- Editor State ---
maxspalten:                        * Maximum columns in editor (stored as longword)
          .ds.l     1

* --- DEF FN State ---
fncnt:    .ds.w     1              * DEF FN: count of function parameters
fntyp:	.ds.w	1                  * DEF FN: return type of current function

* --- Procedure Stack ---
* proctblptr: current position pointer into proctbl
* Each procedure entry is 14 bytes (procedure name hash, return address, etc.)
* Supports up to 100 nested procedure calls: 100 * 14 = 1400 bytes
proctblptr:	.ds.l	1              * Current pointer into procedure stack
proctbl:		.ds.b	100*14     * Procedure stack (100 entries x 14 bytes = 1400 bytes)
procetbl:		.ds.w	1          * End sentinel for proctbl

* --- Command/Function Mode Flag ---
cmdfktfl:		.ds.w	1          * Indicates whether current token is cmd or fkt

*==============================================================================
* AES Communication Arrays
* Used by AES() command. The AESPB parameter block points to these.
*==============================================================================
AESctrl:	.ds.w	10             * AES control array (10 words = 20 bytes)
AESintin:	.ds.w	128            * AES integer input array (128 words = 256 bytes)
AESintout:.ds.w	128                * AES integer output array (128 words = 256 bytes)
AESadrin:	.ds.l	128            * AES address input array (128 longs = 512 bytes)
AESadrout:.ds.l	128                * AES address output array (128 longs = 512 bytes)

*==============================================================================
* VDI Communication Arrays
* Used by VDI() command. The VDIPB parameter block points to these.
*==============================================================================
VDIctrl:	.ds.w	12             * VDI control array (12 words = 24 bytes)
VDIintin:	.ds.w	128            * VDI integer input array (128 words = 256 bytes)
VDIintout:.ds.w	128                * VDI integer output array (128 words = 256 bytes)
VDIptsin:	.ds.w	128            * VDI coordinate input array (128 words = 256 bytes)
VDIptsout:.ds.w	128                * VDI coordinate output array (128 words = 256 bytes)

*==============================================================================
* AES Global Array
*==============================================================================
AESglobal:.ds.l	10                 * AES global array (10 longs = 40 bytes, filled by appl_init)

* --- Trace Cursor Position ---
trx:	.ds.w	1                      * Saved cursor X position during trace
try:	.ds.w     1                    * Saved cursor Y position during trace

* --- AUTO Command State ---
autozeile:	.ds.l	1              * AUTO: current auto-generated line number
autoadd:		.ds.l	1          * AUTO: line number increment value
