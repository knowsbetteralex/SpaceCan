; -------------------------------------------------------------
; SpaceCan Step 22: centered 3x2 boss after full scroll speed.
; Its separate state survives a lost player life; the current boss
; battle is the DEMO END. Future shooters will precede this battle.
; -------------------------------------------------------------

MAYBE_START_BOSS:
    LD A,(BOSS_STARTED)
    OR A
    RET NZ
    LD A,(SPEED_LEVEL)
    CP SPEED_STAGE_COUNT-1        ; maximum stage, score 32768
    RET NZ
    JP START_BOSS_PHASE

START_BOSS_PHASE:
    LD A,1
    LD (BOSS_STARTED),A
    LD A,BOSS_MAX_HP
    LD (BOSS_HP),A
    CALL BOSS_DISABLE_ASTEROIDS
    CALL RESET_HOSTILE_BULLETS
    ; An asteroid killed at the score threshold may still be exploding.
    ; Let the normal renderer erase its last frame before boss entry.
    XOR A
    LD (BLAST_ACTIVE),A
    LD A,1
    LD (BLAST_DIRTY),A
    XOR A
    LD (SHOOT_WARNING_ACTIVE),A
    LD (MISS_TRAVEL_ROWS),A
    LD A,1
    LD (GAUGE_DIRTY),A
    JP BOSS_RESET_ENTRY

; Restart boss encounter after ship death, preserving damage/HP.
BOSS_RESET_ENTRY:
    CALL BOSS_DISABLE_ASTEROIDS
    LD A,BOSS_X_CENTER
    LD (BOSS_X),A
    LD A,BOSS_START_Y
    LD (BOSS_Y),A
    XOR A
    LD (BOSS_DRAWN),A
    LD (BOSS_FRAME),A
    LD A,BOSS_ENTRY_DELAY
    LD (BOSS_ENTRY_TIMER),A
    LD A,BOSS_ANIM_DELAY
    LD (BOSS_ANIM_TIMER),A
    LD A,BOSS_FIRE_DELAY
    LD (BOSS_FIRE_TIMER),A
    LD A,1
    LD (BOSS_ACTIVE),A
    LD (BOSS_DIRTY),A
    LD (GAUGE_DIRTY),A
    LD A,STATE_BOSS
    LD (GAME_STATE),A
    RET

; Leave DRAWN flag alone: renderer must erase old asteroid pixels.
BOSS_DISABLE_ASTEROIDS:
    PUSH BC
    PUSH DE
    PUSH IX
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    XOR A
    LD (IX+E_ACTIVE),A
    LD A,1
    LD (IX+E_DIRTY),A
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    POP IX
    POP DE
    POP BC
    RET

UPDATE_BOSS:
    LD A,(BOSS_ACTIVE)
    OR A
    RET Z
    ; Boss descends to the center before starting to fire.
    LD A,(BOSS_Y)
    CP BOSS_TARGET_Y
    JR NC,.CENTERED
    LD HL,BOSS_ENTRY_TIMER
    DEC (HL)
    RET NZ
    LD (HL),BOSS_ENTRY_DELAY
    LD HL,BOSS_Y
    INC (HL)
    LD A,1
    LD (BOSS_DIRTY),A
    RET
.CENTERED:
    LD HL,BOSS_ANIM_TIMER
    DEC (HL)
    JR NZ,.FIRE
    LD (HL),BOSS_ANIM_DELAY
    LD HL,BOSS_FRAME
    LD A,(HL)
    XOR 1
    LD (HL),A
    LD A,1
    LD (BOSS_DIRTY),A
.FIRE:
    LD HL,BOSS_FIRE_TIMER
    DEC (HL)
    RET NZ
    LD (HL),BOSS_FIRE_DELAY
    JP BOSS_FIRE_PAIR

; Two muzzles, left and right outside the cockpit.
BOSS_FIRE_PAIR:
    LD A,(BOSS_Y)
    ADD A,2
    LD B,A
    LD A,(BOSS_X)
    LD C,A
    CALL SPAWN_HOSTILE_BULLET     ; preserves BC
    LD A,(BOSS_X)
    ADD A,2
    LD C,A
    JP SPAWN_HOSTILE_BULLET

; IN IX=player bullet. CARRY SET iff bullet consumed on boss.
CHECK_BULLET_BOSS:
    LD A,(BOSS_ACTIVE)
    OR A
    JR Z,.MISS
    LD A,(IX+B_Y)
    LD C,A
    LD A,(BOSS_Y)
    CP C
    JR Z,.CHECK_X
    INC A
    CP C
    JR NZ,.MISS
.CHECK_X:
    LD A,(IX+B_X)
    LD C,A
    LD A,(BOSS_X)
    LD D,A
    LD A,C
    SUB D
    JR C,.LEFT
    CP 3
    JR NC,.MISS
    JR .HIT
.LEFT:
    CP #FF
    JR NZ,.MISS
    LD A,(IX+B_HALF)
    OR A
    JR Z,.MISS
