; -------------------------------------------------------------
; Sprites and state
; -------------------------------------------------------------
BG_ATTR:
    DB #47                     ; bright white on black; corridor only
BG_ATTR_PAIR:
    DB #47,#47                 ; default attributes for 2-cell clear

SHIP_START_POS:
    DB 15,22

SHIP_FRAMES:
    ; Five 8x8 poses, from hard left (0) to hard right (4).
    DW SHIP_BANK_LEFT_HARD,SHIP_BANK_LEFT_SOFT,SHIP_SPRITE
    DW SHIP_BANK_RIGHT_SOFT,SHIP_BANK_RIGHT_HARD

SHIP_BANK_LEFT_HARD:
    DB %00110000
    DB %01111000
    DB %11111100
    DB %11111110
    DB %01111100
    DB %00110100
    DB %00011000
    DB %00010000

SHIP_BANK_LEFT_SOFT:
    DB %00011000
    DB %00111100
    DB %01111110
    DB %11111110
    DB %01111110
    DB %00101100
    DB %00011000
    DB %00010000

SHIP_SPRITE:
    DB %00011000
    DB %00111100
    DB %00111100
    DB %01111110
    DB %11111111
    DB %11011011
    DB %00011000
    DB %00011000

SHIP_BANK_RIGHT_SOFT:
    DB %00011000
    DB %00111100
    DB %01111110
    DB %01111111
    DB %01111110
    DB %00110100
    DB %00011000
    DB %00001000

SHIP_BANK_RIGHT_HARD:
    DB %00001100
    DB %00011110
    DB %00111111
    DB %01111111
    DB %00111110
    DB %00101100
    DB %00011000
    DB %00001000

SHIP_ATTR:
    DB #46                      ; bright yellow on black
SHIP_ATTR_PAIR:
    DB #46,#46                  ; when shifted, ship spans 2 cells
SHIP_CUR_POS:
    DB 15,22                   ; last drawn character X / Y
SHIP_CUR_HALF:
    DB 0                       ; last drawn 4px offset (0 or 1)
SHIP_NEW_POS:
    DB 15,22                   ; logical base cell X / Y
SHIP_HALF_POS:
    DB 0                       ; current 4px offset (0 or 1)
SHIP_BANK:
    DB 2                         ; 0..4, neutral = 2
SHIP_BANK_TARGET:
    DB 2                         ; desired pose from O/P
SHIP_BANK_TIMER:
    DB 0                         ; frames until next pose update
SHIP_BANK_HOLD_TIMER:
    DB 0                         ; pause before leveling after key release
SHIP_DRAWN:
    DB 0
SHIP_VISIBLE:
    DB 1                       ; 0 during ship explosion

GAME_STATE:
    DB STATE_MENU               ; menu / playing / exploding / respawn / over

SHIP_LIVES:
    DB START_LIVES              ; 4 initially; collisions only decrease
MISSED_STREAK:
    DB 0                        ; 0..2 escaped objects; 3rd costs life
HUD_MISS_ATTR:
    DB #45                      ; cyan normally, red at 2 missed
SHIP_MOVE_TIMER:
    DB 0                        ; frames until next horizontal step

; Four independent falling objects. On EVERY spawn, X is
; freshly selected in the full corridor using an 8-bit LFSR.
; The initial table stores only TYPE, START_Y, ANIMATION_PHASE.
ENEMY_START_TABLE:
    DB 0,4,1                    ; small 8x8, first animation in 1 tick
    DB 1,11,3                   ; large, first animation in 3 ticks
    DB 0,17,5                   ; small, first animation in 5 ticks

ENEMY_MOVE_TIMER:
    DB 4
ENEMY_MOVE_NOW:
    DB 0

ENEMY_RANDOM_STATE:
    DB #A7                      ; reseeded by LD A,R during startup
ENEMY_TEST_X:
    DB 0                        ; temporary spawn-overlap data
ENEMY_TEST_TYPE:
    DB 0
ENEMY_TEST_Y:
    DB 0

ENEMY_POOL:
    DS MAX_ENEMIES*ENEMY_SLOT_SIZE,0

