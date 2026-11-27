; -------------------------------------------------------------
; SpaceCan demo boss: fixed MIX of aimed, fan, plasma, double
; and homing attacks. In the 6-cell HUD, AVOID + plasma icon
; warns that magenta plasma cannot be shot down.
; -------------------------------------------------------------

; Draw exactly six cells: AVOID (five ROM glyphs) followed
; by the ACTUAL 8x8 invulnerable plasma sprite in magenta.
; Called from RENDER_HUD, never from IM2.
RENDER_BOSS_ATTACK_MODE:
    LD A,(GAME_STATE)
    CP STATE_BOSS
    RET NZ
    LD A,(BOSS_AVOID_DIRTY)
    OR A
    RET Z
    XOR A
    LD (BOSS_AVOID_DIRTY),A
    LD BC,#020D                 ; Y=2 X=13: 'AVOID'
    LD DE,BOSS_AVOID_TEXT
    CALL PRINT_TEXT
    LD BC,#0212                 ; Y=2 X=18: 6th cell, plasma icon
    CALL GET_SCREEN_ADDR
    LD DE,HOSTILE_PLASMA_SPRITE
    CALL DRAW_1_1
    LD HL,#5800+2*32+13
    LD B,5
    LD A,#47                    ; bright white 'AVOID' on black
.TEXT_ATTR:
    LD (HL),A
    INC HL
    DJNZ .TEXT_ATTR
    LD A,(HOSTILE_PLASMA_ATTR)  ; match actual boss projectile
    LD (HL),A
    RET

; Called in boss logic only when the boss is in its firing position.
BOSS_ATTACK_TICK:
    CALL BOSS_TRACK_STILLNESS
    CALL BOSS_TICK_DOUBLE
    JP BOSS_TICK_PLASMA

BOSS_TRACK_STILLNESS:
    LD A,(SHIP_NEW_POS)
    LD HL,BOSS_STILL_LAST_X
    CP (HL)
    JR NZ,.MOVED
    LD A,(SHIP_HALF_POS)
    LD HL,BOSS_STILL_LAST_HALF
    CP (HL)
    JR NZ,.MOVED
    LD HL,BOSS_STILL_FRAMES
    LD A,(HL)
    CP BOSS_STILL_LIMIT
    RET NC
    INC (HL)
    RET
.MOVED:
    LD A,(SHIP_NEW_POS)
    LD (BOSS_STILL_LAST_X),A
    LD A,(SHIP_HALF_POS)
    LD (BOSS_STILL_LAST_HALF),A
    XOR A
    LD (BOSS_STILL_FRAMES),A
    RET

; Delayed second shot from the same cannon toward the SAME
; launch-time target, not a fresh auto-aim that would feel unfair.
BOSS_TICK_DOUBLE:
    LD HL,BOSS_DOUBLE_WAIT
    LD A,(HL)
    OR A
    RET Z
    DEC (HL)
    RET NZ
    CALL BOSS_SHOT_ORIGIN
    LD A,(BOSS_DOUBLE_X)
    LD C,A
    LD A,HB_KIND_NORMAL
    LD (HOSTILE_SPAWN_KIND),A
    LD A,(BOSS_DOUBLE_TARGET)
    JP SPAWN_HOSTILE_BULLET

; Visible cockpit warning, then a slow magenta plasma charge.
BOSS_TICK_PLASMA:
    LD HL,BOSS_PLASMA_CHARGE
    LD A,(HL)
    OR A
    RET Z
    DEC (HL)
    LD A,1
    LD (BOSS_DIRTY),A         ; alternate cockpit red/white
    LD A,(HL)
    OR A
    RET NZ
    CALL BOSS_SHOT_ORIGIN
    LD A,HB_KIND_PLASMA
    LD (HOSTILE_SPAWN_KIND),A
    LD A,(BOSS_PLASMA_TARGET)
    JP SPAWN_HOSTILE_BULLET

BOSS_FIRE_DISPATCH:
    XOR A
    LD (HOSTILE_SPAWN_KIND),A
    ; Fixed MIX: aimed, fan, plasma, delayed double, homing.
    ; While stationary the next volley becomes plasma.
    LD A,(BOSS_ATTACK_CYCLE)
    LD (BOSS_SELECTED_ATTACK),A
    INC A
    CP 5
    JR C,.CYCLE_READY
    XOR A
