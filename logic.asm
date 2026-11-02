; -------------------------------------------------------------
; INPUT: controls prepare positions only. No drawing here.
; O/P: move; Q/A: speed on key-down edge; SPACE: fire on edge.
; -------------------------------------------------------------
READ_INPUT:
    CALL READ_SHIP_HORIZONTAL
    CALL READ_SPEED_KEYS
    CALL READ_FIRE_KEY
    RET

; The ship is now 8x8: one screen cell (X=6..25, Y=22).
; Movement is still one cell per input tick; banking is independent:
; one pose every SHIP_BANK_DELAY frames, then a short hold after
; release to make brief turns visible.
READ_SHIP_HORIZONTAL:
    LD A,(SHIP_NEW_POS)
    LD E,A
    LD BC,#DFFE
    IN A,(C)
    BIT 0,A                    ; P: move right
    JR NZ,.CHECK_LEFT
    LD A,E
    CP 25
    JR Z,.BANK_RIGHT
    INC E
.BANK_RIGHT:
    LD D,4                     ; lean right
    JR .MOVE

.CHECK_LEFT:
    BIT 1,A                    ; O: move left
    JR NZ,.NO_KEY
    LD A,E
    CP 6
    JR Z,.BANK_LEFT
    DEC E
.BANK_LEFT:
    LD D,0                     ; lean left
.MOVE:
    LD A,(SHIP_NEW_POS)
    CP E
    JR Z,.SET_BANK
    LD A,E
    LD (SHIP_NEW_POS),A
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

; Q/A change speed 1..3 for the HUD, asteroids and starfield.
READ_SPEED_KEYS:
    LD BC,#FBFE
    IN A,(C)
    BIT 0,A
    JR NZ,.Q_RELEASED
    LD A,(SPEED_UP_HELD)
    OR A
    JR NZ,.CHECK_A
    LD A,1
    LD (SPEED_UP_HELD),A
    LD A,(SCROLL_SPEED)
    CP 3
    JR Z,.CHECK_A
    INC A
    LD (SCROLL_SPEED),A
    LD A,1
    LD (HUD_DIRTY),A
    JR .CHECK_A
.Q_RELEASED:
    XOR A
    LD (SPEED_UP_HELD),A
.CHECK_A:
    LD BC,#FDFE
    IN A,(C)
    BIT 0,A
    JR NZ,.A_RELEASED
    LD A,(SPEED_DOWN_HELD)
    OR A
    RET NZ
    LD A,1
    LD (SPEED_DOWN_HELD),A
    LD A,(SCROLL_SPEED)
    CP 1
    RET Z
    DEC A
    LD (SCROLL_SPEED),A
    LD A,1
    LD (HUD_DIRTY),A
    RET
.A_RELEASED:
    XOR A
    LD (SPEED_DOWN_HELD),A
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
    CALL UPDATE_BLAST_ANIM
    CALL UPDATE_ENEMIES
    CALL UPDATE_BULLETS
    CALL CHECK_SHIP_ENEMY_COLLISIONS
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

; One-shot explosion: four phases, four ticks per phase.
UPDATE_BLAST_ANIM:
    LD A,(BLAST_ACTIVE)
    OR A
    RET Z
    LD HL,BLAST_ANIM_TIMER
    DEC (HL)
    RET NZ
    LD (HL),BLAST_FRAME_DURATION
    LD A,(BLAST_FRAME)
    INC A
    CP BLAST_FRAME_COUNT
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
    IFN DEBUG_BORDER
        OUT (#FE),A             ; blue border restored in release mode
    ENDIF
    RET

; IN: BLAST_FRAME=0..3. OUT: BLAST_FRAME_PTR updated.
SELECT_BLAST_FRAME:
    LD A,(BLAST_FRAME)
    ADD A,A
    LD E,A
    LD D,0
    LD A,(BLAST_TYPE)
    OR A
    LD HL,BLAST_SMALL_FRAMES
    JR Z,.HAVE_TABLE
    LD HL,BLAST_FRAMES
.HAVE_TABLE:
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
    LD (BLAST_FRAME_PTR),DE
    RET
