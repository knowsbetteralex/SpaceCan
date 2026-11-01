; -------------------------------------------------------------
; Sprites and state
; -------------------------------------------------------------
BG_ATTR:
    DB #47                     ; bright white on black; corridor only
BG_ATTR_PAIR:
    DB #47,#47                 ; default attributes for 2-cell clear

SHIP_START_POS:
    DB 15,22

SHIP_SPRITE:
    DB #01,#80
    DB #03,#C0
    DB #1F,#F8
    DB #7F,#FE
    DB #FF,#FF
    DB #ED,#B7
    DB #44,#22
    DB #04,#20
SHIP_ATTR:
    DB #46,#46                 ; bright yellow on black
SHIP_CUR_POS:
    DB 15,22                   ; last painted position
SHIP_NEW_POS:
    DB 15,22                   ; logical target
SHIP_DRAWN:
    DB 0

SHIP_HP:
    DB 100                      ; 100 -> 75 -> 50 -> 25 -> 0

; Four fixed lanes; no two enemies intersect horizontally.
ENEMY_START_TABLE:
    ; TYPE, X, Y, initial animation timer (1..4).
    DB 0,8,2,1                  ; small, phase 1
    DB 1,12,11,2                ; large, phase 2
    DB 0,19,5,3                 ; small, phase 3
    DB 1,23,16,4                ; large, phase 4

ENEMY_MOVE_TIMER:
    DB 4
ENEMY_MOVE_NOW:
    DB 0

ENEMY_POOL:
    DS MAX_ENEMIES*ENEMY_SLOT_SIZE,0

ENEMY_ATTR_SMALL:
    DB #42                      ; bright red
ENEMY_ATTR_LARGE:
    DB #45,#45                  ; bright cyan

ENEMY_FRAMES:
    DW ENEMY_SMALL_0,ENEMY_SMALL_1
    DW ENEMY_LARGE_0,ENEMY_LARGE_1

; Every frame is two character rows high (top then bottom).
; Small frame: 16 bytes = 1x2. Large frame: 32 bytes = 2x2.
ENEMY_SMALL_0:
    DB %00000000
    DB %00011000
    DB %00111100
    DB %01111110
    DB %01110110
    DB %11111111
    DB %11011111
    DB %11110111
    DB %11111111
    DB %11101111
    DB %01111110
    DB %01111010
    DB %00111100
    DB %00111100
    DB %00011000
    DB %00000000

ENEMY_SMALL_1:
    DB %00000000
    DB %00001100
    DB %00111110
    DB %01111110
    DB %01101111
    DB %11111111
    DB %11110111
    DB %11011111
    DB %11111110
    DB %11101110
    DB %01111110
    DB %01011100
    DB %00111100
    DB %00011100
    DB %00011000
    DB %00000000

ENEMY_LARGE_0:
    DB #00,#00
    DB #00,#C0
    DB #03,#F0
    DB #0F,#FC
    DB #1F,#FE
    DB #3F,#FF
    DB #7F,#FF
    DB #7B,#EF
    DB #FF,#FF
    DB #EF,#BF
    DB #FF,#FF
    DB #7F,#FE
    DB #3F,#FC
    DB #1F,#F8
    DB #07,#E0
    DB #01,#80

ENEMY_LARGE_1:
    DB #00,#00
    DB #01,#80
    DB #07,#E0
    DB #1F,#F8
    DB #3F,#FC
    DB #7F,#FE
    DB #FF,#FF
    DB #FD,#DF
    DB #F7,#EF
    DB #FF,#FF
    DB #FB,#DF
    DB #7F,#FE
    DB #3F,#FC
    DB #0F,#F0
    DB #03,#C0
    DB #00,#00

BULLET_COUNT:
    DB 0                        ; active bullets (0..6)
; All state/last-screen-position/background are stored in each slot.
BULLET_POOL:
    DS MAX_BULLETS*BULLET_SLOT_SIZE,0
BULLET_SPRITE:
    DB %00011000
    DB %00011000
    DB %00111100
    DB %00111100
    DB %00111100
    DB %00111100
    DB %00011000
    DB %00011000
BULLET_ATTR:
    DB #47                     ; bright white on black

BLAST_ACTIVE:
    DB 0
BLAST_DRAWN:
    DB 0
BLAST_TYPE:
    DB 0                        ; 0=8x8 for small, 1=16x8 for large
BLAST_FRAME:
    DB 0
BLAST_ANIM_TIMER:
    DB BLAST_FRAME_DURATION
BLAST_POS:
    DB 0,0                      ; original asteroid X/Y, NO offset
BLAST_FRAME_PTR:
    DW BLAST_FRAME_0
BLAST_ATTR_SMALL:
    DB #07
