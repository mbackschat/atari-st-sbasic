*==============================================================================
* HEADER.S — Program Entry Point, Initialization & STAD Interface
*==============================================================================
* Date: 3.11.88
* This is the main entry point for the BASIC interpreter. It can operate
* standalone or be embedded via the STAD interface (a structure-based API
* that allows an external program to initialize, edit, and run BASIC code).
*
* Exports:
*   edibase  — Pointer to the STAD/editor structure (see field offsets below)
*   initcode — Pointer to Init routine (for STAD embedding)
*   editcode — Pointer to Edit routine (for STAD embedding)
*   runcode  — Pointer to Run routine (for STAD embedding)
*
* External dependencies:
*   BASIC.S:  b_init, b_runcode, b_preup, b_predown, b_up, b_down, ipka_
*   EDITOR.S: ed_editor, ed_clrmem
*   DATA.S:   editscreen, prgbase, prgend, varbase, varend, strbase, strend
*==============================================================================

* STAD/BASIC interface
* Header ohne STAD / 3.11.88
.globl edibase,initcode,editcode,runcode

MINFREE equ     $800            * Minimum free memory required (2048 bytes)

*==============================================================================
* Editor/STAD Structure Definition (31.10.88)
*==============================================================================
* This structure is the central communication block between the editor,
* the BASIC interpreter, and any external STAD host. It holds screen
* parameters, callback pointers, and rendering info.
*
* Total size: edi_y_shft + 4 = approx 80 bytes
*==============================================================================
edi_base        equ     0               * [long] Physical screen base address (framebuffer pointer)
edi_screen      = edi_base+4            * [long] Screen width in bytes (e.g., 80 for 640px mono)
edi_plan        = edi_screen+4          * [word] (unused, reserved)
edi_x           = edi_plan+2            * [word] Window X offset in pixels (top-left corner)
edi_y           = edi_x+2              * [word] Window Y offset in pixels (top-left corner)
edi_ext         = edi_y+2              * [long] (reserved/extension field)
edi_breit       = edi_ext+4             * [word] Window width in pixels (e.g., 480)
edi_hoch        = edi_breit+2           * [word] Window height in pixels (e.g., 160)
edi_maxzeilen   = edi_hoch+2            * [word] Max editor rows (constant, e.g., 25)
edi_maxspalten  = edi_maxzeilen+2       * [word] Max editor columns (e.g., 80)
edi_tab         = edi_maxspalten+2      * [word] Tab stop interval (e.g., 7)
edi_print       = edi_tab+2             * [long] Pointer to character output routine
*                                         Signature: d0.b=char, d1.w=X pixel, d2.w=Y pixel
edi_pgblock     = edi_print+4           * [long] Start address of Line-A routine variables
edi_vrblock     = edi_pgblock+4         * [long] Start address of system variables block
edi_retprg      = edi_vrblock+4         * [long] Callback pointer after RETURN (0=stay in BASIC)
*                                         If non-zero, called with a0=line text, d0=line length
edi_preup	= edi_retprg+4          * [long] Callback: pre-scroll-up (fetch BASIC line above)
edi_up		= edi_preup+4           * [long] Callback: post-scroll-up (update BASIC line pointer)
edi_predown	= edi_up+4             * [long] Callback: pre-scroll-down (fetch BASIC line below)
edi_down	= edi_predown+4         * [long] Callback: post-scroll-down (update BASIC line pointer)
edi_font        = edi_down+4            * [long] Pointer to GEM font header structure
edi_y_shft      = edi_font+4            * [word] Bit-shift for font height: 4 for 16px, 3 for 8px
*                                         Used as: y_pixels = row << edi_y_shft
******************************************************************************


