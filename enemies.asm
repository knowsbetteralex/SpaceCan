; -------------------------------------------------------------
; ENEMIES: four independent asteroids (8x16 and 16x16).
;
; IX -> current enemy slot in all *_ENEMY_SLOT routines.
; Four fixed lanes never overlap each other.
; Game logic updates state/dirty; renderer stores drawn position.
; -------------------------------------------------------------

; Initialise four slots from ENEMY_START_TABLE: TYPE, X, Y, PHASE.
INIT_ENEMIES:
    ; Reset all slot states even when game is restarted.
    LD HL,ENEMY_POOL
    LD (HL),0
    LD DE,ENEMY_POOL+1
    LD BC,MAX_ENEMIES*ENEMY_SLOT_SIZE-1
    LDIR

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
    LD (IX+E_X),A
    INC HL
    LD A,(HL)
    LD (IX+E_Y),A
    INC HL
    LD A,1
    LD (IX+E_ACTIVE),A
    LD (IX+E_DIRTY),A
    ; Stagger the four independent animation timers (1..4).
    LD A,(HL)
    LD (IX+E_ANIM_TIMER),A
    LD (IX+E_PHASE),A
    INC HL
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    LD A,4
    LD (ENEMY_MOVE_TIMER),A
    RET

; Q/A speed 1..4 controls move period: 4..1 game ticks.
UPDATE_ENEMIES:
    LD A,(ENEMY_MOVE_TIMER)
    DEC A
    LD (ENEMY_MOVE_TIMER),A
    JR NZ,.NO_MOVE
    LD A,5
    LD HL,SCROLL_SPEED
    SUB (HL)
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
    LD A,(IX+E_ACTIVE)
    OR A
    JR Z,.INACTIVE

    ; Independently animate two rotation frames.
    LD A,(IX+E_ANIM_TIMER)
    DEC A
    LD (IX+E_ANIM_TIMER),A
    JR NZ,.MOVE
    LD A,ENEMY_FRAME_DELAY
    LD (IX+E_ANIM_TIMER),A
    LD A,(IX+E_FRAME)
    XOR 1
    LD (IX+E_FRAME),A
    LD A,1
    LD (IX+E_DIRTY),A
.MOVE:
    LD A,(ENEMY_MOVE_NOW)
    OR A
    RET Z
    LD A,(IX+E_Y)
    CP 22                       ; ship row is Y=22
    JP NC,DEACTIVATE_ENEMY
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

; IX -> enemy. Its drawn image will be erased by renderer.
DEACTIVATE_ENEMY:
    XOR A
    LD (IX+E_ACTIVE),A
    LD A,ENEMY_RESPAWN_DELAY
    LD (IX+E_RESPAWN),A
    LD A,1
    LD (IX+E_DIRTY),A
    RET

; IX -> enemy: one hit = one HP and +5 score (max 95).
ON_ENEMY_HIT:
    DEC (IX+E_HP)
    JR NZ,.STILL_ALIVE
    CALL START_ENEMY_BLAST
    CALL DEACTIVATE_ENEMY
    JR .SCORE
.STILL_ALIVE:
    LD A,1
    LD (IX+E_DIRTY),A
.SCORE:
    LD A,(SCORE)
    CP 95
    RET NC
    ADD A,5
    LD (SCORE),A
    LD A,1
    LD (HUD_DIRTY),A
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

CHECK_SHIP_ENEMY_SLOT:
    LD A,(IX+E_ACTIVE)
    OR A
    RET Z
    ; Ship may touch the top or bottom asteroid cell row.
    LD A,(SHIP_NEW_POS+1)
    SUB (IX+E_Y)
    CP 2
    RET NC
    LD A,(SHIP_NEW_POS)
    LD C,A                       ; ship left column
    LD A,(IX+E_X)
    CP C
    JR Z,.HIT
    LD A,C
    INC A
    CP (IX+E_X)                ; enemy starts at ship right
    JR Z,.HIT
    LD A,(IX+E_TYPE)
    OR A
    RET Z
    LD A,(IX+E_X)
    INC A
    CP C                       ; large enemy ends at ship left
    RET NZ
.HIT:
    CALL DEACTIVATE_ENEMY
    LD A,(SHIP_HP)
    OR A
    RET Z
    SUB 25
    LD (SHIP_HP),A
    LD A,1
    LD (HUD_DIRTY),A
    RET

; IN: IX=bullet; OUT: carry set iff bullet consumed.
; Preserves IX for caller and all bullet-specific procedures.
CHECK_BULLET_ENEMIES:
    LD B,(IX+B_Y)
    LD C,(IX+B_X)
    PUSH IX
    LD IX,ENEMY_POOL
    LD H,MAX_ENEMIES
.NEXT:
    LD A,(IX+E_ACTIVE)
    OR A
    JR Z,.SKIP
    ; Compare both cell rows Y and Y+1, without tunnelling.
    LD A,B
    SUB (IX+E_Y)
    CP 2
    JR NC,.SKIP
    LD A,C
    SUB (IX+E_X)              ; unsigned delta bulletX - enemyX
    JR C,.SKIP
    OR A
    JR Z,.HIT
    CP 1
    JR NZ,.SKIP
    LD A,(IX+E_TYPE)
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

; Frame table order: small0, small1, large0, large1.
; OUT: DE=bitmap address. IX and BC preserved.
GET_ENEMY_FRAME:
    LD A,(IX+E_TYPE)
    ADD A,A
    ADD A,(IX+E_FRAME)
    ADD A,A
    LD E,A
    LD D,0
    LD HL,ENEMY_FRAMES
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
    RET

; -------------------------------------------------------------
; Asteroids occupy two 8-pixel high character rows.
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
    LD A,(IX+E_TYPE)
    OR A
    JR NZ,.ATTR_WIDE
    LD DE,ENEMY_ATTR_SMALL
    CALL RESTORE_ATTR_1_1
    JR .SPRITE
.ATTR_WIDE:
    LD DE,ENEMY_ATTR_LARGE
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
    LD A,1
    CALL DRAW_ENEMY_ROW
    LD A,(IX+E_X)
    LD (IX+E_DRAW_X),A
    LD A,(IX+E_Y)
    LD (IX+E_DRAW_Y),A
    LD A,1
    LD (IX+E_DRAWN),A
    RET

; No writes to screen here: collect the old 1x2 / 2x2 rectangle.
ERASE_ENEMY_SLOT:
    LD B,(IX+E_DRAW_Y)
    LD C,(IX+E_DRAW_X)
    LD DE,#0102                  ; D=width, E=height
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.MARK
    LD D,2
.MARK:
    CALL STARFIELD_MARK_RECT
    XOR A
    LD (IX+E_DRAWN),A
    RET
