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
MISS_TRAVEL_ROWS:
    DB 0                        ; 0..59 asteroid-movement rows since last kill
MISS_KILLED_THIS_TICK:
    DB 0                        ; don't count the movement before a kill
PRESSURE_LEVEL:
    DB 0                        ; 0..10, persistent red segments right-to-left
BOSS_STARTED:         DB 0      ; boss phase reached this game
BOSS_ACTIVE:          DB 0
BOSS_HP:              DB 0      ; 10 HP shown by shared gauge
BOSS_X:               DB BOSS_X_CENTER
BOSS_Y:               DB BOSS_START_Y
BOSS_DRAWN:           DB 0
BOSS_DRAW_X:          DB BOSS_X_CENTER
BOSS_DRAW_Y:          DB BOSS_START_Y
BOSS_DIRTY:           DB 0
BOSS_ENTRY_TIMER:     DB BOSS_ENTRY_DELAY
BOSS_ANIM_TIMER:      DB BOSS_ANIM_DELAY
BOSS_FRAME:           DB 0
BOSS_FIRE_TIMER:      DB BOSS_FIRE_DELAY
HOSTILE_BULLET_CLOCK: DB HOSTILE_MOVE_DELAY
HOSTILE_BULLET_POOL:  DS MAX_HOSTILE_BULLETS*HOSTILE_BULLET_SIZE,0
SHOOT_WARNING_ACTIVE:
    DB 0                        ; latch after >=20 travel rows; clear on kill/life
SHOOT_VISIBLE:
    DB 0                        ; screen currently contains SHOOT! text
SHOOT_BLINK_COUNTER:
    DB 0                        ; increments only while warning/play active
SHOOT_SAVED_BITMAP:
    DS SHOOT_TEXT_WIDTH*8,0      ; original 48 HUD pixel bytes
SHOOT_SAVED_ATTR:
    DS SHOOT_TEXT_WIDTH,0        ; original six attributes
PAUSE_KEY_HELD:
    DB 1                        ; ENTER edge latch (1 while entering game)
PAUSE_PREVIOUS_STATE:
    DB STATE_PLAYING            ; playing or exploding before pause
PAUSE_SAVED_BITMAP:
    DS PAUSE_TEXT_WIDTH*8,0     ; pixel bytes underneath "PAUSED"
PAUSE_SAVED_ATTR:
    DS PAUSE_TEXT_WIDTH,0       ; exact attributes for screen restore
SHIP_MOVE_TIMER:
    DB 0                        ; frames until next horizontal step

; Four asteroids start far apart vertically. Each new spawn chooses
; another random lane/shape/shade. Initial table: TYPE,Y,PHASE.
; At least 3 completely empty rows between sprite footprints.
ENEMY_START_TABLE:
    DB 0,4,1                    ; small, Y=4
    DB 1,9,3                    ; large, Y=9..10
    DB 0,14,5                   ; small, Y=14
    DB 1,19,7                   ; large, Y=19..20

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

; Every spawned asteroid picks one of eight shades. The 16x16
; asteroid uses a dim/bright pair of attributes for a two-tone look.
; Attribute values: bright bit #40, paper 0 (black), ink 0..7.
ENEMY_SMALL_COLOURS:
    DB #07,#47,#05,#45,#03,#43,#06,#46
    ; gray, white, dark cyan, cyan, dark violet, violet, ochre, gold

ENEMY_LARGE_COLOURS:
    DB #07,#47                   ; slate + ice
    DB #47,#07                   ; ice + slate
    DB #05,#45                   ; blue-green
    DB #45,#05
    DB #03,#43                   ; purple
    DB #43,#03
    DB #06,#46                   ; golden rock
    DB #46,#06

