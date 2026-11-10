; -------------------------------------------------------------
; ENEMIES: four asteroids spread across the corridor; 8 silhouettes.
;
; IX -> current enemy slot. X is assigned at every spawn and
; remains constant until deactivation; overlapping spawn positions
; are rejected for objects currently occupying the entry rows.
; Game logic updates state/dirty; renderer stores drawn position.
; Shape/palette randomize per spawn. New appearances maintain a
; vertical clearance; lane selection prefers horizontal clearance.
; -------------------------------------------------------------

; Initialise from ENEMY_START_TABLE: TYPE, START_Y, ANIM_PHASE.
INIT_ENEMIES:
    ; Reset all slots, including DRAWN and DIRTY flags.
    LD HL,ENEMY_POOL
    LD (HL),0
    LD DE,ENEMY_POOL+1
    LD BC,MAX_ENEMIES*ENEMY_SLOT_SIZE-1
    LDIR

    ; Refresh register gives the first spawn sequence some variation.
    LD A,R
    OR 1
    LD (ENEMY_RANDOM_STATE),A

    LD IX,ENEMY_POOL
    LD HL,ENEMY_START_TABLE
    LD B,MAX_ENEMIES
.NEXT:
    LD A,(HL)
    LD (IX+E_TYPE),A
    INC HL
    OR A
    LD A,1
    JR Z,.STORE_HP
    LD A,3
.STORE_HP:
    LD (IX+E_HP),A
    LD A,(HL)
    LD (IX+E_Y),A
    INC HL
    LD A,(HL)
    LD (IX+E_ANIM_TIMER),A
    LD (IX+E_PHASE),A
    INC HL

    ; Every asteroid begins in a randomly selected vertical lane.
    ; Entry checks enforce vertical spacing; lane search keeps X varied.
    PUSH HL
    PUSH BC
    CALL ENEMY_SPAWN_GAP_CLEAR
    JR C,.SPAWN_TESTED
    CALL SELECT_ENEMY_SPAWN_X
.SPAWN_TESTED:
    POP BC
    POP HL
    JR C,.SKIP_ACTIVE
    CALL RANDOMIZE_ENEMY_APPEARANCE
    LD A,1
    LD (IX+E_ACTIVE),A
    LD (IX+E_DIRTY),A
.SKIP_ACTIVE:
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    LD A,4
    LD (ENEMY_MOVE_TIMER),A
    RET

; Smooth speed stages: asteroid motion intervals 4 / 4-3 / 3 / 3-2 / 2 ticks.
UPDATE_ENEMIES:
    LD A,(ENEMY_MOVE_TIMER)
    DEC A
    LD (ENEMY_MOVE_TIMER),A
    JR NZ,.NO_MOVE
    LD A,5
    LD HL,SCROLL_SPEED
    SUB (HL)
    LD C,A                       ; base interval 4, 3 or 2 ticks
    LD A,(SPEED_LEVEL)
    AND 1
    JR Z,.PERIOD_READY
    ; Half-speed stages alternate 4/3 or 3/2 intervals.
    LD A,(ENEMY_SPEED_PHASE)
    XOR 1
    LD (ENEMY_SPEED_PHASE),A
    OR A
    JR Z,.PERIOD_READY
    DEC C
.PERIOD_READY:
    LD A,C
    LD (ENEMY_MOVE_TIMER),A
    LD A,1
    LD (ENEMY_MOVE_NOW),A
    JR .PROCESS
.NO_MOVE:
    XOR A
    LD (ENEMY_MOVE_NOW),A
.PROCESS:
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    PUSH BC
    CALL UPDATE_ENEMY_SLOT
    POP BC
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

UPDATE_ENEMY_SLOT:
    ; If the preceding asteroid caused Game Over, don't move more
    ; objects in this tick. The loop still advances IX safely.
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    RET NZ
    LD A,(IX+E_ACTIVE)
    OR A
    JP Z,.INACTIVE

    ; Independently animate four rotation frames.
    LD A,(IX+E_ANIM_TIMER)
    DEC A
    LD (IX+E_ANIM_TIMER),A
    JR NZ,.MOVE
    LD A,ENEMY_FRAME_DELAY
    LD (IX+E_ANIM_TIMER),A
    LD A,(IX+E_FRAME)
    INC A
    AND 3
    LD (IX+E_FRAME),A
    LD A,1
    LD (IX+E_DIRTY),A
.MOVE:
    LD A,(ENEMY_MOVE_NOW)
    OR A
    RET Z
    ; Large 2-row sprite must stop at Y=22 (last bitmap row 23).
    ; Small 1-row sprite may reach Y=23 before disappearing.
    LD A,(IX+E_Y)
    LD C,23
    LD D,A
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.CHECK_BOTTOM
    LD C,22
.CHECK_BOTTOM:
    LD A,D
    CP C
    JR C,.STEP_DOWN
    ; Natural exit frees the slot. Pressure is based on travel
    ; distance globally, not on how many asteroids pass the ship.
    JP DEACTIVATE_ENEMY
.STEP_DOWN:
    INC A
    LD (IX+E_Y),A
    LD A,1
    LD (IX+E_DIRTY),A
    RET

.INACTIVE:
    ; Never respawn until old bitmap was erased.
    LD A,(IX+E_RESPAWN)
    OR A
    JR Z,.RESPAWN
    DEC A
    LD (IX+E_RESPAWN),A
    RET NZ
.RESPAWN:
    LD A,(IX+E_DRAWN)
    OR A
    RET NZ
    LD A,PLAYFIELD_TOP
    LD (IX+E_Y),A
    CALL ENEMY_SPAWN_GAP_CLEAR
    RET C                      ; wait until 3 clear rows at the entry
    CALL SELECT_ENEMY_SPAWN_X
    RET C                      ; entry row blocked: retry next tick
    CALL RANDOMIZE_ENEMY_APPEARANCE
    LD A,(IX+E_TYPE)
    OR A
    LD A,1
    JR Z,.HP_READY
    LD A,3
.HP_READY:
    LD (IX+E_HP),A
    XOR A
    LD (IX+E_FRAME),A
    LD A,(IX+E_PHASE)
    LD (IX+E_ANIM_TIMER),A
    LD A,1
    LD (IX+E_ACTIVE),A
    LD (IX+E_DIRTY),A
    RET

; -------------------------------------------------------------
; SPAWN X: prefer lanes with a clear column between all asteroids.
; When no well-separated lane fits, fall back to the existing
; collision-free placement so the fourth asteroid is not starved.
; IX = the inactive/current slot; its logical Y is already set.
; OUT: carry clear = X selected, carry set = all cells occupied.
; Preserves BC, DE, HL and IX. Runs only on spawn, not each frame.
; -------------------------------------------------------------
SELECT_ENEMY_SPAWN_X:
    PUSH BC
    PUSH DE
    PUSH HL

    ; Small uses all 16 columns; large has 15 valid left-Xs.
    LD C,PLAYFIELD_WIDTH
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.PICK
    DEC C
.PICK:
    CALL NEXT_ENEMY_RANDOM       ; A=0..255
.MODULO:
    CP C
    JR C,.START_X
    SUB C
    JR .MODULO
.START_X:
    ADD A,PLAYFIELD_LEFT
    LD (IX+E_X),A
    LD B,PLAYFIELD_WIDTH       ; at most 16 candidate positions
.TRY:
    CALL ENEMY_SPAWN_CLEAR
    JR C,.STEP_NEXT
    CALL ENEMY_SPAWN_LANE_CLEAR
    JR NC,.SUCCESS
.STEP_NEXT:
    LD C,PLAYFIELD_RIGHT
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.STEP
    DEC C                       ; large rightmost left-X is 22
.STEP:
    LD A,(IX+E_X)
    CP C
    JR C,.INCREMENT
    LD A,PLAYFIELD_LEFT
    JR .SAVE_X
.INCREMENT:
    INC A
.SAVE_X:
    LD (IX+E_X),A
    DJNZ .TRY

    ; All preferred lanes failed: retry without the cosmetic
    ; horizontal gap. Spatial overlap is still forbidden.
    LD B,PLAYFIELD_WIDTH
