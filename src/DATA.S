*==============================================================================
* DATA.S — Global Memory Layout Pointers
*==============================================================================
* This module defines the shared memory pointers that all other modules
* (HEADER, BASIC, EDITOR, BLIBF) use to access the interpreter's memory zones.
*
* Memory Layout (low to high addresses):
*
*   +-------------------+  <-- editscreen
*   | Editor Screen Buf |  (25 rows × 80 cols = 2000 bytes of character data)
*   +-------------------+  <-- prgbase
*   | BASIC Program     |  (tokenized program as a linked list, grows UP)
*   |   (grows up →)    |
*   +-------------------+  <-- prgend
*   |                   |
*   +-------------------+  <-- varbase (may be relocated when program changes)
*   | Variable Storage  |  (linked list of variables, grows UP)
*   |   (grows up →)    |
*   +-------------------+  <-- varend
*   |   (free space)    |
*   +-------------------+  <-- strend (current top of string heap)
*   | String Storage    |  (strings stored in REVERSE, grows DOWN)
*   |   (← grows down)  |
*   +-------------------+  <-- strbase (fixed upper boundary)
*
* Note: Strings are allocated top-down from strbase. When strend meets varend,
*       the interpreter is out of memory. Garbage collection reclaims dead
*       strings by scanning and compacting the string heap.
*==============================================================================

.globl  editscreen,prgbase,varbase,strbase,prgend,varend,strend

editscreen      .ds.l   1       * Base address of the editor's screen buffer
prgbase         .ds.l   1       * Base address of tokenized BASIC program storage
prgend          .ds.l   1       * End address of BASIC program (first free byte after program)
varbase         .ds.l   1       * Base address of variable storage (relocatable when program changes!)
varend          .ds.l   1       * End address of variable storage (first free byte after variables)
strbase         .ds.l   1       * Upper boundary of string heap (fixed; strings grow downward from here)
strend          .ds.l   1       * Current bottom of string heap (moves down as strings are allocated)
