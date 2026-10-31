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
