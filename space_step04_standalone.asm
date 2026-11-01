; ===== main.asm =====
; ZX Space Demo - Step 04: layered dirty-cell starfield.
; ZX Spectrum 48K / Delta-C, sjasmplus syntax.
;
; Coordinates are in 8x8 character cells: X in low byte, Y in high byte.
; HUD: Y=0..1, corridor: X=6..25, Y=2..23.
; Render after HALT; update logic and moving stars for NEXT frame.

    ORG #9000

BLAST_FRAME_DURATION EQU 4
BLAST_FRAME_COUNT    EQU 4
PLAYFIELD_TOP        EQU 2
MAX_BULLETS          EQU 6
BULLET_SLOT_SIZE     EQU 8
MAX_ENEMIES          EQU 4
ENEMY_SLOT_SIZE      EQU 16
ENEMY_FRAME_DELAY    EQU 4
ENEMY_RESPAWN_DELAY  EQU 24

; One 16-byte slot for opaque two-row asteroids; no saved background.
E_ACTIVE       EQU 0
E_TYPE         EQU 1           ; 0=8x16, 1=16x16
E_HP           EQU 2
E_X            EQU 3
E_Y            EQU 4
E_DRAWN        EQU 5
E_DRAW_X       EQU 6
E_DRAW_Y       EQU 7
E_DIRTY        EQU 8
E_FRAME        EQU 9
E_ANIM_TIMER   EQU 10
E_RESPAWN      EQU 11
E_PHASE        EQU 12          ; first animation timer value

; -------------------------------------------------------------
; Border phase diagnostics for ZX Spectrum 48K.
;
; Set DEBUG_BORDER=0 for a normal game build (no phase code emitted).
; Current beeper driver is not installed yet. When enabling beeper
; sound, use a shared #FE output routine to preserve MIC/EAR bits.
; -------------------------------------------------------------

DEBUG_BORDER EQU 1

DBG_RENDER_COLOUR EQU 2  ; red: sprites/background
DBG_HUD_COLOUR    EQU 6  ; yellow: HUD
DBG_INPUT_COLOUR  EQU 5  ; cyan: keyboard
DBG_LOGIC_COLOUR  EQU 4  ; green: game update
DBG_IDLE_COLOUR   EQU 1  ; blue: remainder of frame / HALT

