; ===== main.asm =====
; SpaceCan Step 08: title menu, ship blast, respawn and game over.
; ZX Spectrum 48K / Delta-C, sjasmplus syntax.
;
; Coordinates are in 8x8 character cells: X in low byte, Y in high byte.
; Cockpit HUD: Y=0..3; playfield: X=8..23, Y=4..23.
; Render after HALT; update logic and moving stars for NEXT frame.

    ORG #9000

BLAST_FRAME_DURATION EQU 4
BLAST_FRAME_COUNT    EQU 4
PLAYFIELD_TOP        EQU 4
PLAYFIELD_LEFT       EQU 8
PLAYFIELD_RIGHT      EQU 23
PLAYFIELD_WIDTH      EQU 16
PLAYFIELD_BOTTOM     EQU 23
MAX_SCROLL_SPEED     EQU 3
SCORE_BONUS_STEP     EQU 1024
START_LIVES          EQU 4
SHIP_MOVE_DELAY      EQU 2
SHIP_BANK_DELAY      EQU 5    ; ticks between 8x8 banking poses
SHIP_BANK_HOLD       EQU 14   ; keep tilt after releasing O/P
MAX_BULLETS          EQU 6
BULLET_SLOT_SIZE     EQU 8
MAX_ENEMIES          EQU 3
ENEMY_SLOT_SIZE      EQU 13
ENEMY_FRAME_DELAY    EQU 4
ENEMY_RESPAWN_DELAY  EQU 24
SHIP_BLAST_DURATION  EQU 5    ; 6 frames x 5 ticks = 0.6 sec
SHIP_BLAST_FRAMES    EQU 6
STATE_MENU           EQU 0
STATE_PLAYING        EQU 1
STATE_EXPLODING      EQU 2
STATE_RESPAWN        EQU 3
STATE_GAME_OVER      EQU 4

; One 13-byte enemy slot: state + animation + last drawn position.
E_ACTIVE       EQU 0
E_TYPE         EQU 1           ; 0=8x8, 1=16x16
E_HP           EQU 2
E_X            EQU 3
E_Y            EQU 4
E_DRAWN        EQU 5
E_DRAW_X       EQU 6
E_DRAW_Y       EQU 7
E_DIRTY        EQU 8
E_FRAME        EQU 9
E_ANIM_TIMER   EQU 10
E_RESPAWN      EQU 11
E_PHASE        EQU 12          ; initial animation timer

; -------------------------------------------------------------
; Border phase diagnostics for ZX Spectrum 48K.
;
; Set DEBUG_BORDER=0 for a normal game build (no phase code emitted).
; Current beeper driver is not installed yet. When enabling beeper
; sound, use a shared #FE output routine to preserve MIC/EAR bits.
; -------------------------------------------------------------

DEBUG_BORDER EQU 1

DBG_RENDER_COLOUR EQU 2  ; red: sprites/background
DBG_HUD_COLOUR    EQU 6  ; yellow: HUD
DBG_INPUT_COLOUR  EQU 5  ; cyan: keyboard
DBG_LOGIC_COLOUR  EQU 4  ; green: game update
DBG_IDLE_COLOUR   EQU 1  ; blue: remainder of frame / HALT

