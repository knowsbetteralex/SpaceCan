; -------------------------------------------------------------
; Game objects are opaque. No backdrop saving or OR blending.
 ; The old image contributes cells to the dirty queue. Opaque
; object drawing happens after cleaning, moving stars are last.
; -------------------------------------------------------------

; DRAW_SHIP accepts character X and an extra 4px displacement.
; One 8x8 pose occupies 1 byte if aligned, 2 bytes if shifted.
; IN: SHIP_NEW_POS, SHIP_HALF_POS, SHIP_BANK. Clobbers AF, BC, DE, HL.
DRAW_SHIP:
    LD A,(SHIP_BANK)
    ADD A,A                      ; five DW sprite addresses
    LD E,A
    LD D,0
    LD HL,SHIP_FRAMES
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
    PUSH DE                      ; save 8-byte sprite source

    LD BC,(SHIP_NEW_POS)
    CALL GET_SCREEN_ADDR
    LD A,(SHIP_HALF_POS)
    OR A
    JR NZ,.SHIFTED

    LD DE,SHIP_ATTR
    CALL RESTORE_ATTR_1_1
    POP DE
    JP DRAW_1_1

.SHIFTED:
    LD DE,SHIP_ATTR_PAIR
    CALL RESTORE_ATTR_1_2
    POP DE
    JP DRAW_SHIFT4_1_1

; OLD bitmap footprint is 8x8 (aligned) or 12x8 (half-shifted).
; Mark whole affected cells for background and star reconstruction.
ERASE_SHIP:
    LD BC,(SHIP_CUR_POS)
    LD DE,#0101
    LD A,(SHIP_CUR_HALF)
    OR A
    JR Z,.MARK
    LD D,2
.MARK:
    JP STARFIELD_MARK_RECT

; Small explosion: 1x1 (8x8); large: 1x2 (16x8).
; Both use the original asteroid top-left Y with no offset.
DRAW_BLAST:
    LD BC,(BLAST_POS)
    CALL GET_SCREEN_ADDR
    LD A,(BLAST_TYPE)
    OR A
    JR NZ,.WIDE

    LD A,(BLAST_OWNER)
    OR A
    JR Z,.ASTEROID_SMALL

    ; Ship blast: choose color for this frame and reproduce
    ; the same 4px shift as the ship's last logical position.
    PUSH HL
    LD A,(BLAST_FRAME)
    LD E,A
    LD D,0
    LD HL,SHIP_BLAST_ATTRS
    ADD HL,DE
    LD A,(HL)
    LD (BLAST_ATTR_PAIR),A
    LD (BLAST_ATTR_PAIR+1),A
    POP HL

    LD A,(BLAST_HALF)
    OR A
    JR NZ,.SHIP_SHIFTED
    LD DE,BLAST_ATTR_PAIR
    CALL RESTORE_ATTR_1_1
    LD DE,(BLAST_FRAME_PTR)
    JP DRAW_1_1
.SHIP_SHIFTED:
    LD DE,BLAST_ATTR_PAIR
    CALL RESTORE_ATTR_1_2
    LD DE,(BLAST_FRAME_PTR)
    JP DRAW_SHIFT4_1_1

.ASTEROID_SMALL:
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
    JR NZ,.TWO_CELLS
    LD A,(BLAST_OWNER)
    OR A
    JR Z,.MARK
    LD A,(BLAST_HALF)
    OR A
    JR Z,.MARK
.TWO_CELLS:
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
