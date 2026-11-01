; -------------------------------------------------------------
; Selective renderer for an opaque foreground over moving stars.
;
; Old object footprints are queued as dirty character cells.
; All queued cells are cleared and their star background reconstructed.
; Changed objects are painted opaque over the reconstructed cells.
;
; DIRTY is set on movement, animation tick, damage, spawning or
; deactivation; it remains clear for an unchanged object.
;
; When moving stars are added later, their changed character cells
; will mark intersecting objects DIRTY, before rendering, so stars
; never punch through stationary opaque sprites.
; -------------------------------------------------------------
RENDER_FRAME:
    ; Star movement can invalidate otherwise stationary opaque objects.
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
    ; One clear per dirty cell, then plot current stars in those cells.
    CALL STARFIELD_REFRESH_CELLS

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