MACRO DEBUG_PHASE colour
    IF DEBUG_BORDER
        LD A,colour
        OUT (#FE),A
    ENDIF
ENDM


; Each bullet slot is exactly 8 bytes (offsets from IX).
B_ACTIVE    EQU 0  ; 0=free, 1=just spawned, 2=flying
B_X         EQU 1
B_Y         EQU 2
B_DRAWN     EQU 3
B_DRAW_X    EQU 4
B_DRAW_Y    EQU 5
B_DIRTY     EQU 6
B_RESERVED  EQU 7       ; padding; no saved background

START:
    DI
    IM 1                         ; 48K ROM interrupt handler
    EI
    JP SHOW_START_MENU

; New game (from menu or after Game Over):
; only here are score, speed and lives reset.
START_NEW_GAME:
    XOR A
    LD (SCORE),A
    LD (SCORE+1),A
    LD (SCORE_TIER),A
    LD A,1
    LD (SCROLL_SPEED),A
    LD A,START_LIVES
    LD (SHIP_LIVES),A
    JP RESTART_ROUND

; Continue after ship explosion, preserving score/speed/lives.
RESTART_ROUND:
    DI
    CALL DRAW_STATIC_UI
    CALL RESET_ROUND_OBJECTS
    LD A,STATE_PLAYING
    LD (GAME_STATE),A
    EI
    JP MAIN_LOOP

MAIN_LOOP:
    HALT
    LD A,(GAME_STATE)
    CP STATE_RESPAWN
    JP Z,RESTART_ROUND
    CP STATE_GAME_OVER
    JP Z,SHOW_GAME_OVER

    DEBUG_PHASE DBG_RENDER_COLOUR
    CALL RENDER_FRAME
    DEBUG_PHASE DBG_HUD_COLOUR
    CALL RENDER_HUD
    DEBUG_PHASE DBG_INPUT_COLOUR
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    JR NZ,.EXPLODING
    CALL READ_INPUT
    DEBUG_PHASE DBG_LOGIC_COLOUR
    CALL UPDATE_GAME
    JR .FRAME_END
.EXPLODING:
    ; The only moving item during this mode is the ship explosion.
    DEBUG_PHASE DBG_LOGIC_COLOUR
    CALL UPDATE_BLAST_ANIM
.FRAME_END:
    DEBUG_PHASE DBG_IDLE_COLOUR
    JR MAIN_LOOP

; ===== menu.asm =====
; -------------------------------------------------------------
; Step 08: main menu / Game Over / full-round reset.
; Background: Space Soda .SCR, already quantized for ZX 48K.
;
; MENU: game is stopped; blinking prompt, any-key press edge.
; PLAYING: the existing main-loop renderer and logic.
; EXPLODING: only 8x8 ship explosion advances, ship is hidden.
; RESPAWN: same score, speed and remaining lives, fresh actors.
; GAME OVER: final score displayed; any key starts a new game.
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
    LD BC,#0B0C                    ; O - LEFT
    LD DE,MENU_CONTROL_O
    CALL MENU_PRINT_TEXT
    LD BC,#0C0B                    ; P - RIGHT
    LD DE,MENU_CONTROL_P
    CALL MENU_PRINT_TEXT
    LD BC,#0E09                    ; SPACE TO FIRE
    LD DE,MENU_CONTROL_FIRE
    CALL MENU_PRINT_TEXT
    LD BC,#1008                    ; DODGE ASTEROIDS
    LD DE,MENU_HINT
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
    CALL RENDER_HUD                 ; final speed / score / 0 lives

    LD A,#42                       ; bright red on black
    LD (MENU_TEXT_ATTR),A
    LD BC,#0A0B
    LD DE,MENU_GAME_OVER
    CALL MENU_PRINT_TEXT

    LD A,#47
    LD (MENU_TEXT_ATTR),A
    LD BC,#0C0A
    LD DE,MENU_FINAL_SCORE
    CALL MENU_PRINT_TEXT
    LD HL,(SCORE)
    LD BC,#0E0D
    CALL PRINT_DEC5

    LD A,1
    LD (MENU_PROMPT_MODE),A        ; TO TRY AGAIN
    CALL MENU_INIT_PROMPT
    EI
    CALL MENU_WAIT_ANY_KEY
    JP START_NEW_GAME

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
    LD (BLAST_ACTIVE),A
    LD (BLAST_DRAWN),A
    LD (BLAST_FRAME),A
    LD (BLAST_DIRTY),A
    LD (BLAST_OWNER),A
    LD (BLAST_TYPE),A
    LD (BULLET_COUNT),A
    LD (SHIP_MOVE_TIMER),A
    LD (SHIP_BANK_TIMER),A
    LD (SHIP_BANK_HOLD_TIMER),A
    LD A,1
    LD (SPACE_HELD),A              ; ignore held SPACE from menu/retry
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
    LD BC,#1209
    LD DE,MENU_PROMPT_PRESS
    CALL MENU_PRINT_TEXT
    LD BC,#130A
    LD A,(MENU_PROMPT_MODE)
    OR A
    LD DE,MENU_PROMPT_START
    JR Z,.DRAW_LINE2
    LD DE,MENU_PROMPT_RETRY
.DRAW_LINE2:
    JP MENU_PRINT_TEXT
.ERASE:
    LD BC,#1209
    LD DE,MENU_PROMPT_BLANK_13
    CALL MENU_PRINT_TEXT
    LD BC,#130A
    LD DE,MENU_PROMPT_BLANK_12
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

MENU_TEXT_ATTR:    DB #47
MENU_LOGO_ATTRS:   DB #46,#46
MENU_LOGO_CURSOR:  DW 0
MENU_LOGO_X:       DB 8
MENU_LOGO_LEFT:    DB 8
MENU_BLINK_COUNTER: DB 0
MENU_PROMPT_ON:    DB 1
MENU_PROMPT_MODE:  DB 0

MENU_SUBTITLE:     DB "SPACE SODA .33",0
MENU_CONTROL_O:    DB "O - LEFT",0
MENU_CONTROL_P:    DB "P - RIGHT",0
MENU_CONTROL_FIRE: DB "SPACE TO FIRE",0
MENU_HINT:         DB "DODGE ASTEROIDS",0
MENU_GAME_OVER:    DB "GAME OVER",0
MENU_FINAL_SCORE:  DB "FINAL SCORE",0
MENU_PROMPT_PRESS: DB "PRESS ANY KEY",0
MENU_PROMPT_START: DB "TO START",0
MENU_PROMPT_RETRY: DB "TO TRY AGAIN",0
MENU_PROMPT_BLANK_13: DB "             ",0
MENU_PROMPT_BLANK_12: DB "            ",0

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

; ===== logic.asm =====
; -------------------------------------------------------------
; INPUT: controls prepare positions only. No drawing here.
; O/P: move; SPACE: fire on edge. Speed is score-driven.
; -------------------------------------------------------------
READ_INPUT:
    CALL READ_SHIP_HORIZONTAL
    CALL READ_FIRE_KEY
    RET

; The 8x8 ship stays within the can corridor (X=8..23, Y=22).
; Movement is still one cell per input tick; banking is independent:
; one pose every SHIP_BANK_DELAY frames, then a short hold after
; release to make brief turns visible.
READ_SHIP_HORIZONTAL:
    LD A,(SHIP_NEW_POS)
    LD E,A
    LD BC,#DFFE
    IN A,(C)
    BIT 0,A                    ; P: right
    JR NZ,.CHECK_LEFT
    LD D,4
    LD A,E
    CP PLAYFIELD_RIGHT
    JR Z,.SET_BANK
    INC E
    JR .MAYBE_MOVE
.CHECK_LEFT:
    BIT 1,A                    ; O: left
    JR NZ,.NO_KEY
    LD D,0
    LD A,E
    CP PLAYFIELD_LEFT
    JR Z,.SET_BANK
    DEC E

.MAYBE_MOVE:
    ; Banking responds immediately, but moving X is rate-limited.
    LD A,(SHIP_MOVE_TIMER)
    OR A
    JR Z,.MOVE
    DEC A
    LD (SHIP_MOVE_TIMER),A
    JR .SET_BANK
.MOVE:
    LD A,E
    LD (SHIP_NEW_POS),A
    LD A,SHIP_MOVE_DELAY-1
    LD (SHIP_MOVE_TIMER),A
    LD A,1
    LD (SHIP_DIRTY),A

.SET_BANK:
    LD A,D
    LD (SHIP_BANK_TARGET),A
    LD A,SHIP_BANK_HOLD
    LD (SHIP_BANK_HOLD_TIMER),A
.NO_KEY:
    JP UPDATE_SHIP_BANK

; Smooth pose selection; no graphics are drawn here.
; BANK = 0,1,2,3,4. Starts with an immediate first tilt,
; then advances one more pose every 5 game frames (0.1s).
; After movement ends, the last pose remains for ~0.28s,
; then steps back toward the neutral pose (2).
UPDATE_SHIP_BANK:
    LD A,(SHIP_BANK_HOLD_TIMER)
    OR A
    JR Z,.LEVEL
    DEC A
    LD (SHIP_BANK_HOLD_TIMER),A
    JR NZ,.TIMER
.LEVEL:
    LD A,2
    LD (SHIP_BANK_TARGET),A

.TIMER:
    LD A,(SHIP_BANK_TIMER)
    OR A
    JR Z,.STEP
    DEC A
    LD (SHIP_BANK_TIMER),A
    RET
.STEP:
    LD A,SHIP_BANK_DELAY-1
    LD (SHIP_BANK_TIMER),A
    LD A,(SHIP_BANK)
    LD HL,SHIP_BANK_TARGET
    CP (HL)
    RET Z
    JR C,.UP
    DEC A
    JR .STORE
.UP:
    INC A
.STORE:
    LD (SHIP_BANK),A
    LD A,1
    LD (SHIP_DIRTY),A
    RET

; No autofire: holding SPACE creates only one bullet.
; A free slot is needed; when all six slots are occupied, do nothing.
READ_FIRE_KEY:
    LD BC,#7FFE
    IN A,(C)
    BIT 0,A
    JR NZ,.RELEASED
    LD A,(SPACE_HELD)
    OR A
    RET NZ
    LD A,1
    LD (SPACE_HELD),A
    JP FIRE_BULLET
.RELEASED:
    XOR A
    LD (SPACE_HELD),A
    RET

; The logic always runs after render and works only with game state.
; Blast first: a new hit starts from full frame 0 duration.
UPDATE_GAME:
    CALL UPDATE_BLAST_ANIM
    CALL UPDATE_ENEMIES
    CALL UPDATE_BULLETS
    CALL CHECK_SHIP_ENEMY_COLLISIONS
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    RET NZ                     ; ship destroyed: freeze starfield
    CALL STARFIELD_UPDATE
    RET

; Start an explosion at a destroyed asteroid (one effect slot).
; IN: IX = asteroid slot. PRESERVES: IX. DESTROYS: AF, DE, HL.
START_ENEMY_BLAST:
    LD A,(BLAST_ACTIVE)
    OR A
    RET NZ
    LD A,(BLAST_DRAWN)
    OR A
    RET NZ
    LD L,(IX+E_X)
    LD H,(IX+E_Y)
    LD (BLAST_POS),HL
    LD A,(IX+E_TYPE)
    LD (BLAST_TYPE),A           ; 0=8x8, 1=16x8 explosion
    XOR A
    LD (BLAST_OWNER),A         ; 0=asteroid; 1=ship
    LD (BLAST_FRAME),A
    CALL SELECT_BLAST_FRAME
    LD A,BLAST_FRAME_DURATION
    LD (BLAST_ANIM_TIMER),A
    LD A,1
    LD (BLAST_ACTIVE),A
    LD (BLAST_DIRTY),A
    IFN DEBUG_BORDER
        LD A,2
        OUT (#FE),A
    ENDIF
    RET

; Dedicated ship explosion replaces any asteroid blast. Its last
; drawn image is marked for erasure BEFORE BLAST_POS is replaced.
; The renderer then erases the ship and paints explosion frame zero.
START_SHIP_EXPLOSION:
    LD A,(BLAST_DRAWN)
    OR A
    JR Z,.OLD_GONE
    CALL ERASE_BLAST
    XOR A
    LD (BLAST_DRAWN),A
.OLD_GONE:
    LD HL,(SHIP_NEW_POS)
    LD (BLAST_POS),HL
    LD A,1
    LD (BLAST_OWNER),A
    LD (BLAST_ACTIVE),A
    LD (BLAST_DIRTY),A
    LD (SHIP_DIRTY),A
    LD A,STATE_EXPLODING
    LD (GAME_STATE),A
    XOR A
    LD (SHIP_VISIBLE),A
    LD (BLAST_TYPE),A         ; dedicated blast is 8x8
    LD (BLAST_FRAME),A
    CALL SELECT_BLAST_FRAME
    LD A,SHIP_BLAST_DURATION
    LD (BLAST_ANIM_TIMER),A
    RET

; Enemy blast: 4x4 ticks. Ship blast: 6x5 ticks (0.6 seconds).
UPDATE_BLAST_ANIM:
    LD A,(BLAST_ACTIVE)
    OR A
    RET Z
    LD HL,BLAST_ANIM_TIMER
    DEC (HL)
    RET NZ
    LD A,(BLAST_OWNER)
    OR A
    LD A,BLAST_FRAME_DURATION
    JR Z,.STORE_DURATION
    LD A,SHIP_BLAST_DURATION
.STORE_DURATION:
    LD (HL),A
    LD A,(BLAST_FRAME)
    INC A
    LD C,BLAST_FRAME_COUNT
    LD B,A
    LD A,(BLAST_OWNER)
    OR A
    JR Z,.FRAME_LIMIT
    LD C,SHIP_BLAST_FRAMES
.FRAME_LIMIT:
    LD A,B
    CP C
    JR Z,.FINISH
    LD (BLAST_FRAME),A
    CALL SELECT_BLAST_FRAME
    LD A,1
    LD (BLAST_DIRTY),A
    RET
.FINISH:
    XOR A
    LD (BLAST_ACTIVE),A
    LD A,1
    LD (BLAST_DIRTY),A
    LD A,(BLAST_OWNER)
    OR A
    RET Z                     ; an asteroid blast ends normally
    LD A,(SHIP_LIVES)
    OR A
    LD A,STATE_RESPAWN
    JR NZ,.NEXT_MODE
    LD A,STATE_GAME_OVER
.NEXT_MODE:
    LD (GAME_STATE),A
    RET

; IN: BLAST_FRAME=frame index. OUT BLAST_FRAME_PTR.
SELECT_BLAST_FRAME:
    LD A,(BLAST_FRAME)
    ADD A,A
    LD E,A
    LD D,0
    LD A,(BLAST_OWNER)
    OR A
    JR Z,.ASTEROID
    LD HL,SHIP_BLAST_FRAME_PTRS
    JR .SELECT
.ASTEROID:
    LD A,(BLAST_TYPE)
    OR A
    LD HL,BLAST_SMALL_FRAMES
    JR Z,.SELECT
    LD HL,BLAST_FRAMES
.SELECT:
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
    LD (BLAST_FRAME_PTR),DE
    RET

; -------------------------------------------------------------
; Score/bonus: 16-bit total, +64 small / +128 large on destruction.
; IN A=points (64 or 128). Preserves IX.
; At SCORE=1024 and 2048 increase speed, maximum 3.
; Lives start at 4 and NEVER increase; impacts only decrease them.
; -------------------------------------------------------------
ADD_SCORE_A:
    LD E,A
    LD D,0
    LD HL,(SCORE)
    ADD HL,DE
    JR NC,.STORE
    LD HL,#FFFF                 ; do not wrap a long-running game
.STORE:
    LD (SCORE),HL
    LD A,1
    LD (HUD_DIRTY),A
    JP CHECK_SCORE_BONUS

CHECK_SCORE_BONUS:
    LD HL,(SCORE)
    LD A,H
    SRL A
    SRL A                       ; A = SCORE / 1024 (0..63)
    LD HL,SCORE_TIER
    CP (HL)
    RET Z
    RET C                       ; no rewards on score reduction
    LD (HL),A

    LD A,(SCROLL_SPEED)
    CP MAX_SCROLL_SPEED
    JR NC,.HUD
    INC A
    LD (SCROLL_SPEED),A
.HUD:
    LD A,1
    LD (HUD_DIRTY),A
    RET

; ===== bullets.asm =====
; -------------------------------------------------------------
; BULLET POOL (6 x 8 bytes)
;
; A slot is reusable only when ACTIVE=0 and DRAWN=0.
; ACTIVE=0 free, 1 just spawned, 2 in flight.
; DRAWN refers to pixels present on screen right now.
; DIRTY indicates that this slot must be erased/redrawn.
;
; Each bullet travels 2 character rows (16 pixels) per tick.
; Collision is checked after EACH one-row move, avoiding tunneling.
; IX always points to the current slot inside *_SLOT procedures.
; -------------------------------------------------------------

; Find a free slot and spawn a bullet directly above the ship.
; Spawn bullet at ship X and row Y-1, aligned with the 8x8 nose.
; DESTROYS AF, BC, DE, HL, IX.
FIRE_BULLET:
    LD A,(BULLET_COUNT)
    CP MAX_BULLETS
    RET Z
    LD IX,BULLET_POOL
    LD B,MAX_BULLETS
.FIND_SLOT:
    LD A,(IX+B_ACTIVE)
    OR A
    JR NZ,.NEXT_SLOT
    LD A,(IX+B_DRAWN)
    OR A
    JR NZ,.NEXT_SLOT

    LD HL,(SHIP_NEW_POS)
    ; Same character X as the 8x8 ship: bullet is aligned with nose.
    DEC H                        ; launch one row above the ship
    LD (IX+B_X),L
    LD (IX+B_Y),H
    LD A,1
    LD (IX+B_ACTIVE),A
    LD (IX+B_DIRTY),A
    LD HL,BULLET_COUNT
    INC (HL)
    RET
.NEXT_SLOT:
    LD DE,BULLET_SLOT_SIZE
    ADD IX,DE
    DJNZ .FIND_SLOT
    RET

; Apply 2 discrete one-row steps to every active bullet.
; Save BC around per-slot calls: inner routines freely change BC.
UPDATE_BULLETS:
    LD IX,BULLET_POOL
    LD B,MAX_BULLETS
.NEXT:
    PUSH BC
    CALL UPDATE_BULLET_SLOT
    POP BC
    LD DE,BULLET_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

UPDATE_BULLET_SLOT:
    LD A,(IX+B_ACTIVE)
    OR A
    RET Z
    ; An asteroid may have moved onto this bullet's previous cell.
    ; Resolve it before the bullet advances.
    CALL CHECK_BULLET_COLLISION
    LD A,(IX+B_ACTIVE)
    OR A
    RET Z
    CP 1
    JR NZ,.FLYING
    ; The first tick after SPACE only makes the new bullet ready.
    ; Its first visible position is adjacent to the ship's nose.
    LD A,2
    LD (IX+B_ACTIVE),A
    RET
.FLYING:
    CALL BULLET_STEP_ONE
    LD A,(IX+B_ACTIVE)
    OR A
    RET Z
    CALL BULLET_STEP_ONE
    LD A,1
    LD (IX+B_DIRTY),A
    RET

; A one-row step may end the bullet or cause a collision.
; Y=2 is the top playable row. Never write a bullet into HUD Y=0/1.
BULLET_STEP_ONE:
    LD A,(IX+B_Y)
    CP PLAYFIELD_TOP
    JR Z,.EXIT_FIELD
    DEC A
    LD (IX+B_Y),A
    JP CHECK_BULLET_COLLISION
.EXIT_FIELD:
    JP DEACTIVATE_BULLET

; Check moving enemies and absorb bullets entering an explosion.
CHECK_BULLET_COLLISION:
    CALL CHECK_BULLET_ENEMIES
    RET C
    LD A,(BLAST_ACTIVE)
    OR A
    RET Z
    LD A,(BLAST_POS+1)
    CP (IX+B_Y)
    RET NZ
    LD A,(BLAST_POS)
    CP (IX+B_X)
    JR Z,.ABSORB
    LD A,(BLAST_TYPE)
    OR A
    RET Z                       ; small explosion occupies only X
    LD A,(BLAST_POS)
    INC A
    CP (IX+B_X)
    RET NZ
.ABSORB:
    JP DEACTIVATE_BULLET

; Only call for ACTIVE=1. The old DRAWN image (if any) is left
; intact until the next RENDER_ERASE_BULLETS pass.
DEACTIVATE_BULLET:
    XOR A
    LD (IX+B_ACTIVE),A
    LD A,1
    LD (IX+B_DIRTY),A
    LD HL,BULLET_COUNT
    DEC (HL)
    RET

; -------------------------------------------------------------
; Selective bullet rendering. No saved background: erase old cell
; to base corridor ink/paper, then draw active bullet opaque.
; -------------------------------------------------------------
RENDER_ERASE_BULLETS:
    LD IX,BULLET_POOL
    LD B,MAX_BULLETS
.NEXT:
    PUSH BC
    LD A,(IX+B_DIRTY)
    OR A
    JR Z,.SKIP
    LD A,(IX+B_DRAWN)
    OR A
    CALL NZ,ERASE_BULLET_SLOT
.SKIP:
    POP BC
    LD DE,BULLET_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

RENDER_DRAW_BULLETS:
    LD IX,BULLET_POOL
    LD B,MAX_BULLETS
.NEXT:
    PUSH BC
    LD A,(IX+B_DIRTY)
    OR A
    JR Z,.SKIP
    LD A,(IX+B_ACTIVE)
    OR A
    CALL NZ,DRAW_BULLET_SLOT
    XOR A
    LD (IX+B_DIRTY),A
.SKIP:
    POP BC
    LD DE,BULLET_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

; IX preserved; all coordinates in character cells.
DRAW_BULLET_SLOT:
    LD B,(IX+B_Y)
    LD C,(IX+B_X)
    CALL GET_SCREEN_ADDR
    LD DE,BULLET_ATTR
    CALL RESTORE_ATTR_1_1
    LD DE,BULLET_SPRITE
    CALL DRAW_1_1

    LD A,(IX+B_X)
    LD (IX+B_DRAW_X),A
    LD A,(IX+B_Y)
    LD (IX+B_DRAW_Y),A
    LD A,1
    LD (IX+B_DRAWN),A
    RET

ERASE_BULLET_SLOT:
    LD B,(IX+B_DRAW_Y)
    LD C,(IX+B_DRAW_X)
    LD DE,#0101
    CALL STARFIELD_MARK_RECT
    XOR A
    LD (IX+B_DRAWN),A
    RET

; ===== enemies.asm =====
; -------------------------------------------------------------
; ENEMIES: three asteroids falling vertically (8x8 and 16x16).
;
; IX -> current enemy slot. X is assigned at every spawn and
; remains constant until deactivation; overlapping spawn positions
; are rejected for objects currently occupying the entry rows.
; Game logic updates state/dirty; renderer stores drawn position.
; -------------------------------------------------------------

; Initialise from ENEMY_START_TABLE: TYPE, START_Y, ANIM_PHASE.
INIT_ENEMIES:
    ; Reset all slots, including DRAWN and DIRTY flags.
    LD HL,ENEMY_POOL
    LD (HL),0
    LD DE,ENEMY_POOL+1
    LD BC,MAX_ENEMIES*ENEMY_SLOT_SIZE-1
    LDIR

    ; Refresh register gives the first spawn sequence some variation.
    LD A,R
    OR 1
    LD (ENEMY_RANDOM_STATE),A

    LD IX,ENEMY_POOL
    LD HL,ENEMY_START_TABLE
    LD B,MAX_ENEMIES
.NEXT:
    LD A,(HL)
    LD (IX+E_TYPE),A
    INC HL
    OR A
    LD A,1
    JR Z,.STORE_HP
    LD A,3
.STORE_HP:
    LD (IX+E_HP),A
    LD A,(HL)
    LD (IX+E_Y),A
    INC HL
    LD A,(HL)
    LD (IX+E_ANIM_TIMER),A
    LD (IX+E_PHASE),A
    INC HL

    ; Every asteroid begins in a randomly selected vertical lane.
    ; This test also avoids collisions with asteroids already at Y=4/5.
    PUSH HL
    PUSH BC
    CALL SELECT_ENEMY_SPAWN_X
    POP BC
    POP HL
    JR C,.SKIP_ACTIVE
    LD A,1
    LD (IX+E_ACTIVE),A
    LD (IX+E_DIRTY),A
.SKIP_ACTIVE:
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    LD A,4
    LD (ENEMY_MOVE_TIMER),A
    RET

; Automatic speed 1..3 controls vertical move period: 4..2 ticks.
UPDATE_ENEMIES:
    LD A,(ENEMY_MOVE_TIMER)
    DEC A
    LD (ENEMY_MOVE_TIMER),A
    JR NZ,.NO_MOVE
    LD A,5
    LD HL,SCROLL_SPEED
    SUB (HL)
    LD (ENEMY_MOVE_TIMER),A
    LD A,1
    LD (ENEMY_MOVE_NOW),A
    JR .PROCESS
.NO_MOVE:
    XOR A
    LD (ENEMY_MOVE_NOW),A
.PROCESS:
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    PUSH BC
    CALL UPDATE_ENEMY_SLOT
    POP BC
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

UPDATE_ENEMY_SLOT:
    LD A,(IX+E_ACTIVE)
    OR A
    JP Z,.INACTIVE

    ; Independently animate four rotation frames.
    LD A,(IX+E_ANIM_TIMER)
    DEC A
    LD (IX+E_ANIM_TIMER),A
    JR NZ,.MOVE
    LD A,ENEMY_FRAME_DELAY
    LD (IX+E_ANIM_TIMER),A
    LD A,(IX+E_FRAME)
    INC A
    AND 3
    LD (IX+E_FRAME),A
    LD A,1
    LD (IX+E_DIRTY),A
.MOVE:
    LD A,(ENEMY_MOVE_NOW)
    OR A
    RET Z
    ; Large 2-row sprite must stop at Y=22 (last bitmap row 23).
    ; Small 1-row sprite may reach Y=23 before disappearing.
    LD A,(IX+E_Y)
    LD C,23
    LD D,A
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.CHECK_BOTTOM
    LD C,22
.CHECK_BOTTOM:
    LD A,D
    CP C
    JP NC,DEACTIVATE_ENEMY
    INC A
    LD (IX+E_Y),A
    LD A,1
    LD (IX+E_DIRTY),A
    RET

.INACTIVE:
    ; Never respawn until old bitmap was erased.
    LD A,(IX+E_RESPAWN)
    OR A
    JR Z,.RESPAWN
    DEC A
    LD (IX+E_RESPAWN),A
    RET NZ
.RESPAWN:
    LD A,(IX+E_DRAWN)
    OR A
    RET NZ
    LD A,PLAYFIELD_TOP
    LD (IX+E_Y),A
    CALL SELECT_ENEMY_SPAWN_X
    RET C                      ; entry row blocked: retry next tick
    LD A,(IX+E_TYPE)
    OR A
    LD A,1
    JR Z,.HP_READY
    LD A,3
.HP_READY:
    LD (IX+E_HP),A
    XOR A
    LD (IX+E_FRAME),A
    LD A,(IX+E_PHASE)
    LD (IX+E_ANIM_TIMER),A
    LD A,1
    LD (IX+E_ACTIVE),A
    LD (IX+E_DIRTY),A
    RET

; -------------------------------------------------------------
; SPAWN X: choose a fresh left edge across the whole 20-cell
; corridor. Reject candidates intersecting another asteroid at
; the entry row(s), then try the next X until a free one is found.
; IX = the inactive/current slot; its logical Y is already set.
; OUT: carry clear = X selected, carry set = all cells occupied.
; Preserves BC, DE, HL and IX. Runs only on spawn, not each frame.
; -------------------------------------------------------------
SELECT_ENEMY_SPAWN_X:
    PUSH BC
    PUSH DE
    PUSH HL

    ; Small uses all 16 columns; large has 15 valid left-Xs.
    LD C,PLAYFIELD_WIDTH
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.PICK
    DEC C
.PICK:
    CALL NEXT_ENEMY_RANDOM       ; A=0..255
.MODULO:
    CP C
    JR C,.START_X
    SUB C
    JR .MODULO
.START_X:
    ADD A,PLAYFIELD_LEFT
    LD (IX+E_X),A
    LD B,PLAYFIELD_WIDTH       ; at most 16 candidate positions
.TRY:
    CALL ENEMY_SPAWN_CLEAR
    JR NC,.SUCCESS

    LD C,PLAYFIELD_RIGHT
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.STEP
    DEC C                       ; large rightmost left-X is 22
.STEP:
    LD A,(IX+E_X)
    CP C
    JR C,.INCREMENT
    LD A,PLAYFIELD_LEFT
    JR .SAVE_X
.INCREMENT:
    INC A
.SAVE_X:
    LD (IX+E_X),A
    DJNZ .TRY
    POP HL
    POP DE
    POP BC
    SCF                         ; cannot spawn this tick
    RET
.SUCCESS:
    POP HL
    POP DE
    POP BC
    OR A                        ; clear carry
    RET

; 8-bit maximal-length Galois LFSR, polynomial #1D.
; A new X is chosen only on spawn. Never re-seed on respawn.
NEXT_ENEMY_RANDOM:
    LD A,(ENEMY_RANDOM_STATE)
    ADD A,A
    JR NC,.STORE
    XOR #1D
.STORE:
    LD (ENEMY_RANDOM_STATE),A
    RET

; Current candidate is in (IX+E_X), new Y is PLAYFIELD_TOP.
; A collision can only happen with an active asteroid whose top
; currently occupies Y=4 or 5 (for a new 2-row large asteroid).
; Carry set: candidate intersects an active asteroid.
; Carry clear: new asteroid fits; preserves BC,DE,HL,IX.
ENEMY_SPAWN_CLEAR:
    PUSH BC
    PUSH DE
    PUSH IX
    LD A,(IX+E_X)
    LD (ENEMY_TEST_X),A
    LD A,(IX+E_TYPE)
    LD (ENEMY_TEST_TYPE),A
    LD A,(IX+E_Y)
    LD (ENEMY_TEST_Y),A
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    LD A,(IX+E_ACTIVE)
    OR A
    JR Z,.SKIP

    ; Vertical interval overlap:
    ; candidate_top <= existing_bottom, and
    ; existing_top <= candidate_bottom.
    LD A,(IX+E_Y)
    LD C,A
    LD A,(IX+E_TYPE)
    ADD A,C                    ; existing bottom Y
    LD C,A
    LD A,(ENEMY_TEST_Y)
    CP C
    JR C,.OTHER_SIDE
    JR Z,.OTHER_SIDE
    JR .SKIP
.OTHER_SIDE:
    LD A,(ENEMY_TEST_Y)
    LD C,A
    LD A,(ENEMY_TEST_TYPE)
    ADD A,C                    ; candidate bottom Y
    LD C,A
    LD A,(IX+E_Y)
    CP C
    JR C,.CHECK_X
    JR NZ,.SKIP
.CHECK_X:
    ; candidate_right < existing_left => no horizontal overlap
    LD A,(ENEMY_TEST_X)
    LD C,A
    LD A,(ENEMY_TEST_TYPE)
    ADD A,C
    CP (IX+E_X)
    JR C,.SKIP

    ; existing_right < candidate_left => no overlap
    LD A,(IX+E_X)
    LD C,A
    LD A,(IX+E_TYPE)
    ADD A,C
    LD C,A
    LD A,(ENEMY_TEST_X)
    CP C
    JR C,.BLOCKED
    JR Z,.BLOCKED
.SKIP:
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    POP IX
    POP DE
    POP BC
    XOR A
    RET
.BLOCKED:
    POP IX
    POP DE
    POP BC
    SCF
    RET

; IX -> enemy. Its drawn image will be erased by renderer.
DEACTIVATE_ENEMY:
    XOR A
    LD (IX+E_ACTIVE),A
    LD A,ENEMY_RESPAWN_DELAY
    LD (IX+E_RESPAWN),A
    LD A,1
    LD (IX+E_DIRTY),A
    RET

; IX -> enemy: score is awarded only on destruction.
; Small = 64 points, large = 128 points; difficulty checks happen
; after the score changes so every 1024-point threshold is caught.
ON_ENEMY_HIT:
    DEC (IX+E_HP)
    JR NZ,.DAMAGED
    CALL START_ENEMY_BLAST
    CALL DEACTIVATE_ENEMY
    LD A,(IX+E_TYPE)
    OR A
    LD A,64
    JR Z,.AWARD
    LD A,128
.AWARD:
    JP ADD_SCORE_A
.DAMAGED:
    LD A,1
    LD (IX+E_DIRTY),A
    RET

; Compare enemies at player row to logical ship X/X+1.
CHECK_SHIP_ENEMY_COLLISIONS:
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    PUSH BC
    CALL CHECK_SHIP_ENEMY_SLOT
    POP BC
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

; Ship occupies one X column and one row.
; Small asteroid: 1x1; large: 2x2.
CHECK_SHIP_ENEMY_SLOT:
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    RET NZ                    ; second collision cannot cost another life
    LD A,(IX+E_ACTIVE)
    OR A
    RET Z

    LD A,(SHIP_NEW_POS+1)
    SUB (IX+E_Y)
    RET C
    OR A
    JR Z,.CHECK_X
    CP 1
    RET NZ
    LD A,(IX+E_TYPE)
    OR A
    RET Z

.CHECK_X:
    LD A,(SHIP_NEW_POS)
    SUB (IX+E_X)
    RET C                       ; ship is left of the asteroid
    OR A
    JR Z,.HIT
    CP 1
    RET NZ                      ; ship too far to the right
    LD A,(IX+E_TYPE)
    OR A
    RET Z                       ; small asteroid is only 1 cell wide
.HIT:
    CALL DEACTIVATE_ENEMY
    LD A,(SHIP_LIVES)
    OR A
    RET Z
    DEC A
    LD (SHIP_LIVES),A
    LD A,1
    LD (HUD_DIRTY),A
    JP START_SHIP_EXPLOSION

; IN: IX=bullet; OUT: carry set iff bullet consumed.
; Preserves IX for caller and all bullet-specific procedures.
CHECK_BULLET_ENEMIES:
    LD B,(IX+B_Y)
    LD C,(IX+B_X)
    PUSH IX
    LD IX,ENEMY_POOL
    LD H,MAX_ENEMIES
.NEXT:
    LD A,(IX+E_ACTIVE)
    OR A
    JR Z,.SKIP
    ; Only large asteroids occupy two character rows.
    LD A,B
    SUB (IX+E_Y)
    JR C,.SKIP
    OR A
    JR Z,.CHECK_X
    CP 1
    JR NZ,.SKIP
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.SKIP
.CHECK_X:
    LD A,C
    SUB (IX+E_X)              ; unsigned delta bulletX - enemyX
    JR C,.SKIP
    OR A
    JR Z,.HIT
    CP 1
    JR NZ,.SKIP
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.SKIP
.HIT:
    CALL ON_ENEMY_HIT
    POP IX
    CALL DEACTIVATE_BULLET
    SCF
    RET
.SKIP:
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DEC H
    JR NZ,.NEXT
    POP IX
    XOR A                       ; carry clear = no hit
    RET

; -------------------------------------------------------------
; RENDER: erase all dirty images, then draw current state.
; -------------------------------------------------------------
RENDER_ERASE_ENEMIES:
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    PUSH BC
    LD A,(IX+E_DIRTY)
    OR A
    JR Z,.SKIP
    LD A,(IX+E_DRAWN)
    OR A
    CALL NZ,ERASE_ENEMY_SLOT
.SKIP:
    POP BC
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

RENDER_DRAW_ENEMIES:
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    PUSH BC
    LD A,(IX+E_DIRTY)
    OR A
    JR Z,.SKIP
    LD A,(IX+E_ACTIVE)
    OR A
    CALL NZ,DRAW_ENEMY_SLOT
    XOR A
    LD (IX+E_DIRTY),A
.SKIP:
    POP BC
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

; Frame table: small0..3, large0..3 (DW pointers).
; OUT: DE=bitmap address. IX and BC preserved.
GET_ENEMY_FRAME:
    LD A,(IX+E_TYPE)
    ADD A,A
    ADD A,A                    ; TYPE*4 (four frames per type)
    ADD A,(IX+E_FRAME)
    ADD A,A                    ; two bytes per table entry
    LD E,A
    LD D,0
    LD HL,ENEMY_FRAMES
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
    RET

; -------------------------------------------------------------
; Small asteroid occupies one 8x8 cell.
; Large asteroid occupies two rows of two cells (16x16).
; Direct bitmap copy, no saved background and no OR blending.
; -------------------------------------------------------------

; IN: A=0 top / 1 bottom, IX=enemy.
; DESTROYS: AF, BC, DE, HL. PRESERVES: IX.
DRAW_ENEMY_ROW:
    PUSH AF
    LD B,(IX+E_Y)
    ADD A,B
    LD B,A
    LD C,(IX+E_X)
    CALL GET_SCREEN_ADDR
    POP AF
    PUSH AF
    PUSH HL
    LD A,(IX+E_TYPE)
    OR A
    JR NZ,.ATTR_WIDE
    LD DE,ENEMY_ATTR_SMALL
    CALL RESTORE_ATTR_1_1
    JR .SPRITE
.ATTR_WIDE:
    LD DE,ENEMY_ATTR_LARGE
    CALL RESTORE_ATTR_1_2
.SPRITE:
    POP HL
    PUSH HL
    CALL GET_ENEMY_FRAME
    POP HL
    POP AF
    OR A
    JR Z,.DRAW
    PUSH HL
    LD A,(IX+E_TYPE)
    OR A
    LD BC,8
    JR Z,.FRAME_OFFSET
    LD BC,16
.FRAME_OFFSET:
    EX DE,HL
    ADD HL,BC
    EX DE,HL
    POP HL
.DRAW:
    LD A,(IX+E_TYPE)
    OR A
    JP Z,DRAW_1_1
    JP DRAW_1_2

DRAW_ENEMY_SLOT:
    XOR A
    CALL DRAW_ENEMY_ROW
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.SINGLE_ROW
    LD A,1
    CALL DRAW_ENEMY_ROW
.SINGLE_ROW:
    LD A,(IX+E_X)
    LD (IX+E_DRAW_X),A
    LD A,(IX+E_Y)
    LD (IX+E_DRAW_Y),A
    LD A,1
    LD (IX+E_DRAWN),A
    RET

; No writes to screen: collect old 1x1 / 2x2 rectangle.
ERASE_ENEMY_SLOT:
    LD B,(IX+E_DRAW_Y)
    LD C,(IX+E_DRAW_X)
    LD DE,#0101                  ; small = width 1, height 1
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.MARK
    LD DE,#0202                  ; large = width 2, height 2
.MARK:
    CALL STARFIELD_MARK_RECT
    XOR A
    LD (IX+E_DRAWN),A
    RET

; ===== starfield.asm =====
; -------------------------------------------------------------
; STARFIELD: 16 moving single-pixel stars, two slower layers.
;
; Record: X character cell, Y pixel, pixel bit mask, period mask.
; Period 1: +speed pixels every 2 frames.
; Period 3: +speed pixels every 4 frames. speed=1..3.
;
; Render order:
;   1) invalidate foreground sprites touched by star changes;
;   2) add old foreground rectangles to the dirty-cell queue;
;   3) clear each dirty cell once;
;   4) draw changed opaque sprites;
;   5) OR new stars LAST, even over asteroids (intended effect).
; No saved background and no full-screen clearing.
; -------------------------------------------------------------