.RELAX:
    CALL ENEMY_SPAWN_CLEAR
    JR NC,.SUCCESS
    LD C,PLAYFIELD_RIGHT
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.RELAX_STEP
    DEC C
.RELAX_STEP:
    LD A,(IX+E_X)
    CP C
    JR C,.RELAX_INC
    LD A,PLAYFIELD_LEFT
    JR .RELAX_STORE
.RELAX_INC:
    INC A
.RELAX_STORE:
    LD (IX+E_X),A
    DJNZ .RELAX
    POP HL
    POP DE
    POP BC
    SCF                         ; no nonoverlapping lane exists
    RET
.SUCCESS:
    POP HL
    POP DE
    POP BC
    OR A                        ; clear carry
    RET

; 8-bit maximal-length Galois LFSR, polynomial #1D.
; Used for lane, shape and shade; never re-seed on respawn.
NEXT_ENEMY_RANDOM:
    LD A,(ENEMY_RANDOM_STATE)
    ADD A,A
    JR NC,.STORE
    XOR #1D
.STORE:
    LD (ENEMY_RANDOM_STATE),A
    RET

; Pick one of four silhouettes and eight palettes for this spawn.
; A fresh appearance is generated on every respawn, not each frame.
; Preserves BC/DE/HL/IX; modifies AF and carry.
RANDOMIZE_ENEMY_APPEARANCE:
    PUSH BC
    CALL NEXT_ENEMY_RANDOM
    LD C,A
    AND 3
    LD (IX+E_VARIANT),A
    LD A,C
    RLCA
    RLCA
    RLCA
    AND 7
    LD (IX+E_SHADE),A
    POP BC
    RET

; -------------------------------------------------------------
; Vertical spawn clearance (before lane search).
; Require ENEMY_MIN_VERTICAL_GAP fully empty character rows
; between the new asteroid footprint and every active asteroid,
; even if their horizontal lanes differ.
; In: IX = inactive/current slot with E_TYPE and E_Y set.
; Out: carry set -> delay spawn. Preserves BC, DE, HL, IX.
; -------------------------------------------------------------
ENEMY_SPAWN_GAP_CLEAR:
    PUSH BC
    PUSH DE
    PUSH IX
    LD A,(IX+E_Y)
    LD (ENEMY_TEST_Y),A
    LD A,(IX+E_TYPE)
    LD (ENEMY_TEST_TYPE),A
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    LD A,(IX+E_ACTIVE)
    OR A
    JR Z,.SKIP

    ; Existing top >= new bottom + gap + 1? Far below.
    LD A,(ENEMY_TEST_Y)
    LD C,A
    LD A,(ENEMY_TEST_TYPE)
    ADD A,C
    ADD A,ENEMY_MIN_VERTICAL_GAP+1
    CP (IX+E_Y)
    JR C,.SKIP
    JR Z,.SKIP

    ; New top >= existing bottom + gap + 1? Far below.
    LD A,(IX+E_Y)
    LD C,A
    LD A,(IX+E_TYPE)
    ADD A,C
    ADD A,ENEMY_MIN_VERTICAL_GAP+1
    LD C,A
    LD A,(ENEMY_TEST_Y)
    CP C
    JR NC,.SKIP

    POP IX
    POP DE
    POP BC
    SCF
    RET
.SKIP:
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    POP IX
    POP DE
    POP BC
    XOR A
    RET

; Prefer an empty horizontal column between the sprite rectangles,
; to avoid multiple asteroids forming one continuous vertical line.
; This is cosmetic: caller falls back to ENEMY_SPAWN_CLEAR if needed.
; In: IX=new slot, E_X/E_TYPE already set.
; Out: carry set -> lane too near another ACTIVE asteroid.
; Preserves BC, DE, HL, IX.
ENEMY_SPAWN_LANE_CLEAR:
    PUSH BC
    PUSH DE
    PUSH IX
    LD A,(IX+E_X)
    LD (ENEMY_TEST_X),A
    LD A,(IX+E_TYPE)
    LD (ENEMY_TEST_TYPE),A
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    LD A,(IX+E_ACTIVE)
    OR A
    JR Z,.SKIP

    ; Candidate right + gap + 1 <= existing left is allowed.
    LD A,(ENEMY_TEST_X)
    LD C,A
    LD A,(ENEMY_TEST_TYPE)
    ADD A,C
    ADD A,ENEMY_MIN_LANE_GAP+1
    CP (IX+E_X)
    JR C,.SKIP
    JR Z,.SKIP

    ; Existing right + gap + 1 <= candidate left is allowed.
    LD A,(IX+E_X)
    LD C,A
    LD A,(IX+E_TYPE)
    ADD A,C
    ADD A,ENEMY_MIN_LANE_GAP+1
    LD C,A
    LD A,(ENEMY_TEST_X)
    CP C
    JR NC,.SKIP

    POP IX
    POP DE
    POP BC
    SCF
    RET