MACRO DEBUG_PHASE colour
    IF DEBUG_BORDER
        LD A,colour
        OUT (#FE),A
    ENDIF
ENDM


; Each bullet slot is exactly 8 bytes (offsets from IX).
B_ACTIVE    EQU 0  ; 0=free, 1=just spawned, 2=flying
B_X         EQU 1
B_Y         EQU 2
B_DRAWN     EQU 3
B_DRAW_X    EQU 4
B_DRAW_Y    EQU 5
B_DIRTY     EQU 6
B_RESERVED  EQU 7       ; padding; no saved background

START:
    DI
    CALL CLEAR_BITMAP
    CALL DRAW_STATIC_UI
    LD A,1
    OUT (#FE),A                  ; blue border

    ; Initialise bullet slots (state only, no saved background).
    LD HL,BULLET_POOL
    LD (HL),0
    LD DE,BULLET_POOL+1
    LD BC,MAX_BULLETS*BULLET_SLOT_SIZE-1
    LDIR

    CALL INIT_ENEMIES
    CALL STARFIELD_INIT

    XOR A
    LD (SHIP_DRAWN),A
    LD (BLAST_ACTIVE),A
    LD (BLAST_DRAWN),A
    LD (BLAST_FRAME),A
    LD (SCORE),A
    LD (BULLET_COUNT),A
    LD (SPACE_HELD),A
    LD (SPEED_UP_HELD),A
    LD (SPEED_DOWN_HELD),A
    LD (BLAST_DIRTY),A

    LD A,1
    LD (SCROLL_SPEED),A         ; stars and asteroid speed
    LD (HUD_DIRTY),A
    LD (SHIP_DIRTY),A

    LD HL,(SHIP_START_POS)
    LD (SHIP_CUR_POS),HL
    LD (SHIP_NEW_POS),HL
    XOR A
    LD (BLAST_TYPE),A
    LD HL,BLAST_FRAME_0
    LD (BLAST_FRAME_PTR),HL

    IM 1                         ; 48K ROM interrupt handler
    EI

MAIN_LOOP:
    HALT
    DEBUG_PHASE DBG_RENDER_COLOUR
    CALL RENDER_FRAME            ; all graphics first
    DEBUG_PHASE DBG_HUD_COLOUR
    CALL RENDER_HUD              ; only when UI fields changed
    DEBUG_PHASE DBG_INPUT_COLOUR
    CALL READ_INPUT              ; capture next game state
    DEBUG_PHASE DBG_LOGIC_COLOUR
    CALL UPDATE_GAME             ; movement, hits, animations
    DEBUG_PHASE DBG_IDLE_COLOUR ; visible idle border during HALT
    JR MAIN_LOOP

; ===== logic.asm =====
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

; ===== bullets.asm =====
; -------------------------------------------------------------
; BULLET POOL (6 x 8 bytes)
;
; A slot is reusable only when ACTIVE=0 and DRAWN=0.
; ACTIVE=0 free, 1 just spawned, 2 in flight.
; DRAWN refers to pixels present on screen right now.
; DIRTY indicates that this slot must be erased/redrawn.
;
; Each bullet travels 2 character rows (16 pixels) per tick.
; Collision is checked after EACH one-row move, avoiding tunneling.
; IX always points to the current slot inside *_SLOT procedures.
; -------------------------------------------------------------

; Find a free slot and spawn a bullet directly above the ship.
; Spawned bullet stays at Y=ship-1 for its first visible frame.
; DESTROYS AF, BC, DE, HL, IX.
FIRE_BULLET:
    LD A,(BULLET_COUNT)
    CP MAX_BULLETS
    RET Z
    LD IX,BULLET_POOL
    LD B,MAX_BULLETS
.FIND_SLOT:
    LD A,(IX+B_ACTIVE)
    OR A
    JR NZ,.NEXT_SLOT
    LD A,(IX+B_DRAWN)
    OR A
    JR NZ,.NEXT_SLOT

    LD HL,(SHIP_NEW_POS)
    INC L                        ; centre (right cell of ship)
    DEC H                        ; one row above the ship
    LD (IX+B_X),L
    LD (IX+B_Y),H
    LD A,1
    LD (IX+B_ACTIVE),A
    LD (IX+B_DIRTY),A
    LD HL,BULLET_COUNT
    INC (HL)
    LD (HUD_DIRTY),A
    RET
.NEXT_SLOT:
    LD DE,BULLET_SLOT_SIZE
    ADD IX,DE
    DJNZ .FIND_SLOT
    RET

; Apply 2 discrete one-row steps to every active bullet.
; Save BC around per-slot calls: inner routines freely change BC.
UPDATE_BULLETS:
    LD IX,BULLET_POOL
    LD B,MAX_BULLETS
.NEXT:
    PUSH BC
    CALL UPDATE_BULLET_SLOT
    POP BC
    LD DE,BULLET_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

UPDATE_BULLET_SLOT:
    LD A,(IX+B_ACTIVE)
    OR A
    RET Z
    ; An asteroid may have moved onto this bullet's previous cell.
    ; Resolve it before the bullet advances.
    CALL CHECK_BULLET_COLLISION
    LD A,(IX+B_ACTIVE)
    OR A
    RET Z
    CP 1
    JR NZ,.FLYING
    ; The first tick after SPACE only makes the new bullet ready.
    ; Its first visible position is adjacent to the ship's nose.
    LD A,2
    LD (IX+B_ACTIVE),A
    RET
.FLYING:
    CALL BULLET_STEP_ONE
    LD A,(IX+B_ACTIVE)
    OR A
    RET Z
    CALL BULLET_STEP_ONE
    LD A,1
    LD (IX+B_DIRTY),A
    RET

; A one-row step may end the bullet or cause a collision.
; Y=2 is the top playable row. Never write a bullet into HUD Y=0/1.
BULLET_STEP_ONE:
    LD A,(IX+B_Y)
    CP PLAYFIELD_TOP
    JR Z,.EXIT_FIELD
    DEC A
    LD (IX+B_Y),A
    JP CHECK_BULLET_COLLISION
.EXIT_FIELD:
    JP DEACTIVATE_BULLET

; Check moving enemies and absorb bullets entering an explosion.
CHECK_BULLET_COLLISION:
    CALL CHECK_BULLET_ENEMIES
    RET C
    LD A,(BLAST_ACTIVE)
    OR A
    RET Z
    LD A,(BLAST_POS+1)
    CP (IX+B_Y)
    RET NZ
    LD A,(BLAST_POS)
    CP (IX+B_X)
    JR Z,.ABSORB
    LD A,(BLAST_TYPE)
    OR A
    RET Z                       ; small explosion occupies only X
    LD A,(BLAST_POS)
    INC A
    CP (IX+B_X)
    RET NZ
.ABSORB:
    JP DEACTIVATE_BULLET

; Only call for ACTIVE=1. The old DRAWN image (if any) is left
; intact until the next RENDER_ERASE_BULLETS pass.
DEACTIVATE_BULLET:
    XOR A
    LD (IX+B_ACTIVE),A
    LD A,1
    LD (IX+B_DIRTY),A
    LD HL,BULLET_COUNT
    DEC (HL)
    LD (HUD_DIRTY),A
    RET

; -------------------------------------------------------------
; Selective bullet rendering. No saved background: erase old cell
; to base corridor ink/paper, then draw active bullet opaque.
; -------------------------------------------------------------
RENDER_ERASE_BULLETS:
    LD IX,BULLET_POOL
    LD B,MAX_BULLETS
.NEXT:
    PUSH BC
    LD A,(IX+B_DIRTY)
    OR A
    JR Z,.SKIP
    LD A,(IX+B_DRAWN)
    OR A
    CALL NZ,ERASE_BULLET_SLOT
.SKIP:
    POP BC
    LD DE,BULLET_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

RENDER_DRAW_BULLETS:
    LD IX,BULLET_POOL
    LD B,MAX_BULLETS
.NEXT:
    PUSH BC
    LD A,(IX+B_DIRTY)
    OR A
    JR Z,.SKIP
    LD A,(IX+B_ACTIVE)
    OR A
    CALL NZ,DRAW_BULLET_SLOT
    XOR A
    LD (IX+B_DIRTY),A
.SKIP:
    POP BC
    LD DE,BULLET_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

; IX preserved; all coordinates in character cells.
DRAW_BULLET_SLOT:
    LD B,(IX+B_Y)
    LD C,(IX+B_X)
    CALL GET_SCREEN_ADDR
    LD DE,BULLET_ATTR
    CALL RESTORE_ATTR_1_1
    LD DE,BULLET_SPRITE
    CALL DRAW_1_1

    LD A,(IX+B_X)
    LD (IX+B_DRAW_X),A
    LD A,(IX+B_Y)
    LD (IX+B_DRAW_Y),A
    LD A,1
    LD (IX+B_DRAWN),A
    RET

ERASE_BULLET_SLOT:
    LD B,(IX+B_DRAW_Y)
    LD C,(IX+B_DRAW_X)
    LD DE,#0101
    CALL STARFIELD_MARK_RECT
    XOR A
    LD (IX+B_DRAWN),A
    RET

; ===== enemies.asm =====
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

; ===== starfield.asm =====
; -------------------------------------------------------------
; STARFIELD: 16 moving single-pixel stars, two slower layers.
;
; Record: X character cell, Y pixel, pixel bit mask, period mask.
; Period 1: +speed pixels every 2 frames.
; Period 3: +speed pixels every 4 frames. speed=1..3.
;
; Render order:
;   1) invalidate foreground sprites touched by star changes;
;   2) add old foreground rectangles to the dirty-cell queue;
;   3) clear each dirty cell once;
;   4) draw changed opaque sprites;
;   5) OR new stars LAST, even over asteroids (intended effect).
; No saved background and no full-screen clearing.
; -------------------------------------------------------------