S_X       EQU 0
S_Y       EQU 1
S_MASK    EQU 2
S_PERIOD  EQU 3
STAR_SIZE EQU 4
STAR_COUNT EQU 16
DIRTY_LIMIT EQU 160

STARFIELD_INIT:
    LD HL,DIRTY_MAP
    LD (HL),0
    LD DE,DIRTY_MAP+1
    LD BC,768-1
    LDIR
    XOR A
    LD (DIRTY_COUNT),A
    LD (STAR_CLOCK),A
    LD HL,DIRTY_QUEUE
    LD (DIRTY_TAIL),HL

    LD IX,STAR_POOL
    LD B,STAR_COUNT
.INIT_STARS:
    PUSH BC
    CALL STARFIELD_MARK_STAR
    POP BC
    LD DE,STAR_SIZE
    ADD IX,DE
    DJNZ .INIT_STARS
    RET

; Input BC: B=character Y (4..23), C=character X (8..23).
; Output HL: byte in DIRTY_MAP at offset Y*32 + X.
; Destroys DE, HL. Preserves BC.
STARFIELD_MAP_ADDRESS:
    LD L,B
    LD H,0
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    LD E,C
    LD D,0
    ADD HL,DE
    LD DE,DIRTY_MAP
    ADD HL,DE
    RET

