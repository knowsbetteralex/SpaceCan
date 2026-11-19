; -------------------------------------------------------------
; Experimental boss-attack laboratory. Switch live with keys 0..6.
; 0=MIX, 1=AIM, 2=FAN, 3=PLASMA, 4=DOUBLE, 5=HOMING,
; 6=ADAPT (ordinary aimed volley, plasma if ship stays still).
; All attacks use the same 12-slot hostile bullet pool and dirty
; renderer. No random numbers or multiplies on the Spectrum.
; -------------------------------------------------------------
BOSS_MODE_MIX    EQU 0
BOSS_MODE_AIM    EQU 1
BOSS_MODE_FAN    EQU 2
BOSS_MODE_PLASMA EQU 3
BOSS_MODE_DOUBLE EQU 4
BOSS_MODE_HOMING EQU 5
BOSS_MODE_ADAPT  EQU 6

; One edge-triggered keyboard action: ZX row #F7FE keys 1..5
; and row #EFFE keys 0 and 6. Preserve normal O/P/SPACE controls.
BOSS_READ_ATTACK_KEYS:
    LD A,(GAME_STATE)
    CP STATE_BOSS
    RET NZ
    LD BC,#F7FE
    IN A,(C)
    CPL
    AND #1F
    JR NZ,.ONE_TO_FIVE
    LD BC,#EFFE
    IN A,(C)
    CPL
    AND #11                 ; 0:bit0, 6:bit4
    JR Z,.RELEASE
    BIT 0,A
    LD A,BOSS_MODE_MIX
    JR NZ,.SELECT
    LD A,BOSS_MODE_ADAPT
    JR .SELECT
.ONE_TO_FIVE:
    LD D,A
    LD A,BOSS_MODE_AIM
    BIT 0,D
    JR NZ,.SELECT
    INC A
    BIT 1,D
    JR NZ,.SELECT
    INC A
    BIT 2,D
    JR NZ,.SELECT
    INC A
    BIT 3,D
    JR NZ,.SELECT
    INC A
.SELECT:
    LD D,A
    LD A,(BOSS_MODE_KEY_HELD)
    OR A
    RET NZ
    LD A,1
    LD (BOSS_MODE_KEY_HELD),A
    LD A,D
    LD (BOSS_ATTACK_MODE),A
    XOR A
    LD (BOSS_ATTACK_CYCLE),A
    LD (BOSS_DOUBLE_WAIT),A
    LD A,1
    LD (BOSS_MODE_DIRTY),A
    RET
.RELEASE:
    XOR A
    LD (BOSS_MODE_KEY_HELD),A
    RET

; Render exactly six characters in the unused boss HUD window
; Y=2 X=13..18, where asteroid rounds show SHOOT! instead.
RENDER_BOSS_ATTACK_MODE:
    LD A,(GAME_STATE)
    CP STATE_BOSS
    RET NZ
    LD A,(BOSS_MODE_DIRTY)
    OR A
    RET Z
    XOR A
    LD (BOSS_MODE_DIRTY),A
    LD A,(BOSS_ATTACK_MODE)
    ADD A,A
    LD E,A
    LD D,0
    LD HL,BOSS_MODE_STRINGS
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
    LD BC,#020D
    CALL PRINT_TEXT
    LD HL,#5800+2*32+13
    LD A,#45
    LD B,6
.PAINT:
    LD (HL),A
    INC HL
    DJNZ .PAINT
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
    LD A,(BOSS_ATTACK_MODE)
    OR A
    JR Z,.MIX
    CP BOSS_MODE_ADAPT
    JR Z,.ADAPT
    ; Explicit test modes 1..5 map to aimed/fan/plasma/double/homing.
    DEC A
    JP BOSS_FIRE_CHOSEN
.MIX:
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
.ADAPT:
    LD A,(BOSS_STILL_FRAMES)
    CP BOSS_STILL_LIMIT
    LD A,0                    ; aimed pair when moving
    JR C,.ADAPT_READY
    LD A,2                    ; plasma after 100 stationary frames
.ADAPT_READY:
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

BOSS_ATTACK_MODE: DB BOSS_DEFAULT_ATTACK_MODE
BOSS_MODE_KEY_HELD: DB 0
BOSS_MODE_DIRTY: DB 1
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

BOSS_MODE_STRINGS:
    DW BOSS_MODE_TEXT_MIX,BOSS_MODE_TEXT_AIM,BOSS_MODE_TEXT_FAN
    DW BOSS_MODE_TEXT_PLASMA,BOSS_MODE_TEXT_DOUBLE
    DW BOSS_MODE_TEXT_HOMING,BOSS_MODE_TEXT_ADAPT
BOSS_MODE_TEXT_MIX: DB "0:MIX ",0
BOSS_MODE_TEXT_AIM: DB "1:AIM ",0
BOSS_MODE_TEXT_FAN: DB "2:FAN ",0
BOSS_MODE_TEXT_PLASMA: DB "3:PLAS",0
BOSS_MODE_TEXT_DOUBLE: DB "4:DUAL",0
BOSS_MODE_TEXT_HOMING: DB "5:HOME",0
BOSS_MODE_TEXT_ADAPT: DB "6:ADPT",0
