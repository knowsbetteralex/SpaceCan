; -------------------------------------------------------------
; Static cockpit tiles, 8x8 bitmap + 1 ZX attribute byte per tile.
;
; A tile is a reusable GRAPHICAL UNIT: 8 bytes for its pixels,
; followed by one byte for PAPER/INK/BRIGHT. A tile map contains
; only tile IDs, not bitmap data (4x32 HUD, 20x6 each side).
;
; DRAW_TILE_ID: A=tile ID; BC=YX character position.
; Destroys AF,BC,DE,HL. Does not change IX/IY.
; -------------------------------------------------------------

T_PLATE            EQU 0
T_TOP_RAIL         EQU 1
T_TOP_LEFT         EQU 2
T_TOP_RIGHT        EQU 3
T_BOTTOM_RAIL      EQU 4
T_SEAM             EQU 5
T_DISPLAY          EQU 6
T_LIFE_ON          EQU 7
T_LIFE_OFF         EQU 8
T_SIDE_PLATE       EQU 9
T_SIDE_SPINE       EQU 10
T_SIDE_VENT        EQU 11
T_SIDE_BOLT        EQU 12
T_SIDE_LIGHT       EQU 13
T_SIDE_HAZARD      EQU 14
T_SIDE_DARK        EQU 15

DRAW_TILE_ID:
    PUSH BC
    LD L,A
    LD H,0
    ADD HL,HL                    ; table entries are DW (2 bytes)
    LD DE,TILE_POINTERS
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)                    ; DE -> tile's 8+1 bytes
    POP BC

    CALL GET_SCREEN_ADDR        ; HL -> ZX bitmap cell
    PUSH HL
    PUSH DE
    CALL DRAW_1_1               ; copies 8 bitmap rows
    POP DE                      ; restore tile start
    POP HL                      ; restore screen address

    EX DE,HL                    ; HL=tile start, DE=screen
    LD BC,8
    ADD HL,BC                   ; HL=attribute byte
    EX DE,HL                    ; DE=tile attribute, HL=screen
    JP RESTORE_ATTR_1_1

; General rectangular tile-map renderer.
; IN HL=map, B=top Y, C=left X, D=width, E=height.
; Static setup only, so we keep small loop variables in RAM.
DRAW_TILE_MAP:
    LD (TILE_MAP_CURSOR),HL
    LD (TILE_DRAW_POS),BC
    LD A,C
    LD (TILE_MAP_LEFT),A
    LD A,D
    LD (TILE_MAP_WIDTH),A
    LD A,E
    LD (TILE_ROWS_LEFT),A
.ROW:
    LD A,(TILE_MAP_WIDTH)
    LD (TILE_COLS_LEFT),A
.COL:
    LD HL,(TILE_MAP_CURSOR)
    LD A,(HL)                   ; one tile ID
    INC HL
    LD (TILE_MAP_CURSOR),HL
    LD BC,(TILE_DRAW_POS)
    CALL DRAW_TILE_ID

    LD HL,TILE_DRAW_POS         ; low byte is X
    INC (HL)
    LD HL,TILE_COLS_LEFT
    DEC (HL)
    JR NZ,.COL

    LD A,(TILE_MAP_LEFT)
    LD (TILE_DRAW_POS),A        ; reset X, keep Y
    LD HL,TILE_DRAW_POS+1
    INC (HL)                    ; next character row
    LD HL,TILE_ROWS_LEFT
    DEC (HL)
    JR NZ,.ROW
    RET

TILE_MAP_CURSOR: DW 0
TILE_DRAW_POS:  DW 0           ; X in low byte, Y in high byte
TILE_MAP_LEFT:  DB 0
TILE_MAP_WIDTH: DB 0
TILE_COLS_LEFT: DB 0
TILE_ROWS_LEFT: DB 0

TILE_POINTERS:
    DW TILE_PLATE,TILE_TOP_RAIL,TILE_TOP_LEFT,TILE_TOP_RIGHT,TILE_BOTTOM_RAIL,TILE_SEAM,TILE_DISPLAY,TILE_LIFE_ON,TILE_LIFE_OFF,TILE_SIDE_PLATE,TILE_SIDE_SPINE,TILE_SIDE_VENT,TILE_SIDE_BOLT,TILE_SIDE_LIGHT,TILE_SIDE_HAZARD,TILE_SIDE_DARK

TILE_PLATE:
    DB #00,#42,#00,#00,#00,#00,#42,#00
    DB #41

TILE_TOP_RAIL:
    DB #FF,#81,#00,#00,#00,#00,#00,#00
    DB #45

TILE_TOP_LEFT:
    DB #FF,#C0,#A0,#90,#88,#84,#82,#81
    DB #45