ENEMY_FRAMES:
    ; SMALL: [0] classic, [1] chipped, [2] crater, [3] splinter.
    ; Each group has four clockwise-rotation frames.
    DW ENEMY_SMALL_0,ENEMY_SMALL_1,ENEMY_SMALL_2,ENEMY_SMALL_3
    DW ENEMY_SMALL_CHIP_0,ENEMY_SMALL_CHIP_1,ENEMY_SMALL_CHIP_2,ENEMY_SMALL_CHIP_3
    DW ENEMY_SMALL_CRATER_0,ENEMY_SMALL_CRATER_1,ENEMY_SMALL_CRATER_2,ENEMY_SMALL_CRATER_3
    DW ENEMY_SMALL_SPLINTER_0,ENEMY_SMALL_SPLINTER_1,ENEMY_SMALL_SPLINTER_2,ENEMY_SMALL_SPLINTER_3
    ; LARGE: [0] classic, [1] jagged, [2] crater, [3] shard.
    DW ENEMY_LARGE_0,ENEMY_LARGE_1,ENEMY_LARGE_2,ENEMY_LARGE_3
    DW ENEMY_LARGE_JAGGED_0,ENEMY_LARGE_JAGGED_1,ENEMY_LARGE_JAGGED_2,ENEMY_LARGE_JAGGED_3
    DW ENEMY_LARGE_CRATER_0,ENEMY_LARGE_CRATER_1,ENEMY_LARGE_CRATER_2,ENEMY_LARGE_CRATER_3
    DW ENEMY_LARGE_SHARD_0,ENEMY_LARGE_SHARD_1,ENEMY_LARGE_SHARD_2,ENEMY_LARGE_SHARD_3

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


; Additional asteroid silhouettes. Rotation frames are precomputed
; OFFLINE; the Z80 still draws directly without shifts or masks.
ENEMY_SMALL_CHIP_0:
    DB %00111000
    DB %01111100
    DB %11111110
    DB %11110111
    DB %01111111
    DB %00101110
    DB %00011100
    DB %00001000
ENEMY_SMALL_CHIP_1:
    DB %00001100
    DB %00011110
    DB %00111111
    DB %01011111
    DB %11110111
    DB %01111110
    DB %00111100
    DB %00011000
ENEMY_SMALL_CHIP_2:
    DB %00010000
    DB %00111000
    DB %01110100
    DB %11111110
    DB %11101111
    DB %01111111
    DB %00111110
    DB %00011100
ENEMY_SMALL_CHIP_3:
    DB %00011000
    DB %00111100
    DB %01111110
    DB %11101111
    DB %11111010
    DB %11111100
    DB %01111000
    DB %00110000
ENEMY_SMALL_CRATER_0:
    DB %00011000
    DB %01111110
    DB %11100111
    DB %11000011
    DB %11010011
    DB %11100111
    DB %01111110
    DB %00011000
ENEMY_SMALL_CRATER_1:
    DB %00111100
    DB %01111110
    DB %01100110
    DB %11010011
    DB %11000011
    DB %01100110
    DB %01111110
    DB %00111100
ENEMY_SMALL_CRATER_2:
    DB %00011000
    DB %01111110
    DB %11100111
    DB %11001011
    DB %11000011
    DB %11100111
    DB %01111110
    DB %00011000
ENEMY_SMALL_CRATER_3:
    DB %00111100
    DB %01111110
    DB %01100110
    DB %11000011
    DB %11001011
    DB %01100110
    DB %01111110
    DB %00111100
ENEMY_SMALL_SPLINTER_0:
    DB %00100100
    DB %01111100
    DB %11111110
    DB %01101111
    DB %11111110
    DB %00111100
    DB %01111110
    DB %00010100
ENEMY_SMALL_SPLINTER_1:
    DB %00010100
    DB %01011110
    DB %01111111
    DB %11110110
    DB %01111110
    DB %11111111
    DB %01011100
    DB %00001000
ENEMY_SMALL_SPLINTER_2:
    DB %00101000
    DB %01111110
    DB %00111100
    DB %01111111
    DB %11110110
    DB %01111111
    DB %00111110
    DB %00100100
ENEMY_SMALL_SPLINTER_3:
    DB %00010000
    DB %00111010
    DB %11111111
    DB %01111110
    DB %01101111
    DB %11111110
    DB %01111010
    DB %00101000
ENEMY_LARGE_JAGGED_0:
    DB #03,#80
    DB #0F,#C0
    DB #1F,#E0
    DB #3E,#F0
    DB #7F,#F8
    DB #FF,#FC
    DB #7F,#FE
    DB #3F,#FF
    DB #1F,#FF
    DB #0F,#FE
    DB #3F,#FC
    DB #7F,#F8
    DB #6F,#F0
    DB #3F,#E0
    DB #1F,#80
    DB #06,#00
ENEMY_LARGE_JAGGED_1:
    DB #00,#20
    DB #18,#70
    DB #3C,#F8
    DB #6D,#FC
    DB #7F,#FE
    DB #FF,#FE
    DB #FF,#FF
    DB #7F,#F7
    DB #7F,#FF
    DB #3F,#FE
    DB #3F,#FC
    DB #1F,#F8
    DB #0F,#F0
    DB #07,#E0
    DB #03,#C0
    DB #01,#80
ENEMY_LARGE_JAGGED_2:
    DB #00,#60
    DB #01,#F8
    DB #07,#FC
    DB #0F,#F6
    DB #1F,#FE
    DB #3F,#FC
    DB #7F,#F0
    DB #FF,#F8
    DB #FF,#FC
    DB #7F,#FE
    DB #3F,#FF
    DB #1F,#FE
    DB #0F,#7C
    DB #07,#F8
    DB #03,#F0
    DB #01,#C0
ENEMY_LARGE_JAGGED_3:
    DB #01,#80
    DB #03,#C0
    DB #07,#E0
    DB #0F,#F0
    DB #1F,#F8
    DB #3F,#FC
    DB #7F,#FC
    DB #FF,#FE
    DB #EF,#FE
    DB #FF,#FF
    DB #7F,#FF
    DB #7F,#FE
    DB #3F,#B6
    DB #1F,#3C
    DB #0E,#18
    DB #04,#00
ENEMY_LARGE_CRATER_0:
    DB #07,#C0
    DB #1F,#F0
    DB #3F,#F8
    DB #7F,#FC
    DB #FF,#FE
    DB #F8,#3F
    DB #F0,#1F
    DB #E0,#0F
    DB #E0,#1F
    DB #F0,#3F
    DB #F8,#7E
    DB #7F,#FE
    DB #3F,#FC
    DB #1F,#F8
    DB #0F,#E0
    DB #03,#80
ENEMY_LARGE_CRATER_1:
    DB #07,#F0
    DB #0F,#F8
    DB #1F,#FC
    DB #3E,#7E
    DB #7C,#3E
    DB #78,#1F
    DB #F8,#1F
    DB #F8,#1F
    DB #F8,#1F
    DB #7C,#1F
    DB #7E,#3E
    DB #3F,#7E
    DB #3F,#FC
    DB #1F,#F8
    DB #0F,#F0
    DB #03,#E0
ENEMY_LARGE_CRATER_2:
    DB #01,#C0
    DB #07,#F0
    DB #1F,#F8
    DB #3F,#FC
    DB #7F,#FE
    DB #7E,#1F
    DB #FC,#0F
    DB #F8,#07
    DB #F0,#07
    DB #F8,#0F
    DB #FC,#1F
    DB #7F,#FF
    DB #3F,#FE
    DB #1F,#FC
    DB #0F,#F8
    DB #03,#E0
ENEMY_LARGE_CRATER_3:
    DB #07,#C0
    DB #0F,#F0
    DB #1F,#F8
    DB #3F,#FC
    DB #7E,#FC
    DB #7C,#7E
    DB #F8,#3E
    DB #F8,#1F
    DB #F8,#1F
    DB #F8,#1F
    DB #F8,#1E
    DB #7C,#3E
    DB #7E,#7C
    DB #3F,#F8
    DB #1F,#F0
    DB #0F,#E0
