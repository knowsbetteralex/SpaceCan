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
    CALL GET_SCREEN_ADDR
    JP CLEAR_CELL_1_2

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
    CALL GET_SCREEN_ADDR
    LD A,(BLAST_TYPE)
    OR A
    JP Z,CLEAR_CELL_1_1
    JP CLEAR_CELL_1_2

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
