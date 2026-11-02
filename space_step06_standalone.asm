; ===== main.asm =====
; SpaceCan Step 06: narrow can corridor, auto progression and tile artwork.
; ZX Spectrum 48K / Delta-C, sjasmplus syntax.
;
; Coordinates are in 8x8 character cells: X in low byte, Y in high byte.
; Cockpit HUD: Y=0..3; playfield: X=6..25, Y=4..23.
; Render after HALT; update logic and moving stars for NEXT frame.

    ORG #9000

BLAST_FRAME_DURATION EQU 4
BLAST_FRAME_COUNT    EQU 4
PLAYFIELD_TOP        EQU 4
PLAYFIELD_LEFT       EQU 8
PLAYFIELD_RIGHT      EQU 23
PLAYFIELD_WIDTH      EQU 16
PLAYFIELD_BOTTOM     EQU 23
MAX_SCROLL_SPEED     EQU 3
SCORE_BONUS_STEP     EQU 1024
START_LIVES          EQU 4
SHIP_MOVE_DELAY      EQU 2
SHIP_BANK_DELAY      EQU 5    ; ticks between 8x8 banking poses
SHIP_BANK_HOLD       EQU 14   ; keep tilt after releasing O/P
MAX_BULLETS          EQU 6
BULLET_SLOT_SIZE     EQU 8
MAX_ENEMIES          EQU 3
ENEMY_SLOT_SIZE      EQU 13
ENEMY_FRAME_DELAY    EQU 4
ENEMY_RESPAWN_DELAY  EQU 24

; One 13-byte enemy slot: state + animation + last drawn position.
E_ACTIVE       EQU 0
E_TYPE         EQU 1           ; 0=8x8, 1=16x16
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
E_PHASE        EQU 12          ; initial animation timer

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
    LD (SCORE+1),A
    LD (SCORE_TIER),A
    LD (BULLET_COUNT),A
    LD (SPACE_HELD),A
    LD (SHIP_MOVE_TIMER),A
    LD (BLAST_DIRTY),A

    LD A,1
    LD (SCROLL_SPEED),A         ; automatically increases with score
    LD (HUD_DIRTY),A
    LD A,START_LIVES
    LD (SHIP_LIVES),A
    LD (SHIP_DIRTY),A

    LD HL,(SHIP_START_POS)
    LD (SHIP_CUR_POS),HL
    LD (SHIP_NEW_POS),HL
    LD A,2
    LD (SHIP_BANK),A
    LD (SHIP_BANK_TARGET),A
    XOR A
    LD (SHIP_BANK_TIMER),A
    LD (SHIP_BANK_HOLD_TIMER),A
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
; O/P: move; SPACE: fire on edge. Speed is score-driven.
; -------------------------------------------------------------
READ_INPUT:
    CALL READ_SHIP_HORIZONTAL
    CALL READ_FIRE_KEY
    RET

; The 8x8 ship stays within the can corridor (X=8..23, Y=22).
; Movement is still one cell per input tick; banking is independent:
; one pose every SHIP_BANK_DELAY frames, then a short hold after
; release to make brief turns visible.
READ_SHIP_HORIZONTAL:
    LD A,(SHIP_NEW_POS)
    LD E,A
    LD BC,#DFFE
    IN A,(C)
    BIT 0,A                    ; P: right
    JR NZ,.CHECK_LEFT
    LD D,4
    LD A,E
    CP PLAYFIELD_RIGHT
    JR Z,.SET_BANK
    INC E
    JR .MAYBE_MOVE
.CHECK_LEFT:
    BIT 1,A                    ; O: left
    JR NZ,.NO_KEY
    LD D,0
    LD A,E
    CP PLAYFIELD_LEFT
    JR Z,.SET_BANK
    DEC E

.MAYBE_MOVE:
    ; Banking responds immediately, but moving X is rate-limited.
    LD A,(SHIP_MOVE_TIMER)
    OR A
    JR Z,.MOVE
    DEC A
    LD (SHIP_MOVE_TIMER),A
    JR .SET_BANK
.MOVE:
    LD A,E
    LD (SHIP_NEW_POS),A
    LD A,SHIP_MOVE_DELAY-1
    LD (SHIP_MOVE_TIMER),A
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

; -------------------------------------------------------------
; Score/bonus: 16-bit total, +64 small / +128 large on destruction.
; IN A=points (64 or 128). Preserves IX.
; At SCORE=1024 and 2048 increase speed, maximum 3.
; Lives start at 4 and NEVER increase; impacts only decrease them.
; -------------------------------------------------------------
ADD_SCORE_A:
    LD E,A
    LD D,0
    LD HL,(SCORE)
    ADD HL,DE
    JR NC,.STORE
    LD HL,#FFFF                 ; do not wrap a long-running game
.STORE:
    LD (SCORE),HL
    LD A,1
    LD (HUD_DIRTY),A
    JP CHECK_SCORE_BONUS

CHECK_SCORE_BONUS:
    LD HL,(SCORE)
    LD A,H
    SRL A
    SRL A                       ; A = SCORE / 1024 (0..63)
    LD HL,SCORE_TIER
    CP (HL)
    RET Z
    RET C                       ; no rewards on score reduction
    LD (HL),A

    LD A,(SCROLL_SPEED)
    CP MAX_SCROLL_SPEED
    JR NC,.HUD
    INC A
    LD (SCROLL_SPEED),A
.HUD:
    LD A,1
    LD (HUD_DIRTY),A
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
; Spawn bullet at ship X and row Y-1, aligned with the 8x8 nose.
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
    ; Same character X as the 8x8 ship: bullet is aligned with nose.
    DEC H                        ; launch one row above the ship
    LD (IX+B_X),L
    LD (IX+B_Y),H
    LD A,1
    LD (IX+B_ACTIVE),A
    LD (IX+B_DIRTY),A
    LD HL,BULLET_COUNT
    INC (HL)
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
; ENEMIES: three asteroids falling vertically (8x8 and 16x16).
;
; IX -> current enemy slot. X is assigned at every spawn and
; remains constant until deactivation; overlapping spawn positions
; are rejected for objects currently occupying the entry rows.
; Game logic updates state/dirty; renderer stores drawn position.
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
    ; This test also avoids collisions with asteroids already at Y=4/5.
    PUSH HL
    PUSH BC
    CALL SELECT_ENEMY_SPAWN_X
    POP BC
    POP HL
    JR C,.SKIP_ACTIVE
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

; Automatic speed 1..3 controls vertical move period: 4..2 ticks.
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
    CALL SELECT_ENEMY_SPAWN_X
    RET C                      ; entry row blocked: retry next tick
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
; SPAWN X: choose a fresh left edge across the whole 20-cell
; corridor. Reject candidates intersecting another asteroid at
; the entry row(s), then try the next X until a free one is found.
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
    JR NC,.SUCCESS

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
    POP HL
    POP DE
    POP BC
    SCF                         ; cannot spawn this tick
    RET
.SUCCESS:
    POP HL
    POP DE
    POP BC
    OR A                        ; clear carry
    RET

; 8-bit maximal-length Galois LFSR, polynomial #1D.
; A new X is chosen only on spawn. Never re-seed on respawn.
NEXT_ENEMY_RANDOM:
    LD A,(ENEMY_RANDOM_STATE)
    ADD A,A
    JR NC,.STORE
    XOR #1D
.STORE:
    LD (ENEMY_RANDOM_STATE),A
    RET

; Current candidate is in (IX+E_X), new Y is PLAYFIELD_TOP.
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
; after the score changes so every 1024-point threshold is caught.
ON_ENEMY_HIT:
    DEC (IX+E_HP)
    JR NZ,.DAMAGED
    CALL START_ENEMY_BLAST
    CALL DEACTIVATE_ENEMY
    LD A,(IX+E_TYPE)
    OR A
    LD A,64
    JR Z,.AWARD
    LD A,128
.AWARD:
    JP ADD_SCORE_A
.DAMAGED:
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
    LD A,(IX+E_ACTIVE)
    OR A
    RET Z

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
    LD A,(SHIP_NEW_POS)
    SUB (IX+E_X)
    RET C                       ; ship is left of the asteroid
    OR A
    JR Z,.HIT
    CP 1
    RET NZ                      ; ship too far to the right
    LD A,(IX+E_TYPE)
    OR A
    RET Z                       ; small asteroid is only 1 cell wide
.HIT:
    CALL DEACTIVATE_ENEMY
    LD A,(SHIP_LIVES)
    OR A
    RET Z
    DEC A
    LD (SHIP_LIVES),A
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

