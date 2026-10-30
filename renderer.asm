; -------------------------------------------------------------
; Independent dirty flags, two passes:
;   1) Restore old backgrounds of ALL modified objects.
;   2) Save the new backgrounds and draw only modified objects.
; Non-overlap of game objects is enforced by game logic.
; Background scroll will be inserted BETWEEN these passes later.
; -------------------------------------------------------------
RENDER_FRAME:
    CALL RENDER_ERASE_BULLETS

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
    LD A,(STAR_DIRTY)
    OR A
    JR Z,.STAR_ERASE_DONE
    LD A,(STAR_DRAWN)
    OR A
    CALL NZ,ERASE_STAR
    XOR A
    LD (STAR_DRAWN),A
.STAR_ERASE_DONE:

    ; Next stage: update moving background here, while sprites
    ; whose old positions were affected have been erased.

    LD A,(STAR_DIRTY)
    OR A
    JR Z,.STAR_DONE
    XOR A
    LD (STAR_DIRTY),A
    LD A,(STAR_ALIVE)
    OR A
    JR Z,.STAR_DONE
    CALL DRAW_STAR
    LD A,1
    LD (STAR_DRAWN),A
.STAR_DONE:
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
    JP RENDER_DRAW_BULLETS
