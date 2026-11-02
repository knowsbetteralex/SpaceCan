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
