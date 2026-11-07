; -------------------------------------------------------------
; SpaceCan Step 07: static native ZX can-and-bar background.
; Artwork is unpacked once; only numbers are changed at runtime.
; -------------------------------------------------------------
DRAW_STATIC_UI:
    ; Draw the complete ZX screen, including a pure-black 16x20
    ; gameplay corridor. No images are ever copied during gameplay.
    CALL LOAD_SPACE_CAN_SCREEN

    ; Static ROM characters are painted ON TOP of blank HUD cells.
    ; They are not baked in the .SCR so their 8x8 pixels are crisp.
    LD BC,#0005                  ; title at Y=0, X=5
    LD DE,HUD_LABEL_TITLE
    CALL PRINT_TEXT
    LD BC,#0201                  ; SPEED
    LD DE,HUD_LABEL_SPEED
    CALL PRINT_TEXT
    LD BC,#020B                  ; SCORE
    LD DE,HUD_LABEL_SCORE
    CALL PRINT_TEXT
    LD BC,#0217                  ; LIVES
    LD DE,HUD_LABEL_LIVES
    CALL PRINT_TEXT

    ; Top-right pressure gauge, a fixed 8-cell HUD label.
    LD BC,#0118                  ; Y=1, X=24: "MISS  /3"
    LD DE,HUD_LABEL_MISSES
    JP PRINT_TEXT

; Decode RLE background directly into ZX bitmap and attributes.
; 00,count,value => repeat byte count times; nonzero => literal byte.
; IN: none. OUT: #4000..#5AFF = exactly 6912 screen bytes.
; DESTROYS: AF, BC, DE, HL. Caller has disabled interrupts.
LOAD_SPACE_CAN_SCREEN:
    LD HL,SPACE_CAN_SCREEN_RLE
    LD DE,#4000
.NEXT:
    LD A,(HL)
    INC HL
    OR A
    JR Z,.RUN_HEADER
    LD (DE),A
    INC DE
    JR .CHECK_END
.RUN_HEADER:
    LD B,(HL)                    ; run length always 1..255
    INC HL
    LD A,(HL)                    ; repeated byte
    INC HL
.REPEAT:
    LD (DE),A
    INC DE
    DJNZ .REPEAT
.CHECK_END:
    LD A,D
    CP #5B                       ; DE reached #5B00, end of attributes
    JR NZ,.NEXT
    RET

; Draw no more than 7 characters when a reading changes.
RENDER_HUD:
    LD A,(HUD_DIRTY)
    OR A
    RET Z
    XOR A
    LD (HUD_DIRTY),A

    LD A,(SCROLL_SPEED)
    ADD A,'0'
    LD BC,#0207                  ; SPEED number
    CALL DRAW_CHAR_AT

    LD HL,(SCORE)
    LD BC,#0210                  ; 5 digits: 00000..65535
    CALL PRINT_DEC5

    LD A,(SHIP_LIVES)
    ADD A,'0'
    LD BC,#021D                  ; lives 0..9
    CALL DRAW_CHAR_AT

    ; Warn in red when one more asteroid would cost a life.
    LD A,(MISSED_STREAK)
    CP MISSES_TO_DAMAGE-1
    LD A,#45                     ; bright cyan on black
    JR NZ,.MISS_ATTR_READY
    LD A,#42                     ; bright red at 2 consecutive misses
.MISS_ATTR_READY:
    LD (HUD_MISS_ATTR),A
    LD BC,#011D                  ; Y=1, X=29
    CALL GET_SCREEN_ADDR
    LD DE,HUD_MISS_ATTR
    CALL RESTORE_ATTR_1_1
    LD A,(MISSED_STREAK)
    ADD A,'0'
    LD BC,#011D
    JP DRAW_CHAR_AT

; IN HL=0..65535, BC=YX of leftmost digit.
; Four repeated divisions by 10^n, ending with the units.
; Dynamic HUD only: straightforward code is preferred to speed.
PRINT_DEC5:
    LD DE,10000
    CALL PRINT_DEC_PLACE
    LD DE,1000
    CALL PRINT_DEC_PLACE
    LD DE,100
    CALL PRINT_DEC_PLACE
    LD DE,10
    CALL PRINT_DEC_PLACE
    LD A,L
    ADD A,'0'
    JP DRAW_CHAR_AT

; IN HL=remainder, DE=decimal place, BC=YX.
; OUT HL=remainder after quotient, C advanced one screen column.
PRINT_DEC_PLACE:
    LD A,'0'
.NEXT:
    OR A                         ; clear carry before SBC HL,DE
    SBC HL,DE
    JR C,.WRITE
    INC A
    JR .NEXT
.WRITE:
    ADD HL,DE                    ; undo the final underflow
    PUSH HL
    PUSH DE
    PUSH BC
    CALL DRAW_CHAR_AT
    POP BC
    POP DE
    POP HL
    INC C
    RET

; IN BC=YX, DE=zero-terminated text.
PRINT_TEXT:
.NEXT:
    LD A,(DE)
    OR A
    RET Z
    PUSH BC
    PUSH DE
    CALL DRAW_CHAR_AT
    POP DE
    POP BC
    INC DE
    INC C
    JR .NEXT

; IN A=ASCII 32..127, BC=YX; draw 8 rows using Spectrum ROM font.
DRAW_CHAR_AT:
    SUB 32
    LD L,A
    LD H,0
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    LD DE,#3D00
    ADD HL,DE
    EX DE,HL
    CALL GET_SCREEN_ADDR
    JP DRAW_1_1