; Frame table: small0..3, large0..3 (DW pointers).
; OUT: DE=bitmap address. IX and BC preserved.
GET_ENEMY_FRAME:
    LD A,(IX+E_TYPE)
    ADD A,A
    ADD A,A                    ; TYPE*4 (four frames per type)
    ADD A,(IX+E_FRAME)
    ADD A,A                    ; two bytes per table entry
    LD E,A
    LD D,0
    LD HL,ENEMY_FRAMES
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
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

; Input BC: B=character Y (4..23), C=character X (8..23).
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
    SUB 160                  ; wrap into Y=32..191, preserve excess
    LD (IX+S_Y),A
    LD A,(IX+S_X)
    INC A
    CP PLAYFIELD_RIGHT+1
    JR C,.SAVE_X
    LD A,PLAYFIELD_LEFT
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
    LD DE,#0101              ; ship is now 1x1
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
    LD DE,#0101              ; small asteroid = one 8x8 cell
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.ENEMY_RECT
    LD DE,#0202              ; large asteroid = 2x2 cells
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
 ; The old image contributes cells to the dirty queue. Opaque
; object drawing happens after cleaning, moving stars are last.
; -------------------------------------------------------------

DRAW_SHIP:
    ; Select one of five 8x8 pictures without changing its X/Y.
    ; Visual bank is independent of position; hitbox = one cell.
    LD A,(SHIP_BANK)             ; 0..4
    ADD A,A                      ; 2-byte DW address table
    LD E,A
    LD D,0
    LD HL,SHIP_FRAMES
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)                    ; DE -> 8-byte sprite
    PUSH DE

    LD BC,(SHIP_NEW_POS)
    CALL GET_SCREEN_ADDR
    LD DE,SHIP_ATTR
    CALL RESTORE_ATTR_1_1
    POP DE
    JP DRAW_1_1

ERASE_SHIP:
    LD BC,(SHIP_CUR_POS)
    LD DE,#0101
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

; ===== tiles.asm =====
; SpaceCan Step 06 - tiled soda can, wall and bar.
; 32 reusable 8x8 pictures (8 bitmap bytes + ZX attribute).
; Tile map stores just byte-sized tile IDs.
; Coordinates are CHARACTER CELLS, Y in B, X in C.
T_HUD_PLATE            EQU 0
T_HUD_TOP              EQU 1
T_HUD_EDGE             EQU 2
T_HUD_BOTTOM           EQU 3
T_HUD_SEAM             EQU 4
T_HUD_DISPLAY          EQU 5
T_WALL                 EQU 6
T_WALL_SEAM            EQU 7
T_WALL_POSTER          EQU 8
T_WALL_LIGHT           EQU 9
T_WALL_TRIM            EQU 10
T_BAR_TOP              EQU 11
T_BAR_FRONT            EQU 12
T_BAR_GRAIN            EQU 13
T_CAN_METAL            EQU 14
T_CAN_TOP              EQU 15
T_CAN_BOTTOM           EQU 16
T_CAN_GREEN            EQU 17
T_CAN_DARK             EQU 18
T_CAN_YELLOW           EQU 19
T_CAN_SWEEP            EQU 20
T_CAN_STAR             EQU 21
T_CAN_BUBBLES          EQU 22
T_CAN_LIP              EQU 23
T_CAN_LOGO             EQU 24
T_CAN_ROCKET           EQU 25
T_CAN_PLANET           EQU 26
T_CAN_HIGHLIGHT        EQU 27
T_CAN_BOTTOM_SHADE     EQU 28
T_CAN_YELLOW_EDGE      EQU 29
T_CAN_METAL_GLEAM      EQU 30
T_WALL_PANEL           EQU 31

DRAW_TILE_ID:
    PUSH BC
    LD L,A
    LD H,0
    ADD HL,HL
    LD DE,TILE_POINTERS
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
    POP BC
    CALL GET_SCREEN_ADDR
    PUSH HL
    PUSH DE
    CALL DRAW_1_1
    POP DE
    POP HL
    EX DE,HL
    LD BC,8
    ADD HL,BC
    EX DE,HL
    JP RESTORE_ATTR_1_1

; IN HL=tile map, B=top Y, C=left X, D=width, E=height.
; Static tile scene is rendered once at startup.
DRAW_TILE_MAP:
    LD (TILE_MAP_CURSOR),HL
    LD (TILE_DRAW_POS),BC
    LD A,C
    LD (TILE_MAP_LEFT),A
    LD A,D
    LD (TILE_MAP_WIDTH),A
    LD A,E
    LD (TILE_ROWS_LEFT),A