.SKIP:
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    POP IX
    POP DE
    POP BC
    XOR A
    RET

; Current candidate is in (IX+E_X), new Y is already stored in slot.
; A collision can only happen with an active asteroid whose top
; currently occupies Y=4 or 5 (for a new 2-row large asteroid).
; Carry set: candidate intersects an active asteroid.
; Carry clear: new asteroid fits; preserves BC,DE,HL,IX.
ENEMY_SPAWN_CLEAR:
    PUSH BC
    PUSH DE
    PUSH IX
    LD A,(IX+E_X)
    LD (ENEMY_TEST_X),A
    LD A,(IX+E_TYPE)
    LD (ENEMY_TEST_TYPE),A
    LD A,(IX+E_Y)
    LD (ENEMY_TEST_Y),A
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    LD A,(IX+E_ACTIVE)
    OR A
    JR Z,.SKIP

    ; Vertical interval overlap:
    ; candidate_top <= existing_bottom, and
    ; existing_top <= candidate_bottom.
    LD A,(IX+E_Y)
    LD C,A
    LD A,(IX+E_TYPE)
    ADD A,C                    ; existing bottom Y
    LD C,A
    LD A,(ENEMY_TEST_Y)
    CP C
    JR C,.OTHER_SIDE
    JR Z,.OTHER_SIDE
    JR .SKIP
.OTHER_SIDE:
    LD A,(ENEMY_TEST_Y)
    LD C,A
    LD A,(ENEMY_TEST_TYPE)
    ADD A,C                    ; candidate bottom Y
    LD C,A
    LD A,(IX+E_Y)
    CP C
    JR C,.CHECK_X
    JR NZ,.SKIP
.CHECK_X:
    ; candidate_right < existing_left => no horizontal overlap
    LD A,(ENEMY_TEST_X)
    LD C,A
    LD A,(ENEMY_TEST_TYPE)
    ADD A,C
    CP (IX+E_X)
    JR C,.SKIP

    ; existing_right < candidate_left => no overlap
    LD A,(IX+E_X)
    LD C,A
    LD A,(IX+E_TYPE)
    ADD A,C
    LD C,A
    LD A,(ENEMY_TEST_X)
    CP C
    JR C,.BLOCKED
    JR Z,.BLOCKED
.SKIP:
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    POP IX
    POP DE
    POP BC
    XOR A
    RET
.BLOCKED:
    POP IX
    POP DE
    POP BC
    SCF
    RET

; IX -> enemy. Its drawn image will be erased by renderer.
DEACTIVATE_ENEMY:
    XOR A
    LD (IX+E_ACTIVE),A
    LD A,ENEMY_RESPAWN_DELAY
    LD (IX+E_RESPAWN),A
    LD A,1
    LD (IX+E_DIRTY),A
    RET

; IX -> enemy: score is awarded only on destruction.
; Small = 64 points, large = 128 points; difficulty checks happen
; after the score changes so even crossed milestones are caught.
ON_ENEMY_HIT:
    DEC (IX+E_HP)
    JR NZ,.DAMAGED
    CALL START_ENEMY_BLAST
    CALL DEACTIVATE_ENEMY
    CALL RESET_MISS_TRAVEL    ; a kill resets only the 3-screen timer
    LD A,SFX_KILL
    CALL SFX_START
    LD A,(IX+E_TYPE)
    OR A
    LD A,64
    JR Z,.AWARD
    LD A,128
