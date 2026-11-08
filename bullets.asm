; -------------------------------------------------------------
; BULLET POOL (6 x 9 bytes)
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
; Bullet preserves the ship's exact 4px alignment at firing.
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
    DEC H                        ; launch one row above the ship
    LD (IX+B_X),L
    LD (IX+B_Y),H
    LD A,(SHIP_HALF_POS)
    LD (IX+B_HALF),A            ; 0=aligned, 1=shift right 4 pixels
    LD A,1
    LD (IX+B_ACTIVE),A
    LD (IX+B_DIRTY),A
    LD HL,BULLET_COUNT
    INC (HL)
    LD A,SFX_SHOT
    JP SFX_START                 ; sound only after successful spawn
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

    ; Check character-cell overlap of bullet and explosion.
    ; A shifted 8x8 bullet can occupy B_X and B_X+1.
    ; A large asteroid blast or shifted ship blast covers 2 cells.
    LD A,(BLAST_POS)
    LD C,A
    LD A,(IX+B_X)
    CP C
    JR Z,.ABSORB
    JR C,.BULLET_LEFT

    ; Bullet lies one cell to the right of the blast start.
    SUB C
    CP 1
    RET NZ
    LD A,(BLAST_TYPE)
    OR A
    JR NZ,.ABSORB
    LD A,(BLAST_OWNER)
    OR A
    RET Z
    LD A,(BLAST_HALF)
    OR A
    RET Z
    JR .ABSORB

.BULLET_LEFT:
    LD A,(IX+B_HALF)
    OR A
    RET Z
    LD A,(IX+B_X)
    INC A
    CP C
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

    ; Also invalidate the new occupied area, so stars behind a
    ; newly fired half-shifted bullet are restored on the star pass.
    LD A,(IX+B_ACTIVE)
    OR A
    JR Z,.SKIP
    LD B,(IX+B_Y)
    LD C,(IX+B_X)
    LD DE,#0101
    LD A,(IX+B_HALF)
    OR A
    JR Z,.MARK_NEW
    LD D,2
.MARK_NEW:
    CALL STARFIELD_MARK_RECT
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
    LD A,(IX+B_HALF)
    OR A
    JR NZ,.SHIFTED
    LD DE,BULLET_ATTR
    CALL RESTORE_ATTR_1_1
    LD DE,BULLET_SPRITE
    CALL DRAW_1_1
    JR .SAVE_DRAWN
.SHIFTED:
    LD DE,BULLET_ATTR_PAIR
    CALL RESTORE_ATTR_1_2
    LD DE,BULLET_SPRITE
    CALL DRAW_SHIFT4_1_1
.SAVE_DRAWN:
    LD A,(IX+B_X)
    LD (IX+B_DRAW_X),A
    LD A,(IX+B_Y)
    LD (IX+B_DRAW_Y),A
    LD A,(IX+B_HALF)
    LD (IX+B_DRAW_HALF),A
    LD A,1
    LD (IX+B_DRAWN),A
    RET

ERASE_BULLET_SLOT:
    LD B,(IX+B_DRAW_Y)
    LD C,(IX+B_DRAW_X)
    LD DE,#0101
    LD A,(IX+B_DRAW_HALF)
    OR A
    JR Z,.MARK
    LD D,2
.MARK:
    CALL STARFIELD_MARK_RECT
    XOR A
    LD (IX+B_DRAWN),A
    RET
