; -------------------------------------------------------------
; Step 08: main menu / Game Over / full-round reset.
; Background: Space Soda .SCR, already quantized for ZX 48K.
;
; MENU: game is stopped; blinking prompt, any-key press edge.
; PLAYING: the existing main-loop renderer and logic.
; EXPLODING: only 8x8 ship explosion advances, ship is hidden.
; RESPAWN: same score, speed and remaining lives, fresh actors.
; GAME OVER: show final score for 2 seconds, then return to menu.
; -------------------------------------------------------------

SHOW_START_MENU:
    LD A,STATE_MENU
    LD (GAME_STATE),A
    DI
    CALL SFX_STOP
    ; Stop any old AY track before the universal beeper intro.
    IF AY_MUSIC_ENABLED
        CALL AY_STOP
    ENDIF
    CALL LOAD_SPACE_CAN_SCREEN
    CALL DRAW_MENU_LOGO
    LD A,#46                       ; bright yellow title and subtitle
    LD (MENU_TEXT_ATTR),A
    LD BC,#0909
    LD DE,MENU_SUBTITLE
    CALL MENU_PRINT_TEXT

    LD A,#47                       ; bright white on black
    LD (MENU_TEXT_ATTR),A
    ; All four hints are horizontally symmetric about X=15.5.
    LD BC,#0B0C                    ; 8 chars: O...LEFT
    LD DE,MENU_CONTROL_O
    CALL MENU_PRINT_TEXT
    LD BC,#0C0C                    ; 8 chars: P..RIGHT
    LD DE,MENU_CONTROL_P
    CALL MENU_PRINT_TEXT
    LD BC,#0D0A                    ; 12 chars: SPACE...FIRE
    LD DE,MENU_CONTROL_FIRE
    CALL MENU_PRINT_TEXT
    LD BC,#0E0A                    ; 12 chars: ENTER..PAUSE
    LD DE,MENU_CONTROL_PAUSE
    CALL MENU_PRINT_TEXT
    LD A,#42                       
    LD (MENU_TEXT_ATTR),A
    LD BC,#100B                    ; DON'T MISS
    LD DE,MENU_PROMPT_DONT
    CALL MENU_PRINT_TEXT
    LD BC,#110B                    ; ASTEROIDS!
    LD DE,MENU_PROMPT_AST
    CALL MENU_PRINT_TEXT

    LD A,0
    LD (MENU_PROMPT_MODE),A        ; TO START
    CALL MENU_INIT_PROMPT
    ; Always play the beeper title jingle, including on a
    ; 48K without AY. The menu has already been fully drawn.
    LD HL,MELODY_TITLE
    CALL MELODY_PLAY
    ; Then start AY background music, when enabled in the build.
    IF AY_MUSIC_ENABLED
        LD HL,AY_MUSIC_TITLE
        CALL AY_PLAY
    ENDIF
    EI
    CALL MENU_WAIT_ANY_KEY
    JP START_NEW_GAME

SHOW_GAME_OVER:
    LD A,STATE_GAME_OVER
    LD (GAME_STATE),A
    DI
    CALL SFX_STOP
    CALL DRAW_STATIC_UI
    LD A,1
    LD (HUD_DIRTY),A
    CALL RENDER_HUD                 ; final speed, score and 0 lives

    LD A,#42                       ; bright red on black
    LD (MENU_TEXT_ATTR),A
    LD BC,#0A0B
    LD DE,MENU_GAME_OVER
    CALL MENU_PRINT_TEXT

    LD A,#47                       ; bright white on black
    LD (MENU_TEXT_ATTR),A
    LD BC,#0C0A
    LD DE,MENU_FINAL_SCORE
    CALL MENU_PRINT_TEXT
    LD BC,#0E0D
    CALL PRINT_DEC6

    LD BC,#120A
    LD DE,MENU_BACK_TO_TITLE
    CALL MENU_PRINT_TEXT

    ; AY ending updates per 50Hz frame, beeper is the 48K fallback.
    IF AY_MUSIC_ENABLED
        LD HL,AY_MUSIC_GAME_OVER
        CALL AY_PLAY
    ELSE
        LD HL,MELODY_GAME_OVER
        CALL MELODY_PLAY
    ENDIF
    EI
    LD B,GAME_OVER_FRAMES
.HOLD:
    HALT
    IF AY_MUSIC_ENABLED
        PUSH BC
        CALL AY_TICK
        POP BC
    ENDIF
    DJNZ .HOLD
    JP SHOW_START_MENU            ; NOT a direct game restart

; Keep score/speed/lives untouched. Reset only transient game state.
RESET_ROUND_OBJECTS:
    LD HL,BULLET_POOL
    LD (HL),0
    LD DE,BULLET_POOL+1
    LD BC,MAX_BULLETS*BULLET_SLOT_SIZE-1
    LDIR
    CALL INIT_ENEMIES
    CALL STARFIELD_INIT
    XOR A
    LD (SHIP_DRAWN),A
    LD (SHIP_CUR_HALF),A
    LD (SHIP_HALF_POS),A
    LD (BLAST_ACTIVE),A
    LD (BLAST_DRAWN),A
    LD (BLAST_FRAME),A
    LD (BLAST_DIRTY),A
    LD (BLAST_OWNER),A
    LD (BLAST_HALF),A
    LD (BLAST_TYPE),A
    LD (BULLET_COUNT),A
    LD (SHIP_MOVE_TIMER),A
    LD (SHIP_BANK_TIMER),A
    LD (SHIP_BANK_HOLD_TIMER),A
    LD A,1
    LD (SPACE_HELD),A              ; ignore held SPACE from menu/retry
    LD (PAUSE_KEY_HELD),A          ; ignore held ENTER from menu/retry
    LD (SHIP_VISIBLE),A
    LD (SHIP_DIRTY),A
    LD (HUD_DIRTY),A
    LD HL,(SHIP_START_POS)
    LD (SHIP_NEW_POS),HL
    LD (SHIP_CUR_POS),HL
    LD A,2
    LD (SHIP_BANK),A
    LD (SHIP_BANK_TARGET),A
    LD HL,BLAST_FRAME_0
    LD (BLAST_FRAME_PTR),HL
    RET

; The selected SpaceCan Variant #1 is pixel-perfect 16x16
; per glyph, X=8..23, Y=6..7. Dithered blue/cyan-style shading.
DRAW_MENU_LOGO:
    LD HL,MENU_LOGO_POINTERS
    LD (MENU_LOGO_CURSOR),HL
    LD A,PLAYFIELD_LEFT
    LD (MENU_LOGO_X),A
    LD A,8
    LD (MENU_LOGO_LEFT),A
.NEXT:
    LD HL,(MENU_LOGO_CURSOR)
    LD E,(HL)
    INC HL
    LD D,(HL)
    INC HL
    LD (MENU_LOGO_CURSOR),HL
    LD B,6
    LD A,(MENU_LOGO_X)
    LD C,A
    CALL MENU_DRAW_16X16
    LD HL,MENU_LOGO_X
    INC (HL)
    INC (HL)
    LD HL,MENU_LOGO_LEFT
    DEC (HL)
    JR NZ,.NEXT
    RET

; IN BC=top-left YX, DE=32-byte 16x16 sprite. Preserve nothing.
MENU_DRAW_16X16:
    PUSH BC
    PUSH DE
    CALL GET_SCREEN_ADDR
    LD DE,MENU_LOGO_ATTRS_TOP
    CALL RESTORE_ATTR_1_2
    POP DE
    CALL DRAW_1_2
    POP BC
    INC B
    PUSH DE
    CALL GET_SCREEN_ADDR
    LD DE,MENU_LOGO_ATTRS_BOTTOM
    CALL RESTORE_ATTR_1_2
    POP DE
    JP DRAW_1_2

; Print NUL-terminated string with an explicit ZX attribute.
; IN BC=YX and DE=ASCII. Destroys AF,BC,DE,HL.
MENU_PRINT_TEXT:
.NEXT:
    LD A,(DE)
    OR A
    RET Z
    PUSH BC
    PUSH DE
    CALL DRAW_CHAR_AT
    POP DE
    POP BC

    PUSH BC
    PUSH DE
    CALL GET_SCREEN_ADDR
    LD DE,MENU_TEXT_ATTR
    CALL RESTORE_ATTR_1_1
    POP DE
    POP BC
    INC DE
    INC C
    JR .NEXT

MENU_INIT_PROMPT:
    XOR A
    LD (MENU_BLINK_COUNTER),A
    LD A,1
    LD (MENU_PROMPT_ON),A
    JP MENU_DRAW_PROMPT

; "PRESS ANY KEY / TO START" or "PRESS ANY KEY / TO TRY AGAIN".
; Both lines fit entirely inside the X=8..23 gameplay corridor.
MENU_DRAW_PROMPT:
    LD A,#45                       ; cyan
    LD (MENU_TEXT_ATTR),A
    LD A,(MENU_PROMPT_ON)
    OR A
    JR Z,.ERASE
    LD BC,#1309
    LD DE,MENU_PROMPT_PRESS
    ;CALL MENU_PRINT_TEXT
    ;LD A,(MENU_PROMPT_MODE)
    ;OR A
    ;JR NZ,.RETRY
    ;LD BC,#140C                   ; 8-character "TO START" is centered
    ;LD DE,MENU_PROMPT_START
    JP MENU_PRINT_TEXT
.RETRY:
    ;LD BC,#130A                   ; 12-character retry prompt
    ;LD DE,MENU_PROMPT_RETRY
    ;JP MENU_PRINT_TEXT
.ERASE:
    LD BC,#1309
    LD DE,MENU_PROMPT_BLANK_13
    ;CALL MENU_PRINT_TEXT
    ;LD BC,#130A
    ;LD DE,MENU_PROMPT_BLANK_12
    JP MENU_PRINT_TEXT

; First observe all keys released: a held SPACE from the game
; cannot immediately skip Game Over, and holding a start key
; cannot automatically retrigger on the next frame.
MENU_WAIT_ANY_KEY:
.RELEASE:
    HALT
    IF AY_MUSIC_ENABLED
        CALL AY_TICK
    ENDIF
    CALL MENU_ANY_KEY
    OR A
    JR NZ,.RELEASE
.PRESS:
    HALT
    IF AY_MUSIC_ENABLED
        CALL AY_TICK
    ENDIF
    CALL MENU_BLINK_TICK
    CALL MENU_ANY_KEY
    OR A
    JR Z,.PRESS
    RET

MENU_BLINK_TICK:
    LD HL,MENU_BLINK_COUNTER
    INC (HL)
    LD A,(HL)
    AND 15                         ; switch every 16 interrupts
    RET NZ
    LD A,(MENU_PROMPT_ON)
    XOR 1
    LD (MENU_PROMPT_ON),A
    JP MENU_DRAW_PROMPT

; Scan all 8 rows of the Spectrum keyboard (5 bits per row).
; OUT A=0 no key, nonzero any key. Destroys AF,BC,D.
MENU_ANY_KEY:
    LD BC,#FEFE
    LD D,8
.NEXT:
    IN A,(C)
    CPL
    AND #1F
    RET NZ
    RLC B
    DEC D
    JR NZ,.NEXT
    XOR A
    RET

; ENTER pauses both play and explosion animation on a press edge.
; While paused, the main loop skips rendering, physics and input.
; Save exactly the bitmap/attributes under the central 6-char label
; and restore them byte-for-byte on resume (no dirty redraw needed).
HANDLE_PAUSE_KEY:
    LD BC,#BFFE                  ; H J K L ENTER keyboard row
    IN A,(C)
    BIT 0,A                      ; ENTER
    JR NZ,.RELEASED
    LD A,(PAUSE_KEY_HELD)
    OR A
    RET NZ
    LD A,1
    LD (PAUSE_KEY_HELD),A
    LD A,(GAME_STATE)
    CP STATE_PAUSED
    JR Z,.RESUME
    LD (PAUSE_PREVIOUS_STATE),A
    LD A,STATE_PAUSED
    LD (GAME_STATE),A
    IF AY_MUSIC_ENABLED
        CALL AY_PAUSE
    ENDIF
    CALL SAVE_PAUSE_AREA
    LD A,#47
    LD (MENU_TEXT_ATTR),A
    LD BC,#0C0D                 ; centered six-character PAUSED
    LD DE,PAUSE_LABEL
    CALL MENU_PRINT_TEXT
    ; Only on the ENTER press edge; 4-note E-C-E-C phrase.
    ; The game is already frozen while the beeper plays the jingle.
    LD HL,MELODY_PAUSE
    JP MELODY_PLAY
.RESUME:
    CALL RESTORE_PAUSE_AREA
    IF AY_MUSIC_ENABLED
        CALL AY_RESUME
    ENDIF
    LD A,(PAUSE_PREVIOUS_STATE)
    LD (GAME_STATE),A
    RET
.RELEASED:
    XOR A
    LD (PAUSE_KEY_HELD),A
    RET

SAVE_PAUSE_AREA:
    LD DE,PAUSE_SAVED_BITMAP
    LD C,PAUSE_TEXT_X
    LD A,PAUSE_TEXT_WIDTH
.NEXT:
    PUSH AF
    PUSH BC
    LD B,PAUSE_TEXT_Y
    CALL GET_SCREEN_ADDR
    LD B,8
.ROW:
    LD A,(HL)
    LD (DE),A
    INC DE
    INC H
    DJNZ .ROW
    POP BC
    INC C
    POP AF
    DEC A
    JR NZ,.NEXT
    LD HL,PAUSE_ATTR_ADDR
    LD DE,PAUSE_SAVED_ATTR
    LD BC,PAUSE_TEXT_WIDTH
    LDIR
    RET

RESTORE_PAUSE_AREA:
    LD DE,PAUSE_SAVED_BITMAP
    LD C,PAUSE_TEXT_X
    LD A,PAUSE_TEXT_WIDTH
.NEXT:
    PUSH AF
    PUSH BC
    LD B,PAUSE_TEXT_Y
    CALL GET_SCREEN_ADDR
    LD B,8
.ROW:
    LD A,(DE)
    LD (HL),A
    INC DE
    INC H
    DJNZ .ROW
    POP BC
    INC C
    POP AF
    DEC A
    JR NZ,.NEXT
    LD HL,PAUSE_SAVED_ATTR
    LD DE,PAUSE_ATTR_ADDR
    LD BC,PAUSE_TEXT_WIDTH
    LDIR
    RET

MENU_TEXT_ATTR:    DB #47
MENU_LOGO_ATTRS_TOP:    DB #47,#47  ; bright white top band
MENU_LOGO_ATTRS_BOTTOM: DB #45,#45  ; bright cyan shadow band
MENU_LOGO_CURSOR:  DW 0
MENU_LOGO_X:       DB 8
MENU_LOGO_LEFT:    DB 8
MENU_BLINK_COUNTER: DB 0
MENU_PROMPT_ON:    DB 1
MENU_PROMPT_MODE:  DB 0

MENU_SUBTITLE:     DB "SPACE SODA .33",0
MENU_CONTROL_O:    DB "O...LEFT",0
MENU_CONTROL_P:    DB "P..RIGHT",0
MENU_CONTROL_FIRE: DB "SPACE...FIRE",0
MENU_CONTROL_PAUSE: DB "ENTER..PAUSE",0
PAUSE_LABEL:      DB "PAUSED",0
MENU_HINT:         DB "DODGE ASTEROIDS",0
MENU_GAME_OVER:    DB "GAME  OVER",0
MENU_FINAL_SCORE:  DB "FINAL  SCORE",0
MENU_BACK_TO_TITLE: DB "BACK TO MENU",0
MENU_PROMPT_DONT: DB "DON'T MISS",0
MENU_PROMPT_AST: DB "ASTEROIDS!",0
MENU_PROMPT_PRESS: DB "PRESS ANY KEY!",0
MENU_PROMPT_START: DB "TO START",0
MENU_PROMPT_RETRY: DB "TO TRY AGAIN",0
MENU_PROMPT_BLANK_13: DB "              ",0
MENU_PROMPT_BLANK_12: DB "             ",0

MENU_LOGO_POINTERS:
    DW MENU_GLYPH_S,MENU_GLYPH_P,MENU_GLYPH_A,MENU_GLYPH_C
    DW MENU_GLYPH_E,MENU_GLYPH_C,MENU_GLYPH_A,MENU_GLYPH_N

; Pixel-exact Variant #1 from spacecan_variant_1.bin.
; Each glyph is 16x16 pixels (32 bytes), split into two ZX ink
; bands: bright white (#47) above, bright cyan (#45) below.
; Dithered holes give a half-tone shadow without attribute clash.
MENU_GLYPH_S:
    DB #00,#00
    DB #0F,#F8
    DB #3F,#FC
    DB #7F,#FC
    DB #78,#00
    DB #78,#00
    DB #7F,#80
    DB #3B,#B8
    DB #07,#74
    DB #00,#EE
    DB #00,#1C
    DB #20,#3A
    DB #7F,#FE
    DB #7F,#FC
    DB #1F,#F0
    DB #00,#00

MENU_GLYPH_P:
    DB #00,#00
    DB #7F,#F0
    DB #7F,#FC
    DB #7F,#FC
    DB #7C,#3E
    DB #7C,#1E
    DB #7C,#3E
    DB #3B,#BA
    DB #77,#74
    DB #6E,#E0
    DB #5C,#00
    DB #38,#00
    DB #7C,#00
    DB #7C,#00
    DB #7C,#00
    DB #00,#00

MENU_GLYPH_A:
    DB #00,#00
    DB #03,#C0
    DB #07,#C0
    DB #07,#E0
    DB #07,#E0
    DB #0F,#E0
    DB #0E,#70
    DB #0A,#30
    DB #16,#70
    DB #0C,#68
    DB #1D,#D8
    DB #3B,#B8
    DB #3D,#BC
    DB #38,#1C
    DB #78,#1E
    DB #00,#00

MENU_GLYPH_C:
    DB #00,#00
    DB #03,#F8
    DB #0F,#FE
    DB #1F,#FE
    DB #3E,#02
    DB #7C,#00
    DB #7C,#00
    DB #38,#00
    DB #74,#00
    DB #6C,#00
    DB #5C,#00
    DB #3A,#02
    DB #1F,#FE
    DB #0F,#FE
    DB #03,#F8
    DB #00,#00

MENU_GLYPH_E:
    DB #00,#00
    DB #7F,#FC
    DB #7F,#FC
    DB #7F,#FC
    DB #7C,#00
    DB #7C,#00
    DB #7F,#FC
    DB #3B,#B8
    DB #77,#74
    DB #6C,#00
    DB #5C,#00
    DB #38,#00
    DB #7F,#FE
    DB #7F,#FE
    DB #7F,#FE
    DB #00,#00

MENU_GLYPH_N:
    DB #00,#00
    DB #7C,#1E
    DB #7E,#1E
    DB #7E,#1E
    DB #7F,#1E
    DB #7F,#1E
    DB #7F,#9E
    DB #3B,#9A
    DB #71,#56
    DB #68,#EE
    DB #58,#DC
    DB #38,#BA
    DB #78,#7E
    DB #78,#3E
    DB #78,#3E
    DB #00,#00