.AWARD:
    JP ADD_SCORE_A
.DAMAGED:
    LD A,SFX_HIT                ; damaged large asteroid, not destroyed
    CALL SFX_START
    LD A,1
    LD (IX+E_DIRTY),A
    RET

; Compare enemies at player row to logical ship X/X+1.
CHECK_SHIP_ENEMY_COLLISIONS:
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    PUSH BC
    CALL CHECK_SHIP_ENEMY_SLOT
    POP BC
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

; Ship occupies one X column and one row.
; Small asteroid: 1x1; large: 2x2.
CHECK_SHIP_ENEMY_SLOT:
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    RET NZ
    LD A,(IX+E_ACTIVE)
    OR A
    RET Z

    ; Same vertical character row(s) as before.
    LD A,(SHIP_NEW_POS+1)
    SUB (IX+E_Y)
    RET C
    OR A
    JR Z,.CHECK_X
    CP 1
    RET NZ
    LD A,(IX+E_TYPE)
    OR A
    RET Z

.CHECK_X:
    ; Half-shifted ship occupies X and X+1. Aligned ship only X.
    LD A,(IX+E_X)
    LD C,A                      ; asteroid left edge
    LD A,(SHIP_NEW_POS)
    CP C
    JR NC,.SHIP_AT_RIGHT
    ; Ship is one cell left of the asteroid: 4px overlap is possible.
    LD A,(SHIP_HALF_POS)
    OR A
    RET Z
    LD A,(SHIP_NEW_POS)
    INC A
    CP C
    RET NZ
    JR .HIT
.SHIP_AT_RIGHT:
    SUB C
    JR Z,.HIT
    CP 1
    RET NZ
    LD A,(IX+E_TYPE)
    OR A
    RET Z                      ; small asteroid is only 1 cell wide
.HIT:
    CALL DEACTIVATE_ENEMY
    LD A,(SHIP_LIVES)
    OR A
    RET Z
    DEC A
    LD (SHIP_LIVES),A
    LD A,1
    LD (HUD_DIRTY),A
    JP START_SHIP_EXPLOSION

; IN: IX=bullet; OUT: carry set iff bullet consumed.
; Preserves IX for caller and all bullet-specific procedures.
CHECK_BULLET_ENEMIES:
    LD B,(IX+B_Y)
    LD C,(IX+B_X)
    LD L,(IX+B_HALF)             ; bullet spans X and X+1 if L=1
    PUSH IX
    LD IX,ENEMY_POOL
    LD H,MAX_ENEMIES
.NEXT:
    LD A,(IX+E_ACTIVE)
    OR A
    JR Z,.SKIP
    ; Only large asteroids occupy two character rows.
    LD A,B
    SUB (IX+E_Y)
    JR C,.SKIP
    OR A
    JR Z,.CHECK_X
    CP 1
    JR NZ,.SKIP
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.SKIP
.CHECK_X:
    LD A,C
    SUB (IX+E_X)               ; bullet base X minus asteroid left X
    JR C,.BULLET_LEFT
    OR A
    JR Z,.HIT
    CP 1
    JR NZ,.SKIP
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.SKIP                 ; aligned bullet right of small
    JR .HIT
.BULLET_LEFT:
    CP #FF                     ; asteroid begins one cell to right?
    JR NZ,.SKIP
    LD A,L                     ; only a half-shifted shot reaches it
    OR A
    JR Z,.SKIP
.HIT:
    CALL ON_ENEMY_HIT
    POP IX
    CALL DEACTIVATE_BULLET
    SCF
    RET
.SKIP:
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DEC H
    JR NZ,.NEXT
    POP IX
    XOR A                       ; carry clear = no hit
    RET

; -------------------------------------------------------------
; RENDER: erase all dirty images, then draw current state.
; -------------------------------------------------------------
RENDER_ERASE_ENEMIES:
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    PUSH BC
    LD A,(IX+E_DIRTY)
    OR A
    JR Z,.SKIP
    LD A,(IX+E_DRAWN)
    OR A
    CALL NZ,ERASE_ENEMY_SLOT
.SKIP:
    POP BC
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

RENDER_DRAW_ENEMIES:
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    PUSH BC
    LD A,(IX+E_DIRTY)
    OR A
    JR Z,.SKIP
    LD A,(IX+E_ACTIVE)
    OR A
    CALL NZ,DRAW_ENEMY_SLOT
    XOR A
    LD (IX+E_DIRTY),A
.SKIP:
    POP BC
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

; Bitmap table layout: 4 shapes per size, 4 rotation frames/shape.
; Index = 2 * ((TYPE*4 + VARIANT)*4 + FRAME), max 62 bytes.
; OUT: DE=bitmap address. Preserves BC, IX.
GET_ENEMY_FRAME:
    LD A,(IX+E_TYPE)
    ADD A,A
    ADD A,A                    ; 4 silhouettes per size
    ADD A,(IX+E_VARIANT)
    ADD A,A
    ADD A,A                    ; 4 frames per silhouette
    ADD A,(IX+E_FRAME)
    ADD A,A                    ; DW pointer offset
    LD E,A
    LD D,0
    LD HL,ENEMY_FRAMES
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
    RET

; OUT: DE=attribute source (1 byte small / 2 bytes large).
; Keeps HL on the destination screen address; IX/BC preserved.
GET_ENEMY_COLOUR:
    PUSH HL
    LD A,(IX+E_SHADE)
    LD E,A
    LD D,0
    LD HL,ENEMY_SMALL_COLOURS
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.LOOKUP
    SLA E                       ; large palette: two attributes/pair
    LD HL,ENEMY_LARGE_COLOURS
.LOOKUP:
    ADD HL,DE
    EX DE,HL
    POP HL
    RET

; -------------------------------------------------------------
; Small asteroid occupies one 8x8 cell.
; Large asteroid occupies two rows of two cells (16x16).
; Direct bitmap copy, no saved background and no OR blending.
; -------------------------------------------------------------

; IN: A=0 top / 1 bottom, IX=enemy.
; DESTROYS: AF, BC, DE, HL. PRESERVES: IX.
DRAW_ENEMY_ROW:
    PUSH AF
    LD B,(IX+E_Y)
    ADD A,B
    LD B,A
    LD C,(IX+E_X)
    CALL GET_SCREEN_ADDR
    POP AF
    PUSH AF
    PUSH HL
    CALL GET_ENEMY_COLOUR
    LD A,(IX+E_TYPE)
    OR A
    JR NZ,.ATTR_WIDE
    CALL RESTORE_ATTR_1_1
    JR .SPRITE
.ATTR_WIDE:
    CALL RESTORE_ATTR_1_2
.SPRITE:
    POP HL
    PUSH HL
    CALL GET_ENEMY_FRAME
    POP HL
    POP AF
    OR A
    JR Z,.DRAW
    PUSH HL
    LD A,(IX+E_TYPE)
    OR A
    LD BC,8
    JR Z,.FRAME_OFFSET
    LD BC,16
.FRAME_OFFSET:
    EX DE,HL
    ADD HL,BC
    EX DE,HL
    POP HL
.DRAW:
    LD A,(IX+E_TYPE)
    OR A
    JP Z,DRAW_1_1
    JP DRAW_1_2

DRAW_ENEMY_SLOT:
    XOR A
    CALL DRAW_ENEMY_ROW
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.SINGLE_ROW
    LD A,1
    CALL DRAW_ENEMY_ROW
.SINGLE_ROW:
    LD A,(IX+E_X)
    LD (IX+E_DRAW_X),A
    LD A,(IX+E_Y)
    LD (IX+E_DRAW_Y),A
    LD A,1
    LD (IX+E_DRAWN),A
    RET

; No writes to screen: collect old 1x1 / 2x2 rectangle.
ERASE_ENEMY_SLOT:
    LD B,(IX+E_DRAW_Y)
    LD C,(IX+E_DRAW_X)
    LD DE,#0101                  ; small = width 1, height 1
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.MARK
    LD DE,#0202                  ; large = width 2, height 2
.MARK:
    CALL STARFIELD_MARK_RECT
    XOR A
    LD (IX+E_DRAWN),A
    RET
