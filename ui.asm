; -------------------------------------------------------------
; SpaceCan Step 21: HUD + blinking SHOOT! warning after 1 missed screen.
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
    ; Middle window Y=2, X=14..17: four heart sprites.
    ; Right window Y=2, X=25..30: 6 score digits, without label.

    ; Gauge at Y=3, X=11..20, centered over the corridor.
    ; Its bitmap is static; only the 10 attribute bytes change.
    CALL DRAW_PRESSURE_BAR

    ; Save original Y=2, X=13..18 pixels/attrs (between hearts and
    ; gauge); flashing text must not destroy the .SCR decoration.
    JP SAVE_SHOOT_BACKGROUND

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

; Dynamic HUD updates only when values change.
RENDER_HUD:
    LD A,(HUD_DIRTY)
    OR A
    JR Z,.GAUGE
    XOR A
    LD (HUD_DIRTY),A

    ; Left window: 1 / 1.5 / 2 / 2.5 / 3, clearing the old suffix.
    LD A,(SCROLL_SPEED)
    ADD A,'0'
    LD BC,#0207
    CALL DRAW_CHAR_AT
    LD A,(SPEED_LEVEL)
    AND 1
    JR Z,.WHOLE_SPEED
    LD A,'.'
    LD BC,#0208
    CALL DRAW_CHAR_AT
    LD A,'5'
    JR .SPEED_SUFFIX
.WHOLE_SPEED:
    LD A,' '
    LD BC,#0208
    CALL DRAW_CHAR_AT
    LD A,' '
.SPEED_SUFFIX:
    LD BC,#0209
    CALL DRAW_CHAR_AT

    ; Middle window: 4 filled/hollow hearts at X=14..17.
    CALL DRAW_LIVES_HEARTS

    ; Right window: six actual decimal digits, 000000..999999.
    LD BC,#0219                  ; Y=2, X=25
    CALL PRINT_DEC6
.GAUGE:
    LD A,(GAUGE_DIRTY)
    OR A
    JR Z,.WARNING
    XOR A
    LD (GAUGE_DIRTY),A
    CALL RENDER_PRESSURE_GAUGE
.WARNING:
    ; Called every active game frame, independent of HUD_DIRTY.
    JP RENDER_SHOOT_WARNING

; Warning between hearts (actual draw row Y=1) and gauge (Y=3).
; No bitmap writes from IM2: blink in the foreground, paused game freezes.
; OFF restores exact bitmap and attributes, rather than painting spaces.
RENDER_SHOOT_WARNING:
    LD A,(SHOOT_WARNING_ACTIVE)
    OR A
    JR Z,.HIDE
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    JR NZ,.HIDE
    LD HL,SHOOT_BLINK_COUNTER
    INC (HL)
    LD A,(HL)
    AND SHOOT_BLINK_MASK
    JR NZ,.HIDE
    LD A,(SHOOT_VISIBLE)
    OR A
    RET NZ                       ; no redraw on an unchanged blink frame
    LD A,1
    LD (SHOOT_VISIBLE),A
    LD BC,SHOOT_TEXT_Y*256+SHOOT_TEXT_X
    LD DE,HUD_LABEL_SHOOT
    CALL PRINT_TEXT
    LD HL,#5800+SHOOT_TEXT_Y*32+SHOOT_TEXT_X
    LD B,SHOOT_TEXT_WIDTH
    LD A,#46                     ; bright yellow on black
.ATTR:
    LD (HL),A
    INC HL
    DJNZ .ATTR
    RET
.HIDE:
    LD A,(SHOOT_VISIBLE)
    OR A
    RET Z
    XOR A
    LD (SHOOT_VISIBLE),A
    JP RESTORE_SHOOT_BACKGROUND

; Capture the six cells directly from the original .SCR HUD.
; Called every DRAW_STATIC_UI, including after respawn/Game Over.
SAVE_SHOOT_BACKGROUND:
    LD DE,SHOOT_SAVED_BITMAP
    LD C,SHOOT_TEXT_X
    LD A,SHOOT_TEXT_WIDTH
.NEXT_CELL:
    PUSH AF
    PUSH BC
    LD B,SHOOT_TEXT_Y
    CALL GET_SCREEN_ADDR
    LD B,8
.NEXT_ROW:
    LD A,(HL)
    LD (DE),A
    INC DE
    INC H
    DJNZ .NEXT_ROW
    POP BC
    INC C
    POP AF
    DEC A
    JR NZ,.NEXT_CELL
    LD HL,#5800+SHOOT_TEXT_Y*32+SHOOT_TEXT_X
    LD DE,SHOOT_SAVED_ATTR
    LD BC,SHOOT_TEXT_WIDTH
    LDIR
    XOR A
    LD (SHOOT_VISIBLE),A
    RET

; Recover all original pixels/attrs underneath the word.
RESTORE_SHOOT_BACKGROUND:
    LD DE,SHOOT_SAVED_BITMAP
    LD C,SHOOT_TEXT_X
    LD A,SHOOT_TEXT_WIDTH
.NEXT_CELL:
    PUSH AF
    PUSH BC
    LD B,SHOOT_TEXT_Y
    CALL GET_SCREEN_ADDR
    LD B,8
.NEXT_ROW:
    LD A,(DE)
    LD (HL),A
    INC DE
    INC H
    DJNZ .NEXT_ROW
    POP BC
    INC C
    POP AF
    DEC A
    JR NZ,.NEXT_CELL
    LD HL,SHOOT_SAVED_ATTR
    LD DE,#5800+SHOOT_TEXT_Y*32+SHOOT_TEXT_X
    LD BC,SHOOT_TEXT_WIDTH
    LDIR
    RET

; Draw four hearts in Y=1, X=14..17. Each slot index is compared
; to remaining SHIP_LIVES; lost lives remain visible as outlines.
DRAW_LIVES_HEARTS:
    LD C,14
    LD A,START_LIVES
.NEXT_HEART:
    PUSH AF
    PUSH BC
    LD B,1
    CALL GET_SCREEN_ADDR
    LD A,(SHIP_LIVES)
    ADD A,14
    CP C
    JR C,.SPENT
    JR Z,.SPENT
    LD DE,HEART_FILLED
    PUSH DE
    LD DE,HEART_ACTIVE_ATTR
    CALL RESTORE_ATTR_1_1
    POP DE
    JR .DRAW
.SPENT:
    LD DE,HEART_OUTLINE
    PUSH DE
    LD DE,HEART_SPENT_ATTR
    CALL RESTORE_ATTR_1_1
    POP DE
.DRAW:
    CALL DRAW_1_1
    POP BC
    INC C
    POP AF
    DEC A
    JR NZ,.NEXT_HEART
    RET

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

; Draw six digits of 24-bit SCORE (little endian) in decimal.
; IN BC=YX of first digit. Scratch is SCORE_PRINT_WORK; SCORE is kept.
; This routine runs only on HUD updates or in Game Over.
PRINT_DEC6:
    LD HL,(SCORE)
    LD (SCORE_PRINT_WORK),HL
    LD A,(SCORE+2)
    LD (SCORE_PRINT_WORK+2),A
    LD IX,SCORE_DECIMAL_PLACES
    LD A,5                        ; five 24-bit divisors, then units
.NEXT_PLACE:
    PUSH AF
    CALL PRINT_DEC24_PLACE
    LD DE,3
    ADD IX,DE
    POP AF
    DEC A
    JR NZ,.NEXT_PLACE
    LD A,(SCORE_PRINT_WORK)       ; final remainder is 0..9
    ADD A,'0'
    JP DRAW_CHAR_AT

; IN IX -> three-byte divisor, BC=YX. Draws one digit, increments C.
; Each place subtracts at most nine times. Preserves IX and B.
PRINT_DEC24_PLACE:
    LD D,'0'
.TRY:
    LD A,(SCORE_PRINT_WORK+2)
    CP (IX+2)
    JR C,.WRITE
    JR NZ,.SUBTRACT
    LD A,(SCORE_PRINT_WORK+1)
    CP (IX+1)
    JR C,.WRITE
    JR NZ,.SUBTRACT
    LD A,(SCORE_PRINT_WORK)
    CP (IX+0)
    JR C,.WRITE
.SUBTRACT:
    LD A,(SCORE_PRINT_WORK)
    SUB (IX+0)
    LD (SCORE_PRINT_WORK),A
    LD A,(SCORE_PRINT_WORK+1)
    SBC A,(IX+1)
    LD (SCORE_PRINT_WORK+1),A
    LD A,(SCORE_PRINT_WORK+2)
    SBC A,(IX+2)
    LD (SCORE_PRINT_WORK+2),A
    INC D
    JR .TRY
.WRITE:
    LD A,D
    PUSH BC
    CALL DRAW_CHAR_AT
    POP BC
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
