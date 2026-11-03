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
    LD A,(SHIP_VISIBLE)
    OR A
    JR Z,.SHIP_DONE
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
