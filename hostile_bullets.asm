; -------------------------------------------------------------
; Shared hostile bullets (boss now, manoeuvring shooters later).
; 12 slots x 10 bytes, one 8x8 sprite per shot.
; Normal/plasma/homing types share the same movement and dirty renderer.
; -------------------------------------------------------------

HB_ACTIVE  EQU 0
HB_X       EQU 1
HB_Y       EQU 2
HB_DRAWN   EQU 3
HB_DRAW_X  EQU 4
HB_DRAW_Y  EQU 5
HB_DIRTY   EQU 6
HB_TARGET_X EQU 7
HB_KIND     EQU 8
HB_STEP     EQU 9
HB_KIND_NORMAL EQU 0
HB_KIND_PLASMA EQU 1
HB_KIND_HOMING EQU 2

RESET_HOSTILE_BULLETS:
    LD HL,HOSTILE_BULLET_POOL
    LD (HL),0
    LD DE,HOSTILE_BULLET_POOL+1
    LD BC,MAX_HOSTILE_BULLETS*HOSTILE_BULLET_SIZE-1
    LDIR
    LD A,HOSTILE_MOVE_DELAY
    LD (HOSTILE_BULLET_CLOCK),A
    RET

; IN B=spawn Y, C=spawn X, A=target X (fixed once launched).
; PRESERVES BC,DE,IX. DESTROYS AF,HL.
SPAWN_HOSTILE_BULLET:
    PUSH BC
    PUSH DE
    PUSH IX
    LD E,A                        ; keep target during slot search
    LD IX,HOSTILE_BULLET_POOL
    LD D,MAX_HOSTILE_BULLETS
.FIND:
    LD A,(IX+HB_ACTIVE)
    OR A
    JR NZ,.NEXT
    LD A,(IX+HB_DRAWN)
    OR A
    JR NZ,.NEXT
    LD (IX+HB_X),C
    LD (IX+HB_Y),B
    LD (IX+HB_TARGET_X),E
    LD A,(HOSTILE_SPAWN_KIND)
    LD (IX+HB_KIND),A
    XOR A
    LD (IX+HB_STEP),A
    LD A,1
    LD (IX+HB_ACTIVE),A
    LD (IX+HB_DIRTY),A
    ; Only a boss volley opens the duel; keep this shared pool
    ; usable by ordinary shooters in later stages of SpaceCan.
    LD A,(GAME_STATE)
    CP STATE_BOSS
    JR NZ,.DONE
    LD A,1
    LD (BOSS_FIGHT_READY),A    ; actual spawn, not plasma warmup
    JR .DONE
.NEXT:
    ; Save requested YX in BC and retain D as the slot counter.
    PUSH BC
    LD BC,HOSTILE_BULLET_SIZE
    ADD IX,BC
    POP BC
    DEC D
    JR NZ,.FIND
.DONE:
    POP IX
    POP DE
    POP BC
    RET

UPDATE_HOSTILE_BULLETS:
    LD HL,HOSTILE_BULLET_CLOCK
    DEC (HL)
    JR NZ,.NO_STEP
    LD (HL),HOSTILE_MOVE_DELAY
    LD A,1
    LD (HOSTILE_MOVE_NOW),A
    JR .SCAN
.NO_STEP:
    XOR A
    LD (HOSTILE_MOVE_NOW),A
.SCAN:
    LD IX,HOSTILE_BULLET_POOL
    LD B,MAX_HOSTILE_BULLETS
.NEXT:
    PUSH BC
    CALL UPDATE_HOSTILE_SLOT
    POP BC
    LD DE,HOSTILE_BULLET_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