.ROW:
    LD A,(TILE_MAP_WIDTH)
    LD (TILE_COLS_LEFT),A
.COL:
    LD HL,(TILE_MAP_CURSOR)
    LD A,(HL)
    INC HL
    LD (TILE_MAP_CURSOR),HL
    LD BC,(TILE_DRAW_POS)
    CALL DRAW_TILE_ID
    LD HL,TILE_DRAW_POS
    INC (HL)
    LD HL,TILE_COLS_LEFT
    DEC (HL)
    JR NZ,.COL
    LD A,(TILE_MAP_LEFT)
    LD (TILE_DRAW_POS),A
    LD HL,TILE_DRAW_POS+1
    INC (HL)
    LD HL,TILE_ROWS_LEFT
    DEC (HL)
    JR NZ,.ROW
    RET

TILE_MAP_CURSOR: DW 0
TILE_DRAW_POS: DW 0
TILE_MAP_LEFT: DB 0
TILE_MAP_WIDTH: DB 0
TILE_COLS_LEFT: DB 0
TILE_ROWS_LEFT: DB 0

TILE_POINTERS:
    DW TILE_HUD_PLATE,TILE_HUD_TOP,TILE_HUD_EDGE,TILE_HUD_BOTTOM,TILE_HUD_SEAM,TILE_HUD_DISPLAY,TILE_WALL,TILE_WALL_SEAM,TILE_WALL_POSTER,TILE_WALL_LIGHT,TILE_WALL_TRIM,TILE_BAR_TOP,TILE_BAR_FRONT,TILE_BAR_GRAIN,TILE_CAN_METAL,TILE_CAN_TOP,TILE_CAN_BOTTOM,TILE_CAN_GREEN,TILE_CAN_DARK,TILE_CAN_YELLOW,TILE_CAN_SWEEP,TILE_CAN_STAR,TILE_CAN_BUBBLES,TILE_CAN_LIP,TILE_CAN_LOGO,TILE_CAN_ROCKET,TILE_CAN_PLANET,TILE_CAN_HIGHLIGHT,TILE_CAN_BOTTOM_SHADE,TILE_CAN_YELLOW_EDGE,TILE_CAN_METAL_GLEAM,TILE_WALL_PANEL

TILE_HUD_PLATE:
    DB #00,#24,#00,#00,#00,#00,#24,#00
    DB #78

TILE_HUD_TOP:
    DB #FF,#81,#00,#00,#00,#00,#00,#00
    DB #78

TILE_HUD_EDGE:
    DB #18,#18,#18,#18,#18,#18,#18,#18
    DB #75

TILE_HUD_BOTTOM:
    DB #00,#00,#00,#00,#00,#00,#81,#FF
    DB #78

TILE_HUD_SEAM:
    DB #18,#18,#18,#18,#18,#18,#18,#18
    DB #75

TILE_HUD_DISPLAY:
    DB #00,#00,#00,#00,#00,#00,#00,#00
    DB #70

TILE_WALL:
    DB #00,#00,#08,#08,#00,#00,#00,#00
    DB #20

TILE_WALL_SEAM:
    DB #20,#20,#20,#20,#20,#20,#20,#20
    DB #21

TILE_WALL_POSTER:
    DB #7E,#42,#5A,#66,#66,#5A,#42,#7E
    DB #26

TILE_WALL_LIGHT:
    DB #10,#38,#7C,#FE,#7C,#38,#10,#00
    DB #76

TILE_WALL_TRIM:
    DB #FF,#00,#FF,#00,#00,#00,#00,#00
    DB #26

TILE_BAR_TOP:
    DB #FF,#FF,#00,#20,#01,#10,#00,#00
    DB #32

TILE_BAR_FRONT:
    DB #00,#44,#00,#02,#80,#00,#24,#00
    DB #32

TILE_BAR_GRAIN:
    DB #40,#04,#10,#00,#21,#00,#08,#00
    DB #72

TILE_CAN_METAL:
    DB #80,#C0,#C0,#C0,#C0,#C0,#C0,#80
    DB #78

TILE_CAN_TOP:
    DB #FF,#FE,#F8,#F0,#F0,#F0,#F0,#F0
    DB #78

TILE_CAN_BOTTOM:
    DB #00,#00,#00,#00,#F0,#FF,#FF,#7E
    DB #78

TILE_CAN_GREEN:
    DB #02,#00,#00,#00,#00,#00,#00,#02
    DB #67

TILE_CAN_DARK:
    DB #40,#00,#00,#00,#00,#00,#00,#40
    DB #27

TILE_CAN_YELLOW:
    DB #10,#00,#00,#00,#00,#00,#00,#10
    DB #74

TILE_CAN_SWEEP:
    DB #C0,#E0,#70,#38,#1C,#0E,#07,#03
    DB #74

TILE_CAN_STAR:
    DB #00,#10,#10,#7C,#10,#10,#00,#00
    DB #67

TILE_CAN_BUBBLES:
    DB #02,#00,#20,#04,#00,#40,#08,#00
    DB #76

TILE_CAN_LIP:
    DB #E0,#C0,#C0,#C0,#C0,#C0,#C0,#E0
    DB #78

TILE_CAN_LOGO:
    DB #00,#7E,#C0,#F8,#06,#FC,#00,#00
    DB #67

TILE_CAN_ROCKET:
    DB #18,#3C,#7E,#3C,#18,#24,#42,#81
    DB #77

TILE_CAN_PLANET:
    DB #00,#3C,#7E,#FF,#7E,#3C,#66,#81
    DB #76

TILE_CAN_HIGHLIGHT:
    DB #80,#80,#80,#80,#80,#80,#80,#80
    DB #67

TILE_CAN_BOTTOM_SHADE:
    DB #AA,#55,#AA,#55,#FE,#FE,#7C,#38
    DB #27

TILE_CAN_YELLOW_EDGE:
    DB #02,#06,#0E,#1C,#38,#70,#E0,#C0
    DB #74

TILE_CAN_METAL_GLEAM:
    DB #E0,#F0,#F0,#F0,#F0,#F0,#F0,#E0
    DB #78

TILE_WALL_PANEL:
    DB #40,#40,#40,#40,#40,#40,#40,#40
    DB #20


; 4x32 HUD and two 20x8 static murals. No game pixels in these maps.
HUD_TILE_MAP:
    DB 14,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,14   ; y=0
    DB 4,0,0,0,0,0,0,0,0,0,4,0,0,0,0,0,0,0,0,0,0,4,0,0,0,0,0,0,0,0,0,4   ; y=1
    DB 4,0,0,0,0,5,0,0,0,0,4,0,5,5,5,5,5,0,0,0,0,4,0,0,0,0,0,5,0,0,0,4   ; y=2
    DB 14,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,3,14   ; y=3

CAN_LEFT_TILE_MAP:
    DB 6,7,6,14,15,15,15,23   ; y=4
    DB 6,8,6,14,19,19,29,23   ; y=5
    DB 6,9,6,14,19,19,20,23   ; y=6
    DB 6,7,6,14,17,29,17,23   ; y=7
    DB 6,7,6,14,17,20,17,23   ; y=8
    DB 6,7,6,14,17,17,17,23   ; y=9
    DB 6,7,6,14,24,17,24,23   ; y=10
    DB 6,7,6,14,17,17,17,23   ; y=11
    DB 6,7,6,14,21,17,21,23   ; y=12
    DB 6,7,6,14,26,17,17,23   ; y=13
    DB 6,7,6,14,17,17,17,23   ; y=14
    DB 6,7,6,14,29,17,22,23   ; y=15
    DB 6,7,6,14,20,17,17,23   ; y=16
    DB 6,8,6,14,17,17,17,23   ; y=17
    DB 6,7,6,14,22,17,22,23   ; y=18
    DB 10,10,10,14,17,22,17,23   ; y=19
    DB 11,11,11,14,22,17,22,23   ; y=20
    DB 12,12,12,14,28,28,28,23   ; y=21
    DB 12,12,12,14,16,16,16,23   ; y=22
    DB 13,13,13,12,12,13,12,13   ; y=23

CAN_RIGHT_TILE_MAP:
    DB 23,15,15,15,14,6,7,6   ; y=4
    DB 23,19,19,19,14,6,8,6   ; y=5
    DB 23,19,19,19,14,6,9,6   ; y=6
    DB 23,17,29,17,14,6,7,6   ; y=7
    DB 23,17,20,17,14,6,7,6   ; y=8
    DB 23,17,17,17,14,6,7,6   ; y=9
    DB 23,24,17,24,14,6,7,6   ; y=10
    DB 23,17,17,17,14,6,7,6   ; y=11
    DB 23,21,17,21,14,6,7,6   ; y=12
    DB 23,17,25,17,14,6,7,6   ; y=13
    DB 23,17,17,17,14,6,7,6   ; y=14
    DB 23,22,17,29,14,6,7,6   ; y=15
    DB 23,17,17,20,14,6,7,6   ; y=16
    DB 23,17,17,17,14,6,8,6   ; y=17
    DB 23,22,17,22,14,6,7,6   ; y=18
    DB 23,17,22,17,14,10,10,10   ; y=19
    DB 23,22,17,22,14,11,11,11   ; y=20
    DB 23,28,28,28,14,12,12,12   ; y=21
    DB 23,16,16,16,14,12,12,12   ; y=22
    DB 13,12,13,12,12,13,13,13   ; y=23

