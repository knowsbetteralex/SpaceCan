; ZX Space Demo - Step 03: moving asteroids and hit points.
; ZX Spectrum 48K / Delta-C, sjasmplus syntax.
;
; Coordinates are in 8x8 character cells: X in low byte, Y in high byte.
; HUD: Y=0..1, corridor: X=6..25, Y=2..23.
; Render immediately after HALT. Logic prepares the NEXT frame.

    ORG #9000

BLAST_FRAME_DURATION EQU 4
BLAST_FRAME_COUNT    EQU 4
PLAYFIELD_TOP        EQU 2
MAX_BULLETS          EQU 6
BULLET_SLOT_SIZE     EQU 16
MAX_ENEMIES          EQU 4
ENEMY_SLOT_SIZE      EQU 32
ENEMY_FRAME_DELAY    EQU 6
ENEMY_RESPAWN_DELAY  EQU 24

; One 32-byte slot for either an 8x8 or a 16x8 enemy.
E_ACTIVE       EQU 0
E_TYPE         EQU 1           ; 0=8x8, 1=16x8
E_HP           EQU 2
E_X            EQU 3
E_Y            EQU 4
E_DRAWN        EQU 5
E_DRAW_X       EQU 6
E_DRAW_Y       EQU 7
E_DIRTY        EQU 8
E_FRAME        EQU 9
E_ANIM_TIMER   EQU 10
E_BG_ATTR      EQU 11          ; two attribute bytes
E_BG_BITMAP    EQU 13          ; sixteen bitmap bytes
E_RESPAWN      EQU 29

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


; Each bullet slot is exactly 16 bytes (offsets from IX).
B_ACTIVE    EQU 0  ; 0=free, 1=just spawned, 2=flying
B_X         EQU 1
B_Y         EQU 2
B_DRAWN     EQU 3
B_DRAW_X    EQU 4
B_DRAW_Y    EQU 5
B_DIRTY     EQU 6
B_BG_ATTR   EQU 7
B_BG_BITMAP EQU 8       ; 8 bytes at offsets 8..15