BLAST_ATTR:
    DB #07,#07
BLAST_SMALL_FRAMES:
    DW BLAST_SMALL_0,BLAST_SMALL_1,BLAST_SMALL_2,BLAST_SMALL_3

BLAST_SMALL_0:
    DB %00000000
    DB %00000000
    DB %00011000
    DB %00111100
    DB %00111100
    DB %00011000
    DB %00000000
    DB %00000000
BLAST_SMALL_1:
    DB %00000000
    DB %01011010
    DB %00111100
    DB %01111110
    DB %01111110
    DB %00111100
    DB %01011010
    DB %00000000
BLAST_SMALL_2:
    DB %10000001
    DB %00100100
    DB %00011000
    DB %01000010
    DB %01000010
    DB %00011000
    DB %00100100
    DB %10000001
BLAST_SMALL_3:
    DB %00000000
    DB %01000010
    DB %00000000
    DB %00010000
    DB %00001000
    DB %00000000
    DB %01000010
    DB %00000000

BLAST_FRAMES:
    DW BLAST_FRAME_0,BLAST_FRAME_1,BLAST_FRAME_2,BLAST_FRAME_3

BLAST_FRAME_0:
    DB $00,$00
    DB $00,$00
    DB $01,$80
    DB $03,$C0
    DB $03,$C0
    DB $01,$80
    DB $00,$00
    DB $00,$00
BLAST_FRAME_1:
    DB $01,$80
    DB $08,$10
    DB $05,$A0
    DB $43,$C2
    DB $43,$C2
    DB $05,$A0
    DB $08,$10
    DB $01,$80
BLAST_FRAME_2:
    DB $80,$01
    DB $10,$08
    DB $20,$04
    DB $01,$00
    DB $00,$80
    DB $20,$04
    DB $10,$08
    DB $80,$01
BLAST_FRAME_3:
    DB $00,$00
    DB $40,$04
    DB $01,$00
    DB $00,$00
    DB $00,$80
    DB $00,$00
    DB $20,$01
    DB $00,$00

; Individual dirty flags for static target, blast, and player.
; Bullet dirty state is inside each bullet slot.
BLAST_DIRTY:     DB 0
SHIP_DIRTY:      DB 1

; -------------------------------------------------------------
; Moving starfield: 24 points, three motion rates.
; Each record: X cell, Y pixel (16..191), pixel bit, period mask.
; -------------------------------------------------------------
STAR_CLOCK:    DB 0
DIRTY_COUNT:   DB 0
DIRTY_TAIL:    DW DIRTY_QUEUE
DIRTY_MAP:     DS 768,0
DIRTY_QUEUE:   DS 320,0          ; 160 unique character cells

STAR_POOL:
    ; Nearest: 2*SCROLL_SPEED pixels each frame.
    DB 7,20,#10,0
    DB 10,90,#02,0
    DB 14,156,#40,0
    DB 18,28,#08,0
    DB 22,124,#01,0
    DB 25,180,#20,0
    DB 12,64,#04,0
    DB 20,104,#80,0

    ; Mid layer: SCROLL_SPEED pixels every two frames.
    DB 6,73,#10,1
    DB 9,150,#01,1
    DB 13,43,#02,1
    DB 16,170,#08,1
    DB 19,84,#20,1
    DB 23,37,#04,1
    DB 8,114,#40,1
    DB 24,141,#02,1

    ; Far layer: SCROLL_SPEED pixels every four frames.
    DB 7,178,#80,3
    DB 11,22,#08,3
    DB 15,128,#10,3
    DB 17,66,#01,3
    DB 21,152,#20,3
    DB 25,98,#04,3
    DB 10,52,#40,3
    DB 19,186,#02,3

; -------------------------------------------------------------
; Input and HUD state.
; -------------------------------------------------------------
SCROLL_SPEED:      DB 1        ; 1..4, multiplier for stars and asteroid speed
SCORE:             DB 0        ; demo score 0..99
HUD_DIRTY:         DB 1        ; dynamic numeric labels need redraw
SPACE_HELD:        DB 0        ; key edge detection
SPEED_UP_HELD:     DB 0
SPEED_DOWN_HELD:   DB 0

HUD_TEXT_0:    DB "SCORE 00    SPEED 1    HP 100",0
HUD_TEXT_1:    DB "ZX SPACE DEMO     O/P Q/A SPACE",0
LEFT_TEXT_0:  DB "SPEED",0
LEFT_TEXT_1:  DB "0",0
LEFT_TEXT_2:  DB "SHIP",0
RIGHT_TEXT_0: DB "SECTOR",0
RIGHT_TEXT_1: DB "01",0
RIGHT_TEXT_2: DB "SHOTS",0

PROGRAM_END:
