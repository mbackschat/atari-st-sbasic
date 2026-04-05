******************************************************************************
* 31.10.88
* struct        fÅr Editor
******************************************************************************
edi_base        equ     0               * Screenadresse
edi_screen      = edi_base+4            * Screenbreite in Bytes
edi_plan        = edi_screen+4          * unused
edi_x           = edi_plan+2            * links oben des Windows
edi_y           = edi_x+2
edi_ext         = edi_y+2
edi_breit       = edi_ext+4             * Pixelkoord
edi_hoch        = edi_breit+2           * Pixelkoord
edi_maxzeilen   = edi_hoch+2            * max. zeilen im editor (konst.)
edi_maxspalten  = edi_maxzeilen+2
edi_tab         = edi_maxspalten+2
edi_print       = edi_tab+2             * Ausgaberoutine eines Zeichens
*                                         d0 Zeichen, d1/d2 Pixelkoord.
edi_pgblock     = edi_print+4           * Anf.adr. der la-Routinen
edi_vrblock     = edi_pgblock+4         * Anf.adr. der Variablen
edi_retprg      = edi_vrblock+4         * Prgzeiger nach RET (0=basic)
edi_preup		 = edi_retprg+4
edi_up		 = edi_preup+4
edi_predown	 = edi_up+4
edi_down		 = edi_predown+4
edi_font        = edi_down+4          * Fontheaderadresse
edi_y_shft      = edi_font+4
******************************************************************************
.globl  ed_chkstop
.globl  b_init,b_enter,b_runcode,chk_stop,b_up,b_down,b_preup,b_predown
.globl  charget6        * fÅr blibf

anzops = 13	* es gibt 13 operatoren (+-*...) siehe optoktabl...
HEADER = $48454144	* header vor dem basic-prg

		ARRAYTYP	=	$8000	* bit 15
		FNTYP	=	$4000     * bit 14
		DEFFNTYP  =	$2000	* bit 13
		PROCTYP	=	$1000	* bit 12

          STRING    =    4
          INT       =    2
          FLOAT     =    1


		TOKEN1	= 	1		* die tokenintros 1,2,3
		TOKEN2	=	2
		TOKEN3	=	3

* Tokendefinitionen
          PRINT     =    $0100
          DIM       =    $0101
          LIST      =    $0102
          SAVE      =    $0103
          LOAD      =    $0104
          RUN       =    $0105
          CLR       =    $0106
          GOTO      =    $0107
          INT_FKT   =    $0108
          FOR       =    $0109
          TO        =    $010A
          STEP      =    $010B
          NEXT      =    $010C
          ENDPROC   =    $010D
          GOSUB     =    $010E
          RETURN    =    $010F
          IF        =    $0110
          THEN      =    $0111
          ELSE      =    $0112
          FRE       =    $0113
          CREATE    =    $0114
          STRFRE    =    $0115
          MERGE     =    $0116
          REM       =    $0117
          STOP      =    $0118
          HELP      =    $0119
          NEW       =    $011a
          DEFFN     =    $011b
          FN        =    $011c
          INPUT     =    $011d
          ON        =    $011e
          OPEN      =    $011f
          CLOSE     =    $0120
          SPC       =    $0121
          TAB       =    $0122
          DATA      =    $0123
          READ      =    $0124
          RESTORE   =    $0125
          GET       =    $0126
          LEN       =    $0127
          STRFKT    =    $0128
          VAL       =    $0129
          FUNCTION  =    $012a
          ASC       =    $012b
          CHR       =    $012c
          LEFT      =    $012d
          RIGHT     =    $012e
          MID       =    $012f
          POS       =    $0130
          NOT       =    $0131
          CMD       =    $0132
          POKE      =    $0133
          PEEK      =    $0134
          SIN       =    $0135
          COS       =    $0136
          SQR       =    $0137
          LOG       =    $0138
          LN        =    $0139
          EXP10     =    $013a
          TAN       =    $013b
          ATN       =    $013c
          EXP       =    $013d
          SGN       =    $013e
          ABS       =    $013f
          RND       =    $0140
          SYS       =    $0141
          CONT      =    $0142
          CLS       =    $0143
          DPEEK     =    $0144
          DPOKE     =    $0145
          LPEEK     =    $0146
          LPOKE     =    $0147
          ATNPT     =    $0148
          MOD       =    $0149
          GEMDOS    =    $014a
          BIOS      =    $014b
          XBIOS     =    $014c
          VARPTR    =    $014d
          DIR       =    $014e
          HEX       =    $014f
          BIN       =    $0150
          CURSOR    =    $0151
		PROC		=	$0152
		END		=	$0153
		LOCAL	=	$0154
		DELETE	=	$0155
		INKEY	=	$0156
		WAIT		=	$0157
		SWAP		=	$0158
		TRON		=	$0159
		TROFF	=	$015a
		INSTR	=	$015b
		CALL		=	$015c
		AESCTRL	=	$015d
		AESINTIN	=	$015e
		AESINTOUT	=	$015f
		AESADRIN	=	$0160
		AESADROUT	=	$0161
		VDICTRL	=	$0162
		VDIINTIN	=	$0163
		VDIINTOUT	=	$0164
		VDIPTSIN	=	$0165
		VDIPTSOUT	=	$0166
		AES		=	$0167
		VDI		=	$0168
		CONVERT	=	$0169
		DUMP		=	$016a
		TRACE	=	$016b
		AND		=	$016c
		OR		=	$016d
		EOR		=	$016e
		AUTO		=	$016f
		EDTAB	=	$0170
****************
          LINE2     =    $0200          * 7.11.88
          LINE3	=	$0300
****************
.text
tab_:
          tst.w     filefl
          beq       ed_tab
          movem.l   d0-d2/a0-a2,-(sp)
          moveq.l   #1,d0
          move.b    #9,key
          lea       key,a1
          bsr       f_write
          movem.l   (sp)+,d0-d2/a0-a2
          rts

