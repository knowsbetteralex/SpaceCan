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
    LD DE,#0101                ; aligned 8px -> 1 cell
    LD A,(SHIP_CUR_HALF)
    OR A
    JR Z,.TEST_SHIP
    LD D,2                     ; shifted 8px -> 2 cells
.TEST_SHIP:
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
    JR NZ,.BLAST_WIDE
    LD A,(BLAST_OWNER)
    OR A
    JR Z,.BLAST_RECT
    LD A,(BLAST_HALF)
    OR A
    JR Z,.BLAST_RECT
.BLAST_WIDE:
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
    LD DE,#0101
    LD A,(IX+B_DRAW_HALF)
    OR A
    JR Z,.BULLET_RECT
    LD D,2
.BULLET_RECT:
    CALL STARFIELD_TEST_RECT
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