S_X       EQU 0
S_Y       EQU 1
S_MASK    EQU 2
S_PERIOD  EQU 3
STAR_SIZE EQU 4
STAR_COUNT EQU 16
DIRTY_LIMIT EQU 160

STARFIELD_INIT:
    LD HL,DIRTY_MAP
    LD (HL),0
    LD DE,DIRTY_MAP+1
    LD BC,768-1
    LDIR
    XOR A
    LD (DIRTY_COUNT),A
    LD (STAR_CLOCK),A
    LD HL,DIRTY_QUEUE
    LD (DIRTY_TAIL),HL

    LD IX,STAR_POOL
    LD B,STAR_COUNT
.INIT_STARS:
    PUSH BC
    CALL STARFIELD_MARK_STAR
    POP BC
    LD DE,STAR_SIZE
    ADD IX,DE
    DJNZ .INIT_STARS
    RET

; Input BC: B = character Y (2..23), C = character X (6..25).
; Output HL: byte in DIRTY_MAP at offset Y*32 + X.
; Destroys DE, HL. Preserves BC.
STARFIELD_MAP_ADDRESS:
    LD L,B
    LD H,0
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    LD E,C
    LD D,0
    ADD HL,DE
    LD DE,DIRTY_MAP
    ADD HL,DE
    RET

; Mark a character cell just once, append (Y,X) to the queue.
; Preserves BC,DE,HL,IX; destroys AF.
STARFIELD_MARK_CELL:
    PUSH BC
    PUSH DE
    PUSH HL
    CALL STARFIELD_MAP_ADDRESS
    LD A,(HL)
    OR A
    JR NZ,.DONE
    LD A,(DIRTY_COUNT)
    CP DIRTY_LIMIT
    JR NC,.DONE
    INC (HL)
    INC A
    LD (DIRTY_COUNT),A
    LD HL,(DIRTY_TAIL)
    LD (HL),B
    INC HL
    LD (HL),C
    INC HL
    LD (DIRTY_TAIL),HL
.DONE:
    POP HL
    POP DE
    POP BC
    RET

; Read one cell flag. OUT A=0 or 1.
; Preserves BC,DE,HL,IX.
STARFIELD_TEST_CELL:
    PUSH DE
    PUSH HL
    CALL STARFIELD_MAP_ADDRESS
    LD A,(HL)
    POP HL
    POP DE
    RET

; Mark a rectangle of character cells.
; IN B=top Y, C=left X, D=width, E=height.
; Preserves BC,DE,HL,IX.
STARFIELD_MARK_RECT:
    PUSH BC
    PUSH DE
    PUSH HL
.ROW:
    PUSH BC
    LD H,D
.COL:
    CALL STARFIELD_MARK_CELL
    INC C
    DEC H
    JR NZ,.COL
    POP BC
    INC B
    DEC E
    JR NZ,.ROW
    POP HL
    POP DE
    POP BC
    RET

; Test whether any cell in a rectangle is dirty.
; IN B=top Y, C=left X, D=width, E=height.
; OUT A=0 (none) or 1 (at least one).
; Preserves BC,DE,HL,IX.
STARFIELD_TEST_RECT:
    PUSH BC
    PUSH DE
    PUSH HL
.ROW:
    PUSH BC
    LD H,D