UPDATE_HOSTILE_SLOT:
    LD A,(GAME_STATE)
    CP STATE_BOSS
    RET NZ
    LD A,(IX+HB_ACTIVE)
    OR A
    RET Z
    LD A,(HOSTILE_MOVE_NOW)
    OR A
    JR Z,.CHECK_SHIP
    LD A,(IX+HB_Y)
    CP PLAYFIELD_BOTTOM
    JR NC,.EXPIRE
    INC A
    LD (IX+HB_Y),A
    CALL HOSTILE_ADJUST_HOMING

    ; One horizontal cell per vertical step, toward launch target.
    ; No live homing: player can dodge the aimed projectile.
    LD A,(IX+HB_X)
    LD C,A
    LD A,(IX+HB_TARGET_X)
    CP C
    JR Z,.MOVED
    JR C,.MOVE_LEFT
    INC (IX+HB_X)
    JR .MOVED
.MOVE_LEFT:
    DEC (IX+HB_X)
.MOVED:
    LD A,1
    LD (IX+HB_DIRTY),A
.CHECK_SHIP:
    LD A,(IX+HB_Y)
    LD C,A
    LD A,(SHIP_NEW_POS+1)
    CP C
    RET NZ
    LD A,(IX+HB_X)
    LD C,A
    LD A,(SHIP_NEW_POS)
    CP C
    JR Z,.HIT
    LD A,(SHIP_HALF_POS)
    OR A
    RET Z
    LD A,(SHIP_NEW_POS)
    INC A
    CP C
    RET NZ
.HIT:
    CALL DEACTIVATE_HOSTILE_SLOT
    LD A,(SHIP_LIVES)
    OR A
    RET Z
    DEC A
    LD (SHIP_LIVES),A
    LD A,1
    LD (HUD_DIRTY),A
    JP START_SHIP_EXPLOSION
.EXPIRE:
    JP DEACTIVATE_HOSTILE_SLOT

; Homing adjusts its goal every third vertical step, but stops
; tracking for the final five rows so a dodge stays possible.
HOSTILE_ADJUST_HOMING:
    LD A,(IX+HB_KIND)
    CP HB_KIND_HOMING
    RET NZ
    LD A,(IX+HB_Y)
    CP PLAYFIELD_BOTTOM-5
    RET NC
    INC (IX+HB_STEP)
    LD A,(IX+HB_STEP)
    CP 3
    RET C
    XOR A
    LD (IX+HB_STEP),A
    LD A,(SHIP_NEW_POS)
    LD (IX+HB_TARGET_X),A
    RET

DEACTIVATE_HOSTILE_SLOT:
    XOR A
    LD (IX+HB_ACTIVE),A
    LD A,1
    LD (IX+HB_DIRTY),A
    RET

; Player/hostile bullets annihilate one another on contact.
; IN IX=player bullet, preserves IX; OUT carry set if consumed.
CHECK_BULLET_HOSTILES:
    LD A,(BOSS_STARTED)
    OR A
    JR Z,.MISS
    PUSH IY
    LD IY,HOSTILE_BULLET_POOL
    LD B,MAX_HOSTILE_BULLETS
.NEXT:
    LD A,(IY+HB_ACTIVE)
    OR A
    JR Z,.SKIP
    LD A,(IX+B_Y)
    CP (IY+HB_Y)
    JR NZ,.SKIP
    LD A,(IX+B_X)
    CP (IY+HB_X)
    JR Z,.HIT
    LD A,(IX+B_HALF)
    OR A
    JR Z,.SKIP
    LD A,(IX+B_X)
    INC A
    CP (IY+HB_X)
    JR NZ,.SKIP
.HIT:
    ; The plasma sphere survives contact. Other shots annihilate.
    LD A,(IY+HB_KIND)
    CP HB_KIND_PLASMA
    JR Z,.SPARK_ONLY
    XOR A
    LD (IY+HB_ACTIVE),A
    LD A,1
    LD (IY+HB_DIRTY),A
.SPARK_ONLY:
    LD B,(IY+HB_Y)
    LD C,(IY+HB_X)
    CALL SPAWN_BULLET_IMPACT
    LD A,SFX_HIT
    CALL SFX_START
    POP IY
    CALL DEACTIVATE_BULLET
    SCF
    RET
.SKIP:
    LD DE,HOSTILE_BULLET_SIZE
    ADD IY,DE
    DJNZ .NEXT
    POP IY
