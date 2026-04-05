*==============================================================================
* EDITOR.S — Full-Screen Text Editor for the BASIC Interpreter
*==============================================================================
* Date: 31.10.88
*
* This module implements a full-screen character-based text editor that serves
* as the primary user interface for the BASIC interpreter. It maintains an
* internal character buffer (25 rows × 80 columns) and renders characters
* to the screen via the edi_print callback.
*
* The editor supports:
*   - Cursor movement (arrow keys, home)
*   - Character insertion and deletion
*   - Tab stops
*   - Line clearing (CTRL+DEL)
*   - Screen clearing (SHIFT+CLR)
*   - Horizontal scrolling (when line exceeds visible width)
*   - Vertical scrolling with BASIC program line synchronization
*   - RETURN to send current line to BASIC interpreter
*   - ESC to exit the editor
*
* The editor communicates with the BASIC interpreter through:
*   - edi_retprg callback (called when RETURN is pressed, if set)
*   - b_enter (called to enter BASIC direct mode after RETURN)
*   - edi_preup/edi_up/edi_predown/edi_down scroll callbacks
*   - ed_chkstop (check for user break during scrolling)
*
* Screen coordinate system:
*   - ed_x: visible cursor column (0-based, relative to ed_xoffs)
*   - ed_y: cursor row (0-based)
*   - ed_xoffs: horizontal scroll offset (0 when no horizontal scroll)
*   - Actual column in buffer = ed_x + ed_xoffs
*   - Pixel X = ed_x * 8 + edi_x(window offset)
*   - Pixel Y = ed_y << edi_y_shft + edi_y(window offset)
*
* Exports:
*   ed_editor, ed_clrmem, ed_display, ed_edit, ed_getkey
*   ed_curon, ed_curoff, ed_newline, ed_clr, ed_clrhome
*   ed_backspace, ed_insert, ed_delete, ed_tab, ed_store
*   ed_runter, ed_hoch, ed_links, ed_rechts, ed_prline
*   ed_print, ed_pos, ed_x, ed_y, ed_xoffs, edi_yshft
*   ed_scrline, ed_nlfl, ed_mode, ed_clrline, ed_delask
*
* External dependencies:
*   HEADER.S: edibase, editscreen
*   BASIC.S:  b_enter, ed_chkstop
*==============================================================================

******************************************************************************
* Editor/STAD Structure Definition (duplicated from HEADER.S for assembly)
* See HEADER.S for detailed field descriptions.
******************************************************************************
edi_base        equ     0               * [long] Screen base address
edi_screen      = edi_base+4            * [long] Screen width in bytes
edi_plan        = edi_screen+4          * [word] unused
edi_x           = edi_plan+2            * [word] Window X pixel offset
edi_y           = edi_x+2              * [word] Window Y pixel offset
edi_ext         = edi_y+2              * [long] reserved
edi_breit       = edi_ext+4             * [word] Window width in pixels
edi_hoch        = edi_breit+2           * [word] Window height in pixels
edi_maxzeilen   = edi_hoch+2            * [word] Max editor rows (constant)
edi_maxspalten  = edi_maxzeilen+2       * [word] Max editor columns
edi_tab         = edi_maxspalten+2      * [word] Tab stop interval
edi_print       = edi_tab+2             * [long] Character output callback ptr
*                                         Signature: d0.b=char, d1.w=X px, d2.w=Y px
edi_pgblock     = edi_print+4           * [long] Line-A routines base
edi_vrblock     = edi_pgblock+4         * [long] Variables block base
edi_retprg      = edi_vrblock+4         * [long] Return-to-program callback (0=BASIC)
edi_preup	= edi_retprg+4          * [long] Pre-scroll-up callback
edi_up		= edi_preup+4           * [long] Post-scroll-up callback
edi_predown	= edi_up+4             * [long] Pre-scroll-down callback
edi_down	= edi_predown+4         * [long] Post-scroll-down callback
edi_font        = edi_down+4            * [long] Font header pointer
edi_y_shft      = edi_font+4            * [word] Bit-shift for font height (4=16px, 3=8px)
******************************************************************************

.globl  ed_editor,ed_clrmem,ed_display,ed_edit,ed_getkey
.globl  ed_curon,ed_curoff,ed_newline,ed_clr,ed_clrhome
.globl  ed_backspace,ed_insert,ed_delete,ed_tab,ed_store
.globl  ed_runter,ed_hoch,ed_links,ed_rechts,ed_prline
.globl  ed_print,ed_pos,ed_x,ed_y,ed_xoffs,edi_yshft
.globl	ed_scrline,ed_nlfl,ed_mode,ed_clrline,ed_delask

*==============================================================================
* ROUTINE: ed_editor
* Purpose:  Main editor event loop
* Parameters: none
* Returns:    (returns when user presses ESC)
*
* Flow:
*   1. Display the full editor screen
*   2. Enter edit loop: get key, process it
*   3. On RETURN: if edi_retprg is set, call that callback (STAD mode);
*      otherwise call b_enter to enter BASIC direct mode
*   4. On ESC: exit the editor and return to caller
*   5. Loop back to step 2
*==============================================================================
ed_editor:
        bsr     ed_display              * Redraw entire editor screen
l4:
	move.w	#1,ed_mode		* Set editor mode flag (1 = in editor, allows BASIC line scroll)
        bsr     ed_edit                 * Main edit loop (returns on RETURN or ESC)
        beq     l4a                     * Z=1 means ESC was pressed → exit editor
	clr.w	ed_mode                 * Clear editor mode flag (leaving editor temporarily)
        move.l  edibase,a1
        move.l  edi_retprg(a1),d1       * Check STAD return callback
        beq     l4b                     * If 0 → go to BASIC interpreter
        move.l  d1,a1
        jsr     (a1)                    * Call STAD callback(a0=line text, d0=line length)
        bra     l4                      * Return to edit loop
l4b:
        jsr     b_enter                 * Enter BASIC interpreter (process the line)
        *                               * b_enter returns d0: negative = exit BASIC
        tst.w   d0                      * Check return code
        bpl     l4                      * Non-negative → back to editor loop