START:
    DI
    CALL CLEAR_BITMAP
    CALL DRAW_STATIC_UI
    LD A,1
    OUT (#FE),A                  ; blue border

    ; Fully clear bullet slots, including their saved backgrounds.
    LD HL,BULLET_POOL
    LD (HL),0
    LD DE,BULLET_POOL+1
    LD BC,MAX_BULLETS*BULLET_SLOT_SIZE-1
    LDIR

    CALL INIT_ENEMIES

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
    LD (SCROLL_SPEED),A         ; scroll starts at a later step
    LD (HUD_DIRTY),A
    LD (SHIP_DIRTY),A

    LD HL,(SHIP_START_POS)
    LD (SHIP_CUR_POS),HL
    LD (SHIP_NEW_POS),HL
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

; Q/A change 1..4 for the HUD. Background movement comes later.
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
    RET

; Start an explosion at a destroyed asteroid (one effect slot).
; IN: IX = asteroid slot. PRESERVES: IX. DESTROYS: AF, HL.
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
    LD HL,BLAST_FRAME_0
    LD (BLAST_FRAME_PTR),HL
    XOR A
    LD (BLAST_FRAME),A
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
    LD HL,BLAST_FRAMES
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
    LD (BLAST_FRAME_PTR),DE
    RET

; ===== bullets.asm =====
; -------------------------------------------------------------
; BULLET POOL (6 x 16 bytes)
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
; POOL RENDERING: two passes, shared with ship/star/blast.
; Erase uses the last drawn coordinates, never the logical ones.
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

; IN: HL=screen address, IX=slot, BC=field offset (6/7).
; OUT: DE=address of field within slot.
; PRESERVES: HL, BC, IX. DESTROYS: DE.
GET_BULLET_BUFFER:
    PUSH HL
    PUSH IX
    POP HL
    ADD HL,BC
    EX DE,HL
    POP HL
    RET

; Draw 8x8 bullet at logical position and save the background.
; IX preserved; other registers may change.
DRAW_BULLET_SLOT:
    LD B,(IX+B_Y)
    LD C,(IX+B_X)
    CALL GET_SCREEN_ADDR
    LD BC,B_BG_ATTR
    CALL GET_BULLET_BUFFER
    CALL SAVE_ATTR_1_1
    LD BC,B_BG_BITMAP
    CALL GET_BULLET_BUFFER
    CALL SAVE_BITMAP_1_1
    LD DE,BULLET_ATTR
    CALL RESTORE_ATTR_1_1
    LD DE,BULLET_SPRITE
    CALL DRAW_1_1_BLENDED

    LD A,(IX+B_X)
    LD (IX+B_DRAW_X),A
    LD A,(IX+B_Y)
    LD (IX+B_DRAW_Y),A
    LD A,1
    LD (IX+B_DRAWN),A
    RET

; Restore the saved background at the LAST DRAWN position.
ERASE_BULLET_SLOT:
    LD B,(IX+B_DRAW_Y)
    LD C,(IX+B_DRAW_X)
    CALL GET_SCREEN_ADDR
    LD BC,B_BG_ATTR
    CALL GET_BULLET_BUFFER
    CALL RESTORE_ATTR_1_1
    LD BC,B_BG_BITMAP
    CALL GET_BULLET_BUFFER
    CALL DRAW_1_1
    XOR A
    LD (IX+B_DRAWN),A
    RET

; ===== enemies.asm =====
; -------------------------------------------------------------
; ENEMIES: four independent asteroids (8x8 and 16x8).
;
; IX -> current enemy slot in all *_ENEMY_SLOT routines.
; Four fixed lanes never overlap each other or static STAR.
; Game logic updates state/dirty; renderer stores drawn position.
; -------------------------------------------------------------

; Initialise four slots from ENEMY_START_TABLE: TYPE, X, Y.
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
    LD A,ENEMY_FRAME_DELAY
    LD (IX+E_ANIM_TIMER),A
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
    LD A,ENEMY_FRAME_DELAY
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
    LD A,(SHIP_NEW_POS+1)
    CP (IX+E_Y)
    RET NZ
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
    LD A,(IX+E_Y)
    CP B
    JR NZ,.SKIP
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

; IN: HL=screen address, IX=enemy, BC=field offset.
; OUT: DE=slot background buffer. HL, BC, IX preserved.
GET_ENEMY_BUFFER:
    PUSH HL
    PUSH IX
    POP HL
    ADD HL,BC
    EX DE,HL
    POP HL
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

DRAW_ENEMY_SLOT:
    LD B,(IX+E_Y)
    LD C,(IX+E_X)
    CALL GET_SCREEN_ADDR
    LD BC,E_BG_ATTR
    CALL GET_ENEMY_BUFFER
    LD A,(IX+E_TYPE)
    OR A
    JR NZ,.SAVE_ATTR_2
    CALL SAVE_ATTR_1_1
    JR .SAVE_BITMAP
.SAVE_ATTR_2:
    CALL SAVE_ATTR_1_2
.SAVE_BITMAP:
    LD BC,E_BG_BITMAP
    CALL GET_ENEMY_BUFFER
    LD A,(IX+E_TYPE)
    OR A
    JR NZ,.SAVE_BITMAP_2
    CALL SAVE_BITMAP_1_1
    JR .ATTR
.SAVE_BITMAP_2:
    CALL SAVE_BITMAP_1_2
.ATTR:
    LD A,(IX+E_TYPE)
    OR A
    JR NZ,.ATTR_2
    LD DE,ENEMY_ATTR_SMALL
    CALL RESTORE_ATTR_1_1
    JR .SPRITE
.ATTR_2:
    LD DE,ENEMY_ATTR_LARGE
    CALL RESTORE_ATTR_1_2
.SPRITE:
    PUSH HL
    CALL GET_ENEMY_FRAME
    POP HL
    LD A,(IX+E_TYPE)
    OR A
    JR NZ,.DRAW_2
    CALL DRAW_1_1_BLENDED
    JR .DONE
.DRAW_2:
    CALL DRAW_1_2_BLENDED
.DONE:
    LD A,(IX+E_X)
    LD (IX+E_DRAW_X),A
    LD A,(IX+E_Y)
    LD (IX+E_DRAW_Y),A
    LD A,1
    LD (IX+E_DRAWN),A
    RET

ERASE_ENEMY_SLOT:
    LD B,(IX+E_DRAW_Y)
    LD C,(IX+E_DRAW_X)
    CALL GET_SCREEN_ADDR
    LD BC,E_BG_ATTR
    CALL GET_ENEMY_BUFFER
    LD A,(IX+E_TYPE)
    OR A
    JR NZ,.ATTR_2
    CALL RESTORE_ATTR_1_1
    JR .BITMAP
.ATTR_2:
    CALL RESTORE_ATTR_1_2
.BITMAP:
    LD BC,E_BG_BITMAP
    CALL GET_ENEMY_BUFFER
    LD A,(IX+E_TYPE)
    OR A
    JR NZ,.BITMAP_2
    CALL DRAW_1_1
    JR .DONE
.BITMAP_2:
    CALL DRAW_1_2
.DONE:
    XOR A
    LD (IX+E_DRAWN),A
    RET

; ===== renderer.asm =====
; -------------------------------------------------------------
; Independent dirty flags, two passes:
;   1) Restore old backgrounds of ALL modified objects.
;   2) Save the new backgrounds and draw only modified objects.
; Non-overlap of game objects is enforced by game logic.
; Background scroll will be inserted BETWEEN these passes later.
; -------------------------------------------------------------
RENDER_FRAME:
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
    ; Next stage: update moving background here, while sprites
    ; whose old positions were affected have been erased.

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
    JP RENDER_DRAW_BULLETS