; ===== ui.asm =====
; -------------------------------------------------------------
; SpaceCan Step 06: "Space Soda 0.33 L" static can/wall/bar mural.
; Top 4 rows: HUD (32x4). Sides: wall + can, 8x20 each.
; Only digital SPEED / SCORE / LIVES change at runtime.
; -------------------------------------------------------------
DRAW_STATIC_UI:
    LD HL,HUD_TILE_MAP
    LD BC,#0000
    LD DE,#2004                  ; 32x4
    CALL DRAW_TILE_MAP

    LD HL,CAN_LEFT_TILE_MAP
    LD BC,#0400                  ; Y=4, X=0
    LD DE,#0814                  ; 8x20
    CALL DRAW_TILE_MAP

    LD HL,CAN_RIGHT_TILE_MAP
    LD BC,#0418                  ; Y=4, X=24
    LD DE,#0814                  ; 8x20
    CALL DRAW_TILE_MAP

    ; ROM font characters are also 8x8 tiles.
    LD BC,#000B                  ; top chrome rail
    LD DE,HUD_LABEL_TITLE
    CALL PRINT_TEXT

    LD BC,#0102
    LD DE,HUD_LABEL_SPEED
    CALL PRINT_TEXT
    LD BC,#010C
    LD DE,HUD_LABEL_SCORE
    CALL PRINT_TEXT
    LD BC,#0119
    LD DE,HUD_LABEL_LIVES
    CALL PRINT_TEXT

    ; Label fragments on either side of the black playfield.
    LD BC,#0904                  ; left can X=4..6
    LD DE,CAN_LABEL_LEFT
    CALL PRINT_TEXT
    LD BC,#0919                  ; right can X=25..27
    LD DE,CAN_LABEL_RIGHT
    CALL PRINT_TEXT
    LD BC,#0619                  ; 0.33 as a small can mark
    LD DE,CAN_LABEL_VOLUME
    JP PRINT_TEXT

; Draw no more than 7 characters when a reading changes.
RENDER_HUD:
    LD A,(HUD_DIRTY)
    OR A
    RET Z
    XOR A
    LD (HUD_DIRTY),A

    LD A,(SCROLL_SPEED)
    ADD A,'0'
    LD BC,#0205                  ; SPEED
    CALL DRAW_CHAR_AT

    LD HL,(SCORE)
    LD BC,#020C                  ; 5 digits: 00000..65535
    CALL PRINT_DEC5

    LD A,(SHIP_LIVES)
    ADD A,'0'
    LD BC,#021B                  ; lives 0..9
    JP DRAW_CHAR_AT

; IN HL=0..65535, BC=YX of leftmost digit.
; Four repeated divisions by 10^n, ending with the units.
; Dynamic HUD only: straightforward code is preferred to speed.
PRINT_DEC5:
    LD DE,10000
    CALL PRINT_DEC_PLACE
    LD DE,1000
    CALL PRINT_DEC_PLACE
    LD DE,100
    CALL PRINT_DEC_PLACE
    LD DE,10
    CALL PRINT_DEC_PLACE
    LD A,L
    ADD A,'0'
    JP DRAW_CHAR_AT

; IN HL=remainder, DE=decimal place, BC=YX.
; OUT HL=remainder after quotient, C advanced one screen column.
PRINT_DEC_PLACE:
    LD A,'0'
.NEXT:
    OR A                         ; clear carry before SBC HL,DE
    SBC HL,DE
    JR C,.WRITE
    INC A
    JR .NEXT
.WRITE:
    ADD HL,DE                    ; undo the final underflow
    PUSH HL
    PUSH DE
    PUSH BC
    CALL DRAW_CHAR_AT
    POP BC
    POP DE
    POP HL
    INC C
    RET

; IN BC=YX, DE=zero-terminated text.
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