.MISS:
    OR A
    RET

RENDER_ERASE_HOSTILE_BULLETS:
    LD A,(BOSS_STARTED)
    OR A
    RET Z
    LD IX,HOSTILE_BULLET_POOL
    LD B,MAX_HOSTILE_BULLETS
.NEXT:
    PUSH BC
    LD A,(IX+HB_DIRTY)
    OR A
    JR Z,.SKIP
    LD A,(IX+HB_DRAWN)
    OR A
    JR Z,.NEW
    LD B,(IX+HB_DRAW_Y)
    LD C,(IX+HB_DRAW_X)
    LD DE,#0101
    CALL STARFIELD_MARK_RECT
    XOR A
    LD (IX+HB_DRAWN),A
.NEW:
    LD A,(IX+HB_ACTIVE)
    OR A
    JR Z,.SKIP
    LD B,(IX+HB_Y)
    LD C,(IX+HB_X)
    LD DE,#0101
    CALL STARFIELD_MARK_RECT
.SKIP:
    POP BC
    LD DE,HOSTILE_BULLET_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

RENDER_DRAW_HOSTILE_BULLETS:
    LD A,(BOSS_STARTED)
    OR A
    RET Z
    LD IX,HOSTILE_BULLET_POOL
    LD B,MAX_HOSTILE_BULLETS
.NEXT:
    PUSH BC
    LD A,(IX+HB_DIRTY)
    OR A
    JR Z,.SKIP
    XOR A
    LD (IX+HB_DIRTY),A
    LD A,(IX+HB_ACTIVE)
    OR A
    JR Z,.SKIP
    LD B,(IX+HB_Y)
    LD C,(IX+HB_X)
    CALL GET_SCREEN_ADDR
    LD A,(IX+HB_KIND)
    CP HB_KIND_PLASMA
    JR Z,.PLASMA
    CP HB_KIND_HOMING
    JR Z,.HOMING
    LD DE,HOSTILE_BULLET_ATTR
    CALL RESTORE_ATTR_1_1
    LD DE,HOSTILE_BULLET_SPRITE
    CALL DRAW_1_1
    JR .DRAWN
.PLASMA:
    LD DE,HOSTILE_PLASMA_ATTR
    CALL RESTORE_ATTR_1_1
    LD DE,HOSTILE_PLASMA_SPRITE
    CALL DRAW_1_1
    JR .DRAWN
.HOMING:
    LD DE,HOSTILE_HOMING_ATTR
    CALL RESTORE_ATTR_1_1
    LD DE,HOSTILE_HOMING_SPRITE
    CALL DRAW_1_1
.DRAWN:
    LD A,(IX+HB_X)
    LD (IX+HB_DRAW_X),A
    LD A,(IX+HB_Y)
    LD (IX+HB_DRAW_Y),A
    LD A,1
    LD (IX+HB_DRAWN),A
.SKIP:
    POP BC
    LD DE,HOSTILE_BULLET_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

HOSTILE_MOVE_NOW: DB 0
HOSTILE_SPAWN_KIND: DB HB_KIND_NORMAL
HOSTILE_BULLET_ATTR: DB #42
HOSTILE_BULLET_SPRITE:
    DB %00011000
    DB %00111100
    DB %01111110
    DB %11111111
    DB %01111110
    DB %00111100
    DB %00011000
    DB %00000000

; Distinct projectiles: magenta, unsmashable plasma and yellow tracker.
HOSTILE_PLASMA_ATTR: DB #43
HOSTILE_PLASMA_SPRITE:
    DB %00100100
    DB %01111110
    DB %11111111
    DB %11011011
    DB %11011011
    DB %11111111
    DB %01111110
    DB %00100100

HOSTILE_HOMING_ATTR: DB #46
HOSTILE_HOMING_SPRITE:
    DB %00011000
    DB %00111100
    DB %01111110
    DB %11011011
    DB %11111111
    DB %01111110
    DB %00100100
    DB %01000010