.COL:
    CALL STARFIELD_TEST_CELL
    OR A
    JR NZ,.FOUND
    INC C
    DEC H
    JR NZ,.COL
    POP BC
    INC B
    DEC E
    JR NZ,.ROW
    XOR A
    JR .DONE
.FOUND:
    POP BC
    LD A,1
.DONE:
    POP HL
    POP DE
    POP BC
    RET

; Mark a star's current character cell.
; IN IX = star slot. Preserves IX and BC.
STARFIELD_MARK_STAR:
    LD A,(IX+S_Y)
    SRL A
    SRL A
    SRL A
    LD B,A
    LD C,(IX+S_X)
    JP STARFIELD_MARK_CELL

; Logical update only; actual drawing takes place after next HALT.
STARFIELD_UPDATE:
    LD HL,STAR_CLOCK
    INC (HL)
    LD IX,STAR_POOL
    LD B,STAR_COUNT
.NEXT:
    PUSH BC
    LD A,(STAR_CLOCK)
    AND (IX+S_PERIOD)
    JR NZ,.SKIP

    CALL STARFIELD_MARK_STAR  ; old character cell
    ; Both remaining layers use the same pixel step (1..3).
    ; S_PERIOD changes only how often the star takes that step.
    LD A,(SCROLL_SPEED)
    LD C,A
    LD A,(IX+S_Y)
    ADD A,C
    CP 192
    JR C,.SAVE_Y
    SUB 176                  ; wrap into Y=16..191, preserve excess
    LD (IX+S_Y),A
    LD A,(IX+S_X)
    INC A
    CP 26
    JR C,.SAVE_X
    LD A,6
.SAVE_X:
    LD (IX+S_X),A
    JR .MARK_NEW
.SAVE_Y:
    LD (IX+S_Y),A
.MARK_NEW:
    CALL STARFIELD_MARK_STAR  ; new character cell
.SKIP:
    POP BC
    LD DE,STAR_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

; If a star changed beneath a stationary sprite, mark that sprite
; DIRTY so the bitmap overwritten by refreshed stars is redrawn.
STARFIELD_INVALIDATE_FOREGROUND:
    LD A,(SHIP_DRAWN)
    OR A
    JR Z,.BLAST
    LD BC,(SHIP_CUR_POS)
    LD DE,#0201              ; width=2, height=1
    CALL STARFIELD_TEST_RECT
    OR A
    JR Z,.BLAST
    LD A,1
    LD (SHIP_DIRTY),A

.BLAST:
    LD A,(BLAST_DRAWN)
    OR A
    JR Z,.BULLETS
    LD BC,(BLAST_POS)
    LD DE,#0101
    LD A,(BLAST_TYPE)
    OR A
    JR Z,.BLAST_RECT
    LD D,2
.BLAST_RECT:
    CALL STARFIELD_TEST_RECT
    OR A
    JR Z,.BULLETS
    LD A,1
    LD (BLAST_DIRTY),A

.BULLETS:
    LD IX,BULLET_POOL
    LD B,MAX_BULLETS
.NEXT_BULLET:
    PUSH BC
    LD A,(IX+B_DRAWN)
    OR A
    JR Z,.SKIP_BULLET
    LD B,(IX+B_DRAW_Y)
    LD C,(IX+B_DRAW_X)
    CALL STARFIELD_TEST_CELL
    OR A
    JR Z,.SKIP_BULLET
    LD A,1
    LD (IX+B_DIRTY),A
.SKIP_BULLET:
    POP BC
    LD DE,BULLET_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT_BULLET

.ENEMIES:
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT_ENEMY:
    PUSH BC
    LD A,(IX+E_DRAWN)
    OR A
    JR Z,.SKIP_ENEMY
    LD B,(IX+E_DRAW_Y)
    LD C,(IX+E_DRAW_X)
    LD DE,#0102              ; one cell wide, two tall
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.ENEMY_RECT
    LD D,2
.ENEMY_RECT:
    CALL STARFIELD_TEST_RECT
    OR A
    JR Z,.SKIP_ENEMY
    LD A,1
    LD (IX+E_DIRTY),A
.SKIP_ENEMY:
    POP BC
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT_ENEMY
    RET

; Stage 1: clear changed cells BEFORE drawing sprites.
; DIRTY_MAP and DIRTY_QUEUE remain valid until the star pass finishes.
STARFIELD_CLEAR_CELLS:
    LD A,(DIRTY_COUNT)
    OR A
    RET Z
    LD B,A
    LD IX,DIRTY_QUEUE
.CLEAR_NEXT:
    PUSH BC
    LD B,(IX+0)
    LD C,(IX+1)
    CALL GET_SCREEN_ADDR
    CALL CLEAR_CELL_1_1
    INC IX
    INC IX
    POP BC
    DJNZ .CLEAR_NEXT
    RET

; Stage 2: plot current stars AFTER all foreground drawing.
; An OR star may intentionally appear over an asteroid.
; Reset the dirty queue only AFTER plotting all stars.
STARFIELD_DRAW_STARS:
    LD A,(DIRTY_COUNT)
    OR A
    RET Z

    LD IX,STAR_POOL
    LD B,STAR_COUNT