; IN A=ASCII 32..127, BC=YX; draw 8 rows using Spectrum ROM font.
DRAW_CHAR_AT:
    SUB 32
    LD L,A
    LD H,0
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    LD DE,#3D00
    ADD HL,DE
    EX DE,HL
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

SHIP_FRAMES:
    ; Five 8x8 poses, from hard left (0) to hard right (4).
    DW SHIP_BANK_LEFT_HARD,SHIP_BANK_LEFT_SOFT,SHIP_SPRITE
    DW SHIP_BANK_RIGHT_SOFT,SHIP_BANK_RIGHT_HARD

SHIP_BANK_LEFT_HARD:
    DB %00110000
    DB %01111000
    DB %11111100
    DB %11111110
    DB %01111100
    DB %00110100
    DB %00011000
    DB %00010000

SHIP_BANK_LEFT_SOFT:
    DB %00011000
    DB %00111100
    DB %01111110
    DB %11111110
    DB %01111110
    DB %00101100
    DB %00011000
    DB %00010000

SHIP_SPRITE:
    DB %00011000
    DB %00111100
    DB %00111100
    DB %01111110
    DB %11111111
    DB %11011011
    DB %00011000
    DB %00011000

SHIP_BANK_RIGHT_SOFT:
    DB %00011000
    DB %00111100
    DB %01111110
    DB %01111111
    DB %01111110
    DB %00110100
    DB %00011000
    DB %00001000

SHIP_BANK_RIGHT_HARD:
    DB %00001100
    DB %00011110
    DB %00111111
    DB %01111111
    DB %00111110
    DB %00101100
    DB %00011000
    DB %00001000

SHIP_ATTR:
    DB #46                      ; bright yellow on black
SHIP_CUR_POS:
    DB 15,22                   ; last painted position
SHIP_NEW_POS:
    DB 15,22                   ; logical target
SHIP_BANK:
    DB 2                         ; 0..4, neutral = 2
SHIP_BANK_TARGET:
    DB 2                         ; desired pose from O/P
SHIP_BANK_TIMER:
    DB 0                         ; frames until next pose update
SHIP_BANK_HOLD_TIMER:
    DB 0                         ; pause before leveling after key release
SHIP_DRAWN:
    DB 0

SHIP_LIVES:
    DB START_LIVES              ; 4 initially; collisions only decrease
SHIP_MOVE_TIMER:
    DB 0                        ; frames until next horizontal step

; Four independent falling objects. On EVERY spawn, X is
; freshly selected in the full corridor using an 8-bit LFSR.
; The initial table stores only TYPE, START_Y, ANIMATION_PHASE.
ENEMY_START_TABLE:
    DB 0,4,1                    ; small 8x8
    DB 1,11,2                   ; large 16x16
    DB 0,17,3                   ; small 8x8

ENEMY_MOVE_TIMER:
    DB 4
ENEMY_MOVE_NOW:
    DB 0

ENEMY_RANDOM_STATE:
    DB #A7                      ; reseeded by LD A,R during startup
ENEMY_TEST_X:
    DB 0                        ; temporary spawn-overlap data
ENEMY_TEST_TYPE:
    DB 0
ENEMY_TEST_Y:
    DB 0

ENEMY_POOL:
    DS MAX_ENEMIES*ENEMY_SLOT_SIZE,0

ENEMY_ATTR_SMALL:
    DB #42                      ; bright red
ENEMY_ATTR_LARGE:
    DB #45,#45                  ; bright cyan

ENEMY_FRAMES:
    ; 4 rotation frames per type, each 90 degrees clockwise.
    DW ENEMY_SMALL_0,ENEMY_SMALL_1,ENEMY_SMALL_2,ENEMY_SMALL_3
    DW ENEMY_LARGE_0,ENEMY_LARGE_1,ENEMY_LARGE_2,ENEMY_LARGE_3

; Small 8x8: 8 bytes/frame. Large 16x16: 32 bytes/frame.
; No masking or backdrop saving; sprites draw opaque.
ENEMY_SMALL_0:
    DB %00011100
    DB %00111110
    DB %11111111
    DB %11110111
    DB %11111110
    DB %00111111
    DB %00001110
    DB %00000100

ENEMY_SMALL_1:
    DB %00011100
    DB %00011100
    DB %00111110
    DB %00111111
    DB %01110111
    DB %11111111
    DB %01111110
    DB %00101100