; ===== graphics.asm =====
; -------------------------------------------------------------
; Graphics primitives (screen address, 8x8 and 16x8 bitmap/attrs).
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

SAVE_ATTR_1_1:
    PUSH HL
    LD A,H
    RRCA
    RRCA
    RRCA
    AND 3
    OR #58
    LD H,A
    LD A,(HL)
    LD (DE),A
    POP HL
    RET

SAVE_ATTR_1_2:
    PUSH HL
    LD A,H
    RRCA
    RRCA
    RRCA
    AND 3
    OR #58
    LD H,A
    LD A,(HL)
    LD (DE),A
    INC L
    INC DE
    LD A,(HL)
    LD (DE),A
    POP HL
    RET

SAVE_BITMAP_1_1:
    LD B,8
    PUSH HL
LOOP_SAVE_BITMAP_1_1:
    LD A,(HL)
    LD (DE),A
    INC H
    INC DE
    DJNZ LOOP_SAVE_BITMAP_1_1
    POP HL
    RET

SAVE_BITMAP_1_2:
    LD B,8
    PUSH HL
LOOP_SAVE_BITMAP_1_2:
    LD A,(HL)
    LD (DE),A
    INC L
    INC DE
    LD A,(HL)
    LD (DE),A
    DEC L
    INC H
    INC DE
    DJNZ LOOP_SAVE_BITMAP_1_2
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
    
DRAW_1_2_BLENDED:
    LD B,8
    PUSH HL
LOOP_DRAW_1_2_BLENDED:
    LD A,(DE)
    OR (HL) ; OR-BLEND
    LD (HL),A
    INC L
    INC DE
    LD A,(DE)
    OR (HL) ; OR-BLEND
    LD (HL),A
    DEC L
    INC H
    INC DE
    DJNZ LOOP_DRAW_1_2_BLENDED
    POP HL
    RET
    
DRAW_1_1_BLENDED:
    LD B,8
    PUSH HL
LOOP_DRAW_1_1_BLENDED:
    LD A,(DE)
    OR (HL) ; OR-BLEND
    LD (HL),A
    INC H
    INC DE
    DJNZ LOOP_DRAW_1_1_BLENDED
    POP HL
    RET

; ===== objects.asm =====
; -------------------------------------------------------------
; Object drawing: save underlying pixels + attributes, then draw.
; -------------------------------------------------------------
DRAW_BLAST:
    LD BC,(BLAST_POS)
    CALL GET_SCREEN_ADDR
    LD DE,BLAST_BG_ATTR
    CALL SAVE_ATTR_1_2
    LD DE,BLAST_BG_BITMAP
    CALL SAVE_BITMAP_1_2
    LD DE,BLAST_ATTR
    CALL RESTORE_ATTR_1_2
    LD DE,(BLAST_FRAME_PTR)
    CALL DRAW_1_2_BLENDED
    RET

DRAW_SHIP:
    LD BC,(SHIP_NEW_POS)
    CALL GET_SCREEN_ADDR
    LD DE,SHIP_BG_ATTR
    CALL SAVE_ATTR_1_2
    LD DE,SHIP_BG_BITMAP
    CALL SAVE_BITMAP_1_2
    LD DE,SHIP_ATTR
    CALL RESTORE_ATTR_1_2
    LD DE,SHIP_SPRITE
    CALL DRAW_1_2_BLENDED
    RET

; Bullet drawing/erasing lives in bullets.asm (one slot at IX).

ERASE_SHIP:
    LD BC,(SHIP_CUR_POS)
    CALL GET_SCREEN_ADDR
    LD DE,SHIP_BG_ATTR
    CALL RESTORE_ATTR_1_2
    LD DE,SHIP_BG_BITMAP
    CALL DRAW_1_2
    RET

ERASE_BLAST:
    LD BC,(BLAST_POS)
    CALL GET_SCREEN_ADDR
    LD DE,BLAST_BG_ATTR
    CALL RESTORE_ATTR_1_2
    LD DE,BLAST_BG_BITMAP
    CALL DRAW_1_2
    RET

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
SHIP_BG_ATTR:
    DS 2,0
SHIP_BG_BITMAP:
    DS 16,0

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
BLAST_FRAME:
    DB 0
BLAST_ANIM_TIMER:
    DB BLAST_FRAME_DURATION
BLAST_POS:
    DB 0,0
BLAST_FRAME_PTR:
    DW BLAST_FRAME_0
BLAST_BG_ATTR:
    DS 2,0
BLAST_BG_BITMAP:
    DS 16,0
BLAST_ATTR:
    DB #07,#07
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
; Step 01: UI and input state.
; -------------------------------------------------------------
SCROLL_SPEED:      DB 1        ; 1..4, background will use later
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