; Mark a character cell just once, append (Y,X) to the queue.
; Preserves BC,DE,HL,IX; destroys AF.
STARFIELD_MARK_CELL:
    PUSH BC
    PUSH DE
    PUSH HL
    CALL STARFIELD_MAP_ADDRESS
    LD A,(HL)
    OR A
    JR NZ,.DONE
    LD A,(DIRTY_COUNT)
    CP DIRTY_LIMIT
    JR NC,.DONE
    INC (HL)
    INC A
    LD (DIRTY_COUNT),A
    LD HL,(DIRTY_TAIL)
    LD (HL),B
    INC HL
    LD (HL),C
    INC HL
    LD (DIRTY_TAIL),HL
.DONE:
    POP HL
    POP DE
    POP BC
    RET

; Read one cell flag. OUT A=0 or 1.
; Preserves BC,DE,HL,IX.
STARFIELD_TEST_CELL:
    PUSH DE
    PUSH HL
    CALL STARFIELD_MAP_ADDRESS
    LD A,(HL)
    POP HL
    POP DE
    RET

; Mark a rectangle of character cells.
; IN B=top Y, C=left X, D=width, E=height.
; Preserves BC,DE,HL,IX.
STARFIELD_MARK_RECT:
    PUSH BC
    PUSH DE
    PUSH HL
.ROW:
    PUSH BC
    LD H,D
.COL:
    CALL STARFIELD_MARK_CELL
    INC C
    DEC H
    JR NZ,.COL
    POP BC
    INC B
    DEC E
    JR NZ,.ROW
    POP HL
    POP DE
    POP BC
    RET

; Test whether any cell in a rectangle is dirty.
; IN B=top Y, C=left X, D=width, E=height.
; OUT A=0 (none) or 1 (at least one).
; Preserves BC,DE,HL,IX.
STARFIELD_TEST_RECT:
    PUSH BC
    PUSH DE
    PUSH HL
.ROW:
    PUSH BC
    LD H,D
.COL:
    CALL STARFIELD_TEST_CELL
    OR A
    JR NZ,.FOUND
    INC C
    DEC H
    JR NZ,.COL
    POP BC
    INC B
    DEC E
    JR NZ,.ROW
    XOR A
    JR .DONE
.FOUND:
    POP BC
    LD A,1
.DONE:
    POP HL
    POP DE
    POP BC
    RET

; Mark a star's current character cell.
; IN IX = star slot. Preserves IX and BC.
STARFIELD_MARK_STAR:
    LD A,(IX+S_Y)
    SRL A
    SRL A
    SRL A
    LD B,A
    LD C,(IX+S_X)
    JP STARFIELD_MARK_CELL

; Logical update only; actual drawing takes place after next HALT.
STARFIELD_UPDATE:
    LD HL,STAR_CLOCK
    INC (HL)
    LD IX,STAR_POOL
    LD B,STAR_COUNT
.NEXT:
    PUSH BC
    LD A,(STAR_CLOCK)
    AND (IX+S_PERIOD)
    JR NZ,.SKIP

    CALL STARFIELD_MARK_STAR  ; old character cell
    ; Both remaining layers use the same pixel step (1..3).
    ; S_PERIOD changes only how often the star takes that step.
    LD A,(SCROLL_SPEED)
    LD C,A
    LD A,(IX+S_Y)
    ADD A,C
    CP 192
    JR C,.SAVE_Y
    SUB 160                  ; wrap into Y=32..191, preserve excess
    LD (IX+S_Y),A
    LD A,(IX+S_X)
    INC A
    CP PLAYFIELD_RIGHT+1
    JR C,.SAVE_X
    LD A,PLAYFIELD_LEFT
.SAVE_X:
    LD (IX+S_X),A
    JR .MARK_NEW
.SAVE_Y:
    LD (IX+S_Y),A
.MARK_NEW:
    CALL STARFIELD_MARK_STAR  ; new character cell
.SKIP:
    POP BC
    LD DE,STAR_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

; If a star changed beneath a stationary sprite, mark that sprite
; DIRTY so the bitmap overwritten by refreshed stars is redrawn.
STARFIELD_INVALIDATE_FOREGROUND:
    LD A,(SHIP_DRAWN)
    OR A
    JR Z,.BLAST
    LD BC,(SHIP_CUR_POS)
    LD DE,#0101              ; ship is now 1x1
    CALL STARFIELD_TEST_RECT
    OR A
    JR Z,.BLAST
    LD A,1
    LD (SHIP_DIRTY),A

.BLAST:
    LD A,(BLAST_DRAWN)
    OR A
    JR Z,.BULLETS
    LD BC,(BLAST_POS)
    LD DE,#0101
    LD A,(BLAST_TYPE)
    OR A
    JR Z,.BLAST_RECT
    LD D,2
.BLAST_RECT:
    CALL STARFIELD_TEST_RECT
    OR A
    JR Z,.BULLETS
    LD A,1
    LD (BLAST_DIRTY),A

.BULLETS:
    LD IX,BULLET_POOL
    LD B,MAX_BULLETS
.NEXT_BULLET:
    PUSH BC
    LD A,(IX+B_DRAWN)
    OR A
    JR Z,.SKIP_BULLET
    LD B,(IX+B_DRAW_Y)
    LD C,(IX+B_DRAW_X)
    CALL STARFIELD_TEST_CELL
    OR A
    JR Z,.SKIP_BULLET
    LD A,1
    LD (IX+B_DIRTY),A
.SKIP_BULLET:
    POP BC
    LD DE,BULLET_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT_BULLET

.ENEMIES:
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT_ENEMY:
    PUSH BC
    LD A,(IX+E_DRAWN)
    OR A
    JR Z,.SKIP_ENEMY
    LD B,(IX+E_DRAW_Y)
    LD C,(IX+E_DRAW_X)
    LD DE,#0101              ; small asteroid = one 8x8 cell
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.ENEMY_RECT
    LD DE,#0202              ; large asteroid = 2x2 cells
.ENEMY_RECT:
    CALL STARFIELD_TEST_RECT
    OR A
    JR Z,.SKIP_ENEMY
    LD A,1
    LD (IX+E_DIRTY),A
.SKIP_ENEMY:
    POP BC
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT_ENEMY
    RET

; Stage 1: clear changed cells BEFORE drawing sprites.
; DIRTY_MAP and DIRTY_QUEUE remain valid until the star pass finishes.
STARFIELD_CLEAR_CELLS:
    LD A,(DIRTY_COUNT)
    OR A
    RET Z
    LD B,A
    LD IX,DIRTY_QUEUE
.CLEAR_NEXT:
    PUSH BC
    LD B,(IX+0)
    LD C,(IX+1)
    CALL GET_SCREEN_ADDR
    CALL CLEAR_CELL_1_1
    INC IX
    INC IX
    POP BC
    DJNZ .CLEAR_NEXT
    RET

; Stage 2: plot current stars AFTER all foreground drawing.
; An OR star may intentionally appear over an asteroid.
; Reset the dirty queue only AFTER plotting all stars.
STARFIELD_DRAW_STARS:
    LD A,(DIRTY_COUNT)
    OR A
    RET Z

    LD IX,STAR_POOL
    LD B,STAR_COUNT
.DRAW_NEXT:
    PUSH BC
    LD A,(IX+S_Y)
    SRL A
    SRL A
    SRL A
    LD B,A
    LD C,(IX+S_X)
    CALL STARFIELD_TEST_CELL
    OR A
    CALL NZ,STARFIELD_DRAW_STAR
    POP BC
    LD DE,STAR_SIZE
    ADD IX,DE
    DJNZ .DRAW_NEXT

    LD IX,DIRTY_QUEUE
    LD A,(DIRTY_COUNT)
    LD B,A
.RESET_NEXT:
    PUSH BC
    LD B,(IX+0)
    LD C,(IX+1)
    CALL STARFIELD_MAP_ADDRESS
    XOR A
    LD (HL),A
    INC IX
    INC IX
    POP BC
    DJNZ .RESET_NEXT

    XOR A
    LD (DIRTY_COUNT),A
    LD HL,DIRTY_QUEUE
    LD (DIRTY_TAIL),HL
    RET

; Draw one white star bit. Its Y is a PIXEL coordinate, not a row.
; IN IX=star. Uses only OR for background point composition.
; Unlike opaque sprites, stars are intentionally OR'ed on top.
STARFIELD_DRAW_STAR:
    LD A,(IX+S_Y)
    SRL A
    SRL A
    SRL A
    LD B,A
    LD C,(IX+S_X)
    CALL GET_SCREEN_ADDR
    LD A,(IX+S_Y)
    AND 7
    ADD A,H
    LD H,A
    LD A,(IX+S_MASK)
    OR (HL)
    LD (HL),A
    RET

; ===== renderer.asm =====
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