l4a:
        rts                             * Exit editor (ESC pressed or BASIC requested exit)

*==============================================================================
* ROUTINE: ed_clrmem
* Purpose:  Clear the internal editor screen buffer and reset cursor to home
* Parameters: none (uses edibase, editscreen globals)
* Returns:    nothing
* Modifies:   d0, d1, a0 (saved/restored)
*==============================================================================
* löscht internes editscreen-array und setzt x,y-cursor auf home-pos
ed_clrmem:
        movem.l d0/d1/a0,-(sp)

        move.l  edibase,a0
        move.w  edi_maxzeilen(a0),d0    * D0 = max rows
        mulu    edi_maxspalten(a0),d0   * D0 = total bytes in screen buffer (rows × cols)
        subq.w  #1,d0                   * Adjust for DBF loop (counts down to -1)
        move.l  editscreen,a0           * A0 = base of character buffer
        move.b  #$20,d1                 * D1 = space character ($20)
* --- Fill entire buffer with spaces ---
l1:
        move.b  d1,(a0)+                * Write space to current position, advance
        dbf     d0,l1                   * Decrement and loop until done

        bsr     ed_homepos              * Reset cursor position to (0,0)
        movem.l (sp)+,d0/d1/a0
        rts

*==============================================================================
* ROUTINE: ed_homepos
* Purpose:  Reset cursor to top-left position (0,0) with no horizontal scroll
*==============================================================================
* Cursor nach oben links setzen
ed_homepos:
        clr.w   ed_x                    * Cursor column = 0
        clr.w   ed_y                    * Cursor row = 0
        clr.w   ed_xoffs                * Horizontal scroll offset = 0
        rts

*==============================================================================
* ROUTINE: ed_display
* Purpose:  Redraw the entire visible editor screen (all rows)
* Parameters: none
* Returns:    nothing
* Modifies:   d0, d1, a0 (saved/restored)
*
* Iterates through each visible row and calls ed_prline to render it.
* Temporarily modifies ed_y but restores it afterward.
*==============================================================================
* gibt aktuellen editscreen aus (zeilenweise)
ed_display:
        movem.l d0/d1/a0,-(sp)

        move.l  edibase,a0
        move.w  edi_hoch(a0),d0         * D0 = window height in pixels
        move.w  edi_yshft,d1            * D1 = shift value (4 for 16px font)
        lsr.w   d1,d0                   * D0 = height / font_height = number of visible rows
        subq.w  #1,d0                   * Adjust for DBF loop
        move.w  ed_y,-(sp)              * Save current cursor row on stack
        clr.w   ed_y                    * Start rendering from row 0
* --- Loop: render each visible row ---
l14:
        bsr     ed_prline               * Render the current row (ed_y)
        addq.w  #1,ed_y                 * Next row
        dbf     d0,l14                  * Loop for all visible rows
        move.w  (sp)+,ed_y              * Restore original cursor row

        movem.l (sp)+,d0/d1/a0
        rts


*==============================================================================
* ROUTINE: ed_edit
* Purpose:  Main keyboard input loop for the editor
* Parameters: none
* Returns:
*   On RETURN: a0.l = pointer to current line in editscreen buffer
*              d0.w = line length (maxspalten)
*              d1.w = 1 (non-zero, Z flag clear)
*   On ESC:    d1.w = 0 (zero, Z flag set)
* Modifies:   d0, d1
*
* Flow: show cursor → get key → hide cursor → dispatch:
*   RETURN (13) → return line to caller
*   ESC ($1B)   → signal exit
*   Command key → process via ed_tstcmd
*   Normal char → store via ed_store
*==============================================================================
* eigentliche editor-schleife (kehrt bei RETURN zurück)
* -> a0 = Adr der eingegebenen zeile (x-pos 0)
* -> d0 = länge der zeile
ed_edit:
        bsr     ed_curon                * Show cursor (XOR the character cell)
        bsr     ed_getkey               * Wait for keypress → d0.b=ASCII, d1.b=scan code
        bsr     ed_curoff               * Hide cursor (XOR again to restore)
        cmp.b   #13,d0                  * RETURN key?
        beq     l5                      * Yes → return current line to caller
        cmp.b   #$1b,d0                 * ESC key?
        beq     l5a                     * Yes → exit editor
        bsr     ed_tstcmd               * Test if key is an editor command
        bmi     ed_edit                 * Negative = was a command (already processed) → next key
        bsr     ed_store                * Not a command → store as normal character
        bra     ed_edit                 * Next key

* --- RETURN pressed: return current line to caller ---
l5:
        move.l  edibase,a0
        move.w  edi_maxspalten(a0),d0   * D0 = line length (full line width)
        move.l  editscreen,a0           * A0 = base of editor screen buffer
        move.w  ed_y,d1                 * D1 = current cursor row
        mulu    d0,d1                   * D1 = row * columns = byte offset
        add.l   d1,a0                   * A0 = pointer to start of current line
        moveq.l #1,d1                   * D1 = 1 (non-zero → Z flag clear → "RETURN" signal)
        rts

* --- ESC pressed: exit editor ---
l5a:
        moveq.l #0,d1                   * D1 = 0 (Z flag set → "ESC/exit" signal)
        rts


*==============================================================================
* ROUTINE: ed_curon / ed_curoff
* Purpose:  Toggle cursor visibility by XORing the character cell on screen
* Parameters: none (uses ed_x, ed_y, ed_xoffs, edibase globals)
* Returns:    nothing
*
* Implementation: Both labels point to the same code because XOR is
* self-inverting: calling once shows the cursor, calling again hides it.
*
* The cursor is drawn by inverting (NOT) each byte in a vertical column
* of screen memory at the cursor position, for the full font height.
*==============================================================================
* Cursor an/abschalten
ed_curon:
ed_curoff:
        movem.l d0/d1/d2/d3/a0/a1,-(sp)

        * --- Calculate screen address for cursor position ---
        move.l  edibase,a0              * A0 = STAD structure
        move.w  edi_x(a0),d0           * D0 = window X offset in pixels
        lsr.w   #3,d0                   * D0 = window X offset / 8 (convert to bytes)
        move.w  ed_y,d1                 * D1 = cursor row
        move.w  edi_yshft,d2            * D2 = font height shift (4 for 16px)
        lsl.w   d2,d1                   * D1 = row * font_height (in pixels)
        add.w   ed_x,d0                * D0 = window_byte_offset + cursor_column
        add.w   edi_y(a0),d1           * D1 = pixel_row + window_Y_offset
        move.l  edi_base(a0),a1         * A1 = physical screen base
        move.l  edi_screen(a0),d2       * D2 = screen width in bytes (stride)
        mulu    d2,d1                   * D1 = pixel_row * stride = byte offset for row
        add.w   d1,d0                   * D0 = total byte offset from screen base
        ext.l   d0                      * Sign-extend for address arithmetic
        add.l   d0,a1                   * A1 = screen address of cursor position

        * --- XOR cursor for font height scan lines ---
        movea.l edi_font(a0),a0         * A0 = font header
        move.w  82(a0),d3               * D3 = font height in pixels (from fonthigh field)
        subq.w  #1,d3                   * Adjust for DBF loop
l10:
        not.b   (a1)                    * Invert byte at cursor screen position (XOR cursor)
        add.l   d2,a1                   * Advance to next scan line (add screen stride)
        dbf     d3,l10                  * Loop for all scan lines of the font

        movem.l (sp)+,d0/d1/d2/d3/a0/a1
        rts


*==============================================================================
* ROUTINE: ed_getkey
* Purpose:  Wait for and return a single keypress
* Parameters: none
* Returns:
*   d0.w = ASCII code of key (low byte) — or 0 for special keys
*   d1.w = keyboard scan code (for special keys like arrows, function keys)
*
* Uses GEMDOS function 7 (Crawcin): reads a character from console
* without echoing. Returns a long word in d0:
*   bits 31-24: unused
*   bits 23-16: scan code
*   bits 15-8:  unused
*   bits 7-0:   ASCII code
*==============================================================================
* holt eingabe: -> d0.w ascii/d1.w scan
ed_getkey
        movem.l a0/a1,-(sp)
        move.w  #7,-(sp)                * GEMDOS function 7 = Crawcin (console raw char input)
        trap    #1                      * GEMDOS trap
        addq.l  #2,sp                   * Clean up stack (1 word)
        move.l  d0,d1                   * Copy full result to d1
        swap    d1                      * D1.w = scan code (was in upper word)
        movem.l (sp)+,a0/a1
        rts


*==============================================================================
* ROUTINE: ed_tstcmd
* Purpose:  Test if the current keypress is an editor command and execute it
* Parameters:
*   d0.b = ASCII code from ed_getkey
*   d1.b = scan code from ed_getkey
* Returns:
*   d1.w = -1 (MI/negative) if a command was recognized and processed
*   d1.w = +1 (PL/positive) if key is a normal character (not a command)
*
* Recognized commands:
*   Scan $4B = Left arrow  → ed_links (move cursor left)
*   Scan $4D = Right arrow → ed_rechts (move cursor right)
*   Scan $48 = Up arrow    → ed_hoch (move cursor/scroll up)
*   Scan $50 = Down arrow  → ed_runter (move cursor/scroll down)
*   ASCII 9  = Tab         → ed_tab (jump to next tab stop)
*   Scan $53 = Delete      → ed_delask (delete char, or CTRL+DEL = clear line)
*   Scan $52 = Insert      → ed_insert (insert space at cursor)
*   ASCII 8  = Backspace   → ed_backspace (move cursor left = ed_links)
*   Scan $47 = CLR/HOME    → ed_clrask (HOME or SHIFT+CLR = clear screen)
*==============================================================================
* testet, ob d0/d1 einen editor-command enthält
ed_tstcmd:
        cmp.b   #$4b,d1                 * Scan code $4B = Left arrow?
        bne     cmd1
        bsr     ed_links                * Move cursor left
        bra     l9a                     * Return "command processed"
cmd1:
        cmp.b   #$4d,d1                 * Scan code $4D = Right arrow?
        bne     cmd2
        bsr     ed_rechts               * Move cursor right
        bra     l9a
cmd2:
        cmp.b   #$48,d1                 * Scan code $48 = Up arrow?
        bne     cmd3
        bsr     ed_hoch                 * Move cursor up / scroll up
        bra     l9a
cmd3:
        cmp.b   #$50,d1                 * Scan code $50 = Down arrow?
        bne     cmd4
        bsr     ed_runter               * Move cursor down / scroll down
        bra     l9a
cmd4:
        cmp.b   #9,d0                   * ASCII 9 = Tab?
        bne     cmd5
        bsr     ed_tab                  * Jump to next tab stop
        bra     l9a
cmd5:
        cmp.b   #$53,d1                 * Scan code $53 = Delete?
        bne     cmd6
	   bsr     ed_delask              * Delete (or CTRL+DEL = clear line)
        bra     l9a
cmd6:
        cmp.b   #$52,d1                 * Scan code $52 = Insert?
        bne     cmd7
        bsr     ed_insert               * Insert space at cursor position
        bra     l9a
cmd7:
        cmp.b   #8,d0                   * ASCII 8 = Backspace?
        bne     cmd8
        bsr     ed_backspace            * Backspace (same as cursor left)
        bra     l9a
cmd8:
        cmp.b   #$47,d1                 * Scan code $47 = CLR/HOME?
        bne     cmd9
        bsr     ed_clrask               * HOME or clear screen (depending on SHIFT)
        bra     l9a
cmd9:
        moveq.l #1,d1                   * Not a command → return positive (normal character)
        rts
l9a:
        moveq.l #-1,d1                  * Command was processed → return negative
        rts


*==============================================================================
* ROUTINE: ed_newline
* Purpose:  Move cursor to beginning of next line (carriage return + line feed)
* Parameters: none
* Returns:    nothing
*==============================================================================
ed_newline:
        clr.w   ed_x                    * Reset cursor column to 0
        bra     ed_runter               * Move cursor down one line (may scroll)

