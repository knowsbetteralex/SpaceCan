; -------------------------------------------------------------
; INPUT: controls prepare positions only. No drawing here.
; O/P: move; Q/A: speed on key-down edge; SPACE: fire on edge.
; -------------------------------------------------------------
READ_INPUT:
    CALL READ_SHIP_HORIZONTAL
    CALL READ_SPEED_KEYS
    CALL READ_FIRE_KEY
    RET

; Ship is 16 pixels wide. Allowed left X = 6..24, Y fixed at 22.
READ_SHIP_HORIZONTAL:
    LD DE,(SHIP_NEW_POS)
    LD BC,#DFFE
    IN A,(C)
    BIT 0,A                      ; P: right
    JR NZ,.CHECK_LEFT
    LD A,E
    CP 24
    JR Z,.STORE
    INC E
    JR .STORE
.CHECK_LEFT:
    BIT 1,A                      ; O: left
    JR NZ,.STORE
    LD A,E
    CP 6
    JR Z,.STORE
    DEC E
.STORE:
    LD HL,(SHIP_NEW_POS)
    LD (SHIP_NEW_POS),DE
    XOR A
    SBC HL,DE
    RET Z
    LD A,1
    LD (SHIP_DIRTY),A
    RET

; Q/A change speed 1..4 for the HUD, asteroids and starfield.
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
    CP 4
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
