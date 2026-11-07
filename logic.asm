; -------------------------------------------------------------
; INPUT: controls prepare positions only. No drawing here.
; O/P: move; SPACE: fire on edge. Speed is score-driven.
; -------------------------------------------------------------
READ_INPUT:
    CALL READ_SHIP_HORIZONTAL
    CALL READ_FIRE_KEY
    RET

; The 8x8 ship stays within X=8..23, Y=22, now moving in 4px steps.
; Banking is independent:
; one pose every SHIP_BANK_DELAY frames, then a short hold after
; release to make brief turns visible.
READ_SHIP_HORIZONTAL:
    ; 8x8 ship moves in 4-pixel steps (1/2 character cell).
    ; X stores the LEFT cell; SHIP_HALF_POS=1 means +4 pixels.
    ; Valid leftmost pixel positions are 8*8 .. 23*8.
    LD BC,#DFFE
    IN A,(C)
    BIT 0,A                      ; P: right
    JR NZ,.CHECK_LEFT
    LD D,4
    LD A,(SHIP_NEW_POS)
    CP PLAYFIELD_RIGHT
    JP Z,.SET_BANK               ; last whole cell: never spill right

    LD A,(SHIP_MOVE_TIMER)
    OR A
    JP NZ,.WAIT
    LD A,(SHIP_HALF_POS)
    OR A
    JR Z,.HALF_RIGHT
    ;  x+.5 -> (x+1)+0
    XOR A
    LD (SHIP_HALF_POS),A
    LD HL,SHIP_NEW_POS
    INC (HL)
    JP .MOVED
.HALF_RIGHT:
    LD A,1
    LD (SHIP_HALF_POS),A
    JP .MOVED

.CHECK_LEFT:
    BIT 1,A                      ; O: left
    JP NZ,.NO_KEY
    LD D,0
    LD A,(SHIP_NEW_POS)
    CP PLAYFIELD_LEFT
    JR NZ,.LEFT_ALLOWED
    LD A,(SHIP_HALF_POS)
    OR A
    JP Z,.SET_BANK               ; at the leftmost pixel
.LEFT_ALLOWED:
    LD A,(SHIP_MOVE_TIMER)
    OR A
    JP NZ,.WAIT
    LD A,(SHIP_HALF_POS)
    OR A
    JR NZ,.HALF_LEFT
    ;  x+0 -> (x-1)+.5
    LD HL,SHIP_NEW_POS
    DEC (HL)
    LD A,1
    LD (SHIP_HALF_POS),A
    JP .MOVED
.HALF_LEFT:
    XOR A
    LD (SHIP_HALF_POS),A
    JP .MOVED

.WAIT:
    DEC A
    LD (SHIP_MOVE_TIMER),A
    JR .SET_BANK
.MOVED:
    LD A,SHIP_MOVE_DELAY-1
    LD (SHIP_MOVE_TIMER),A
    LD A,1
    LD (SHIP_DIRTY),A

.SET_BANK:
    LD A,D
    LD (SHIP_BANK_TARGET),A
    LD A,SHIP_BANK_HOLD
    LD (SHIP_BANK_HOLD_TIMER),A
.NO_KEY:
    JP UPDATE_SHIP_BANK

; Smooth pose selection; no graphics are drawn here.
; BANK = 0,1,2,3,4. Starts with an immediate first tilt,
; then advances one more pose every 5 game frames (0.1s).
; After movement ends, the last pose remains for ~0.28s,
; then steps back toward the neutral pose (2).
UPDATE_SHIP_BANK:
    LD A,(SHIP_BANK_HOLD_TIMER)
    OR A
    JR Z,.LEVEL
    DEC A
    LD (SHIP_BANK_HOLD_TIMER),A
    JR NZ,.TIMER
.LEVEL:
    LD A,2
    LD (SHIP_BANK_TARGET),A

.TIMER:
    LD A,(SHIP_BANK_TIMER)
    OR A
    JR Z,.STEP
    DEC A
    LD (SHIP_BANK_TIMER),A
    RET
.STEP:
    LD A,SHIP_BANK_DELAY-1
    LD (SHIP_BANK_TIMER),A
    LD A,(SHIP_BANK)
    LD HL,SHIP_BANK_TARGET
    CP (HL)
    RET Z
    JR C,.UP
    DEC A
    JR .STORE
.UP:
    INC A
.STORE:
    LD (SHIP_BANK),A
    LD A,1
    LD (SHIP_DIRTY),A
    RET

; No autofire: holding SPACE creates only one bullet.
; A free slot is needed; when all six slots are occupied, do nothing.
READ_FIRE_KEY:
    LD BC,#7FFE
    IN A,(C)
    BIT 0,A
    JR NZ,.RELEASED
    LD A,(SPACE_HELD)
    OR A
    RET NZ
    LD A,1
    LD (SPACE_HELD),A
    JP FIRE_BULLET
