# SBasic -- Atari ST BASIC Interpreter

A BASIC interpreter for the Atari ST, written in 68000 assembly language. I originally created it in 1987, when I was 18, under the name **FBasic** (FastBasic). In 1988 it was integrated into the **STAD** drawing application (by ASH) as a scripting add-on and renamed **SBasic** (STAD-Basic) internally. The STAD integration was never published.

This repository contains the original source code along with reverse-engineered documentation reconstructing the language manual, technical architecture, and system call references from the assembly sources.

## Features

- **Full-screen editor** with 25x80 character display, cursor navigation, and horizontal scrolling
- **Three data types**: floating-point (22-digit BCD precision), 32-bit integers, and strings (up to 255 characters)
- **113 keywords** with abbreviation support for faster typing
- **Structured programming**: named procedures (`DEF PROC`/`ENDPROC`) with parameters, local variables, local arrays, and recursion; user-defined functions (`DEF FN`)
- **Control flow**: `IF`/`THEN`/`ELSE`, `FOR`/`NEXT`, `GOTO`, `GOSUB`/`RETURN`, `ON...GOTO`/`GOSUB`
- **File I/O**: `OPEN`, `CREATE`, `CLOSE`, `PRINT #`, `INPUT #`, `DIR`
- **Full OS access**: `GEMDOS()`, `BIOS()`, `XBIOS()` system call wrappers
- **GEM graphics**: direct AES and VDI array access, Line-A drawing
- **Memory access**: `PEEK`/`POKE` (byte/word/long), `SYS`, `CALL` for machine code
- **Debugging**: `TRON`/`TROFF` trace mode, `ON TRACE GOSUB`, `DUMP` variable inspector
- **STAD embedding API**: Init/Edit/Run entry points for host application integration

## Architecture

~15,600 lines of Motorola 68000 assembly across five modules:

```
HEADER.S            Entry point, STAD interface, character renderer
  |
  +-- EDITOR.S      Full-screen text editor
  +-- BASIC_COMMENTS.S   Core interpreter (tokenizer, commands, expressions,
  |                       variables, procedures, I/O, error handling)
  |     |
  |     +-- BLIBF.S      BCD floating-point math library
  +-- DATA.S        Shared memory layout pointers
```

## Repository Structure

```
src/                Source code (68000 assembly)
  HEADER.S            Program entry point and STAD interface
  BASIC_COMMENTS.S    Core interpreter (annotated)
  BLIBF.S             BCD floating-point library
  EDITOR.S            Full-screen editor
  DATA.S              Global memory pointers
  BUILD.TXT           Build instructions

out/                Build output
  BASIC.PRG           Atari ST executable
  *.O                 Object files

demos/              Demo programs (.BAS tokenized files)

doc/                Reverse-engineered documentation
  MANUAL.md           User manual (language reference)
  ANALYSIS.md         Technical architecture analysis
  SYMBOLS.md          Symbol map and source navigation guide
  GEMDOS_BIOS_XBIOS.md   GEMDOS/BIOS/XBIOS system call reference
  GEM_VDI_LINEA.md    AES, VDI, and Line-A graphics reference
  DEMOS.md            Annotated demo program walkthroughs
  EXAMPLES-NEW.md     Additional example programs

material/           Reference material
  as68.zip            DRI 68K Development Kit (assembler, linker)
  M68000PRM.pdf       Motorola 68000 Programmer's Reference
  *.TXT, *.md         Atari ST TOS/hardware documentation
```

## Building

The interpreter is built using the DRI 68000 assembler and linker (included in `material/as68.zip`). From `src/BUILD.TXT`:

```
as68 -l -u header.s
as68 -l -u basic_comments.s
as68 -l -u blibf.s
as68 -l -u editor.s
as68 -l -u data.s

link68 [u,s,l] basic.68k = header.o,basic_comments.o,blibf.o,editor.o,data.o
relmod basic.68k basic.prg
```

The resulting `BASIC.PRG` is a standard Atari ST executable. A pre-built binary is provided in `out/`.

## Quick Start

A taste of SBasic:

```basic
10  CLS
20  INPUT "Number of disks (1-10): "; n%
30  PROC hanoi(n%, "A", "C", "B")
40  END
50  DEF PROC hanoi(disks%, from$, to$, via$)
60    IF disks% = 0 THEN ENDPROC
70    PROC hanoi(disks% - 1, from$, via$, to$)
80    PRINT "Move disk "; disks%; " from "; from$; " to "; to$
90    PROC hanoi(disks% - 1, via$, to$, from$)
100 ENDPROC
```

See [doc/MANUAL.md](doc/MANUAL.md) for the full language reference, and [doc/DEMOS.md](doc/DEMOS.md) for annotated example programs.

## Documentation

Start here:

- **[doc/MANUAL.md](doc/MANUAL.md)** -- The complete language reference. Covers the editor, all 113 keywords, data types, control flow, procedures, string/math functions, file I/O, system calls, GEM/VDI graphics, and error messages. This is the best entry point for understanding what SBasic can do.

- **[doc/ANALYSIS.md](doc/ANALYSIS.md)** -- Technical deep-dive into the interpreter's internals. Covers the memory layout, token system, expression evaluator, variable and procedure systems, string management, the BCD floating-point library, and 68000 assembly idioms. Start here if you want to study how the interpreter works under the hood.

- **[doc/DEMOS.md](doc/DEMOS.md)** -- Annotated walkthroughs of the included demo programs, showing SBasic features in action.

Further references in `doc/`: [SYMBOLS.md](doc/SYMBOLS.md) (symbol map for navigating the source), [GEMDOS_BIOS_XBIOS.md](doc/GEMDOS_BIOS_XBIOS.md) (OS call reference), [GEM_VDI_LINEA.md](doc/GEM_VDI_LINEA.md) (graphics programming reference), [EXAMPLES-NEW.md](doc/EXAMPLES-NEW.md) (additional examples).

## Historic Context

- **1987** -- Created as **FBasic** (FastBasic), a standalone BASIC interpreter for the Atari ST
- **1988** -- Integrated into the **STAD** drawing application as a scripting extension, renamed **SBasic** (STAD-Basic); source dated 31.10.88. Never publicly released as part of STAD
- **2026** -- Source code reverse-engineered and annotated; documentation reconstructed from the 68000 assembly

## License

This project is released under the [MIT License](LICENSE).