.DRAW_NEXT:
    PUSH BC
    LD A,(IX+S_Y)
    SRL A
    SRL A
    SRL A
    LD B,A
    LD C,(IX+S_X)
    CALL STARFIELD_TEST_CELL
    OR A
    CALL NZ,STARFIELD_DRAW_STAR
    POP BC
    LD DE,STAR_SIZE
    ADD IX,DE
    DJNZ .DRAW_NEXT

    LD IX,DIRTY_QUEUE
    LD A,(DIRTY_COUNT)
    LD B,A
.RESET_NEXT:
    PUSH BC
    LD B,(IX+0)
    LD C,(IX+1)
    CALL STARFIELD_MAP_ADDRESS
    XOR A
    LD (HL),A
    INC IX
    INC IX
    POP BC
    DJNZ .RESET_NEXT

    XOR A
    LD (DIRTY_COUNT),A
    LD HL,DIRTY_QUEUE
    LD (DIRTY_TAIL),HL
    RET

; Draw one white star bit. Its Y is a PIXEL coordinate, not a row.
; IN IX=star. Uses only OR for background point composition.
; Unlike opaque sprites, stars are intentionally OR'ed on top.
STARFIELD_DRAW_STAR:
    LD A,(IX+S_Y)
    SRL A
    SRL A
    SRL A
    LD B,A
    LD C,(IX+S_X)
    CALL GET_SCREEN_ADDR
    LD A,(IX+S_Y)
    AND 7
    ADD A,H
    LD H,A
    LD A,(IX+S_MASK)
    OR (HL)
    LD (HL),A
    RET

; ===== renderer.asm =====
; -------------------------------------------------------------
; Selective renderer, foreground first / stars last.
;
; Dirty old object cells and moved star cells share the queue.
; Clear these cells first, redraw changed opaque sprites next,
; then add the moving star pixels as a final OR overlay.
;
; DIRTY is set on movement, animation tick, damage, spawning or
; deactivation; it remains clear for an unchanged object.
;
; Star changes still invalidate affected objects: cleaning an old
; star cell must not punch a blank hole into a stationary sprite.
; The final star itself MAY appear over the asteroid (by design).
; -------------------------------------------------------------
RENDER_FRAME:
    ; A moved star may require restoring an otherwise static sprite.
    CALL STARFIELD_INVALIDATE_FOREGROUND

    ; Erase phase marks old footprints in the dirty-cell queue.
    CALL RENDER_ERASE_BULLETS
    CALL RENDER_ERASE_ENEMIES

    LD A,(SHIP_DIRTY)
    OR A
    JR Z,.SHIP_ERASE_DONE
    LD A,(SHIP_DRAWN)
    OR A
    CALL NZ,ERASE_SHIP
    XOR A
    LD (SHIP_DRAWN),A
.SHIP_ERASE_DONE:
    LD A,(BLAST_DIRTY)
    OR A
    JR Z,.BLAST_ERASE_DONE
    LD A,(BLAST_DRAWN)
    OR A
    CALL NZ,ERASE_BLAST
    XOR A
    LD (BLAST_DRAWN),A
.BLAST_ERASE_DONE:
    ; Clear each changed cell once, leaving foreground rendering next.
    CALL STARFIELD_CLEAR_CELLS

    LD A,(BLAST_DIRTY)
    OR A
    JR Z,.BLAST_DONE
    XOR A
    LD (BLAST_DIRTY),A
    LD A,(BLAST_ACTIVE)
    OR A
    JR Z,.BLAST_DONE
    CALL DRAW_BLAST
    LD A,1
    LD (BLAST_DRAWN),A
.BLAST_DONE:
    LD A,(SHIP_DIRTY)
    OR A
    JR Z,.SHIP_DONE
    XOR A
    LD (SHIP_DIRTY),A
    CALL DRAW_SHIP
    LD HL,(SHIP_NEW_POS)
    LD (SHIP_CUR_POS),HL
    LD A,1
    LD (SHIP_DRAWN),A
.SHIP_DONE:
    CALL RENDER_DRAW_ENEMIES
    CALL RENDER_DRAW_BULLETS

    ; Final pass: OR star bits into the finished image, including
    ; asteroid pixels when a star happens to cross one.
    JP STARFIELD_DRAW_STARS

; ===== graphics.asm =====
; -------------------------------------------------------------
; Opaque bitmap drawing: 8x8 / 16x8, attribute writes and clear.
; -------------------------------------------------------------
GET_SCREEN_ADDR: ; IN: BC=YX, OUT: HL=ADDR
    LD A,B
    AND #18
    OR #40
    LD H,A
    LD A,B
    AND 7
    RRCA
    RRCA
    RRCA
    OR C
    LD L,A
    RET

RESTORE_ATTR_1_1:   ; IN: HL=ADDR (SAVED), DE=ATTR ADDR
    PUSH HL
    LD A,H
    RRCA
    RRCA
    RRCA
    AND 3
    OR #58
    LD H,A
    LD A,(DE)
    LD (HL),A
    POP HL
    RET

