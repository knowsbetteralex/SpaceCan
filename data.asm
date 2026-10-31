; -------------------------------------------------------------
; Sprites and state
; -------------------------------------------------------------
BG_ATTR:
    DB #47                     ; bright white on black; corridor only

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
SHIP_BG_ATTR:
    DS 2,0
SHIP_BG_BITMAP:
    DS 16,0

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
BLAST_FRAME:
    DB 0
BLAST_ANIM_TIMER:
    DB BLAST_FRAME_DURATION
BLAST_POS:
    DB 0,0
BLAST_FRAME_PTR:
    DW BLAST_FRAME_0
BLAST_BG_ATTR:
    DS 2,0
BLAST_BG_BITMAP:
    DS 16,0
BLAST_ATTR:
    DB #07,#07
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
; Step 01: UI and input state.
; -------------------------------------------------------------
SCROLL_SPEED:      DB 1        ; 1..4, background will use later
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