.HIT:
    CALL BOSS_TAKE_HIT
    CALL DEACTIVATE_BULLET
    SCF
    RET
.MISS:
    OR A
    RET

; The same gauge holds 10 boss HP. Each player hit removes one.
BOSS_TAKE_HIT:
    LD HL,BOSS_HP
    LD A,(HL)
    OR A
    RET Z
    DEC (HL)
    LD A,1
    LD (GAUGE_DIRTY),A
    LD (BOSS_DIRTY),A
    LD A,(HL)
    OR A
    JR Z,.DEFEATED
    LD A,SFX_HIT
    JP SFX_START
.DEFEATED:
    XOR A
    LD (BOSS_ACTIVE),A
    LD A,STATE_VICTORY
    LD (GAME_STATE),A
    LD A,SFX_KILL
    JP SFX_START

RENDER_ERASE_BOSS:
    LD A,(BOSS_DIRTY)
    OR A
    RET Z
    LD A,(BOSS_DRAWN)
    OR A
    JR Z,.NEW
    LD B,(BOSS_DRAW_Y)
    LD C,(BOSS_DRAW_X)
    LD DE,#0302
    CALL STARFIELD_MARK_RECT
    XOR A
    LD (BOSS_DRAWN),A
.NEW:
    LD A,(BOSS_ACTIVE)
    OR A
    RET Z
    LD B,(BOSS_Y)
    LD C,(BOSS_X)
    LD DE,#0302
    JP STARFIELD_MARK_RECT

RENDER_DRAW_BOSS:
    LD A,(BOSS_DIRTY)
    OR A
    RET Z
    XOR A
    LD (BOSS_DIRTY),A
    LD A,(BOSS_ACTIVE)
    OR A
    RET Z
    LD A,(BOSS_FRAME)
    OR A
    LD DE,BOSS_SPRITE_0
    JR Z,.TOP
    LD DE,BOSS_SPRITE_1
.TOP:
    XOR A
    CALL DRAW_BOSS_ROW
    LD A,(BOSS_FRAME)
    OR A
    LD DE,BOSS_SPRITE_0+24
    JR Z,.BOTTOM
    LD DE,BOSS_SPRITE_1+24
.BOTTOM:
    LD A,1
    CALL DRAW_BOSS_ROW
    LD A,(BOSS_X)
    LD (BOSS_DRAW_X),A
    LD A,(BOSS_Y)
    LD (BOSS_DRAW_Y),A
    LD A,1
    LD (BOSS_DRAWN),A
    RET

; A=0/1 row, DE=24 bitmap bytes of that row, width 3 cells.
; No special renderer: 3 direct bitmap writes x 8 scan lines.
DRAW_BOSS_ROW:
    PUSH DE
    LD B,(BOSS_Y)
    ADD A,B
    LD B,A
    LD C,(BOSS_X)
    CALL GET_SCREEN_ADDR
    PUSH HL
    LD A,H
    RRCA
    RRCA
    RRCA
    AND 3
    OR #58
    LD H,A
    LD A,#45                     ; bright cyan wings
    LD (HL),A
    INC L
    LD A,#42                     ; red cockpit
    LD (HL),A
    INC L
    LD A,#45
    LD (HL),A
    POP HL
    POP DE
    LD B,8
.PIXEL:
    LD A,(DE)
    LD (HL),A
    INC DE
    INC L
    LD A,(DE)
    LD (HL),A
    INC DE
    INC L
    LD A,(DE)
    LD (HL),A
    INC DE
    DEC L
    DEC L
    INC H
    DJNZ .PIXEL
    RET

; Two 24x16 frames; 3 bytes per scanline, 48 bytes each.
BOSS_SPRITE_0:
    DB #80,#00,#01
    DB #C0,#18,#03
    DB #E1,#3C,#87
    DB #FB,#7E,#DF
    DB #FF,#FF,#FF
    DB #7F,#FF,#FE
    DB #37,#E7,#EC
    DB #3F,#FF,#FC
    DB #3F,#FF,#FC
    DB #1F,#FF,#F8
    DB #0F,#DB,#F0
    DB #07,#BD,#E0
    DB #03,#FF,#C0
    DB #03,#7E,#C0
    DB #02,#3C,#40
    DB #02,#18,#40

BOSS_SPRITE_1:
    DB #80,#00,#01
    DB #C1,#18,#83
    DB #E3,#3C,#C7
    DB #FB,#7E,#DF
    DB #FF,#FF,#FF
    DB #7F,#E7,#FE
    DB #37,#FF,#EC
    DB #3F,#DB,#FC
    DB #3F,#DB,#FC
    DB #1F,#FF,#F8
    DB #0F,#FF,#F0
    DB #07,#BD,#E0
    DB #03,#FF,#C0
    DB #03,#7E,#C0
    DB #02,#3C,#40
    DB #02,#18,#40