.RELEASED:
    XOR A
    LD (SPACE_HELD),A
    RET

; The logic always runs after render and works only with game state.
; Blast first: a new hit starts from full frame 0 duration.
UPDATE_GAME:
    XOR A
    LD (MISS_KILLED_THIS_TICK),A
    CALL UPDATE_BLAST_ANIM
    CALL UPDATE_ENEMIES
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    RET NZ                      ; a missed asteroid may end the game
    CALL UPDATE_BULLETS
    CALL CHECK_SHIP_ENEMY_COLLISIONS
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    RET NZ                     ; ship destroyed: freeze starfield
    ; Count world distance AFTER bullets: a kill in this tick resets it.
    CALL UPDATE_MISS_PRESSURE
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    RET NZ
    CALL STARFIELD_UPDATE
    RET

; Start an explosion at a destroyed asteroid (one effect slot).
; IN: IX = asteroid slot. PRESERVES: IX. DESTROYS: AF, DE, HL.
START_ENEMY_BLAST:
    LD A,(BLAST_ACTIVE)
    OR A
    RET NZ
    LD A,(BLAST_DRAWN)
    OR A
    RET NZ
    LD L,(IX+E_X)
    LD H,(IX+E_Y)
    LD (BLAST_POS),HL
    LD A,(IX+E_TYPE)
    LD (BLAST_TYPE),A           ; 0=8x8, 1=16x8 explosion
    XOR A
    LD (BLAST_OWNER),A         ; 0=asteroid; 1=ship
    LD (BLAST_HALF),A          ; asteroids always cell aligned
    LD (BLAST_FRAME),A
    CALL SELECT_BLAST_FRAME
    LD A,BLAST_FRAME_DURATION
    LD (BLAST_ANIM_TIMER),A
    LD A,1
    LD (BLAST_ACTIVE),A
    LD (BLAST_DIRTY),A
    IFN DEBUG_BORDER
        LD A,2
        OUT (#FE),A
    ENDIF
    RET

; Dedicated ship explosion replaces any asteroid blast. Its last
; drawn image is marked for erasure BEFORE BLAST_POS is replaced.
; The renderer then erases the ship and paints explosion frame zero.
START_SHIP_EXPLOSION:
    LD A,(BLAST_DRAWN)
    OR A
    JR Z,.OLD_GONE
    CALL ERASE_BLAST
    XOR A
    LD (BLAST_DRAWN),A
.OLD_GONE:
    LD HL,(SHIP_NEW_POS)
    LD (BLAST_POS),HL           ; retain base X, don't round to next cell
    LD A,(SHIP_HALF_POS)
    LD (BLAST_HALF),A          ; ship blast is also shifted by exactly 4px
    LD A,1
    LD (BLAST_OWNER),A
    LD (BLAST_ACTIVE),A
    LD (BLAST_DIRTY),A
    LD (SHIP_DIRTY),A
    LD A,STATE_EXPLODING
    LD (GAME_STATE),A
    XOR A
    LD (SHIP_VISIBLE),A
    LD (BLAST_TYPE),A         ; dedicated blast is 8x8
    LD (BLAST_FRAME),A
    CALL SELECT_BLAST_FRAME
    LD A,SHIP_BLAST_DURATION
    LD (BLAST_ANIM_TIMER),A
    RET

; Enemy blast: 4x4 ticks. Ship blast: 6x5 ticks (0.6 seconds).
UPDATE_BLAST_ANIM:
    LD A,(BLAST_ACTIVE)
    OR A
    RET Z
    LD HL,BLAST_ANIM_TIMER
    DEC (HL)
    RET NZ
    LD A,(BLAST_OWNER)
    OR A
    LD A,BLAST_FRAME_DURATION
    JR Z,.STORE_DURATION
    LD A,SHIP_BLAST_DURATION
.STORE_DURATION:
    LD (HL),A
    LD A,(BLAST_FRAME)
    INC A
    LD C,BLAST_FRAME_COUNT
    LD B,A
    LD A,(BLAST_OWNER)
    OR A
    JR Z,.FRAME_LIMIT
    LD C,SHIP_BLAST_FRAMES
.FRAME_LIMIT:
    LD A,B
    CP C
    JR Z,.FINISH
    LD (BLAST_FRAME),A
    CALL SELECT_BLAST_FRAME
    LD A,1
    LD (BLAST_DIRTY),A
    RET
.FINISH:
    XOR A
    LD (BLAST_ACTIVE),A
    LD A,1
    LD (BLAST_DIRTY),A
    LD A,(BLAST_OWNER)
    OR A
    RET Z                     ; an asteroid blast ends normally
    LD A,(SHIP_LIVES)
    OR A
    LD A,STATE_RESPAWN
    JR NZ,.NEXT_MODE
    LD A,STATE_GAME_OVER
.NEXT_MODE:
    LD (GAME_STATE),A
    RET

; IN: BLAST_FRAME=frame index. OUT BLAST_FRAME_PTR.
SELECT_BLAST_FRAME:
    LD A,(BLAST_FRAME)
    ADD A,A
    LD E,A
    LD D,0
    LD A,(BLAST_OWNER)
    OR A
    JR Z,.ASTEROID
    LD HL,SHIP_BLAST_FRAME_PTRS
    JR .SELECT
.ASTEROID:
    LD A,(BLAST_TYPE)
    OR A
    LD HL,BLAST_SMALL_FRAMES
    JR Z,.SELECT
    LD HL,BLAST_FRAMES
.SELECT:
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
    LD (BLAST_FRAME_PTR),DE
    RET

; -------------------------------------------------------------
; Score/bonus: 24-bit total (capped at 999999).
; Small = 64, large = 128 points. Gentle speed milestones:
; 4096, 8192, 16384, 32768 => stages 1..4 (start stage 0).
; -------------------------------------------------------------
ADD_SCORE_A:
    LD E,A
    LD D,0
    LD HL,(SCORE)
    ADD HL,DE
    LD (SCORE),HL
    LD A,(SCORE+2)
    ADC A,0
    LD (SCORE+2),A

    ; Saturate at 999999 = #0F423F, not at 16-bit #FFFF.
    CP #0F
    JR C,.IN_RANGE
    JR NZ,.CAP
    LD HL,(SCORE)
    LD DE,#4240                 ; first value beyond 999999
    OR A
    SBC HL,DE
    JR C,.IN_RANGE
.CAP:
    LD HL,#423F
    LD (SCORE),HL
    LD A,#0F
    LD (SCORE+2),A
.IN_RANGE:
    LD A,1
    LD (HUD_DIRTY),A
    JP CHECK_SCORE_BONUS

; Thresholds align to #1000/#2000/#4000/#8000.
CHECK_SCORE_BONUS:
    LD A,(SCORE+2)
    OR A
    JR NZ,.STAGE_4
    LD A,(SCORE+1)
    CP #80
    JR NC,.STAGE_4
    CP #40
    JR NC,.STAGE_3
    CP #20
    JR NC,.STAGE_2
    CP #10
    JR NC,.STAGE_1
    XOR A
    JR .STORE
.STAGE_1:
    LD A,1
    JR .STORE
.STAGE_2:
    LD A,2
    JR .STORE
.STAGE_3:
    LD A,3
    JR .STORE
.STAGE_4:
    LD A,4
.STORE:
    LD HL,SPEED_LEVEL
    CP (HL)
    RET Z
    LD (HL),A
    SRL A                       ; stage 0..4 => 0,0,1,1,2
    INC A                       ; integer portion 1..3
    LD (SCROLL_SPEED),A
    LD A,1
    LD (HUD_DIRTY),A
    RET

; -------------------------------------------------------------
; Pressure grows with world travel, NOT with count of escaped objects.
; Every downward movement is one of 20 rows in a corridor crossing.
; Three complete corridor heights (60 moves) with no asteroid kill
; add ONE permanent red segment. Any kill resets only the travel timer,
; never the accumulated gauge. At ten red segments a life is lost
; through the normal ship-explosion/respawn sequence.
; -------------------------------------------------------------
UPDATE_MISS_PRESSURE:
    LD A,(MISS_KILLED_THIS_TICK)
    OR A
    RET NZ                        ; a destruction restarted the timer
    LD A,(ENEMY_MOVE_NOW)
    OR A
    RET Z                         ; count movement, not 50Hz frames
    LD HL,MISS_TRAVEL_ROWS
    INC (HL)
    LD A,(HL)
    CP MISS_DISTANCE_LIMIT
    RET C                         ; fewer than 3 screens since last kill
    LD (HL),0                     ; begin the next 3-screen interval

    LD HL,PRESSURE_LEVEL
    INC (HL)                      ; once red, segments never turn green
    LD A,1
    LD (GAUGE_DIRTY),A
    LD A,(PRESSURE_LEVEL)
    CP PRESSURE_SEGMENTS
    RET C

    ; Full red bar takes one life and triggers the familiar ship blast.
    LD A,(SHIP_LIVES)
    OR A
    RET Z
    DEC A
    LD (SHIP_LIVES),A
    LD A,1
    LD (HUD_DIRTY),A
    JP START_SHIP_EXPLOSION

; Called ONLY for an asteroid destroyed by bullets.
RESET_MISS_TRAVEL:
    XOR A
    LD (MISS_TRAVEL_ROWS),A
    INC A
    LD (MISS_KILLED_THIS_TICK),A
    RET