*==============================================================================
* PROGRAM ENTRY POINT (standalone mode)
*==============================================================================
* When run as a standalone .PRG:
*   1. Points A0 to the built-in data area ('datas', 64KB)
*   2. Calls Init to set up all memory zones and subsystems
*   3. Calls Edit to enter the interactive editor/BASIC loop
*   4. On exit, terminates via GEMDOS Pterm0 (trap #1, function 0)
*==============================================================================
        lea     datas,a0                * A0 = base of free memory block (built-in 64KB area)
        move.l  #$10000,d0              * D0 = size of memory block (65536 bytes)
        bsr     Init                    * Initialize all subsystems
        bsr     Edit                    * Enter interactive editor/BASIC loop
        clr.w   -(sp)                   * Push function code 0 (Pterm0)
        trap    #1                      * GEMDOS: terminate program

*==============================================================================
* STAD Interface Jump Table
*==============================================================================
* These are exported as long-word pointers so an external STAD host can
* call Init, Edit, or Run without knowing absolute addresses.
*==============================================================================
edibase:        .dc.l   test    * Pointer to STAD structure instance (editor state)
initcode:       .dc.l   Init    * -> Init(a0=membase, d0=memsize)
editcode:       .dc.l   Edit    * -> Edit() — enter editor loop
runcode:        .dc.l   Run     * -> Run(d0=mode, a0=param)

*==============================================================================
* ROUTINE: Init
* Purpose:  Initialize the BASIC interpreter and editor subsystems
* Parameters:
*   a0.l = Base address of available free memory block
*   d0.l = Size of free memory block in bytes
* Returns:
*   d0.l = 0 if OK, -1 if insufficient memory
* Modifies: d0-d1, a0-a1 (plus all globals in DATA.S)
* Called by: standalone entry point, or external STAD host via initcode
*
* This routine:
*   1. Initializes Line-A graphics variables (for direct screen drawing)
*   2. Gets physical screen address via XBIOS Physbase (trap 14, func 2)
*   3. Fills in the STAD/editor structure with screen params and callbacks
*   4. Allocates memory zones: editor screen, program, variables, strings
*   5. Calls b_init to initialize the BASIC interpreter state
*==============================================================================
* A0:Basis des zugeordneten freien Speichers
* D0:Länge des Speichers
Init:
***
        movem.l d0/a0,-(a7)            * Save memory base/size for later use

        * --- Line-A initialization ---
        * The $A000 trap returns:
        *   a0 = pointer to Line-A variable block
        *   a1 = pointer to array of 3 font header pointers:
        *         0(a1) = 6x6 font, 4(a1) = 8x8 font, 8(a1) = 8x16 font
        *   a2 = pointer to Line-A opcode table
        .dc.w   $a000                   * Line-A A_init trap (opcode $A000): returns a0=variable block, a1=font ptrs, a2=opcode table
        move.l  a0,la_variablen         * Save Line-A variables base for later use
        move.w  #1,$18(a0)              * Set COLBIT0 (offset 24/$18): foreground color plane 0 = 1 (black in mono)
        move.w  #-1,$20(a0)            * Set LSTLIN  (offset 32/$20): draw last pixel flag = -1 (yes)
        move.w  #$ffff,$22(a0)          * Set LNMASK  (offset 34/$22): line style mask = $FFFF (solid line)
        move.w  #1,$24(a0)              * Set WMODE   (offset 36/$24): write mode = 1 (XOR)
        move.l  8(a1),bsc_font          * Use 8x16 font (third entry in font pointer array)
        move.w  #4,edi_yshft            * Shift value 4: row * 16 = row << 4 (for 16px font)
*        move.l  4(a1),bsc_font          * (commented out: alternative 8x8 font)
*        move.w  #3,edi_yshft            * (commented out: shift 3 for 8px font: row << 3)

        * --- Get physical screen base address via XBIOS ---
        * XBIOS function 2 (Physbase): returns physical screen address in d0
        move.w  #2,-(a7)                * Push XBIOS function number 2 (Physbase)
        trap    14                      * XBIOS trap: call Physbase
        addq.l  #2,a7                   * Clean up stack (1 word parameter)
        move.l  d0,w_base               * Store physical screen base address
        move.l  #80,w_screen            * Screen width = 80 bytes (640 pixels / 8 = 80 in mono)
        movem.l (a7)+,d0/a0             * Restore memory base (a0) and size (d0)
***
        * --- Fill in the STAD/editor structure ---
        move.l  edibase,a1              * A1 = pointer to STAD structure
***!!!
        move.l  #_g_char,edi_print(a1)  * Set character rendering callback (temporary/built-in)
        move.w  #16,edi_x(a1)           * Window X offset = 16 pixels from left edge
        move.w  #40,edi_y(a1)           * Window Y offset = 40 pixels from top
        move.w  #480,edi_breit(a1)      * Window width = 480 pixels (60 chars × 8px)
        move.w  #160,edi_hoch(a1)       * Window height = 160 pixels (10 lines × 16px)
        move.w  #25,edi_maxzeilen(a1)   * Max editor rows = 25 (internal buffer size)
        move.l  w_screen,edi_screen(a1) * Screen width in bytes = 80
        move.l  w_base,edi_base(a1)     * Physical screen base address
        move.w  #80,edi_maxspalten(a1)  * Max editor columns = 80
        move.w  #7,edi_tab(a1)          * Tab stop interval = 7 characters
        clr.l   edi_retprg(a1)          * No STAD return callback (0 = stay in BASIC)
        move.l  bsc_font,edi_font(a1)   * Set font header pointer (8x16 system font)
        move.w  edi_yshft,edi_y_shft(a1) * Copy font height shift value
***!!!
        * --- Set BASIC scroll callbacks (from BASIC.S) ---
        * These allow the editor to sync with BASIC program line numbers
        * when scrolling up/down through the listing
	move.l	#b_preup,edi_preup(a1)   * Pre-scroll-up: get BASIC line for top of screen
	move.l	#b_predown,edi_predown(a1) * Pre-scroll-down: get BASIC line for bottom
	move.l	#b_up,edi_up(a1)         * Post-scroll-up: update current BASIC line pointer
	move.l	#b_down,edi_down(a1)     * Post-scroll-down: update current BASIC line pointer

        * --- Allocate editor screen buffer ---
        * The editor maintains an internal character buffer (rows × cols bytes)
        * separate from the pixel framebuffer
        move.w  edi_maxzeilen(a1),d1    * D1 = max rows (25)
        mulu    edi_maxspalten(a1),d1   * D1 = rows × cols = 25 × 80 = 2000 bytes
        move.l  a0,editscreen           * editscreen = start of free memory
        jsr     ed_clrmem               * Fill editor screen buffer with spaces ($20)

        * --- Partition remaining memory into program/variable/string zones ---
        add.l   d1,a0                   * Skip past editor screen buffer
        sub.l   d1,d0                   * Subtract editor buffer from available memory
        cmp.l   #MINFREE,d0             * At least 2048 bytes free?
        bpl     initok                  * Yes: continue
        moveq.l #-1,d0                  * No: return error code -1
        bra     initback

initok:
        * Memory layout after allocation:
        *   a0 → prgbase (program storage starts here)
        *   a0+16 → varbase (variables start 16 bytes after program base)
        *   a0+d0-16 → strbase (string heap upper boundary)
        move.l  a0,prgbase              * Program storage base
        move.l  a0,prgend               * Program end = base (empty program)
        add.l   #16,a0                  * Leave 16-byte gap between program and variable zones
        move.l  a0,varbase              * Variable storage base (relocatable when program grows)
        move.l  a0,varend               * Variable end = base (no variables yet)
        lea     -16(a0,d0.l),a0         * A0 = top of memory minus 16-byte safety margin
        move.l  a0,strbase              * String heap upper boundary
        subq.l  #1,strbase              * Adjust: strbase points to last usable byte
        move.l  strbase,strend          * strend = strbase (no strings allocated yet; grows down)
        jsr     b_init                  * Initialize BASIC interpreter (clear all buffers/tables)

        moveq.l #0,d0                   * Return 0 = success

initback:
        rts


*==============================================================================
* ROUTINE: Edit
* Purpose:  Enter the interactive BASIC editor (main loop)
* Parameters: none
* Returns:    (does not return until user exits)
* Called by:  standalone entry, or external STAD host via editcode
*==============================================================================
* direkter Sprung in den Editor
Edit:
        jmp     ed_editor               * Jump to editor main loop (EDITOR.S)

*==============================================================================
* ROUTINE: Run
* Purpose:  Execute BASIC commands directly (without entering the editor)
* Parameters:
*   d0.w = mode:
*     0 = Load & Run: load file named by A0, then RUN it
*     1 = Clear & Call Procedure: CLR, then call procedure named by A0
*     2 = Run from line: RUN from line number passed in A0 (as integer)
*   a0.l = parameter (filename string, procedure name, or line number)
* Returns:    (returns after execution completes)
* Called by:  external STAD host via runcode
*
* Implementation: Builds a BASIC command string in 'runpuffer' buffer,
*   then calls b_runcode to tokenize and execute it.
*   Mode 0 builds: load "filename":run
*   Mode 1 builds: clr:procedurename
*   Mode 2 builds: run linenumber
*==============================================================================
* direktes Ausführen von Befehlen des Basics!
* D0.w = 0 -> Load Programm (A0:name) & run
* D0.w = 1 -> Clr (to define procedures) & Call Procedure (A0:name)
* D0.w = 2 -> Run line (A0.l:Line Number)
Run:
		move.l	a0,a6           * Save parameter pointer in A6
		lea		runpuffer,a0    * A0 = output buffer for constructed command string
		tst.w	d0              * Test mode
		bne		run1            * Not 0 → try mode 1

* --- Mode 0: Load & Run ---
* Constructs the string: load "filename":run
RunLoad:
		lea		runload1,a1     * A1 → 'load "' prefix string
		bsr		copya1a0        * Copy prefix to buffer
		move.l	a6,a1           * A1 → filename from caller
		bsr		copya1a0        * Copy filename to buffer
		lea		runload2,a1     * A1 → '":run' suffix string
		bsr		copya1a0        * Copy suffix to buffer
		bra		runstart        * Execute the constructed command

run1:
		subq.w	#1,d0           * Test for mode 1
		bne		run2            * Not 1 → try mode 2

* --- Mode 1: Clear & Call Procedure ---
* Constructs the string: clr:procedurename
RunProc:
		lea		runproc1,a1     * A1 → 'clr:' prefix string
		bsr		copya1a0        * Copy prefix to buffer
		move.l	a6,a1           * A1 → procedure name from caller
		bsr		copya1a0        * Copy procedure name to buffer
		bra		runstart        * Execute the constructed command

run2:
		subq.w	#1,d0           * Test for mode 2
		bne		run3            * Not 2 → unknown mode, just return

* --- Mode 2: Run from Line Number ---
* Constructs the string: run N (where N is the line number)
RunRun:
		lea		runrun1,a1      * A1 → 'run ' prefix string
		bsr		copya1a0        * Copy prefix to buffer
		move.l	a6,d0           * D0 = line number (passed as long in A0/A6)
		move.l	a0,-(sp)        * Save current buffer pointer
		bsr		ipka_           * Convert integer in D0 to ASCII string
		*                       * ipka_ returns: A2 points past end of result string
		move.l	(sp)+,a0        * Restore buffer pointer
runr1:
		move.b	-(a2),(a0)+     * Copy digits from ipka_ result (stored in reverse) to buffer
		bne		runr1           * Loop until null terminator
		subq		#1,a0   * Back up past the null (copya1a0 convention)

* --- Execute the constructed command string ---
runstart:
		move.l	a0,d0           * D0 = pointer past end of command string
		lea		runpuffer,a0    * A0 = start of command string
		sub.l	a0,d0           * D0 = length of command string
		jmp		b_runcode       * Execute: tokenize and run the command string
		*                       * b_runcode(a0=string, d0=length)

run3:
		rts                     * Unknown mode: do nothing


*==============================================================================
* ROUTINE: copya1a0
* Purpose:  Copy null-terminated string from A1 to A0
* Parameters:
*   a1.l = source string pointer (null-terminated)
*   a0.l = destination buffer pointer
* Returns:
*   a0.l = points to the position of the null terminator (not past it)
*          This allows subsequent copies to overwrite the null and concatenate
*   a1.l = points past the null terminator of the source
* Modifies: a0, a1
*==============================================================================
copya1a0:
		move.b	(a1)+,(a0)+     * Copy byte from source to destination
		bne		copya1a0        * Loop until null terminator copied
		subq.l	#1,a0           * Back up A0 to point AT the null (for concatenation)
		rts


*==============================================================================
* ROUTINE: _g_char
* Purpose:  Render a single character to the screen framebuffer
* Date:     1.11.88
*
* Parameters:
*   d0.b = ASCII character code to render
*   d1.w = X position in pixels (must be on byte boundary, i.e., multiple of 8)
*   d2.w = Y position in pixels
*
* Returns:    nothing (character is drawn directly to screen memory)
* Modifies:   d1-d4, a0, a2 (saved/restored via stack)
* Called by:  editor via edi_print callback pointer
*
* How it works:
*   The Atari ST GEM font format stores glyph data as a bitmap where each
*   character occupies one byte per scan line, with 'fontoffs' bytes between
*   consecutive scan lines of the same character. The glyph for character N
*   starts at fontdat + N (one byte wide).
*
*   Font header structure offsets used:
*     76 (fontdat)  = [long] Pointer to font bitmap data
*     80 (fontoffs) = [word] Byte offset between scan lines in font data
*     82 (fonthigh) = [word] Font height in pixels (8 or 16)
*
*   Screen address calculation:
*     addr = w_base + (y * w_screen) + (x / 8)
*   Then each scan line of the glyph is copied to successive screen lines:
*     screen[line] = fontdata[char + line * fontoffs]
*
*   The routine is UNROLLED for performance:
*     - 16 iterations for 8x16 font (the default)
*     - 8 iterations for 8x8 font (alternate path via g8char)
*==============================================================================
fontdat         equ     76              * Offset in font header: pointer to bitmap data
fontoffs        equ     80              * Offset in font header: bytes between scan lines
fonthigh        equ     82              * Offset in font header: character height in pixels
.globl  _g_char
_g_char
        movem.l d1-d4/a0/a2,-(a7)      * Save registers
        andi.l  #$ff,d0                 * Mask character to byte (0-255)
        movea.l w_base,a0               * A0 = screen framebuffer base address
        move.l  w_screen,d3             * D3 = screen width in bytes (80 for mono 640px)
        mulu    d3,d2                   * D2 = Y pixel * screen_width = byte offset for row
        movea.l bsc_font,a2             * A2 = font header base address
        lsr.w   #3,d1                   * D1 = X / 8 (convert pixel X to byte column)
        ext.l   d1                      * Sign-extend to long for address arithmetic
        add.l   d1,d2                   * D2 = row_offset + column_byte = screen position
        adda.l  d2,a0                   * A0 = screen address for top-left of character cell
        cmpi.w  #8,fonthigh(a2)         * Is font height 8 pixels?
        beq     g8char                  * Yes → use the shorter 8-line rendering loop

        * --- 16-pixel font rendering (unrolled loop: 16 iterations) ---
        * Each iteration: read one scan line from font, write to screen,
        *   advance font pointer by fontoffs, advance screen pointer by screen width
        move.w  fontoffs(a2),d4         * D4 = font line stride (bytes between scan lines)
        ext.l   d4                      * Sign-extend for address arithmetic
        move.l  fontdat(a2),a2          * A2 = pointer to font bitmap data
        adda.l  d0,a2                   * A2 = pointer to glyph data for character d0
        * Scan line 0
        move.b  (a2),(a0)               * Copy font scan line 0 to screen
        adda.l  d4,a2                   * Advance to next font scan line
        adda.l  d3,a0                   * Advance to next screen row
        * Scan line 1
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 2
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 3
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 4
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 5
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 6
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 7
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 8
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 9
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 10
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 11
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 12
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 13
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 14
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 15
        move.b  (a2),(a0)
        movem.l (a7)+,d1-d4/a0/a2      * Restore registers
        rts

* --- 8-pixel font rendering (unrolled loop: 8 iterations) ---
g8char
        move.w  fontoffs(a2),d4         * D4 = font line stride
        ext.l   d4
        move.l  fontdat(a2),a2          * A2 = font bitmap data base
        adda.l  d0,a2                   * A2 = glyph data for character d0
        * Scan line 0
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 1
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 2
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 3
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 4
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 5
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 6
        move.b  (a2),(a0)
        adda.l  d4,a2
        adda.l  d3,a0
        * Scan line 7
        move.b  (a2),(a0)
        movem.l (a7)+,d1-d4/a0/a2      * Restore registers
        rts

*==============================================================================
* DATA SECTION — Module-local variables
*==============================================================================
.data
.globl  la_variablen    * Exported: Line-A variables block pointer (used by LINE command)
.globl  bsc_font        * Exported: Font header pointer (used by editor for cursor height)
la_variablen
        .dc.l   0               * Pointer to Line-A variables (set by $A000 init)
w_base                          * Physical screen framebuffer address
        .dc.l   0               * (set by XBIOS Physbase during Init)
w_screen                        * Screen width in bytes
        .dc.l   0               * (set to 80 during Init for 640px mono mode)
bsc_font                        * GEM font header address
        .dc.l   0               * (set to 8x16 system font during Init)

* --- Command template strings for Run modes ---
* These are concatenated with user-supplied parameters to build
* executable BASIC command strings in the 'runpuffer' buffer
runload1:.dc.b	"load ",$22,0   * 'load "' — $22 is the double-quote character
runload2:.dc.b	$22,":run",0    * '":run'
runproc1:.dc.b "clr:",0         * 'clr:' — clear variables before calling procedure
runrun1:.dc.b "run ",0          * 'run '  — followed by line number

*==============================================================================
* BSS SECTION — Uninitialized data
*==============================================================================
.bss
runpuffer:.ds.b	100             * Buffer for constructing Run command strings (100 bytes)

* --- Built-in STAD structure instance and memory ---
* When running standalone (not embedded), this provides the default
* STAD structure and a 64KB memory block for the BASIC interpreter
test:
        .ds.b   1000            * STAD structure instance (1000 bytes, includes padding)
datas:
        .ds.b   $10000          * 64KB memory block for program/variables/strings