ENEMY_ATTR_SMALL:
    DB #42                      ; bright red
ENEMY_ATTR_LARGE:
    DB #45,#45                  ; bright cyan

ENEMY_FRAMES:
    ; 4 rotation frames per type, each 90 degrees clockwise.
    DW ENEMY_SMALL_0,ENEMY_SMALL_1,ENEMY_SMALL_2,ENEMY_SMALL_3
    DW ENEMY_LARGE_0,ENEMY_LARGE_1,ENEMY_LARGE_2,ENEMY_LARGE_3

; Small 8x8: 8 bytes/frame. Large 16x16: 32 bytes/frame.
; No masking or backdrop saving; sprites draw opaque.
ENEMY_SMALL_0:
    DB %00011100
    DB %00111110
    DB %11111111
    DB %11110111
    DB %11111110
    DB %00111111
    DB %00001110
    DB %00000100

ENEMY_SMALL_1:
    DB %00011100
    DB %00011100
    DB %00111110
    DB %00111111
    DB %01110111
    DB %11111111
    DB %01111110
    DB %00101100

ENEMY_SMALL_2:
    DB %00100000
    DB %01110000
    DB %11111100
    DB %01111111
    DB %11101111
    DB %11111111
    DB %01111100
    DB %00111000

ENEMY_SMALL_3:
    DB %00110100
    DB %01111110
    DB %11111111
    DB %11101110
    DB %11111100
    DB %01111100
    DB %00111000
    DB %00111000

ENEMY_LARGE_0:
    DB #01,#E0
    DB #07,#F8
    DB #1F,#FC
    DB #3F,#FE
    DB #3F,#FF
    DB #7F,#FF
    DB #FB,#FF
    DB #FF,#FE
    DB #FF,#FF
    DB #FF,#FC
    DB #7F,#F8
    DB #77,#F8
    DB #3F,#FC
    DB #1F,#F0
    DB #07,#C0
    DB #03,#80

ENEMY_LARGE_1:
    DB #03,#C0
    DB #0F,#E0
    DB #1F,#F8
    DB #3F,#FC
    DB #37,#FC
    DB #7F,#BE
    DB #FF,#FE
    DB #FF,#FF
    DB #FF,#FF
    DB #7F,#FF
    DB #3F,#FF
    DB #3F,#FE
    DB #1F,#FE
    DB #13,#FC
    DB #01,#F8
    DB #01,#70

ENEMY_LARGE_2:
    DB #01,#C0
    DB #03,#E0
    DB #0F,#F8
    DB #3F,#FC
    DB #1F,#EE
    DB #1F,#FE
    DB #3F,#FF
    DB #FF,#FF
    DB #7F,#FF
    DB #FF,#DF
    DB #FF,#FE
    DB #FF,#FC
    DB #7F,#FC
    DB #3F,#F8
    DB #1F,#E0
    DB #07,#80

ENEMY_LARGE_3:
    DB #0E,#80
    DB #1F,#80
    DB #3F,#C8
    DB #7F,#F8
    DB #7F,#FC
    DB #FF,#FC
    DB #FF,#FE
    DB #FF,#FF
    DB #FF,#FF
    DB #7F,#FF
    DB #7D,#FE
    DB #3F,#EC
    DB #3F,#FC
    DB #1F,#F8
    DB #07,#F0
    DB #03,#C0

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
BULLET_ATTR_PAIR:
    DB #47,#47                 ; bullet spans two cells at +4px

BLAST_ACTIVE:
    DB 0
BLAST_DRAWN:
    DB 0
BLAST_OWNER:
    DB 0                       ; 0 asteroid, 1 ship
BLAST_TYPE:
    DB 0                        ; 0=8x8 for small, 1=16x8 for large
BLAST_FRAME:
    DB 0
BLAST_ANIM_TIMER:
    DB BLAST_FRAME_DURATION
BLAST_POS:
    DB 0,0                      ; base cell X/Y for blast
BLAST_HALF:
    DB 0                        ; 4px offset of ship blast (0 or 1)
