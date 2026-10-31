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
