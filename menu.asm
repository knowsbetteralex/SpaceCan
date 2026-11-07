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
    EI
    CALL MENU_WAIT_ANY_KEY
    JP START_NEW_GAME

SHOW_GAME_OVER:
    LD A,STATE_GAME_OVER
    LD (GAME_STATE),A
    DI
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
    LD HL,(SCORE)
    LD BC,#0E0D
    CALL PRINT_DEC5

    LD BC,#120A
    LD DE,MENU_BACK_TO_TITLE
    CALL MENU_PRINT_TEXT

    ; 100 frame interrupts = approximately two seconds on 48K.
    ; Future music can be started before this wait loop.
    EI
    LD B,GAME_OVER_FRAMES
.HOLD:
    HALT
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

; 8 custom 16x16 pixel letters spanning X=8..23, Y=6..7.
; 5x7 bitmaps are expanded 2x in both directions with margins.
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
    LD DE,MENU_LOGO_ATTRS
    CALL RESTORE_ATTR_1_2
    POP DE
    CALL DRAW_1_2
    POP BC
    INC B
    PUSH DE
    CALL GET_SCREEN_ADDR
    LD DE,MENU_LOGO_ATTRS
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
    CALL MENU_ANY_KEY
    OR A
    JR NZ,.RELEASE
.PRESS:
    HALT
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
    CALL SAVE_PAUSE_AREA
    LD A,#47
    LD (MENU_TEXT_ATTR),A
    LD BC,#0C0D                 ; centered six-character PAUSED
    LD DE,PAUSE_LABEL
    JP MENU_PRINT_TEXT
.RESUME:
    CALL RESTORE_PAUSE_AREA
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
MENU_LOGO_ATTRS:   DB #44,#44
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
MENU_GAME_OVER:    DB "GAME OVER",0
MENU_FINAL_SCORE:  DB "FINAL SCORE",0
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

MENU_GLYPH_S:
    DB #00,#00
    DB #07,#E0
    DB #07,#E0
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #07,#E0
    DB #07,#E0
    DB #00,#18
    DB #00,#18
    DB #00,#18
    DB #00,#18
    DB #1F,#E0
    DB #1F,#E0
    DB #00,#00

MENU_GLYPH_P:
    DB #00,#00
    DB #1F,#E0
    DB #1F,#E0
    DB #18,#18
    DB #18,#18
    DB #18,#18
    DB #18,#18
    DB #1F,#E0
    DB #1F,#E0
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #00,#00

MENU_GLYPH_A:
    DB #00,#00
    DB #07,#E0
    DB #07,#E0
    DB #18,#18
    DB #18,#18
    DB #18,#18
    DB #18,#18
    DB #1F,#F8
    DB #1F,#F8
    DB #18,#18
    DB #18,#18
    DB #18,#18
    DB #18,#18
    DB #18,#18
    DB #18,#18
    DB #00,#00

MENU_GLYPH_C:
    DB #00,#00
    DB #07,#F8
    DB #07,#F8
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #07,#F8
    DB #07,#F8
    DB #00,#00

MENU_GLYPH_E:
    DB #00,#00
    DB #1F,#F8
    DB #1F,#F8
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #1F,#E0
    DB #1F,#E0
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #18,#00
    DB #1F,#F8
    DB #1F,#F8
    DB #00,#00

MENU_GLYPH_N:
    DB #00,#00
    DB #18,#18
    DB #18,#18
    DB #1E,#18
    DB #1E,#18
    DB #19,#98
    DB #19,#98
    DB #18,#78
    DB #18,#78
    DB #18,#18
    DB #18,#18
    DB #18,#18
    DB #18,#18
    DB #18,#18
    DB #18,#18
    DB #00,#00