.CYCLE_READY:
    LD (BOSS_ATTACK_CYCLE),A
    ; In MIX double volleys are activated after 50% boss damage.
    LD A,(BOSS_SELECTED_ATTACK)
    CP 3
    JR NZ,.CHECK_STILL
    LD A,(BOSS_HP)
    CP BOSS_MAX_HP/2+1
    JR C,.CHECK_STILL
    XOR A
    LD (BOSS_SELECTED_ATTACK),A
.CHECK_STILL:
    LD A,(BOSS_STILL_FRAMES)
    CP BOSS_STILL_LIMIT
    JR C,.MIX_READY
    LD A,2                    ; anti-camping plasma
    LD (BOSS_SELECTED_ATTACK),A
.MIX_READY:
    LD A,(BOSS_SELECTED_ATTACK)
    JP BOSS_FIRE_CHOSEN
; A=0 aimed, 1 fan, 2 plasma, 3 double, 4 homing.
BOSS_FIRE_CHOSEN:
    OR A
    JP Z,BOSS_FIRE_PAIR
    DEC A
    JP Z,BOSS_FIRE_FAN
    DEC A
    JP Z,BOSS_FIRE_PLASMA
    DEC A
    JP Z,BOSS_FIRE_DOUBLE
    JP BOSS_FIRE_HOMING

; IN B=spawn row, C=center launcher. Destroys A only.
BOSS_SHOT_ORIGIN:
    LD A,(BOSS_Y)
    ADD A,2
    LD B,A
    LD A,(BOSS_X)
    INC A
    LD C,A
    RET

BOSS_FIRE_FAN:
    CALL BOSS_SHOT_ORIGIN
    DEC C                     ; left launcher
    LD A,(SHIP_NEW_POS)
    SUB 2
    CP PLAYFIELD_LEFT
    JR NC,.LEFT_READY
    LD A,PLAYFIELD_LEFT
.LEFT_READY:
    CALL SPAWN_HOSTILE_BULLET
    INC C                     ; middle launcher
    LD A,(SHIP_NEW_POS)
    CALL SPAWN_HOSTILE_BULLET
    INC C                     ; right launcher
    LD A,(SHIP_NEW_POS)
    ADD A,2
    CP PLAYFIELD_RIGHT
    JR C,.RIGHT_READY
    LD A,PLAYFIELD_RIGHT
.RIGHT_READY:
    JP SPAWN_HOSTILE_BULLET

BOSS_FIRE_PLASMA:
    LD A,BOSS_PLASMA_WARMUP
    LD (BOSS_PLASMA_CHARGE),A
    LD A,(SHIP_NEW_POS)
    LD (BOSS_PLASMA_TARGET),A
    LD A,1
    LD (BOSS_DIRTY),A
    RET

BOSS_FIRE_DOUBLE:
    CALL BOSS_SHOT_ORIGIN
    LD A,C
    LD (BOSS_DOUBLE_X),A
    LD A,(SHIP_NEW_POS)
    LD (BOSS_DOUBLE_TARGET),A
    CALL SPAWN_HOSTILE_BULLET
    LD A,BOSS_DOUBLE_DELAY
    LD (BOSS_DOUBLE_WAIT),A
    RET

BOSS_FIRE_HOMING:
    CALL BOSS_SHOT_ORIGIN
    LD A,HB_KIND_HOMING
    LD (HOSTILE_SPAWN_KIND),A
    LD A,(SHIP_NEW_POS)
    JP SPAWN_HOSTILE_BULLET

BOSS_AVOID_DIRTY: DB 1
BOSS_ATTACK_CYCLE: DB 0
BOSS_SELECTED_ATTACK: DB 0
BOSS_STILL_LAST_X: DB 0
BOSS_STILL_LAST_HALF: DB 0
BOSS_STILL_FRAMES: DB 0
BOSS_PLASMA_CHARGE: DB 0
BOSS_PLASMA_TARGET: DB 0
BOSS_DOUBLE_WAIT: DB 0
BOSS_DOUBLE_TARGET: DB 0
BOSS_DOUBLE_X: DB 0

BOSS_AVOID_TEXT: DB "AVOID",0