TILE_TOP_RIGHT:
    DB #FF,#03,#05,#09,#11,#21,#41,#81
    DB #45

TILE_BOTTOM_RAIL:
    DB #00,#00,#00,#00,#00,#00,#81,#FF
    DB #45

TILE_SEAM:
    DB #18,#18,#18,#18,#18,#18,#18,#18
    DB #42

TILE_DISPLAY:
    DB #00,#00,#00,#00,#00,#00,#00,#00
    DB #47

TILE_LIFE_ON:
    DB #18,#3C,#7E,#DB,#FF,#7E,#3C,#18
    DB #44

TILE_LIFE_OFF:
    DB #18,#24,#42,#81,#81,#42,#24,#18
    DB #01

TILE_SIDE_PLATE:
    DB #81,#00,#00,#24,#00,#00,#00,#81
    DB #41

TILE_SIDE_SPINE:
    DB #18,#18,#18,#18,#18,#18,#18,#18
    DB #45

TILE_SIDE_VENT:
    DB #00,#7E,#00,#7E,#00,#7E,#00,#00
    DB #45

TILE_SIDE_BOLT:
    DB #00,#00,#18,#3C,#3C,#18,#00,#00
    DB #46

TILE_SIDE_LIGHT:
    DB #00,#18,#3C,#7E,#7E,#3C,#18,#00
    DB #44

TILE_SIDE_HAZARD:
    DB #80,#C0,#60,#30,#18,#0C,#06,#03
    DB #46

TILE_SIDE_DARK:
    DB #00,#00,#00,#00,#00,#00,#00,#00
    DB #41

; 4 x 32 = 128 reusable tile IDs, not 1024 bitmap bytes.
; Side maps: 20 x 6 each, drawn once during initialization.
HUD_TILE_MAP:
    DB 2,1,1,1,12,1,1,1,1,1,1,1,1,1,1,12,1,1,1,1,1,1,1,1,1,1,12,1,1,1,1,3  ; row 0
    DB 5,0,0,0,0,0,0,0,0,0,0,5,0,0,0,0,0,0,0,0,0,0,5,0,0,0,0,0,0,0,0,5  ; row 1
    DB 5,0,0,0,0,0,0,6,0,0,0,5,0,0,0,0,6,6,0,0,0,0,5,0,0,8,8,8,8,0,0,5  ; row 2
    DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4  ; row 3

SIDE_LEFT_TILE_MAP:
    DB 10,12,9,9,11,10  ; row 0
    DB 10,9,9,14,9,10  ; row 1
    DB 10,11,9,9,13,10  ; row 2
    DB 10,9,12,9,9,10  ; row 3
    DB 10,12,9,9,11,10  ; row 4
    DB 10,9,9,14,9,10  ; row 5
    DB 10,11,9,9,13,10  ; row 6
    DB 10,9,12,9,9,10  ; row 7
    DB 10,12,9,9,11,10  ; row 8
    DB 10,9,9,14,9,10  ; row 9
    DB 10,11,9,9,13,10  ; row 10
    DB 10,9,12,9,9,10  ; row 11
    DB 10,12,9,9,11,10  ; row 12
    DB 10,9,9,14,9,10  ; row 13
    DB 10,11,9,9,13,10  ; row 14
    DB 10,9,12,9,9,10  ; row 15
    DB 10,12,9,9,11,10  ; row 16
    DB 10,9,9,14,9,10  ; row 17
    DB 10,11,9,9,13,10  ; row 18
    DB 10,9,12,9,9,10  ; row 19

SIDE_RIGHT_TILE_MAP:
    DB 10,11,9,9,12,10  ; row 0
    DB 10,9,14,9,9,10  ; row 1
    DB 10,13,9,9,11,10  ; row 2
    DB 10,9,9,12,9,10  ; row 3
    DB 10,11,9,9,12,10  ; row 4
    DB 10,9,14,9,9,10  ; row 5
    DB 10,13,9,9,11,10  ; row 6
    DB 10,9,9,12,9,10  ; row 7
    DB 10,11,9,9,12,10  ; row 8
    DB 10,9,14,9,9,10  ; row 9
    DB 10,13,9,9,11,10  ; row 10
    DB 10,9,9,12,9,10  ; row 11
    DB 10,11,9,9,12,10  ; row 12
    DB 10,9,14,9,9,10  ; row 13
    DB 10,13,9,9,11,10  ; row 14
    DB 10,9,9,12,9,10  ; row 15
    DB 10,11,9,9,12,10  ; row 16
    DB 10,9,14,9,9,10  ; row 17
    DB 10,13,9,9,11,10  ; row 18
    DB 10,9,9,12,9,10  ; row 19