ENEMY_LARGE_SHARD_0:
    DB #01,#80
    DB #0F,#E0
    DB #1E,#F0
    DB #3F,#F8
    DB #7F,#7C
    DB #7C,#3E
    DB #FD,#7F
    DB #FF,#FF
    DB #FB,#FE
    DB #78,#FE
    DB #7F,#FC
    DB #3F,#B8
    DB #1F,#F0
    DB #1D,#E0
    DB #0F,#80
    DB #05,#00
ENEMY_LARGE_SHARD_1:
    DB #01,#C0
    DB #07,#F0
    DB #0F,#F8
    DB #3F,#FC
    DB #7F,#FE
    DB #FC,#FE
    DB #5D,#9E
    DB #FD,#DB
    DB #7F,#8F
    DB #37,#DE
    DB #3F,#FE
    DB #1F,#FC
    DB #0F,#F8
    DB #07,#F0
    DB #03,#E0
    DB #00,#C0
ENEMY_LARGE_SHARD_2:
    DB #00,#A0
    DB #01,#F0
    DB #07,#B8
    DB #0F,#F8
    DB #1D,#FC
    DB #3F,#FE
    DB #7F,#1E
    DB #7F,#DF
    DB #FF,#FF
    DB #FE,#BF
    DB #7C,#3E
    DB #3E,#FE
    DB #1F,#FC
    DB #0F,#78
    DB #07,#F0
    DB #01,#80
ENEMY_LARGE_SHARD_3:
    DB #03,#00
    DB #07,#C0
    DB #0F,#E0
    DB #1F,#F0
    DB #3F,#F8
    DB #7F,#FC
    DB #7B,#EC
    DB #F1,#FE
    DB #DB,#BF
    DB #79,#BA
    DB #7F,#3F
    DB #7F,#FE
    DB #3F,#FC
    DB #1F,#F0
    DB #0F,#E0
    DB #03,#80

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
    ; Far layer: 1..3 pixels (with half-stages) every four frames.
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
SCROLL_SPEED:      DB 1        ; integer portion of motion speed (1..3)
SPEED_LEVEL:       DB 0        ; stages 0..4: 1,1.5,2,2.5,3
ENEMY_SPEED_PHASE: DB 0        ; alternates 4/3 or 3/2 enemy intervals
SCORE:             DB 0,0,0    ; 24-bit little endian, capped at 999999
SCORE_PRINT_WORK:  DB 0,0,0    ; scratch remainder for decimal output
HUD_DIRTY:         DB 1        ; refresh speed, score and lives
GAUGE_DIRTY:       DB 1        ; gauge colors need redraw
SPACE_HELD:        DB 0

HUD_LABEL_TITLE:  DB "SPACECAN: SPACE SODA",0
HUD_LABEL_SPEED:  DB "SPEED",0
HUD_LABEL_SHOOT:  DB "SHOOT!",0

; Each life is one 8x8 character, active vs spent.
HEART_FILLED:
    DB %00000000
    DB %01100110
    DB %11111111
    DB %11111111
    DB %11111111
    DB %01111110
    DB %00111100
    DB %00011000
HEART_OUTLINE:
    DB %00000000
    DB %01100110
    DB %10011001
    DB %10000001
    DB %10000001
    DB %01000010
    DB %00100100
    DB %00011000
HEART_ACTIVE_ATTR: DB #42    ; bright red ink on black
HEART_SPENT_ATTR:  DB #07    ; dim white ink on black

; 100000, 10000, 1000, 100, 10 as 24-bit little-endian divisors.
SCORE_DECIMAL_PLACES:
    DB #A0,#86,#01
    DB #10,#27,#00
    DB #E8,#03,#00
    DB #64,#00,#00
    DB #0A,#00,#00

CAN_LABEL_LEFT:   DB "SPA",0
CAN_LABEL_RIGHT:  DB "CAN",0
CAN_LABEL_VOLUME: DB "0.33",0

PROGRAM_END:
