; -------------------------------------------------------------
; STATIC UI. Called once at START, outside the frame budget.
; Paper colours distinguish HUD/panels from the black corridor.
; Attributes: 32x24 starting at #5800; no attribute FLASH.
; -------------------------------------------------------------
DRAW_STATIC_UI:
    ; Two HUD rows: white ink on blue paper (BRIGHT).
    LD HL,#5800
    LD B,2
.HUD_ROW:
    LD C,32
.HUD_CELL:
    LD (HL),#4F
    INC HL
    DEC C
    JR NZ,.HUD_CELL
    DJNZ .HUD_ROW

    ; Remaining 22 rows: left 6 + corridor 20 + right 6.
    LD HL,#5840                  ; attributes at Y=2
    LD B,22
.SIDE_ROW:
    LD C,6
.LEFT_CELL:
    LD (HL),#4F
    INC HL
    DEC C
    JR NZ,.LEFT_CELL
    LD DE,20
    ADD HL,DE                   ; corridor remains black
    LD C,6
.RIGHT_CELL:
    LD (HL),#4F
    INC HL
    DEC C
    JR NZ,.RIGHT_CELL
    DJNZ .SIDE_ROW

    ; Text: X/Y in character cells. 48K ROM font at #3D00.
    LD BC,#0000
    LD DE,HUD_TEXT_0
    CALL PRINT_TEXT
    LD BC,#0100
    LD DE,HUD_TEXT_1
    CALL PRINT_TEXT

    LD BC,#0300
    LD DE,LEFT_TEXT_0
    CALL PRINT_TEXT
    LD BC,#0600
    LD DE,LEFT_TEXT_1
    CALL PRINT_TEXT
    LD BC,#1000
    LD DE,LEFT_TEXT_2
    CALL PRINT_TEXT

    LD BC,#031A                  ; X=26, Y=3
    LD DE,RIGHT_TEXT_0
    CALL PRINT_TEXT
    LD BC,#061A
    LD DE,RIGHT_TEXT_1
    CALL PRINT_TEXT
    LD BC,#101A
    LD DE,RIGHT_TEXT_2
    CALL PRINT_TEXT
    RET

; Draw only dynamic counters after HALT; no UI work when unchanged.
RENDER_HUD:
    LD A,(HUD_DIRTY)
    OR A
    RET Z
    XOR A
    LD (HUD_DIRTY),A

    LD A,(SCORE)                 ; 0..99, +10 for first target
    LD BC,#0006                  ; SCORE 00: digits start X=6
    CALL PRINT_DEC2

    LD A,(SCROLL_SPEED)
    ADD A,48                     ; ASCII '0'
    LD BC,#0012                  ; SPEED digit at X=18
    CALL DRAW_CHAR_AT

    LD A,(SCROLL_SPEED)
    ADD A,48
    LD BC,#0700                  ; left panel, below SPEED
    CALL DRAW_CHAR_AT

    ; Active bullets in flight: two digits below "SHOTS".
    LD A,(BULLET_COUNT)
    LD BC,#111C                  ; Y=17, X=28
    CALL PRINT_DEC2
    RET

; IN: A=0..99, BC=YX first digit; draw two decimal digits.
PRINT_DEC2:
    LD D,0                       ; tens
.TENS:
    CP 10
    JR C,.WRITE
    SUB 10
    INC D
    JR .TENS
.WRITE:
    PUSH AF                      ; save units
    LD A,D
    ADD A,48
    PUSH BC                      ; DRAW_CHAR_AT destroys B
    CALL DRAW_CHAR_AT
    POP BC
    INC C
    POP AF
    ADD A,48
    JP DRAW_CHAR_AT

; IN: BC=YX, DE -> zero-terminated string (ASCII 32..127).
PRINT_TEXT:
.NEXT:
    LD A,(DE)
    OR A
    RET Z
    PUSH BC
    PUSH DE
    CALL DRAW_CHAR_AT
    POP DE
    POP BC
    INC DE
    INC C
    JR .NEXT

; IN: A=ASCII, BC=YX. Uses ZX Spectrum 48K ROM font.
; OUT: character rendered. DESTROYS: AF, B, DE, HL.
DRAW_CHAR_AT:
    SUB 32
    LD L,A
    LD H,0
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL                  ; font offset = (ASCII-32)*8
    LD DE,#3D00                 ; ROM charset, character 32
    ADD HL,DE
    EX DE,HL                   ; DE = eight bitmap bytes
    CALL GET_SCREEN_ADDR
    JP DRAW_1_1