* jetzt string in a0 [... rÅckwÑrts ausgeben
putstrreverse:
          movem.l   d1/a0,-(sp)
          addq.l    #1,a0
putrvl9:
          move.b    (a0),d1
          clr.b     (a0)
          subq.l    #1,a0
          bsr       put_string
          move.b    d1,1(a0)
          tst.b     (a0)
          bne       putrvl9
          movem.l   (sp)+,d1/a0
          rts


put_string:
          tst.w     filefl
          beq       ed_print

* ausgabe auf dem file
          movem.l   d0-d2/a0-a2,-(sp)
          move.l    a0,a1
          moveq.l   #1,d0          * immer nur ein byte ausgeben
prfl2:
          move.b    (a1),d1
          beq       hsoend
          movem.l   d0/a1,-(sp)
          cmp.b     #13,d1         * RET?
          bne       prfl1
          move.b    #10,key2       * LF ausgeben
          lea       key2,a1
          bsr       f_write
          movem.l   (sp)+,d0/a1
          movem.l   d0/a1,-(sp)
prfl1:
          bsr       f_write
          movem.l   (sp)+,d0/a1
          addq.l    #1,a1
          bra       prfl2
hsoend:
          movem.l   (sp)+,d0-d2/a0-a2
          rts
*****************************************
* fragt die stop-taste ab...ggf aufhîren
ed_chkstop:	* wird aus scroll-rout aus editor aufgerufen
		tst.w	b_modus			* nur unterbrechbar wenn direktmodus!
		beq		chk_stop
		rts

chk_stop:
          move.l    a0,-(sp)
		move.w	#-1,-(sp)
		move.w	#11,-(sp)
		trap		#$d
		addq.l	#4,sp
		and.w	#%1000,d0			* ALT?
          beq		nostoperr

		move.w	#7,-(sp)
		move.w	#2,-(sp)
		move.w	#3,-(sp)
		trap		#13				* klingel zeichen!
		addq.l	#6,sp
		move.w	#7,-(sp)
		trap		#1
		addq.l	#2,sp
		swap		d0
		cmp.b	#$61,d0			* ALT und UNDO?
		bne		nostoperr
		move.l	(sp)+,a0
		bra		stoperr
nostoperr:
		move.l	(sp)+,a0
          rts


********************************************************************************
**   Beginn des BASICs                                                        **
********************************************************************************
b_init:
		move.l	edibase,a0
		clr.l	d0
		move.w	edi_maxspalten(a0),d0
		move.l	d0,maxspalten
* zunÑchst in den cmd-strings die geshifteten in bit7=1 wandeln
          lea       token1adr,a0
basicl1:  tst.l     (a0)
          beq       basic_              * alle cmds schon durch?
          move.l    (a0)+,a1             * zeiger auf cmd-string
basicl2:  move.b    (a1)+,d0
          beq       basicl1
          cmp.b     #'Z',d0
          bhi       basicl2
          cmp.b     #'A',d0             * nicht im bereich
          blt       basicl2
          add.b     #$20,d0             * wieder in kleinbuchstabe wandeln
          bset      #7,d0               * aber mit bit7 gesetzt
          move.b    d0,-1(a1)           * wieder schreiben
          bra       basicl1
basic_:                                 * hier geht das richtige basicinit. los
          move.l    #-1,contline        * cont nicht erlaubt
		move.l	#-1,traceline
		bsr		New1
          bra       Clr1
          
********************************************************************************
* Befehlszeileneingabeschleife
basic1:
          bsr       clrfilefl
		tst.w	autofl 			* nach <autox,y> kein ready ausgeben!
		bne		basic2
          lea       ready,a0            * bereitschaft zeigen
          bsr       put_string
basic2:
          bsr       clrfilefl
          bsr       restore
          clr.w     argfl
          clr.w     b_modus             * auf direktmodus schalten
          clr.w     ifcnt
          bsr       init_tbls           * for-next/gosub/if-tables lîschen
		tst.l	contline			* akt_zeile bei non-cont lîschen!
		bpl		quit2
		clr.l	akt_zeile
quit2:
* und jetzt auto...
		tst.w	autofl			* auto an?
		beq		posquit
		move.w	ed_x,d0
		add.w	ed_xoffs,d0		* testen, ob zeilenstart
		beq		quit2a
		bsr		ed_newline		* mitten in zeile, dann neue zeile
quit2a:
		move.l	autozeile,d0
		move.l	d0,-(sp)
		bsr		ipka_
		move.w	filefl,-(sp)
		clr.w	filefl			* unbedingt auf screen ausgeben
		lea		-1(a2),a0
		bsr		putstrreverse
		lea		key,a0
		move.w	#$2000,(a0)		* SPACE+0
		bsr		put_string
		move.w	(sp)+,filefl		* jetzt ggf. wieder auf file
		move.l	(sp)+,d0
		add.l	autoadd,d0
		bpl		quit2b
		clr.w	autofl			* wenn zeilencnt Åbergelaufen -> ende
quit2b:
		move.l	d0,autozeile

posquit:
          move.l    oldstack,sp
          moveq.l   #0,d0
          rts
quit:
          move.l    oldstack,sp
          moveq.l   #-1,d0
          rts

oldstack:
          .ds.l     1
********************************************************************************
**   Start des Hauptprogrammes                                                **
********************************************************************************
* b_runcode ist genauso wie b_enter, doch zeigt a0 nicht in den editorscreen
* sondern in einen kleineren puffer. d0 wurde hier der eingabelenge angeglichen
* und hat deshalb nicht mit der Var. maxspalten zu tun, die ja die max. laenge
* einer editor-zeile angibt.
b_enter:
          move.l    d0,maxspalten
b_runcode:
          move.l    sp,oldstack
          lea       stack,sp
          bsr       copy_inpuf
          bsr       konv_inpuf
          bsr       ed_newline          * neue zeile (unbedingt auf screen)
          lea       input_puf,a0

          bsr       charget
		bne		b_runc1
		clr.w	autofl			* leere zeile -> auto aus
          bra       basic2
b_runc1:
          cmp.b     #'!',d0  
		bne		b_runc2
		clr.w	autofl			* ende -> auto aus
          bra       quit
b_runc2:
          cmp.b     #'0',d0  
          blt       exec_puf
          cmp.b     #'9',d0   
          bhi       exec_puf

		subq.l	#1,a0
		bsr		zeilenverwaltung
		bra		basic2

* A0 zeigt auf gewandelte zeile (2 0er als ende)
zeilenverwaltung:
          move.l    #-1,contline        * wenn zeile verÑndert -> no cont!
		move.l	#-1,traceline
          tst.w     fncnt               * nur variablen lîschen, wenn fn def
          bne       zv1
		tst.w	anzprocs
		beq		insline			* bzw. procs angelegt sind!
zv1:
          bsr       Clr1

insline:  * zeile -> in listing einfÅgen
          bsr       get_int             * holt integerwert in d0.l
          tst.b     (a0)                * wenn nur zeilennr, dann zeile lîschen
          bne       basic20
delline:  * zeile -> aus listing lîschen (d0 ist zeilennr.!)
		tst.w	autofl
		beq		delline1
		clr.w	autofl			* del line -> auto aus
		bra		endezv
delline1:
          bsr       poszeile
delline2:	* d0 = zeilennr, a1 = zeiger auf zeile
          cmp.l     4(a1),d0            * ist zeile auch wirklich vorhanden?
          bne       endezv              * nein, dann zur basic-schleife back
          move.l    a1,a3
          move.l    (a1),a2
          move.l    a2,d0
          sub.l     a1,d0               * lÑnge
basic3:   move.b    (a2)+,(a1)+
          cmp.l     varend,a2
          bne       basic3
basic3b:  sub.l     d0,prgend
          sub.l     d0,varbase
          sub.l     d0,varend
          clr.l     (a1)                * und neu linken...
basic3a:  tst.l     (a3)
          beq       basic3c
          sub.l     d0,(a3)
          move.l    (a3),a3
          bra       basic3a

basic3c:  * vars neu linken (d0.l ist distanzwert zur alten pos)
          move.l    varbase,a1
lll3:
		cmp.l	varend,a1			* ende der vars erreicht?
          beq       endezv              * und in interpreter back
          move.l    (a1),d1
          sub.l     d0,d1
          move.l    d1,(a1)
          move.l    d1,a1
          bra       lll3

* neu einfÅgen
* D0 ist zeilennr.
* A0 zeigt auf zeilendaten
basic20:
          move.l    a0,a1
basic2a:  tst.b     (a1)+               * zeilenende (0) durch (ffff) ersetzen
          bne.s     basic2a
          tst.b     (a1)+               * 2 0er als ende in zeile sollte reichen
          bne.s     basic2a
          move.l    a1,d1
          sub.l     a0,d1               * lÑnge der zeile in d1.l (xxx = 3)
          btst      #0,d1               * ungerade, dann gerade machen
          beq       basic2b
          addq.l    #1,d1
basic2b:
          move.l    d1,d3               * retten (lÑnge)
          bsr       poszeile            * auf old bzw. nÑchste zeile
          cmp.l     4(a1),d0            * ist gleiche zeile, so nur teilw. einf.
          bne       basic2c             * muss vollkommen neu angelegt werden
          move.l    (a1),d2             * ptr auf next line
          lea       8(a1),a2
          sub.l     a2,d2               * lÑnge der tokenzeile
          cmp.l     d1,d2               * beide lÑngen vergleichen
          ble       basic2d             * es muss nur noch etwas eingefÅgt
          sub.l     d1,d2               * d2 bytes mÅssen entfernt werden!
          move.l    a2,a3
          add.l     d2,a3
basic2e:  move.b    (a3)+,(a2)+
          cmp.l     varend,a3           * prg+variablen zurÅckkopieren
          bne       basic2e
          clr.l     (a2)
          neg.l     d2                  * neg (wg sub.l d2)
basic2f:  * neu linken
          move.l    a1,a2               * ptr auf sich selbst
          move.l    a2,(a2)
          addq.l    #8,(a2)             * auf cmdtail
          add.l     d3,(a2)             * -> auf nÑchste zeile (8+len)
          add.l     d2,prgend           * endeptr auf prg neu setzen
          add.l     d2,varbase          * var.start update
          add.l     d2,varend           * varend update
          move.l    prgend,a4
          clr.l     (a4)                * basic-prg-ende markieren
          bra       basic2f2
basic2f1: move.l    a2,a3               * kurzfristig merken
          add.l     d2,(a2)             * und dann neu durchlinken...
basic2f2: move.l    (a2),a2             * ptr auf next line
          cmp.l     a2,d2               * ist ptr = 0 gewesen?
          bne       basic2f1

          bsr       basic2h             * zeile kopieren
          move.l    d2,d0
          neg.l     d0
          bra       basic3c             * vars link * back

basic2d:  * es muss nur noch kleines stÅck angehangen werden
          sub.l     d2,d1               * lÑnge des stÅcks
          bne       basic2c2            * wenn lÑngen gleich, gl. kopieren
          bsr       basic2h             * nur kopy ohne var-link
          bra       endezv

basic2c:  * es muss eine zeile ab a1 mit d1(+8 headerbytes) angelegt werden
          addq.l    #8,d1               * header zusÑtzl. anlegen
basic2c2: move.l    varend,a2
          lea       -32(a2,d1.l),a3
          cmp.l     strend,a3          * speicher schon voll?
          bge       outprgmem
          add.l     #32,a3
		clr.l	(a3)
basic2g:  move.b    -(a2),-(a3)         * prg/vars nach oben kopieren
          cmp.l     a1,a2
          bhi       basic2g
basic2j:  move.l    d1,d2               * und auch hier neu durchlinken
          bra       basic2f

basic2h:  * zeile kopieren
          addq.l    #4,a1               * ptr Åbergehen
          move.l    d0,(a1)+            * zeilennr
basic2i:  move.b    (a0)+,(a1)+
          subq.l    #1,d3
          bne       basic2i
          move.l    prgend,a0
          clr.l     (a0)+               * basic-prg-ende markieren
          move.l    #-1,(a0)
endezv:
          rts


*****************************************
* Gibt ein Return aus
new_line:
          move.l    a0,-(sp)
          lea       key,a0
          move.b    #$0d,(a0)
          bsr       put_string
          move.l    (sp)+,a0
          rts
*****************************************
* unterroutine, die in abhÑng. von cmdfl filefl ausschaltet oder nicht
clrfilefl:
          tst.w     cmdfl               * filefl nur ausschalten, wenn cmd aus
          bne       clrfend
          clr.w     filefl
clrfend:  rts

*****************************************
* Kopiert Eingabe in Basicarbeitspuffer/ Setzt Cursor eine Zeile tiefer
copy_inpuf:
          * A0 Zeiger auf Zeile
          * D0 ist max. ZeilenlÑnge
          move.l    a0,a1
          lea       input_puf,a0
* A1 Zeiger auf Zeile
* D0 max. LÑnge
* A0 Zielpuffer (input_puf)
copya1_ina0:
		ext.l	d0
          lea       0(a1,d0),a2
coi1:     moveq     #0,d7
seek_st:
          addq.l    #1,d7
          cmp.b     d0,d7
          beq.s     seekend
          cmp.b     #$20,(a1)+
          beq.s     seek_st
          subq.l    #1,a1
          move.l    d0,d7
          addq.l    #1,d7
seek_end:
          subq.l    #1,d7
          beq.s     seekend
          move.b    -(a2),d0
          cmp.b     #$20,d0
          beq.s     seek_end
          addq.l    #1,a2
seek1:    move.b    (a1)+,(a0)+
          cmp.l     a1,a2
          bne.s     seek1
seekend:  bsr       clrendpuf
          rts
*****************************************
* Wandelt Befehlsstrings in Token um
konv_inpuf:
          lea       input_puf,a0
          clr.w     d7                  * Hochkommaflag = 0/Befehle
konv0:
		move.b    (a0)+,d0
		beq		konvend
          tst.w     d7
          bne.s     konv1

		cmp.b     #'?',d0             * SOnderfall ? fÅr print?
          beq       konvcmd			* ist befehl

		cmp.l	#input_puf+1,a0	* 1. zeichen im puffer?
		beq		konv0a
		move.b	d0,d1
		move.b	-2(a0),d0
		bsr		isvarn			* testen, ob cmd im varname sein kînnte		beq		konv0
		beq		konv0
		move.b	d1,d0
konv0a:
		cmp.b	#'A',d0
		blo		konv1
		cmp.b	#'Z',d0
		bls		konvCmd			* befehl (in grossbuchstaben)
          cmp.b     #'a',d0
          blo		konv1
          cmp.b     #'z',d0
          bls       konvcmd			* befehl (in kleinbuchstaben)
konv1:
		cmp.b	#$27,d0			* ' (rem)?
		bne		konv1a
		tst.w	d7				* wenn innerhalb ".." dann nichts
		bne		konv2
		not.w	d7
		bra		konv2
konv1a:
		cmp.b     #$22,d0             * Hochkomma?
          bne.s     konv2
          not.w     d7
konv2:
		bra		konv0


konvCmd:
		moveq.l	#1,d1			* befehl ist gross
		bra		konvcmd1
konvcmd:
		clr.l	d1				* befehl ist klein
konvcmd1:
          lea    	-1(a0),a1           * merken
          moveq     #0,d6               * Starttoken ist #0
          cmp.b     #'?',d0             * ist es sonderfall print?
          bne       konv3

		lea		inpuf2_end-2,a2
konvprl:
		move.b	-(a2),1(a2)		* ein zeichen einfÅgen!
		cmp.l	a0,a2
		bne		konvprl
          bra       token2found

konv3:
		lea       tokenstr,a2
konv5:
          move.b    (a2)+,d2
		tst.b	d1				* befehl in klein/grossbuchstaben?
		beq		inklein
* vergleich tokenstr und GROSSCMD
		bclr		#7,d2			* in grosschrift keine abkÅrzung
		or.b		#$20,d0			* in kleinschrift
		cmp.b	d0,d2			* vergleichen
		bne		nexttoken
		bra		nextcmp
* vergleich tokenstr und KLEINCMD
inklein:
		btst		#5,d0			* befehl geshiftet?
		bne		konv5a			* nein
		bset		#7,d0
		or.b		#$20,d0			* in kleinschrift
		cmp.b     d0,d2			* shortform?
		beq		tokenfound
		bra		nexttoken			* liSt != list/lI
konv5a:
		bclr		#7,d2
		cmp.b	d0,d2
		bne		nexttoken
nextcmp:
		tst.b	(a2)
		beq		tokenfound
		move.b	(a0)+,d0
		bne		konv5
		beq		nexttoken
konvback:
		lea		1(a1),a0			* um ein zeichen versetzt neu beginnen
		bra		konv0
		
nexttoken:
          move.l    a1,a0
nt1:
		tst.b     (a2)+			* nÑchstes token suchen
          bne.s     nt1
          addq.l    #1,d6			* eine token# weiter
          tst.b     (a2)				* war's letztes token?
          beq       konvback
		move.b	(a0)+,d0
		bra		konv5

tokenfound:
		move.b	(a0),d0
		bsr		isvarn
		beq		konvback
token2found:
          move.l    #inpuf2_end-2,d0
          sub.l     a0,d0
          lsl.l     #1,d6
          lea       tokennr,a3
          move.b    (a3,d6.l),(a1)+
          move.b    1(a3,d6.l),(a1)+
          move.l    a1,a2
          tst.w     d0
          beq       tf3
		cmp.l	a2,a0
		ble		tf3
tf1:      move.b    (a0)+,d1
          move.b    d1,(a2)+
          dbf       d0,tf1
          clr.b     (a2)
tf3:
		move.l	a1,a0
		bra		konv2

konvend:
clrendpuf:
          clr.b     (a0)+
          clr.b     (a0)+
          clr.b     (a0)+
          clr.b     (a0)+
          rts

* testet, ob d0.b zeichen einer var sein kann
isvarn:
		cmp.b	#'0',d0
		blo		isvarname
		cmp.b	#'9',d0
		bls		isvarpos
* testet, ob d0.b das 1. zeichen einer variablen sein kann
isvarname:
		tst.b	d0
		bmi		isvarpos

		cmp.b	#'a',d0
		blo		isvn1
		cmp.b	#'z',d0
		bls		isvarpos
isvn1:
		cmp.b	#'A',d0
		blo		isvn2
		cmp.b	#'Z',d0
		bls		isvarpos
isvn2:
		cmp.b	#$5f,d0
		bne		isvarneg

isvarpos:
		cmp.b	d0,d0
		rts
isvarneg:
		cmp.b	#'a',d0
		rts


*****************************************
* Puffer ausfÅhren
exec_puf:
		clr.w	autofl
          lea       input_puf,a0
          bsr       exec_line
          bra       basic1
*****************************************
* Zeile ausfÅhren
exec_line:
exec1:
          bsr       chk_stop            * stop-taste abfragen + ggf. enden
          bsr       charget             * Zeichen holen
          beq       exec_end

		tst.b	b_modus
		beq		execnotrace
		cmp.w	#1,tracefl
		bne		notrace
		bsr		trace			* d0 ist akt. befehl, a0 zeigt dahinter
		bra		execnotrace
notrace:
		cmp.w	#2,tracefl		* gerade von trace gosub zurÅck?
		bne		execnotrace
		move.w	#1,tracefl
execnotrace:
          cmp.b     #TOKEN1,d0		* Hibyte muss 1 sein!
          beq       exec2
		cmp.b	#TOKEN2,d0
		beq		exec2
		cmp.b	#TOKEN3,d0
		beq		exec2

          subq.l    #1,a0               * Auf anfang des Namens pos.
		cmp.b	#'&'+1,d0			* zeichen nach & ist ' (nicht darstellbar!)
		bne		exec0c
		move.w	#REM,d0			* ' ist ersatz fÅr REM!
		bra		exec0b
exec0c:		
		cmp.b	#'0',d0			* ist es eine zeilennr?
		blt		exec0a
		cmp.b	#'9',d0
		bhi		exec0a
		move.w	#GOTO,d0			* eine zahl -> ersatz fÅr goto x
		bra		exec0b
exec0a:
          move.w    #-1,sysallow        * system-var dÅrfen def. werden
          bsr       var_def             * a = ...-Befehl
          bra       exec3

exec2:
          move.b    (a0)+,d1            * Vorerst nur Lowbyte verwenden!
		bra		exec0ba
exec0b:
		move.b	d0,d1
		lsr.w	#8,d0
exec0ba:
		and.w	#$ff,d0
		lsl.w	#2,d0			* .l tab
		lea		comadr,a1
		move.l	(a1,d0),a1
		and.w	#$ff,d1
          lsl.w     #2,d1
          move.l    (a1,d1),d0		* A0 muss von befehl mitgezogen werden
          btst      #31,d0              * wenn gesetzt, dann funktion -> synerr
          beq		onlyexec
		btst		#28,d0			* wenn bit28 gesetz, dann com/fkt
		beq		nocmderr
		clr.w	cmdfktfl			* 0:aufruf als cmd
onlyexec:
          btst      #30,d0              * wenn gesetzt, dann nur im prg mgl!
          beq       exec2a
          tst.w     b_modus
          beq       dircterr            * illegal direct err
exec2a:   btst      #29,d0              * wenn gesetzt, dann nur im direktm. mgl
          beq       exec2b
          tst.w     b_modus
          bne       prgmerr
exec2b:   and.l     #$00ffffff,d0
          move.l    d0,a2
          jsr       (a2)
exec3:
          bsr       chargot             * auf letztes gelesenes Zeichen testen
          beq       exec_end            * Zeilenende ?
          cmp.b     #':',d0             * Befehlstrenner?
          bne       syntaxerr           * nein, dann Syntaxfehler!
          bra       exec1
exec_end:
          rts
********************************************************************************
* VARIABLEN
********************************************************************************
* Definition einer variablen
* sysallow besagt (-1) sysvar erlaubt, (0) nicht!
* a0 zeigt auf anfang des statements
var_def:
		move.l	a0,-(sp)
		clr.w	d7				* "-Flag
tstvarproc:
		move.b	(a0)+,d0			* unterscheidung var/proc
		beq		isproc			* -> bei var syntax:  var =...
		cmp.b	#'"',d0			* in/aus string?
		bne		tst2varproc
		not.w	d7				* str-fl switchen
tst2varproc:
		tst.w	d7         		* wenn im str dann nicht =: checken!
		bne		tstvarproc
		cmp.b	#'=',d0			* -> bei proc synt:   proc($0,:)
		beq		isvar
		cmp.b	#':',d0
		bne		tstvarproc	
isproc:
		move.l	(sp)+,a0
		bra		Proc				* direkt in den Proc-Befehl!
isvar:
		move.l	(sp)+,a0

          bsr       tst_var             * var testen
          move.w    sysvar,-(sp)
          bsr       var3_def            * var holen ggf. anlegen
          move.l    a6,-(sp)
          cmp.l     #0,a6               * wenn alt, noch nicht als ungÅltig!!!!
          beq       ll10
          clr.b     (a6)                * string wieder gÅltig
ll10:
          move.l    a1,-(sp)
          bsr       charget
          cmp.b     #'=',d0
          bne       syntaxerr
          bsr       get_defterm         * variablezuweisung einlesen
          move.l    (sp)+,a1
          move.l    (sp)+,a6            * mgl. zeiger auf markstr-ff
          cmp.l     #0,a6
          beq       ll10a
          move.b    #$ff,(a6)           * jetzt kann er freigegeben werden!
ll10a:
          move.w    (sp)+,d0            * sysvarfl (-2 = tiint/-3 = tistr)
          bpl       def_cont            * kein sysvar
          tst.w     sysallow            * sind sys.var Åberhaupt erlaubt?
          beq       syserr              * nein!
          cmp.w     #-2,d0
          beq       setti
          cmp.w     #-3,d0
          beq       settistr
          tst.w     d0                  * pi und andere sysvar not writeable!
          bmi       syserr
def_cont: bra       write_var

* Unterroutine von def_var. Holt Var und legt ggf an
* -> a1 zeigt wert, typvalid auf typ
var2_def:
          bsr       tst_var             * testet auf Variable und holt ggf adr.
          bsr       tstsysvar
var3_def: * einsprungpunkt hinter sysvar test
          move.w    typflag,typvalid
          move.w    d0,-(sp)            * flag merken
          tst.w     d0
          bne       def_v1              * ja, schon definiert
          bsr       create2_var
def_v1:
          tst.b     arrayfl
          beq       def_v2
          bsr       posarray            * holt argument und positioniert (->a1)
          bsr       chk_klammer
def_v2:
          move.w    (sp)+,d0            * flag, ob var. neu o. alt war
          tst.w     d0
          beq       def_v3
          move.b    typvalid+1,d0       * nur unteres byte (egal ob array...)
          cmp.b     #STRING,d0
          bne       def_v3
          bsr       mark_str            * alt, dann alten string mit $ff mark.
          rts
def_v3:
          clr.l     a6
          rts

*****************************************
* markiert stringende mit -1 -> bei garbage col. kann entfernt werden
* -> a6 zeiger auf ff
mark_str:
          move.l    (a1),a6             * zeiger holen
          cmp.l     #zero_+4,a6
          beq       markend
          cmp.l     #0,a6
          beq       markend             * bei leerstrings nichts machen!
		addq.l	#1,a6
markstr1:
          tst.b     -(a6)
          bne       markstr1
          move.b    #-1,(a6)
          rts
markend:
          clr.l     a6
          rts

*****************************************
* positioniert auf ein arrayelement (angegeben zwischen klammern)
* a1 muss auf Infoheader II (anz dim....) zeigen
* -> a1 zeigt auf wert
posarray:
          movem.l   d0-d7/a2-a6,-(sp)   * alles erstmal sichern
          move.w    typflag,-(sp)
          move.w    typ2flag,-(sp)
          move.w    typvalid,-(sp)
          move.l    (a1)+,d0
          move.l    d0,arraydeep
          moveq     #0,d1
          lsl.l     #2,d0
          lea       array2len,a2
posa0:
          move.l    (a1)+,(a2,d1)
          addq.l    #4,d1
          cmp.l     d0,d1
          bne       posa0

          moveq     #0,d0               * beginnen mit dimension 1
posa2:
          move.l    d0,-(sp)
          move.l    a1,-(sp)
          bsr       get_aterm
          move.l    (sp)+,a1
          move.l    (sp)+,d0

          move.l    d0,d1
          lsl.l     #2,d1
		lea		array2len,a3
          lea       arraylen,a2

          move.l    fac1,d3
		bmi		negdimerr
          cmp.l     (a3,d1),d3          * feldlÑnge grîsser als erlaubt?
          bcc       badsubscr           * dann fehler!
          move.l    d3,(a2,d1)          * lÑnge der aktuellen dim. schreiben
          addq.l    #1,d0
          cmp.l     arraydeep,d0        * ende der dim. erreicht?
          beq       posa1

          move.w    d0,d7
          bsr       chk_komma
          move.w    d7,d0
          bra       posa2

posa1:
          lsl.l     #2,d0               * zur weiterverarbeitung fÅr lw-adres.
		clr.l	d1				* hier wird alles aufaddiert!
		move.l	#1,fac2			* hier multiplikator
posa1a:
          subq.l    #4,d0
          bmi		posa1b              * alle dimensionen durchmultipliziert?
          move.l    (a2,d0),fac1		
          bsr       submul
		add.l	fac1,d1			* und zur gesamtpos addieren
		move.l	(a3,d0),fac1
		bsr		submul			* jetzt multiplikator updaten!
		move.l	fac1,fac2
          bra       posa1a
posa1b:
          move.w    (sp)+,typvalid
          move.w    (sp)+,typ2flag
          move.w    (sp)+,typflag
          moveq.l   #4,d0
          cmp.w     #FLOAT,typflag
          bne       posa1e
          moveq.l   #12,d0
posa1e:
          move.l    d1,fac1
          move.l    d0,fac2
          bsr       submul
          add.l     fac1,a1
          movem.l   (sp)+,d0-d7/a2-a6 
          rts


*****************************************
* liest einen wert/strptr in einen variablenwert
* a1 zeiger auf den variablenwert
* -> a1 zeigt auf ptr der nÑchsten var.
* -> a2 zeigt auf den variablenwert
write_var:
          movem.l   d0-d7/a3-a6,-(sp)
          move.l    a1,a2
          move.w    typvalid,d4         * je nach typ schreiben
          cmp.w     #STRING,d4          * string?
          beq       write_str
          movem.l   fac1,d0-d3
          cmp.w     #FLOAT,d4           * float?
          beq       write_fl
write_int:
          move.l    d0,(a1)+
          bra       write_end
write_fl:
          movem.l   d0-d2,(a1)
          add.l     #12,a1              * a1 erneuern
          bra       write_end
write_str:
          move.l    str_ptr,(a1)+
write_end:movem.l   (sp)+,d0-d7/a3-a6
          rts
*****************************************
* liest den variablenwert/ bzw. holt ptr auf string
* a1 zeigt auf den variablenwert
* -> float/int: d0-d3 bzw string:a1 auf string
read_var:
          movem.l   d4-d7/a2-a6,-(sp)
          move.w    typflag,d0
          cmp.w     #STRING,d0          * string?
          beq       read_str
          cmp.w     #FLOAT,d0           * float?
          beq       read_fl
read_int:
          move.l    (a1),d0
          bra       read_end
read_fl:
          movem.l   (a1),d0-d2         * float lesen
          moveq     #0,d3
          bra       read_end
read_str:
          move.l    (a1),a1
          cmp.l     #0,a1               * auf leerstring testen
          bne       read_end
          lea       leer_str+2,a1
read_end:
          movem.l   (sp)+,d4-d7/a2-a6
          rts

*****************************************
* erzeugt eine variable
* namen beginnt bei var_name- 0-kode
* typvalid enthÑlt typ
* arrayfl = 1 -> array -> arraydeep anz. dimens., arraylen[arraydeep] je lÑnge
* -> a1 zeigt auf wert der var.
create2_var:
          tst.b     arrayfl             * beim anlegen auf arrayvar. achten
          beq       cr2_v1
          move.l    #1,arraydeep        * anlegen einer autom. arrayvar
          move.l    #11,arraylen        * -> autom. 1D und LÑnge von 11 Elem.
cr2_v1:
*         bra       create_var          * variable anlegen

create_var:
          movem.l   d0-d7/a2-a6,-(sp)
          move.l    varend,a1           * zeiger auf ende der var.
          lea       var_name,a3
          move.l    strend,a4
          sub.l     #32,a4
          cmp.l     a4,a1               * schon pufferende erreicht?
          bge       outvarmem
          move.l    a1,a4               * ptr erstmal retten
          addq.l    #4,a1
          move.w    typvalid,d1
          tst.b     arrayfl
          beq       cv3a
          bset      #15,d1              * oberstes bit -> array
cv3a:     move.w    d1,(a1)+            * typflag setzen
cv3:
          move.b    (a3)+,(a1)+         * name einsetzen
          bne       cv3
          move.l    a1,d0
          btst      #0,d0
          beq       cv4                 * a1 muss gerade sein
          clr.b     (a1)+
cv4:
          move.l    a1,a2
          moveq     #1,d2               * anzahl Lwords fÅr eine var (default)
          btst      #13,d1              * ist es funktionsvar (a = )?
          bne       cv4c                * ja, dann wird ptr auf fkt. angelegt
		btst		#12,d1			* ist es proc?
		bne		cv4c
		and.w	#INT+FLOAT+STRING,d1	* procnr ausblenden!
          cmp.b     #FLOAT,d1           * nur unteres byte (oberes mgl. gesetzt)
          bne       cv4d
          moveq     #3,d2
cv4d:
          tst.b     arrayfl             * nochmals arrays testen
          beq       cv4c

* arrayvariablen-lîschroutine
          move.l    arraydeep,d1        * anz dimensionen
          move.l    d1,(a2)+
          lea       arraylen,a3
cv4c1:    move.l    (a3)+,d3
          addq.l    #1,d3               * im speicher statt von 0 mit 1 starten
          move.l    d3,fac1
          move.l    d3,(a2)+
          subq.l    #1,d1
          beq       cv4c2
cv4c3:    move.l    (a3)+,d3
          addq.l    #1,d3
          move.l    d3,fac2
          move.l    d3,(a2)+
          bsr       submul
          subq.l    #1,d1
          bne       cv4c3
cv4c2:
          move.l    d2,fac2
          bsr       submul
          move.l    fac1,d0             * anzahl der zu lîschenden langworte
          move.l    d0,d1
          lsl.l     #2,d1               * lw in byte anzahl wandeln
          lea       (a2,d1.l),a3
          move.l    a4,-(sp)
          move.l    strend,a4
          sub.l     #32,a4
          cmp.l     a4,a3                 * schon pufferende erreicht?
          bge       outvarmem
          move.l    (sp)+,a4
cv4c4:    clr.l     (a2)+
          subq.l    #1,d0
          bne       cv4c4
          bra       cv5

* normale variablen-lîschroutine
cv4a:     clr.l     (a2)+               * lîscht variable
cv4c:     dbf       d2,cv4a
cv5:
          move.l    a2,(a4)             * zeigt auf 1. leere var.
          move.l    a2,varend           * zeigt auf ende der var.
          clr.l     (a2)
          movem.l   (sp)+,d0-d7/a2-a6
          rts

*****************************************
* Testet auf Variablenname, holt ggf. Wert
* a0 zeigt auf Variablenname
* -> BNE gefunden! -> a1 enthÑlt Adresse, typflag typ der variablen
*     (d0 = -1 beim 1. mal [lokal], d0 = 1 beim 2.mal [global]
* -> arrayfl = 1 wenn arrayvariable angesprochen
* -> sysvar.w = 0 (keine)/ 1 (sys.var.)
*****************************************
tst_prcvar:
		move.w	procnr,d0
		bra		tstspecVar

tst_dprcvar:
          move.w	#PROCTYP,d0
		bra		tstspecVar

tst_dfnvar:
          move.w    #DEFFNTYP,d0		* funktionsvar! , es wird auf bit13
tstspecVar:
          bsr       tst2_var            * geachtet
          bra       tstsysvar           * wenn sys-var, dann error

tst_fnvar:     * entspricht tst_var jedoch fÅr funktionsvariablen
          move.w    #FNTYP,d0			* es wird auf bit 14 geachtet
          bsr       tst2_var
tstsysvar:     * testet auf sys-var und gibt ggf. error aus
          tst.w     sysvar
          bne       syserr
          rts

*****************************************
tst_var:
          clr.w     d0				* keine funktionsvar!
tst2_var:
		move.w	d0,fnvarfl

          tst.w     argfl               * normale variable holen
          beq       tv41proc
          move.l    a0,work2
          move.w    fnvarfl,-(sp)
          move.w    #FNTYP,fnvarfl      * zuerst schauen, ob arg-var vorhanden
          bsr       tv41
          move.w    (sp)+,d1
          tst.w     d0
          bne       tv41found
		tst.w	fnvarfl			* wenn # dann nur global -> fnvarfl=0
		beq		tv41back
		move.w	d1,fnvarfl
          move.l    work2,a0
          bra       tv41                * nein, dann nach normaler var schauen
tv41found:
		moveq.l	#-1,d0
tv41back:
		rts

tv41proc:	* sobald eine prozedure aktiv, zuerst schauen, ob lokal definiert!
		move.w	procnr,d1
		beq		tv41				* sind wir im hauptprg?
		tst.w	d0
		beq		tv41ok			* aufruf kam von normalen tst_var
		cmp.w	d1,d0
		bne		tv41				* aufruf kam von lokaler var def?
tv41ok:
		move.l	a0,work2
		move.w	d1,fnvarfl
		bsr		tv41
		tst.w	d0
		bne		tv41found
		tst.w	fnvarfl			* wenn # -> global -> fnvarfl = 0
		beq		tv41back
		move.l	work2,a0
		clr.w	fnvarfl
		bra		tv41

*
* eigentliche routine
*
tv41:
		cmp.b	#$20,(a0)			* alle spaces Åberlesen
		bne		tva1
		addq.l	#1,a0
		bra		tv41
tva1:
          clr.w     sysvar              * default: keine sys-variable
          movem.l   d1-d7/a2-a6,-(sp)
          move.w    #FLOAT,typflag      * default ist integer
          clr.b     arrayfl
          lea       var_name,a3
          move.l    a3,a5
tv4:
          move.b    (a0)+,d0            * ende des var.namens errechnen
          move.b    d0,(a3)+
          beq       tv3a
		bsr		isvarn
		beq		tv4
tv4c:
		cmp.b	#'#',d0			* zeichen fÅr globale var. ansprechen?
		bne		tv4noglobl
		subq.l	#1,a3			* nicht mitspeichern!
		move.w	fnvarfl,d0		* nur bei procnr,FNTYP
		beq		tv4
		cmp.w	procnr,d0
		beq		tva1change
		cmp.w	#FNTYP,d0
		bne		tv4
tva1change:
		clr.w	fnvarfl			* globale var. ansprechen!
		bra		tv4

tv4noglobl:
          cmp.b     #'$',d0
          bne       tv4a
          move.w    #STRING,typflag     * nur strings erlaubt
          bra       tv3a
tv4a:     cmp.b     #'%',d0
          bne       tv4b
          move.w    #INT,typflag        * nur integer
          bra       tv3a
tv4b:     cmp.b     #'!',d0
          bne       tv4d				* sonst jedes zeichen erlaubt!
          move.w    #FLOAT,typflag
          bra       tv3a
tv4d:

tv3:
          subq.l    #1,a0
tv3a:
          clr.b     -(a3)

		move.w	fnvarfl,d2
		move.w	d2,d0
		and.w	#ARRAYTYP+FNTYP+DEFFNTYP+PROCTYP,d0
          beq		tv3b1               * handelt es sich um fnvar, dann:
          cmp.w     #FNTYP,d2           * ist es def-var, dann nicht beachten
          bne       tv3STRING			* auch bei proc nicht beachten

          bsr       charget             * ansonsten prÅfen, ob arrayvar da ist
          subq.l    #1,a0
          cmp.b     #'(',d0             * ja, dann fehler, da dies bei
          beq       noargerr            * funktionsarg. nicht erlaubt ist!
          bra       tv3b

tv3STRING:
		move.w	typflag,fntyp		* typ trotzdem merken
		move.w	#STRING,typflag	* PROCs, DEFFNs sind Strings!
		bra		tv3b

tv3b1:    bsr       charget			* dies nur, wenn lokal oder global!
          subq.l    #1,a0
          cmp.b     #'(',d0             * handelt es sich um ein array?
          bne       tv3b
          addq.l    #1,a0
          bset      #0,arrayfl

tv3b:     * und jetzt auf sys-vars testen
          btst      #0,arrayfl
          bne       nosysvar            * keine arrays erlaubt

          lea       var_name,a1         * jetzt auf systemvars testen
          move.b    (a1)+,d0
          cmp.b     #'t',d0             * anfang fÅr ti/ti$?
          bne       sysvar1
          cmp.b     #'i',(a1)+
          bne       nosysvar
          tst.b     (a1)
          bne       nosysvar
          cmp.w     #STRING,typflag
          beq       TiString
TiInt:    move.w    #INT,typflag        * immer int
          move.w    #-2,sysvar          * es ist eine sysvar!
		bsr		readtime
		lea		tiint,a1
		move.l	d0,(a1)
*          move.l    $466,tiint         * ti ausrechnen (in 1/x0 sec)
          bra       tvar2_found         * weitermachen
TiString: move.w    #-3,sysvar
          bsr       clctistr            * ti$ ausrechnen
		lea		tisptr,a1			* zeiger auf tistring
          bra       tvar2_found
sysvar1:  cmp.b     #'p',d0             * anfang fÅr PI?
          bne       nosysvar
          cmp.b     #'i',(a1)+
          bne       nosysvar
          tst.b     (a1)
          bne       nosysvar
          cmp.w     #STRING,typflag
          beq       nosysvar
PiInt:    move.w    #FLOAT,typflag
          move.w    #-1,sysvar
          lea       pi_,a1              * zeiger auf wert von pi
          bra       tvar2_found

nosysvar:
          move.l    varbase,a1          * zeiger auf Variablenspeicher
		move.w	typflag,d4
		or.w		fnvarfl,d4
		tst.b	arrayfl
		beq		tv2
		or.w		#ARRAYTYP,d4
tv2:		* d4 : typ!
          move.l    (a1)+,a2
          cmp.l     #0,a2
          beq       tst_vend            * ptr != 0 -> Variable, ansonsten ende
          move.l    a5,a3
          move.w    (a1)+,d0
		cmp.w	d4,d0			* stimmt auch typ Åbereinander?
          bne       tv7                 * nein, dann zur nÑchsten variablen
tv1:
          move.b    (a1)+,d0
          move.b    (a3)+,d1
          beq       tv6
          tst.b     d0
          beq       tv7
          bra       tv5
tv6:
          tst.b     d0
          beq       tvar_found
          bne       tv7
tv5:
          cmp.b     d0,d1
          beq       tv1                 * gleich, dann weitersuchen
tv7:
          move.l    a2,a1
          bra       tv2                 * zur nÑchsten Variable
tvar_found:
          move.l    a1,d0
          btst      #0,d0               * auf ungerade testen
          beq       tvar2_found         * gerade...ok
          addq.l    #1,a1
tvar2_found:
          moveq.l   #1,d0
          movem.l   (sp)+,d1-d7/a2-a6
          rts
tst_vend:
          moveq     #0,d0
          movem.l   (sp)+,d1-d7/a2-a6
          rts


*****************************************
* TI/TI$ von VAR aufgerufen
* setzt uhr nach ti
setti
		move.l	fac1,d0
		bra		writetime

* setzt uhr nach ti$
settistr:
          move.l    str_ptr,a2          * zeiger auf string
		addq.l	#1,a2
          bsr       readtistr           * liest Åber -(a2) stunden
          move.w    d1,d0
          mulu      #3600,d0
          bsr       readtistr           * minuten lesen
          mulu      #60,d1
          add.l     d1,d0
          bsr       readtistr           * sekunden lesen
          add.l     d1,d0

		moveq.l	#0,d1
		move.w	d0,d1
		clr.w	d0
		swap		d0
		mulu		#70,d0          	* hi x 70
		swap		d0
		mulu		#70,d1			* lo x 70
		add.l	d1,d0
          bra		writetime

* liest Åber -(a2) eine zweistellige zahl und folgendes trennzeichen
readtistr:
          moveq     #0,d1
          move.b    -(a2),d1
          sub.b     #'0',d1
          move.l    d1,d2
          lsl.l     #3,d1
          lsl.l     #1,d2
          add.l     d2,d1               * x10
          moveq     #0,d2
          move.b    -(a2),d2
          sub.b     #'0',d2
          add.l     d2,d1               * einer dazuaddieren
          subq.l    #1,a2               * trennzeichen Åberspringen
          rts


readtime:
		movem.l	d7/a0,-(sp)
		clr.l	-(sp)
		move.w	#$20,-(sp)
		trap		#1
		addq.l	#6,sp
		move.l	d0,-(sp)
		move.l	$466,d7
		move.w	#$20,-(sp)
		trap		#1
		addq.l	#6,sp
		move.l	d7,d0
		movem.l	(sp)+,d7/a0
		rts


writetime:
		movem.l	d7/a0,-(sp)
		move.l	d0,d7
		clr.l	-(sp)
		move.w	#$20,-(sp)
		trap		#1
		addq.l	#6,sp
		move.l	d0,-(sp)
		move.l	d7,$466
		move.w	#$20,-(sp)
		trap		#1
		addq.l	#6,sp
		movem.l	(sp)+,d7/a0
		rts


* errechnet ti$ aus $466
clctistr:
		bsr		readtime
          lea       tistrend,a1
		clr.l	d1
clctis2:
		cmp.l	#70*3600*12,d0		* am or pm?
		blo		clctis1
		sub.l	#70*3600*12,d0		
		add.w	#12,d1			* 12 h weiter
		bra		clctis2
clctis1:
		divu		#70,d0			* -> zeit in sekunden
		and.l	#$ffff,d0
		divu		#3600,d0			* anzahl stunden
		add.w	d1,d0			* 0/12 h dazuaddieren!
		swap		d0
		moveq.l	#0,d1
		move.w	d0,d1
		swap		d0
		divu		#60,d1			* anzahl minuten

          bsr       wr_tistr            * in -(a1) schreiben (stunden)
          move.b    #':',-(a1)          * trennzeichen
          move.w    d1,d0
          bsr       wr_tistr            * anzahl minuten
          move.b    #':',-(a1)
          swap		d1
          move.w	d1,d0
          bsr       wr_tistr			* anzahl sekunden
          clr.b     -(a1)
          rts


* unterroutine zu calc_tistring
wr_tistr:
          moveq     #0,d4
          move.w    d0,d4
          divu      #10,d4              * /10 -> zehnerstelle 0-9
          move.w    d4,d5               * zehner
          swap      d4                  * einer
          add.b     #'0',d5
          move.b    d5,-(a1)            * zehner schreiben
          add.b     #'0',d4
          move.b    d4,-(a1)            * einer schreiben
          rts


********************************************************************************
* BEFEHLE:
********************************************************************************
****************************************
* HEX
****************************************
* Åbergibt hexstring -> a1 (a2 ist dummy auf zero_4)
Hex:
          move.w    #INT,typvalid
          bsr       get_term
          lea       iout,a1
          move.w    #7,d1               * 8 ziffern max.
          move.b    #'$',d3
          move.w    #4,d4
          move.w    #$f,d5
* einsprung von bin/hex (d3 = %/$, a1 auf pufend+1, d1 = 7/31
*                        d4 auf anzahl verschieb. bei lsr, d5 = $f/$1
hexbin:
		lea       hextab,a2
		clr.b	(a1)+
          move.l    fac1,d0
hex1:     move.l    d0,d2
          and.w     d5,d2
          move.b    0(a2,d2),(a1)+
          lsr.l     d4,d0
          dbf       d1,hex1

hex2:     tst.b     -1(a1)			* wenn 0, dann $0/%0
          beq       hex2a
          cmp.b     #'0',-(a1)          * die ersten 0er nicht ausgeben
          beq       hex2
hex2a:
		addq.l	#1,a1
	     move.b    d3,(a1)
          lea       zero_+4,a2
          move.w    #STRING,typflag
          rts

****************************************
* BIN
****************************************
* gibt binstring aus
Bin:
          move.w    #INT,typvalid
          bsr       get_term
          lea       inputpuf,a1
          move.w    #31,d1
          move.b    #'%',d3
          move.w    #1,d4
          move.w    #1,d5
          bra       hexbin

****************************************
* DIR
****************************************
* gibt inhaltsverzeichnis aus
Dir:
		move.l	a0,-(sp)
		bsr		charget
		beq		nopath
		cmp.b	#':',d0
		beq		nopath
		subq.l	#1,a0
		move.w	#STRING,typvalid
		bsr		get_term
		subq.l	#1,a0			* da am ende noch ein charget folgt
		move.l	a0,(sp)			* neues a0
		move.l	str_ptr,a1
		bsr		setdrv
		move.l	a1,str_ptr
		move.l	#mirrorpuf,mirptr	* jetzt spiegeln
		bsr		mirror_str		* -> d0 zeigt auf base
		move.l	d0,mirptr
		move.l	d0,a1
		tst.b	(a1)				* dir x: ? ---> dir x:*.*
		bne		Dir2
		move.b	#'*',(a1)+
		move.b	#'.',(a1)+
		move.b	#'*',(a1)+
		clr.b	(a1)		
		bra		Dir2
nopath:
		move.l	#joker,mirptr
*		bra		Dir2
Dir2:
          movem.l   a1-a6,-(sp)         * reg. merken
          pea       dta_puf             * dta puffer
          move.w    #$1a,-(sp)
          trap      #1
          addq.l    #6,sp
          move.w    #$31,-(sp)          * attr
          move.l	mirptr,-(sp)
          move.w    #$4e,-(sp)
          trap      #1
          addq.l    #8,sp
          tst.l     d0
          bne       dirend

dirl1:
		lea       30+dta_puf,a1       * adr. des namens
          lea       inputpuf,a0         * hier wird zur ausgabe vorbereitet
          move.l    a0,a2
		move.b	#$22,(a2)+		* "

		cmp.b	#$10,dta_puf+21	* subdir?
		bne		c2dirname
dirl2:
		move.b	(a1)+,(a2)+
		bne		dirl2
		subq.l	#1,a2
		bra		cdir
c2dirname:
		move.b    (a1)+,d0			* name kopieren
		beq		cdir
		cmp.b	#'A',d0
		blo		c2d
		cmp.b	#'Z',d0
		bhi		c2d
		add.b	#$20,d0			* buchstaben klein
c2d:
		move.b	d0,(a2)+
          bra		c2dirname
cdir:
		move.b	#$22,(a2)+		* "

          move.l    a2,d0
          sub.l     a0,d0               * lÑnge des namens
          move.w    #14,d1
          sub.w     d0,d1               * anzahl der noch kommenden ' '
dirl3:    move.b    #' ',(a2)+
          dbf       d1,dirl3

		move.b	#':',(a2)+
		move.b	#$27,(a2)+		* ' fÅr rem
		move.b	#' ',(a2)+

          move.b    dta_puf+21,d0       * file attribut
          bne       dirj1
dirj0:    move.b    #' ',d0
          bra       dirl4
dirj1:    btst      #5,d0               * bit6 (opened and closed)
          bne       dirj0
          cmp.b     #1,d0               * write-protected?
          bne       dirj3
          move.b    #'P',d0
          bra       dirl4
dirj3:    cmp.b     #$10,d0             * subdir?
          bne       nextdir			* undefinierbar....
          move.b    #7,d0
dirl4:
		move.b    d0,(a2)+
          move.w    #2,d0
dirl5:    move.b    #' ',(a2)+
          dbf       d0,dirl5
		clr.b	(a2)

		bsr		tab_
		bsr		put_string
          move.l    dta_puf+26,d0       * length
          bsr       ipka_               * in ascii wandeln
          lea       -1(a2),a0           * vorzeichen umgehen
          bsr       putstrreverse
          bsr       new_line

nextdir:
          move.w    #$4f,-(sp)
          trap      #1
          addq.l    #2,sp
          tst.l     d0
          beq       dirl1
dirend:   movem.l   (sp)+,a1-a6
		move.l	(sp)+,a0
          bra       charget

*****************************************
* VARPTR
*****************************************
* adr einer variablen
Varptr:
          bsr       tst_var             * testet auf Variable und holt ggf adr.
          bsr       tstsysvar
          move.w    typflag,typvalid
          tst.w     d0
          beq       varperr             * noch nicht definiert -> fehler
          tst.b     arrayfl
          beq       varp2
          bsr       posarray            * holt argument und positioniert (->a1)
          bsr       chk_klammer
varp2:    bsr       charget
          cmp.w     #STRING,typvalid
          bne       varp1
          move.l    (a1),a1
varp1:    move.l    a1,d0
          move.w    #INT,typflag
          rts


**********
* ruft AES,VDI auf.
*********

Aes:
		moveq.l	#0,d0			* max. Åbergabeparameter
		lea		AESctrl,a1
		lea		AESctrl+20,a2		* max. 10 int
		bra		execaes
Vdi:
		moveq.l	#1,d0
		lea		VDIctrl,a1
		lea		VDIctrl+24,a2		* max. 12 int
*		bra		execaes
execaes:
		move.w	d0,-(sp)

		move.l	a0,work1
		bsr		charget
		beq		eaesend
		cmp.b	#':',d0
		beq		eaesend
		bra		eaes3
eaes1:
		move.l	work1,a0
		movem.l	a1/a2,-(sp)
		move.w	#INT,typvalid
		bsr		get_term
		movem.l	(sp)+,a1/a2
		cmp.l	a2,a1
		bge		manyargerr		* zu viele parameter
		move.w	fac1+2,(a1)+
eaes2:
		bsr		chargot
		beq		eaesend
		cmp.b	#':',d0
		beq		eaesend
		cmp.b	#',',d0			* chk_komma
		bne		syntaxerr
		move.l	a0,work1
		bsr		charget
eaes3:
		cmp.b	#',',d0
		bne		eaes1
		cmp.l	a2,a1
		bge		manyargerr
		addq.l	#2,a1
		bra		eaes2
eaesend:
		tst.w	(sp)+			* aes oder vdi
		beq		aesaes
		move.l	#VDIPB,d1
		move.w	#$73,d0
aesvdi:
		pea		(a0)
		trap		#2
		move.l	(sp)+,a0
		rts
aesaes
		move.l	#AESPB,d1
		move.w	#$c8,d0
		bra		aesvdi


* aesctrl offs,x[,offs,x...]
Aesctrl:
		moveq.l	#1,d1			* .w tab (lsl 1)
		move.l	#10,d2			* 0-9
		lea		AESctrl,a1
		bra		aesdecide

Aesintin:
		moveq.l	#1,d1
		move.l	#128,d2
		lea		AESintin,a1
		bra		setaes

Aesintout:
		moveq.l	#1,d1
		move.l	#128,d2
		lea		AESintout,a1
		bra		readaes

Aesadrin:
		moveq.l	#2,d1
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
		move.l	#12,d2
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


**** sub
aesdecide:
		tst.w	cmdfktfl
		bne		readaes
*		beq		setaes

setaes:
		movem.l	d1/d2/a1,-(sp)
		move.w	#INT,typvalid
		bsr		get_term
		movem.l	(sp)+,d1/d2/a1
		move.l	fac1,d0
		bmi		negerr
		cmp.l	d2,d0
		bpl		aesrangeerr
		lsl.l	d1,d0
		pea		0(a1,d0)
		bsr		chk_komma
		movem.l	d1/d2/a1,-(sp)
		move.w	#INT,typvalid
		bsr		get_term
		movem.l	(sp)+,d1/d2/a1
		move.l	(sp)+,a2
		move.w	fac1+2,(a2)
		bsr		chargot
		cmp.b	#',',d0
		bne		setaes1
		addq.l	#1,a0
		bra		setaes
setaes1:
		rts

readaes:
		movem.l	d1/d2/a1,-(sp)
		move.w	#INT,typvalid
		bsr		get_term
		movem.l	(sp)+,d1/d2/a1
		move.l	fac1,d0
		bmi		negerr
		cmp.l	d2,d0
		bpl		aesrangeerr
		lsl.l	d1,d0
		move.w	#INT,typflag
		cmp.w	#1,d1			* .w?
		beq		readwaes
		move.l	0(a1,d0),d0
		rts
readwaes:
		move.w	0(a1,d0),d0
		ext.l	d0
		rts

*****************************************
* GEMDOS/BIOS/XBIOS
*****************************************
mirptr	.ds.l	1

* ruft Systemfunktion auf
Gemdos:
          moveq.l   #1,d0               * trap #1
          lea       gemdtbl,a1          * tabelle mit musterelementen
          bra       callsys
Bios:     moveq.l   #13,d0              * trap #13
          lea       biostbl,a1
          bra       callsys
Xbios:    moveq.l   #14,d0              * trap #14
          lea       xbiostbl,a1
callsys:
          and.w     #$fff0,calltrap
          or.w      d0,calltrap         * trap vorbereiten
          move.l    a1,-(sp)
          move.w    #INT,typvalid       * funktionsnummer holen
          bsr       get_term
          move.l    (sp)+,a1
          move.l    fac1,d0
          cmp.w     (a1)+,d0            * ist fktnr zu gross?
          bpl       callerr             * ja...fehler
          lea       inputpuf,a2         * hier werden stackdaten abgelegt
          move.w    d0,(a2)+            * fkt-nr merken
          lsl.l     #2,d0               * fÅr lw-operation
          move.l    0(a1,d0),d0		* Zeiger auf Fkt-Parameter
          bmi		callerr
          move.l	d0,a1
		move.l	#mirrorpuf,mirptr	* wird fÅr mirror_str gebraucht!
          bra       calls4              * mit kommacheck weitermachen...

calls0:   move.w    (a1)+,typvalid
          move.l    a1,-(sp)
          move.l    a2,-(sp)
          bsr       get_term            * element holen
          cmp.w     #STRING,typvalid    * zwischen vararten unterscheiden
          bne       calls1
		bsr		mirror_str		* spiegelt str (str_ptr)->(mirptr)
          bra       calls2

calls1:   move.l    fac1,d0
calls2:   move.l    (sp)+,a2
          move.l    (sp)+,a1
          tst.w     (a1)+               * 0 = .w/1 = .l in die liste
          beq       calls3              * wort
          move.l    d0,(a2)+
          bra       calls4
calls3:   move.w    d0,(a2)+            * lwort
calls4:   tst.w     (a1)                * wÅrde noch ein arg folgen mÅssen?
          beq       calls5
          bsr       chk_komma
          bra       calls0
calls5:   * und nun daten auf den stack
          move.l    a0,-(sp)            * reg retten
          move.l    sp,spstr
          bsr       onqlist
calls6    move.w    -(a2),-(sp)         * daten andersrum auf stack
          cmp.l     #inputpuf,a2
          bne       calls6
calltrap: trap      #0                  * hier wird richtige nr eingesetzt
          bsr       offqlist
          move.l    spstr,sp
          move.l    (sp)+,a0
          move.w    #INT,typflag
          rts

* mirror_str spiegelt einen string, allerdings nicht im eigenen str.bereich,
* sondern Åber den ptr. mirptr, der normalerweise auf mirrorpuf zeigt!
* -> d0.l = string base, mirptr wird upgedated!
mirror_str:
		movem.l	d1/a0-a2,-(sp)

		move.l	str_ptr,a0
		addq.l	#1,a0
		move.l	a0,a2
		moveq.l	#0,d1
mir_tstlen:
		addq.l	#1,d1
		tst.b	-(a0)
		bne		mir_tstlen

		cmp.l	#mirrorpend-mirrorpuf,d1
		bpl		outvarmem
		
		move.l	mirptr,d0
		move.l	d0,a1
		add.l	d1,mirptr
mir_copy:
		move.b	-(a2),(a1)+
		subq.l	#1,d1
		bne		mir_copy

		movem.l	(sp)+,d1/a0-a2
		rts


*****************************************
* CURSOR
*****************************************
* cursor heim bringen
Cursor:
          bsr       tstnxtarg
          bne       Home
          move.w    #INT,typvalid
          bsr       get_term
		subq.l	#1,fac1
		bmi		start1err
          move.l    fac1,-(sp)    
          bsr       chk_komma
          move.w    #INT,typvalid
          bsr       get_term
		subq.l	#1,fac1
		bmi		start1err
          move.l    fac1,d1       
          move.l    (sp)+,d0
          move.l    edibase,a1
          move.w    edi_breit(a1),d2
          lsr.w     #4,d2

          cmp.l     maxspalten,d0
          bge       cposerr
          cmp.w     d2,d1
          bge       cposerr
          bra       ed_pos
*****************************************
* HOME
*****************************************
Home:     bsr       ed_clrhome          * cursor nach 0,0 bringen
          bra       charget
*****************************************
* CLS
*****************************************
* lîscht ed-Bildschirm
Cls:
          bsr       ed_clr
          bra       charget
*****************************************
* CONT
*****************************************
* fÅhrt soweit mgl. das programm weiter
Cont:
          move.l    contline,d0
          bmi       conterr             * cant cont!
          move.l    d0,akt_zeile
          move.l    contladr,akt_adr
          move.l    contadr,a0
          move.w    #-1,b_modus
          bra       runcont
*****************************************
* STOP
*****************************************
* stoppt programm
Stop:
          bsr       charget             * auf nÑchsten befehl
          bra       stoperr


****
* Call (  adr [,[[*]x],....] )
calltbld0:	.ds.l	8		* max. 15 d0-a6 reg. koennen uebergeben werden
calltbla0:	.ds.l	7
calltblend:
Call:
		lea		calltbld0,a1		* merken, da auch rekursiv mgl.!
		movem.l	(a1)+,d0-d7
		movem.l	d0-d7,-(sp)
		movem.l	(a1)+,d0-d6
		movem.l	d0-d6,-(sp)

		move.w	#INT,typvalid
		bsr		get_term
		move.l	fac1,-(sp)
		clr.w	d6				* no dataregisters
		clr.w	d7				* no adrregs
		lea		calltbld0,a5
		lea		calltbla0,a6
callgetregs:
		bsr		tst_komma
		bne		nocallparam
		move.l	a0,d1
		bsr		charget
		cmp.b	#'*',d0			* adr-register?
		bne		noadrreg
useadrregs:
		addq.w	#1,d7
		cmp.w	#7,d7			* zu viele adr. register?
		bhi		manyargerr
		moveq.l	#1,d5			* -> adr ist akt. wert
		bra		call1
noadrreg
		move.l	d1,a0
		cmp.w	#8,d6			* alle datenregs voll, dann adr.
		bge		useadrregs
		addq.w	#1,d6
		moveq.l	#0,d5
call1:
		move.l	a0,d1
		bsr		charget
		cmp.b	#',',d0			* auch ,, zulassen (,, & ,*,)
		beq		call1c
		cmp.b	#')',d0			* ,)
		bne		call1a
call1c
		clr.l	fac1
		bra		call1b
call1a:
		move.l	d1,a0
		movem.l	d5/d6/d7/a5/a6,-(sp)
		move.w	#INT,typvalid
		bsr		get_term
		movem.l	(sp)+,d5/d6/d7/a5/a6
call1b:
		tst.w	d5
		beq		callwrd0
callwra0:
		move.l	fac1,(a6)+
		bra		callgetregs
callwrd0:
		move.l	fac1,(a5)+
		bra		callgetregs

nocallparam:
		move.l	(sp)+,fac1			* anspringen...
		move.l	a0,-(sp)
		movem.l	calltbld0,d0-d7
		movem.l	calltbla0,a0-a6
		bsr		jumpfac1
		move.l	(sp)+,a0
		lea		calltblend,a1
		movem.l	(sp)+,d1-d7
		movem.l	d1-d7,-(a1)
		movem.l	(sp)+,d1-d7/a2
		movem.l	d1-d7/a2,-(a1)
		move.w	#INT,typflag
		rts


*****************************************
* SYS
*****************************************
* springt in speicher
Sys:
          move.w    #INT,typvalid
          bsr       get_term
          move.l    a0,-(sp)
		bsr		jumpfac1
          move.l    (sp)+,a0
          rts

jumpfac1:
		btst		#0,fac1+3			* ungerade, dann fehler!
		bne		oddadrerr
		move.l	fac1,jumptomem+2
jumptomem:
		jmp		$12345678

*****************************************
* RND(x)
*****************************************
* liefert zufallszahl
Rnd:
          lea       rrand_,a1
          bsr       trig_arg
		movem.l	fac1,d4-d7
		lea		zero_,a1		* rnd(0) ist wie rnd(1)
		cmp.l	(a1)+,d4
		bne		rndnozero
		cmp.l	(a1)+,d5
		bne		rndnozero
		cmp.l	(a1),d6
		bne		rndnozero
		rts					* x=0 -> ok.
rndnozero:
		lea		one_,a1
		cmp.l	(a1)+,d4
		bne		rndnoone
		cmp.l	(a1)+,d5
		bne		rndnoone
		cmp.l	(a1),d6
		bne		rndnoone
		rts					* x=1 -> ok.
rndnoone:
		move.l	a0,-(sp)
		bsr		rmul_
		move.l	(sp)+,a0
		rts

*****************************************
* SGN
*****************************************
* liefert vorzeichen einer zahl
Sgn:
          move.w    #STRING,typvalid
          bsr       gets_term
          move.w    #INT,typflag        * rÅckgabewert ist int
		move.w	typ2flag,d0		* eingeholter typ
		cmp.b	#STRING,d0
		beq		NADDI_
		cmp.b	#INT,d0
		beq		sgnint
sgnfloat:
		movem.l	fac1,d0-d2
		lea		zero_,a1
		cmp.l	(a1)+,d0
		bne		sgnfl1
		cmp.l	(a1)+,d1
		bne		sgnfl1
		cmp.l	(a1),d2
		beq		sgnequal
sgnfl1:
		btst		#31,d0
		beq		sgnpos
		bra		sgnneg
sgnint:
		move.l	fac1,d0
		beq		sgnequal
		bmi		sgnneg
sgnpos:
          moveq.l   #1,d0
		rts
sgnneg
		moveq.l	#-1,d0
		rts
sgnequal:
		moveq.l	#0,d0
		rts


*****************************************
* ABS
*****************************************
* berechnet absolutwert
Abs:
          move.w    #STRING,typvalid
          bsr       gets_term
          movem.l   fac1,d0-d3
          move.w    typ2flag,typflag
          cmp.w     #FLOAT,typ2flag
          beq       absfloat
          cmp.w     #INT,typ2flag
          bne       typemis
absint:   btst      #31,d0              * nur ausfÅhren, wenn negativ
          beq       absend
          neg.l     d0
absend:   rts
absfloat: bclr      #31,d0
          rts
*****************************************
* SQR
*****************************************
* liefert wurzel
Sqr:
          lea       rsqrt_,a1
          bra       trig_arg
*****************************************
* LN
*****************************************
* liefert nat log zur basis e
Ln:
          lea       rlog_,a1
          bra       trig_arg
*****************************************
* LOG
*****************************************
* liefert log zur basis 10
Log:
          lea       rlog10_,a1
          bra       trig_arg
*****************************************
* EXP10
*****************************************
* liefert exp zur basis 10
Exp10:
          lea       rexp10_,a1
          bra       trig_arg
*****************************************
* EXP
*****************************************
* liefer exponenten
Exp:
          lea       rexp_,a1
          bra       trig_arg
*****************************************
* TAN
*****************************************
* liefert tangens
Tan:
          lea       rtan_,a1
          bra       trig_arg
*****************************************
* MOD
*****************************************
* positiver rest
Mod:
          lea       rmod_,a1
          bra       trig3_arg
*****************************************
* ATNPT
*****************************************
* liefert arc-tan eines punktes
Atnpt:
          lea       ratan2_,a1
trig3_arg:move.l    a1,-(sp)            * einspr. fÅr fkt. fkt(x,y)
          move.w    #FLOAT,typvalid
          bsr       get_term
          movem.l   fac1,d0-d3
          movem.l   d0-d3,-(sp)
          bsr       chk_komma
          move.w    #FLOAT,typvalid
          bsr       get_term
          movem.l   fac1,d4-d7
          movem.l   (sp)+,d0-d3
          move.l    (sp)+,a1
          bra       trig2_arg
*****************************************
* ATN
*****************************************
* liefert arc-tan
Atn:
          lea       ratan_,a1
          bra       trig_arg
*****************************************
* COS
*****************************************
* liefert cosinus im bogenmass
Cos:
          lea       rcos_,a1
          bra       trig_arg            * trigonom. arg holen
*****************************************
* SIN
*****************************************
* liefert sinus im bogenmass
Sin:
          lea       rsin_,a1
trig_arg: move.w    #FLOAT,typvalid
          move.l    a1,-(sp)
          bsr       get_term             * argument holen
          move.l    (sp)+,a1
          movem.l   fac1,d0-d3
trig2_arg:move.w    #FLOAT,typflag
          move.l    a0,-(sp)
          jsr       (a1)
          move.l    (sp)+,a0
          rts
*****************************************
* LPEEK
*****************************************
* liefert wert einer adr
Lpeek:
          move.w    #INT,typvalid
          bsr       get_term            * adr holen
          move.l    fac1,a1
          move.l    a1,d0
          btst      #0,d0               * auf ungerade testen
          bne       oddadrerr           * ja, dann fehler
          move.l    (a1),d0
          move.w    #INT,typflag
          rts
*****************************************
* DPEEK
*****************************************
* liefert wert einer adr
Dpeek:
          move.w    #INT,typvalid
          bsr       get_term            * adr holen
          move.l    fac1,a1
          move.l    a1,d0
          btst      #0,d0               * auf ungerade testen
          bne       oddadrerr           * ja, dann fehler
          move.w    (a1),d0
          ext.l     d0                  * falls negativ, dann auf lw
          move.w    #INT,typflag
          rts
*****************************************
* PEEK
*****************************************
* liefert wert einer adr
Peek:
          move.w    #INT,typvalid
          bsr       get_term            * adr holen
          move.l    fac1,a1
extbyte:  move.b    (a1),d0
          ext.w     d0
          ext.l     d0                  * falls negativ, dann auf lw
          move.w    #INT,typflag
          rts
*****************************************
* LPOKE
*****************************************
* poked einen wert in adr
Lpoke:
          bsr       get_poke            * Parameter holen
          move.l    d0,(a1)
          rts
get_poke:
          move.w    #INT,typvalid
          bsr       get_term
          move.l    fac1,-(sp)          * adr merken
          bsr       chk_komma
          move.w    #INT,typvalid
          bsr       get_term
          move.l    (sp)+,a1
          move.l    a1,d0
          btst      #0,d0
          bne       oddadrerr           * ungerade nicht erlaubt
          move.l    fac1,d0
          rts
*****************************************
* DPOKE
*****************************************
* poked einen wert in adr
Dpoke:
          bsr       get_poke
          move.w    d0,(a1)
          rts
*****************************************
* POKE
*****************************************
* poked einen wert in adr
Poke:
          move.w    #INT,typvalid
          bsr       get_term
          move.l    fac1,-(sp)          * adr merken
          bsr       chk_komma
          move.w    #INT,typvalid
          bsr       get_term
          move.l    (sp)+,a1
          move.l    fac1,d0
          move.b    d0,(a1)             * wert schreiben
          rts
*****************************************
* CMD
*****************************************
* steuert alle ausgaben bis weiterer zugriff auf ein file (get_handle) da
Cmd:
          bsr       get_handle
          move.w    #-1,cmdfl                * flag einschalten
          move.w    #-1,filefl
          rts
*****************************************
* NOT
*****************************************
* negiert (nur int!)
Not:
          move.w    #INT,typvalid
          bsr       get_term
          move.w    #INT,typflag
          move.l    fac1,d0
          not.l     d0
          subq.l    #1,a0               * wieder ein zeichen zurÅchgehen
          rts
*****************************************
* POS
*****************************************
* ermittelt bildschirmpos.
Pos:
          move.w    #INT,typvalid
          bsr       get_term            * unwichtiges arg.
          move.w    #INT,typflag
          moveq     #0,d0
          move.w    ed_x,d0
          add.w     ed_xoffs,d0
          rts
*****************************************
* MID
*****************************************
* mittleren teil eines strings Åbergeben
Mid:
          bsr       strpos
		addq.l	#1,d0
          lea       0(a1,d0.l),a1       * anfang des string
          bsr       chk_komma
          move.l    a1,spstr
		bsr		onqlist
          move.w    #INT,typvalid
          bsr       get_term
		bsr		offqlist
          move.l    spstr,a1
          move.l    fac1,d0
          neg.l     d0
          move.w    #STRING,typflag
          move.l    a1,a2
          addq.l    #1,a2
mid1:     tst.b     -(a2)               * schauen, ob pos vorhanden
          bne       mid1
          sub.l     a1,a2
          cmp.l     d0,a2
          bgt       strposerr           * pos gibt es nicht!
          lea       zero_+4,a2          * dummy
          clr.b     0(a1,d0.l)
          rts
*****************************************
* RIGHT
*****************************************
* rechten teil eines strings Åbergeben
Right:
          bsr       strpos
          sub.l     d0,a3               * anfang des string
          move.l    a3,a1
          rts
*****************************************
* LEFT
*****************************************
* linken teil eines strings Åbergeben
Left:
          bsr       strpos
          clr.b     0(a1,d0.l)          * ende des strings
          rts

****
* Instr (a$,b$[,pos]) liefert pos. eines str im anderen
Instr:
		move.l	strend,spstr
		bsr		onqlist
		bsr		initstrpos
		bsr		chk_komma
		move.l	str_ptr,spstr
		bsr		onqlist
		bsr		initstrpos
		move.l	str_ptr,spstr
		bsr		onqlist
		moveq.l	#0,d1			* default pos
		bsr		tst_komma
		bne		noinstrpos
		move.w	#INT,typvalid
		bsr		get_term
		move.l	fac1,d1
		bmi		start1err
		subq.l	#1,d1
		bmi		start1err
noinstrpos:
		neg.l	d1
		bsr		offqlist			* zu suchender str
		move.l	spstr,a1
		bsr		offqlist			* zu durchsuchende str
		move.l	spstr,a2
		move.l	a2,a5
		lea		0(a2,d1.l),a3		* zeigt auf pos.
		tst.l	d1				* wenn 0 , dann Åbergehen
		beq		instr2
		addq.l	#1,a2
instr1:
		tst.b	-(a2)
		beq		strposerr			* pos ausserhalb des strings!
		cmp.l	a2,a3
		bne		instr1
instr2:
		tst.b	(a3)
		beq		instrend
		move.l	a3,a2
		move.l	a1,a4
		addq.l	#1,a2
		addq.l	#1,a4
instr3:
		move.b	-(a4),d0			* zu suchendes zeichen
		beq		instrfound
		move.b	-(a2),d1			* zu durchsuchender str
		beq		instrend
		cmp.b	d0,d1
		beq		instr3
instrnotfound:
		subq.l	#1,a3
		bra		instr2
instrend:
		moveq.l	#0,d0
		bra		instr4
instrfound:
		sub.l	a3,a5
		move.l	a5,d0
		addq.l	#1,d0
instr4:
		move.w	#INT,typflag
		bsr		offqlist
		move.l	spstr,strend
		rts


* kleine subroutine		
initstrpos:
		move.w	#STRING,typvalid
		bsr		get_defterm
		cmp.b	#STRING,typvalid+1
		bne		NADDI_
		rts

*****************************************
* unterroutine fÅr right$, left$, die string (a1) und pos (d0) holt
* -> a1 zeiger auf str/a3 zeigt auf ende/d0 rel. pos/alles gesetzt fÅr funktion
strpos:
          move.l    strend,spstr
          bsr       onqlist             * in querverweisliste eintr.
		bsr		initstrpos
          bsr       chk_komma
          move.l    str_ptr,spstr
          bsr       onqlist
          move.w    #INT,typvalid
          bsr       get_term
          bsr       offqlist
          move.l    spstr,a1
          bsr       offqlist
          move.l    spstr,strend
          move.l    fac1,d0
          move.w    #STRING,typflag
          move.l    a1,a2
          addq.l    #1,a2
strp1:    tst.b     -(a2)                    * schauen, ob pos vorhanden
          bne       strp1
          move.l    a2,a3
          sub.l     a1,a2
          neg.l     d0
          cmp.l     d0,a2
          bgt       strposerr           * pos gibt es nicht!
          lea       zero_+4,a2          * dummy
          rts


*****************************************
* CHR
*****************************************
* gibt 1-byte string zurÅck (umkehrung des asc-cmds.)
Chr:
          move.w    #INT,typvalid
          bsr       get_term
          move.l    fac1,d0             * zeichen
storebyte:
          move.l    strend,a1
          move.l    a1,a2
          move.b    d0,(a2)             * rÅckwÑrts reinschreiben
          clr.b     -(a2)
          lea       zero_+4,a2
          move.w    #STRING,typflag
          rts

* holt ein zeichen von keyboard
Inkey:
		move.l	a0,-(sp)
		move.w	#7,-(sp)
		trap		#1
		addq.l	#2,sp
		move.l	(sp)+,a0
		bra		storebyte


* wartet x/70 secs
Wait:
		move.w	#INT,typvalid
		bsr		get_term
		move.l	a0,-(sp)
wait1:
		move.w	#37,-(sp)
		trap		#14
		addq.l	#2,sp
		subq.l	#1,fac1
		bpl		wait1
		move.l	(sp)+,a0
		rts


******* Auto- Befehl: [x[,y]]
Auto:
		bsr		getoptparam	* (eigentl. fÅr DELETE/LIST, geht aber, da bis 2 param. eingelesen werden!)
		tst.l	d6			* 1. param = 0?
		bne		auto1
		moveq.l	#100,d6		* ja, dann default-wert 100 nehmen
auto1:
		tst.l	d7
		beq		start1err
		cmp.l	#$7fffffff,d7	* 2. param unendlich?
		bne		auto2
		moveq.l	#10,d7		* ja, dann def-wert 10
auto2:
		move.l	d6,autozeile
		move.l	d7,autoadd
		
		move.w	#1,autofl
		rts


* schaltet das TRACE ein
tracefl:	.dc.w	0		* am Anfang ist trace ausgeschalten!
Tron:
		move.w	#1,tracefl
		bra		charget
Troff:
		clr.w	tracefl
		bra		charget

* d0 ist aktueller befehl, a0 zeigt dahinter
trace:
		movem.l	d0/a0-a2,-(sp)	* merken
		move.l	a0,work1
		lea		var2_name,a1	* zeiger auf ausgabepuffer
		move.b	#':',(a1)+
		move.b	#' ',(a1)+
		clr.b	d1			* switch fÅr " (wenn : in "...")
		bra		trace1

trace2:
		move.b	(a0)+,d0
		beq		traceend
trace1:
		cmp.b	#':',d0
		bne		trace1a
		tst.b	d1			* : nur ende, wenn nicht zw. "..."
		beq		traceend
trace1a:
		cmp.b	#TOKEN1,d0	* einleitung fÅr token?
		beq		trtoken
		cmp.b	#TOKEN2,d0
		beq		trtoken
		cmp.b	#TOKEN3,d0
		bne		trnotoken
trtoken:
		and.w	#$ff,d0
		lsl.w	#2,d0		* .l tab
		lea		tokenadr,a2
		move.l	(a2,d0),a2
		move.b	(a0)+,d0		* tokenwert
		lsl.w	#2,d0		* .l tabelle
		move.l	(a2,d0.w),a2	* ptr auf name
trtoken1:
		move.b	(a2)+,d0
		beq		trace2
		bclr		#7,d0
		cmp.b	#'a',d0
		bmi		tr2aa
		cmp.b	#'z'+1,d0
		bpl		tr2aa
		sub.b	#$20,d0			* in grossbuchstaben wandeln
tr2aa:
		move.b	d0,(a1)+		* in puffer schreiben
		bra		trtoken1
trnotoken:
		cmp.b	#'"',d0		* "->switch
		bne		trnotok2
		not.b	d1
trnotok2:
		move.b	d0,(a1)+
		bra		trace2

traceend:
		move.b	d0,(a1)+		* : bzw. $0 dahinter
		clr.b	(a1)
		move.l	akt_zeile,d0	* akt. zeilennr
		bsr		ipka_
		move.l	a2,a0
		subq.l	#1,a0		* + Åbergehen

		tst.w	filefl
		bne		notrhome
		move.w	ed_y,try
		move.w	ed_x,d0
		add.w	ed_xoffs,d0
		move.w	d0,trx
		clr.w	ed_y
		bsr		ed_clrline
		bra		trhome
notrhome:
		bsr		new_line
trhome:
		bsr		putstrreverse
		lea		var2_name,a0
		bsr		put_string

		move.l	traceline,d0
		bmi		notrgos
		bsr		new_line
		move.l	work1,d1			* akt prgptr
		subq.l	#1,d1			* wider auf $01-Tokeneinleitung pos.
		bset		#31,d1			* bit31:bei return tracebit
		move.l	d1,a0		
		move.l	d0,fac1			* trace gosub zeile
		clr.w	tracefl			* -> trace abgeschalten (bei return wieder an!!)
		lea		stack,sp
		bra		Gosub1
notrgos:
		tst.w	filefl
		bne		notr2home
		move.w	trx,d0
		move.w	try,d1
		bsr		ed_pos
notr2home:

		move.w	#7,-(sp)
		trap		#1
		addq.l	#2,sp
		swap		d0
		cmp.b	#$61,d0		* UNDO?
		beq		stoperr
		
		movem.l	(sp)+,d0/a0-a2
		rts


* dumpt variablen aus!
dumpfl:	.ds.b	1
dump2fl:	.ds.b	1
dmpstr1:	.dc.b	" = ",0
dmpa0:	.ds.l	1
Dump:
		move.l	a0,work1
		bsr		charget
		beq		dmpnoarg
		cmp.b	#':',d0
		beq		dmpnoarg
		move.l	work1,a0
		move.w	#INT,typvalid
		bsr		get_term
		move.l	fac1,d0
		bra		dmparg
dmpnoarg:
		moveq.l	#1+2+4+8+16,d0		* alle steuerbits gestzt!
dmparg:
		move.b	d0,dumpfl
		move.b	#1,dump2fl		* mit typ1 beginnen (FLOAT)
		move.l	a0,dmpa0
dmp2:
		move.b	dump2fl,d0
		and.b	dumpfl,d0			* schauen, ob typ verlangt
		bne		dmp1
dmp2a:
		move.b	dump2fl,d0
		lsl.b	d0				* zum naechsten typ scrollen
		move.b	d0,dump2fl
		cmp.b	#8,dump2fl		* alle typen schon durch?
		beq		dumpend
		bra		dmp2
dmp1:
		move.l	varbase,a1
dumploop:
		move.l	(a1)+,d7			* zeiger auf nxt var
		beq		dmp2a			* ende -> naechsten typ suchen
		move.w	(a1)+,d0			* typ
		move.w	d0,d6
		and.w	#$7ff8,d0			* testen, ob fn,def,proctyp dabei?
		bne		dumpnext
		cmp.b	dump2fl,d6		* aktueller typ?
		bne		dumpnext
		lea		var2_name,a2		* hier wird namen abgelegt
dmp3:
		move.b	(a1)+,(a2)+
		bne		dmp3
		move.l	a1,d0
		btst		#0,d0			* ungerade?
		beq		dmpeven
		addq.l	#1,a1
dmpeven:
		move.b	#'!',d0			* default float
		cmp.b	#INT,d6			* muss ein % kommen?
		bne		dmp4
		move.b	#'%',d0
		bra		dmp5
dmp4:
		cmp.b	#STRING,d6
		bne		dmp5
		move.b	#'$',d0
dmp5:
		move.b	d0,-1(a2)			* anhaengsel %,$ an namen haengen
		clr.b	(a2)

		btst		#15,d6			* array?
		bne		dumparray
		bsr		dmpvar
		bra		dumpnext

* in: d6 = typ, a1 zeigt auf wert
* out: d6 = typ, a1 zeigt hinter den wert
dmpvar:
		movem.l	d6/d7/a2-a6,-(sp)
		cmp.b	#STRING,d6
		bne		dmpnostr
		move.l	(a1)+,d0
		tst.l	d0
		beq		dumprts
		btst		#4,dumpfl			* nur belegte?
		beq		dmpstr
		cmp.l	#zero_+4,d0
		beq		dumprts
		move.l	d0,a0
		tst.b	(a0)
		beq		dumprts
dmpstr:
		bsr		dumptext
		lea		key,a0
		move.w	#$2200,(a0)		* " ausgeben
		bsr		put_string
		move.l	d0,a0
		bsr		putstrreverse
		lea		key,a0
		bsr		put_string
dumprts:
		movem.l	(sp)+,d6/d7/a2-a6
		rts

dmpnostr:
		cmp.b	#INT,d6
		bne		dmpnoint
		move.l	(a1)+,d0
		btst		#4,dumpfl			* nur belegte?
		beq		dmpint
		tst.l	d0
		beq		dumprts
dmpint:
		bsr		dumptext
		move.l	a1,-(sp)
		bsr		ipka_
dmpfloat:
		move.l	(sp)+,a1
		move.l	a2,a0
		bsr		putstrreverse
		bra		dumprts

dmpnoint:
		movem.l	(a1)+,d0-d2
		clr.l	d3
		btst		#4,dumpfl			* nur belegte?
		beq		dmpfl
		lea		zero_,a0
		cmp.l	(a0)+,d0
		bne		dmpfl
		cmp.l	(a0)+,d1
		bne		dmpfl
		cmp		(a0),d2
		beq		dumprts
dmpfl:
		bsr		dumptext
		move.l	a1,-(sp)
		bsr		rpka_
		bra		dmpfloat

dumpnext:
		move.l	d7,a1
		bsr		dmpchkstop
		bra		dumploop

dumptext:
		btst		#15,d6			* array?
		bne		dtarray
		bsr		new_line
		lea		var2_name,a0
		bsr		put_string
		lea		dmpstr1,a0
		bra		put_string
dtarray:
		bsr		new_line
		lea		var2_name,a0
		bsr		put_string
		lea		key,a0
		move.w	#$2800,(a0)
		bsr		put_string
		move.b	#',',(a0)
		movem.l	d0-d3/a1-a6,-(sp)

		lea		inputpuf+100,a1
dta1:
		move.l	(a1)+,d0
		bmi		dtaend
		move.l	a1,-(sp)
		bsr		ipka_
		move.l	(sp)+,a1
		lea		-1(a2),a0
		bsr		putstrreverse
		tst.l	(a1)
		bmi		dtaend
		lea		key,a0
		bsr		put_string
		bra		dta1
dtaend:
		lea		key,a0
		move.w	#$2900,(a0)
		bsr		put_string

		movem.l	(sp)+,d0-d3/a1-a6
		lea		dmpstr1,a0
		bra		put_string


dumparray:
		btst		#3,dumpfl			* kein interesse an arrays?
		beq		dumpnext
		lea		inputpuf,a2
		move.l	a2,a4			* zeigt auf je hîschte deep
		lea		inputpuf+100,a3	* hier akt. pos im feld
		move.l	a3,a5			* init. deeps
		move.l	(a1)+,d0			* anz dims
		move.l	d0,d2
		subq.l	#1,d2			* mit 0...ende-1
		lsl.l	#2,d2			* x4,da dort
		move.l	d2,(a2)+
dmpa1:
		move.l	(a1)+,d2			* alle deeps einlesen
		subq.l	#1,d2
		move.l	d2,(a2)+
		clr.l	(a3)+
		subq.l	#1,d0
		bne		dmpa1		
		moveq.l	#-1,d0
		move.l	d0,(a2)			* ende markieren
		move.l	d0,(a3)

dmpanext:
		move.l	(a4),d0			* anzahl dims (schon x4 fÅr .l-tab)
dmpa3:
		lea		0(a5,d0),a2
		move.l	4(a4,d0),d2
		cmp.l	(a2),d2			* hintere dim schon max. erreicht?
		bge		dmpaok
dmpa2:
		clr.l	(a2)+
		cmp.l	#-1,(a2)			* alle hinteren deeps lîschen
		bne		dmpa2
		subq.l	#4,d0			* alle arrays schon durch...
		bmi		dumpnext
		lea		(a5,d0),a2
		addq.l	#1,(a2)
		move.l	4(a4,d0),d2
		cmp.l	(a2),d2
		blt		dmpa2
		bsr		dmpvar
		move.l	(a4),d0
		addq.l	#1,(a5,d0)
		bra		dmpa2ok
dmpaok:
		bsr		dmpvar			* d6:typ, a1 zeigt auf wert, wird upgedated
		addq.l	#1,(a2)
dmpa2ok:
		bsr		dmpchkstop
		bra		dmpanext

dmpchkstop:
		movem.l	d0-a6,-(sp)
		move.l	dmpa0,a0
		bsr		chk_stop
		movem.l	(sp)+,d0-a6
		rts

dumpend:
		move.l	dmpa0,a0
		rts



* tauscht 2 variablen des gleichen typs aus!
Swapvars:
		bsr		var2_def
		cmp.l	#0,a6		* mark_str ggf. aufheben
		beq		swap1
		clr.b	(a6)
swap1:
		move.l	a1,-(sp)
		move.w	typvalid,-(sp)
		bsr		charget
		bsr		var2_def
		cmp.l	#0,a6
		beq		swap2
		clr.b	(a6)
swap2:
		move.w	(sp)+,d0
		move.l	(sp)+,a2
		move.w	typvalid,d1

		cmp.b	#INT,d0
		beq		swapint
		cmp.b	#FLOAT,d0
		beq		swapfloat
swapstr:
		cmp.b	#STRING,d1
		bne		NADDI_
swap1int:
		move.l	(a1),d0
		move.l	(a2),(a1)
		move.l	d0,(a2)
		bra		charget
swapint:		
		cmp.b	#STRING,d1
		beq		NADDI_
		cmp.b	#INT,d1
		beq		swap1int
		movem.l	(a1),d0-d2
		clr.l	d3
		bsr		rpkl
		move.l	(a2),d4
		move.l	d0,(a2)
		bsr		ltor_
		movem.l	d0-d2,(a1)
		bra		charget
swapfloat:
		cmp.b	#STRING,d1
		beq		NADDI_
		cmp.b	#FLOAT,d1
		beq		swap1float
		move.l	(a1),d4
		bsr		ltor_
		movem.l	(a2),d4-d6
		movem.l	d0-d2,(a2)
		move.l	d4,d0
		move.l	d5,d1
		move.l	d6,d2
		clr.l	d3
		bsr		rpkl
		move.l	d0,(a1)
		bra		charget
swap1float:
		movem.l	(a1),d4-d6
		movem.l	(a2),d0-d2
		movem.l	d4-d6,(a2)
		movem.l	d0-d2,(a1)
		bra		charget

		
*****************************************
* ASC
*****************************************
* ermittelt den Ascii-kode des ersten stringzeichens
Asc:
          move.w    #STRING,typvalid
          bsr       get_term
          move.l    str_ptr,a1
          bra       extbyte             * byte aus a1 lesen und auf lw
*****************************************
* VAL
*****************************************
* errechnet inhalt eines strings
Val:
Function:
          move.w    #STRING,typvalid
          bsr       get_term            * string holen -> str_ptr
          move.l    a0,-(sp)

          move.l    str_ptr,a0
          addq.l    #1,a0
          move.l    a0,a1
lll1:
          tst.b     -(a0)
          bne       lll1
          move.l    a0,a2
lll2:
          move.b    (a2),d0
          move.b    -(a1),(a2)+
          move.b    d0,(a1)
          cmp.l     a2,a1
          bgt       lll2

          move.w    #FLOAT,typvalid
          bsr       get_term            * inhalt des strings in float wandeln

          move.l    (sp)+,a0
          move.w    #FLOAT,typflag
          movem.l   fac1,d0-d3
          rts
*****************************************
* STR
*****************************************
* wandelt einen numerischen ausdruck in einen string
Str:
          move.w    #STRING,typvalid    * string,float und int sind erlaubt
          bsr       gets_term           * wertet beliebigen Ausdruck aus
          move.l    a0,-(sp)            * Zeiger auf Basiczeile erhalten
          move.w    typ2flag,d0         * Art des Ausdrucks
          beq       misargerr           * kein Ausdruck gefunden?
          cmp.w     #FLOAT,d0           * float?
          beq       strfl
          cmp.w     #INT,d0
          bne       NADDI_              * keine string-var erlaubt
          move.l    fac1,d0
          bsr       ipka_               * gibt ptr auf string in a2 zurÅck
          bra       str1a
strfl:    movem.l   fac1,d0-d3
          bsr       rpka_
str1a:    move.l    strend,a1           * zeiger auf string
          move.l    a1,a3
          addq.l    #1,a3
str1b:    move.b    -(a2),-(a3)
          bne       str1b
          move.l    (sp)+,a0
          lea       zero_+4,a2          * dummy
          move.w    #STRING,typflag
          rts
*****************************************
* LEN
*****************************************
* ermittelt lÑnge eines strings
Len:
          move.w    #STRING,typvalid
          bsr       get_term
          move.w    #INT,typflag
          move.l    str_ptr,a1
          move.l    a1,a2
		addq.l	#1,a2
len1:     tst.b     -(a2)
          bne       len1
          sub.l     a2,a1
          move.l    a1,d0
          rts
*****************************************
* GET
*****************************************
* Holt ein Zeichen von tastatur bzw file
* um string-speicher zu sparen, wird ggf. auch in vorhandenen string
* geschrieben
Get:
          move.l    a0,work2
          bsr       charget
          cmp.b     #'#',d0             * get #filehandle?
          bne       Getkey
          bsr       get_handle          * holt log.handle
          bsr       chk_komma
          bsr       getI
          bsr		getII
          move.l    a1,-(sp)
Get1:     lea       key,a1
          moveq.l   #1,d0
          bsr       f_read              * 1 zeichen von file holen
          move.b    key,d0
          cmp.b     #10,d0              * bei 10-code folgt noch RET!
          beq       Get1
          move.l    (sp)+,a1
          bra       Get2

* get von tastatur
Getkey:   move.l    work2,a0
          bsr       getI
		move.w	d0,work2			* fl von getI merken

		move.l	a0,-(sp)
		move.l	a1,-(sp)
		move.w	#$b,-(sp)
		trap		#1
		addq.l	#2,sp
		move.l	(sp)+,a1
		move.l	(sp)+,a0
		tst.w	d0
		bne		charavailable
* - keine zeichen verfÅgbar-> str ist leer!
		tst.w	work2
		beq		getkey1			* schon mal definiert?
		bsr		mark_str
getkey1:
		move.l	#zero_+4,(a1)
		bra		charget

charavailable:
		tst.w	work2
		bsr		getII
		move.l	a0,-(sp)
          move.l    a1,-(sp)
          move.w    #7,-(sp)
          trap      #1                  * auf taste warten
          addq.l    #2,sp
          move.l    (sp)+,a1
		move.l	(sp)+,a0

Get2:     move.l    (a1),a1
          move.b    d0,(a1)
          clr.b     -(a1)
          bra       charget


*****************************************
* unterroutinen fÅr get (holt str -> a1)
getI:
          bsr       tst_var             * testet auf Variable und holt ggf adr.
          bsr       tstsysvar
          move.w    typflag,typvalid
          cmp.w     #STRING,typvalid    * es muss eine string-var sein!
          bne       NADDI_
          move.w    d0,-(sp)
          tst.w     d0
          bne       get1                * ja, schon definiert
          bsr       create2_var
get1:
          tst.b     arrayfl
          beq       get2
          bsr       posarray            * holt argument und positioniert (->a1)
          bsr       chk_klammer
get2:
          move.w    (sp)+,d0            * flag, ob var. neu o. alt war
		rts

getII:	* achtung, sr von getI gesetzt!
          bne       get3
get3a:
          move.l    strend,(a1)
          subq.l    #2,strend           * string braucht nur 2 byte (x,0)
          move.l    strend,d0
          sub.l     #32,d0
          cmp.l     varend,d0
          bmi       outvarmem
          bra       get4
get3:
          move.l    (a1),a2
		cmp.l	#0,a2
		beq		get3a
		tst.b	(a2)				* leer bzw. dummy?
		beq		get4a
          tst.b     -1(a2)              * string zu groû?
		beq		get4
get4a:
		bsr		mark_str
          bra       get3a
get4:
          rts

*****************************************
* setzt an prg zurÅck
restore:
          moveq.l   #-1,d0
          move.l    d0,dataptr
          move.l    d0,dataadr
          move.l    prgbase,restadr
          rts
*****************************************
* RESTORE
*****************************************
* setzt data-zeiger auf bestimmte adr.
Restore:
          bsr       restore
          bsr       tstnxtarg
          bne       rest1               * keine zeilenr angegeben...
          move.w    #INT,typvalid
          bsr       get_term
          move.l    fac1,d0
          bsr       poszeile
          tst.l     (a1)                * zeile nicht vorhanden?
          beq       nolineerr
          move.l    a1,restadr
          rts
rest1:    bra       charget

*****************************************
* unterroutine fÅr Read, die ab basic-start erstes data sucht
* a1 zeigt auf erste zu suchende zeile
* -> dataptr, dataadr, BNE -> OK
posdata:
          move.l    a0,a6
          move.l    a1,a0
posd2:    move.l    (a0),d7
          beq       posd2end                 * fehler: kein data-element da!
          move.l    a0,a1
          addq.l    #8,a0                    * auf zeileninhalt setzen
posd1:    bsr       charget                  * befehl lesen
          lsl.w     #8,d0
          move.b    (a0)+,d0
          cmp.w     #DATA,d0                 * ist es data-befehl?
          beq       posdend
          bsr       dtonxtcmd                * nein, dann zum nÑchsten com.
          tst.b     -1(a0)
          bne       posd1                    * zeilenende?
posdnl:   move.l    d7,a0
          bra       posd2
posdend:  move.l    a0,dataptr               * zeiger hinter data
          move.l    a1,dataadr               * zeiger auf data-line!
          move.l    a6,a0
          moveq.l   #1,d0
          rts
posd2end: move.l    #-1,dataptr
          clr.l     dataadr
          move.l    a6,a0
          moveq     #0,d0
          rts
*****************************************
* READ
*****************************************
* liest datas ein
Read:
readmore: tst.l     dataptr             * zeiger auf next data
          bpl       read1                    * -1 -> suchen
          tst.l     dataadr                  * noch datas vorhanden?
          beq       nodataerr
          move.l    restadr,a1               * suchen ab basicstart
          bsr       posdata
          beq       nodataerr
read1:    bsr       var2_def                 * varname holen -> a1 auf wert
          move.l    a0,-(sp)
          move.l    a1,-(sp)
          move.l    dataptr,a0
          bsr       get_defterm
          move.l    (sp)+,a1
          bsr       write_var                * variable schreiben
          bsr       tst_komma                * folgt weiteres element?
          beq       read2
          move.l    dataadr,a1               * werte fÅr posd1
          move.l    (a1),d7
          tst.b     d0                       * zeilenende, dann next line
          beq       read4
          cmp.b     #':',d0                  * nein, dann auf jeden fall :
          bne       syntaxerr
          bsr       posd1                    * nÑchstes data suchen
          bra       read3
read4:    bsr       posdnl                   * gleich in next line
          bra       read3
read2:    move.l    a0,dataptr
read3:    move.l    (sp)+,a0
          bsr       charget
          cmp.b     #',',d0                  * noch eine variable einlesen?
          beq       readmore
          rts
*****************************************
* REM
*****************************************
* prg-dokumentation
Rem
          bra       iffalse
*****************************************
* ELSE
*****************************************
Else:
          move.l    ifendptr,a1
          cmp.l     #iftbl,a1
          beq       elseerr
          subq.l    #4,a1
          move.l    a1,ifendptr
          move.l    (a1),d0             * 0 oder 1 als argument
          beq       iftrue              * hier alles genau umgekehrt!
          bra       iffalse
*****************************************
* IF
*****************************************
* if then - befehl , then wird direkt abgefragt
If:
          move.w    #INT,typvalid
          bsr       get_term            * ausdruck holen
          bsr       tstelse             * ist in nÑchster zeile ein else?
          bne       if1                 * nein, dann kann tabelle gespart werden
          move.l    ifendptr,a1
          cmp.l     #endiftbl-4,a1      * zuviele ifs ineinander?
          bge       ifflow
          move.l    fac1,(a1)+
          move.l    a1,ifendptr
if1:      tst.l     fac1                * wahr (1) oder falch (0)
          beq       iffalse             * falsch, dann in nÑchste zeile
          bsr       chargot             * jetzt wird then erwartet
          move.b    d0,d1
          lsl.w     #8,d1
          move.b    (a0)+,d1
          cmp.w     #THEN,d1
          bne       thenerr             * es fehlt!
iftrue:   addq.l    #4,sp               * jsr (a2) in befehl [exec_line]
          bra       exec1
iffalse:  addq.l    #4,sp               * auch hier den jsr abÑndern
          bra       exec_end            * zeilenausfÅhrung beenden (next line!)
*****************************************
* ELSE
*****************************************
* testet, ob in nÑchster zeile ein else steht!
* -> BEQ wenn ja
tstelse:
          move.l    a0,-(sp)
          tst.w     b_modus
          beq       noelse
          addq.w    #1,ifcnt            * ein if in der zeile mehr
          cmp.w     #1,ifcnt            * sind es mehr als 1 if, dann kein else
          bne       noelse
          move.l    akt_adr,a0
          move.l    (a0),a0
          tst.l     (a0)                * gibt es eine nÑchste zeile?
          beq       noelse
          addq.l    #8,a0               * in zeile gehen
          bsr       charget
          lsl.w     #8,d0
          move.b    (a0),d0
          cmp.w     #ELSE,d0
          bne       noelse
          move.l    (sp)+,a0
          moveq     #0,d0
          rts
noelse:   move.l    (sp)+,a0
          moveq.l   #-1,d0
          rts
*****************************************
* NEXT
*****************************************
* next (...siehe For!)
* for-next struktur:     0  ptr auf wert
*                        4  typ
*                        6  to-wert
*                        18 step-wert
*                        30 zeilennr
*                        34 adr der zeile
*                        38 adr hinter for-step
Next:
          bsr       tonxtcmd            * bis zum nÑchsten : oder 0 springen
          move.l    foreptr,a1
          cmp.l     #fortable,a1        * wenn noch kein for gesichert
          beq       nexterr             * dann fehler!
          sub.l     #42,a1              * auf anfang der struktur setzen
          move.l    (a1),a2             * zeiger auf variable
          cmp.w     #INT,4(a1)          * zwei verschiedene routinen fÅr typen
          beq       nextint
nextfloat:
          movem.l   (a2),d0-d2
          moveq     #0,d3
          moveq     #0,d7
          movem.l   18(a1),d4-d6
          movem.l   a0-a2,-(sp)         * wichtige register sichern
          bsr       radd_               * float addieren -> d0-d3
          movem.l   (sp)+,a0-a2
          movem.l   d0-d2,(a2)          * variable auffrischen
          moveq     #0,d7
          movem.l   6(a1),d4-d6         * to-wert
          btst      #7,18(a1)           * wenn step-wert neg, dann alles umdrhen
          bne       next2
          bsr       rcmp_               * beide floats vergleichen  1-2
          bhi       nextend             * variable hat to-wert erreicht
          bra       nextcont
next2:    bsr       rcmp_               * beide floats vergleichen  1-2
          bmi       nextend             * variable hat to-wert erreicht
          bra       nextcont
nextint:
          move.l    (a2),d0
          add.l     18(a1),d0           * step-wert dazuaddieren
          move.l    d0,(a2)
          btst      #7,18(a1)           * neg. step-wert, dann umdrehen
          bne       next3
          cmp.l     6(a1),d0            * mit to-wert vergleichen
          beq       nextcont
          bpl       nextend
          bra       nextcont
next3:    cmp.l     6(a1),d0  
          bmi       nextend
nextcont:
          move.l    30(a1),akt_zeile    * zeilennr. restaurieren
          move.l    34(a1),akt_adr      * adr der zeile
          move.l    38(a1),a0           * akt. ptr auf befehle
          rts
nextend:
          sub.l     #42,foreptr         * for-schleife lîschen
          rts
*****************************************
* FOR
*****************************************
* for-to-step-next schleife, auch Åber mehrere zeilen
* feld angelegt: 1. ptr auf wert, 2. typ, 3. to-wert, 4. step (add-wert)
*                5. zeilennr des for, 6. adr der zeile, 7. adr
* - ergibt 4+2+12+12+4+4+4 = 42 bytes!!!!!! (nicht ohne weiteres Ñnderbar)
For:
          clr.w     sysallow            * kein sysvar erlaubt
          bsr       var_def             * variable anlegen, -> a2 ptr auf wert!
          clr.b     typvalid            * oberes byte (arrayflag) uninteressant
          cmp.w     #STRING,typvalid    * bei stringvar. type mismatch
          beq       typemis
          move.l    foreptr,a1          * adr des 42byte-speichers
          cmp.l     #endfortbl-42,a1    * schauen, ob schon Åberlauf
          bhi       forflow             * ja, dann fehler
          move.l    a2,(a1)+
          move.w    typvalid,(a1)+
          bsr       chargot
          lsl.w     #8,d0
          move.b    (a0)+,d0
          cmp.w     #TO,d0              * es muss to folgen!
          bne       toerr
          move.l    a1,-(sp)
          bsr       get_term            * to-wert holen
          move.l    (sp)+,a1
          movem.l   fac1,d0-d2
          movem.l   d0-d2,(a1)          * to-wert speichern
          add.l     #12,a1
          bsr       chargot
          cmp.b     #TOKEN1,d0 		* wenn kein step, dann default
          bne       nostep
          lsl.w     #8,d0
          move.b    (a0)+,d0
          cmp.w     #STEP,d0            * es muss step folgen!
          bne       syntaxerr
          move.l    a1,-(sp)
          bsr       get_term            * step-wert holen
          move.l    (sp)+,a1
          movem.l   fac1,d0-d2
          bra       for1
nostep:   cmp.w     #INT,typvalid       * default fÅr step ist 1
          beq       intstep
          move.l    #$4001,d0
          move.l    #$00010000,d1
          moveq.l   #0,d2
          bra       for1
intstep:  moveq.l   #1,d0
for1:     movem.l   d0-d2,(a1)          * step-wert speichern
          add.l     #12,a1
          move.l    akt_zeile,(a1)+     * akt. zeile
          move.l    akt_adr,(a1)+       * adr des zeilenanfangs
          move.l    a1,-(sp)            * diesen ptr aktualisieren
          subq.l    #1,a0               * da bei get_term ein zeichen weiter
          bsr       tstnxtarg           * es muss : oder zeilenende folgen
          beq       syntaxerr
          addq.l    #1,a0
          move.l    (sp)+,a1
          move.l    a0,(a1)+            * akt. adr abspeichern
          move.l    a1,foreptr
          rts

*****************************************
* CLOSE
*****************************************
* schliesst file und entfernt eintrag!
Close:
          bsr       get_handle
          cmp.w     #5,handle
          ble       close1 
          clr.l     (a1)                * eintrag lîschen
          bra       f_close
close1:   rts
*****************************************
* holt log.handle -> handle
get_handle:
          clr.w     cmdfl
          clr.w     handle
          move.w    #INT,typvalid
          bsr       get_term
          move.l    fac1,d0
		bmi		negerr
          cmp.l     #$ffff,d0           * zu gross?
          bpl       toobigerr
          cmp.w     #5,d0
          ble       get_h1              * handle 0-5 -> sonderfÑlle

          lea       handtab,a1          * filetable
cl2:      cmp.w     (a1),d0             * eintrag gefunden?
          beq       cl1
          addq.l    #4,a1
          cmp.l     #endhtab,a1         * handle-table Åbergelaufen?
          bge       notopenerr
          bra       cl2

cl1:      move.w    2(a1),handle        * basic-handle
          rts
get_h1:   move.w    d0,handle           * sonderfÑlle 0-3
          rts

*****************************************
* OPEN/CREATE handle,name
*****************************************
* îffnet ein file, setzt handletable
* sonderfÑlle: handle 0-5 sind devices (3:printer...)
Create:
		clr.w	-(sp)
		bra		openfile
Open:
		move.w	#1,-(sp)
openfile:
          move.w    #INT,typvalid
          bsr       get_term            * basic-handle holen
          move.l    fac1,d0
		bmi		negerr
          cmp.l     #$ffff,d0           * zu gross?
          bpl       toobigerr
          cmp.w     #5,d0               * lhandle 0-5 sonderfall!
          ble       open0123            * wenn <= 5, dann kein str erlaubt!

* testen, ob schon offen
          lea       handtab,a1          * filetable
open0:    cmp.w     (a1),d0             * eintrag gefunden?
          beq       alropen             * -> schon offen fehler!
          addq.l    #4,a1
          cmp.l     #endhtab,a1         * handle-table Åbergelaufen?
          blt       open0

          lea       handtab,a1          * filetable
open2:    tst.w     (a1)                * leerer eintrag?
          beq       open1
          addq.l    #4,a1
          cmp.l     #endhtab,a1         * handle-table Åbergelaufen?
          bge       handflow
          bra       open2

open1:
		move.w	d0,-(sp)			* basic-handle
          bsr       chk_komma
          move.w    #STRING,typvalid    * jetzt den filenamen einlesen
          move.l    a1,-(sp)
 		move.l    strend,spstr
		bsr       onqlist
          bsr       get_defterm         * brauchen
		bsr       offqlist
		move.l    spstr,strend

		tst.w	6(sp)			* fl create/open; offs 6 wegen a1/handle auf sp
		beq		open3
          bsr       f_open              * file îffnen
		bra		open4
open3:
		bsr		f_create
open4:
		move.l    (sp)+,a1
		move.w	(sp)+,(a1)+		* basic handle!
          move.w    handle,(a1)         * log. handle auch eintragen!
open0123:
		addq.l	#2,sp			* fl create/open
		rts

*****************************************
* ON
*****************************************
* springt je nach arg. in eine angegebene zeile
* arg = 1 -> z1 usw.
On:
		move.l	a0,work1
		bsr		charget
		lsl.w	#8,d0
		bsr		charget
		cmp.w	#TRACE,d0			* on trace?
		bne		OnX
		bsr		charget
		lsl.w	#8,d0
		bsr		charget
		cmp.w	#GOSUB,d0			* on trace gosub?
		bne		trgoserr
		move.w	#INT,typvalid
		bsr		get_term
		move.l	fac1,d0
		bsr		poszeile
		cmp.l	4(a1),d0			* gibt es zeile?
		bne		nolineerr
		move.l	fac1,traceline
		bra		charget

OnX:
		move.l	work1,a0
          move.w    #INT,typvalid
          bsr       get_term
          move.l    fac1,onarg          * arg 1-...
		subq.l	#1,onarg
          bsr       chargot
          lsl.w     #8,d0
          move.b    (a0)+,d0
          move.w    d0,oncmd            * fÅr spÑter merken
on2:      bsr       tstnxtarg           * folgt eine sprungadr.
          bne       syntaxerr           * nein, dann fehler
          bsr       get_term            * sprung holen
          subq.l    #1,a0
          tst.l     onarg               * ist es die richtige adresse
          beq       onfound             * ja
          cmp.b     #',',(a0)+          * folgt ein weiteres arg?
          bne       onend               * nein, dann heute wohl nicht...
          subq.l    #1,onarg
          bra       on2
onfound:  move.w    oncmd,d0
          cmp.w     #GOTO,d0
          beq       ongoto
          cmp.w     #GOSUB,d0
          bne       syntaxerr
ongosub:  bsr       tonxtcmd            * springt hinter den on-gosub...
          bra       Gosub1
ongoto:   bra       Run1
onend:    rts
*****************************************
* INPUT
*****************************************
* Holt ein oder mehrere argumente; ein textstr kann zwecks ausgabe davor stehen
Input:
          move.l    a0,work2
          bsr       charget
          cmp.b     #'#',d0             * input #filehandle?
          bne       Input1
          bsr       get_handle          * holt log.handle
          bsr       chk_komma
* hier beginnt das file-input...
finpnext: bsr       var2_def            * variable holen -> a1/typvalid
          move.l    a0,-(sp)
          lea       inputpuf,a0
          move.l    a0,inptr
          move.l    a1,-(sp)            * retten
          move.l    a0,a1
finp1:    moveq     #1,d0
          move.l    a1,-(sp)
          bsr       f_read              * 1 byte aus file lesen
          move.l    (sp)+,a1
          tst.l     d0                  * ende der datei?
          beq       finp1end
          move.b    (a1)+,d0
          beq       finp1end            * 0-kode als ende
          cmp.l     #inputpuf+254,a1    * nÑchstes datas kurz vor Åberschreiben
          beq       finp1end
          cmp.b     #9,d0               * tab als ende
          beq       finp1end
          cmp.b     #10,d0              * es folgt noch 13-> 10 Åbergehen
          bne       finp1b
          subq.l    #1,a1
          bra       finp1
finp1b:   cmp.b     #13,d0              * RET als ende
          bne       finp1               * keiner dieser kodes, dann weiter
finp1end: clr.b     (a1)
          move.l    a1,d0
          move.l    (sp)+,a1            * zeiger auf wert der var wiederholen
          cmp.w     #STRING,typvalid
          bne       finp3               * kein str?, dann mit get_term

          sub.l     #inputpuf,d0
          move.l    strend,d1
          sub.l     #32,d1
          sub.l     d0,d1
          cmp.l     varend,d1
          bmi       outvarmem

*         sub.l     d0,strend
          move.l    strend,a0
          move.l    a0,str_ptr
          addq.l    #1,a0
          lea       inputpuf,a2
          subq.l    #1,d0
          bra       ll2
ll1:
          move.b    (a2)+,-(a0)
ll2:
          dbf       d0,ll1
          clr.b     -(a0)
          subq.l    #1,a0
          move.l    a0,strend
          bra       finp4
finp3:
          move.l    a1,-(sp)
          bsr       get_term
          move.l    (sp)+,a1
finp4:    bsr       write_var           * variable INT/FLOAT schreiben
          move.l    a0,inptr
          move.l    (sp)+,a0            * nÑchste var. einlesen
          bsr       charget
          cmp.b     #',',d0             * wenn neues arg, dann auch hier ,
          beq       finpnext
          rts

Input1:   * normales input von der tastatur...
          move.l    work2,a0
          move.l    a0,a1
          lea       fragez,a0
          bsr       put_string
          move.l    a1,a0
          bsr       charget
          subq.l    #1,a0
          cmp.b     #'"',d0             * ", dann kommt textstr
          bne       inp1
          move.w    #STRING,typvalid    * es wird ein textstring erwartet
          bsr       get_term
          move.l    a0,-(sp)
          move.l    str_ptr,a0
          bsr       putstrreverse
          move.l    (sp)+,a0
          bsr       chargot
          cmp.b     #';',d0             * nach textstr sollte ; folgen
          bne       syntaxerr
inp1:     * es folgt die einzulesende argumentenliste
          move.l    a0,-(sp)

          moveq.l   #0,d0
          move.w    ed_xoffs,d0
          add.w     ed_x,d0
          move.l    d0,-(sp)
          move.l    edibase,a1
          move.l    #inputentry,edi_retprg(a1)
          move.l    sp,inputpuf
          bra       posquit
inputentry:         * Text einlesen bis RET!
          move.l    edibase,a1
          clr.l     edi_retprg(a1)
          move.l    inputpuf,sp
          move.l    (sp)+,d1            * frÅhere xpos
          add.l     d1,a0               * in zeile pos.
          sub.l     d1,d0               * deswegen maxspalten updaten

		move.l	a0,a1
		lea		inputpuf,a0
          move.l    a0,inptr
          bsr       copya1_ina0         * nach inputpuf bringen
          move.l    (sp)+,a0

inpnext:  bsr       var2_def            * variable holen -> a1/typvalid
          move.l    a0,-(sp)
          move.l    inptr,a0
          cmp.w     #STRING,typvalid
          bne       inp3                * kein str?, dann mit get_term

          move.l    strend,a2
          move.l    a2,str_ptr
          addq.l    #1,a2
inp2b:    move.b    (a0)+,d0
          beq       inp2a
*          cmp.b     #':',d0
*          beq       inp2a
          cmp.b     #',',d0
          beq       inp2a
          move.b    d0,-(a2)
          move.l    a2,a3
          sub.l     #32,a3
          cmp.l     varend,a3
          bmi       outvarmem
          bra       inp2b
inp2a:    clr.b     -(a2)
          subq.l    #1,a2
          move.l    a2,strend
          bra       inp4
inp3:
          move.l    a1,-(sp)
          bsr       get_term
          move.l    (sp)+,a1
inp4:     bsr       write_var           * variable INT/FLOAT schreiben
          bsr       tst_komma           * nur weitermachen wenn , folgt
          bne       inpend
          move.l    a0,inptr
          move.l    (sp)+,a0            * nÑchste var. einlesen
          bsr       charget
          cmp.b     #',',d0             * wenn neues arg, dann auch hier ,
          beq       inpnext
          bra       syntaxerr
inpend:
          bsr       new_line
          move.l    (sp)+,a0
          bra       charget



*****************************************
* bei den Fn-Cmd ist das Problem, der ganze Fn-Block(typ,ptr,typ..,ascii..)
* im stringpuffer liegt und damit kein $ff enthalten darf, da dieses als
* Mark-UngÅltig-String bei garbage erkannt wird
* Deswegen mÅssen alle $ff entfernt werden: $ff taucht nur bei ptrs auf
* -> diese ptr mit aufbau  00 0x yy zz (z.B. 00 01 ff 88)
* -> hier ist yy das einzige byte, das $ff enthalten kann -> 0x yy mal 2
* -> es wird gerade !!! Beim Auslesen muss dies natÅrlich wieder /2 div. werden
code_ptr:
          move.b    d0,d1
          add.l     d0,d0
          move.b    d1,d0          * -> d0 gecodeter wert
          rts

decode_ptr:
          move.b    d0,d1
          lsr.l     #1,d0
          move.b    d1,d0          * -> d0 decodeter wert
          rts

* Aufbau des Fn-Strings:
*	[RÅckgabetyp (def:FLOAT)].w {[typ].w [ptr].l}... $0.w
*	[asciitext der funktion...].b  

*****************************************
* FN
*****************************************
* Wird als funktion behandelt -> fn(arg1,...)
Fn:
          move.l    str_ptr,spstr
          bsr       onqlist
          move.l    strend,spstr
          bsr       onqlist
          bsr       tst_dfnvar          * testet auf fkt-variable vorhanden (a1)
          tst.w     d0
          beq       fndeferr            * noch nicht def. -> fehler
          move.l    (a1),a2             * zeiger auf def-feld
		move.w	(a2)+,-(sp)		* typflag der rÅckgabe merken!
          tst.w     (a2)                * arg vorhanden
          beq       fn1                 * nein, dann nicht auf ( prÅfen
          bsr       charget
          cmp.b     #'(',d0
          bne       misargerr           * es fehlen argumente!
fn2:      move.w    (a2)+,typvalid      * typ des folgenden argumentes
          move.l    a2,-(sp)
          bsr       get_defterm
          move.l    (sp)+,a2
          move.l    (a2)+,d0            * zeiger auf wert des arg.
          bsr       decode_ptr
          move.l    d0,a1
          move.l    a2,-(sp)
          bsr       write_var           * variable schreiben
          move.l    (sp)+,a2
          tst.w     (a2)                * alle arg vorhanden?
          beq       fn1a
          bsr       tst_komma           * es muss noch ein arg folgen!
          bne       misargerr
          bra       fn2
fn1a:     bsr       chk_klammer
fn1: * jetzt, da alle fkt-arg init. sind, fkt ausfÅhren
          move.w    (sp)+,typvalid      * typ, der zurÅckkommen muss
          move.l    a0,-(sp)
          addq.l    #2,a2               * zur funktion vordringen
          move.l    a2,a0               * hier steht nun die funktion
          move.w    argfl,-(sp)
          move.w    #-1,argfl
          bsr       get_term
          move.w    (sp)+,argfl
          move.w    typvalid,typflag
          move.l    str_ptr,a1
          lea       zero_+4,a2
          movem.l   fac1,d0-d3
          move.l    (sp)+,a0
          bsr       offqlist
          move.l    spstr,strend
          bsr       offqlist
          move.l    spstr,str_ptr
          rts
*****************************************
* DEFFN
*****************************************
* bereitet funktionsvariable in speicher vor (arg werden als normale vars
* jedoch mit bit14=1 gespeichert, so dass sie nicht mit normalen vars ver-
* tauscht werden!). die funtktionsvar ist wie Åblich, aber bit13=1
Deffn:
          bsr       charget
          move.b    d0,d1
          lsl.w     #8,d1
          bsr       charget
          move.b    d0,d1
          cmp.w     #FN,d1              * auf def muss fn folgen oder proc
          bne       checkforproc
          bsr       tst_dfnvar          * testet auf Variable und holt ggf adr.
          move.w    typflag,typvalid    * typ ohne bit13 gesetzt
          or.w      #$2000,typvalid     * bit13 setzen
          tst.w     d0
          bne       redef               * ja, schon definiert -> Fehler
          bsr       create2_var         * anlegen
          addq.w    #1,fncnt
* -> a1 zeigt auf ptr
          lea       var2_name,a2        * var2_name nur bei Dim gebraucht
		move.w	fntyp,(a2)+

          move.l    a1,-(sp)
          bsr       charget
          cmp.b     #'=',d0
          beq       def_f3
          cmp.b     #'(',d0             * ansonsten mÅsste arg-liste folgen
          bne       syntaxerr           * und zwar in klammern

def_f6:   move.l    a2,-(sp)
          bsr       tst_fnvar           * testet auf Variable und holt ggf adr.
          move.w    typflag,typvalid    * typ ohne bit14 gesetzt
          or.w      #$4000,typvalid     * bit14 setzen
          tst.w     d0
          bne       def_f4              * ja, schon definiert
          bsr       create2_var         * anlegen
def_f4:
          move.l    (sp)+,a2
          move.w    typflag,(a2)+       * typ des argumentes
          move.l    a1,d0
          bsr       code_ptr
          move.l    d0,(a2)+            * zeiger auf wert der variable
          bsr       charget
          cmp.b     #')',d0
          beq       def_f3a             * ende!
          cmp.b     #',',d0             * arg mÅssen durch komma getrennt sein!
          beq       def_f6              * zum nÑchsten arg
          bra       syntaxerr
def_f3a:  bsr       charget
          cmp.b     #'=',d0             * nach arg-lister muss = folgen!
          bne       syntaxerr
def_f3:
          clr.w     (a2)+               * endkennung der arg-liste!

def_f7:   move.b    (a0)+,d0            * jetzt die funktion kopieren
          beq       def_f8
          cmp.b     #':',d0
          beq       def_f8
          move.b    d0,(a2)+
          bra       def_f7
def_f8:   clr.b     (a2)+
          clr.b     (a2)+
          clr.b     (a2)+               * noch 2 nuller zur sicherheit!
          lea       var2_name,a3
          sub.l     a3,a2               * lÑnge des strings
          move.l    a2,d0

          move.l    strend,a1
          clr.b     (a1)
          sub.l     #32,a1
          sub.l     d0,a1
          cmp.l     varend,a1           * passt string rein?
          bmi       outvarmem
          sub.l     d0,strend

          btst      #0,strend+3
          bne       wrdalligned
          subq.l    #1,strend
wrdalligned:
          move.l    strend,a1
		addq.l	#1,a1
          move.l    a1,a4
          subq.w    #1,d0
ll4:
          move.b    (a3)+,(a1)+
          dbf       d0,ll4
          move.l    (sp)+,a1
          move.l    a4,(a1)             * in deffn ptr auf string setzen
          rts


*
* Prcedure-Routinen fÅr DEF PROC, PROC name
*
* Aufbau einer PROC-Variablen:
* 	[nextptr].l [typ PROC&STRING].w [NAME].b .even [PTR AUF STRING].l
* String ist aufgebaut:
* 	[PROCNR (x8) 8,16,...].w [Ptr auf nÑchste Zeile (nach DEFPROC)].l
*    [typ var (inkl. procnr.].w [ptr auf wert].l ... (<- siehe FN's!)
*	$0.w
*    !alle PTR sind codiert, weil ein string kein $ff enthalten darf!
*
anzprocs	.dc.w	0
procnr	.ds.w	1

* definiert lokale variablen
Local:
		move.l	a0,-(sp)
		bsr		charget
		lsl.w	#8,d0
		bsr		charget
		cmp.w	#DIM,d0
		beq		localdim
* local a,b,c,...
		move.l	(sp)+,a0
localget:
		bsr		tst_var
		bmi		localfound	* gibt es schon diese lokale variable?
		tst.b	arrayfl
		bne		locdeferr
		tst.w	sysvar
		bne		locdeferr
		move.w	typflag,d1
		or.w		procnr,d1
		move.w	d1,typvalid
		bsr		create2_var
* lîschen
		move.w	typflag,d0
		cmp.b	#INT,d0
		bne		locnoint
		clr.l	(a1)
		bra		localfound
locnoint:
		cmp.b	#FLOAT,d0
		bne		locnofl
		movem.l	zero_,d0-d2
		movem.l	d0-d2,(a1)
		bra		localfound
locnofl:
		move.l	#zero_+4,(a1)
localfound:
		bsr		charget
		cmp.b	#',',d0
		beq		localget
		rts

localdim:
		addq.l	#4,sp
		bra		Localdim
		

* def proc Åberlesen
checkforproc:
		cmp.w	#PROC,d1
		bne		syntaxerr
		move.l	akt_adr,a0
cfp1:
		move.l	(a0),a1
		tst.l	(a1)
		beq		basic1			* ende des listings!
		addq.l	#8,a0
		bsr		charget
		lsl.w	#8,d0
		bsr		charget
		cmp.w	#ENDPROC,d0
		beq		cfpend1
		move.l	a1,a0
		bra		cfp1		
cfpend1:
		move.l	a1,akt_adr
		move.l	4(a1),akt_zeile
		lea		8(a1),a0
		addq.l	#4,sp			* JSR CMD in exec_line Åberlesen
		bra		exec_line


* vor run alle procs erkennen
get_procs:
		movem.l	a0/a1,-(sp)
		move.w	#1*8,procnr
		lea		prgbase,a0
proctstnxt:
		move.l	(a0),d0
		beq		endgetproc
		move.l	d0,-(sp)			* ptr auf nÑchste zeile merken
		addq.l	#8,a0			* zeigen auf zeilenbeginn.
		bsr		charget
		lsl.w	#8,d0
		bsr		charget
		cmp.w	#DEFFN,d0
		bne		procnxtline
		bsr		charget
		lsl.w	#8,d0
		bsr		charget
		cmp.w	#PROC,d0
		bne		procnxtline

          bsr       tst_dprcvar         * testet auf Variable und holt ggf adr.
          move.w    typflag,typvalid    * typ ohne bit12 gesetzt
          or.w      #PROCTYP,typvalid   * bit12 setzen
          tst.w     d0
          bne       redef               * ja, schon definiert -> Fehler
          bsr       create2_var         * anlegen
* -> a1 zeigt auf ptr
          lea       var2_name,a2        * var2_name nur bei Dim gebraucht
		move.w	procnr,(a2)+		* procnr ist x8 (bit 3-11)
		move.l	(sp),d0			* ptr auf nÑchste zeile
		bsr		code_ptr
		move.l	d0,(a2)+

          move.l    a1,-(sp)
          bsr       charget
		beq		proc_f3
          cmp.b     #'(',d0
		beq		proc_f6
		cmp.b	#':',d0
		beq		proc_f3
		bsr		Clr1
		bra		defprerr

proc_f6:
		move.l    a2,-(sp)
          bsr       tst_prcvar          * testet auf Variable und holt ggf adr.
		move.w	typflag,d1
		move.w	d1,-(sp)
		or.w		procnr,d1			* proc-nummer in var-typ einbinden
		move.w	d1,typflag
		bsr		var3_def			* einrichten...
		move.w	(sp)+,d1
          move.l    (sp)+,a2

          move.w    d1,(a2)+			* typ des argumentes (ohne procnr)
          move.l    a1,d0
          bsr       code_ptr
          move.l    d0,(a2)+            * zeiger auf wert der variable
          bsr       charget
          cmp.b     #')',d0
          beq       proc_f3             * ende!
          cmp.b     #',',d0             * arg mÅssen durch komma getrennt sein!
          beq       proc_f6             * zum nÑchsten arg
          bra       syntaxerr
proc_f3:
          clr.w     (a2)+               * endkennung der arg-liste!

          lea       var2_name,a3
          sub.l     a3,a2               * lÑnge des strings
          move.l    a2,d0

          move.l    strend,a1
          clr.b     (a1)
          sub.l     #32,a1
          sub.l     d0,a1
          cmp.l     varend,a1           * passt string rein?
          bmi       outvarmem
          sub.l     d0,strend

          btst      #0,strend+3
          bne       Wrdalligned
          subq.l    #1,strend
Wrdalligned:
          move.l    strend,a1
		addq.l	#1,a1
          move.l    a1,a4
          subq.w    #1,d0
copyprc:
          move.b    (a3)+,(a1)+
          dbf       d0,copyprc

          move.l    (sp)+,a1
          move.l    a4,(a1)             * in PROC ptr auf string setzen
		addq.w	#1*8,procnr		* eine nr. weiter
		cmp.w	#512*8,procnr		* max 511 erlaubt!
		beq		toomanyprocs

procnxtline:
		move.l	(sp)+,a0
		bra		proctstnxt

endgetproc:
		move.w	procnr,d0
		lsr.w	#3,d0
		subq.w	#1,d0
		move.w	d0,anzprocs
		clr.w	procnr
		movem.l	(sp)+,a0/a1
		rts


* eigentlicher aufruf!
* proctable struktur: 0  zeilennr der proc
*                     4  adr der zeile
*                     8  adr hinter proc-befehl
*				 12  procnr (alte)
*				 14
Proc:
		move.w	b_modus,-(sp)
		move.w	#-1,b_modus
          bsr       tst_dprcvar         * testet auf proc-variable vorhanden (a1)
          tst.w     d0
          beq       procnotfound        * noch nicht def. -> fehler
          move.l    (a1),a2             * zeiger auf def-feld
		move.w	(a2)+,-(sp)		* prozedurnr. (x8) merken
		move.l	(a2)+,d0			* adr der zeile der prozedur (coded)
		bsr		decode_ptr
		move.l	d0,-(sp)			* merken, erst am ende setzen

          tst.w     (a2)                * arg vorhanden
		bne		cproc2a
		move.l	a0,d1
		bsr		charget
		move.l	d1,a0
		tst.b	d0
          beq       cproc1              * nein, dann nicht auf ( prÅfen
		cmp.b	#':',d0
		beq		cproc1
		bra		manyargerr		* arg-Åbergabe, aber keins erlaubt!
cproc2a:
          bsr       charget
          cmp.b     #'(',d0
          bne       misargerr           * es fehlen argumente!
cproc2:   move.w    (a2)+,typvalid      * typ des folgenden argumentes
          move.l    a2,-(sp)
          bsr       get_defterm
          move.l    (sp)+,a2
          move.l    (a2)+,d0            * zeiger auf wert des arg.
          bsr       decode_ptr
          move.l    d0,a1
          move.l    a2,-(sp)
		cmp.w	#STRING,typvalid
		bne		nocprocmark
		bsr		mark_str
nocprocmark:
          bsr       write_var           * variable schreiben
          move.l    (sp)+,a2
          tst.w     (a2)                * alle arg vorhanden?
          beq       cproc1a
          bsr       tst_komma           * es muss noch ein arg folgen!
          bne       misargerr
          bra       cproc2
cproc1a:  bsr       chk_klammer
cproc1: * jetzt, da alle fkt-arg init. sind, fkt ausfÅhren
		move.l	(sp)+,a1			* ptr auf zeile
		tst.l	(a1)				* ist ende der zeile?
		beq		noeprcerr
		move.w	(sp)+,d0			* procnr

		move.l	proctblptr,a2
		cmp.l	#procetbl-14,a2
		bhi		toomanyprocs

		move.l	akt_zeile,(a2)+
		tst.w	(sp)+			* wenn direkt-modus -> akt_adr=0
		bne		itsprg
		clr.l	akt_adr
itsprg:
		move.l	akt_adr,(a2)+
		move.l	a0,(a2)+
		move.w	procnr,(a2)+
		move.l	a2,proctblptr
		
		move.w	d0,procnr
		move.l	a1,akt_adr
		move.l	4(a1),akt_zeile
		lea		8(a1),a0
		
contwithrun:
		lea		stack,sp
		move.w	#-1,b_modus
		bra		runcont


Endproc:
          move.l    proctblptr,a1
          cmp.l     #proctbl,a1         * kein proc bisher? dann fehler!
          beq       procerr
          sub.l     #14,a1
          move.l    a1,proctblptr
          move.l    (a1)+,akt_zeile
          move.l    (a1)+,akt_adr
          move.l    (a1)+,a0
		move.w	(a1)+,procnr
		bsr		charget
		lea		stack,sp
		tst.l	akt_adr
		bne		endprocprg
endprocdirekt:
		clr.w	b_modus
		pea		basic1
		bra		exec_line			* und hinter proc... weitermachen
endprocprg:
		move.w	#-1,b_modus
		bra		runcont

*****************************************
* HELP
*****************************************
* listet alle vorhandenen befehle auf
Help:
          movem.l   a0,-(sp)            * prgzeiger retten
          lea       helpnadr,a1         * zeiger auf tabelle mit commandnames
help1:    move.l    (a1)+,d0
          beq       helpend
          move.l    d0,a0
          move.l    a0,a2
help2:    addq.l    #1,a2
          move.b    (a2),d0             * dieses bit7 = 0 setzen
          beq       help2a
          bpl       help2
          bclr      #7,(a2)
help2a:   bsr       put_string
          move.b    d0,(a2)             * bit7 wieder wie frÅher setzen
          move.l    a1,-(sp)
          bsr       tab_
          move.l    (sp)+,a1
          bra       help1
helpend:  bsr       new_line
          move.l    (sp)+,a0
          bra       charget
*****************************************
* VARFRE
*****************************************
* gibt anzahl der freien bytes im var-puf aus
* fre(0,2,3...) mit garbage, fre(1):ohne garbage
Prgfre:
Varfre:   move.w    #INT,typvalid
          bsr       get_term
		cmp.l	#1,fac1
		beq		nofregarb
		move.l	strend,pgarbend	* nur belegten strspeicher testen
		bsr		garbage
nofregarb:
          move.w    #INT,typflag        * ergebnis ist int
          move.l    strend,d0
          sub.l     #32,d0
          sub.l     varend,d0           * ende - anfang
          rts


* gibt anzahl der freien bytes im str-puf aus
Strfre:   move.w    #INT,typvalid
          bsr       get_term
          move.l    strend,pgarbend     * nur belegten strspeicher testen
          bsr       garbage
          move.w    #INT,typflag        * ergebnis ist int
          move.l    strbase,d0
          sub.l     strend,d0           * ende - anfang
          rts

*****************************************
* TAB
*****************************************
Edtab:
          move.w    #INT,typvalid
          bsr       get_term
          move.w    #INT,typflag        * ergebnis ist int
		tst.w	filefl
		bne		edtabend			* keine file-ausgabe mgl.
          move.l    fac1,d0
		bmi		start1err
		beq		start1err
		clr.w	ed_x
		clr.w	ed_xoffs
edtab1:
		bsr		ed_tab
		subq.w	#1,d0
		bne		edtab1
edtabend:
		rts

* springt in angegebene spalte
Tab:
          tst.w     filefl              * ist file-ausgabe aktiv?
          bne       Spc                 * ja, dann wie spc behandeln
          bsr       get_tab
          move.w    ed_x,d1
          add.w     ed_xoffs,d1
          add.w     d0,d1
          cmp.l     maxspalten,d1
          bge       cposerr
          move.w    d1,d0
          move.w    ed_y,d1
          bra       ed_pos

*****************************************
* unterroutine, die tab-arg. prÅft und holt
get_tab:
          move.w    #INT,typvalid
          bsr       get_term
          move.w    #INT,typflag        * ergebnis ist int
          move.l    fac1,d0
		bmi		start1err
		beq		start1err
		subq.l	#1,d0
          cmp.l     maxspalten,d0
          bge       cposerr
          rts

*****************************************
* SPC
*****************************************
* gibt anzahl leerzeichen aus; als funktion liefert sie diese anzahl zurÅck
Spc:
          bsr       get_tab
          move.l    d0,d1               * merken
          beq       spc1
          move.l    a0,a2               * merken
          lea       inputpuf,a0
          move.l    a0,a1
spc2:     move.b    #' ',(a1)+
          subq.l    #1,d0
          bne       spc2
          clr.b     (a1)
          bsr       put_string          * anzahl leerzeichen ausgeben
          move.l    a2,a0
spc1:     move.l    d1,d0
          rts
*****************************************
* INT
*****************************************
* diese funktion liefert den INT-wert einer beliebigen numerischen var
* (eigentlich ÅberflÅssig, da float und int sowieso verwandelt werden kînnen!
* -> D0 ist wert, typflag ist INT
Int:
          move.w    #INT,typvalid       * wir wollen int zurÅck
          bsr       get_term
          move.l    fac1,d0
          move.w    #INT,typflag
          rts
*****************************************
* NEW
*****************************************
* wie clr aber auch basic-prg
New:
		bsr		New1
		bsr		charget
		bra		Clr1

New1:
		move.l	prgbase,a1
		move.l	a1,prgend
		clr.l	(a1)
		move.l	#-1,4(a1)
		rts

*****************************************
* CLR
*****************************************
* Lîscht alle Variablen und strukturen (setzt deren ptr zurÅck)
Clr:
          bsr       charget
		beq		simpleclr
		cmp.b	#':',d0
		beq		simpleclr
		subq.l	#1,a0
readclrnext:
		bsr		var2_def
		move.w	typvalid,d0
		cmp.b	#INT,d0
		beq		clrint
		cmp.b	#FLOAT,d0
		beq		clrfl
clrint:
		clr.l	(a1)
		bra		clrnext
clrfl:
		movem.l	zero_,d0-d2
		movem.l	d0-d2,(a1)
*		bra		clrnext
clrnext:
		bsr		charget
		bsr		tst_komma
		beq		readclrnext		
		rts

simpleclr:
		bsr		Clr1
		bra		get_procs			* prozeduren erfassen!

Clr1:     move.l    strbase,strend      * variablen lîschen
          move.l    prgend,d0    
          add.l     #16,d0
          move.l    d0,varbase
          move.l    d0,varend
          bsr       init_tbls           * for-next/gosub/if-tables lîschen
          movem.l   zero_,d0-d2
          move.l    varbase,a1
          movem.l   d0-d2,(a1)          * puffer lîschen
          move.l    strbase,a1
          clr.b     (a1)
          clr.b     -(a1)
          clr.b     -(a1)
          clr.b     -(a1)
          clr.w     fncnt               * anzahl der definierten DEF FN(x)
		clr.w	anzprocs			* "      "        "      PROCS
          rts
*****************************************
* lîscht alle for-next/gosub/if tables/procs
init_tbls:
          tst.l     contline
          bpl       init_tend           * nicht, wenn cont aktiv
          move.l    #fortable,foreptr   * alle for-next lîschen
          move.l    #gostabl,goseptr
          move.l    #iftbl,ifendptr
		move.l	#proctbl,proctblptr
		clr.w	procnr
		cmp.w	#2,tracefl		* 2 -> wieder 1 (tron)
		bne		init_tend
		move.w	#1,tracefl
init_tend:rts
*****************************************
* RETURN
*****************************************
* springt in die letzte gosub-zeile zurÅck
Return:
          move.l    goseptr,a1
          cmp.l     #gostabl,a1         * kein gosub bisher? dann fehler!
          beq       goserr
          sub.l     #12,a1
          move.l    a1,goseptr
          move.l    (a1)+,akt_zeile
          move.l    (a1)+,akt_adr
          move.l    (a1),d0
		btst		#31,d0
		beq		return
		
		bclr		#31,d0
		move.l	d0,a0		
		move.w	trx,d0
		move.w	try,d1
		bsr		ed_pos
		move.w	#2,tracefl		* 2: bei execpuf next cmd Åberspr.
		bra		return2

return:
		move.l	d0,a0
return2:
		tst.l	akt_adr
		beq		endprocdirekt
		bne		endprocprg


*****************************************
* GOSUB
*****************************************
* springt in eine unterroutine (gosub zeilennr)
* auch hier Struktur: (12 bytes lÑnge)
* gosub struktur:     0  zeilennr des gosubs
*                     4  adr der zeile
*                     8  adr hinter gosub-befehl
Gosub:
          move.w    #INT,typvalid
          bsr       get_term            * zeilennr holen
Gosub1:   move.l    fac1,d0
          bsr       poszeile            * auf zeile setzen -> a1 ptr
          cmp.l     4(a1),d0            * zeile auch wirklich vorhanden!
          bne       nolineerr           * nein, dann invalid operand
          move.l    goseptr,a2          * zeiger auf gosubstruktur
          cmp.l     #endgostabl-12,a2
          bhi       gosflow             * overflow error!
          move.l    akt_zeile,(a2)+     * struktur anlegen
		tst.w	b_modus
		bne		gosprg
		clr.l	akt_adr			* wenn direktm., dann markieren!
gosprg:		
          move.l    akt_adr,(a2)+
          move.l    a0,(a2)+
          move.l    a2,goseptr
          move.l    d0,akt_zeile
          lea       8(a1),a3
          move.l    a1,akt_adr
          move.l    a3,a0

		bra		contwithrun


*****************************************
* GOTO
*****************************************
* springt an die angebene zeile
Goto:
          addq.l    #4,sp               * Stack korrigieren
          bra       Run2
*****************************************
* RUN
*****************************************
* Startet programm (vorher CLR-Befehl [alle variablen lîschen]) m. o. ohne Zeile
Run:
          move.l    #-1,contline
		move.l	#-1,traceline
          bsr       Clr1                * alle Variablen lîschen
          bsr       restore             * data-zeiger
		bsr		get_procs			* alle proceduren erkennen!
          bsr       tstnxtarg           * testen, ob argument folgt (ja = BEQ)
          bne       run3
Run2:     move.w    #INT,typvalid
          bsr       get_term
Run1:     move.l    fac1,d0             * falls zeile angegeben, dann auch lesen
          bsr       poszeile
          cmp.l     4(a1),d0            * zeile vorhanden?
          beq       run3a
          bra       nolineerr
run3:     moveq.l   #0,d0               * default ist immer zeile 0
          bsr       poszeile            * auf zeile setzen  -> a1 zeiger
run3a:    move.w    #-1,b_modus         * -1 = programm-modus!
		move.l	4(a1),a2			* aktuelle zeile prÑzise setzen
          move.l    a2,akt_zeile		* "

		lea		stack,sp			* stack aufrÑumen!
run1:     tst.l     (a1)
          beq       run2a2              * ende des listings -> zurÅck
          move.l    a1,akt_adr          * adr. der akt. zeile
          lea       8(a1),a0            * auf adr im prg-speicher setzen
          clr.w     ifcnt               * if-zÑhler fÅr zeile init.
runcont:  bsr       exec_line           * zeile ausfÅhren lassen
          move.l    akt_adr,a1
          move.l    (a1),a1             * zeiger auf nÑchste zeile holen
		move.l	akt_zeile,a2		* kurz mal merken (wg run2-fehlern...)
          move.l    4(a1),akt_zeile     * in nÑchste zeile setzen
          bra       run1
run2a2:
		move.l	a2,akt_zeile		* letzte zeilennr noch merken!
run2:
		cmp.l	#fortable,foreptr	* alle fors geschlossen?
		bne		nonxterr
		cmp.l	#gostabl,goseptr	* alle gosubs zu?
		bne		noreterr
		cmp.l	#proctbl,proctblptr	* alle procs zu?
		bne		noeprcerr
		bra		basic1


*****************************************
* LOAD
*****************************************
tst_prgheader:
		lea		work1,a1
		moveq	#4,d0
		bsr		f_read
		move.l	work1,d0
		cmp.l	#HEADER,d0
		beq		tst_hok
		bsr		f_close
		bra		headerr
tst_hok:
		rts

Merge:
		move.w	#STRING,typvalid
		bsr		get_term
		move.l	a0,-(sp)
		bsr		f_open
		bsr		tst_prgheader
		lea		mergetext,a0
		bsr		put_string

		move.l	#-1,contline
		move.l	#-1,traceline
		bsr		Clr1
		bsr		restore

		clr.l	d1				* fileoffs 0
merge:
		lea		inputpuf,a1
		moveq.l	#4,d0
		bsr		f_read			* offs auf neue zeile lesen
		tst.l	d0
		beq		mergeend			* es folgt keine weitere zeile!
		move.l	(a1),d2

		move.l    d2,d0
		sub.l	d1,d0			* alten offs abziehen -> len of line!
		subq.l	#4,d0			* ptr ja schon gelesen
		lea		inputpuf,a1
		bsr		f_read			* zeile lesen
		move.l	(a1)+,d0			* zeilennummer
		move.l	a1,a0
		move.l	d2,-(sp)
		bsr		basic20			* einfÅgen
		move.l	(sp)+,d1			* neuer offs wird alter
		bra		merge
mergeend:				
		bsr		f_close		
		bsr		get_procs
		move.l	(sp)+,a0
		rts
		
* Wandelt ASCII-Datei in Basiczeilen
convfl:	.dc.w	0
Convert:
		move.w	#STRING,typvalid
		bsr		get_term
		bsr		f_open
		move.w	#1,convfl			* conv aktiv!
		lea		convtext,a0
		bsr		put_string
		bsr		New1
		bsr		Clr1
convnext:
		lea		inputpuf,a1
		move.l	a1,a0
convrepeat:
		moveq.l	#1,d0			* 1 byte
		move.l	a1,-(sp)
		bsr		f_read
		move.l	(sp)+,a1
		tst.l	d0
		beq		convend
		move.b	(a1),d0
		beq		convend
		cmp.b	#13,d0
		beq		convlend
		cmp.b	#10,d0
		beq		convrepeat
		cmp.b	#9,d0			* tab?
		bne		convnotab
		move.b	#' ',(a1)
convnotab:
		addq.l	#1,a1
		cmp.l	#inputepuf,a1
		beq		convovflerr
		bra		convrepeat
convlend:
		sub.l	a0,a1			* -> len
		move.l	a1,d0
		tst.l	d0
		beq		convnext			* leere zeile -> nichts machen!
		bsr		copy_inpuf
		bsr		konv_inpuf
		lea		input_puf,a0
		move.b	(a0),d0
		cmp.b	#'0',d0
		bmi		convnoerr
		cmp.b	#'9',d0
		bhi		convnoerr
		bsr		zeilenverwaltung
		bra		convnext
convend:
		bsr		f_close
		clr.w	convfl
		lea		input_puf,a0
		clr.l	(a0)
		bra		Loadend
		
* LÑdt prg relativ von disk
Load:
          move.w    #STRING,typvalid    * string ist filename
          bsr       get_term
          move.l    a0,-(sp)            * merken
          bsr       f_open              * str_ptr zeigt auf name, handle ist h.
		bsr		tst_prgheader
          lea       loadtext,a0
          bsr       put_string
		bsr		New1
          move.l    #$fffff,d0          * lÑnge ist uninteresant!
          bsr       f_read              * a1 zeigt auf puffer,handle, ->D0 lÑnge
          add.l     d0,prgend
          bsr       f_close
          bsr       new_link            * linken, so dass aus rel. fest wird
          move.l    (sp)+,a0
Loadend:
          move.l    #-1,contline        * kein cont erlaubt
		move.l	#-1,traceline
          bsr       Clr1
          bsr       restore             * vorher noch DATA, var. resetten
		bsr		get_procs
          tst.w     b_modus             * vom prg oder direktmodus?
          beq       loadend
		lea		stack,sp
          bra       run3
loadend:
          rts

*****************************************
* SAVE
*****************************************
* Speichert prg relativ auf disk
Save:
          move.w    #STRING,typvalid    * string ist filename
          bsr       get_term

		clr.l	d6
		move.l	#$7fffffff,d7
		bsr		tst_komma			* keine weiteren args?
		bne		save0
		move.l	d6,-(sp)
		move.w	#INT,typvalid		* wir brauchen INT
		bsr		get_term
		move.l	(sp)+,d6
		move.l	fac1,d7			* endzeile
		bsr		tst_komma
		bne		save0
		move.l	d7,-(sp)			* 1.arg war startzeile
		move.w	#INT,typvalid
		bsr		get_term
		move.l	(sp)+,d6
		move.l	fac1,d7

save0:
		bsr		tstlinenr
          move.l    a0,-(sp)            * merken
          bsr       f_create            * str_ptr zeigt auf name, handle ist h.
          lea       savetext,a0
          bsr       put_string
		lea		work1,a1			* und Basicprg-Header schreiben
		move.l	#HEADER,(a1)
		moveq.l	#4,d0
		bsr		f_write

save1:	* prgstart feststellen
		move.l	prgend,a2			* start der zu sichernden prg-zeilen
		move.l	prgbase,a0
save3b:
		move.l	(a0),d0			* prg-listing ende?
		beq		save3
		cmp.l	4(a0),d6			* zeile >= startzeile?
		bls		save3a			* ja, dann gefunden!
		move.l	d0,a0
		bra		save3b
save3a:
		move.l	a0,a2			* startzeile Åbernehmen
save3:	* prgende feststellen
		move.l	prgend,a3			* ende der zu sichernden prg-zeilen
		move.l	a2,a0			* a2:erste zeile
save4b:
		move.l	(a0),d0			* prg-listing ende?
		beq		save4
		cmp.l	4(a0),d7			* zeile > endzeile?
		blt		save4a			* ja, dann ende erreicht!
		move.l	d0,a0
		bra		save4b
save4a:
		move.l	a0,a3			* endzeile Åbernehmen
save4:	* jetzt erstmal abs->rel!
		move.l	a2,a4			* [start
		move.l	a3,a5			* ende]
		move.l	a2,d0			* decrementwert
save6:
		cmp.l	a4,a5			* ende erreicht?
		beq		save5
		move.l	(a4),d1
		move.l	d1,d2
		sub.l	d0,d1
		move.l	d1,(a4)
		move.l	d2,a4
		bra		save6
save5:	* und jetzt sichern
		move.l	a2,a1			* a1:pufferptr
		move.l	a3,d0
		sub.l	a2,d0
          bsr       f_write             * a1 zeigt auf puffer, d0 lÑnge, handle
          bsr       f_close
* jetzt wieder neu linken!
		move.l	a2,a4			* [start
		move.l	a3,a5			* ende]
		move.l	a2,d0			* incrementwert
save7:
		cmp.l	a4,a5			* ende erreicht?
		beq		save8
		move.l	(a4),d1
		add.l	d0,d1
		move.l	d1,(a4)
		move.l	d1,a4
		bra		save7
save8:
          move.l    (sp)+,a0
          rts

*****************************************
* LIST
*****************************************
scrline:	.ds.l	1
b_preup:
b_predown:
		movem.l	d0-a6,-(sp)
		moveq.l	#-1,d0
		move.l	d0,scrline
		tst.w	ed_mode			* 1=editormode->ok
		beq		nolinenr

		move.l	ed_scrline,a0
		bsr		charget
		cmp.b	#'0',d0
		blt		nolinenr
		cmp.b	#'9',d0
		bhi		nolinenr

		subq.l	#1,a0
		bsr		get_int
		move.l	d0,scrline
nolinenr:
		movem.l	(sp)+,d0-a6
		rts
		
b_up:
		tst.l	scrline
		bmi		b_scrend
		movem.l	d0-a6,-(sp)

		move.l	scrline,d0
		bsr		poszeile
		move.l	preline,d0		* zeile vor aktueller
		beq		nochange

		move.w	ed_x,-(sp)
		move.w	ed_xoffs,-(sp)
		clr.w	ed_x
		clr.w	ed_xoffs
		move.l	d0,a0			* zeilenadr
		move.l	4(a0),d6
		bra		listoneline

b_down:
		tst.l	scrline
		bmi		b_scrend
		movem.l	d0-a6,-(sp)
		move.w	ed_x,-(sp)
		move.w	ed_xoffs,-(sp)
		clr.w	ed_x
		clr.w	ed_xoffs
		move.l	scrline,d0
		addq.l	#1,d0
		bsr		poszeile

		move.l	a1,a0
		move.l	d0,d6

listoneline:
		move.l	#$7fffffff,d7
		moveq.l	#1,d0		
		bsr		listlines

		move.w	ed_xoffs,d0
		move.w	(sp)+,ed_xoffs
		move.w	(sp)+,ed_x
		cmp.w	ed_xoffs,d0
		beq		nochange
          jsr		ed_prline			* wenn Ñnderungen, dann neu ausgeben
nochange:
		movem.l	(sp)+,d0-a6
b_scrend:
		rts


* Delete-Befehl siehe list
Delete:
		bsr		getoptparam
		bsr		Clr1
		move.l	prgbase,a1
delLoop:
		tst.l     (a1)
          beq       delend
delloop:
          move.l    4(a1),d0            * zeilennr.
          cmp.l     d6,d0               * grîsser als min. angegeb. nummer?
          blt       del1				* nein, dann zur nÑchsten zeile
          cmp.l     d7,d0               * grîsser als erlaubter bereich?
          bhi       delend              * ja, dann sofort abbrechen
		movem.l	d6/d7/a0/a1,-(sp)
		bsr		delline2
		movem.l	(sp)+,d6/d7/a0/a1
		tst.l	(a1)
		bne		delloop
		beq		delend
del1:
		move.l	(a1),a1
		bra		delLoop
delend:
		rts


* List-Befehl list (n)(,)(n)
List:
		bsr		getoptparam
		move.l    a0,-(sp)            * retten
          move.l    prgbase,a0          * ab hier listing ausgeben
		clr.w	d0
		bsr		listlines			* eigentliche list routine
          bsr       new_line
          move.l    (sp)+,a0
          rts


tstlinenr:
		tst.l	d6
		bmi		negerr
		tst.l	d7
		bmi		negerr
		rts


* -> d6/d7 = [...] zeilennummern
getoptparam:
          move.l    #$7fffffff,fac1     * default            
          move.w    #INT,typvalid
          bsr       get_ckterm
          cmp.l     #$7fffffff,fac1     * kein 1. operand?
          bne       list1b
          bsr       tst_komma           * Chargot -> , -> start bei null
          bne       list1d
          clr.l     fac1
          bra       list1b
list1d:   moveq     #0,d6               * dann komplettes listing
          move.l    fac1,d7
          bra       list1c
list1b:   move.l    fac1,-(sp)
          move.l    #$7fffffff,fac1     * default = unendlich
          bsr       chargot             * testen, ob 2.operand vorhanden
          beq       list1e
          cmp.b     #':',d0             * bei 0-Kode oder : -> kein 2.
          beq       list1e
          move.w    #INT,typvalid
          bsr       get_ckterm
list1e:   move.l    (sp)+,d6            * startzeile
          cmp.l     #$7fffffff,fac1     * ist kein 2. element da gewesen?
          bne       list1a
          cmp.b     #',',-2(a0)         * 2xChargot -> , -> bis unendlich
          beq       list1a
          move.l    d6,fac1             * wenn nein, dann 1. Åbernehmen
list1a:   move.l    fac1,d7             * endzeile
list1c:
		bra		tstlinenr


* A0 auf 1. zeile
* d0 flag ob LIST(0) oder SCROLL(1)
* d6 ist [...
* d7 ist ...]
listfl:	.ds.w	1
listlines:
		move.w	#1,ed_nlfl		* keinen zeilenumbruch erlauben
		move.w	d0,listfl
list1:
		tst.l     (a0)
          beq       listend
          move.l    (a0)+,a6            * ptr auf next line retten
          move.l    (a0)+,d0            * zeilennr.
          cmp.l     d6,d0               * grîsser als min. angegeb. nummer?
          blt       list3a              * nein, dann zur nÑchsten zeile
          cmp.l     d7,d0               * grîsser als erlaubter bereich?
          bhi       listend             * ja, dann sofort abbrechen
          move.l    a0,-(sp)

          bsr       ipka_               * in asciikode (a2) wandeln
		tst.w	listfl
		bne		nonewline
          bsr       new_line            * neue zeile beginnen
nonewline:
          move.l    a2,a0
          subq.l    #1,a0               * vorzeichen Åbergehen
          bsr       putstrreverse       * zeilennr. ausgeben

          move.l    (sp)+,a1
          lea       var2_name,a0        * output puffer
list4:
          cmp.l     a1,a6               * ende der zeile erreicht?
          beq       list3
		moveq.l	#0,d0
          move.b    (a1)+,d0            * zeichen holen
          cmp.b     #TOKEN1,d0		* ist es tokenbeginn?
          beq       list2
		cmp.b	#TOKEN2,d0
		beq		list2
		cmp.b	#TOKEN3,d0
		beq		list2
          move.b    d0,(a0)+
          bra       list4
list2:    * tokenverarbeitung
		move.w	d0,d1
		lsl.w	#2,d1			* ist .l tabelle
          move.b    (a1)+,d0
          lsl.l     #2,d0
		lea		tokenadr,a2
          move.l    (a2,d1),a2		* token-name-start-tab holen
          move.l    0(a2,d0),a2
list2a:   move.b    (a2)+,d0            * kommando ausschreiben
		bclr		#7,d0			* kînnte gesetzt sein
		cmp.b	#'a',d0
		bmi		list2aa
		cmp.b	#'z'+1,d0
		bpl		list2aa
		sub.b	#$20,d0			* in grossbuchstaben wandeln
list2aa:
          move.b    d0,(a0)+
          tst.b     (a2)
          bne       list2a
          bra       list4
list3:    * zeile ausgeben und neue zeile anpos.
          clr.b     (a0)
          lea       var2_name,a0
          bsr       put_string
list3a:   move.l    a6,a0
		tst.w	listfl
		bne		listend
          bra       list1
listend:
		clr.w	ed_nlfl			* zeilenumbruch gestattet
		rts

*****************************************
* DIM
*****************************************
* Dim-Befehl
* erwartet Zeiger hinter Token in a0
dimtypext:	.ds.w	1
dimcmpfl:		.ds.w	1
dimcmpadr:	.ds.l	1

Dim:
		clr.w	dimtypext
		bra		DimA
Localdim:
		move.w	procnr,dimtypext

DimA:
		clr.w	dimcmpfl
          bsr       tst_var             * testet auf Variable und holt ggf adr.
          bsr       tstsysvar
          move.w    typflag,-(sp)        
		tst.w	dimtypext
		beq		hauptdim
		tst.w	d0				* local dim der var schon mal?
		bpl		ldimok
		addq.w	#1,dimcmpfl
		move.l	a1,dimcmpadr		* zeiger auf array-header merken!
		bra		ldimok
hauptdim:
          tst.w     d0
          bne       redef               * variable schon def. -> fehler
ldimok:
          bsr       save_vname          * variablenname sichern
          lea       arraylen,a4
          clr.l     arraydeep
          bra       dim1a
dim1:
          bsr       chk_komma
dim1a:    addq.l    #1,arraydeep
          move.l    a4,-(sp)
          bsr       get_aterm
          move.l    (sp)+,a4
          cmp.l     #11,arraydeep
          beq       dimerr              * schon zuviele felder?
          move.l    fac1,d0             * tiefe der dim setzen
		bmi		negdimerr
		move.l	d0,(a4)+
          bsr       chargot
          cmp.b     #')',d0             * Dim Zuweisung vollendet?
          bne.s     dim1

		tst.w	dimcmpfl			* local dim var redefined gewesen?
		beq		nolocredef
		move.l	dimcmpadr,a5		* zu vergl. array header!
		move.l	arraydeep,d0
		cmp.l	(a5)+,d0			* stimmt anzahl dimensions?
		bne		redef			* nein, fehler
		lea		arraylen,a4
tstlocredef:
		move.l	(a4)+,d1
		addq.l	#1,d1			* um 1 erhîhen (wie im varspeicher)
		cmp.l	(a5)+,d1
		bne		redef			* nicht gleich->err
		subq.l	#1,d0
		bne		tstlocredef

nolocredef:
          bsr       load_vname
          move.w    (sp)+,d0
		or.w		dimtypext,d0		* 0 bzw vbei local dim procnr
		move.w	d0,typvalid
          bsr       create_var
          bsr       charget
          cmp.b     #',',d0
          beq       DimA 
          rts

*****************************************
* PRINT
*****************************************
* erwartet Zeiger hinter Token in a0
Print:
          bsr       clrfilefl           * default: kein print #
          move.l    a0,work2
          bsr       charget
          cmp.b     #'#',d0             * print #filehandle?
          bne       Print1
          bsr       get_handle          * holt log.handle
          move.w    #-1,filefl
          bsr       chk_komma
          bra       Print1a
Print1:   move.l    work2,a0
Print1a:  move.l    a0,work2
          bsr       charget
          cmp.b     #TOKEN1,d0		* init-byte fÅr funktion?
          bne       Print1aa
          lsl.w     #8,d0
          move.b    (a0),d0
          cmp.w     #TAB,d0             * tab-funktion?
          bne       Print1ab
Printfkt: subq.l    #1,a0
          bsr       get_fkt             * tab/spc ausfÅhren
          bsr       charget
          bra       print2
Print1ab: cmp.w     #SPC,d0             * spc-funktion?
          beq       Printfkt
		cmp.w	#EDTAB,d0			* edtab
		beq		Printfkt

Print1aa: move.l    work2,a0
          move.w    #STRING,typvalid    * string,float und int sind erlaubt
          bsr       gets_term           * wertet beliebigen Ausdruck aus
          move.l    a0,a6               * Zeiger auf Basiczeile erhalten
          move.w    typ2flag,d0         * Art des Ausdrucks
          beq       print2              * kein Ausdruck gefunden?
          cmp.w     #FLOAT,d0           * float?
          beq       printfl
          cmp.w     #INT,d0
          beq       printint
printstr:
          move.l    str_ptr,a0          * zeigt auf auszugebenden String
          bra       print1
printint:
          move.l    fac1,d0
          bsr       ipka_               * gibt ptr auf string in a2 zurÅck
          bra       print1a
printfl:
          movem.l   fac1,d0-d3
          bsr       rpka_
print1a:  move.b    #' ',1(a2)          * bei Zahlen noch ein leerzeichen davor
          addq.l    #1,a2
          move.l    a2,a0
print1:
          bsr       putstrreverse

          move.l    a6,a0
print2:   bsr       tst_komma           * letztes Zeichen holen zum Checken!
          bne       print2a
          bsr       tab_                * zum nÑchsten TAB
          bra       Print2              * und das nÑchste Statement ausfÅhren
print2a:
          cmp.b     #';',d0			* auf screen/file zu einem arg verschmelzen
          beq       Print2
print2b:  bsr       new_line
printend: bra       clrfilefl
Print2:   bsr       tstnxtarg           * schauen, ob ein weiteres arg da ist
          beq       Print1a
          bsr       clrfilefl
          bra       charget             * zeiger auf : oder 0 richten

********************************************************************************
* Holt einen beliebigen Term (Numerisch, String) und setzt dafÅr Typflag
* in typvalid steht der End-Typ -> endergebnis wird nach typvalid gewandlelt
* A0 zeigt auf Term, A2 zeigt auf mgl. Zuweisungsstringname, ansonsten auf 0
* -> falls String str_ptr auf Start des Strings
*                 strend  auf Ende des String (0)
* -> falls float  fac1 enthÑlt Wert
* -> falls int    fac1 enthÑlt Wert (int-format)
get_aterm:     * get array term (save important vars)
          move.w    arrayfl,-(sp)
          movem.l   arraylen,d0-d7/a5-a6     * arraydaten sichern im stack!
          movem.l   d0-d7/a5-a6,-(sp)
          move.l    arraydeep,-(sp)
          move.l    str_ptr,spstr
          bsr       onqlist
          move.w    #INT,typvalid       * wir brauchen int in fac1
          bsr       get_term            * variablezuweisung einlesen
          bsr       offqlist
          move.l    spstr,str_ptr
          move.l    (sp)+,arraydeep
          movem.l   (sp)+,d0-d7/a5-a6
          movem.l   d0-d7/a5-a6,arraylen
          move.w    (sp)+,arrayfl
          rts
*****************************************
* gets_term sichert zudem noch den zeiger auf den stringpuf start
gets_term:
          move.l    strend,spstr        * strings dÅrfen nicht angelegt werden
          bsr       onqlist
          bsr       get1_term           * wertet beliebigen Ausdruck aus
          bsr       offqlist
          move.l    spstr,strend
          rts
*****************************************
* ÅberprÅft vorher, ob wert nur durch , ,0 , : ersetzt wurde
ckt2:     rts
get_ckterm:
          bsr       charget
          beq       ckt2           * 0Kode
          cmp.b     #',',d0
          beq       ckt2           * Komma
          cmp.b     #':',d0
          beq       ckt2           * :
          lea       -1(a0),a0
          bra       get_term
*****************************************
* -> float:fac1, int:fac, str->str_ptr
get_defterm:        * string wichtig zu definitionen
          bsr       get1_term
          bra       get_1
*****************************************
get_term:
          move.l    strend,spstr
          bsr       onqlist
          bsr       get1_term           * Termausdruck holen
          bsr       offqlist
          move.l    spstr,strend        * angelegte strings unwichtig
get_1:    move.w    typ2flag,d0
          beq       get_t2              * kein Ausdruck gefunden?
          move.w    typvalid,d1         * Art des Ausdrucks
          cmp.w     d0,d1
          beq       get_t1              * ausdrÅcke gleich -> fertig
          cmp.w     #FLOAT,d1           * float?
          beq       konvfl
          cmp.w     #INT,d1
          beq       konvint
konvstr:
          cmp.w     #STRING,d0          * float und int kînnen hier nicht gew.
          bne       typemis
          beq       get_t1

konvint:
          cmp.w     #FLOAT,d0
          bne       typemis             * int nur int und float
          movem.l   fac1,d0-d3
          bsr       rpkl
          move.l    d0,fac1
          bra       get_t1

konvfl:
          cmp.w     #INT,d0
          bne       typemis             * strings kînnen keine floats werden
          move.l    fac1,d4
          bsr       ltor_
          movem.l   d0-d3,fac1
get_t1:   move.w    typvalid,typ2flag
get_t2:   rts

*****************************************
* holt term -> typ2flag enthÑlt typ des rÅckgabewertes
get1_term:
          clr.w     typ2flag            * Lîschen
          clr.w     typflag
          clr.l     work1
          movem.l   zero_,d0-d3
          movem.l   d0-d3,fac1          * init.
get3_term:
          bsr       get_element         * Element holen
          beq       gtend               * kein Ausdruck!
          move.w    typflag,d7          * falls numerisch Ausdr. nach FAC_I
          move.w    d7,typ2flag
          cmp.w     #STRING,d7
          beq.s     no_numeric
          movem.l   d0-d3,fac1          * float/int nach fac_I
no_numeric:
          bsr       get_operator        * Operator holen -> D0
          beq       gtend               * kein Operator -> Abbruch
          move.w    d0,operator         * Operator merken
          cmp.w     #STRING,typflag
          bne       get2_term
          clr.l     work1               * init.
          tst.b     follchar            * wenn gesetzt, dann war =,<,>
          beq       gt6
          move.l    strend,work1        * merken fÅr spÑter
          bra       get2_term
gt6:      bsr       chargot             * ist es nicht +, dann aufhîren
          cmp.b     #'+',d0
          beq       get2_term
          subq.l    #1,a0
          bra       gtend
get2_term:
          move.l    work1,spstr
          bsr       onqlist
          move.w    follchar,-(sp)      * merken, da sonst zerstîrt
          move.w    operator,-(sp)
          move.w    typ2flag,-(sp)
          bsr       get_element         * Element holen
          beq       syntaxerr           * kein Element nach Operator->Fehler!
          move.w    (sp)+,typ2flag
          move.w    (sp)+,operator
          move.w    (sp)+,follchar
          bsr       offqlist
          move.l    spstr,work1
          move.w    typflag,d7          * falls numerisch Ausdr. nach FAC_I
          cmp.w     #STRING,d7          * String?
          bne       gt5                 * dann wurde schon addiert!
* string-verarbeitung!
          move.w    typ2flag,d6
          move.w    d7,typ2flag
          cmp.w     d6,d7               * z.b. a$<b$+5 -> mismatch
          bne       typemis
          tst.l     work1               * wenn gesetzt, dann vergleich
          beq       no_numeric
          move.w    follchar,-(sp)      * merken
          move.l    work1,spstr         * merken
          bsr       onqlist
          move.w    operator,-(sp)
          bsr       no_numeric          * zweiten stringkomplex holen
          move.w    (sp)+,operator
          bsr       offqlist
          move.l    spstr,work1
          move.w    (sp)+,follchar
          tst.w     workop
          bne       gt5d
          subq.l    #1,a0
gt5d:     cmp.w     #STRING,typvalid
          bne       gt5a
          move.w    #INT,d7
          bra       gt5b
gt5a:     move.w    typvalid,d7
gt5b:     move.w    d7,typ3flag         * wird nach str-vgl in typ2flag kopiert
          bsr       exec_operation      * string-vgl ausfÅhren
          movem.l   d0-d3,-(sp)
          move.l    a0,a6
          bsr       get_operator
          bne       gt5e  
          movem.l   (sp)+,d0-d3
          movem.l   d0-d3,fac1
          bra       gtend2
gt5e:     move.w    d0,-(sp)
          move.w    typvalid,-(sp)
          move.w    typ2flag,typvalid
          bsr       get_term            * nÑchstes element holen
          move.w    typ2flag,d0
          cmp.w     typvalid,d0         * achten, dass mindesten 1 elem. da war
          bne       typemis
          move.w    (sp)+,typvalid
          move.w    (sp)+,operator
          movem.l   (sp)+,d0-d3         * altes in fac2, neues in fac1
          movem.l   d0-d3,fac2
          bsr       exec_operation
          movem.l   d0-d3,fac1
          bra       gtend2
* int/float-verarbeitung
gt5:
		cmp.w	#STRING,typ2flag	* string und int/float passen nicht!
		beq		typemis
		movem.l	d0-d3,fac2		* wert sichern
          move.l    a0,a6               * Adresse merken
          move.w    follchar,-(sp)      * zeichen hinter mgl. vgl merken
          bsr       get_operator
          beq       gt4                 * ')' bzw. Ende der Zeile Oper. ausf.
          cmp.w     operator,d0         * PrioritÑten vergleichen
          bhi       to_next_op          * alte verknÅpfung hîher, dann ausf.
gt4:      move.l    a6,a0
          move.w    (sp)+,follchar
gt7:
		move.w	typflag,d7		* neue(2.)
          cmp.w     #FLOAT,d7           * 2.Float?
          beq       gt2
* integer:
          cmp.w     typ2flag,d7
          beq       no2_numeric         * 1. und 2. operand sind int
          move.l    fac2,d4			* 1. float/2.int -> 2. in float
          bsr       ltor_
          movem.l   d0-d3,fac2
          bra       no2a
gt2:
          cmp.w     typ2flag,d7
          beq       no2_numeric         * 1. und 2. operand sind float
          move.l    fac1,d4             * 1. operand ist integer
          bsr       ltor_               * in float wandeln
          movem.l   d0-d3,fac1
no2a:     move.w    #FLOAT,d7
no2_numeric:
		move.w	d7,typflag
		move.w	d7,typ2flag
		bsr       exec_operation      * Operation wie gewîhnlich ausfÅhren
          bra       no_numeric


* NÑchste VerknÅpfung hat hîhere PrioritÑt, dann anders arbeiten...
to_next_op:
		move.w	typ2flag,-(sp)		* alten typ merken
          movem.l   fac1,d1-d4
          movem.l   d1-d4,-(sp)         * 1. Element auf Stack
          move.w    operator,-(sp)      * Operator merken
          movem.l   fac2,d1-d4
          movem.l   d1-d4,fac1          * 2. Element ist jetzt 1.
          move.w    d0,operator         * nÑchster Operator ist jetziger
		move.w	typflag,typ2flag	* neuer typ ist jetzt alter
          bsr       get2_term           * und weiterarbeiten
          movem.l   fac1,d1-d4
          movem.l   d1-d4,fac2
          move.w    (sp)+,operator
          movem.l   (sp)+,d1-d4
          movem.l   d1-d4,fac1
		move.w	(sp)+,typ2flag
          move.w    (sp)+,follchar
          subq.l    #1,a0
          bra       gt7

exec_operation:
          move.w    operator,d0
          sub.w     #1,d0
          lsl.w     #2,d0               * Als Offset fÅr Langworte
          lea       optabl,a1
          move.l    0(a1,d0),a1
          movem.l   a0-a6,-(sp)         * Alle wichtigen register sichern
          cmp.w     #FLOAT,typ2flag     * testen fÅr operation ob float-oper.
          movem.l   fac1,d0-d3
          movem.l   fac2,d4-d7
          jsr       (a1)                * VerknÅpfungsroutine anspringen
          movem.l   (sp)+,a0-a6         * register wieder holen
          movem.l   d0-d3,fac1          * Int/Float zuruÅckschreiben
          rts
gtend:    movem.l   fac1,d0-d3          * nach ')' wird wert in d0-d3 erwartet
gtend2:   rts

*****************************************
* Holt ein Element (Bei Klammern rekursives Verfahren!)
get_element:
          bsr       charget             * Zeichen holen
          beq       ge2
          cmp.b     #':',d0             * abruchsbedingungen
          beq       ge2
          cmp.b     #',',d0
          beq       ge2
          cmp.b     #';',d0
          beq       ge2
          cmp.b     #'(',d0             * Klammer kenzeichnet neues Subargum.
          bne       ge1
get_klammerarg
          movem.l   fac1,d0-d3          * fac1 sichern
          movem.l   d0-d3,-(sp)
          move.w    operator,-(sp)
          bsr       get3_term           * Termholenroutine rek. anspringen
          move.w    d0,d7
          bsr       chk_klammer
          move.w    d7,d0
          move.w    (sp)+,operator
          movem.l   (sp)+,d4-d7
          movem.l   d4-d7,fac1          * fac1 wieder holen
          moveq     #1,d7               * BEQ lîschen
          rts
ge1:
          move.w    typflag,d7          * Typflag merken
          bsr       get_var_konst       * Variable/Konstante holen
          cmp.w     #STRING,typflag     * Typflag
          beq       get_str
ge2:      rts
*****************************************
* Holt String (Pointer auf Var in A1, Zeiger A2) und fÅgt bzw. legt String an.
get_str:
          move.b    -(a2),d1            * ggf. bei StrKonst auf " achten
          clr.b     (a2)
          move.w    typflag,d7
          cmp.w     typ2flag,d7         * schon Typ vorher da?
          beq       gs1                 * ja, dann nur hineinkopieren
          bsr       resv_str
          bra       gs2
gs1:      bsr       copy_str
gs2:      move.b    d1,(a2)+
          moveq     #1,d1               * BNE -> Term gefunden!
          rts

resv_str:
          move.l    strend,str_ptr      * Zeiger auf leeren Stringspeicher
          bset      #0,d7               * flag
          bra       copy2_str

copy_str:
          bclr      #0,d7
copy2_str:
          cmp.b     #$22,d1             * anfhrungszeichen->stringkonstante
          bne       warstring

          move.l    a1,a4
ll5:
          tst.b     (a4)+
          bne       ll5
          sub.l     a1,a4
          bra       ll6

warstring:
          move.l    a1,a4
          addq.l    #1,a4
cstr1:
          tst.b     -(a4)
          bne       cstr1
          sub.l     a1,a4
          move.l    a4,d0
          neg.l     d0
          addq.l    #1,d0
          move.l    d0,a4

ll6:
          btst      #0,d7               * folgende abfrage nicht bei resv_str
          bne       cstrcont
          cmp.l     #1,a4               * war neuer string leer?
          beq       nocstr              * ja, dann nicht kopieren!
cstrcont: move.l    strend,a3
		add.l	#32,a4
          sub.l     a4,a3               * wahrscheinl. spÑtere Lage des 0-Kodes
          cmp.l     varend,a3
          bpl       cstr3
          move.l    strend,pgarbend     * kompletten strspeicher
          bsr       garbage			* d0-d7 wird gemerkt,a0-a6 ggf angegl...
		move.l	strend,a3
		sub.l	a4,a3
		cmp.l	varend,a3
		bpl		cstr3
		move.b	d1,(a2)			* vorher gemerkten wert ins prg zurÅck!!
		bra		outstrspc

cstr3:
          move.l    strend,a3
          cmp.b     #$22,d1             * string oder konst?
          beq       warkonst

          addq.l    #1,a1
          addq.l    #1,a3
          btst      #0,d7
          bne       ll7
          addq.l    #1,a3
ll7:
          move.b    -(a1),-(a3)
          bne       ll7
          bra       ll8

warkonst:
          addq.l    #1,a3
          btst      #0,d7
          bne       cstr2
          addq.l    #1,a3               * $0 vom letzten str Åberschreiben
cstr2:
          move.b    (a1)+,-(a3)
          bne       cstr2

ll8:
          subq.l    #1,a3
          move.l    a3,strend           * Zeiger setzen
nocstr:   rts

*****************************************
* Holt eine Variable/Konstante
savea0:	.ds.l	1
get_var_konst:
          move.b    -(a0),d0            * Chargot
		move.l	a0,savea0
		cmp.b	#'-',d0			* muss zahl negiert werden?
		bne		vkpos
		move.w	#1,-(sp)			* zahl ist negativ!
		addq.l	#1,a0
		bsr		charget
		subq.l	#1,a0
		bra		getv0
vkpos:
		clr.w	-(sp)

getv0:
          cmp.b     #TOKEN1,d0 		* 1. byte eines funktionstokens?
		beq		getv0a
		cmp.b	#TOKEN2,d0
		beq		getv0a
		cmp.b	#TOKEN3,d0
		bne		getv1
getv0a:
          bsr       get_fkt
		bra		getvtstneg
getv1:
          cmp.b     #$22,d0             * " -> Stringkonstante
		bne		getv2
          bsr       get_strkonst
		bra		getvtstneg
getv2:
          cmp.b     #'$',d0             * ist hexzahl?
		bne		getv3
          bsr       get_hexvar
		bra		getvtstneg
getv3:
          cmp.b     #'%',d0             * ist binÑrzahl?
		bne		getv4
          bsr       get_binvar
		bra		getvtstneg
getv4:
          bsr		isvarname           * Ist Variable?
          bne       getv5
		bsr		get_var
 		bra		getvtstneg
getv5:
		cmp.b	#'(',d0			* klammerarg?
		beq		getv7
		move.l	savea0,a0			* hier wird ja automatisch negiert!
		addq.l	#2,sp			* flag von sp
		bra		no_var
getv7:
		addq.l	#1,a0			* klammer Åbergehen
		bsr		get_klammerarg
*		bra		getvtstneg
getvtstneg:
		tst.w	(sp)+
		beq		getvend
		cmp.w	#INT,typflag
		bne		tstnegfloat
		neg.l	d0
		rts
tstnegfloat:
		cmp.w	#FLOAT,typflag
		bne		getvend
		movem.l	d4-a6,-(sp)
		move.l	d0,d4
		move.l	d1,d5
		move.l	d2,d6
		move.l	d3,d7
		movem.l	zero_,d0-d3
		bsr		rsub_			* neg: 0-x
		movem.l	(sp)+,d4-a6
getvend:
		rts


* keine Stringkonst, keine Variable -> Nummerische Eingabe
no_var:
          bsr       rlda_     * D0-d3 ist float (extended), a0 auf hinter zahl
* in rlda_ typflag is set to float, if radix is found or number is to big
          subq.l    #1,a0     * auf nÑchstes Zeichen im Puffer positionieren
          cmp.w     #FLOAT,typflag
          beq       novarend
          cmp.w     #FLOAT,typ2flag     * wird sowieso float benîtigt?
          bne       intoint
intofl:
          move.w    #FLOAT,typflag
          rts
intoint:
          cmp.w     #$4001,d0           * ist bereich fÅr int zulÑssig?
          blt       intofl
          cmp.w     #$4009,d0
          bhi       intofl              * kleiner e0 und grîsser e8 -> float!
          bsr       rpkl
          move.w    #INT,typflag
novarend:
          rts
*****************************************
* holt eine Variable
* a0 zeigt auf erstes zeichen des namens
get_var:
          bsr       tst_var             * testet auf Variable und holt ggf adr.
          tst.w     d0
          bne       get_v1              * ja, schon definiert
		move.w	typvalid,-(sp)		* typvalid sicherheitshalber mal merken
		move.w	typflag,typvalid
          bsr       create2_var
		move.w	(sp)+,typvalid
get_v1:
          tst.b     arrayfl
          beq       get_v3
          movem.l   fac1,d1-d4          * fac1 zwecks mgl. rekursion retten
          movem.l   d1-d4,-(sp)
          bsr       posarray            * holt argument und positioniert (->a1)
          movem.l   (sp)+,d1-d4
          movem.l   d1-d4,fac1
          move.w    d0,d7
          bsr       chk_klammer
          move.w    d7,d0
get_v3:
          bsr       read_var
          lea       zero_+4,a2          * dummywert, da 0-kode bereits da!
          rts

*****************************************
* Holt eine Stringkonstante
* -> A2 zeigt auf Ende ("), A1 auf erstes Zeichen
get_strkonst:
          move.w    #STRING,typflag
          addq.l    #1,a0               * auf Ascii-Zeichen statt auf "
          move.l    a0,a1
getsk1:
          move.b    (a0)+,d0
          beq       getskend
          cmp.b     #$22,d0
          bne       getsk1
getskend:
          move.l    a0,a2
          rts
*****************************************
* holt eine hexzahl (z.B. $fffabfd) -> d0.l
get_hexvar:
          moveq     #0,d1
          addq.l    #1,a0
ghex3:    move.b    (a0)+,d0            * ziffer holen
		or.b		#$20,d0			* a-z/A-Z
          cmp.b     #'0',d0
          blt       ghexend
          cmp.b     #'f',d0
          bhi       ghexend             * keine richte zahl mehr...
          cmp.b     #'a',d0
          blt       ghex2
          sub.b     #'a'-10,d0
          bra       ghex1
ghex2:    cmp.b     #'9',d0
          bhi       ghexend             * keine hexzahl
          sub.b     #'0',d0
ghex1:    lsl.l     #4,d1
          bcs       SOVER_              * zu grosse zahl!
          or.b      d0,d1
          bra       ghex3
ghexend:  move.w    #INT,typflag
          move.l    d1,d0
          subq.l    #1,a0
          rts
*****************************************
* holt binaerzahl
get_binvar:
          moveq     #0,d1
          addq.l    #1,a0
gbin1:    move.b    (a0)+,d0
          cmp.b     #'1',d0
          bhi       ghexend
          cmp.b     #'0',d0
          blt       ghexend
          sub.b     #'0',d0
          lsl.l     #1,d1
          bcs       SOVER_
          or.b      d0,d1
          bra       gbin1

*****************************************
* fÅhrt eine Funktion aus
* -> typflag wird und muss von funktion gesetzt werden
* -> d0-d3 enthÑlt wert, bei string a2 aufs ende und a1 auf anfang
get_fkt:
		moveq	#0,d0
		move.b	(a0)+,d0			* tokenintro 1,2,3
		lsl.w	#2,d0
		lea		comadr,a1
		move.l	(a1,d0),a1
		
          move.b    (a0)+,d0            * Lowbyte
          lsl.w     #2,d0
          move.l    (a1,d0),d7		* A0 muss von befehl mitgezogen werden
          btst      #31,d7              * wenn gesetzt, dann funktion
		bne		onlyfkt
		btst		#28,d7			* wenn gesetzt, dann fkt/com
		beq		nofkterr
		move.w	#1,cmdfktfl		* aufruf als fkt
onlyfkt:
          btst      #27,d7              * funktion, aber ohne (-Check?
          bne       gfkt1
          bsr       charget
          cmp.b     #'(',d0             * funktion beginnt auf jedenfall mit (
          bne       syntaxerr
gfkt1:    move.w    typvalid,-(sp)
          move.w    typ2flag,-(sp)
          movem.l   fac1,d0-d3          * fac1 sichern
          movem.l   d0-d3,-(sp)
          movem.l   fac2,d0-d3          * fac2 sichern
          movem.l   d0-d3,-(sp)
          move.w    operator,-(sp)
          move.l    strend,spstr
          bsr       onqlist
          move.l    str_ptr,spstr
          bsr       onqlist
          move.l    d7,-(sp)
          and.l     #$00ffffff,d7
          move.l    d7,a2
          jsr       (a2)                * funktion anspr (typflag wird gesetzt!
          move.l    (sp)+,d7
          btst      #27,d7              * ohne )-Check?
          bne       gfkt2
          move.w    d0,d7
          bsr       chk_klammer
          move.w    d7,d0
gfkt2:    bsr       offqlist
          move.l    spstr,str_ptr
          bsr       offqlist
          move.l    spstr,strend
          move.w    (sp)+,operator
          movem.l   (sp)+,d4-d7
          movem.l   d4-d7,fac2          * fac2 wieder holen
          movem.l   (sp)+,d4-d7
          movem.l   d4-d7,fac1          * fac1 wieder holen
          move.w    (sp)+,typ2flag
          move.w    (sp)+,typvalid
          rts

*****************************************
* holt einen Basicoperator + -...
* -> BEQ bei Zeilenende,Vgl,')'
* Zeichen auf jedenfall in D0.w (schon in PrioritÑtsstufe gewandelt)
get_operator:
		moveq.l	#0,d0
          clr.w     follchar            * init.
          clr.w     workop
          bsr       charget             * Zeichen holen
		beq		koend2			* zeilenende
		cmp.b	#TOKEN1,d0		* tokenintro?
		bne		ko0

		lsl.w	#8,d0
		bsr		charget
		cmp.w	#AND,d0
		beq		ko_and
		cmp.w	#OR,d0
		beq		ko_or
		cmp.w	#EOR,d0
		beq		ko_eor
		subq.l	#2,a0			* falsches token -> wieder zurÅck!
		clr.w	d0				* zerofl = 1
		bra		koend2
ko_eor:
		moveq.l	#2,d1			* eintrags#
		bra		kofound
ko_or:
		moveq.l	#4,d1
		bra		kofound
ko_and:
		moveq.l	#3,d1
		bra		kofound
		
ko0:
          lea       optoktabl,a5
          clr.w     d1
ko1:
          cmp.b     (a5,d1),d0          * Operator mit Tabelle vgl.
          beq       kofound
          addq.w    #1,d1
          cmp.w     #anzops,d1          * Anzahl der vorhandenen Operatoren!
          bne       ko1                 * fehler!
          bra       koend2
kofound:
		moveq.l	#0,d0
          lea       oppriotabl,a5       * PrioritÑtstabelle
          move.b    (a5,d1),d0
          cmp.b     #6,d0               * ist prior. 6-8, dann vgl.operator
          blt       koend
          cmp.b     #8,d0
          bhi       koend
          move.b    (a0),follchar       * dieses next vgl-operator merken
          move.b    (a0),d2             * testen, ob next char Åberspr. soll
          cmp.b     #'<',d2
          beq       koend1
          cmp.b     #'>',d2
          beq       koend1
          cmp.b     #'=',d2
          bne       koend
koend1:   addq.l    #1,a0               * zweites vgl.zeichen Åbergehen
koend:    move.w    d0,workop
koend2:   rts

*****************************************
* Vergleich-routinen
Lower:
          cmp.b     #'=',follchar       * <=?
          beq       lowerequ
          cmp.b     #'<',follchar
          beq       syntaxerr
          cmp.b     #'>',follchar
          beq       unequal
          bsr       facscmp             * beide vars miteinander vgl.
          bmi       cmptrue
          bra       cmpfalse
lowerequ:
          bsr       facscmp
          bmi       cmptrue
          beq       cmptrue
          bra       cmpfalse
unequal:
          bsr       facscmp
          bne       cmptrue
          bra       cmpfalse
*****************************************
Higher:
          cmp.b     #'<',follchar
          beq       unequal
          cmp.b     #'=',follchar       * >=?
          beq       higherequ
          cmp.b     #'>',follchar
          beq       syntaxerr
          bsr       facscmp             * beide vars miteinander vgl.
          beq       cmpfalse
          bpl       cmptrue
          bra       cmpfalse
higherequ:
          bsr       facscmp
          bpl       cmptrue
          bra       cmpfalse
*****************************************
Equal:
          cmp.b     #'<',follchar
          beq       lowerequ
          cmp.b     #'>',follchar
          beq       higherequ
          cmp.b     #'=',follchar
          beq       syntaxerr
          bsr       facscmp
          bne       cmpfalse
cmptrue:
          cmp.w     #FLOAT,typ2flag
          beq       cmptr1
          moveq.l   #1,d0
          rts
cmptr1:   move.l    #$00004001,d0
          move.l    #$00010000,d1
          moveq.l   #0,d2
          moveq.l   #0,d3
          rts
cmpfalse:
          movem.l   zero_,d0-d3
          rts


****************************************
* Shiftleft
ShL:
          bsr       convint
          move.l    fac1,d0
		move.l	fac2,d1
          lsl.l     d1,d0
          bra       reconvint

****************************************
* Shiftright
ShR:
          bsr       convint
          move.l    fac1,d0
		move.l	fac2,d1
          lsr.l     d1,d0
          bra       reconvint

****************************************
* Xor-VerknÅpfung
Xor:
          bsr       convint
          move.l    fac1,d0
		move.l	fac2,d1
          eor.l     d1,d0
          bra       reconvint

****************************************
* And-VerknÅpfung
And:
          bsr       convint
          move.l    fac1,d0
          and.l     fac2,d0
          bra       reconvint

****************************************
* Or-VerknÅpfung
Or:
          bsr       convint
          move.l    fac1,d0
          or.l      fac2,d0
          bra       reconvint

* wandelt fac1,fac2 wider zurÅck
reconvint:
          cmp.w     #FLOAT,typ2flag
          beq       reconv1
          rts
reconv1:  move.l    d0,d4
          bra       ltor_


* diese routine wandelt fac1,fac2 unbedingt in int
convint:  cmp.w     #FLOAT,typ2flag
          beq       convfloat
          cmp.w     #STRING,typ2flag    * bei string fehler!
          beq       typemis
          rts
convfloat:movem.l   fac1,d0-d3
          bsr       rpkl
          move.l    d0,fac1
          movem.l   fac2,d0-d3
          bsr       rpkl
          move.l    d0,fac2
          rts

*****************************************
* Addition Fl+Fl/ int+int
* BEQ bedeutet float-addition
* d0-d3 = fac1+fac2/  d0-d1 = fac1+fac2
Add:
          beq       radd_
          add.l     d4,d0
          bvs       SOVER_              * overflow-error
          rts
*****************************************
* Subtraktion Fl-Fl/ int-int
* BEQ bedeutet float-subtraction
* d0-d3 = fac1-fac2/  d0-d1 = fac1-fac2
Sub:
          beq       rsub_
          sub.l     d4,d0
          bvs       SOVER_              * overflow-error
          rts

*****************************************
* x^y fl:fl/int:int
sgnfl:	.ds.w	1
Exponent:
          beq       exponent
		move.l	d4,d5
		move.l	d0,d4
		bsr		lateconv

exponent:
		lea		zero_,a1
		cmp.l	(a1)+,d0
		bne		expon0
		cmp.l	(a1)+,d1
		bne		expon0
		cmp.l	(a1)+,d2
		bne		expon0
		cmp.l	(a1),d3
		beq		expon3
expon0:
		clr.w	sgnfl
		btst		#31,d0			* pos/neg?		
		beq		expon1
		not.w	sgnfl
		bclr		#31,d0
expon1:
		movem.l	d4-d7,-(sp)		* y (fÅr spÑter) merken
		movem.l	d0-d3,-(sp)		* x merken
		move.l	d4,d0
		move.l	d5,d1
		move.l	d6,d2
		move.l	d7,d3
		bsr		rpkl				* y in int wandeln
		btst		#0,d0			* gerade?
		bne		expon2
		clr.w	sgnfl
expon2:
		movem.l	(sp)+,d0-d3
		
          bsr       rlog10_
          move.l    d0,d4
          move.l    d1,d5
          move.l    d2,d6
          move.l    d3,d7
          movem.l   (sp)+,d0-d3		* y von stack
          bsr       rmul_
          bsr       rexp10_

		tst.w	sgnfl
		beq		expon3
		bset		#31,d0
expon3:
		rts

*****************************************
* Division Fl:Fl/ int+int
* BEQ bedeutet float-division
* d0-d3 = fac1:fac2/  d0-d1 = fac1:fac2
Div:
		beq		rdiv_			* float...
		movem.l	d0/d4,-(sp)		* fac1,2 merken
		bsr		idiv				* int divide...
		movem.l	(sp)+,d4/d5
		tst.l	d0
		bne		divnozero
		bsr		lateconv
		bra		rdiv_
divnozero:
		rts

lateconv:
		move.l	d5,-(sp)			* fac2 merken
		bsr		ltor_			* -> d0-d3 ist fac1
		move.l	(sp)+,d4
		movem.l	d0-d3,-(sp)
		bsr		ltor_			* fac2 wandeln
		move.l	d0,d4
		move.l	d1,d5
		move.l	d2,d6
		move.l	d3,d7
		movem.l	(sp)+,d0-d3
		move.w	#FLOAT,typ2flag
		rts

*****************************************
* Multipl Fl*Fl/ int*int
* BEQ bedeutet float-multiplikation
* d0-d3 = fac1*fac2/  d0 = fac1*fac2
Mul:
		beq		rmul_			* float...
		movem.l	d0/d4,-(sp)		* fac1,2 merken
		bsr		imul				* int multiply
		movem.l	(sp)+,d4/d5
		tst.l	fl1work			* Åberlauf?
		beq		nooverflw
		bsr		lateconv
		bra		rmul_
nooverflw:
		rts

*****************************************
* fÅr unterroutinenen einsetzbare integermultiplikation
submul:
          movem.l   d0-a6,-(sp)         * register sichern vorher
          bsr       imul
          movem.l   (sp)+,d0-a6
          rts

*****************************************
* prÅft letztes Zeichen auf Klammer zu ), neg->syntaxerr
chk_klammer:
          bsr       chargot
          cmp.b     #')',d0
          bne       syntaxerr
          rts

*****************************************
* prÅft letztes Zeichen auf Komma
tst_komma:
          bsr       chargot
          cmp.b     #',',d0
          rts
*****************************************
* prÅft letztes Zeichen auf Komma, neg->syntaxerr
chk_komma:
          bsr       chargot
          cmp.b     #',',d0
          bne       syntaxerr
          rts
*****************************************
* Charget-Routine
* verlangt in a0 zeiger auf akt. Zeichen im Eingabepuffer
* Åberliest Spaces
* rÅckgabebyte in D0
chargot:
          subq.l    #1,a0
charget:
          move.b    (a0)+,d0
          cmp.b     #$20,d0
          beq.s     charget
          tst.b     d0
          rts
*****************************************
* Charget-Routine II
* verlangt in a0 zeiger auf akt. Zeichen im Eingabepuffer
* Åberliest Spaces
* rÅckgabebyte in D6
charget6:
          move.b    (a0)+,d6
          cmp.b     #$20,d6
          beq.s     charget
          tst.b     d6
          rts

*****************************************
* trÑgt stringptr (spstr) in querverweisliste ein (statt auf stack!)
onqlist:
          move.l    a0,-(sp)
          move.l    qlistptr,a0
          move.l    spstr,(a0)+
          move.l    a0,qlistptr
          move.l    (sp)+,a0
          rts
*****************************************
* holt stringptr wieder zurÅck (->spstr) aus qliste
offqlist:
          move.l    a0,-(sp)
          move.l    qlistptr,a0
          subq.l    #4,a0
          move.l    (a0),spstr
          move.l    a0,qlistptr
          move.l    (sp)+,a0
          rts

********************************************************************************
* Garbage Collection
********************************************************************************
* entfernt aus dem stringspeicher alle mit $ff als Endmarke gekennzeichneten
* strings
* in pgarbend steht ende bis wohin gesucht werden soll
* linkt alle descriptoren, strend, str_ptr, stackptr auf strings, a0-a6
garbage:
          movem.l   d0-d7,-(sp)
          movem.l   a0-a6,savereg
          move.l    pgarbend,spstr      * diese sollen auch akt. werden
          bsr       onqlist
          move.l    str_ptr,spstr
          bsr       onqlist
          move.l    strend,spstr
          bsr       onqlist
          move.w    #$0700,key          * Keyton als Arbeitszeichen
          pea       key
          move.w    #9,-(sp)
          trap      #1                  * ton ausgeben
          addq.l    #6,sp

          move.l    strbase,a0
garb1:
          move.l    a0,a6               * anfang des strings merken
          addq.l    #1,a0
garb2:
          move.b    -(a0),d0                 * zeichen auslesen
          beq       nextstrd                 * normaler, benutzter string->next
          cmp.b     #-1,d0                   * ÅberflÅssiger string
          bne       garb2
killstr:  * entfernt string und linkt descriptoren
          move.l    a6,d7                    * retten
          subq.l    #1,a0
          sub.l     a0,d7                    * d7 enthÑlt lÑnge des strings
          move.l    a0,a2                    * ziel
          move.l    a6,a3                    * start
          move.l    a0,d0                    * end (mit a3)
          sub.l     pgarbend,d0              * gibt es nichts zu lîschen?
          addq.l    #1,a2
          addq.l    #1,a3
garb4:
          move.b    -(a2),-(a3)
          subq.l    #1,d0
          bne       garb4
          bsr       garb_var                 * var. puffer prÅfen
          bsr       garb_reg                 * savereg prÅfen
          bsr       garb_qlist               * qliste prÅfen
          add.l     d7,a0                    * akt. strptr aktualisieren
          bra       nextstr                  * weitermachen

* qlist, savereg,var_puf aktualisieren
garb_qlist:
          lea       qlist,a1                 * basis der werte
garbq1:   cmp.l     qlistptr,a1              * schon fertig?
          bpl       garbrts
          bsr       linkstr                  * ggf. eintrag in liste akt.
          addq.l    #4,a1
          bra       garbq1
          rts

garb_reg:
          moveq.l   #6,d6                    * a0-a6 = 7 reg (-1) da dbf
          lea       savereg,a1
garbr1:   bsr       linkstr
          addq.l    #4,a1
          dbf       d6,garbr1
          rts

garb_var:
          move.l    varbase,a1
garb3:
          move.l    (a1)+,a5                 * ptr Åbergehen
          cmp.l     #0,a5
          beq       garbrts                  * mit nÑchsten string weiter
          move.w    (a1)+,d0
		and.w	#INT+FLOAT+STRING,d0
          cmp.w     #STRING,d0
          bne       garb5
garbok:   btst      #15,d0                   * array?
          bne       garbarray
          bra       garbstr                  * nein, dann normale strings
garb5:
          move.l    a5,a1
          bra       garb3
garbrts:  rts
 
nextstrd:
          subq.l    #1,a0
nextstr:
          cmp.l     pgarbend,a0
          bge       garb1                    * ende noch nicht da, weiter
          bsr       offqlist
          move.l    spstr,strend
          bsr       offqlist                 * werte zurÅckholen
          move.l    spstr,str_ptr
          bsr       offqlist
*         move.l    spstr,pgarbend
          movem.l   (sp)+,d0-d7
          movem.l   savereg,a0-a6
          rts

garbstr:
          bsr       garbsearch               * wert suchen (hinter namen)
          bsr       linkstr
          bra       garb5
 
* sucht hinter name den wert -> a1
garbsearch:
          tst.b     (a1)+
          bne       garbsearch
          move.l    a1,d0
          btst      #0,d0                    * auf gerade adr. setzen
          beq       garbs1
          addq.l    #1,a1
garbs1:
          rts
 
* linkt den string in a1
linkstr:
          move.l    (a1),d0
          cmp.l     a0,d0                    * prÅfen, ob hinter str stand
          bhi       garbs1
          cmp.l     strend,d0                * auf bereich prÅfen
          blt       garbs1                   * ausserhalb
          add.l     d7,(a1)
          rts
 
garbarray:
          bsr       garbsearch               * arrayheader suchen
          move.l    (a1)+,d0                 * arraytiefe
garbar1:
          move.l    (a1)+,d1                 * header Åberspringen
          subq.l    #1,d0
          bne       garbar1
garbar2:
          bsr       linkstr
          addq.l    #4,a1
          cmp.l     a1,a5                    * schon ende erreicht?
          bhi       garbar2
          bra       garb5

*****************************************
* macht eine kopie des var-names in var2_name
save_vname:
          movem.l   a0-a1,-(sp)
          lea       var_name,a0
          lea       var2_name,a1
save_v2:
          move.b    (a0)+,(a1)+
          bne.s     save_v2
          movem.l   (sp)+,a0-a1
          rts
*****************************************
* holt eine kopie des var-names in var2_name zurÅck
load_vname:
          movem.l   a0-a1,-(sp)
          lea       var2_name,a0
          lea       var_name,a1
          bra.s     save_v2
*****************************************
* liest integerwert ein (nur zahlen!)
* -> d0 ist int-wert, a0 zeigt hinter int-wert
get_int:
          moveq     #0,d0
get_i1:
          moveq     #0,d1
          move.b    (a0),d1
          cmp.b     #'0',d1  
          blt       get_iend
          cmp.b     #'9',d1   
          bhi       get_iend
          sub.b     #'0',d1
          move.l    d0,d2
          lsl.l     #3,d0               * mal 8
          lsl.l     #1,d2               * mal 2
          add.l     d2,d0               * ----- -> mal 10
          add.l     d1,d0
          addq.l    #1,a0
          bra.s     get_i1
get_iend:
          rts


* in a1 filenamen...wenn x: dann drive setzen!
setdrv:
		cmp.b	#':',-1(a1)		* drive?
		bne		nodrv
		moveq.l	#0,d0
		move.b	(a1),d0
		and.b	#$1f,d0
		subq.w	#1,d0
		move.w	d0,-(sp)
		move.w	#$e,-(sp)
		trap		#1				* setdrv
		addq.l	#4,sp
		subq.l	#2,a1
nodrv:
		rts

*****************************************
* îffnet file mit name Åber str_ptr
* -> handle enthÑlt filehandle oder -1 fÅr fehler!
f_create:
          move.l    a0,-(sp)            * retten
          clr.w     -(sp)
          move.w    #$3c,work2          * code fÅr create
          bra       fo2
*****************************************
f_open:
          move.l    a0,-(sp)
          move.w    #2,-(sp)
          move.w    #$3d,work2          * code fÅr open
fo2:
		move.l    str_ptr,a1
		bsr		setdrv
          lea       var2_name,a2
          addq.l    #1,a1
fo1a:
          move.b    -(a1),(a2)+
          bne       fo1a

          pea       var2_name
          move.w    work2,-(sp)         * open/create
          trap      #1
          addq.l    #8,sp
          tst.w     d0                  * auf fehler testen
          bmi       fo3
          move.w    d0,handle
          move.l    (sp)+,a0
          rts
fo3:      cmp.w     #$3c,work2          * createerr?
          beq       createrr
          bra       openerr

******************************************
* schreibt ein file, a1 zeigt auf puffer, d0 auf lÑnge, handle ist fhandle
f_write:
          move.l    a0,-(sp)
          move.l    a1,-(sp)
          move.l    d0,-(sp)
          move.w    handle,-(sp)
          move.w    #$40,-(sp)
          trap      #1
          lea       12(a7),a7
          tst.l     d0
          bmi       writerr
          move.l    (sp)+,a0
          rts

******************************************
* liest ein file, a1 zeigt auf puffer, handle ist fhandle, d0 ist anzahl
* -> D0 enthÑlt lÑnge
f_read:
          move.l    a0,-(sp)
          move.l    a1,-(sp)
          move.l    d0,-(sp)    
          move.w    handle,-(sp)
          move.w    #$3f,-(sp)
          trap      #1
          lea       12(a7),a7
          tst.l     d0
          bmi       readerr
          move.l    (sp)+,a0
          rts

*****************************************
* schliesst file, handle ist fhandle
f_close:
          move.l    a0,-(sp)
          move.w    handle,-(sp)
          move.w    #$3e,-(sp)
          trap      #1
          addq.l    #4,sp
          move.l    (sp)+,a0
          rts
*****************************************
* linkt ein programm so, das aus rel. feste ptr werden.
new_link:
          move.l    prgend,a2
          clr.l     (a2)                * sichergehen, das ende durch 0 da ist
          move.l    prgbase,a2
          move.l    a2,d1
nlink1:   move.l    (a2),d0
          beq       nlinkend
          add.l     d1,(a2)
          add.l     d1,d0
          move.l    d0,a2
          bra       nlink1
nlinkend: rts

*****************************************
* auf zeile im prg-speicher positionieren
* D0 enthÑlt zu suchende zeilennr.
* -> a1 zeigt auf einzufÅgende stelle
preline:	.ds.l	1	* -> 0 (keine vorhige zeile)/wert
poszeile:
          movem.l   d2/d3,-(sp)
          move.l    prgbase,a1
		moveq.l	#0,d2
posz1:
          move.l    (a1),d3
          beq       poszend
		cmp.l	4(a1),d0			* zeilennr. vgl
		ble		poszend
		move.l	a1,d2			* die zeile zuvor auch merken!
          move.l    d3,a1
          bra       posz1
poszend:
		move.l	d2,preline
          movem.l   (sp)+,d2/d3
          rts

*****************************************
* testet, ob ein nÑchstes argument vorhanden ist
* -> D0 = BEQ wenn arg da ist
tstnxtarg:
          move.l    a0,a1
          bsr       charget
          beq       nonxt
          cmp.b     #':',d0
          beq       nonxt
          move.l    a1,a0
          moveq     #0,d0          * BEQ als zeichen, dass ein arg da ist
          rts
nonxt:
          move.l    a1,a0
          moveq.l   #-1,d0
          rts
*****************************************
* springt zum nÑchsten befehl oder zeilenende (: oder 0)
tonxtcmd:
          bsr       charget
          beq       tonxt1
          cmp.b     #':',d0
          beq       tonxt1
          bra       tonxtcmd
tonxt1:   rts

*****************************************
* springt zum nÑchsten befehl oder zeilenende (: oder 0)
* allerdings wird bei : auf innerhalb string geachetet!
dtonxtcmd:
          clr.w     d1                  * flag fÅr " oder nicht
dton3:    bsr       charget
          beq       dtonend             * zeilenende
          cmp.b     #':',d0
          bne       dton2
          tst.w     d1                  * : ausserhalb eines strings
          beq       dtonend
          bra       dton3
dton2:    cmp.b     #'"',d0
          bne       dton3
          not.w     d1                  * d1 als flag hin-und herschalten
          bra       dton3
dtonend:  rts


********************************************************************************
* STAD-Befehle:
********************************************************************************
*****************************************
* LINE   line x1,y1,x2,y2
*****************************************
* Linie  von x1,y1 nach x2,y2
line:
          bsr       tstnxtarg
          bne       misargerr           * Argumente fehlen
          move.w    #INT,typvalid
          bsr       get_term
          movea.l   la_variablen,a2
          move.w    fac1+2,$26(a2)      * x1
          bsr       chk_komma
          move.w    #INT,typvalid
          bsr       get_term
          movea.l   la_variablen,a2
          move.w    fac1+2,$28(a2)      * y1
          bsr       chk_komma
          move.w    #INT,typvalid
          bsr       get_term
          movea.l   la_variablen,a2
          move.w    fac1+2,$2a(a2)      * x2
          bsr       chk_komma
          move.w    #INT,typvalid
          bsr       get_term
          movea.l   la_variablen,a2
          move.w    fac1+2,$2c(a2)      * y2
*
* lineparameter setzen
*
          nop
          move.l    a0,-(a7)
          .dc.w     $a003               * Line
          move.l    (a7)+,a0
          rts

********************************************************************************
* Fehlermeldungen
********************************************************************************
* Syntaxfehler
.globl  error                           * Einsprung fÅr blibf


defprerr:
		moveq.l	#63,d0
		bra		error
headerr:
		moveq.l	#62,d0
		bra		error
notopenerr:
		moveq.l	#61,d0
		bra		error
trgoserr:
		moveq.l	#60,d0
		bra		error
noeprcerr:
		moveq.l	#59,d0
		bra		error
noreterr:
		moveq.l	#58,d0
		bra		error
nonxterr:
		moveq.l	#57,d0
		bra		error
outstrspc:
		moveq.l	#56,d0
		bra		error
nofkterr:
		moveq.l	#55,d0
		bra		error
toerr:
		moveq.l	#54,d0
		bra		error
thenerr:
		moveq.l	#53,d0
		bra		error
elseerr:
		moveq.l	#52,d0
		bra		error
nocmderr:
		moveq.l	#51,d0
		bra		error
locdeferr:
		moveq.l	#50,d0
		bra		error
misargerr:
		moveq.l	#49,d0
		bra		error
fndeferr:
		moveq.l	#48,d0
		bra		error
toobigerr:
		moveq.l	#47,d0
		bra		error
nolineerr:
		moveq.l	#46,d0
		bra		error
strposerr:
		moveq.l	#45,d0
		bra		error
oddadrerr:
		moveq.l	#44,d0
		bra		error
cposerr:
		moveq.l	#43,d0
		bra		error
start1err:
		moveq.l	#42,d0
		bra		error
aesrangeerr:
		moveq.l	#41,d0
		bra		error
manyargerr:
		moveq.l	#40,d0
		bra		error
noargerr:
		moveq.l	#39,d0
		bra		error
negerr:
negdimerr:
		moveq.l	#38,d0
		bra		error
convovflerr:
		moveq.l	#37,d0
		bra		error
convnoerr:
		moveq.l	#36,d0
		bra		error
procerr:
		moveq.l	#35,d0
		bra		error
procnotfound:
		moveq.l	#34,d0
		bra		error
varperr:
          moveq.l   #33,d0
          bra       error
callerr:
          moveq.l   #32,d0
          bra       error
syserr:
          moveq.l   #31,d0
          bra       error
conterr:
          moveq.l   #30,d0
          bra       error
nodataerr:
          moveq.l   #29,d0
          bra       error
alropen:
          moveq.l   #28,d0
          bra       error
handflow:
          moveq.l   #27,d0
          bra       error
stoperr:
          moveq.l   #26,d0
          bra       error
ifflow:
          moveq.l   #25,d0
          bra       error
toomanyprocs:
		moveq.l	#24,d0
		bra		error
gosflow:
          moveq.l   #23,d0
          bra       error
goserr:
          moveq.l   #22,d0
          bra       error
prgmerr:
          moveq.l   #21,d0
          bra       error
forflow:
          moveq.l   #20,d0
          bra       error
nexterr:
          moveq.l   #19,d0
          bra       error
dircterr:
          moveq.l   #18,d0
          bra       error
readerr:
          moveq.l   #17,d0
          bra       error
openerr:
          moveq.l   #16,d0
          bra       error
writerr:
          moveq.l   #15,d0
          bra       error
createrr:
          moveq.l   #14,d0
          bra       error
outprgmem:
          moveq.l   #13,d0
          bra       error
dimerr:
          moveq.l   #12,d0
          bra       error
redef:
          moveq.l   #11,d0
          bra       error
outvarmem:
          moveq.l   #10,d0
          bra       error
badsubscr:
          moveq.l   #9,d0
          bra       error
typemis:                        * 2-8 belegt durch floating point emulator
          moveq     #1,d0
          bra       error
syntaxerr:
          moveq.l   #0,d0
error:
		tst.w	convfl
		beq		error0
		move.l	d0,-(sp)
		bsr		f_close			* bei fehler in convert file closen!
		clr.w	convfl
		move.l	(sp)+,d0
error0:
		move.l	akt_zeile,-(sp)	* merken
          move.l    #-1,contline        * default: kein cont erlaubt
          cmp.b     #26,d0              * war fehler der stop error?
          bne       error1
          tst.w     b_modus             * geht auch nicht bei direkt-m.
          beq       error1
          move.l    akt_zeile,contline  * zeilennr
          move.l    akt_adr,contladr    * adr der zeile
          move.l    a0,contadr          * akt zeiger
		clr.l	akt_zeile			* 0->kein list line
error1:
		bsr       clrfilefl
          lea       errormark,a0
          bsr       put_string
          lsl.w     #2,d0
          lea       errortab,a0
          move.l    (a0,d0.w),a0
          bsr       put_string
          lea       errtxt1,a0
          bsr       put_string
          tst.w     b_modus             * auf direktmodus testen
          beq       basic1
		tst.l	(sp)				* zeilennr.
		beq		error1a			* nicht ausgeben, da 0 verwirrend (da oft als dummy-line#)

          lea       errtxt2,a0          * bei prg-mode noch line ausgeben
          bsr       put_string
          move.l    (sp)+,d0
          bsr       ipka_               * zeilenr. in ascii wandeln (->a2)
          lea       -1(a2),a0            * vorzeichen Åbergehen
          bsr       putstrreverse
error1a:
		tst.l	akt_zeile			* wenn 0, kein list
		beq		noerrlist
		move.l	akt_zeile,d0
		move.l	d0,d6
		move.l	d0,d7
		bsr		poszeile			* versucht darauf zu positionieren
		cmp.l	akt_adr,a1		* stimmt zeilenadr?
		bne		noerrlist
		move.l	a1,a0
		clr.w	d0
		bsr		listlines
		bsr		new_line
noerrlist:
          bra       basic1


********************************************************************************
**   Start des Datenteils                                                     **
********************************************************************************
* fÅr blibf global:
.globl  typflag,typ2flag,typ3flag,str_ptr,work1
.data
hextab    .dc.b   '0','1','2','3','4','5','6','7','8','9','a','b','c'
          .dc.b   'd','e','f'
qlistptr  .dc.l     qlist          * zeiger auf qlist
tisptr	.dc.l	tistrend-1
ready:    .dc.b     13,"ready.",13,0

fragez:   .dc.b     "? ",0
errormark:.dc.b     13,"? ",0
errtxt1:  .dc.b     " error",0
errtxt2:  .dc.b     " in line ",0

.even
errortab: .dc.l     err0,err1,err2,err3,err4,err5,err6,err7,err8,err9,err10
          .dc.l     err11,err12,err13,err14,err15,err16,err17,err18,err19
          .dc.l     err20,err21,err22,err23,err24,err25,err26,err27,err28
          .dc.l     err29,err30,err31,err32,err33,err34,err35,err36,err37
		.dc.l	err38,err39,err40,err41,err42,err43,err44,err45,err46
		.dc.l	err47,err48,err49,err50,err51,err52,err53,err54,err55
		.dc.l	err56,err57,err58,err59,err60,err61,err62,err63

err0:     .dc.b     "syntax",0
err1:     .dc.b     "type mismatch",0
err2:     .dc.b     "invalid operand",0
err3:     .dc.b     "inexact result",0
err4:     .dc.b     "square root of negative",0
err5:     .dc.b     "log of negative number",0
err6:     .dc.b     "overflow",0
err7:     .dc.b     "underflow",0
err8:     .dc.b     "division by zero",0
err9:     .dc.b     "bad subscript",0
err10:    .dc.b     "out of variable space",0
err11:    .dc.b     "re-define",0
err12:    .dc.b     "dim",0
err13:    .dc.b     "out of program space",0
err14:    .dc.b     "file create",0
err15:    .dc.b     "file write",0
err16:    .dc.b     "file open",0
err17:    .dc.b     "file read",0
err18:    .dc.b     "illegal direct",0
err19:    .dc.b     "next without for",0
err20:    .dc.b     "for-next overflow",0
err21:    .dc.b     "illegal prg. mode",0
err22:    .dc.b     "return without gosub",0
err23:    .dc.b     "gosub-return overflow",0
err24:	.dc.b	"procedure overflow",0
err25:    .dc.b     "if-then-else overflow",0
err26:    .dc.b     "prg stopped",0
err27:    .dc.b     "too many files open",0
err28:    .dc.b     "already open",0
err29:    .dc.b     "out of data",0
err30:    .dc.b     "can't continue",0
err31:    .dc.b     "improper use of system variable",0
err32:    .dc.b     "improper function number for gemdos/bios/xbios",0
err33:    .dc.b     "variable not yet defined",0
err34:	.dc.b	"procedure not defined",0
err35:	.dc.b	"endproc without proc",0
err36:	.dc.b	"line numbers missing",0
err37:	.dc.b	"line too long",0
err38:	.dc.b	"no negative arg allowed",0
err39:	.dc.b	"no arg allowed",0
err40:	.dc.b	"too many args",0
err41:	.dc.b	"out of field range",0
err42:	.dc.b	"arg < 1",0
err43:	.dc.b	"cursor out of range",0
err44:	.dc.b	"odd address access",0
err45:	.dc.b	"position not within string",0
err46:	.dc.b	"cant't find line number",0
err47:	.dc.b	"arg too big",0
err48:	.dc.b	"fn not defined",0
err49:	.dc.b	"missing arg(s)",0
err50:	.dc.b	"local definition",0
err51:	.dc.b	"illegal use as command",0
err52:	.dc.b	"else without for",0
err53:	.dc.b	"missing <then>",0
err54:	.dc.b	"missing <to>",0
err55:	.dc.b	"illegal use as function",0
err56:	.dc.b	"out of string space",0
err57:	.dc.b	"for without next",0
err58:	.dc.b	"gosub without return",0
err59:	.dc.b	"proc without endproc",0
err60:	.dc.b	"missing gosub",0
err61:	.dc.b	"no such handle known",0
err62:	.dc.b	"no BASIC file format",0
err63:	.dc.b	"improper procedure definition",0

.even
savetext: .dc.b     13,"saving...",0
.even
loadtext: .dc.b     13,"loading...",0
.even
mergetext:.dc.b	13,"merging...",0
.even
convtext:	.dc.b	13,"converting...",0
.even
joker     .dc.b     "*.*",0
.even

optabl:
          .dc.l     ShL,ShR,Xor,And,Or,Lower,Equal,Higher,Add,Sub,Mul,Div,Exponent
optoktabl:
          .dc.b     '{','}','~','&','|','<','=','>','+','-','*','/','^',0
oppriotabl:
          .dc.b      1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13
*                                        -   -   - wird direkt im prg abgefragt (cmp #6)!


.even
comadr:	.dc.l	0,comadr1,comadr2,comadr3
tokenadr:
		.dc.l	0,token1adr,token2adr,token3adr

comadr1:
          .dc.l     Print
          .dc.l     Dim
          .dc.l     List
          .dc.l     Save
          .dc.l     Load
          .dc.l     Run
          .dc.l     Clr
          .dc.l     Goto
          .dc.l     Int+$80000000  * funktion
          .dc.l     For
          .dc.l     syntaxerr
          .dc.l     syntaxerr * wird nur von For-routine aufgerufen
          .dc.l     Next
          .dc.l     Endproc+$40000000
          .dc.l     Gosub	* gosub geht immer!
          .dc.l     Return+$40000000
          .dc.l     If
          .dc.l     syntaxerr * then wird direkt in If abgefragt
          .dc.l     Else+$40000000
          .dc.l     Varfre+$80000000
          .dc.l     Create
          .dc.l     Strfre+$80000000
          .dc.l     Merge
          .dc.l     Rem
          .dc.l     Stop
          .dc.l     Help
          .dc.l     New+$20000000
          .dc.l     Deffn
          .dc.l     Fn+$88000000   * funktion, aber ohen (-PrÅfung!
          .dc.l     Input
          .dc.l     On
          .dc.l     Open
          .dc.l     Close
          .dc.l     Spc+$80000000
          .dc.l     Tab+$80000000
          .dc.l     dtonxtcmd+$40000000      * bei data befehl Åbergehen!
          .dc.l     Read
          .dc.l     Restore+$40000000
          .dc.l     Get
          .dc.l     Len+$80000000
          .dc.l     Str+$80000000
          .dc.l     Val+$80000000
          .dc.l     Function+$80000000
          .dc.l     Asc+$80000000
          .dc.l     Chr+$80000000
          .dc.l     Left+$80000000
          .dc.l     Right+$80000000
          .dc.l     Mid+$80000000
          .dc.l     Pos+$80000000
          .dc.l     Not+$88000000
          .dc.l     Cmd
          .dc.l     Poke
          .dc.l     Peek+$80000000
          .dc.l     Sin+$80000000
          .dc.l     Cos+$80000000
          .dc.l     Sqr+$80000000
          .dc.l     Log+$80000000
          .dc.l     Ln+$80000000
          .dc.l     Exp10+$80000000
          .dc.l     Tan+$80000000
          .dc.l     Atn+$80000000
          .dc.l     Exp+$80000000
          .dc.l     Sgn+$80000000
          .dc.l     Abs+$80000000
          .dc.l     Rnd+$80000000
          .dc.l     Sys
          .dc.l     Cont+$20000000
          .dc.l     Cls
          .dc.l     Dpeek+$80000000
          .dc.l     Dpoke
          .dc.l     Lpeek+$80000000
          .dc.l     Lpoke
          .dc.l     Atnpt+$80000000
          .dc.l     Mod+$80000000
          .dc.l     Gemdos+$80000000
          .dc.l     Bios+$80000000
          .dc.l     Xbios+$80000000
          .dc.l     Varptr+$80000000
          .dc.l     Dir
          .dc.l     Hex+$80000000
          .dc.l     Bin+$80000000
          .dc.l     Cursor
		.dc.l	Proc
		.dc.l	run2
		.dc.l	Local+$40000000
		.dc.l	Delete+$20000000
		.dc.l	Inkey+$88000000
		.dc.l	Wait
		.dc.l	Swapvars
		.dc.l	Tron
		.dc.l	Troff
		.dc.l	Instr+$80000000
		.dc.l	Call+$80000000
		.dc.l	Aesctrl+$10000000
		.dc.l	Aesintin
		.dc.l	Aesintout+$80000000
		.dc.l	Aesadrin
		.dc.l	Aesadrout+$80000000
		.dc.l	Vdictrl+$10000000
		.dc.l	Vdiintin
		.dc.l	Vdiintout+$80000000
		.dc.l	Vdiptsin
		.dc.l	Vdiptsout+$80000000
		.dc.l	Aes
		.dc.l	Vdi
		.dc.l	Convert
		.dc.l	Dump
		.dc.l	syntaxerr		* trace
		.dc.l	syntaxerr		* and
		.dc.l	syntaxerr		* or
		.dc.l	syntaxerr		* eor
		.dc.l	Auto+$20000000
		.dc.l	Edtab+$80000000
comadr2:
          .dc.l     line
comadr3:
		.dc.l	line

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
          .dc.w     LINE2
*************** token 3xx
		.dc.w	LINE3
***************

helpnadr: .dc.l     helpn1,helpn2,helpn3,helpn4,helpn5,helpn6,helpn7
          .dc.l     helpn8,helpn9,helpn10,helpn11,helpn12,helpn13
          .dc.l     helpn14,helpn15,helpn16,helpn17,helpn18,helpn19
          .dc.l	helpn20,helpn21
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
          .dc.l     comn2_1
*************** token 3xx
token3adr:
		.dc.l	comn3_1
***************
          .dc.l     0


helpstr:
helpn1:   .dc.b     "$",0
helpn2:   .dc.b     "%",0
helpn3:   .dc.b     "pi",0
helpn4:   .dc.b     "ti",0
helpn5:   .dc.b     "ti$",0
helpn6:	.dc.b	"{",0
helpn7:	.dc.b	"}",0
helpn8:	.dc.b	"~",0
helpn9:   .dc.b     "&",0
helpn10:   .dc.b     "|",0
helpn11:   .dc.b     "<",0
helpn12:   .dc.b     "=",0
helpn13:  .dc.b     ">",0
helpn14:  .dc.b     "+",0
helpn15:  .dc.b     "-",0
helpn16:  .dc.b     "*",0
helpn17:  .dc.b     "/",0
helpn18:  .dc.b     "^",0
helpn19:  .dc.b     "print#",0
helpn20:  .dc.b     "input#",0
helpn21:  .dc.b     "get#",0

tokenstr:
******** token 1xx
comn1:    .dc.b     "print",0
comn2:    .dc.b     "dIm",0
comn3:    .dc.b     "lIst",0
comn4:    .dc.b     "sAve",0
comn5:    .dc.b     "lOad",0
comn6:    .dc.b     "rUn",0
comn7:    .dc.b     "clr",0
comn8:    .dc.b     "gOto",0
comn9:    .dc.b     "inT",0
comn10:   .dc.b     "fOr",0
comn11:   .dc.b     "to",0
comn12:   .dc.b     "sTep",0
comn13:   .dc.b     "nExt",0
comn14:   .dc.b     "eNdproc",0
comn15:   .dc.b     "goSub",0
comn16:   .dc.b     "reTurn",0
comn17:   .dc.b     "if",0
comn18:   .dc.b     "tHen",0
comn19:   .dc.b     "eLse",0
comn20:   .dc.b     "fRe",0
comn21:   .dc.b     "cReate",0
comn22:   .dc.b     "strFre",0
comn23:   .dc.b     "mErge",0
comn24:   .dc.b     "rEm",0
comn25:   .dc.b     "stOp",0
comn26:   .dc.b     "hElp",0
comn27:   .dc.b     "nEw",0
comn28:   .dc.b     "dEf",0
comn29:   .dc.b     "fn",0
comn30:   .dc.b     "iNput",0
comn31:   .dc.b     "on",0
comn32:   .dc.b     "oPen",0
comn33:   .dc.b     "cLose",0
comn34:   .dc.b     "sPc",0
comn35:   .dc.b     "tAb",0
comn36:   .dc.b     "dAta",0
comn37:   .dc.b     "reAd",0
comn38:   .dc.b     "reStore",0
comn39:   .dc.b     "gEt",0
comn40:   .dc.b     "lEn",0
comn41:   .dc.b     "stR$",0
comn42:   .dc.b     "vAl",0
comn43:   .dc.b     "fUnction",0
comn44:   .dc.b     "aSc",0
comn45:   .dc.b     "cHr$",0
comn46:   .dc.b     "leFt$",0
comn47:   .dc.b     "rIght$",0
comn48:   .dc.b     "mId$",0
comn49:   .dc.b     "pos",0
comn50:   .dc.b     "nOt",0
comn51:   .dc.b     "cMd",0
comn52:   .dc.b     "pOke",0
comn53:   .dc.b     "pEek",0
comn54:   .dc.b     "sIn",0
comn55:   .dc.b     "cos",0
comn56:   .dc.b     "sQr",0
comn57:   .dc.b     "log",0
comn58:   .dc.b     "ln",0
comn59:   .dc.b     "exP10",0
comn60:   .dc.b     "tAn",0
comn61:   .dc.b     "aTn",0
comn62:   .dc.b     "eXp",0
comn63:   .dc.b     "sGn",0
comn64:   .dc.b     "aBs",0
comn65:   .dc.b     "rNd",0
comn66:   .dc.b     "sYs",0
comn67:   .dc.b     "cOnt",0
comn68:   .dc.b     "cls",0
comn69:   .dc.b     "wpEek",0
comn70:   .dc.b     "wpOke",0
comn71:   .dc.b     "lpEek",0
comn72:   .dc.b     "lpOke",0
comn73:   .dc.b     "atAnpt",0
comn74:   .dc.b     "mOd",0
comn75:   .dc.b     "geMdos",0
comn76:   .dc.b     "bIos",0
comn77:   .dc.b     "xBios",0
comn78:   .dc.b     "varPtr",0
comn79:   .dc.b     "dir",0
comn80:   .dc.b     "heX$",0
comn81:   .dc.b     "bIn$",0
comn82:   .dc.b     "cUrsor",0
comn83:	.dc.b	"prOc",0
comn84:	.dc.b	"end",0
comn85:	.dc.b	"loCal",0
comn86:	.dc.b	"deLete",0
comn87:	.dc.b	"inKey$",0
comn88:	.dc.b	"wAit",0
comn89:	.dc.b	"sWap",0
comn90:	.dc.b	"tRon",0
comn91:	.dc.b	"trOff",0
comn92:	.dc.b	"inStr$",0
comn93:	.dc.b	"cAll",0
comn94:	.dc.b	"aesCtrl",0
comn95:	.dc.b	"aesintIn",0
comn96:	.dc.b	"aesintOut",0
comn97:	.dc.b	"aesadrIn",0
comn98:	.dc.b	"aesadrOut",0
comn99:	.dc.b	"vdiCtrl",0
comn100:	.dc.b	"vdiintIn",0
comn101:	.dc.b	"vdiintOut",0
comn102:	.dc.b	"vdiptsIn",0
comn103:	.dc.b	"vdiptsOut",0
comn104:	.dc.b	"aEs",0
comn105:	.dc.b	"vDi",0
comn106:	.dc.b	"coNvert",0
comn107:	.dc.b	"dUmp",0
comn108:	.dc.b	"trAce",0
comn109:	.dc.b	"aNd",0
comn110:	.dc.b	"or",0
comn111:	.dc.b	"eOr",0
comn112:	.dc.b	"aUto",0
comn113:	.dc.b	"eDtab",0

*************** token 2xx
comn2_1:  .dc.b     "line2",0
*************** token 3xx
comn3_1:	.dc.b	"line3",0
***************
          .dc.b     0

.even
                .ds.w   1
.even
* aufbau von gemdtbl,biostbl und xbiostbl: 1(STRING/INT),2(0=.W/1=.L)
gemdtbl:
     .dc.w     $58  * $58 eintrÑge
     .dc.l     Gt1,Gt2,Gt3,Gt4,Gt5,Gt6,Gt7,Gt8,Gt9,Gt10,Gt11,Gt12,-1,-1
     .dc.l     Gt13,-1,Gt14,Gt15,Gt16,Gt17,-1,-1,-1,-1,-1,Gt18,Gt19
     .dc.l     -1,-1,-1,-1,-1,Gt20,-1,-1,-1,-1,-1,-1,-1,-1,-1,Gt21,Gt22
     .dc.l     Gt23,Gt24,-1,Gt25,Gt26,Gt27,-1,-1,-1,-1,Gt28,-1,-1,Gt29
     .dc.l     Gt30,Gt31,Gt32,Gt33,Gt34,Gt35,Gt36,Gt37,Gt38,Gt39,-1
     .dc.l     Gt40,Gt41,Gt42,Gt43,Gt44,Gt45,Gt46,Gt47,Gt48,Gt49
     .dc.l     -1,-1,-1,-1,-1,-1,Gt50,Gt51
Gt1  .dc.w     0                           * TERM
Gt2  .DC.W     0                           * CONIN
Gt3  .DC.W     INT,0, 0                    * CONOUT
Gt4  .DC.W     0                           * CAUXIN
Gt5  .DC.W     INT,0, 0                    * CAUXOUT
Gt6  .DC.W     INT,0, 0                    * PRNTOUT
Gt7  .DC.W     INT,0, 0                    * RAWCONIO
Gt8  .DC.W     0                           * DCONIN
Gt9  .DC.W     0                           * ECONIN
Gt10 .DC.W     STRING,1, 0                 * PRINTLINE
Gt11 .DC.W     INT,1, 0                    * READLINE
Gt12 .DC.W     0                           * CONSTAT
Gt13 .DC.W     INT,0, 0                    * SETDRV
Gt14 .DC.W     0                           * CONSTATOUT
Gt15 .DC.W     0                           * PRTOUTSTAT
Gt16 .DC.W     0                           * AUXINSTAT
Gt17 .DC.W     0                           * AUXOUTSTAT
Gt18 .DC.W     0                           * CURRENTDISK
Gt19 .DC.W     INT,1, 0                    * SETDTA
Gt20 .DC.W     INT,1, 0                      * SUPER
Gt21 .DC.W     0                             * GETDATE
Gt22 .DC.W     INT,0, 0                      * SETDATE
Gt23 .DC.W     0                             * GETTIME
Gt24 .DC.W     INT,0, 0                      * SETTIME
Gt25 .DC.W     0                             * GETDTA
Gt26 .DC.W     0                             * GETVERSION
Gt27 .DC.W     INT,1, INT,0, 0               * KEEPPROCESS
Gt28 .DC.W     INT,1, INT,0, 0               * GET DISK FREE SPACE
Gt29 .DC.W     STRING,1, 0                   * MKDIR
Gt30 .DC.W     STRING,1, 0                   * RMDIR
Gt31 .DC.W     STRING,1, 0                   * CHNGDIR
Gt32 .DC.W     STRING,1, INT,0, 0            * CREATE
Gt33 .DC.W     STRING,1, INT,0, 0            * OPEN
Gt34 .DC.W     INT,0, 0                      * CLOSE
Gt35 .DC.W     INT,0, INT,1, INT,1, 0        * READ
Gt36 .DC.W     INT,0, INT,1, INT,1, 0        * WRITE
Gt37 .DC.W     STRING,1, 0                   * UNLINK
Gt38 .DC.W     INT,1, INT,0, INT,0, 0        * LSEEK
Gt39 .DC.W     STRING,1, INT,0, INT,0, 0     * CHMOD
Gt40 .DC.W     INT,0, 0                      * DUP
Gt41 .DC.W     INT,0 ,INT,0, 0               * FORCE
Gt42 .DC.W     INT,1, INT,0, 0               * DGETPATH
Gt43 .DC.W     INT,1, 0                      * MALLOC
Gt44 .DC.W     INT,1, 0                      * MFREE
Gt45 .DC.W     INT,0, INT,1, INT,1, 0        * MSHRINK
Gt46 .DC.W     INT,0, STRING,1, STRING,1, STRING,1, 0  * PEXEC
Gt47 .DC.W     INT,0, 0                      * PTERM
Gt48 .DC.W     STRING,1, INT,0, 0            * FSFIRST
Gt49 .DC.W     0                             * FSNEXT
Gt50 .DC.W     INT,0, STRING,1, STRING,1, 0  * RENAME
Gt51 .DC.W     INT,0, INT,1, INT,0, 0        * FDATIME
     
biostbl:
     .dc.w     12   * 12 eintrÑge
     .dc.l     bt1,bt2,bt3,bt4,bt5,bt6,bt7,bt8,bt9,bt10,bt11,bt12
bt1  .DC.W     INT,1, 0                      * GETMPB
bt2  .DC.W     INT,0, 0                      * BCONSTAT
bt3  .DC.W     INT,0, 0                      * BCONIN
bt4  .DC.W     INT,0, INT,0, 0               * BCONOUT
bt5  .DC.W     INT,0, INT,1, INT,0, INT,0, INT,0, 0    * RWABS
bt6  .DC.W     INT,0, INT,1, 0               * SETEXEC
bt7  .DC.W     0                             * TICKCAL
bt8  .DC.W     INT,0, 0                      * GETBPB
bt9  .DC.W     INT,0, 0                      * BCOSTAT
bt10 .DC.W     INT,0, 0                      * MEDIACH
bt11 .DC.W     INT,1, 0                      * DRVMAP
bt12 .DC.W     INT,0, 0                      * KBSHIFT
     
xbiostbl:
     .dc.w     40   * 40 eintrÑge
     .dc.l     xt1,xt2,xt3,xt4,xt5,xt6,xt7,xt8,xt9,xt10,xt11,-1,xt12
     .dc.l     xt13,xt14,xt15,xt16,xt17,xt18,xt19,xt20,xt21,xt22
     .dc.l     xt23,xt24,xt25,xt26,xt27,xt28,xt29,xt30,xt31,xt32
     .dc.l     xt33,xt34,xt35,xt36,xt37,xt38,xt39
xt1  .DC.W     INT,0, INT,1, INT,1, 0        * INITMOUSE
xt2  .DC.W     INT,1, 0                      * SSBRK
xt3  .DC.W     0                             * PHYSBASE
xt4  .DC.W     0                             * LOGBASE
xt5  .DC.W     0                             * GETREZ
xt6  .DC.W     INT,1, INT,1, INT,0, 0        * SETSCR
xt7  .DC.W     INT,1, 0                      * SETPALET
xt8  .DC.W     INT,0, INT,0 ,0               * SETCOL
xt9  .DC.W     INT,1, INT,1, INT,0, INT,0, INT,0, INT,0, INT,0, 0  * READ
xt10 .DC.W     INT,1, INT,1, INT,0, INT,0, INT,0, INT,0, INT,0, 0  * WRITE
xt11 .DC.W     INT,1, INT,1, INT,0, INT,0, INT,0, INT,0, INT,0
     .dc.w     INT,1, INT,0, 0               * FORMAT
xt12 .DC.W     INT,0, INT,1, 0               * MIDIWS
xt13 .DC.W     INT,0, INT,1, 0               * MFPINT
xt14 .DC.W     INT,0, 0                      * IOREC
xt15 .DC.W     INT,0, INT,0, INT,0, INT,0, INT,0, INT,0, 0  * RSCONF
xt16 .DC.W     INT,1, INT,1, INT,1, 0        * KEYTAB
xt17 .DC.W     0                             * RANDOM
xt18 .DC.W     INT,1, INT,1, INT,0, INT,0, 0 * PROTOBT
xt19 .DC.W     INT,1, INT,1, INT,0, INT,0, INT,0, INT,0, INT,0, 0  * VERIFY
xt20 .DC.W     0                             * SCRDUMP
xt21 .DC.W     INT,0, INT,0, 0               *CURSCONF
xt22 .DC.W     INT,1, 0                      * SETTIME
xt23 .DC.W     0                             * GETTIME
xt24 .DC.W     0                             * BIOSKEYS
xt25 .DC.W     INT,0, INT,1, 0               * IKDBWS
xt26 .DC.W     INT,0, 0                      *JDISINT
xt27 .DC.W     INT,0 ,0                      * JENABINT
xt28 .DC.W     INT,0, INT,0, 0               * GIACCESS
xt29 .DC.W     INT,0, 0                      * OFFGIBIT
xt30 .DC.W     INT,0, 0                      * ONGBIT
xt31 .DC.W     INT,0, INT,0, INT,0, INT,1, 0 * XBTIMER
xt32 .DC.W     INT,1, 0                      * DOSOUND
xt33 .DC.W     INT,0 ,0                      * OLDCONF
xt34 .DC.W     0                             * KDBVBASE
xt35 .DC.W     INT,0, INT,0, 0               * KBRATE
xt36 .DC.W     INT,1, 0                      * PRTBLK
xt37 .DC.W     0                             * VSYNC
xt38 .DC.W     INT,1, 0                      * SUPEX
xt39 .DC.W     0                             * PUNTAES

.even
leer_str:      .dc.l    0          * inhalt eines leerstrings
.even

AESPB:	.dc.l	AESctrl,AESglobal,AESintin,AESintout,AESadrin,AESadrout
VDIPB:	.dc.l	VDIctrl,VDIintin,VDIptsin,VDIintout,VDIptsout


.bss
arrayfl   .ds.b     1              * wenn gesetzt, dann akt. var. ist array
.even
arraydeep .ds.l     1              * anzahl der dimensionen
arraylen  .ds.l     10             * lÑngen der max. 10 dimensionen
array2len	.ds.l	10
putfl     .ds.w     1              * wenn gesetzt, put_str ignoriert zeil.Åberl.
          .ds.w     1
tiint:    .ds.l     1
tistring: .ds.b     10
tistrend:
typvalid: .ds.w     1
typflag   .ds.w     1
typ2flag  .ds.w     1
operator  .ds.w     1
handle    .ds.w     1
akt_zeile .ds.l     1                   * aktuelle basic-zeile
b_modus   .ds.w     1                   * basicmodus (0=direkt, -1=prg.)
akt_adr   .ds.l     1
foreptr   .ds.l     1
goseptr   .ds.l     1
follchar  .ds.w     1                   * enthÑlt das zeichen hinter vgl-op.
work1     .ds.l     1                   * z.B. kopie end_strpuf
typ3flag  .ds.w     1
workop    .ds.w     1
ifendptr  .ds.l     1
ifcnt     .ds.w     1                   * anzahl der ifs in der akt. zeile
fnvarfl   .ds.w     1                   * 0=normale var, 13/14=funktionsvar
argfl     .ds.w     1                   * 0=normale var. -1=erst auf argvar chk
work2     .ds.l     1                   * ~ kopie von a0
inptr     .ds.l     1
onarg     .ds.l     1
oncmd     .ds.w     1
filefl    .ds.w     1
cmdfl     .ds.w     1
dataptr   .ds.l     1                   * zeigt auf nÑchstes data-element
dataadr   .ds.l     1                   * zeigt auf zeile des data-elements
restadr   .ds.l     1                   * adr fÅr restor
traceline	.ds.l	1
contline  .ds.l     1
contladr  .ds.l     1
contadr   .ds.l     1
sysvar    .ds.w     1                   * 0 wenn nicht/-1 pi/-2 ti/-3 ti$
sysallow  .ds.w     1
spstr     .ds.l     1
savereg   .ds.l     16                  * registerspeicher bei garbage
pgarbend  .ds.l     1
sbase     .ds.l     1

str_puf   .ds.l     1
str_pufend .ds.l    1

str_ptr   .ds.l     1
key:      .ds.l     1
key2:     .ds.w     1

dta_puf   .ds.b     50
var_name  .ds.b     80                  * max 80 zeichen fÅr eine var.
var2_name .ds.b     512                 * kopie des variablennamens (wenn erw.)
inputpuf  .ds.b     256
inputepuf:.ds.w	1
input_puf .ds.b     256
inpuf_end .ds.w     1                   * ende einer bs.zeile
          .ds.b     256                 * falls mit abgekÅrtzen cmd gearb.
inpuf2_end .ds.w    1
mirrorpuf	.ds.b	512				* in diesem puffer werden gespiegelte strings abeglegt!
mirrorpend:
sp_base:  .ds.l     5000
stack:    .ds.l     1
          .ds.l     1              * 4 nullen
fortable  .ds.b     100*42         * 100 for-next-schleifen ineinander mgl.
endfortbl      .ds.w     1
gostabl   .ds.b     100*12         * 100 gosubs ineinander mgl
endgostabl     .ds.w     1
iftbl:    .ds.b     100*4          * fÅr 100 ifs ineinander
endiftbl:      .ds.w     1
handtab:  .ds.b     100*4          * 100 file gleichzeitig offen!
endhtab:       .ds.w     1
qlist     .ds.l     250            * 250 eintrÑge in PSstackliste
maxspalten:
          .ds.l     1
fncnt:    .ds.w     1
fntyp:	.ds.w	1
proctblptr:	.ds.l	1
proctbl:		.ds.b	100*14
procetbl:		.ds.w	1
cmdfktfl:		.ds.w	1

AESctrl:	.ds.w	10
AESintin:	.ds.w	128
AESintout:.ds.w	128
AESadrin:	.ds.l	128
AESadrout:.ds.l	128
VDIctrl:	.ds.w	12
VDIintin:	.ds.w	128
VDIintout:.ds.w	128
VDIptsin:	.ds.w	128
VDIptsout:.ds.w	128
AESglobal:.ds.l	10
trx:	.ds.w	1
try:	.ds.w     1

autozeile:	.ds.l	1
autoadd:		.ds.l	1
autofl:		.ds.w	1	* default = 0 (aus)