*==============================================================================
* ROUTINE: ed_clrask
* Purpose:  Handle CLR/HOME key: HOME if no shift, clear screen if SHIFT held
* Parameters: none
* Returns:    nothing
*
* Uses BIOS function 11 (Kbshift, trap #13) to check modifier key state:
*   Bit 0 = Right Shift, Bit 1 = Left Shift
*   If either shift is held → clear entire screen (ed_clr)
*   If no shift → just go to home position (ed_clrhome)
*==============================================================================
* wenn SHIFT, dann CLR SCRN, ansonsten HOME
ed_clrask:
        movem.l d1-a6,-(sp)
        move.w  #-1,-(sp)               * Parameter: -1 = read current state (don't change)
        move.w  #11,-(sp)               * BIOS function 11 = Kbshift
        trap    #$d                     * BIOS trap #13
        addq.l  #4,sp                   * Clean up stack (2 words)
        movem.l (sp)+,d1-a6
        and.w   #3,d0                   * Mask bits 0-1 (left/right shift keys)
        beq     ed_clrhome              * No shift → HOME only

*==============================================================================
* ROUTINE: ed_clr
* Purpose:  Clear entire editor screen and redisplay
*==============================================================================
ed_clr:
        bsr     ed_clrmem               * Fill screen buffer with spaces
        bsr     ed_homepos              * Reset cursor to (0,0)
        bra     ed_display              * Redraw screen (shows blank screen)

*==============================================================================
* ROUTINE: ed_clrhome
* Purpose:  Move cursor to home position (0,0) and redraw current line
*           (resets horizontal scroll but doesn't clear screen content)
*==============================================================================
ed_clrhome:
        clr.w   ed_xoffs                * Reset horizontal scroll
        bsr     ed_prline               * Redraw current line (in case it was scrolled)
        bra     ed_homepos              * Set cursor to (0,0)


*==============================================================================
* ROUTINE: ed_delask
* Purpose:  Handle Delete key: normal delete, or CTRL+DEL = clear line
* Parameters: none
* Returns:    nothing
*
* Checks BIOS Kbshift for CTRL key (bit 2). If CTRL held, clears the
* entire current line. Otherwise, deletes the character at cursor.
*==============================================================================
ed_delask:
        movem.l d1-a6,-(sp)
        move.w  #-1,-(sp)               * Read current key state
        move.w  #11,-(sp)               * BIOS Kbshift
        trap    #$d                     * BIOS trap
        addq.l  #4,sp
        movem.l (sp)+,d1-a6
        btst    #2,d0                   * Bit 2 = CTRL key?
        beq	 ed_delete               * No CTRL → normal delete

*==============================================================================
* ROUTINE: ed_clrline
* Purpose:  Clear the current line (fill with spaces) and reset cursor X
* Parameters: none
* Returns:    nothing
*==============================================================================
ed_clrline:
	   movem.l d0/d1/a0,-(sp)
        move.l  edibase,a0
        move.w  ed_y,d0                 * D0 = current cursor row
        move.w  edi_maxspalten(a0),d1   * D1 = columns per line
        mulu    d1,d0                   * D0 = byte offset to start of current line

        move.l  editscreen,a0           * A0 = screen buffer base
  	   add.l	 d0,a0                  * A0 = pointer to start of current line
	   subq.w	 #1,d1                  * Adjust for DBF loop
* --- Fill line with spaces ---
clrl:
	   move.b	#$20,(a0)+             * Write space
        dbf     d1,clrl                 * Loop for all columns
	   clr.w	 ed_x                   * Reset cursor column to 0
	   clr.w	 ed_xoffs               * Reset horizontal scroll
        bsr     ed_prline               * Redraw the line on screen
	   movem.l (sp)+,d0/d1/a0
	   rts


*==============================================================================
* ROUTINE: ed_backspace
* Purpose:  Handle backspace key (simply moves cursor left one position)
* Note: Unlike typical backspace, this does NOT delete the character.
*       It just repositions the cursor. The user can then type over it.
*==============================================================================
ed_backspace:
        bra     ed_links                * Same as cursor left


*==============================================================================
* ROUTINE: ed_insert
* Purpose:  Insert a space at the current cursor position, shifting all
*           characters to the right by one position. The rightmost
*           character on the line is lost (dropped off the end).
* Parameters: none (uses ed_x, ed_y, ed_xoffs, edibase, editscreen)
* Returns:    nothing
*==============================================================================
ed_insert:
        movem.l d0/d1/d2/a0,-(sp)

        move.l  edibase,a0
        move.w  ed_y,d0                 * D0 = current row
        move.w  edi_maxspalten(a0),d1   * D1 = columns per line
        mulu    d1,d0                   * D0 = offset to start of current line

        move.w  ed_x,d2                 * D2 = visible cursor column
        add.w   ed_xoffs,d2             * D2 = absolute cursor column (with scroll offset)
        add.w   d1,d0                   * D0 = offset to END of current line
        ext.l   d0

        move.l  editscreen,a0           * A0 = screen buffer base
        lea     -1(a0,d0.l),a0          * A0 = pointer to LAST char of current line
        sub.w   d2,d1                   * D1 = chars from cursor to end of line
        subq.w  #1,d1                   * Adjust for DBF (one less: last char is dropped)
        bra     l21
* --- Shift characters right: copy from right to left to avoid overwriting ---
l21a:
        move.b  -(a0),1(a0)             * Copy char one position to the right
l21:
        dbf     d1,l21a                 * Loop until cursor position reached
        move.b  #$20,(a0)               * Place space at cursor position
        bsr     ed_prline               * Redraw the line

        movem.l (sp)+,d0/d1/d2/a0
        rts



*==============================================================================
* ROUTINE: ed_delete
* Purpose:  Delete the character at the current cursor position, shifting
*           all characters to the right one position to the left.
*           A space is placed at the end of the line.
* Parameters: none (uses ed_x, ed_y, ed_xoffs, edibase, editscreen)
* Returns:    nothing
*==============================================================================
ed_delete:
        movem.l d0/d1/d2/a0,-(sp)

        move.l  edibase,a0
        move.w  ed_y,d0                 * D0 = current row
        move.w  edi_maxspalten(a0),d1   * D1 = columns per line
        mulu    d1,d0                   * D0 = offset to start of current line

        move.w  ed_x,d2                 * D2 = visible cursor column
        add.w   ed_xoffs,d2             * D2 = absolute cursor column
        add.w   d2,d0                   * D0 = offset to character at cursor
        ext.l   d0

        move.l  editscreen,a0           * A0 = screen buffer base
        add.l   d0,a0                   * A0 = pointer to character at cursor position
        sub.w   d2,d1                   * D1 = remaining chars from cursor to end of line
        subq.w  #1,d1                   * Adjust for DBF
        bra     l20
* --- Shift characters left: copy from left to right ---
l20a:
        move.b  1(a0),(a0)+             * Copy next char to current position, advance
l20:
        dbf     d1,l20a                 * Loop until end of line
        move.b  #$20,(a0)               * Fill the vacated last position with space
        bsr     ed_prline               * Redraw the line

        movem.l (sp)+,d0/d1/d2/a0
        rts


*==============================================================================
* ROUTINE: ed_tab
* Purpose:  Move cursor to the next tab stop position
* Parameters: none (uses edi_tab from STAD structure)
* Returns:    nothing
*
* Algorithm:
*   1. Find the next tab stop > current column (tab stops at intervals of edi_tab)
*   2. If tab stop is beyond maxspalten → do newline instead
*   3. Otherwise, move cursor right the appropriate number of positions
*==============================================================================
* zum nächsten Tabulator springen
ed_tab:
        movem.l d0/d1/d2/a0,-(sp)

        move.l  edibase,a0
        move.w  edi_tab(a0),d0          * D0 = tab interval (e.g., 7)
        clr.w   d1                      * D1 = candidate tab stop position (starts at 0)
        move.w  ed_x,d2                 * D2 = current absolute cursor column
        add.w   ed_xoffs,d2
* --- Find next tab stop greater than current position ---
l17a:
        cmp.w   d2,d1                   * Is candidate tab stop > current column?
        bhi     l17                     * Yes → found the next tab stop
        add.w   d0,d1                   * No → advance to next tab stop
        bra     l17a
l17:
        cmp.w   edi_maxspalten(a0),d1   * Tab stop beyond end of line?
        bmi     l17e                    * No → move to tab stop
	bsr	ed_newline              * Yes → wrap to next line
	bra	l17b
l17e:
        sub.w   d2,d1                   * D1 = number of positions to move right
        bra     l17c
* --- Move cursor right by D1 positions ---
l17d:
        bsr     ed_rechts               * Move cursor right one position
l17c:
        dbf     d1,l17d                 * Loop until target position reached
l17b:
        movem.l (sp)+,d0/d1/d2/a0
        rts


*==============================================================================
* ROUTINE: ed_store
* Purpose:  Store a character at the current cursor position in the screen
*           buffer, render it to the pixel screen, and advance cursor right
* Parameters:
*   d0.b = ASCII character to store
* Returns:    nothing
* Modifies:   d1-d4, a0-a1 (saved/restored)
*
* This is the main "type a character" routine. It:
*   1. Writes the char to the internal screen buffer at (ed_x+ed_xoffs, ed_y)
*   2. Calculates pixel coordinates and calls edi_print callback to render
*   3. Advances cursor one position to the right (may scroll horizontally)
*==============================================================================
* Zeichen in D0 an aktueller Pos sichern, eine Pos weiter
ed_store:
        movem.l d1/d2/d3/d4/a0/a1,-(sp)

        move.l  edibase,a1

        * --- Store character in screen buffer ---
        move.w  ed_x,d1                 * D1 = visible cursor column
        move.w  d1,d3                   * D3 = copy of visible column (for pixel calc later)
        move.w  ed_y,d2                 * D2 = cursor row
        move.w  d2,d4                   * D4 = copy of row
        mulu    edi_maxspalten(a1),d4   * D4 = row * maxcols = line offset
        add.w   d3,d4                   * D4 = line offset + visible column
        add.w   ed_xoffs,d4             * D4 = buffer offset (includes horizontal scroll)
        move.l  editscreen,a0           * A0 = screen buffer base
        move.b  d0,0(a0,d4.w)          * Write character to buffer

        * --- Calculate pixel coordinates and render ---
        lsl.w   #3,d1                   * D1 = visible column * 8 = X pixel offset
        move.w  edi_yshft,d3            * D3 = font height shift
        lsl.w   d3,d2                   * D2 = row * font_height = Y pixel offset
        add.w   edi_x(a1),d1           * D1 += window X offset → absolute X pixel
        add.w   edi_y(a1),d2           * D2 += window Y offset → absolute Y pixel
        move.l  edi_print(a1),a1       * A1 = character rendering callback
        jsr     (a1)                    * Call: _g_char(d0=char, d1=X pixel, d2=Y pixel)

        bsr     ed_rechts               * Advance cursor one position to the right

        movem.l (sp)+,d1/d2/d3/d4/a0/a1
        rts


*==============================================================================
* ROUTINE: ed_runter (= "down" in German)
* Purpose:  Move cursor down one row. If already at the bottom of the visible
*           area, scroll the screen up by one line.
* Parameters: none
* Returns:    nothing
*
* When scrolling is needed:
*   1. Copies each row up by one (row 1→0, 2→1, etc.)
*   2. Calls edi_predown callback to fetch the next BASIC line
*   3. Fills the new bottom row with spaces
*   4. Redraws the entire screen
*   5. Calls edi_down callback to update BASIC line tracking
*
* The 'delay' routine is called first to slow down rapid scrolling
* and check for CTRL key (pause) or SHIFT key (slow scroll).
*==============================================================================
ed_runter:
	bsr		delay                   * Check for CTRL (pause) / SHIFT (slow down)
	movem.l	d0-a6,-(sp)
	jsr		ed_chkstop              * Check if user pressed ALT+UNDO (break)
	movem.l	(sp)+,d0-a6

        movem.l d0/d1/d2/a0/a1/a2,-(sp)
	clr.l	ed_scrline              * Clear scroll-line flag (no scroll yet)

	move.l	edibase,a0
        move.w  ed_y,d1                 * D1 = current cursor row
        addq.w  #1,d1                   * D1 = next row
        move.w  edi_hoch(a0),d0         * D0 = window height in pixels
        move.w  edi_yshft,d2
        lsr.w   d2,d0                   * D0 = number of visible rows
        cmp.w   d1,d0                   * Is cursor already at the bottom?
        bne     l13                     * No → just move cursor down

        * --- Scroll screen up: cursor is at bottom row ---
        subq.w  #1,d1                   * D1 = last visible row index (bottom)
        move.w  edi_maxspalten(a0),d0   * D0 = columns per line
        mulu    d0,d1                   * D1 = bytes from row 1 to bottom (amount to copy)
        ext.l   d0
        move.l  editscreen,a0           * A0 = destination (row 0)
        lea     0(a0,d0.l),a1          * A1 = source (row 1)
        bra     l13e
* --- Copy loop: shift all rows up by one ---
l13c:
        move.b  (a1)+,(a0)+            * Copy byte from row N+1 to row N
l13e:
        dbf     d1,l13c                 * Loop for all bytes

        * --- Call BASIC pre-scroll-down callback ---
        * This tells BASIC to prepare the content for the new bottom line
	move.l	a0,ed_scrline           * Save pointer to new bottom line (for edi_down)
	move.l	edibase,a1
	move.l	edi_predown(a1),a1      * Get pre-scroll-down callback
	jsr	(a1)                    * Call: b_predown — fills new bottom line

        * --- Fill new bottom row with spaces ---
        subq.w  #1,d0                   * Adjust for DBF loop (d0 still = maxspalten)
        move.b  #$20,d1                 * Space character
l13d:
        move.b  d1,(a0)+               * Fill with spaces
        dbf     d0,l13d

        clr.w   ed_xoffs                * Reset horizontal scroll
        bsr     ed_display              * Redraw entire screen
        bra     l13b                    * Skip cursor increment (already at bottom)

l13:
        * --- No scroll needed: just move cursor down ---
        tst.w   ed_xoffs                * Is there horizontal scroll?
        beq     l13a                    * No → skip
        clr.w   ed_xoffs                * Reset horizontal scroll
        bsr     ed_prline               * Redraw current line (without scroll offset)
l13a:
        add.w   #1,ed_y                 * Increment cursor row

l13b:
        * --- Call BASIC post-scroll-down callback if scroll happened ---
	tst.l	ed_scrline              * Did we scroll?
	beq	nopredwn                * No → skip callback
	move.l	edibase,a1
	move.l	edi_down(a1),a1         * Get post-scroll-down callback
	jsr	(a1)                    * Call: b_down — update BASIC line pointer
nopredwn
        movem.l (sp)+,d0/d1/d2/a0/a1/a2
        rts


*==============================================================================
* ROUTINE: ed_hoch (= "up" in German)
* Purpose:  Move cursor up one row. If already at the top, scroll the screen
*           down by one line (shift all rows down, insert new content at top).
* Parameters: none
* Returns:    nothing
*
* When scrolling is needed:
*   1. Copies each row down by one (second-to-last→last, etc.)
*   2. Calls edi_preup callback to fetch the BASIC line above current top
*   3. Fills the new top row with spaces
*   4. Redraws the entire screen
*   5. Calls edi_up callback to update BASIC line tracking
*==============================================================================
ed_hoch:
        movem.l d0/d1/d2/a0/a1/a2,-(sp)

	clr.l	ed_scrline              * Clear scroll-line flag
	move.l	edibase,a0

        tst.w   ed_y                    * Is cursor at row 0 (top)?
        bne     l16                     * No → just move cursor up

        * --- Scroll screen down: cursor is at top row ---
        move.w  edi_hoch(a0),d1         * D1 = window height in pixels
        move.w  edi_yshft,d2
        lsr.w   d2,d1                   * D1 = number of visible rows
        subq.w  #1,d1                   * D1 = last row index
        move.w  edi_maxspalten(a0),d0   * D0 = columns per line
        mulu    d0,d1                   * D1 = byte offset to last row start
        ext.l   d0
        move.l  editscreen,a0           * A0 = screen buffer base
        move.l  a0,a2                   * A2 = save base address (for filling top row later)
        lea     0(a0,d1.l),a0          * A0 = start of second-to-last row (source end)
        lea     0(a0,d0.l),a1          * A1 = start of last row (destination end)
        bra     l15e
* --- Copy loop: shift all rows down by one (copy from bottom to top) ---
l15c:
        move.b  -(a0),-(a1)            * Copy byte from row N to row N+1
l15e:
        dbf     d1,l15c                 * Loop for all bytes

        * --- Call BASIC pre-scroll-up callback ---
	move.l	a2,ed_scrline           * Save pointer to top row (for edi_up)
	move.l	edibase,a1
	move.l	edi_preup(a1),a1        * Get pre-scroll-up callback
	jsr	(a1)                    * Call: b_preup — fetches line above current top

        * --- Fill new top row with spaces ---
        subq.w  #1,d0                   * Adjust for DBF
        move.b  #$20,d1
l15d:
        move.b  d1,(a2)+               * Fill with spaces
        dbf     d0,l15d

        clr.w   ed_xoffs                * Reset horizontal scroll
        bsr     ed_display              * Redraw entire screen
        bra     l15                     * Skip cursor decrement

l16:
        * --- No scroll needed: just move cursor up ---
        tst.w   ed_xoffs
        beq     l16a
        clr.w   ed_xoffs
        bsr     ed_prline
l16a:
        sub.w   #1,ed_y                 * Decrement cursor row

l15:
        * --- Call BASIC post-scroll-up callback if scroll happened ---
	tst.l	ed_scrline              * Did we scroll?
	beq	nopreup                 * No → skip
	move.l	edibase,a0
	move.l	edi_up(a0),a0           * Get post-scroll-up callback
	jsr	(a0)                    * Call: b_up — update BASIC line pointer
nopreup:
        movem.l (sp)+,d0/d1/d2/a0/a1/a2
        rts



*==============================================================================
* ROUTINE: ed_rechts (= "right" in German)
* Purpose:  Move cursor one position to the right
* Parameters: none
* Returns:    nothing
*
* Handles three cases:
*   1. If maxspalten <= visible width: cursor wraps to next line at maxspalten
*   2. If cursor reaches visible width boundary: horizontal scroll (ed_xoffs++)
*   3. If cursor reaches maxspalten after scrolling: wrap to next line
*==============================================================================
ed_rechts:
        movem.l d0/d1/a0,-(sp)

        add.w   #1,ed_x                * Increment visible cursor column
        move.l  edibase,a0
        move.w  edi_maxspalten(a0),d1   * D1 = max columns in buffer (e.g., 80)
        move.w  edi_breit(a0),d0        * D0 = window width in pixels
        lsr.w   #3,d0                   * D0 = visible columns (width / 8)
        cmp.w   d0,d1                   * Is maxspalten <= visible width?
        bhi     breiteOK                * No → horizontal scrolling possible

        * --- No scrolling possible: maxspalten fits in window ---
        cmp.w   ed_x,d1                 * Cursor beyond maxspalten?
        bne     l6                      * No → done
        bra     l6runter                * Yes → wrap to next line

breiteOK:
        * --- Horizontal scrolling mode ---
        cmp.w   ed_x,d0                * Cursor beyond visible width?
        bne     l6                      * No → done

        subq.w  #1,ed_x                * Stay at last visible column
        addq.w  #1,ed_xoffs             * Scroll content left by one
        sub.w   d0,d1                   * D1 = max scroll offset
        cmp.w   ed_xoffs,d1             * Scrolled beyond max?
        bge     l7                      * No → redraw line

        bra     l6runter                * Yes → wrap to next line

l7:
        bsr     ed_prline               * Redraw line with new scroll offset
        bra     l6
l6runter:
        * --- Wrap to next line ---
        clr.w   ed_x                    * Reset column to 0
        bsr     ed_runter               * Move down one row
l6:
        movem.l (sp)+,d0/d1/a0
        rts

*==============================================================================
* ROUTINE: ed_links (= "left" in German)
* Purpose:  Move cursor one position to the left
* Parameters: none
* Returns:    nothing
*
* Handles three cases:
*   1. Normal: just decrement ed_x
*   2. At left edge with scroll: decrement ed_xoffs, redraw line
*   3. At absolute left edge (x=0, xoffs=0): wrap to end of previous line
*==============================================================================
ed_links:
        movem.l d0/d1/a0,-(sp)

        subq.w  #1,ed_x                * Decrement visible column
        bpl     l11                     * Still >= 0 → done

        * --- At left edge of visible area ---
        clr.w   ed_x                    * Keep at column 0
        subq.w  #1,ed_xoffs             * Try to scroll right (decrease offset)
        bpl     l12                     * Still >= 0 → scroll was possible

        * --- At absolute left edge: wrap to end of previous line ---
        clr.w   ed_xoffs                * Reset scroll
        bsr     ed_hoch                 * Move cursor up one row
        move.l  edibase,a0
        move.w  edi_breit(a0),d0        * D0 = visible columns (pixels / 8)
        lsr.w   #3,d0
        move.w  edi_maxspalten(a0),d1   * D1 = max columns
        sub.w   d0,d1                   * D1 = scroll offset for showing end of line
        bpl     linksok                 * Positive → line is wider than window
        clr.w   d1                      * No scroll needed
        move.w  edi_maxspalten(a0),d0   * D0 = use maxspalten as visible width
linksok:
        move.w  d1,ed_xoffs             * Set horizontal scroll to show end of line
        subq.w  #1,d0                   * D0 = last visible column
        move.w  d0,ed_x                 * Cursor at end of visible area

l12:
        bsr     ed_prline               * Redraw line with new scroll offset
l11:
        movem.l (sp)+,d0/d1/a0
        rts


*==============================================================================
* ROUTINE: ed_prline
* Purpose:  Render a single line from the screen buffer to the pixel display
* Parameters: none (uses ed_y for which line, ed_xoffs for scroll position)
* Returns:    nothing
*
* For each character in the visible portion of the current line:
*   - Reads the character from editscreen buffer at (col + ed_xoffs, ed_y)
*   - Calculates pixel coordinates
*   - Calls the edi_print callback to render the character
*==============================================================================
ed_prline:
        movem.l d0/d1/d2/d3/d4/a0/a1/a2,-(sp)

        move.l  edibase,a1

        * --- Calculate source address in screen buffer ---
        move.w  ed_y,d2                 * D2 = current row (will become Y pixel)
        move.w  d2,d3                   * D3 = row copy for buffer offset
        mulu    edi_maxspalten(a1),d3   * D3 = row * maxcols = line start offset
        add.w   ed_xoffs,d3             * D3 += scroll offset → visible portion start
        ext.l   d3
        move.l  editscreen,a0           * A0 = screen buffer base
        add.l   d3,a0                   * A0 = pointer to first visible char on this line

        * --- Calculate Y pixel coordinate ---
        move.w  edi_yshft,d3
        lsl.w   d3,d2                   * D2 = row * font_height = Y pixel offset
        add.w   edi_y(a1),d2           * D2 += window Y offset → absolute Y pixel
        move.l  edi_print(a1),a2       * A2 = character rendering callback

        * --- Determine rendering width ---
        move.w  edi_breit(a1),d3        * D3 = window width in pixels
        move.w  edi_maxspalten(a1),d1   * D1 = max columns * 8 = max pixel width
        lsl.w   #3,d1
        cmp.w   d3,d1                   * maxcols * 8 < window width?
        bpl     breiteok                * No → use window width
        exg     d1,d3                   * Yes → swap so D3 = smaller width (maxcols * 8)

breiteok:
        * --- Render loop: output each character ---
        clr.w   d4                      * D4 = current X pixel offset (relative to window)
l8:
        move.w  d4,d1                   * D1 = X pixel offset
        add.w   edi_x(a1),d1           * D1 += window X offset → absolute X pixel
        move.b  (a0)+,d0               * D0 = next character from buffer
        jsr     (a2)                    * Call: edi_print(d0=char, d1=X pixel, d2=Y pixel)
        addq.w  #8,d4                   * Advance X by 8 pixels (one character width)
        cmp.w   d3,d4                   * Reached end of visible width?
        bmi     l8                      * No → continue with next character

        movem.l (sp)+,d0/d1/d2/d3/d4/a0/a1/a2
        rts

*==============================================================================
* ROUTINE: ed_print
* Purpose:  Print a null-terminated string at the current cursor position
*           using ed_store for each character
* Parameters:
*   a0.l = pointer to null-terminated string
* Returns:    nothing
*
* Special handling:
*   - ASCII 13 (CR) → calls ed_newline instead of ed_store
*   - If ed_nlfl is set: stops printing at end of line (no auto-wrap)
*==============================================================================
* A0:auszugebender String (ende = $0)
ed_print:
        movem.l d0/d1/a0/a1,-(sp)
	move.l	edibase,a1
	move.w	edi_maxspalten(a1),a1   * A1 = max columns (used as limit counter)
	subq.w	#1,a1                   * A1 = last valid column index
* --- Character output loop ---
l22a:
        move.b  (a0)+,d0               * Read next character
        beq     l22                     * Null terminator → done

        cmp.b   #13,d0                  * Carriage return?
        bne     l22b
        bsr     ed_newline              * Yes → move to beginning of next line
        bra     l22a                    * Continue with next character
l22b:
	tst.w	ed_nlfl                 * Line-wrap prevention flag set?
	beq	l22c                    * No → allow wrapping
	move.w	ed_x,d1                 * Check current cursor position
	add.w	ed_xoffs,d1             * D1 = absolute column
	cmp.w	a1,d1                   * At or past end of line?
	bpl	l22                     * Yes → stop printing (no wrap)
l22c:
        bsr     ed_store                * Store character and render it
        bra     l22a                    * Next character
l22:
        movem.l (sp)+,d0/d1/a0/a1
        rts


*==============================================================================
* ROUTINE: ed_pos
* Purpose:  Set cursor position to (column=D0, row=D1)
* Parameters:
*   d0.w = target column (0-based)
*   d1.w = target row (0-based)
* Returns:    nothing
*
* If D1 exceeds the visible rows, it is clamped to the last row.
* Column positioning is done by moving right from column 0, D0 times.
*==============================================================================
* D0/D1 sind ed_x/ed_y
ed_pos:
        movem.l d0/d1/d2/d3/a0,-(sp)

        move.l  edibase,a0
        move.w  edi_hoch(a0),d2         * D2 = window height in pixels
        move.w  edi_yshft,d3
        lsr.w   d3,d2                   * D2 = number of visible rows
        cmp.w   d2,d1                   * Is target row beyond visible area?
        bmi     l23                     * No → use target row
        subq.w  #1,d2                   * Yes → clamp to last visible row
        move.w  d2,d1
l23:
        move.w  d1,ed_y                 * Set cursor row
        clr.w   ed_x                    * Reset cursor column to 0
        clr.w   ed_xoffs                * Reset horizontal scroll
        bra     l23a
* --- Move cursor right D0 times to reach target column ---
l23b:
        bsr     ed_rechts               * Move right (handles scrolling automatically)
l23a:
        dbf     d0,l23b                 * Loop D0 times

        movem.l (sp)+,d0/d1/d2/d3/a0
        rts


*==============================================================================
* ROUTINE: delay
* Purpose:  Delay routine for scroll speed control
*           - If CTRL is held: wait until CTRL is released (pause scrolling)
*           - If SHIFT is held: insert a delay (slow scrolling)
*           - If neither: no delay (fast scrolling)
*
* Uses BIOS function 11 (Kbshift, trap #13) to read modifier key state:
*   Bit 0 = Right Shift, Bit 1 = Left Shift, Bit 2 = CTRL
*==============================================================================
delay:
	movem.l	d0-a6,-(sp)
* --- Wait while CTRL is held (pause) ---
waitctrl:
	move.w    #-1,-(sp)               * Read key state (don't change)
	move.w    #11,-(sp)               * BIOS Kbshift
	trap      #$d                     * BIOS trap
	addq.l    #4,sp                   * Clean up stack
	btst      #2,d0                   * CTRL key held?
	bne       waitctrl                * Yes → keep waiting (pause mode)
	and.b     #$3,d0                  * Check SHIFT keys (bits 0-1)
	beq       noshift                 * No shift → no delay
	* --- SHIFT held: execute a busy-wait delay for slow scrolling ---
	move.l    #$28000,d0              * Delay counter (~163840 iterations)
waitshift:
	subq.l    #1,d0                   * Decrement counter
	bne       waitshift               * Loop until zero
noshift:
	movem.l	(sp)+,d0-a6
	rts


*==============================================================================
* EDITOR DATA SECTION
*==============================================================================
*
* EDITOR-DATENTEIL
*
ed_nlfl		.dc.w	0	* Newline flag: 0=auto-wrap at end of line / 1=stop at end (no wrap)
ed_mode		.dc.w	1	* Editor mode: 1=in editor (BASIC line scrolling active) / 0=not in editor
ed_xoffs        .ds.w   1       * Horizontal scroll offset (0 = no scroll)
ed_x:           .ds.w   1       * Current cursor column (visible, 0-based)
ed_y:           .ds.w   1       * Current cursor row (0-based)
ed_scrline	.ds.l	1       * Pointer to scroll line buffer (non-zero if scroll just happened)
edi_yshft       .ds.w   1       * Font height bit-shift: 4 for 16px font, 3 for 8px font