; ===== graphics.asm =====
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

; ===== objects.asm =====
; -------------------------------------------------------------
; Game objects are opaque. No backdrop saving or OR blending.
 ; The old image contributes cells to the dirty queue. Opaque
; object drawing happens after cleaning, moving stars are last.
; -------------------------------------------------------------

DRAW_SHIP:
    ; Select one of five 8x8 pictures without changing its X/Y.
    ; Visual bank is independent of position; hitbox = one cell.
    LD A,(SHIP_BANK)             ; 0..4
    ADD A,A                      ; 2-byte DW address table
    LD E,A
    LD D,0
    LD HL,SHIP_FRAMES
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)                    ; DE -> 8-byte sprite
    PUSH DE

    LD BC,(SHIP_NEW_POS)
    CALL GET_SCREEN_ADDR
    LD DE,SHIP_ATTR
    CALL RESTORE_ATTR_1_1
    POP DE
    JP DRAW_1_1

ERASE_SHIP:
    LD BC,(SHIP_CUR_POS)
    LD DE,#0101
    JP STARFIELD_MARK_RECT

; Small explosion: 1x1 (8x8); large: 1x2 (16x8).
; Both use the original asteroid top-left Y with no offset.
DRAW_BLAST:
    LD BC,(BLAST_POS)
    CALL GET_SCREEN_ADDR
    LD A,(BLAST_TYPE)
    OR A
    JR NZ,.WIDE
    ; Different colours for dedicated six-frame ship blast.
    PUSH HL
    LD A,(BLAST_OWNER)
    OR A
    LD DE,BLAST_ATTR_SMALL
    JR Z,.SMALL_ATTR
    LD A,(BLAST_FRAME)
    LD E,A
    LD D,0
    LD HL,SHIP_BLAST_ATTRS
    ADD HL,DE
    EX DE,HL
.SMALL_ATTR:
    POP HL
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
    JR Z,.MARK
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

; ===== ui.asm =====
; -------------------------------------------------------------
; SpaceCan Step 07: static native ZX can-and-bar background.
; Artwork is unpacked once; only numbers are changed at runtime.
; -------------------------------------------------------------
DRAW_STATIC_UI:
    ; Draw the complete ZX screen, including a pure-black 16x20
    ; gameplay corridor. No images are ever copied during gameplay.
    CALL LOAD_SPACE_CAN_SCREEN

    ; Static ROM characters are painted ON TOP of blank HUD cells.
    ; They are not baked in the .SCR so their 8x8 pixels are crisp.
    LD BC,#0005                  ; title at Y=0, X=5
    LD DE,HUD_LABEL_TITLE
    CALL PRINT_TEXT
    LD BC,#0201                  ; SPEED
    LD DE,HUD_LABEL_SPEED
    CALL PRINT_TEXT
    LD BC,#020B                  ; SCORE
    LD DE,HUD_LABEL_SCORE
    CALL PRINT_TEXT
    LD BC,#0217                  ; LIVES
    LD DE,HUD_LABEL_LIVES
    JP PRINT_TEXT

; Decode RLE background directly into ZX bitmap and attributes.
; 00,count,value => repeat byte count times; nonzero => literal byte.
; IN: none. OUT: #4000..#5AFF = exactly 6912 screen bytes.
; DESTROYS: AF, BC, DE, HL. Caller has disabled interrupts.
LOAD_SPACE_CAN_SCREEN:
    LD HL,SPACE_CAN_SCREEN_RLE
    LD DE,#4000
.NEXT:
    LD A,(HL)
    INC HL
    OR A
    JR Z,.RUN_HEADER
    LD (DE),A
    INC DE
    JR .CHECK_END
.RUN_HEADER:
    LD B,(HL)                    ; run length always 1..255
    INC HL
    LD A,(HL)                    ; repeated byte
    INC HL
.REPEAT:
    LD (DE),A
    INC DE
    DJNZ .REPEAT
.CHECK_END:
    LD A,D
    CP #5B                       ; DE reached #5B00, end of attributes
    JR NZ,.NEXT
    RET

; Draw no more than 7 characters when a reading changes.
RENDER_HUD:
    LD A,(HUD_DIRTY)
    OR A
    RET Z
    XOR A
    LD (HUD_DIRTY),A

    LD A,(SCROLL_SPEED)
    ADD A,'0'
    LD BC,#0207                  ; SPEED number
    CALL DRAW_CHAR_AT

    LD HL,(SCORE)
    LD BC,#0210                  ; 5 digits: 00000..65535
    CALL PRINT_DEC5

    LD A,(SHIP_LIVES)
    ADD A,'0'
    LD BC,#021D                  ; lives 0..9
    JP DRAW_CHAR_AT

; IN HL=0..65535, BC=YX of leftmost digit.
; Four repeated divisions by 10^n, ending with the units.
; Dynamic HUD only: straightforward code is preferred to speed.
PRINT_DEC5:
    LD DE,10000
    CALL PRINT_DEC_PLACE
    LD DE,1000
    CALL PRINT_DEC_PLACE
    LD DE,100
    CALL PRINT_DEC_PLACE
    LD DE,10
    CALL PRINT_DEC_PLACE
    LD A,L
    ADD A,'0'
    JP DRAW_CHAR_AT

; IN HL=remainder, DE=decimal place, BC=YX.
; OUT HL=remainder after quotient, C advanced one screen column.
PRINT_DEC_PLACE:
    LD A,'0'
.NEXT:
    OR A                         ; clear carry before SBC HL,DE
    SBC HL,DE
    JR C,.WRITE
    INC A
    JR .NEXT
.WRITE:
    ADD HL,DE                    ; undo the final underflow
    PUSH HL
    PUSH DE
    PUSH BC
    CALL DRAW_CHAR_AT
    POP BC
    POP DE
    POP HL
    INC C
    RET

; IN BC=YX, DE=zero-terminated text.
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

; IN A=ASCII 32..127, BC=YX; draw 8 rows using Spectrum ROM font.
DRAW_CHAR_AT:
    SUB 32
    LD L,A
    LD H,0
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    LD DE,#3D00
    ADD HL,DE
    EX DE,HL
    CALL GET_SCREEN_ADDR
    JP DRAW_1_1

; ===== data.asm =====
; -------------------------------------------------------------
; Sprites and state
; -------------------------------------------------------------
BG_ATTR:
    DB #47                     ; bright white on black; corridor only
BG_ATTR_PAIR:
    DB #47,#47                 ; default attributes for 2-cell clear

SHIP_START_POS:
    DB 15,22

SHIP_FRAMES:
    ; Five 8x8 poses, from hard left (0) to hard right (4).
    DW SHIP_BANK_LEFT_HARD,SHIP_BANK_LEFT_SOFT,SHIP_SPRITE
    DW SHIP_BANK_RIGHT_SOFT,SHIP_BANK_RIGHT_HARD

SHIP_BANK_LEFT_HARD:
    DB %00110000
    DB %01111000
    DB %11111100
    DB %11111110
    DB %01111100
    DB %00110100
    DB %00011000
    DB %00010000

SHIP_BANK_LEFT_SOFT:
    DB %00011000
    DB %00111100
    DB %01111110
    DB %11111110
    DB %01111110
    DB %00101100
    DB %00011000
    DB %00010000

SHIP_SPRITE:
    DB %00011000
    DB %00111100
    DB %00111100
    DB %01111110
    DB %11111111
    DB %11011011
    DB %00011000
    DB %00011000

SHIP_BANK_RIGHT_SOFT:
    DB %00011000
    DB %00111100
    DB %01111110
    DB %01111111
    DB %01111110
    DB %00110100
    DB %00011000
    DB %00001000

SHIP_BANK_RIGHT_HARD:
    DB %00001100
    DB %00011110
    DB %00111111
    DB %01111111
    DB %00111110
    DB %00101100
    DB %00011000
    DB %00001000

SHIP_ATTR:
    DB #46                      ; bright yellow on black
SHIP_CUR_POS:
    DB 15,22                   ; last painted position
SHIP_NEW_POS:
    DB 15,22                   ; logical target
SHIP_BANK:
    DB 2                         ; 0..4, neutral = 2
SHIP_BANK_TARGET:
    DB 2                         ; desired pose from O/P
SHIP_BANK_TIMER:
    DB 0                         ; frames until next pose update
SHIP_BANK_HOLD_TIMER:
    DB 0                         ; pause before leveling after key release
SHIP_DRAWN:
    DB 0
SHIP_VISIBLE:
    DB 1                       ; 0 during ship explosion

GAME_STATE:
    DB STATE_MENU               ; menu / playing / exploding / respawn / over

SHIP_LIVES:
    DB START_LIVES              ; 4 initially; collisions only decrease
SHIP_MOVE_TIMER:
    DB 0                        ; frames until next horizontal step

; Four independent falling objects. On EVERY spawn, X is
; freshly selected in the full corridor using an 8-bit LFSR.
; The initial table stores only TYPE, START_Y, ANIMATION_PHASE.
ENEMY_START_TABLE:
    DB 0,4,1                    ; small 8x8
    DB 1,11,2                   ; large 16x16
    DB 0,17,3                   ; small 8x8

ENEMY_MOVE_TIMER:
    DB 4
ENEMY_MOVE_NOW:
    DB 0

ENEMY_RANDOM_STATE:
    DB #A7                      ; reseeded by LD A,R during startup
ENEMY_TEST_X:
    DB 0                        ; temporary spawn-overlap data
ENEMY_TEST_TYPE:
    DB 0
ENEMY_TEST_Y:
    DB 0

ENEMY_POOL:
    DS MAX_ENEMIES*ENEMY_SLOT_SIZE,0

ENEMY_ATTR_SMALL:
    DB #42                      ; bright red
ENEMY_ATTR_LARGE:
    DB #45,#45                  ; bright cyan

ENEMY_FRAMES:
    ; 4 rotation frames per type, each 90 degrees clockwise.
    DW ENEMY_SMALL_0,ENEMY_SMALL_1,ENEMY_SMALL_2,ENEMY_SMALL_3
    DW ENEMY_LARGE_0,ENEMY_LARGE_1,ENEMY_LARGE_2,ENEMY_LARGE_3

; Small 8x8: 8 bytes/frame. Large 16x16: 32 bytes/frame.
; No masking or backdrop saving; sprites draw opaque.
ENEMY_SMALL_0:
    DB %00011100
    DB %00111110
    DB %11111111
    DB %11110111
    DB %11111110
    DB %00111111
    DB %00001110
    DB %00000100

ENEMY_SMALL_1:
    DB %00011100
    DB %00011100
    DB %00111110
    DB %00111111
    DB %01110111
    DB %11111111
    DB %01111110
    DB %00101100

ENEMY_SMALL_2:
    DB %00100000
    DB %01110000
    DB %11111100
    DB %01111111
    DB %11101111
    DB %11111111
    DB %01111100
    DB %00111000

ENEMY_SMALL_3:
    DB %00110100
    DB %01111110
    DB %11111111
    DB %11101110
    DB %11111100
    DB %01111100
    DB %00111000
    DB %00111000

ENEMY_LARGE_0:
    DB #01,#E0
    DB #07,#F8
    DB #1F,#FC
    DB #3F,#FE
    DB #3F,#FF
    DB #7F,#FF
    DB #FB,#FF
    DB #FF,#FE
    DB #FF,#FF
    DB #FF,#FC
    DB #7F,#F8
    DB #77,#F8
    DB #3F,#FC
    DB #1F,#F0
    DB #07,#C0
    DB #03,#80

ENEMY_LARGE_1:
    DB #03,#C0
    DB #0F,#E0
    DB #1F,#F8
    DB #3F,#FC
    DB #37,#FC
    DB #7F,#BE
    DB #FF,#FE
    DB #FF,#FF
    DB #FF,#FF
    DB #7F,#FF
    DB #3F,#FF
    DB #3F,#FE
    DB #1F,#FE
    DB #13,#FC
    DB #01,#F8
    DB #01,#70

ENEMY_LARGE_2:
    DB #01,#C0
    DB #03,#E0
    DB #0F,#F8
    DB #3F,#FC
    DB #1F,#EE
    DB #1F,#FE
    DB #3F,#FF
    DB #FF,#FF
    DB #7F,#FF
    DB #FF,#DF
    DB #FF,#FE
    DB #FF,#FC
    DB #7F,#FC
    DB #3F,#F8
    DB #1F,#E0
    DB #07,#80

ENEMY_LARGE_3:
    DB #0E,#80
    DB #1F,#80
    DB #3F,#C8
    DB #7F,#F8
    DB #7F,#FC
    DB #FF,#FC
    DB #FF,#FE
    DB #FF,#FF
    DB #FF,#FF
    DB #7F,#FF
    DB #7D,#FE
    DB #3F,#EC
    DB #3F,#FC
    DB #1F,#F8
    DB #07,#F0
    DB #03,#C0

BULLET_COUNT:
    DB 0                        ; active bullets (0..6)
; All state/last-screen-position/background are stored in each slot.
BULLET_POOL:
    DS MAX_BULLETS*BULLET_SLOT_SIZE,0
BULLET_SPRITE:
    DB %00011000
    DB %00011000
    DB %00111100
    DB %00111100
    DB %00111100
    DB %00111100
    DB %00011000
    DB %00011000
BULLET_ATTR:
    DB #47                     ; bright white on black

