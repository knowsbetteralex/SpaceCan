; -------------------------------------------------------------
; Graphics primitives (screen address, 8x8 and 16x8 bitmap/attrs).
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

SAVE_ATTR_1_1:
    PUSH HL
    LD A,H
    RRCA
    RRCA
    RRCA
    AND 3
    OR #58
    LD H,A
    LD A,(HL)
    LD (DE),A
    POP HL
    RET

SAVE_ATTR_1_2:
    PUSH HL
    LD A,H
    RRCA
    RRCA
    RRCA
    AND 3
    OR #58
    LD H,A
    LD A,(HL)
    LD (DE),A
    INC L
    INC DE
    LD A,(HL)
    LD (DE),A
    POP HL
    RET

SAVE_BITMAP_1_1:
    LD B,8
    PUSH HL
LOOP_SAVE_BITMAP_1_1:
    LD A,(HL)
    LD (DE),A
    INC H
    INC DE
    DJNZ LOOP_SAVE_BITMAP_1_1
    POP HL
    RET

SAVE_BITMAP_1_2:
    LD B,8
    PUSH HL
LOOP_SAVE_BITMAP_1_2:
    LD A,(HL)
    LD (DE),A
    INC L
    INC DE
    LD A,(HL)
    LD (DE),A
    DEC L
    INC H
    INC DE
    DJNZ LOOP_SAVE_BITMAP_1_2
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
    
DRAW_1_2_BLENDED:
    LD B,8
    PUSH HL
LOOP_DRAW_1_2_BLENDED:
    LD A,(DE)
    OR (HL) ; OR-BLEND
    LD (HL),A
    INC L
    INC DE
    LD A,(DE)
    OR (HL) ; OR-BLEND
    LD (HL),A
    DEC L
    INC H
    INC DE
    DJNZ LOOP_DRAW_1_2_BLENDED
    POP HL
    RET
    
DRAW_1_1_BLENDED:
    LD B,8
    PUSH HL
LOOP_DRAW_1_1_BLENDED:
    LD A,(DE)
    OR (HL) ; OR-BLEND
    LD (HL),A
    INC H
    INC DE
    DJNZ LOOP_DRAW_1_1_BLENDED
    POP HL
    RET
