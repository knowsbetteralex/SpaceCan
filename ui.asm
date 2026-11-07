; -------------------------------------------------------------
; SpaceCan Step 11: static can background with 10-cell pressure gauge.
; RLE artwork is unpacked once; only HUD numerals/attributes change.
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

    ; Gauge at Y=3, X=11..20, centered over the corridor.
    ; Its bitmap is static; only the 10 attribute bytes change.
    JP DRAW_PRESSURE_BAR

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
    JR Z,.GAUGE
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
.GAUGE:
    LD A,(GAUGE_DIRTY)
    OR A
    RET Z
    XOR A
    LD (GAUGE_DIRTY),A
    JP RENDER_PRESSURE_GAUGE

; Print a narrow bright pixel bar in the topmost corridor border.
; First clear the original .SCR bitmap in exactly 10 cells, then
; draw a fixed 8-row glyph to give each attribute its own visible bar.
DRAW_PRESSURE_BAR:
    LD C,11                      ; centered 10 cells (X=11..20)
    LD A,PRESSURE_SEGMENTS
.NEXT:
    PUSH AF
    PUSH BC
    LD B,3                       ; directly above playfield top (Y=4)
    CALL GET_SCREEN_ADDR
    LD DE,PRESSURE_SEGMENT_PIXELS
    CALL DRAW_1_1
    POP BC
    INC C
    POP AF
    DEC A
    JR NZ,.NEXT
    XOR A
    LD (GAUGE_DIRTY),A
    JP RENDER_PRESSURE_GAUGE

; Only 10 attribute writes per penalty. Green on the left,
; red grows from the RIGHT. Full red is shown during the blast.
RENDER_PRESSURE_GAUGE:
    LD A,(PRESSURE_LEVEL)
    LD B,A
    LD C,PRESSURE_SEGMENTS
    LD HL,#5800+3*32+11
.NEXT:
    LD A,C
    CP B
    JR C,.RED
    JR Z,.RED
    LD A,#44                     ; bright green ink / black paper
    JR .STORE
.RED:
    LD A,#42                     ; bright red ink / black paper
.STORE:
    LD (HL),A
    INC HL
    DEC C
    JR NZ,.NEXT
    RET

PRESSURE_SEGMENT_PIXELS:
    DB #00,#7E,#7E,#7E,#7E,#7E,#7E,#00

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