RESTORE_ATTR_1_2:   ; IN: HL=ADDR (SAVED), DE=ATTR ADDR
    PUSH HL
    LD A,H
    RRCA
    RRCA
    RRCA
    AND 3
    OR #58
    LD H,A
    LD A,(DE)
    LD (HL),A
    INC L
    INC DE
    LD A,(DE)
    LD (HL),A
    POP HL
    RET

DRAW_1_1:
    LD B,8
LOOP_DRAW_1_1:
    LD A,(DE)
    LD (HL),A
    INC H
    INC DE
    DJNZ LOOP_DRAW_1_1
    RET
    
DRAW_1_2:
    LD B,8
LOOP_DRAW_1_2:
    LD A,(DE)
    LD (HL),A
    INC L
    INC DE
    LD A,(DE)
    LD (HL),A
    DEC L
    INC H
    INC DE
    DJNZ LOOP_DRAW_1_2
    RET
    
; -------------------------------------------------------------
; Clear old opaque sprite footprints WITHOUT saving the backdrop.
; Call on old coordinates before drawing moving background dots.
; IN: HL = top-left bitmap address of 8x8 or 16x8 cell area.
; OUT: bitmap bytes = 0; attrs reset to corridor BG_ATTR.
; DESTROYS AF,BC,DE; PRESERVES HL.
; -------------------------------------------------------------
CLEAR_CELL_1_1:
    LD DE,BG_ATTR
    CALL RESTORE_ATTR_1_1
    PUSH HL
    LD B,8
    XOR A
.LOOP:
    LD (HL),A
    INC H
    DJNZ .LOOP
    POP HL
    RET

CLEAR_CELL_1_2:
    LD DE,BG_ATTR_PAIR
    CALL RESTORE_ATTR_1_2
    PUSH HL
    LD B,8
    XOR A
.LOOP:
    LD (HL),A
    INC L
    LD (HL),A
    DEC L
    INC H
    DJNZ .LOOP
    POP HL
    RET

; ===== objects.asm =====
; -------------------------------------------------------------
; Game objects are opaque. No backdrop saving or OR blending.
; The old picture is erased to empty corridor cells, the moving
; starfield will be drawn next, and then active objects drawn.
; -------------------------------------------------------------

DRAW_SHIP:
    LD BC,(SHIP_NEW_POS)
    CALL GET_SCREEN_ADDR
    LD DE,SHIP_ATTR
    CALL RESTORE_ATTR_1_2
    LD DE,SHIP_SPRITE
    JP DRAW_1_2

ERASE_SHIP:
    LD BC,(SHIP_CUR_POS)
    LD DE,#0201
    JP STARFIELD_MARK_RECT

; Small explosion: 1x1 (8x8); large: 1x2 (16x8).
; Both use the original asteroid top-left Y with no offset.
DRAW_BLAST:
    LD BC,(BLAST_POS)
    CALL GET_SCREEN_ADDR
    LD A,(BLAST_TYPE)
    OR A
    JR NZ,.WIDE
    LD DE,BLAST_ATTR_SMALL
    CALL RESTORE_ATTR_1_1
    LD DE,(BLAST_FRAME_PTR)
    JP DRAW_1_1
.WIDE:
    LD DE,BLAST_ATTR
    CALL RESTORE_ATTR_1_2
    LD DE,(BLAST_FRAME_PTR)
    JP DRAW_1_2

ERASE_BLAST:
    LD BC,(BLAST_POS)
    LD DE,#0101
    LD A,(BLAST_TYPE)
    OR A
    JR Z,.MARK
    LD D,2
.MARK:
    JP STARFIELD_MARK_RECT

; Clear screen only: all game objects are drawn by RENDER_FRAME.
CLEAR_BITMAP:
    LD HL,#4000
    LD (HL),0
    LD DE,#4001
    LD BC,6143
    LDIR
    LD HL,#5800
    LD A,(BG_ATTR)
    LD (HL),A
    LD DE,#5801
    LD BC,767
    LDIR
    RET

; ===== ui.asm =====
; -------------------------------------------------------------
; STATIC UI. Called once at START, outside the frame budget.
; Paper colours distinguish HUD/panels from the black corridor.
; Attributes: 32x24 starting at #5800; no attribute FLASH.
; -------------------------------------------------------------
DRAW_STATIC_UI:
    ; Two HUD rows: white ink on blue paper (BRIGHT).
    LD HL,#5800
    LD B,2
.HUD_ROW:
    LD C,32
.HUD_CELL:
    LD (HL),#4F
    INC HL
    DEC C
    JR NZ,.HUD_CELL
    DJNZ .HUD_ROW

    ; Remaining 22 rows: left 6 + corridor 20 + right 6.
    LD HL,#5840                  ; attributes at Y=2
    LD B,22
.SIDE_ROW:
    LD C,6
.LEFT_CELL:
    LD (HL),#4F
    INC HL
    DEC C
    JR NZ,.LEFT_CELL
    LD DE,20
    ADD HL,DE                   ; corridor remains black
    LD C,6
.RIGHT_CELL:
    LD (HL),#4F
    INC HL
    DEC C
    JR NZ,.RIGHT_CELL
    DJNZ .SIDE_ROW

    ; Text: X/Y in character cells. 48K ROM font at #3D00.
    LD BC,#0000
    LD DE,HUD_TEXT_0
    CALL PRINT_TEXT
    LD BC,#0100
    LD DE,HUD_TEXT_1
    CALL PRINT_TEXT

    LD BC,#0300
    LD DE,LEFT_TEXT_0
    CALL PRINT_TEXT
    LD BC,#0600
    LD DE,LEFT_TEXT_1
    CALL PRINT_TEXT
    LD BC,#1000
    LD DE,LEFT_TEXT_2
    CALL PRINT_TEXT

    LD BC,#031A                  ; X=26, Y=3
    LD DE,RIGHT_TEXT_0
    CALL PRINT_TEXT
    LD BC,#061A
    LD DE,RIGHT_TEXT_1
    CALL PRINT_TEXT
    LD BC,#101A
    LD DE,RIGHT_TEXT_2
    CALL PRINT_TEXT
    RET

; Draw only dynamic counters after HALT; no UI work when unchanged.
RENDER_HUD:
    LD A,(HUD_DIRTY)
    OR A
    RET Z
    XOR A
    LD (HUD_DIRTY),A

    LD A,(SCORE)                 ; 0..99, +10 for first target
    LD BC,#0006                  ; SCORE 00: digits start X=6
    CALL PRINT_DEC2

    LD A,(SCROLL_SPEED)
    ADD A,48                     ; ASCII '0'
    LD BC,#0012                  ; SPEED digit at X=18
    CALL DRAW_CHAR_AT

    LD A,(SCROLL_SPEED)
    ADD A,48
    LD BC,#0700                  ; left panel, below SPEED
    CALL DRAW_CHAR_AT

    ; Health at top-right: 100, 075, 050, 025, 000.
    LD A,(SHIP_HP)
    LD BC,#001A                  ; HP digits start at X=26
    CP 100
    JR NZ,.HP_BELOW_100
    LD A,'1'
    JR .HP_HUNDREDS
.HP_BELOW_100:
    LD A,'0'
.HP_HUNDREDS:
    PUSH BC
    CALL DRAW_CHAR_AT
    POP BC
    INC C
    LD A,(SHIP_HP)
    CP 100
    JR NZ,.HP_LAST_TWO
    XOR A
.HP_LAST_TWO:
    CALL PRINT_DEC2

    ; Active bullets in flight: two digits below "SHOTS".
    LD A,(BULLET_COUNT)
    LD BC,#111C                  ; Y=17, X=28
    CALL PRINT_DEC2
    RET

; IN: A=0..99, BC=YX first digit; draw two decimal digits.
PRINT_DEC2:
    LD D,0                       ; tens
.TENS:
    CP 10
    JR C,.WRITE
    SUB 10
    INC D
    JR .TENS
.WRITE:
    PUSH AF                      ; save units
    LD A,D
    ADD A,48
    PUSH BC                      ; DRAW_CHAR_AT destroys B
    CALL DRAW_CHAR_AT
    POP BC
    INC C
    POP AF
    ADD A,48
    JP DRAW_CHAR_AT

; IN: BC=YX, DE -> zero-terminated string (ASCII 32..127).
PRINT_TEXT:
.NEXT:
    LD A,(DE)
    OR A
    RET Z
    PUSH BC
    PUSH DE
    CALL DRAW_CHAR_AT
    POP DE
    POP BC
    INC DE
    INC C
    JR .NEXT

; IN: A=ASCII, BC=YX. Uses ZX Spectrum 48K ROM font.
; OUT: character rendered. DESTROYS: AF, B, DE, HL.
DRAW_CHAR_AT:
    SUB 32
    LD L,A
    LD H,0
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL                  ; font offset = (ASCII-32)*8
    LD DE,#3D00                 ; ROM charset, character 32
    ADD HL,DE
    EX DE,HL                   ; DE = eight bitmap bytes
    CALL GET_SCREEN_ADDR
    JP DRAW_1_1

; ===== data.asm =====
; -------------------------------------------------------------
; Sprites and state
; -------------------------------------------------------------
BG_ATTR:
    DB #47                     ; bright white on black; corridor only
BG_ATTR_PAIR:
    DB #47,#47                 ; default attributes for 2-cell clear

SHIP_START_POS:
    DB 15,22

SHIP_SPRITE:
    DB #01,#80
    DB #03,#C0
    DB #1F,#F8
    DB #7F,#FE
    DB #FF,#FF
    DB #ED,#B7
    DB #44,#22
    DB #04,#20
SHIP_ATTR:
    DB #46,#46                 ; bright yellow on black
SHIP_CUR_POS:
    DB 15,22                   ; last painted position
SHIP_NEW_POS:
    DB 15,22                   ; logical target
SHIP_DRAWN:
    DB 0

SHIP_HP:
    DB 100                      ; 100 -> 75 -> 50 -> 25 -> 0

; Four fixed lanes; no two enemies intersect horizontally.
ENEMY_START_TABLE:
    ; TYPE, X, Y, initial animation timer (1..4).
    DB 0,8,2,1                  ; small, phase 1
    DB 1,12,11,2                ; large, phase 2
    DB 0,19,5,3                 ; small, phase 3
    DB 1,23,16,4                ; large, phase 4