BLAST_ATTR_PAIR:
    DB #46,#46                 ; dynamically selected ship blast colors
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

; Six expressive ship-debris frames, each 8x8.
; Yellow ignition, red fireball, white shrapnel.
SHIP_BLAST_ATTRS:
    DB #46,#46,#42,#42,#47,#47
SHIP_BLAST_FRAME_PTRS:
    DW SHIP_BLAST_0,SHIP_BLAST_1,SHIP_BLAST_2
    DW SHIP_BLAST_3,SHIP_BLAST_4,SHIP_BLAST_5

SHIP_BLAST_0:
    DB %00011000
    DB %00111100
    DB %01111110
    DB %11011011
    DB %11111111
    DB %01111110
    DB %00100100
    DB %01000010
SHIP_BLAST_1:
    DB %10011001
    DB %01111110
    DB %11111111
    DB %11111111
    DB %11111111
    DB %11111111
    DB %01111110
    DB %10011001
SHIP_BLAST_2:
    DB %10100101
    DB %01111110
    DB %11111111
    DB %11100111
    DB %11100111
    DB %11111111
    DB %01111110
    DB %10100101
SHIP_BLAST_3:
    DB %10011001
    DB %01000010
    DB %00111100
    DB %10100101
    DB %10100101
    DB %00111100
    DB %01000010
    DB %10011001
SHIP_BLAST_4:
    DB %10000001
    DB %00100100
    DB %01000010
    DB %00011000
    DB %00011000
    DB %01000010
    DB %00100100
    DB %10000001
SHIP_BLAST_5:
    DB %00000000
    DB %01000010
    DB %00000000
    DB %00100100
    DB %00000000
    DB %01000010
    DB %00000000
    DB %00000000

; Dirty flags for explosion and player.
; Bullet dirty state is inside each bullet slot.
BLAST_DIRTY:     DB 0
SHIP_DIRTY:      DB 1

; -------------------------------------------------------------
; Moving starfield: 16 points, two slow motion rates.
; Each record: X cell, Y pixel (32..191), pixel bit, period mask.
; -------------------------------------------------------------
STAR_CLOCK:    DB 0
DIRTY_COUNT:   DB 0
DIRTY_TAIL:    DW DIRTY_QUEUE
DIRTY_MAP:     DS 768,0
DIRTY_QUEUE:   DS 320,0          ; 160 unique character cells

STAR_POOL:
    ; Mid layer: SCROLL_SPEED pixels every two frames.
    DB 8,73,#10,1
    DB 10,150,#01,1
    DB 12,43,#02,1
    DB 14,170,#08,1
    DB 16,84,#20,1
    DB 18,37,#04,1
    DB 20,114,#40,1
    DB 22,141,#02,1
    ; Far layer: SCROLL_SPEED pixels every four frames.
    DB 9,178,#80,3
    DB 11,38,#08,3
    DB 13,128,#10,3
    DB 15,66,#01,3
    DB 17,152,#20,3
    DB 19,98,#04,3
    DB 21,52,#40,3
    DB 23,186,#02,3
; -------------------------------------------------------------
; Input and HUD state.
; -------------------------------------------------------------
SCROLL_SPEED:      DB 1        ; auto 1..3, multiplier for star/asteroid speed
SCORE:             DW 0        ; 0..65535, saturating 16-bit total
SCORE_TIER:        DB 0        ; SCORE / 1024 at last bonus
HUD_DIRTY:         DB 1        ; numeric labels need redraw
SPACE_HELD:        DB 0

HUD_LABEL_TITLE:  DB "SPACECAN: SPACE SODA",0
HUD_LABEL_SPEED:  DB "SPEED",0
HUD_LABEL_SCORE:  DB "SCORE",0
HUD_LABEL_LIVES:  DB "LIVES",0
HUD_LABEL_MISSES: DB "MISS  /3",0

CAN_LABEL_LEFT:   DB "SPA",0
CAN_LABEL_RIGHT:  DB "CAN",0
CAN_LABEL_VOLUME: DB "0.33",0

PROGRAM_END:
