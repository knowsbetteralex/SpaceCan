; -------------------------------------------------------------
; 4-row cockpit HUD and 20-row static side-hull tile pictures.
; Dynamic values update only when HUD_DIRTY is set.
; Existing SHIP_HP 100/75/50/25/0 -> 4/3/2/1/0 life tiles.
; -------------------------------------------------------------
DRAW_STATIC_UI:
    LD HL,HUD_TILE_MAP
    LD BC,#0000
    LD DE,#2004                 ; 32 x 4 HUD
    CALL DRAW_TILE_MAP

    LD HL,SIDE_LEFT_TILE_MAP
    LD BC,#0400                 ; left side: X=0, Y=4
    LD DE,#0614                 ; 6 x 20
    CALL DRAW_TILE_MAP

    LD HL,SIDE_RIGHT_TILE_MAP
    LD BC,#041A                 ; right side: X=26, Y=4
    LD DE,#0614
    CALL DRAW_TILE_MAP

    LD BC,#0102
    LD DE,HUD_LABEL_SPEED
    CALL PRINT_TEXT
    LD BC,#010D
    LD DE,HUD_LABEL_SCORE
    CALL PRINT_TEXT
    LD BC,#0118
    LD DE,HUD_LABEL_LIVES
    JP PRINT_TEXT

RENDER_HUD:
    LD A,(HUD_DIRTY)
    OR A
    RET Z
    XOR A
    LD (HUD_DIRTY),A

    LD A,(SCROLL_SPEED)
    ADD A,'0'
    LD BC,#0207                 ; speed (row 2, X=7)
    CALL DRAW_CHAR_AT

    LD A,(SCORE)
    LD BC,#0210                 ; score (row 2, X=16-17)
    CALL PRINT_DEC2

    ; Four shield tiles (X=25..28). Thresholds 25,50,75,100.
    LD BC,#0219
    LD D,25
    LD E,4
.LIVES:
    PUSH BC
    PUSH DE
    LD A,(SHIP_HP)
    CP D
    LD A,T_LIFE_OFF
    JR C,.DRAW_LIFE
    LD A,T_LIFE_ON
.DRAW_LIFE:
    CALL DRAW_TILE_ID
    POP DE
    POP BC
    INC C
    LD A,D
    ADD A,25
    LD D,A
    DEC E
    JR NZ,.LIVES
    RET

; IN: A=0..99, BC=first digit coordinate (Y in B, X in C).
PRINT_DEC2:
    LD D,0
.TENS:
    CP 10
    JR C,.WRITE
    SUB 10
    INC D
    JR .TENS
.WRITE:
    PUSH AF
    LD A,D
    ADD A,'0'
    PUSH BC
    CALL DRAW_CHAR_AT
    POP BC
    INC C
    POP AF
    ADD A,'0'
    JP DRAW_CHAR_AT

; ROM font glyphs are also 8x8 bitmap tiles, starting at #3D00.
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

; IN: A=ASCII 32..127, BC=screen YX.
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