ENEMY_SMALL_2:
    DB %00100000
    DB %01110000
    DB %11111100
    DB %01111111
    DB %11101111
    DB %11111111
    DB %01111100
    DB %00111000

ENEMY_SMALL_3:
    DB %00110100
    DB %01111110
    DB %11111111
    DB %11101110
    DB %11111100
    DB %01111100
    DB %00111000
    DB %00111000

ENEMY_LARGE_0:
    DB #01,#E0
    DB #07,#F8
    DB #1F,#FC
    DB #3F,#FE
    DB #3F,#FF
    DB #7F,#FF
    DB #FB,#FF
    DB #FF,#FE
    DB #FF,#FF
    DB #FF,#FC
    DB #7F,#F8
    DB #77,#F8
    DB #3F,#FC
    DB #1F,#F0
    DB #07,#C0
    DB #03,#80

ENEMY_LARGE_1:
    DB #03,#C0
    DB #0F,#E0
    DB #1F,#F8
    DB #3F,#FC
    DB #37,#FC
    DB #7F,#BE
    DB #FF,#FE
    DB #FF,#FF
    DB #FF,#FF
    DB #7F,#FF
    DB #3F,#FF
    DB #3F,#FE
    DB #1F,#FE
    DB #13,#FC
    DB #01,#F8
    DB #01,#70

ENEMY_LARGE_2:
    DB #01,#C0
    DB #03,#E0
    DB #0F,#F8
    DB #3F,#FC
    DB #1F,#EE
    DB #1F,#FE
    DB #3F,#FF
    DB #FF,#FF
    DB #7F,#FF
    DB #FF,#DF
    DB #FF,#FE
    DB #FF,#FC
    DB #7F,#FC
    DB #3F,#F8
    DB #1F,#E0
    DB #07,#80

ENEMY_LARGE_3:
    DB #0E,#80
    DB #1F,#80
    DB #3F,#C8
    DB #7F,#F8
    DB #7F,#FC
    DB #FF,#FC
    DB #FF,#FE
    DB #FF,#FF
    DB #FF,#FF
    DB #7F,#FF
    DB #7D,#FE
    DB #3F,#EC
    DB #3F,#FC
    DB #1F,#F8
    DB #07,#F0
    DB #03,#C0

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

; Dirty flags for explosion and player.
; Bullet dirty state is inside each bullet slot.
BLAST_DIRTY:     DB 0
SHIP_DIRTY:      DB 1

; -------------------------------------------------------------
; Moving starfield: 16 points, two slow motion rates.
; Each record: X cell, Y pixel (32..191), pixel bit, period mask.
; -------------------------------------------------------------
STAR_CLOCK:    DB 0
DIRTY_COUNT:   DB 0
DIRTY_TAIL:    DW DIRTY_QUEUE
DIRTY_MAP:     DS 768,0
DIRTY_QUEUE:   DS 320,0          ; 160 unique character cells

STAR_POOL:
    ; Mid layer: SCROLL_SPEED pixels every two frames.
    DB 8,73,#10,1
    DB 10,150,#01,1
    DB 12,43,#02,1
    DB 14,170,#08,1
    DB 16,84,#20,1
    DB 18,37,#04,1
    DB 20,114,#40,1
    DB 22,141,#02,1
    ; Far layer: SCROLL_SPEED pixels every four frames.
    DB 9,178,#80,3
    DB 11,38,#08,3
    DB 13,128,#10,3
    DB 15,66,#01,3
    DB 17,152,#20,3
    DB 19,98,#04,3
    DB 21,52,#40,3
    DB 23,186,#02,3
; -------------------------------------------------------------
; Input and HUD state.
; -------------------------------------------------------------
SCROLL_SPEED:      DB 1        ; auto 1..3, multiplier for star/asteroid speed
SCORE:             DW 0        ; 0..65535, saturating 16-bit total
SCORE_TIER:        DB 0        ; SCORE / 1024 at last bonus
HUD_DIRTY:         DB 1        ; numeric labels need redraw
SPACE_HELD:        DB 0

HUD_LABEL_TITLE:  DB "SPACE SODA",0
HUD_LABEL_SPEED:  DB "SPEED",0
HUD_LABEL_SCORE:  DB "SCORE",0
HUD_LABEL_LIVES:  DB "LIVES",0

CAN_LABEL_LEFT:   DB "SPA",0
CAN_LABEL_RIGHT:  DB "CAN",0
CAN_LABEL_VOLUME: DB "0.33",0

PROGRAM_END:
