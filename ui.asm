; -------------------------------------------------------------
; SpaceCan Step 06: "Space Soda 0.33 L" static can/wall/bar mural.
; Top 4 rows: HUD (32x4). Sides: wall + can, 8x20 each.
; Only digital SPEED / SCORE / LIVES change at runtime.
; -------------------------------------------------------------
DRAW_STATIC_UI:
    LD HL,HUD_TILE_MAP
    LD BC,#0000
    LD DE,#2004                  ; 32x4
    CALL DRAW_TILE_MAP

    LD HL,CAN_LEFT_TILE_MAP
    LD BC,#0400                  ; Y=4, X=0
    LD DE,#0814                  ; 8x20
    CALL DRAW_TILE_MAP

    LD HL,CAN_RIGHT_TILE_MAP
    LD BC,#0418                  ; Y=4, X=24
    LD DE,#0814                  ; 8x20
    CALL DRAW_TILE_MAP

    ; ROM font characters are also 8x8 tiles.
    LD BC,#000B                  ; top chrome rail
    LD DE,HUD_LABEL_TITLE
    CALL PRINT_TEXT

    LD BC,#0102
    LD DE,HUD_LABEL_SPEED
    CALL PRINT_TEXT
    LD BC,#010C
    LD DE,HUD_LABEL_SCORE
    CALL PRINT_TEXT
    LD BC,#0119
    LD DE,HUD_LABEL_LIVES
    CALL PRINT_TEXT

    ; Label fragments on either side of the black playfield.
    LD BC,#0904                  ; left can X=4..6
    LD DE,CAN_LABEL_LEFT
    CALL PRINT_TEXT
    LD BC,#0919                  ; right can X=25..27
    LD DE,CAN_LABEL_RIGHT
    CALL PRINT_TEXT
    LD BC,#0619                  ; 0.33 as a small can mark
    LD DE,CAN_LABEL_VOLUME
    JP PRINT_TEXT

; Draw no more than 7 characters when a reading changes.
RENDER_HUD:
    LD A,(HUD_DIRTY)
    OR A
    RET Z
    XOR A
    LD (HUD_DIRTY),A

    LD A,(SCROLL_SPEED)
    ADD A,'0'
    LD BC,#0205                  ; SPEED
    CALL DRAW_CHAR_AT

    LD HL,(SCORE)
    LD BC,#020C                  ; 5 digits: 00000..65535
    CALL PRINT_DEC5

    LD A,(SHIP_LIVES)
    ADD A,'0'
    LD BC,#021B                  ; lives 0..9
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