BLAST_ACTIVE:
    DB 0
BLAST_DRAWN:
    DB 0
BLAST_OWNER:
    DB 0                       ; 0 asteroid, 1 ship
BLAST_TYPE:
    DB 0                        ; 0=8x8 for small, 1=16x8 for large
BLAST_FRAME:
    DB 0
BLAST_ANIM_TIMER:
    DB BLAST_FRAME_DURATION
BLAST_POS:
    DB 0,0                      ; original asteroid X/Y, NO offset
BLAST_FRAME_PTR:
    DW BLAST_FRAME_0
BLAST_ATTR_SMALL:
    DB #07
BLAST_ATTR:
    DB #07,#07
BLAST_SMALL_FRAMES:
    DW BLAST_SMALL_0,BLAST_SMALL_1,BLAST_SMALL_2,BLAST_SMALL_3

BLAST_SMALL_0:
    DB %00000000
    DB %00000000
    DB %00011000
    DB %00111100
    DB %00111100
    DB %00011000
    DB %00000000
    DB %00000000
BLAST_SMALL_1:
    DB %00000000
    DB %01011010
    DB %00111100
    DB %01111110
    DB %01111110
    DB %00111100
    DB %01011010
    DB %00000000
BLAST_SMALL_2:
    DB %10000001
    DB %00100100
    DB %00011000
    DB %01000010
    DB %01000010
    DB %00011000
    DB %00100100
    DB %10000001
BLAST_SMALL_3:
    DB %00000000
    DB %01000010
    DB %00000000
    DB %00010000
    DB %00001000
    DB %00000000
    DB %01000010
    DB %00000000

BLAST_FRAMES:
    DW BLAST_FRAME_0,BLAST_FRAME_1,BLAST_FRAME_2,BLAST_FRAME_3

BLAST_FRAME_0:
    DB $00,$00
    DB $00,$00
    DB $01,$80
    DB $03,$C0
    DB $03,$C0
    DB $01,$80
    DB $00,$00
    DB $00,$00
BLAST_FRAME_1:
    DB $01,$80
    DB $08,$10
    DB $05,$A0
    DB $43,$C2
    DB $43,$C2
    DB $05,$A0
    DB $08,$10
    DB $01,$80
BLAST_FRAME_2:
    DB $80,$01
    DB $10,$08
    DB $20,$04
    DB $01,$00
    DB $00,$80
    DB $20,$04
    DB $10,$08
    DB $80,$01
BLAST_FRAME_3:
    DB $00,$00
    DB $40,$04
    DB $01,$00
    DB $00,$00
    DB $00,$80
    DB $00,$00
    DB $20,$01
    DB $00,$00

; Six expressive ship-debris frames, each 8x8.
; Yellow ignition, red fireball, white shrapnel.
SHIP_BLAST_ATTRS:
    DB #46,#46,#42,#42,#47,#47
SHIP_BLAST_FRAME_PTRS:
    DW SHIP_BLAST_0,SHIP_BLAST_1,SHIP_BLAST_2
    DW SHIP_BLAST_3,SHIP_BLAST_4,SHIP_BLAST_5

SHIP_BLAST_0:
    DB %00011000
    DB %00111100
    DB %01111110
    DB %11011011
    DB %11111111
    DB %01111110
    DB %00100100
    DB %01000010
SHIP_BLAST_1:
    DB %10011001
    DB %01111110
    DB %11111111
    DB %11111111
    DB %11111111
    DB %11111111
    DB %01111110
    DB %10011001
SHIP_BLAST_2:
    DB %10100101
    DB %01111110
    DB %11111111
    DB %11100111
    DB %11100111
    DB %11111111
    DB %01111110
    DB %10100101
SHIP_BLAST_3:
    DB %10011001
    DB %01000010
    DB %00111100
    DB %10100101
    DB %10100101
    DB %00111100
    DB %01000010
    DB %10011001
SHIP_BLAST_4:
    DB %10000001
    DB %00100100
    DB %01000010
    DB %00011000
    DB %00011000
    DB %01000010
    DB %00100100
    DB %10000001
SHIP_BLAST_5:
    DB %00000000
    DB %01000010
    DB %00000000
    DB %00100100
    DB %00000000
    DB %01000010
    DB %00000000
    DB %00000000

; Dirty flags for explosion and player.
; Bullet dirty state is inside each bullet slot.
BLAST_DIRTY:     DB 0
SHIP_DIRTY:      DB 1

; -------------------------------------------------------------
; Moving starfield: 16 points, two slow motion rates.
; Each record: X cell, Y pixel (32..191), pixel bit, period mask.
; -------------------------------------------------------------
STAR_CLOCK:    DB 0
DIRTY_COUNT:   DB 0
DIRTY_TAIL:    DW DIRTY_QUEUE
DIRTY_MAP:     DS 768,0
DIRTY_QUEUE:   DS 320,0          ; 160 unique character cells

STAR_POOL:
    ; Mid layer: SCROLL_SPEED pixels every two frames.
    DB 8,73,#10,1
    DB 10,150,#01,1
    DB 12,43,#02,1
    DB 14,170,#08,1
    DB 16,84,#20,1
    DB 18,37,#04,1
    DB 20,114,#40,1
    DB 22,141,#02,1
    ; Far layer: SCROLL_SPEED pixels every four frames.
    DB 9,178,#80,3
    DB 11,38,#08,3
    DB 13,128,#10,3
    DB 15,66,#01,3
    DB 17,152,#20,3
    DB 19,98,#04,3
    DB 21,52,#40,3
    DB 23,186,#02,3
; -------------------------------------------------------------
; Input and HUD state.
; -------------------------------------------------------------
SCROLL_SPEED:      DB 1        ; auto 1..3, multiplier for star/asteroid speed
SCORE:             DW 0        ; 0..65535, saturating 16-bit total
SCORE_TIER:        DB 0        ; SCORE / 1024 at last bonus
HUD_DIRTY:         DB 1        ; numeric labels need redraw
SPACE_HELD:        DB 0

HUD_LABEL_TITLE:  DB "SPACECAN: SPACE SODA",0
HUD_LABEL_SPEED:  DB "SPEED",0
HUD_LABEL_SCORE:  DB "SCORE",0
HUD_LABEL_LIVES:  DB "LIVES",0

CAN_LABEL_LEFT:   DB "SPA",0
CAN_LABEL_RIGHT:  DB "CAN",0
CAN_LABEL_VOLUME: DB "0.33",0

PROGRAM_END:

; ===== artwork.asm =====
; SpaceCan Step 07 - native ZX Spectrum 256x192 background.
; RLE stream expands to 6144 bitmap + 768 attribute bytes at #4000.
; Escape: 00,count,byte = repeat; all nonzero bytes are literals.
; 8x8 cells use valid ZX INK/PAPER/BRIGHT, with checker half-tones.
; Source: AI concept adapted to Spectrum geometry; central X=8..23 black.
SPACE_CAN_SCREEN_RLE:
    DB #CC,#CC,#CC,#80,#00,#19,#00,#CC,#CC,#CC,#00,#20,#FF,#00,#0A,#00
    DB #80,#00,#0B,#00,#80,#00,#13,#00,#80,#00,#0B,#00,#80,#00,#10,#00
    DB #01,#00,#10,#00,#80,#00,#07,#00,#3D,#F7,#DF,#79,#E7,#9D,#97,#FF
    DB #00,#10,#00,#FF,#F5,#1D,#F7,#9E,#7B,#EF,#BC,#3D,#F6,#84,#79,#E7
    DB #31,#80,#01,#00,#10,#00,#80,#00,#01,#00,#4C,#F7,#9E,#21,#6F,#BC
    DB #3D,#F5,#D0,#E9,#E7,#3F,#16,#EF,#00,#10,#00,#F9,#ED,#FE,#F7,#97
    DB #03,#AF,#BC,#CC,#CC,#CC,#80,#00,#19,#00,#CC,#CC,#CC,#00,#2A,#00
    DB #80,#00,#0B,#00,#80,#00,#13,#00,#80,#00,#0B,#00,#80,#00,#29,#00
    DB #3C,#F7,#DF,#79,#EF,#B9,#BF,#FE,#00,#10,#00,#2F,#A9,#BD,#E7,#9E
    DB #FB,#EF,#BC,#3C,#F6,#86,#39,#E7,#30,#3F,#FE,#00,#10,#00,#3F,#FC
    DB #0C,#F7,#9C,#61,#6F,#BC,#3D,#F0,#83,#E9,#E7,#39,#52,#26,#00,#10
    DB #00,#71,#CD,#FE,#F7,#97,#C9,#0F,#BC,#33,#33,#33,#00,#19,#00,#01
    DB #33,#33,#33,#00,#0A,#00,#80,#00,#0B,#00,#80,#00,#13,#00,#80,#00
    DB #0B,#00,#80,#00,#13,#00,#80,#00,#0B,#00,#80,#00,#0A,#00,#40,#00
    DB #01,#00,#51,#44,#04,#00,#14,#00,#10,#45,#14,#41,#45,#04,#3D,#F7
    DB #DF,#79,#E7,#90,#00,#14,#00,#0D,#F7,#9E,#7B,#EF,#BC,#3D,#F6,#87
    DB #99,#E7,#71,#FF,#FE,#00,#10,#00,#7F,#FF,#8E,#F7,#99,#E1,#6F,#BC
    DB #3D,#F1,#C3,#C9,#E7,#73,#11,#3E,#00,#10,#00,#75,#EE,#9E,#F7,#93
    DB #C3,#8F,#BC,#33,#33,#33,#00,#19,#00,#01,#33,#33,#33,#00,#0A,#00
    DB #80,#00,#0B,#00,#80,#00,#13,#00,#80,#00,#0B,#00,#80,#00,#13,#00
    DB #80,#00,#0B,#00,#80,#00,#09,#00,#3D,#F7,#DF,#79,#EF,#BE,#0F,#FE
    DB #00,#10,#00,#7F,#F0,#7D,#F7,#9E,#FB,#EF,#BC,#3D,#F7,#DE,#79,#EF
    DB #B1,#03,#80,#00,#10,#00,#23,#E0,#8D,#F7,#9E,#FB,#EF,#BC,#3C,#F6
    DB #87,#C9,#EF,#67,#FF,#F6,#00,#10,#00,#7F,#FF,#E6,#F7,#93,#E1,#6F
    DB #BC,#3D,#E7,#E1,#99,#EF,#33,#2D,#FE,#00,#10,#00,#75,#E8,#9E,#F7
    DB #99,#8F,#EF,#BC,#CC,#CC,#CC,#80,#00,#19,#00,#CC,#CC,#CC,#00,#0A
    DB #00,#80,#00,#0B,#00,#80,#00,#13,#00,#80,#00,#0B,#00,#80,#00,#13
    DB #00,#80,#00,#0B,#00,#80,#00,#09,#00,#3D,#F7,#DF,#79,#E7,#9C,#7E
    DB #01,#00,#10,#00,#80,#7E,#3D,#F7,#9E,#7B,#EF,#3C,#3D,#F7,#03,#79
    DB #E7,#83,#17,#81,#00,#10,#00,#83,#C0,#41,#F7,#9E,#40,#EF,#BC,#3D
    DB #F6,#97,#E9,#E7,#1F,#FF,#A7,#00,#10,#00,#FF,#FF,#F8,#F7,#97,#E1
    DB #6F,#BC,#3D,#E7,#F0,#39,#E7,#39,#6F,#DF,#00,#10,#00,#F5,#4F,#FE
    DB #F7,#9C,#0F,#E7,#BC,#CC,#CC,#CC,#80,#00,#19,#00,#CC,#CC,#CC,#00
    DB #0A,#00,#80,#00,#0B,#00,#80,#00,#13,#00,#80,#00,#0B,#00,#80,#00
    DB #13,#00,#80,#00,#0B,#00,#80,#00,#09,#00,#3C,#F7,#DF,#79,#EF,#B8
    DB #F0,#E0,#00,#10,#00,#03,#8F,#3D,#F7,#9E,#FB,#EF,#BC,#3D,#F7,#3B
    DB #79,#EF,#86,#2F,#80,#00,#10,#00,#2B,#EA,#61,#F7,#9E,#DE,#EF,#BC
    DB #3D,#F6,#87,#E9,#EF,#3F,#FF,#2E,#00,#10,#00,#7F,#FF,#FC,#F7,#97
    DB #E9,#6F,#BC,#3C,#CF,#FA,#79,#EF,#3D,#7D,#8E,#00,#10,#00,#71,#FF
    DB #FE,#F7,#9E,#1F,#F3,#BC,#33,#33,#33,#00,#19,#00,#01,#33,#33,#33
    DB #00,#0A,#00,#80,#00,#0B,#00,#80,#00,#13,#00,#80,#00,#0B,#00,#80
    DB #00,#09,#00,#00,#20,#FF,#3D,#F7,#DF,#79,#E7,#9D,#87,#FE,#00,#10
    DB #00,#7F,#F1,#9D,#F7,#9E,#7B,#EF,#BC,#3D,#F6,#7D,#79,#E7,#8C,#0F
    DB #80,#00,#10,#00,#05,#F0,#31,#F7,#9E,#1E,#6F,#BC,#3D,#F4,#87,#E9
    DB #E7,#3F,#F2,#66,#00,#10,#00,#7F,#C8,#7C,#F7,#97,#E1,#2F,#BC,#3D
    DB #CF,#F8,#79,#E7,#79,#F8,#AE,#00,#10,#00,#73,#FC,#1E,#F7,#9E,#1F
    DB #F3,#BC,#00,#2A,#00,#80,#00,#0B,#00,#80,#00,#13,#00,#80,#00,#0B
    DB #00,#80,#00,#29,#00,#3C,#F7,#DF,#79,#EF,#B9,#9F,#FE,#00,#10,#00
    DB #7F,#F8,#9D,#F7,#9E,#FB,#EF,#BC,#3C,#F6,#CC,#79,#EF,#99,#7F,#00
    DB #11,#00,#2B,#FA,#99,#F7,#9E,#33,#6F,#BC,#3C,#F4,#87,#69,#EF,#3F
    DB #B2,#EE,#00,#10,#00,#7F,#CE,#FE,#F7,#97,#E9,#2F,#BC,#3C,#DF,#EC
    DB #79,#EF,#33,#CA,#8E,#00,#10,#00,#7F,#E0,#FE,#F7,#9E,#3F,#FB,#BC
    DB #3D,#9F,#FC,#79,#E7,#3E,#AA,#8F,#00,#10,#00,#FF,#87,#FE,#F7,#9E
    DB #3F,#F9,#BC,#3D,#1F,#F6,#79,#E7,#3F,#8F,#FF,#00,#10,#00,#FC,#EF
    DB #FE,#F7,#9E,#7F,#F0,#BC,#3C,#F7,#DF,#F9,#E7,#20,#7F,#FD,#00,#10
    DB #00,#80,#00,#01,#00,#10,#F7,#9E,#FB,#EF,#3C,#3D,#D3,#9E,#79,#E7
    DB #23,#C0,#1D,#00,#10,#00,#81,#FF,#0C,#F7,#9E,#59,#47,#BC,#33,#00
    DB #02,#00,#06,#E7,#21,#F0,#3F,#00,#10,#00,#E0,#33,#B6,#F7,#60,#00
    DB #02,#00,#CC,#33,#01,#00,#01,#00,#36,#67,#27,#EF,#9F,#00,#10,#00
    DB #B0,#7F,#26,#F7,#60,#20,#17,#CC,#33,#5F,#F0,#26,#E7,#2F,#98,#3F
    DB #00,#10,#00,#9C,#07,#DC,#F7,#69,#EE,#04,#CC,#33,#7F,#00,#01,#00
    DB #86,#E7,#20,#FC,#0F,#00,#10,#00,#FF,#0F,#FE,#F7,#67,#E0,#10,#CC
    DB #3C,#B0,#06,#79,#E7,#3C,#AA,#AE,#00,#10,#00,#7E,#3F,#FE,#F7,#9E
    DB #60,#0D,#BC,#3C,#1F,#FE,#79,#E7,#3E,#3F,#FE,#00,#10,#00,#78,#FF
    DB #FC,#F7,#9E,#5F,#E8,#BC,#3D,#F7,#DF,#79,#EF,#20,#07,#FE,#00,#12
    DB #00,#20,#F7,#9E,#FB,#FF,#BC,#38,#00,#03,#00,#E7,#21,#80,#FE,#00
    DB #10,#00,#03,#FC,#00,#01,#00,#F7,#00,#03,#00,#1C,#33,#0C,#00,#01
    DB #00,#06,#EF,#27,#C0,#78,#00,#11,#00,#3B,#F0,#F7,#61,#80,#00,#01
    DB #00,#CC,#33,#02,#00,#01,#00,#B6,#EF,#2F,#BB,#9E,#00,#10,#00,#30
    DB #FF,#0E,#F7,#60,#40,#56,#CC,#33,#7B,#40,#66,#EF,#27,#B0,#7E,#00
    DB #10,#00,#08,#1F,#BE,#F7,#6F,#70,#0C,#CC,#33,#3C,#01,#C6,#EF,#21
    DB #F0,#FE,#00,#10,#00,#7C,#3F,#FC,#F7,#63,#80,#18,#CC,#3C,#BF,#FE
    DB #79,#E7,#39,#A9,#FE,#00,#10,#00,#7C,#FF,#FE,#F7,#9E,#7F,#FD,#BC
    DB #3D,#27,#E9,#79,#E7,#3C,#FF,#FC,#00,#10,#00,#70,#05,#FC,#F7,#9E
    DB #AF,#E8,#BC,#3D,#F7,#DF,#79,#E7,#20,#01,#FC,#00,#12,#00,#30,#F7
    DB #9F,#79,#EF,#BC,#30,#00,#03,#00,#E7,#21,#81,#FE,#00,#10,#00,#0F
    DB #E0,#00,#01,#00,#F7,#00,#03,#00,#0C,#33,#0E,#00,#01,#00,#06,#E7
    DB #07,#80,#F8,#00,#10,#00,#06,#7B,#F6,#F7,#61,#C0,#00,#01,#00,#CC
    DB #33,#04,#17,#B6,#E7,#2F,#BB,#FC,#00,#10,#00,#30,#CF,#1E,#F7,#60
    DB #83,#D6,#CC,#33,#30,#01,#C6,#E7,#27,#81,#FE,#00,#11,#00,#3F,#7C
    DB #F7,#66,#40,#38,#CC,#33,#00,#02,#00,#C6,#E7,#23,#E0,#1E,#00,#10
    DB #00,#78,#07,#FC,#F7,#60,#00,#01,#00,#18,#CC,#3C,#9F,#FC,#79,#EF
    DB #38,#AB,#FE,#00,#10,#00,#7B,#FF,#FE,#F7,#9E,#3F,#F9,#BC,#3D,#5A
    DB #AA,#F9,#EF,#39,#FF,#FE,#00,#10,#00,#60,#BF,#FE,#F7,#9F,#25,#F6
    DB #BC,#3C,#F3,#DF,#79,#EF,#20,#80,#FE,#00,#12,#00,#30,#F7,#9E,#7B
    DB #EF,#BC,#3B,#FF,#FF,#FE,#EF,#20,#87,#F8,#00,#10,#00,#1F,#C0,#36
    DB #F7,#7F,#FF,#FF,#CC,#3B,#0C,#01,#E6,#EF,#6F,#06,#DE,#00,#10,#00
    DB #0E,#7B,#F6,#F7,#60,#80,#7E,#CC,#3B,#00,#01,#00,#3D,#F6,#EF,#1D
    DB #FF,#F8,#00,#10,#00,#30,#CC,#3E,#F7,#60,#0E,#BF,#CC,#3B,#70,#03
    DB #06,#EF,#2F,#83,#F8,#00,#11,#00,#FC,#FE,#F7,#6E,#00,#01,#00,#E0
    DB #CC,#3B,#00,#02,#00,#86,#EF,#27,#C0,#FE,#00,#10,#00,#60,#BF,#9E
    DB #F7,#60,#00,#02,#00,#CC,#3D,#83,#E0,#79,#E7,#3C,#8F,#C7,#00,#10
    DB #00,#FF,#FE,#00,#01,#00,#F7,#9E,#07,#C1,#BC,#3D,#5B,#D6,#B9,#E7
    DB #3F,#FF,#FF,#00,#10,#00,#80,#3F,#FC,#F7,#9F,#57,#F6,#BC,#3C,#F3
    DB #DF,#79,#E7,#21,#80,#3D,#00,#10,#00,#80,#00,#02,#00,#F7,#9E,#79
    DB #EF,#BC,#33,#FF,#FF,#FE,#E7,#20,#1F,#E1,#00,#10,#00,#BF,#00,#01
    DB #00,#34,#F7,#7F,#FF,#FF,#CC,#33,#00,#01,#00,#0F,#B6,#E7,#3C,#04
    DB #DF,#00,#10,#00,#8E,#7B,#70,#F7,#60,#03,#E6,#CC,#33,#00,#01,#00
    DB #75,#F6,#E7,#79,#FF,#E1,#00,#10,#00,#B0,#C0,#7C,#F7,#60,#0A,#BD
    DB #CC,#33,#40,#0E,#06,#67,#3E,#07,#F1,#00,#10,#00,#83,#F8,#FC,#F7
    DB #68,#01,#C0,#CC,#33,#00,#02,#00,#06,#E7,#2F,#00,#01,#00,#5F,#00
    DB #10,#00,#C0,#BE,#1C,#F7,#60,#00,#02,#00,#CC,#3D,#BF,#FA,#79,#EF
    DB #3E,#FE,#1E,#00,#10,#00,#7F,#F0,#BC,#F7,#9E,#7F,#FF,#BC,#3C,#28
    DB #2A,#79,#EF,#3F,#FF,#FE,#00,#11,#00,#07,#FC,#F7,#9E,#8A,#8B,#BC
    DB #3C,#F3,#DF,#79,#E7,#21,#80,#1E,#00,#11,#00,#07,#F8,#F7,#9E,#7B
    DB #EF,#BC,#3B,#FF,#FF,#FE,#E7,#20,#3F,#80,#00,#10,#00,#7C,#01,#30
    DB #F7,#7F,#FF,#FF,#CC,#3B,#00,#01,#00,#3C,#06,#E7,#3C,#0F,#9E,#00
    DB #10,#00,#1E,#7B,#76,#F7,#60,#07,#80,#CC,#33,#0B,#9D,#E6,#EF,#39
    DB #FF,#40,#00,#10,#00,#3B,#C0,#FC,#F7,#61,#EB,#A8,#CC,#33,#00,#01
    DB #00,#38,#06,#EF,#3C,#1F,#C4,#00,#10,#00,#07,#F0,#FC,#F7,#60,#0F
    DB #80,#CC,#3B,#00,#02,#00,#06,#EF,#3E,#00,#01,#00,#0C,#00,#11,#00
    DB #0C,#7E,#F7,#60,#00,#02,#00,#CC,#3D,#D7,#FC,#79,#E7,#38,#F0,#7E
    DB #00,#10,#00,#7F,#C3,#FC,#F7,#9E,#5F,#FD,#BC,#3D,#5B,#2A,#79,#E7
    DB #3F,#FF,#FE,#00,#11,#00,#FF,#FE,#F7,#9F,#65,#54,#BC,#3D,#F7,#DF
    DB #79,#E7,#61,#80,#04,#00,#11,#00,#1F,#FC,#F7,#9E,#79,#EF,#BC,#33
    DB #00,#02,#00,#06,#E7,#20,#7E,#06,#00,#10,#00,#7C,#03,#B4,#F7,#60
    DB #00,#02,#00,#CC,#33,#00,#01,#00,#70,#06,#E7,#70,#6F,#98,#00,#10
    DB #00,#18,#5B,#70,#F7,#60,#0C,#00,#01,#00,#CC,#33,#3F,#17,#06,#E7
    DB #1D,#9B,#06,#00,#10,#00,#3F,#C1,#F4,#F7,#67,#F2,#C0,#CC,#33,#01
    DB #F0,#06,#E7,#38,#3F,#82,#00,#10,#00,#0F,#C0,#FC,#F7,#64,#3E,#00
    DB #01,#00,#CC,#33,#00,#02,#00,#06,#E7,#3C,#00,#01,#00,#FE,#00,#11
    DB #00,#38,#FC,#F7,#60,#00,#02,#00,#CC,#3C,#EF,#FA,#79,#EF,#39,#E3
    DB #FE,#00,#10,#00,#7F,#0D,#7C,#F7,#9E,#7F,#FB,#BC,#3D,#18,#50,#B9
    DB #EF,#3F,#FF,#FC,#00,#11,#00,#BF,#FC,#F7,#9F,#4A,#90,#BC,#3C,#F3
    DB #DF,#79,#EF,#27,#E0,#02,#00,#11,#00,#7F,#FE,#F7,#9E,#7B,#EF,#BC
    DB #3B,#00,#02,#00,#06,#EF,#20,#F8,#0E,#00,#10,#00,#70,#33,#B4,#F7
    DB #60,#00,#02,#00,#CC,#3B,#00,#01,#00,#C0,#06,#EF,#31,#EF,#98,#00
    DB #10,#00,#38,#FB,#36,#F7,#60,#18,#00,#01,#00,#CC,#3B,#7F,#98,#06
    DB #EF,#7F,#98,#0E,#00,#10,#00,#1E,#03,#EE,#F7,#6D,#FB,#00,#01,#00
    DB #CC,#3B,#67,#E0,#06,#EF,#20,#7E,#04,#00,#10,#00,#3F,#80,#FC,#F7
    DB #66,#F8,#00,#01,#00,#CC,#3B,#FF,#FF,#FE,#EF,#38,#00,#01,#00,#26
    DB #00,#11,#00,#01,#EC,#F7,#7F,#FF,#FF,#CC,#33,#FF,#FF,#FE,#E7,#30
    DB #00,#01,#00,#FF,#00,#10,#00,#86,#03,#7E,#F7,#7F,#FF,#FF,#CC,#3D
    DB #F7,#DF,#79,#E7,#60,#FF,#35,#00,#10,#00,#81,#BB,#7C,#F7,#9E,#79
    DB #EF,#BC,#00,#05,#00,#2F,#3F,#05,#00,#10,#00,#81,#F3,#5C,#00,#0A
    DB #00,#27,#87,#E1,#00,#10,#00,#8B,#02,#7C,#00,#05,#00,#32,#00,#02
    DB #00,#02,#64,#07,#8F,#5F,#00,#10,#00,#80,#AB,#BE,#17,#40,#00,#02
    DB #00,#4C,#32,#41,#0A,#12,#64,#25,#7F,#FF,#00,#10,#00,#AA,#FF,#FC
    DB #17,#44,#00,#01,#00,#10,#4C,#32,#00,#02,#00,#02,#64,#2F,#FF,#FF
    DB #00,#10,#00,#BF,#FF,#FC,#17,#41,#00,#02,#00,#4C,#1F,#00,#01,#00
    DB #7F,#C0,#FF,#F3,#07,#E1,#00,#10,#00,#86,#D0,#4F,#FD,#01,#FF,#00
    DB #01,#00,#F4,#3B,#FF,#FF,#FE,#EF,#20,#00,#01,#00,#8E,#00,#10,#00
    DB #06,#06,#6C,#F7,#7F,#FF,#FF,#CC,#3C,#F3,#DF,#79,#EF,#21,#FE,#7E
    DB #00,#10,#00,#03,#BE,#3C,#F7,#9E,#7B,#EF,#BC,#00,#05,#00,#20,#7E
    DB #08,#00,#10,#00,#03,#F2,#7C,#00,#05,#00,#2A,#BA,#AF,#AB,#3B,#23
    DB #0F,#CC,#00,#10,#00,#1E,#0F,#FE,#AA,#EB,#AA,#BB,#AC,#32,#6A,#AA
    DB #82,#EC,#2F,#8B,#FC,#00,#11,#00,#AA,#FC,#97,#4A,#29,#A4,#4C,#32
    DB #62,#85,#22,#EC,#20,#3F,#FE,#00,#11,#00,#7F,#FE,#B7,#4A,#2A,#22
    DB #4C,#32,#00,#02,#00,#02,#EC,#0F,#FF,#FC,#00,#10,#00,#2F,#FF,#F8
    DB #97,#4A,#00,#02,#00,#4C,#2E,#05,#FF,#F0,#FE,#FB,#3F,#FE,#00,#10
    DB #00,#7F,#F8,#CB,#FB,#2F,#FF,#C0,#BE,#38,#00,#03,#00,#E7,#60,#00
    DB #01,#00,#44,#00,#10,#00,#0F,#07,#5C,#F7,#00,#03,#00,#0C,#3D,#F7
    DB #DF,#79,#E7,#23,#FD,#E6,#00,#10,#00,#03,#76,#3C,#F7,#9E,#79,#EF
    DB #BC,#7F,#00,#04,#FF,#20,#3C,#04,#00,#10,#00,#03,#60,#FC,#00,#04
    DB #FF,#FE,#3F,#00,#04,#FF,#23,#1F,#00,#11,#00,#06,#06,#7C,#00,#04
    DB #FF,#FC,#32,#85,#55,#42,#6D,#7F,#10,#5C,#00,#11,#00,#01,#74,#17
    DB #44,#10,#08,#4C,#32,#A0,#00,#01,#00,#52,#65,#60,#7F,#FE,#00,#10
    DB #00,#2B,#7F,#FE,#97,#44,#15,#00,#01,#00,#4C,#32,#00,#02,#00,#02
    DB #E5,#67,#FF,#FE,#00,#10,#00,#1F,#FF,#F6,#97,#4C,#00,#02,#00,#4C
    DB #35,#00,#01,#00,#7F,#E8,#FD,#F9,#1F,#FE,#00,#10,#00,#5F,#FC,#9F
    DB #F5,#03,#FF,#00,#01,#00,#F4,#3C,#F3,#DF,#79,#EF,#20,#00,#01,#00
    DB #FE,#00,#10,#00,#06,#0F,#DE,#F7,#9E,#79,#EF,#BC,#3C,#F7,#DF,#79
    DB #EF,#27,#E7,#CE,#00,#10,#00,#06,#7D,#FE,#F7,#9E,#7B,#EF,#BC,#3F
    DB #00,#04,#FF,#20,#00,#01,#00,#0A,#00,#10,#00,#06,#E0,#FC,#00,#04
    DB #FF,#FC,#38,#00,#03,#00,#E0,#20,#7E,#D4,#00,#10,#00,#0C,#02,#FC
    DB #8F,#00,#03,#00,#0C,#32,#46,#AA,#92,#EC,#3E,#3F,#FE,#00,#10,#00
    DB #02,#AF,#FE,#97,#4A,#28,#24,#4C,#32,#42,#B2,#92,#EC,#2F,#FF,#FE
    DB #00,#10,#00,#2A,#FF,#FC,#37,#4A,#2A,#84,#4C,#32,#00,#02,#00,#02
    DB #EC,#30,#FF,#FE,#00,#10,#00,#3F,#FF,#8E,#97,#4C,#00,#02,#00,#4C
    DB #3F,#06,#FF,#FC,#FF,#81,#BF,#FE,#00,#10,#00,#7F,#FB,#83,#FF,#3F
    DB #FF,#E0,#FC,#3D,#F3,#DF,#79,#E7,#20,#38,#15,#00,#10,#00,#84,#0F
    DB #DC,#F7,#9E,#79,#EF,#BC,#3D,#F7,#DF,#79,#E7,#0D,#9F,#9F,#00,#10
    DB #00,#84,#7D,#BC,#F7,#9E,#79,#EF,#BC,#00,#05,#00,#20,#00,#01,#00
    DB #01,#00,#10,#00,#86,#C0,#FE,#00,#05,#00,#30,#00,#03,#00,#60,#20
    DB #FC,#01,#00,#10,#00,#8C,#02,#7C,#07,#00,#03,#00,#0C,#32,#61,#01
    DB #12,#65,#7C,#01,#77,#00,#10,#00,#80,#0D,#7C,#17,#45,#10,#00,#01
    DB #00,#4C,#32,#00,#02,#00,#22,#65,#60,#7F,#FD,#00,#10,#00,#81,#7F
    DB #FE,#97,#44,#15,#00,#01,#00,#4C,#32,#00,#02,#00,#02,#ED,#38,#3F
    DB #A3,#00,#10,#00,#85,#3C,#3C,#97,#48,#00,#02,#00,#4C,#3F,#00,#01
    DB #00,#3F,#D0,#7A,#80,#DB,#F5,#00,#10,#00,#AB,#FB,#01,#FB,#01,#FF
    DB #00,#01,#00,#AC,#3C,#F3,#DF,#79,#EF,#00,#01,#00,#7E,#0E,#00,#11
    DB #00,#1F,#BC,#F7,#9E,#7B,#EF,#BC,#3C,#F7,#DF,#79,#EF,#2C,#7C,#0C
    DB #00,#11,#00,#8B,#7E,#F7,#9E,#7B,#EF,#BC,#2D,#52,#BA,#A8,#55,#20
    DB #00,#01,#00,#1E,#00,#10,#00,#07,#80,#FC,#AA,#AA,#AA,#EF,#54,#33
    DB #FF,#FF,#FE,#EF,#21,#F8,#00,#11,#00,#08,#00,#01,#00,#7E,#F7,#7F
    DB #FF,#FF,#CC,#32,#20,#90,#92,#EC,#38,#FF,#FE,#00,#10,#00,#0A,#AF
    DB #FE,#97,#4A,#80,#AA,#4C,#32,#2A,#2A,#42,#ED,#2B,#FF,#FE,#00,#10
    DB #00,#2F,#FF,#FE,#B7,#4A,#20,#2A,#4C,#22,#00,#04,#00,#0F,#C0,#00
    DB #12,#00,#03,#F8,#00,#01,#00,#40,#00,#03,#00,#3E,#03,#FF,#F8,#FF
    DB #E8,#00,#14,#00,#17,#EF,#1F,#FF,#E0,#FC,#3D,#F7,#DF,#79,#E7,#20
    DB #FF,#F4,#00,#11,#00,#5F,#BC,#F7,#9E,#79,#EF,#BC,#3D,#F7,#DF,#79
    DB #E7,#1D,#F1,#BE,#00,#10,#00,#01,#C3,#7C,#F7,#9E,#79,#EF,#BC,#7F
    DB #DF,#FA,#AF,#FF,#23,#00,#01,#00,#7E,#00,#10,#00,#0D,#80,#7C,#BA
    DB #BA,#FF,#FD,#D4,#33,#FF,#FF,#FE,#67,#21,#E3,#54,#00,#10,#00,#18
    DB #22,#FC,#F7,#7F,#FF,#FF,#CC,#32,#45,#08,#42,#64,#30,#7F,#FE,#00
    DB #10,#00,#0A,#FF,#FC,#17,#4C,#42,#94,#4C,#32,#50,#15,#12,#64,#6F
    DB #FF,#FE,#00,#10,#00,#2F,#FF,#FC,#17,#48,#0A,#14,#4C,#00,#05,#00
    DB #05,#FF,#FE,#00,#10,#00,#7F,#FF,#A0,#00,#05,#00,#3F,#00,#01,#00
    DB #3F,#C0,#FF,#FE,#00,#14,#00,#7F,#FF,#01,#FE,#00,#01,#00,#FC,#3C
    DB #F7,#DF,#79,#EF,#20,#FF,#F6,#00,#11,#00,#FF,#3E,#F7,#9E,#7B,#EF
    DB #BC,#3D,#F7,#DF,#79,#EF,#1F,#CF,#0E,#00,#10,#00,#01,#F3,#7E,#F7
    DB #9E,#FB,#EF,#BC,#00,#05,#00,#23,#01,#F8,#00,#10,#00,#0B,#02,#FE
    DB #00,#05,#00,#32,#00,#02,#00,#02,#6C,#23,#C0,#00,#11,#00,#10,#00
    DB #01,#00,#FE,#37,#40,#00,#02,#00,#4C,#32,#AA,#95,#A2,#ED,#30,#07
    DB #FC,#00,#11,#00,#1F,#FE,#97,#42,#2D,#4A,#4C,#32,#AA,#2A,#82,#ED
    DB #65,#FF,#FE,#00,#10,#00,#17,#FF,#FE,#97,#44,#95,#AA,#4C,#00,#01
    DB #00,#FF,#FF,#FF,#00,#01,#00,#E6,#C0,#00,#12,#00,#03,#63,#00,#01
    DB #00,#0B,#FF,#FF,#00,#01,#00,#3F,#01,#FF,#F8,#FF,#7F,#AA,#AA,#00
    DB #10,#00,#2A,#BA,#FF,#FF,#0F,#FF,#C0,#FC,#00,#04,#05,#01,#00,#15
    DB #46,#01,#01,#00,#24,#05,#00,#07,#47,#44,#00,#08,#47,#00,#05,#46
    DB #00,#0B,#47,#00,#20,#05,#00,#06,#04,#07,#07,#00,#10,#47,#07,#07
    DB #00,#0C,#04,#07,#27,#00,#10,#47,#07,#07,#00,#08,#04,#06,#04,#04
    DB #06,#06,#06,#00,#10,#47,#06,#06,#06,#04,#04,#06,#00,#04,#04,#06
    DB #04,#04,#06,#06,#06,#00,#10,#47,#06,#06,#06,#04,#04,#06,#04,#04
    DB #04,#06,#06,#04,#04,#46,#06,#06,#00,#10,#47,#06,#06,#06,#04,#04
    DB #06,#06,#04,#04,#26,#26,#04,#04,#46,#46,#06,#00,#10,#47,#06,#00
    DB #04,#04,#26,#26,#00,#06,#04,#07,#06,#06,#00,#11,#47,#26,#26,#00
    DB #06,#04,#06,#06,#06,#04,#07,#06,#06,#00,#10,#47,#06,#06,#07,#04
    DB #06,#06,#06,#04,#04,#07,#06,#06,#04,#06,#07,#07,#00,#10,#47,#07
    DB #07,#07,#04,#06,#06,#06,#04,#04,#07,#07,#06,#04,#07,#07,#07,#00
    DB #10,#47,#07,#07,#06,#04,#06,#07,#07,#04,#04,#07,#06,#06,#04,#07
    DB #06,#06,#00,#10,#47,#06,#26,#04,#04,#06,#06,#06,#04,#04,#06,#06
    DB #06,#04,#06,#06,#04,#00,#10,#47,#06,#04,#04,#04,#06,#06,#06,#00
    DB #06,#04,#06,#06,#04,#00,#10,#47,#07,#07,#00,#0B,#04,#06,#06,#04
    DB #00,#10,#47,#07,#07,#00,#06,#04,#00,#08,#06,#00,#10,#47,#06,#06
    DB #04,#00,#05,#06,#00,#05,#04,#07,#06,#06,#00,#10,#47,#06,#07,#00
    DB #0B,#04,#06,#04,#06,#00,#10,#47,#06,#06,#06,#00,#0A,#04,#06,#06
    DB #06,#00,#10,#47,#06,#26,#06,#00,#06,#04,#02,#06,#06,#04,#06,#06
    DB #06,#00,#10,#47,#06,#06,#06,#04,#04,#06,#02,#04,#02,#16,#16,#16
    DB #02,#02,#07,#07,#00,#10,#47,#07,#07,#02,#02,#16,#16,#16,#02
SPACE_CAN_SCREEN_END:
