Your job is to reverse-engineering a Atari ST BASIC interpreter with the full source in the src folder. It's rare and there is not much documentation.

BASIC interpreter source files are at src/:
- S files : 68000 Assembler
- BUILD.TXT script using as68 assembler and link68
 
## Goals

New files: BASIC-MANUAL.md, BASIC-ANALYSIS.md
Updated: Source files (.S)

1. The main goal is to create a comprehensive manual for the interpreter under BASIC-MANUAL.md, so that I know how to use the basic interpreter. It needs to document the various modes (editor, basic keywords and parameter/results, types, features like variables etc, functions etc).
Most of this information must be derived by understanding the 68000 assembler sources in src/ and the TOS calls.

2. Write all your findings to a BASIC-ANALYSIS.md

3.
You can also add comments to the assembler source, to help me better understand it.
This might also help you to gather knowledge.
Specifically, add comments to the code lines and blocks in src/ source files. The goal is that I understand what a sections/routine is doing (adding multi-line comments), but also add comments to instruction blocks (like loops) and even single assembler instructions if the code is non-trivial. I want to read the assembler source and really understand what is going on. Note that I need you to explain Assembler/68000 machine code tricks,  TOS knowhow (trap calls and parameter usage), and algorithms and logic of the BASIC interpreter itself. Try also to reconstruct the signature (parameters and results, and its types) of routines and then add comments to the call sites about it and its parameters.
You might want to read the source files and the BASIC-ANALYSIS.md for     
better context. And understand that BASIC.S is a huge source file, so it commenting it might need to happen in (many) batches (with each batch working on a logical unit of this source file).



So you need to make a plan and consult the provided material (see below).


## Here are some hints:

- The full Atari ST SDK is under atari-tos-main folder:
	- the atari-tos-main/doc/ folder: a comprehensive set of documents about the Atari ST (the actual Developer SDK for Atari ST TOS). So make sure to inspect them and make really make sure to USE this material.
Most relevant is under atari-tos-main/doc is:
	- additional_material/ subfolder
		- TOS.TXT explains the as68 assembler (its options, flags, Directives) and the link68 tools
		- 68000_Assembly_Language.txt explains the 68000 assembler language
	- SDK_DOCS_INDEX.md as a bill-of-material of the docs folder
- Additional: doc/GEM/AES/README.md : about the GEM subsystem of TOS (maybe not really required)

- Note that .doc files are actually ASCII files (with Atari ST specific encoding )!!! There was not Word format back then, so always try unknown extensions as such Atari ST specific ASCII files.
	- Note that some docs are also in PDF format, but prefer .doc, .txt, .md

- Demo files for the BASIC interpreter are in demos folder:
	- .BAS are binary files (tokenized form) that are read into memory
	- .TXT are Atari ST ASCII BASIC sources.
	- The demos should be understood and the 00529-CONVERT.TXT demo should be explained in detail in the BASIC-MANUAL.md


## Guardrails:

- For the analysis, you can use uv to install local Python libraries. The MUST not be installed globally!!!

- Stay in this project folder, do not go to parent folders!



---




Go through the annotated sources in src/:
Make a map of relevant routines and functions of the source code for easy navigation and write it to BASIC-SYMBOLS.md?


By inspecting the relevant source codes in src/ (which now have extensive comments!!) and BASIC-ANALYSIS.md and BASIC-SYMBOLS.md:
Check if BASIC-ANALYSIS.md is missing something. Maybe surprise findings?

In BASIC-ANALYSIS.md: Explain: TOKEN2 and TOKEN3 for Extended commands, and check src if it is actually used…

Note that: "iNput" is a Keyword string, where the capital "N" has a special meaning to indicate how to use a short form. Make sure to understand this (from BASIC-ANALYSIS.md and the sources) and update BASIC-ANALYSIS.md and the BASIC-MANUAL.md

Check if BASIC-MANUAL.md is missing something.


In BASIC-ANALYSIS.md: Explain the memory organisation in more details, specifically what areas grow and which relocated (e.g. varbase), and the mechanisms and sources where that happens.




In BASIC-ANALYSIS.md: Add Pseudo-Code for the principal interpreter loop and main logic (by inspecting the relevant source code in src/)
And also propose other parts of the source code where a Pseudo-Code version would help.
Understand that BASIC.S is a huge source file, be careful to make this detection of potential Pseudo-code candidates efficient.



In BASIC-ANALYSIS.md: Explain: TOKEN2 and TOKEN3 for Extended commands, and check src if it is actually used…

(❯ Cross-check your statements about LINE2 and LINE3 In BASIC-ANALYSIS.md. I am sure that you could write LINE x1, y1, x2, y2 in your BASIC sources, correct?)


Also note that I have added atari.s in                                     
  atari-tos-main/doc/additional_material with a list of hardware locations and their symbolic uses.  Check it to add more precise symbols to the
  commented sources, the BASIC-ANALYSIS.md , and possibly correct statements.




Investigate the syntax form of variable_name#type_suffix:
- Where is it defined in the source (BASIC_COMMENTS.S)?
- Is this already mentioned in BASIC-ANALYSIS.md and BASIC-MANUAL.md?






### Cleanup

I need more hands-on examples in the BASIC-MANUAL.md, for some relevent functions and also for specific topics like control flow, UI, etc.  Propose good examples typical in such manuals, then let me review first


Remove redundancies in BASIC-MANUAL.md, clean up, correct and organize sections best suited for reading.



For BASIC-ANALYSIS.md: remove redundancies, clean up, correct and organize sections best suited for reading.
The BASIC-ANALYSIS.md references BASIC.S whereas it is now BASIC_COMMENTS.S and has different lines count, since we added many comments!
Correct the references, and check what else needs to be fixed.

In BASIC-ANALYSIS.md: move the subsections under "16. Pseudo-Code for Key Algorithms" to where they are actually belong in the document, e.g. "16.6 Tokenizer" should go to section "Tokenizer Algorithm (konv_inpuf)".
Just move and adjust, don't remove any pseudo code!!




Are there any topics in BASIC-ANALYSIS.md left where Pseudo-Code of the implementation might help understanding? Suggest only. 

❯ OK, go ahead. And write also some motivations and explanations (and maybe findings) around the pseude code blocks (old and new).     


In BASIC-ANALYSIS.md: Cross the Pseudo-Code sections with BASIC_COMMENTS.S and if it helps: use the material atari-tos-main/doc/additional_material (about Atari ST TOS and 68000 assembler) as deeper understandings.


In BASIC-ANALYSIS.md:  Does it make sense to move the subsections from "16. Implementation Tricks and Surprise Findings" to the sections where the respective topics are covered? Maybe not all (so keep some). Propose first.

In BASIC-ANALYSIS.md: is there something missing about EDITOR.S or header.s? Propose first.

### Readme

Create a README.md for this project by consulting doc/BASIC-MANUAL.md

This is a reverse-engineering of a BASIC interpreter for the Atari ST

Here are some additional Historic Notes: Originally called FBasic (for FastBasic) from its creation in 1987, it was later in 1988 incorporated into the STAD drawing application as a add-on (although never got published). This version of the source was called SBasic (for STAD-Basic) internally.

Also check out the folders:
- src/ is the Source code of the Basic interpreters
- demos/ are demos (with explanations in top-level DEMOS.md)
- out/  are the object files and the executable (BASIC.PRG) (see src/BUILD.TXT)
- material/  contains the a zip (with assembler, linker from DRI 68K DevKit) and some relevant documentation about Atari ST TOS and hardware
- tmp/ leftover from reverse-engineering process, can be ignored!
- doc/ markdown files are results of a  reverse-engineering using the sources and the Atari ST material
	- Most relevant is MANUAL.md
	- For technical studies: ANALYSIS.md










---

## BASIC-GEMDOS_BIOS_XBIOS.md and a BASIC-GEM_VDI.md

The BASIC interpreter provides direct access 
- to the three Atari ST system trap interfaces GEMDOS/BIOS/XBIOS and
- GEM Application Environment Services (AES) and Virtual Device Interface (VDI) through dedicated control arrays
AES/VDI Access
- There is also the Line-A interface, that is currently used by LINE, and controlled via LPOKE.

Task: Using the atari-tos-main/doc/ folder and its SDK_DOCS_INDEX.md overview, provide a full list of how these can be utilized and called from the BASIC interpreter. Write out BASIC-GEMDOS_BIOS_XBIOS.md, BASIC-GEM_VDI_LINEA.md.
Come also up with examples.


Hint:
- atari-tos-main/doc/GEM/AES/README.md : easily accessible info about the GEM subsystem. Also: and also 
- Also under atari-tos-main/doc/BDOS check these subfolders out:
	- GEMDOS/, BIOS/, XBIOS/.
	- And LINEA/SALAD.TXT might be provide additional information for GEM, specifically the LINE A interface.



You can also update BASIC-MANUAL.md if you have new information that matters for users




## Examples

---
Here are some more BASIC examples:
Note, these are tokenized binary BASIC files (for LOAD).
Explain these step-by-step and write output to BASIC-EXAMPLES.md





Write out in BASIC-EXAMPLES.md a hanoi towers example, also a GEM demo that opens a windows and prints Hello World in it.           


Think about a BASIC demo that uses all relevant and nearly all of the other keywords/commands, operators, and variable of all types. Write out in BASIC-EXAMPLES.md.




Important: make sure that the BASIC-MANUAL.md really has correct syntax of the keywords, give me a feedback if there are inconsistancies!
Also: in BASIC-MANUAL.md: make sure that each keyword and operator has at least one example.
Also, add a cheat sheet chapter at the end.