ENEMY_MOVE_TIMER:
    DB 4
ENEMY_MOVE_NOW:
    DB 0

ENEMY_POOL:
    DS MAX_ENEMIES*ENEMY_SLOT_SIZE,0

ENEMY_ATTR_SMALL:
    DB #42                      ; bright red
ENEMY_ATTR_LARGE:
    DB #45,#45                  ; bright cyan

ENEMY_FRAMES:
    DW ENEMY_SMALL_0,ENEMY_SMALL_1
    DW ENEMY_LARGE_0,ENEMY_LARGE_1

; Every frame is two character rows high (top then bottom).
; Small frame: 16 bytes = 1x2. Large frame: 32 bytes = 2x2.
ENEMY_SMALL_0:
    DB %00000000
    DB %00011000
    DB %00111100
    DB %01111110
    DB %01110110
    DB %11111111
    DB %11011111
    DB %11110111
    DB %11111111
    DB %11101111
    DB %01111110
    DB %01111010
    DB %00111100
    DB %00111100
    DB %00011000
    DB %00000000

ENEMY_SMALL_1:
    DB %00000000
    DB %00001100
    DB %00111110
    DB %01111110
    DB %01101111
    DB %11111111
    DB %11110111
    DB %11011111
    DB %11111110
    DB %11101110
    DB %01111110
    DB %01011100
    DB %00111100
    DB %00011100
    DB %00011000
    DB %00000000

ENEMY_LARGE_0:
    DB #00,#00
    DB #00,#C0
    DB #03,#F0
    DB #0F,#FC
    DB #1F,#FE
    DB #3F,#FF
    DB #7F,#FF
    DB #7B,#EF
    DB #FF,#FF
    DB #EF,#BF
    DB #FF,#FF
    DB #7F,#FE
    DB #3F,#FC
    DB #1F,#F8
    DB #07,#E0
    DB #01,#80

ENEMY_LARGE_1:
    DB #00,#00
    DB #01,#80
    DB #07,#E0
    DB #1F,#F8
    DB #3F,#FC
    DB #7F,#FE
    DB #FF,#FF
    DB #FD,#DF
    DB #F7,#EF
    DB #FF,#FF
    DB #FB,#DF
    DB #7F,#FE
    DB #3F,#FC
    DB #0F,#F0
    DB #03,#C0
    DB #00,#00

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

BLAST_ACTIVE:
    DB 0
BLAST_DRAWN:
    DB 0
BLAST_TYPE:
    DB 0                        ; 0=8x8 for small, 1=16x8 for large
BLAST_FRAME:
    DB 0
BLAST_ANIM_TIMER:
    DB BLAST_FRAME_DURATION
BLAST_POS:
    DB 0,0                      ; original asteroid X/Y, NO offset
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

; Individual dirty flags for static target, blast, and player.
; Bullet dirty state is inside each bullet slot.
BLAST_DIRTY:     DB 0
SHIP_DIRTY:      DB 1

; -------------------------------------------------------------
; Moving starfield: 24 points, three motion rates.
; Each record: X cell, Y pixel (16..191), pixel bit, period mask.
; -------------------------------------------------------------
STAR_CLOCK:    DB 0
DIRTY_COUNT:   DB 0
DIRTY_TAIL:    DW DIRTY_QUEUE
DIRTY_MAP:     DS 768,0
DIRTY_QUEUE:   DS 320,0          ; 160 unique character cells

STAR_POOL:
    ; Mid layer: SCROLL_SPEED pixels every two frames.
    DB 6,73,#10,1
    DB 9,150,#01,1
    DB 13,43,#02,1
    DB 16,170,#08,1
    DB 19,84,#20,1
    DB 23,37,#04,1
    DB 8,114,#40,1
    DB 24,141,#02,1

    ; Far layer: SCROLL_SPEED pixels every four frames.
    DB 7,178,#80,3
    DB 11,22,#08,3
    DB 15,128,#10,3
    DB 17,66,#01,3
    DB 21,152,#20,3
    DB 25,98,#04,3
    DB 10,52,#40,3
    DB 19,186,#02,3

; -------------------------------------------------------------
; Input and HUD state.
; -------------------------------------------------------------
SCROLL_SPEED:      DB 1        ; 1..3, multiplier for stars and asteroid speed
SCORE:             DB 0        ; demo score 0..99
HUD_DIRTY:         DB 1        ; dynamic numeric labels need redraw
SPACE_HELD:        DB 0        ; key edge detection
SPEED_UP_HELD:     DB 0
SPEED_DOWN_HELD:   DB 0

HUD_TEXT_0:    DB "SCORE 00    SPEED 1    HP 100",0
HUD_TEXT_1:    DB "ZX SPACE DEMO     O/P Q/A SPACE",0
LEFT_TEXT_0:  DB "SPEED",0
LEFT_TEXT_1:  DB "0",0
LEFT_TEXT_2:  DB "SHIP",0
RIGHT_TEXT_0: DB "SECTOR",0
RIGHT_TEXT_1: DB "01",0
RIGHT_TEXT_2: DB "SHOTS",0

PROGRAM_END:
