; ===== SpaceCan Step 22: demo 2x at 4096, boss at 8192 =====
; SpaceCan Step 22: short demo progression (2x at 4096; boss at 8192).
; ZX Spectrum 48K / Delta-C, sjasmplus syntax.
;
; Object coordinates use 8x8 cells; ship also stores a 4-pixel half-cell offset.
; Cockpit HUD: Y=0..3; playfield: X=8..23, Y=4..23.
; Render after HALT; update logic and moving stars for NEXT frame.

    ORG #9000

; Set 0 to skip AY access; beeper title intro plays in both modes.
AY_MUSIC_ENABLED EQU 1
AY_TARGET_CLOCK EQU 2000000    ; Delta-C AY board, check real oscillator

BLAST_FRAME_DURATION EQU 4
BLAST_FRAME_COUNT    EQU 4
PLAYFIELD_TOP        EQU 4
PLAYFIELD_LEFT       EQU 8
PLAYFIELD_RIGHT      EQU 23
PLAYFIELD_WIDTH      EQU 16
PLAYFIELD_BOTTOM     EQU 23
MAX_SCROLL_SPEED     EQU 3
SPEED_STAGE_COUNT    EQU 5     ; engine supports 1 / 1.5 / 2 / 2.5 / 3

; =============================================================
; DEMO PROGRESSION: EDIT THE TWO SCORE LIMITS HERE.
; 0..4095 = speed 1x; from 4096 = speed 2x; from 8192 = boss.
; SCORE is 24-bit, so both limits can be set as high as 999999.
; The demo skips intermediate 1.5x / 2.5x / 3x stages.
; =============================================================
DEMO_SPEEDUP_SCORE   EQU 4096
DEMO_BOSS_SCORE      EQU 8192
    ASSERT DEMO_SPEEDUP_SCORE >= 0
    ASSERT DEMO_SPEEDUP_SCORE < DEMO_BOSS_SCORE
    ASSERT DEMO_BOSS_SCORE <= 999999

START_LIVES          EQU 4
MISS_SCREEN_ROWS      EQU PLAYFIELD_BOTTOM-PLAYFIELD_TOP+1
MISS_DISTANCE_LIMIT   EQU MISS_SCREEN_ROWS*3 ; 3 full corridor heights without kills
SHOOT_TEXT_X          EQU 13    ; central HUD, below hearts and above gauge
SHOOT_TEXT_Y          EQU 2
SHOOT_TEXT_WIDTH      EQU 6     ; "SHOOT!"
SHOOT_BLINK_MASK      EQU #10   ; 16 video frames on, 16 off
PRESSURE_SEGMENTS     EQU 10    ; 10 penalties fill the gauge and cost a life
GAME_OVER_FRAMES     EQU 50    ; ~1 second after the Game Over melody
SHIP_MOVE_DELAY      EQU 2
SHIP_BANK_DELAY      EQU 5    ; ticks between 8x8 banking poses
SHIP_BANK_HOLD       EQU 14   ; keep tilt after releasing O/P
MAX_BULLETS          EQU 6
BULLET_SLOT_SIZE     EQU 9
MAX_ENEMIES          EQU 4
BOSS_MAX_HP          EQU PRESSURE_SEGMENTS
BOSS_X_CENTER        EQU 14 ; 3 columns 14..16, centered
BOSS_START_Y         EQU PLAYFIELD_TOP
BOSS_TARGET_Y        EQU 12
BOSS_ENTRY_DELAY     EQU 5
BOSS_ANIM_DELAY      EQU 12
BOSS_FIRE_DELAY      EQU 45
MAX_HOSTILE_BULLETS  EQU 6
HOSTILE_BULLET_SIZE  EQU 7
HOSTILE_MOVE_DELAY   EQU 4
ENEMY_SLOT_SIZE      EQU 15
ENEMY_FRAME_DELAY    EQU 8     ; rotate once every 8 ticks
ENEMY_RESPAWN_DELAY  EQU 24
ENEMY_MIN_VERTICAL_GAP EQU 3 ; empty 8px rows between asteroids at spawn
ENEMY_MIN_LANE_GAP EQU 1     ; preferred empty columns between asteroid lanes
SHIP_BLAST_DURATION  EQU 5    ; 6 frames x 5 ticks = 0.6 sec
SHIP_BLAST_FRAMES    EQU 6
STATE_MENU           EQU 0
STATE_PLAYING        EQU 1
STATE_EXPLODING      EQU 2
STATE_RESPAWN        EQU 3
STATE_GAME_OVER      EQU 4
STATE_PAUSED         EQU 5
STATE_BOSS           EQU 6
STATE_VICTORY        EQU 7
PAUSE_TEXT_Y         EQU 12
PAUSE_TEXT_X         EQU 13
PAUSE_TEXT_WIDTH     EQU 6
PAUSE_ATTR_ADDR      EQU #5800 + PAUSE_TEXT_Y*32 + PAUSE_TEXT_X

; One 15-byte enemy slot: state, animation, appearance and drawn position.
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
E_VARIANT      EQU 13          ; silhouette 0..3, chosen on each spawn
E_SHADE        EQU 14          ; palette index 0..7, chosen on spawn

; ===== diagnostics.asm =====
; -------------------------------------------------------------
; Border phase diagnostics for ZX Spectrum 48K.
;
; Set DEBUG_BORDER=0 for a normal game build (no phase code emitted).
; Phase writes must update SFX_FE_BASE before touching port #FE
; so sound pulses preserve border colour and MIC state.
; -------------------------------------------------------------

DEBUG_BORDER EQU 0

DBG_RENDER_COLOUR EQU 2  ; red: sprites/background
DBG_HUD_COLOUR    EQU 6  ; yellow: HUD
DBG_INPUT_COLOUR  EQU 5  ; cyan: keyboard
DBG_LOGIC_COLOUR  EQU 4  ; green: game update
DBG_IDLE_COLOUR   EQU 1  ; blue: remainder of frame / HALT

    MACRO DEBUG_PHASE colour
    IF DEBUG_BORDER
        LD A,colour
        LD (SFX_FE_BASE),A
        OUT (#FE),A
    ENDIF
    ENDM


; Each bullet slot is 9 bytes; current/drawn half-cell offsets differ.
B_ACTIVE    EQU 0  ; 0=free, 1=just spawned, 2=flying
B_X         EQU 1
B_Y         EQU 2
B_DRAWN     EQU 3
B_DRAW_X    EQU 4
B_DRAW_Y    EQU 5
B_DIRTY     EQU 6
B_HALF      EQU 7  ; spawn 4px offset (0=aligned,1=half cell)
B_DRAW_HALF EQU 8  ; 4px offset of last drawn picture

START:
    DI
    LD SP,IM2_STACK_TOP          ; isolated stack below IM2 gate, never overwrite vectors
    LD A,1
    LD (SFX_FE_BASE),A            ; border/MIC shadow for beeper pulses
    OUT (#FE),A
    IF AY_MUSIC_ENABLED
        CALL AY_INIT
    ENDIF
    CALL IM2_INSTALL             ; full 257-byte vector table + #FDFD jump
    EI
    JP SHOW_START_MENU

; New game (from menu or after Game Over):
; only here are score, speed and lives reset.
START_NEW_GAME:
    CALL SFX_STOP                 ; silence any earlier effect
    IF AY_MUSIC_ENABLED
        LD HL,AY_MUSIC_GAME
        CALL AY_PLAY             ; continues across ship respawns
    ENDIF
    XOR A
    LD (SCORE),A
    LD (SCORE+1),A
    LD (SCORE+2),A             ; 24-bit score, up to 999999
    LD (SPEED_LEVEL),A        ; demo: stage 0 (1x), then stage 2 (2x)
    LD (ENEMY_SPEED_PHASE),A
    LD (MISS_TRAVEL_ROWS),A       ; a new game resets travel since last kill
    LD (SHOOT_WARNING_ACTIVE),A
    LD (SHOOT_BLINK_COUNTER),A
    LD (PRESSURE_LEVEL),A        ; start with ten green segments
    LD (BOSS_STARTED),A
    LD (BOSS_ACTIVE),A
    LD A,1
    LD (SCROLL_SPEED),A
    LD A,START_LIVES
    LD (SHIP_LIVES),A
    JP RESTART_ROUND

; Each new ship starts without pressure, preserving score/speed/lives.
RESTART_ROUND:
    ; Keep IM2 enabled while the screen is reconstructed: AY never
    ; touches graphics and must continue across new lives.
    CALL SFX_STOP                 ; each new life starts silent
    ; Pressure is local to ONE life, regardless of how it was lost.
    ; Also reset the partial 3-screen distance on every respawn.
    XOR A
    LD (PRESSURE_LEVEL),A
    LD (MISS_TRAVEL_ROWS),A
    LD (MISS_KILLED_THIS_TICK),A
    LD (SHOOT_WARNING_ACTIVE),A
    LD (SHOOT_BLINK_COUNTER),A
    CALL DRAW_STATIC_UI
    CALL RESET_ROUND_OBJECTS
    CALL RESET_HOSTILE_BULLETS
    LD A,(BOSS_STARTED)
    OR A
    JR Z,.ASTEROID_ROUND
    ; Resume boss after lost life, retaining its remaining HP.
    CALL BOSS_RESET_ENTRY
    JP MAIN_LOOP
.ASTEROID_ROUND:
    XOR A
    LD (BOSS_ACTIVE),A
    LD (BOSS_DRAWN),A
    LD A,STATE_PLAYING
    LD (GAME_STATE),A
    JP MAIN_LOOP

MAIN_LOOP:
    HALT
    LD A,(GAME_STATE)
    CP STATE_RESPAWN
    JP Z,RESTART_ROUND
    CP STATE_GAME_OVER
    JP Z,SHOW_GAME_OVER
    CP STATE_VICTORY
    JP Z,SHOW_VICTORY

    ; Pause scan runs before rendering and game logic. While paused,
    ; only HALT and ENTER are processed, so all animation clocks freeze.
    CALL HANDLE_PAUSE_KEY
    LD A,(GAME_STATE)
    CP STATE_PAUSED
    JR Z,.FRAME_END

    DEBUG_PHASE DBG_RENDER_COLOUR
    CALL RENDER_FRAME
    DEBUG_PHASE DBG_HUD_COLOUR
    CALL RENDER_HUD
    DEBUG_PHASE DBG_INPUT_COLOUR
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    JR Z,.ACTIVE
    CP STATE_BOSS
    JR NZ,.EXPLODING
.ACTIVE:
    CALL READ_INPUT
    DEBUG_PHASE DBG_LOGIC_COLOUR
    CALL UPDATE_GAME
    JR .FRAME_SOUND
.EXPLODING:
    ; The only moving item during this mode is the ship explosion.
    DEBUG_PHASE DBG_LOGIC_COLOUR
    CALL UPDATE_BLAST_ANIM
.FRAME_SOUND:
    ; AY_TICK is IRQ-driven now; only beeper SFX remains here.
    CALL SFX_TICK                  ; bounded short pulse; skip on PAUSED
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

; Demo's terminal encounter won: display a victory card and return.
SHOW_VICTORY:
    LD A,STATE_VICTORY
    LD (GAME_STATE),A
    CALL SFX_STOP
    CALL DRAW_STATIC_UI
    LD A,1
    LD (HUD_DIRTY),A
    CALL RENDER_HUD
    LD A,#46
    LD (MENU_TEXT_ATTR),A
    LD BC,#0B0A
    LD DE,MENU_BOSS_DEFEATED
    CALL MENU_PRINT_TEXT
    LD BC,#0D0C
    LD DE,MENU_YOU_WIN
    CALL MENU_PRINT_TEXT
    IF AY_MUSIC_ENABLED
        LD HL,AY_MUSIC_GAME_OVER
        CALL AY_PLAY
    ELSE
        LD HL,MELODY_GAME_OVER
        CALL MELODY_PLAY
    ENDIF
    EI
    LD B,150
.HOLD:
    HALT
    DJNZ .HOLD
    JP SHOW_START_MENU

MENU_BOSS_DEFEATED: DB "BOSS DEFEATED",0
MENU_YOU_WIN:       DB "YOU WIN!",0

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

    ; AY ending advances in IM2; beeper is the 48K fallback.
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

; ===== sfx.asm =====
; -------------------------------------------------------------
; SpaceCan Step 15.1 — deeper, noise-based ship blast on ZX #FE.
; No AY access here: three AY voices remain free for future music.
;
; SFX_START: A=1..5. Clobbers AF,DE,HL, preserves BC/IX.
; SFX_TICK:  one bounded burst/frame; clobbers AF,BC,DE,HL.
; Ship explosion uses a dedicated irregular pulse routine.
; SFX_STOP:  silence immediately, preserving border (clobbers AF).
; Priority: SHIP > PENALTY > KILL > HIT > SHOT.
; Only called from mainline; beeper pulses are atomic vs IM2.
; Port #FE lower bits: BORDER (0..2), MIC (3), EAR (4).
; -------------------------------------------------------------
SFX_SHOT    EQU 1
SFX_HIT     EQU 2
SFX_KILL    EQU 3
SFX_PENALTY EQU 4
SFX_SHIP    EQU 5

; Start/replace a sound only if it is not lower priority.
SFX_START:
    LD HL,SFX_ACTIVE
    CP (HL)
    RET C
    LD (HL),A
    DEC A
    LD E,A
    ADD A,A
    ADD A,E                       ; three bytes per preset
    LD E,A
    LD D,0
    LD HL,SFX_PRESETS
    ADD HL,DE
    LD A,(HL)
    LD (SFX_FRAMES),A
    INC HL
    LD A,(HL)
    LD (SFX_PERIOD),A
    INC HL
    LD A,(HL)
    LD (SFX_SWEEP),A
    RET

; EAR low, even if stopping during pause, restart or Game Over.
SFX_STOP:
    XOR A
    LD (SFX_ACTIVE),A
    LD (SFX_FRAMES),A
    LD A,(SFX_FE_BASE)
    AND #0F
    OUT (#FE),A
    RET

; One small pulse packet at the end of a game frame.
; Bound: C<=19 => 8 pulses, 20<=C<40 => 4, >=40 => 2.
; At 3.5MHz: <~1.8ms worst case including management overhead.
SFX_TICK:
    LD A,(SFX_ACTIVE)
    OR A
    RET Z
    CP SFX_SHIP
    JP Z,SFX_SHIP_TICK            ; low irregular noise, not tonal sweep

    ; Halfway through penalty effect, restart pitch for second chirp.
    CP SFX_PENALTY
    JR NZ,.PREPARE
    LD A,(SFX_FRAMES)
    CP 4
    JR NZ,.PREPARE
    LD A,12
    LD (SFX_PERIOD),A
.PREPARE:
    LD A,(SFX_PERIOD)
    LD C,A
    LD A,(SFX_ACTIVE)
    CP SFX_KILL
    JR NZ,.SELECT_PULSES
.NOISE:
    ; Low-cost LFSR pitch jitter, only for destructive effects.
    LD A,(SFX_NOISE)
    SRL A
    JR NC,.NO_XOR
    XOR #B8
.NO_XOR:
    LD (SFX_NOISE),A
    AND 7
    ADD A,C
    LD C,A
.SELECT_PULSES:
    LD A,C
    CP 20
    LD B,8
    JR C,.PORT
    LD B,4
    CP 40
    JR C,.PORT
    LD B,2
.PORT:
    DI                             ; prevent IRQ in a HIGH EAR pulse
    LD A,(SFX_FE_BASE)
    AND #0F                       ; keep border and MIC, EAR cleared
    LD D,A
    OR #10
    LD E,A
.PULSE:
    LD A,E
    OUT (#FE),A                    ; high
    LD A,C
.HIGH_WAIT:
    DEC A
    JR NZ,.HIGH_WAIT
    LD A,D
    OUT (#FE),A                    ; low
    LD A,C
.LOW_WAIT:
    DEC A
    JR NZ,.LOW_WAIT
    DJNZ .PULSE                   ; EAR always low between frames
    EI                             ; IRQ may now update AY safely

    LD HL,SFX_FRAMES
    DEC (HL)
    JR Z,.DONE
    LD A,(SFX_PERIOD)
    LD HL,SFX_SWEEP
    ADD A,(HL)
    CP 65
    JR C,.STORE_PERIOD
    LD A,64                        ; cap base period, no 8-bit wrap
.STORE_PERIOD:
    LD (SFX_PERIOD),A
    RET
.DONE:
    XOR A
    LD (SFX_ACTIVE),A
    RET


; -------------------------------------------------------------
; Separate ship explosion: irregular, lower-frequency crackle.
; Unlike short game sounds, high and low half-waves use DIFFERENT
; LFSR delays, so no stable pitch can form. The first four frames
; have a two-pulse crack; then one lower pulse per video frame.
; During the final 10 frames, every second burst is omitted to
; simulate an energy decay (beeper volume itself cannot be changed).
;
; Base period 126..190, random upper half +0..63 / lower +0..31:
; no 8-bit wrap; EAR returns low after every burst. Worst attack
; is around 3.5ms on 3.5MHz Z80, only during the ship explosion.
; -------------------------------------------------------------
SFX_SHIP_TICK:
    LD A,(SFX_FRAMES)
    CP 10
    JR NC,.PLAY
    AND 1
    JR Z,.ADVANCE                ; scattered tail, no audible tone
.PLAY:
    DI                             ; protect noisy ship burst as well
    LD A,(SFX_FE_BASE)
    AND #0F
    LD D,A                       ; EAR off + preserved border/MIC
    OR #10
    LD E,A                       ; EAR on + preserved border/MIC

    LD A,(SFX_FRAMES)
    LD B,1
    CP 27                        ; first 4 of 30 frames: stronger crack
    JR C,.PULSE
    LD B,2
.PULSE:
    LD A,E
    OUT (#FE),A
    CALL SFX_SHIP_RANDOM
    AND #3F                      ; independent HIGH time jitter 0..63
    LD C,A
    LD A,(SFX_PERIOD)
    ADD A,C                      ; max 190+63 = 253
.HIGH_WAIT:
    DEC A
    JR NZ,.HIGH_WAIT
    LD A,D
    OUT (#FE),A
    CALL SFX_SHIP_RANDOM
    AND #1F                      ; independent LOW time jitter 0..31
    LD C,A
    LD A,(SFX_PERIOD)
    ADD A,C                      ; max 190+31 = 221
.LOW_WAIT:
    DEC A
    JR NZ,.LOW_WAIT
    DJNZ .PULSE
    EI                             ; last EAR state is low

.ADVANCE:
    LD HL,SFX_FRAMES
    DEC (HL)
    JR Z,.DONE
    LD A,(SFX_PERIOD)
    ADD A,3                      ; descend into lower frequency
    CP 191
    JR C,.STORE
    LD A,190
.STORE:
    LD (SFX_PERIOD),A
    RET
.DONE:
    XOR A
    LD (SFX_ACTIVE),A
    RET

; Galois noise generator, advanced twice per audible pulse.
; OUT: A=new noise byte. Preserves BC, DE and HL.
SFX_SHIP_RANDOM:
    LD A,(SFX_NOISE)
    SRL A
    JR NC,.STORE
    XOR #B8
.STORE:
    LD (SFX_NOISE),A
    RET

; One preset = duration (50Hz frames), period, per-frame sweep.
SFX_PRESETS:
    DB 4,11,5                      ; laser shot
    DB 3,7,8                       ; hard hit
    DB 9,19,5                      ; noisy asteroid destruction
    DB 8,14,2                      ; two-part alarm
    DB 30,126,3                    ; low noisy ship blast, separate path

SFX_ACTIVE:  DB 0
SFX_FRAMES:  DB 0
SFX_PERIOD:  DB 0
SFX_SWEEP:   DB 0
SFX_NOISE:   DB #A5
SFX_FE_BASE: DB 1                  ; shadow: border/MIC only, no EAR

; ===== melodies.asm =====
; -------------------------------------------------------------
; SpaceCan Step 15: BPM-aware beeper melodies, 16-bit note lengths.
;
; Melody source is written in musical note values, not raw periods:
;    MELODY_NOTE NOTE_E5, DUR_EIGHTH, PAUSE_BPM
;    MELODY_REST DUR_SIXTEENTH, PAUSE_BPM
;    MELODY_END
;
; Encoded stream (3 bytes per event):
;   pitch, count_lo, count_hi
;   pitch 1..255 = note; count is 16-bit square-wave cycles.
;   pitch 0 + nonzero count = silence in 50Hz interrupt frames.
;   pitch 0 + zero count = end of tune.
;
; Tempo and duration symbols are compile-time: change *_BPM and
; reassemble. This keeps the run-time 48K player small and readable.
; 24 units per quarter note: represents ordinary notes, dotted
; notes, and standard triplets without fractional arithmetic.
; -------------------------------------------------------------

MELODY_CPU_HZ      EQU 3500000
MELODY_FRAME_HZ    EQU 50
MELODY_UNITS_BEAT  EQU 24
MELODY_GAP_FRAMES  EQU 1       ; a real 20ms silence after each note

DUR_WHOLE          EQU 96
DUR_HALF           EQU 48
DUR_QUARTER        EQU 24
DUR_EIGHTH         EQU 12
DUR_SIXTEENTH      EQU 6
DUR_THIRTYSECOND   EQU 3

DUR_HALF_DOT       EQU 72
DUR_QUARTER_DOT    EQU 36
DUR_EIGHTH_DOT     EQU 18
DUR_SIXTEENTH_DOT  EQU 9

DUR_HALF_TRIPLET      EQU 32
DUR_QUARTER_TRIPLET   EQU 16
DUR_EIGHTH_TRIPLET    EQU 8
DUR_SIXTEENTH_TRIPLET EQU 4

; One square-wave cycle is approximately 54 + 32*pitch T-states.
; Divide clock by the per-cycle cost FIRST to avoid overflow of
; 32-bit assembler arithmetic, then multiply by musical duration.
; Note encoding uses a 16-bit cycle count, so long notes no longer
; suffer the former 255-cycle limit.
    MACRO MELODY_NOTE pitch, duration, tempo
    DB pitch
    DW ((MELODY_CPU_HZ / (54 + 32*(pitch))) * 60 * (duration) + ((tempo)*MELODY_UNITS_BEAT/2)) / ((tempo)*MELODY_UNITS_BEAT)
    ENDM

; A rest is counted in whole 50Hz frames; timing precision is 20ms.
    MACRO MELODY_REST duration, tempo
    DB 0
    DW (MELODY_FRAME_HZ * 60 * (duration) + ((tempo)*MELODY_UNITS_BEAT/2)) / ((tempo)*MELODY_UNITS_BEAT)
    ENDM

    MACRO MELODY_END
    DB 0,0,0
    ENDM

; IN HL = 3-byte melody stream. OUT no defined registers.
; Preserves IX. Uses foreground beeper only outside active play:
; title, Game Over, or after the game state is set to PAUSED.
; Tone generation is DI-blocking, rests/gaps use 50Hz IM1 HALT.
MELODY_PLAY:
    PUSH IX
    PUSH HL
    POP IX                        ; IX tracks the current event
    DI
.NEXT_EVENT:
    LD C,(IX+0)                  ; tone half-period (0 = rest/end)
    LD E,(IX+1)                  ; 16-bit cycle count / rest frames
    LD D,(IX+2)
    INC IX
    INC IX
    INC IX
    LD A,C
    OR A
    JR NZ,.NOTE
    LD A,D
    OR E
    JR Z,.END                    ; 0,0,0 = end of melody
    CALL MELODY_WAIT_FRAMES      ; explicit rest, no extra note gap
    JR .NEXT_EVENT
.NOTE:
    LD A,D
    OR E
    JR Z,.NEXT_EVENT             ; a zero-length note is ignored
    CALL MELODY_TONE
    LD DE,MELODY_GAP_FRAMES
    CALL MELODY_WAIT_FRAMES
    JR .NEXT_EVENT
.END:
    LD A,(SFX_FE_BASE)
    AND #0F                       ; EAR low; keep border and MIC
    OUT (#FE),A
    EI
    POP IX
    RET

; IN: C = pitch delay, DE = complete square-wave cycles (1..65535).
; Out: DE=0; destroys AF,HL. Preserves BC and IX.
; One loop is ~54+32*C T-states. Interrupts must be disabled.
MELODY_TONE:
    LD A,(SFX_FE_BASE)
    AND #0F
    LD H,A                        ; EAR low
    OR #10
    LD L,A                        ; EAR high
.CYCLE:
    LD A,L
    OUT (#FE),A
    LD A,C
.HIGH:
    DEC A
    JR NZ,.HIGH
    LD A,H
    OUT (#FE),A
    LD A,C
.LOW:
    DEC A
    JR NZ,.LOW
    DEC DE                        ; 16-bit duration, no wrap
    LD A,D
    OR E
    JR NZ,.CYCLE
    RET                            ; last write already left EAR low

; IN DE=number of 50Hz frames (1..65535), entry/exit with DI.
; First HALT synchronizes to IM1; the following HALTs consume full
; frame periods. No audible square wave is produced during a rest.
MELODY_WAIT_FRAMES:
    LD A,(SFX_FE_BASE)
    AND #0F
    OUT (#FE),A
    EI
    HALT                           ; align with a frame interrupt
.NEXT_FRAME:
    HALT
    DEC DE
    LD A,D
    OR E
    JR NZ,.NEXT_FRAME
    DI
    RET

; Existing tone periods (8-bit), tuned for 3.5MHz and the loop above.
NOTE_A4 EQU 247
NOTE_B4 EQU 219
NOTE_C5 EQU 208
NOTE_D5 EQU 185
NOTE_E5 EQU 165
NOTE_F5 EQU 155
NOTE_G5 EQU 138
NOTE_A5 EQU 123
NOTE_B5 EQU 109
NOTE_C6 EQU 103
NOTE_D6 EQU 92

; Song tempos are measured in quarter notes per minute.
PAUSE_BPM      EQU 160
TITLE_BPM      EQU 160
GAME_OVER_BPM  EQU 150

; Pause: E - C - E - C held, with the last C one full quarter.
; At 160 BPM the first three notes are each ~93.75ms, last ~375ms.
MELODY_PAUSE:
    MELODY_NOTE NOTE_E5, DUR_SIXTEENTH, PAUSE_BPM
    MELODY_NOTE NOTE_C5, DUR_SIXTEENTH, PAUSE_BPM
    MELODY_NOTE NOTE_E5, DUR_SIXTEENTH, PAUSE_BPM
    MELODY_NOTE NOTE_C5, DUR_QUARTER, PAUSE_BPM
    MELODY_END

; Original nine-note rising SpaceCan title fanfare.
MELODY_TITLE:
    MELODY_NOTE NOTE_C5, DUR_SIXTEENTH, TITLE_BPM
    MELODY_NOTE NOTE_E5, DUR_SIXTEENTH, TITLE_BPM
    MELODY_NOTE NOTE_G5, DUR_SIXTEENTH, TITLE_BPM
    MELODY_NOTE NOTE_C6, DUR_EIGHTH, TITLE_BPM
    MELODY_NOTE NOTE_D6, DUR_SIXTEENTH, TITLE_BPM
    MELODY_NOTE NOTE_C6, DUR_SIXTEENTH, TITLE_BPM
    MELODY_NOTE NOTE_G5, DUR_EIGHTH, TITLE_BPM
    MELODY_NOTE NOTE_E5, DUR_SIXTEENTH, TITLE_BPM
    MELODY_REST DUR_SIXTEENTH, TITLE_BPM
    MELODY_NOTE NOTE_C6, DUR_EIGHTH_DOT, TITLE_BPM
    MELODY_END

; Original seven-note downward Game Over ending.
MELODY_GAME_OVER:
    MELODY_NOTE NOTE_C6, DUR_SIXTEENTH, GAME_OVER_BPM
    MELODY_NOTE NOTE_B5, DUR_SIXTEENTH, GAME_OVER_BPM
    MELODY_NOTE NOTE_A5, DUR_SIXTEENTH, GAME_OVER_BPM
    MELODY_NOTE NOTE_G5, DUR_SIXTEENTH, GAME_OVER_BPM
    MELODY_NOTE NOTE_E5, DUR_EIGHTH, GAME_OVER_BPM
    MELODY_NOTE NOTE_D5, DUR_EIGHTH, GAME_OVER_BPM
    MELODY_NOTE NOTE_C5, DUR_QUARTER, GAME_OVER_BPM
    MELODY_END

; ===== ay_driver.asm =====
; -------------------------------------------------------------
; AY-3-891x hardware access: ZX 128-compatible I/O decode.
; Delta-C uses an external AY board; confirm #FFFD/#BFFD decoding.
; IN  AY_WRITE_REG: A=register 0..13, E=value
; OUT: AF/flags destroyed; BC, DE, HL, IX preserved.
; R14/R15 (GPIO) are never accessed by the music player.
; -------------------------------------------------------------
AY_PORT_SELECT EQU #FFFD
AY_PORT_WRITE  EQU #BFFD

AY_WRITE_REG:
    PUSH BC
    LD BC,AY_PORT_SELECT
    OUT (C),A
    LD BC,AY_PORT_WRITE
    LD A,E
    OUT (C),A
    POP BC
    RET

; Hardware mute: R7 disables all tone/noise and R8-R10 are zero.
; R7 bits 6/7 are zero (GPIO inputs), not used for peripherals.
; Clobbers AF, E. Preserves BC, HL, IX.
AY_SILENCE:
    LD E,#3F
    LD A,7
    CALL AY_WRITE_REG
    LD E,0
    LD A,8
    CALL AY_WRITE_REG
    LD A,9
    CALL AY_WRITE_REG
    LD A,10
    JP AY_WRITE_REG

; ===== ay_player.asm =====
; -------------------------------------------------------------
; SpaceCan AYM1 v1 player: register deltas at 50Hz, no MIDI parsing.
;
; AY_INIT     reset hardware/shadow
; AY_PLAY     HL -> AYM1 blob (header + command stream)
; AY_TICK     IM2-only, one stream frame (preserves BC,DE,HL,IX)
; AY_PAUSE    mute and freeze stream; do not reset AY R13
; AY_RESUME   restore R7 and R8-R10 from last logical frame
; AY_STOP     stop stream, mute hardware
; Public control routines preserve the incoming interrupt-enable state
; and are safe against IM2 AY_TICK. Only the ISR calls AY_STOP_RAW.
;
; Runtime only writes R0..R13. Converter resolves MIDI overlapping
; notes, channel allocation, tempo, ADSR/velocity OFFLINE.
; R13 is written each time its mask bit is set, even if unchanged.
; -------------------------------------------------------------

AY_INIT:
    CALL AY_RESET_SHADOW
    JP AY_STOP

; Reset logical register state for the next song. Hardware is
; already silenced by AY_STOP, so these are only shadow writes.
AY_RESET_SHADOW:
    LD HL,AY_SHADOW
    LD B,14
    XOR A
.CLEAR:
    LD (HL),A
    INC HL
    DJNZ .CLEAR
    LD A,#3F
    LD (AY_SHADOW+7),A
    RET

; Atomic mainline control entry. LD A,I copies IFF2 to P/V.
; Save flags BEFORE DI. Do not force EI if the caller entered with DI.
AY_STOP:
    LD A,I
    PUSH AF
    DI
    CALL AY_STOP_RAW
    POP AF
    RET PO
    EI
    RET

; Raw stop is ALSO called from the IM2 decoder: must not EI.
AY_STOP_RAW:
    XOR A
    LD (AY_ACTIVE),A
    LD (AY_PAUSED),A
    LD (AY_WAIT),A
    JP AY_SILENCE

; Header v1 (16 bytes):
; +0  "AYM1", +4 fps=50, +5 flags bit0=loop, +6 word full size,
; +8 word loop byte offset, +10 word 0, +12 dword target clock.
; Data begins at +16. Size includes header. Loop offset must
; point to the beginning of a command, not the terminal END byte.
AY_PLAY:
    LD A,I
    PUSH AF
    DI
    CALL AY_PLAY_RAW
    POP AF
    RET PO
    EI
    RET

AY_PLAY_RAW:
    PUSH HL
    CALL AY_STOP_RAW
    CALL AY_RESET_SHADOW
    POP HL
    LD (AY_BASE),HL
    LD A,(HL)
    CP 'A'
    JP NZ,.INVALID
    INC HL
    LD A,(HL)
    CP 'Y'
    JP NZ,.INVALID
    INC HL
    LD A,(HL)
    CP 'M'
    JP NZ,.INVALID
    INC HL
    LD A,(HL)
    CP '1'
    JP NZ,.INVALID
    INC HL
    LD A,(HL)
    CP 50
    JP NZ,.INVALID
    INC HL
    LD A,(HL)
    LD (AY_FLAGS),A
    AND #FE                       ; v1 supports only loop bit 0
    JP NZ,.INVALID
    INC HL
    LD E,(HL)                     ; total length in bytes
    INC HL
    LD D,(HL)
    LD (AY_LENGTH),DE
    INC HL
    LD E,(HL)                     ; loop offset from track base
    INC HL
    LD D,(HL)
    LD (AY_LOOP_OFFSET),DE
    INC HL
    LD A,(HL)                     ; reserved must be zero
    OR A
    JP NZ,.INVALID
    INC HL
    LD A,(HL)
    OR A
    JP NZ,.INVALID
    INC HL
    LD DE,4
    ADD HL,DE                     ; skip target clock metadata
    LD (AY_POS),HL                ; base + 16

    LD HL,(AY_LENGTH)
    LD DE,17                      ; at least 16-byte header + END
    OR A
    SBC HL,DE
    JP C,.INVALID
    LD HL,(AY_BASE)
    LD DE,(AY_LENGTH)
    ADD HL,DE
    JP C,.INVALID                 ; refuse tracks crossing #FFFF
    LD (AY_END_PTR),HL

    LD A,(AY_FLAGS)
    AND 1
    JR Z,.READY
    LD HL,(AY_LOOP_OFFSET)
    LD DE,16
    OR A
    SBC HL,DE
    JP C,.INVALID                 ; must point inside payload
    LD HL,(AY_LOOP_OFFSET)
    LD DE,(AY_LENGTH)
    OR A
    SBC HL,DE
    JP NC,.INVALID
    LD HL,(AY_BASE)
    LD DE,(AY_LOOP_OFFSET)
    ADD HL,DE
    LD (AY_LOOP_PTR),HL
.READY:
    LD A,1
    LD (AY_ACTIVE),A
    RET
.INVALID:
    JP AY_STOP_RAW                ; malformed header -> silence

AY_PAUSE:
    LD A,I
    PUSH AF
    DI
    CALL AY_PAUSE_RAW
    POP AF
    RET PO
    EI
    RET

AY_PAUSE_RAW:
    LD A,(AY_ACTIVE)
    OR A
    RET Z
    LD A,1
    LD (AY_PAUSED),A
    JP AY_SILENCE                 ; keep AY_SHADOW unchanged

AY_RESUME:
    LD A,I
    PUSH AF
    DI
    CALL AY_RESUME_RAW
    POP AF
    RET PO
    EI
    RET

AY_RESUME_RAW:
    LD A,(AY_ACTIVE)
    OR A
    RET Z
    XOR A
    LD (AY_PAUSED),A
    LD A,(AY_SHADOW+8)
    LD E,A
    LD A,8
    CALL AY_WRITE_REG
    LD A,(AY_SHADOW+9)
    LD E,A
    LD A,9
    CALL AY_WRITE_REG
    LD A,(AY_SHADOW+10)
    LD E,A
    LD A,10
    CALL AY_WRITE_REG
    LD A,(AY_SHADOW+7)
    LD E,A
    LD A,7
    JP AY_WRITE_REG

AY_TICK:
    PUSH BC
    PUSH DE
    PUSH HL
    CALL AY_TICK_INTERNAL
    POP HL
    POP DE
    POP BC
    RET

AY_TICK_INTERNAL:
    LD A,(AY_ACTIVE)
    OR A
    RET Z
    LD A,(AY_PAUSED)
    OR A
    RET NZ
    LD A,(AY_WAIT)
    OR A
    JR Z,.DECODE
    DEC A
    LD (AY_WAIT),A
    RET

.DECODE:
    ; Guard the command pointer before reading a new opcode.
    LD HL,(AY_POS)
    LD DE,(AY_END_PTR)
    PUSH HL
    OR A
    SBC HL,DE
    POP HL
    JP NC,AY_STOP_RAW
    LD A,(HL)
    INC HL
    OR A
    JP Z,.TRACK_END
    CP #80
    JP Z,.REG_FRAME
    BIT 7,A
    JP NZ,AY_STOP_RAW             ; 81..FF reserved
    DEC A                         ; WAIT n: n ticks of silence
    LD (AY_WAIT),A
    LD (AY_POS),HL
    RET

.REG_FRAME:
    LD C,(HL)                     ; 14-bit bitmask, LE
    INC HL
    LD B,(HL)
    INC HL
    LD A,B
    AND #C0
    JP NZ,AY_STOP_RAW             ; bits 14/15 reserved
    LD D,0                        ; AY register 0..13
.NEXT_REG:
    LD A,B
    OR C
    JR Z,.FRAME_DONE
    BIT 0,C
    JR Z,.ADVANCE
    LD E,(HL)                     ; next value selected by mask
    INC HL
    LD A,D
    CP 7
    JR NZ,.SAVE
    LD A,E
    AND #3F                       ; R7: GPIO A/B input, no R14/R15
    LD E,A
.SAVE:
    PUSH HL
    LD HL,AY_SHADOW
    LD A,D
    ADD A,L
    LD L,A
    JR NC,.INDEX_READY
    INC H
.INDEX_READY:
    LD (HL),E                     ; shadow is authoritative on resume
    LD A,D
    CALL AY_WRITE_REG             ; ALWAYS write if mask bit set
    POP HL
.ADVANCE:
    SRL B
    RR C
    INC D
    JR .NEXT_REG
.FRAME_DONE:
    LD (AY_POS),HL
    RET

.TRACK_END:
    LD A,(AY_FLAGS)
    AND 1
    JP Z,AY_STOP_RAW
    LD HL,(AY_LOOP_PTR)
    LD A,(HL)
    OR A
    JP Z,AY_STOP_RAW              ; no endless zero-length loop
    LD (AY_POS),HL
    JP .DECODE                    ; loop boundary has no extra tick

AY_ACTIVE:       DB 0
AY_PAUSED:       DB 0
AY_FLAGS:        DB 0
AY_WAIT:         DB 0
AY_BASE:         DW 0
AY_LENGTH:       DW 0
AY_LOOP_OFFSET:  DW 0
AY_LOOP_PTR:     DW 0
AY_END_PTR:      DW 0
AY_POS:          DW 0
AY_SHADOW:       DS 14,0

; ===== music.asm =====
; -------------------------------------------------------------
; SpaceCan Step 18: external AYM1 music resources, zero inline music.
; Drop converted full-format .aym files into assets/music/ and rebuild.
; Each .aym contains a complete 16-byte AYM1 header + register stream.
;
; Target AY clock: 2000000 Hz. If your board uses a different clock,
; export the .aym files for that clock; source assembly no longer
; recalculates the notes contained in these binary resources.
; -------------------------------------------------------------

    IF AY_MUSIC_ENABLED
AY_MUSIC_TITLE:
    INCBIN "assets/music/title.aym"

AY_MUSIC_GAME:
    INCBIN "assets/music/game.aym"

AY_MUSIC_GAME_OVER:
    INCBIN "assets/music/game_over.aym"
    ENDIF

; ===== logic.asm =====
; -------------------------------------------------------------
; INPUT: controls prepare positions only. No drawing here.
; O/P: move; SPACE: fire on edge. Speed is score-driven.
; -------------------------------------------------------------
READ_INPUT:
    CALL READ_SHIP_HORIZONTAL
    CALL READ_FIRE_KEY
    RET

; The 8x8 ship stays within X=8..23, Y=22, now moving in 4px steps.
; Banking is independent:
; one pose every SHIP_BANK_DELAY frames, then a short hold after
; release to make brief turns visible.
READ_SHIP_HORIZONTAL:
    ; 8x8 ship moves in 4-pixel steps (1/2 character cell).
    ; X stores the LEFT cell; SHIP_HALF_POS=1 means +4 pixels.
    ; Valid leftmost pixel positions are 8*8 .. 23*8.
    LD BC,#DFFE
    IN A,(C)
    BIT 0,A                      ; P: right
    JR NZ,.CHECK_LEFT
    LD D,4
    LD A,(SHIP_NEW_POS)
    CP PLAYFIELD_RIGHT
    JP Z,.SET_BANK               ; last whole cell: never spill right

    LD A,(SHIP_MOVE_TIMER)
    OR A
    JP NZ,.WAIT
    LD A,(SHIP_HALF_POS)
    OR A
    JR Z,.HALF_RIGHT
    ;  x+.5 -> (x+1)+0
    XOR A
    LD (SHIP_HALF_POS),A
    LD HL,SHIP_NEW_POS
    INC (HL)
    JP .MOVED
.HALF_RIGHT:
    LD A,1
    LD (SHIP_HALF_POS),A
    JP .MOVED

.CHECK_LEFT:
    BIT 1,A                      ; O: left
    JP NZ,.NO_KEY
    LD D,0
    LD A,(SHIP_NEW_POS)
    CP PLAYFIELD_LEFT
    JR NZ,.LEFT_ALLOWED
    LD A,(SHIP_HALF_POS)
    OR A
    JP Z,.SET_BANK               ; at the leftmost pixel
.LEFT_ALLOWED:
    LD A,(SHIP_MOVE_TIMER)
    OR A
    JP NZ,.WAIT
    LD A,(SHIP_HALF_POS)
    OR A
    JR NZ,.HALF_LEFT
    ;  x+0 -> (x-1)+.5
    LD HL,SHIP_NEW_POS
    DEC (HL)
    LD A,1
    LD (SHIP_HALF_POS),A
    JP .MOVED
.HALF_LEFT:
    XOR A
    LD (SHIP_HALF_POS),A
    JP .MOVED

.WAIT:
    DEC A
    LD (SHIP_MOVE_TIMER),A
    JR .SET_BANK
.MOVED:
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
    LD A,(GAME_STATE)
    CP STATE_BOSS
    JP Z,UPDATE_BOSS_GAME

    XOR A
    LD (MISS_KILLED_THIS_TICK),A
    CALL UPDATE_BLAST_ANIM
    CALL UPDATE_ENEMIES
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    RET NZ                      ; a missed asteroid may end the game
    CALL UPDATE_BULLETS
    CALL CHECK_SHIP_ENEMY_COLLISIONS
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    RET NZ                     ; ship destroyed: freeze starfield
    ; Count world distance AFTER bullets: a kill in this tick resets it.
    CALL UPDATE_MISS_PRESSURE
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    RET NZ
    CALL STARFIELD_UPDATE
    JP MAYBE_START_BOSS

; Final boss has no asteroids and no missed-screen penalty.
UPDATE_BOSS_GAME:
    CALL UPDATE_BOSS
    CALL UPDATE_HOSTILE_BULLETS
    LD A,(GAME_STATE)
    CP STATE_BOSS
    RET NZ
    CALL UPDATE_BULLETS
    LD A,(GAME_STATE)
    CP STATE_BOSS
    RET NZ
    JP STARFIELD_UPDATE

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
    LD (BLAST_HALF),A          ; asteroids always cell aligned
    LD (BLAST_FRAME),A
    CALL SELECT_BLAST_FRAME
    LD A,BLAST_FRAME_DURATION
    LD (BLAST_ANIM_TIMER),A
    LD A,1
    LD (BLAST_ACTIVE),A
    LD (BLAST_DIRTY),A
    ;IFN DEBUG_BORDER
    ;    LD A,2
    ;    OUT (#FE),A
    ;ENDIF
    RET

; Dedicated ship explosion replaces any asteroid blast. Its last
; drawn image is marked for erasure BEFORE BLAST_POS is replaced.
; The renderer then erases the ship and paints explosion frame zero.
START_SHIP_EXPLOSION:
    LD A,SFX_SHIP              ; highest priority: new ship explosion
    CALL SFX_START
    LD A,(BLAST_DRAWN)
    OR A
    JR Z,.OLD_GONE
    CALL ERASE_BLAST
    XOR A
    LD (BLAST_DRAWN),A
.OLD_GONE:
    LD HL,(SHIP_NEW_POS)
    LD (BLAST_POS),HL           ; retain base X, don't round to next cell
    LD A,(SHIP_HALF_POS)
    LD (BLAST_HALF),A          ; ship blast is also shifted by exactly 4px
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
; Score/bonus: 24-bit total (capped at 999999).
; Small = 64, large = 128 points. Gentle speed milestones:
; 4096, 8192, 16384, 32768 => stages 1..4 (start stage 0).
; -------------------------------------------------------------
ADD_SCORE_A:
    LD E,A
    LD D,0
    LD HL,(SCORE)
    ADD HL,DE
    LD (SCORE),HL
    LD A,(SCORE+2)
    ADC A,0
    LD (SCORE+2),A

    ; Saturate at 999999 = #0F423F, not at 16-bit #FFFF.
    CP #0F
    JR C,.IN_RANGE
    JR NZ,.CAP
    LD HL,(SCORE)
    LD DE,#4240                 ; first value beyond 999999
    OR A
    SBC HL,DE
    JR C,.IN_RANGE
.CAP:
    LD HL,#423F
    LD (SCORE),HL
    LD A,#0F
    LD (SCORE+2),A
.IN_RANGE:
    LD A,1
    LD (HUD_DIRTY),A
    JP CHECK_SCORE_BONUS

; Demo only: jump from stage 0 (1x) straight to stage 2 (2x).
; Both score limits are defined near the top of main.asm.
CHECK_SCORE_BONUS:
    LD DE,DEMO_SPEEDUP_SCORE & #FFFF
    LD A,DEMO_SPEEDUP_SCORE >> 16
    CALL SCORE_AT_LEAST
    LD A,0                        ; before threshold: 1x
    JR C,.STORE
    LD A,2                        ; reached threshold: 2x
.STORE:
    LD HL,SPEED_LEVEL
    CP (HL)
    RET Z
    LD (HL),A
    SRL A                         ; stages 0/2 -> integer 1/2
    INC A
    LD (SCROLL_SPEED),A
    LD A,1
    LD (HUD_DIRTY),A
    RET

; Generic 24-bit score comparison, shared with the boss trigger.
; IN: A=high threshold byte, DE=low 16 bits of threshold.
; OUT: Carry=1 when SCORE<threshold; Carry=0 otherwise.
; DESTROYS AF,HL; preserves BC,DE and IX/IY.
SCORE_AT_LEAST:
    LD H,A
    LD A,(SCORE+2)
    CP H
    RET C
    JR NZ,.REACHED
    LD HL,(SCORE)
    OR A                          ; clear carry before 16-bit subtract
    SBC HL,DE
    RET
.REACHED:
    OR A                          ; SCORE high byte exceeds threshold
    RET

; -------------------------------------------------------------
; Pressure grows with world travel, NOT with count of escaped objects.
; Every downward movement is one of 20 rows in a corridor crossing.
; Three complete corridor heights (60 moves) with no asteroid kill
; add ONE permanent red segment. Any kill resets only the travel timer,
; never the accumulated gauge. At ten red segments a life is lost
; through the normal ship-explosion/respawn sequence.
; -------------------------------------------------------------
UPDATE_MISS_PRESSURE:
    LD A,(MISS_KILLED_THIS_TICK)
    OR A
    RET NZ                        ; a destruction restarted the timer
    LD A,(ENEMY_MOVE_NOW)
    OR A
    RET Z                         ; count movement, not 50Hz frames
    LD HL,MISS_TRAVEL_ROWS
    INC (HL)
    LD A,(HL)
    CP MISS_SCREEN_ROWS
    JR NZ,.CHECK_PENALTY
    ; One complete screen has passed without destroying an asteroid.
    ; Warning stays active across the 3-screen penalty counter wrap.
    LD A,1
    LD (SHOOT_WARNING_ACTIVE),A
    LD A,(HL)
.CHECK_PENALTY:
    CP MISS_DISTANCE_LIMIT
    RET C                         ; fewer than 3 screens since last kill
    LD (HL),0                     ; begin the next 3-screen interval

    LD HL,PRESSURE_LEVEL
    INC (HL)                      ; once red, segments never turn green
    LD A,1
    LD (GAUGE_DIRTY),A
    LD A,SFX_PENALTY           ; new red segment: double warning chirp
    CALL SFX_START
    LD A,(PRESSURE_LEVEL)
    CP PRESSURE_SEGMENTS
    RET C

    ; Full red bar takes one life and triggers the familiar ship blast.
    LD A,(SHIP_LIVES)
    OR A
    RET Z
    DEC A
    LD (SHIP_LIVES),A
    LD A,1
    LD (HUD_DIRTY),A
    JP START_SHIP_EXPLOSION

; Called ONLY for an asteroid destroyed by bullets.
RESET_MISS_TRAVEL:
    XOR A
    LD (MISS_TRAVEL_ROWS),A
    LD (SHOOT_WARNING_ACTIVE),A   ; next render restores original HUD
    LD (SHOOT_BLINK_COUNTER),A
    INC A
    LD (MISS_KILLED_THIS_TICK),A
    RET

; ===== bullets.asm =====
; -------------------------------------------------------------
; BULLET POOL (6 x 9 bytes)
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
; Bullet preserves the ship's exact 4px alignment at firing.
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
    DEC H                        ; launch one row above the ship
    LD (IX+B_X),L
    LD (IX+B_Y),H
    LD A,(SHIP_HALF_POS)
    LD (IX+B_HALF),A            ; 0=aligned, 1=shift right 4 pixels
    LD A,1
    LD (IX+B_ACTIVE),A
    LD (IX+B_DIRTY),A
    LD HL,BULLET_COUNT
    INC (HL)
    LD A,SFX_SHOT
    JP SFX_START                 ; sound only after successful spawn
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
    CALL CHECK_BULLET_HOSTILES
    RET C
    CALL CHECK_BULLET_BOSS
    RET C
    CALL CHECK_BULLET_ENEMIES
    RET C
    LD A,(BLAST_ACTIVE)
    OR A
    RET Z
    LD A,(BLAST_POS+1)
    CP (IX+B_Y)
    RET NZ

    ; Check character-cell overlap of bullet and explosion.
    ; A shifted 8x8 bullet can occupy B_X and B_X+1.
    ; A large asteroid blast or shifted ship blast covers 2 cells.
    LD A,(BLAST_POS)
    LD C,A
    LD A,(IX+B_X)
    CP C
    JR Z,.ABSORB
    JR C,.BULLET_LEFT

    ; Bullet lies one cell to the right of the blast start.
    SUB C
    CP 1
    RET NZ
    LD A,(BLAST_TYPE)
    OR A
    JR NZ,.ABSORB
    LD A,(BLAST_OWNER)
    OR A
    RET Z
    LD A,(BLAST_HALF)
    OR A
    RET Z
    JR .ABSORB

.BULLET_LEFT:
    LD A,(IX+B_HALF)
    OR A
    RET Z
    LD A,(IX+B_X)
    INC A
    CP C
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

    ; Also invalidate the new occupied area, so stars behind a
    ; newly fired half-shifted bullet are restored on the star pass.
    LD A,(IX+B_ACTIVE)
    OR A
    JR Z,.SKIP
    LD B,(IX+B_Y)
    LD C,(IX+B_X)
    LD DE,#0101
    LD A,(IX+B_HALF)
    OR A
    JR Z,.MARK_NEW
    LD D,2
.MARK_NEW:
    CALL STARFIELD_MARK_RECT
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
    LD A,(IX+B_HALF)
    OR A
    JR NZ,.SHIFTED
    LD DE,BULLET_ATTR
    CALL RESTORE_ATTR_1_1
    LD DE,BULLET_SPRITE
    CALL DRAW_1_1
    JR .SAVE_DRAWN
.SHIFTED:
    LD DE,BULLET_ATTR_PAIR
    CALL RESTORE_ATTR_1_2
    LD DE,BULLET_SPRITE
    CALL DRAW_SHIFT4_1_1
.SAVE_DRAWN:
    LD A,(IX+B_X)
    LD (IX+B_DRAW_X),A
    LD A,(IX+B_Y)
    LD (IX+B_DRAW_Y),A
    LD A,(IX+B_HALF)
    LD (IX+B_DRAW_HALF),A
    LD A,1
    LD (IX+B_DRAWN),A
    RET

ERASE_BULLET_SLOT:
    LD B,(IX+B_DRAW_Y)
    LD C,(IX+B_DRAW_X)
    LD DE,#0101
    LD A,(IX+B_DRAW_HALF)
    OR A
    JR Z,.MARK
    LD D,2
.MARK:
    CALL STARFIELD_MARK_RECT
    XOR A
    LD (IX+B_DRAWN),A
    RET

; ===== hostile_bullets.asm =====
; -------------------------------------------------------------
; Shared hostile bullets (boss now, manoeuvring shooters later).
; 6 slots x 7 bytes, one 8x8 sprite, 1 row per 4 gameplay ticks.
; -------------------------------------------------------------

HB_ACTIVE  EQU 0
HB_X       EQU 1
HB_Y       EQU 2
HB_DRAWN   EQU 3
HB_DRAW_X  EQU 4
HB_DRAW_Y  EQU 5
HB_DIRTY   EQU 6

RESET_HOSTILE_BULLETS:
    LD HL,HOSTILE_BULLET_POOL
    LD (HL),0
    LD DE,HOSTILE_BULLET_POOL+1
    LD BC,MAX_HOSTILE_BULLETS*HOSTILE_BULLET_SIZE-1
    LDIR
    LD A,HOSTILE_MOVE_DELAY
    LD (HOSTILE_BULLET_CLOCK),A
    RET

; IN BC=YX (B=row, C=column). PRESERVE BC/DE/IX.
SPAWN_HOSTILE_BULLET:
    PUSH BC
    PUSH DE
    PUSH IX
    LD IX,HOSTILE_BULLET_POOL
    LD D,MAX_HOSTILE_BULLETS
.FIND:
    LD A,(IX+HB_ACTIVE)
    OR A
    JR NZ,.NEXT
    LD A,(IX+HB_DRAWN)
    OR A
    JR NZ,.NEXT
    LD (IX+HB_X),C
    LD (IX+HB_Y),B
    LD A,1
    LD (IX+HB_ACTIVE),A
    LD (IX+HB_DIRTY),A
    JR .DONE
.NEXT:
    ; Save requested YX in BC and retain D as the slot counter.
    PUSH BC
    LD BC,HOSTILE_BULLET_SIZE
    ADD IX,BC
    POP BC
    DEC D
    JR NZ,.FIND
.DONE:
    POP IX
    POP DE
    POP BC
    RET

UPDATE_HOSTILE_BULLETS:
    LD HL,HOSTILE_BULLET_CLOCK
    DEC (HL)
    JR NZ,.NO_STEP
    LD (HL),HOSTILE_MOVE_DELAY
    LD A,1
    LD (HOSTILE_MOVE_NOW),A
    JR .SCAN
.NO_STEP:
    XOR A
    LD (HOSTILE_MOVE_NOW),A
.SCAN:
    LD IX,HOSTILE_BULLET_POOL
    LD B,MAX_HOSTILE_BULLETS
.NEXT:
    PUSH BC
    CALL UPDATE_HOSTILE_SLOT
    POP BC
    LD DE,HOSTILE_BULLET_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

UPDATE_HOSTILE_SLOT:
    LD A,(GAME_STATE)
    CP STATE_BOSS
    RET NZ
    LD A,(IX+HB_ACTIVE)
    OR A
    RET Z
    LD A,(HOSTILE_MOVE_NOW)
    OR A
    JR Z,.CHECK_SHIP
    LD A,(IX+HB_Y)
    CP PLAYFIELD_BOTTOM
    JR NC,.EXPIRE
    INC A
    LD (IX+HB_Y),A
    LD A,1
    LD (IX+HB_DIRTY),A
.CHECK_SHIP:
    LD A,(IX+HB_Y)
    LD C,A
    LD A,(SHIP_NEW_POS+1)
    CP C
    RET NZ
    LD A,(IX+HB_X)
    LD C,A
    LD A,(SHIP_NEW_POS)
    CP C
    JR Z,.HIT
    LD A,(SHIP_HALF_POS)
    OR A
    RET Z
    LD A,(SHIP_NEW_POS)
    INC A
    CP C
    RET NZ
.HIT:
    CALL DEACTIVATE_HOSTILE_SLOT
    LD A,(SHIP_LIVES)
    OR A
    RET Z
    DEC A
    LD (SHIP_LIVES),A
    LD A,1
    LD (HUD_DIRTY),A
    JP START_SHIP_EXPLOSION
.EXPIRE:
    JP DEACTIVATE_HOSTILE_SLOT

DEACTIVATE_HOSTILE_SLOT:
    XOR A
    LD (IX+HB_ACTIVE),A
    LD A,1
    LD (IX+HB_DIRTY),A
    RET

; Player/hostile bullets annihilate one another on contact.
; IN IX=player bullet, preserves IX; OUT carry set if consumed.
CHECK_BULLET_HOSTILES:
    LD A,(BOSS_STARTED)
    OR A
    JR Z,.MISS
    PUSH IY
    LD IY,HOSTILE_BULLET_POOL
    LD B,MAX_HOSTILE_BULLETS
.NEXT:
    LD A,(IY+HB_ACTIVE)
    OR A
    JR Z,.SKIP
    LD A,(IX+B_Y)
    CP (IY+HB_Y)
    JR NZ,.SKIP
    LD A,(IX+B_X)
    CP (IY+HB_X)
    JR Z,.HIT
    LD A,(IX+B_HALF)
    OR A
    JR Z,.SKIP
    LD A,(IX+B_X)
    INC A
    CP (IY+HB_X)
    JR NZ,.SKIP
.HIT:
    XOR A
    LD (IY+HB_ACTIVE),A
    LD A,1
    LD (IY+HB_DIRTY),A
    POP IY
    CALL DEACTIVATE_BULLET
    SCF
    RET
.SKIP:
    LD DE,HOSTILE_BULLET_SIZE
    ADD IY,DE
    DJNZ .NEXT
    POP IY
.MISS:
    OR A
    RET

RENDER_ERASE_HOSTILE_BULLETS:
    LD A,(BOSS_STARTED)
    OR A
    RET Z
    LD IX,HOSTILE_BULLET_POOL
    LD B,MAX_HOSTILE_BULLETS
.NEXT:
    PUSH BC
    LD A,(IX+HB_DIRTY)
    OR A
    JR Z,.SKIP
    LD A,(IX+HB_DRAWN)
    OR A
    JR Z,.NEW
    LD B,(IX+HB_DRAW_Y)
    LD C,(IX+HB_DRAW_X)
    LD DE,#0101
    CALL STARFIELD_MARK_RECT
    XOR A
    LD (IX+HB_DRAWN),A
.NEW:
    LD A,(IX+HB_ACTIVE)
    OR A
    JR Z,.SKIP
    LD B,(IX+HB_Y)
    LD C,(IX+HB_X)
    LD DE,#0101
    CALL STARFIELD_MARK_RECT
.SKIP:
    POP BC
    LD DE,HOSTILE_BULLET_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

RENDER_DRAW_HOSTILE_BULLETS:
    LD A,(BOSS_STARTED)
    OR A
    RET Z
    LD IX,HOSTILE_BULLET_POOL
    LD B,MAX_HOSTILE_BULLETS
.NEXT:
    PUSH BC
    LD A,(IX+HB_DIRTY)
    OR A
    JR Z,.SKIP
    XOR A
    LD (IX+HB_DIRTY),A
    LD A,(IX+HB_ACTIVE)
    OR A
    JR Z,.SKIP
    LD B,(IX+HB_Y)
    LD C,(IX+HB_X)
    CALL GET_SCREEN_ADDR
    LD DE,HOSTILE_BULLET_ATTR
    CALL RESTORE_ATTR_1_1
    LD DE,HOSTILE_BULLET_SPRITE
    CALL DRAW_1_1
    LD A,(IX+HB_X)
    LD (IX+HB_DRAW_X),A
    LD A,(IX+HB_Y)
    LD (IX+HB_DRAW_Y),A
    LD A,1
    LD (IX+HB_DRAWN),A
.SKIP:
    POP BC
    LD DE,HOSTILE_BULLET_SIZE
    ADD IX,DE
    DJNZ .NEXT
    RET

HOSTILE_MOVE_NOW: DB 0
HOSTILE_BULLET_ATTR: DB #42
HOSTILE_BULLET_SPRITE:
    DB %00011000
    DB %00111100
    DB %01111110
    DB %11111111
    DB %01111110
    DB %00111100
    DB %00011000
    DB %00000000

; ===== enemies.asm =====
; -------------------------------------------------------------
; ENEMIES: four asteroids spread across the corridor; 8 silhouettes.
;
; IX -> current enemy slot. X is assigned at every spawn and
; remains constant until deactivation; overlapping spawn positions
; are rejected for objects currently occupying the entry rows.
; Game logic updates state/dirty; renderer stores drawn position.
; Shape/palette randomize per spawn. New appearances maintain a
; vertical clearance; lane selection prefers horizontal clearance.
; -------------------------------------------------------------

; Initialise from ENEMY_START_TABLE: TYPE, ENTRY_Y, ANIM_PHASE, DELAY.
; Delayed slots start INACTIVE and enter at the top of the corridor.
; This is used on a new game and after every lost life.
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
    ; Delay is in 50 Hz game frames; a delayed asteroid starts
    ; inactive and uses the standard safe entry-spawn procedure.
    LD A,(HL)
    LD (IX+E_RESPAWN),A
    INC HL
    OR A
    JR NZ,.SKIP_ACTIVE

    ; Every asteroid begins in a randomly selected vertical lane.
    ; Entry checks enforce vertical spacing; lane search keeps X varied.
    PUSH HL
    PUSH BC
    CALL ENEMY_SPAWN_GAP_CLEAR
    JR C,.SPAWN_TESTED
    CALL SELECT_ENEMY_SPAWN_X
.SPAWN_TESTED:
    POP BC
    POP HL
    JR C,.SKIP_ACTIVE
    CALL RANDOMIZE_ENEMY_APPEARANCE
    LD A,1
    LD (IX+E_ACTIVE),A
    LD (IX+E_DIRTY),A
.SKIP_ACTIVE:
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    LD A,4
    LD (ENEMY_MOVE_TIMER),A
    XOR A
    LD (ENEMY_MOVE_NOW),A
    RET

; Smooth speed stages: asteroid motion intervals 4 / 4-3 / 3 / 3-2 / 2 ticks.
UPDATE_ENEMIES:
    LD A,(ENEMY_MOVE_TIMER)
    DEC A
    LD (ENEMY_MOVE_TIMER),A
    JR NZ,.NO_MOVE
    LD A,5
    LD HL,SCROLL_SPEED
    SUB (HL)
    LD C,A                       ; base interval 4, 3 or 2 ticks
    LD A,(SPEED_LEVEL)
    AND 1
    JR Z,.PERIOD_READY
    ; Half-speed stages alternate 4/3 or 3/2 intervals.
    LD A,(ENEMY_SPEED_PHASE)
    XOR 1
    LD (ENEMY_SPEED_PHASE),A
    OR A
    JR Z,.PERIOD_READY
    DEC C
.PERIOD_READY:
    LD A,C
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
    ; If the preceding asteroid caused Game Over, don't move more
    ; objects in this tick. The loop still advances IX safely.
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    RET NZ
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
    JR C,.STEP_DOWN
    ; Natural exit frees the slot. Pressure is based on travel
    ; distance globally, not on how many asteroids pass the ship.
    JP DEACTIVATE_ENEMY
.STEP_DOWN:
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
    CALL ENEMY_SPAWN_GAP_CLEAR
    RET C                      ; wait until 3 clear rows at the entry
    CALL SELECT_ENEMY_SPAWN_X
    RET C                      ; entry row blocked: retry next tick
    CALL RANDOMIZE_ENEMY_APPEARANCE
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
; SPAWN X: prefer lanes with a clear column between all asteroids.
; When no well-separated lane fits, fall back to the existing
; collision-free placement so the fourth asteroid is not starved.
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
    JR C,.STEP_NEXT
    CALL ENEMY_SPAWN_LANE_CLEAR
    JR NC,.SUCCESS
.STEP_NEXT:
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

    ; All preferred lanes failed: retry without the cosmetic
    ; horizontal gap. Spatial overlap is still forbidden.
    LD B,PLAYFIELD_WIDTH
.RELAX:
    CALL ENEMY_SPAWN_CLEAR
    JR NC,.SUCCESS
    LD C,PLAYFIELD_RIGHT
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.RELAX_STEP
    DEC C
.RELAX_STEP:
    LD A,(IX+E_X)
    CP C
    JR C,.RELAX_INC
    LD A,PLAYFIELD_LEFT
    JR .RELAX_STORE
.RELAX_INC:
    INC A
.RELAX_STORE:
    LD (IX+E_X),A
    DJNZ .RELAX
    POP HL
    POP DE
    POP BC
    SCF                         ; no nonoverlapping lane exists
    RET
.SUCCESS:
    POP HL
    POP DE
    POP BC
    OR A                        ; clear carry
    RET

; 8-bit maximal-length Galois LFSR, polynomial #1D.
; Used for lane, shape and shade; never re-seed on respawn.
NEXT_ENEMY_RANDOM:
    LD A,(ENEMY_RANDOM_STATE)
    ADD A,A
    JR NC,.STORE
    XOR #1D
.STORE:
    LD (ENEMY_RANDOM_STATE),A
    RET

; Pick one of four silhouettes and eight palettes for this spawn.
; A fresh appearance is generated on every respawn, not each frame.
; Preserves BC/DE/HL/IX; modifies AF and carry.
RANDOMIZE_ENEMY_APPEARANCE:
    PUSH BC
    CALL NEXT_ENEMY_RANDOM
    LD C,A
    AND 3
    LD (IX+E_VARIANT),A
    LD A,C
    RLCA
    RLCA
    RLCA
    AND 7
    LD (IX+E_SHADE),A
    POP BC
    RET

; -------------------------------------------------------------
; Vertical spawn clearance (before lane search).
; Require ENEMY_MIN_VERTICAL_GAP fully empty character rows
; between the new asteroid footprint and every active asteroid,
; even if their horizontal lanes differ.
; In: IX = inactive/current slot with E_TYPE and E_Y set.
; Out: carry set -> delay spawn. Preserves BC, DE, HL, IX.
; -------------------------------------------------------------
ENEMY_SPAWN_GAP_CLEAR:
    PUSH BC
    PUSH DE
    PUSH IX
    LD A,(IX+E_Y)
    LD (ENEMY_TEST_Y),A
    LD A,(IX+E_TYPE)
    LD (ENEMY_TEST_TYPE),A
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    LD A,(IX+E_ACTIVE)
    OR A
    JR Z,.SKIP

    ; Existing top >= new bottom + gap + 1? Far below.
    LD A,(ENEMY_TEST_Y)
    LD C,A
    LD A,(ENEMY_TEST_TYPE)
    ADD A,C
    ADD A,ENEMY_MIN_VERTICAL_GAP+1
    CP (IX+E_Y)
    JR C,.SKIP
    JR Z,.SKIP

    ; New top >= existing bottom + gap + 1? Far below.
    LD A,(IX+E_Y)
    LD C,A
    LD A,(IX+E_TYPE)
    ADD A,C
    ADD A,ENEMY_MIN_VERTICAL_GAP+1
    LD C,A
    LD A,(ENEMY_TEST_Y)
    CP C
    JR NC,.SKIP

    POP IX
    POP DE
    POP BC
    SCF
    RET
.SKIP:
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    POP IX
    POP DE
    POP BC
    XOR A
    RET

; Prefer an empty horizontal column between the sprite rectangles,
; to avoid multiple asteroids forming one continuous vertical line.
; This is cosmetic: caller falls back to ENEMY_SPAWN_CLEAR if needed.
; In: IX=new slot, E_X/E_TYPE already set.
; Out: carry set -> lane too near another ACTIVE asteroid.
; Preserves BC, DE, HL, IX.
ENEMY_SPAWN_LANE_CLEAR:
    PUSH BC
    PUSH DE
    PUSH IX
    LD A,(IX+E_X)
    LD (ENEMY_TEST_X),A
    LD A,(IX+E_TYPE)
    LD (ENEMY_TEST_TYPE),A
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    LD A,(IX+E_ACTIVE)
    OR A
    JR Z,.SKIP

    ; Candidate right + gap + 1 <= existing left is allowed.
    LD A,(ENEMY_TEST_X)
    LD C,A
    LD A,(ENEMY_TEST_TYPE)
    ADD A,C
    ADD A,ENEMY_MIN_LANE_GAP+1
    CP (IX+E_X)
    JR C,.SKIP
    JR Z,.SKIP

    ; Existing right + gap + 1 <= candidate left is allowed.
    LD A,(IX+E_X)
    LD C,A
    LD A,(IX+E_TYPE)
    ADD A,C
    ADD A,ENEMY_MIN_LANE_GAP+1
    LD C,A
    LD A,(ENEMY_TEST_X)
    CP C
    JR NC,.SKIP

    POP IX
    POP DE
    POP BC
    SCF
    RET
.SKIP:
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    POP IX
    POP DE
    POP BC
    XOR A
    RET

; Current candidate is in (IX+E_X), new Y is already stored in slot.
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
; after the score changes so even crossed milestones are caught.
ON_ENEMY_HIT:
    DEC (IX+E_HP)
    JR NZ,.DAMAGED
    CALL START_ENEMY_BLAST
    CALL DEACTIVATE_ENEMY
    CALL RESET_MISS_TRAVEL    ; a kill resets only the 3-screen timer
    LD A,SFX_KILL
    CALL SFX_START
    LD A,(IX+E_TYPE)
    OR A
    LD A,64
    JR Z,.AWARD
    LD A,128
.AWARD:
    JP ADD_SCORE_A
.DAMAGED:
    LD A,SFX_HIT                ; damaged large asteroid, not destroyed
    CALL SFX_START
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
    RET NZ
    LD A,(IX+E_ACTIVE)
    OR A
    RET Z

    ; Same vertical character row(s) as before.
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
    ; Half-shifted ship occupies X and X+1. Aligned ship only X.
    LD A,(IX+E_X)
    LD C,A                      ; asteroid left edge
    LD A,(SHIP_NEW_POS)
    CP C
    JR NC,.SHIP_AT_RIGHT
    ; Ship is one cell left of the asteroid: 4px overlap is possible.
    LD A,(SHIP_HALF_POS)
    OR A
    RET Z
    LD A,(SHIP_NEW_POS)
    INC A
    CP C
    RET NZ
    JR .HIT
.SHIP_AT_RIGHT:
    SUB C
    JR Z,.HIT
    CP 1
    RET NZ
    LD A,(IX+E_TYPE)
    OR A
    RET Z                      ; small asteroid is only 1 cell wide
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
    LD L,(IX+B_HALF)             ; bullet spans X and X+1 if L=1
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
    SUB (IX+E_X)               ; bullet base X minus asteroid left X
    JR C,.BULLET_LEFT
    OR A
    JR Z,.HIT
    CP 1
    JR NZ,.SKIP
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.SKIP                 ; aligned bullet right of small
    JR .HIT
.BULLET_LEFT:
    CP #FF                     ; asteroid begins one cell to right?
    JR NZ,.SKIP
    LD A,L                     ; only a half-shifted shot reaches it
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

; Bitmap table layout: 4 shapes per size, 4 rotation frames/shape.
; Index = 2 * ((TYPE*4 + VARIANT)*4 + FRAME), max 62 bytes.
; OUT: DE=bitmap address. Preserves BC, IX.
GET_ENEMY_FRAME:
    LD A,(IX+E_TYPE)
    ADD A,A
    ADD A,A                    ; 4 silhouettes per size
    ADD A,(IX+E_VARIANT)
    ADD A,A
    ADD A,A                    ; 4 frames per silhouette
    ADD A,(IX+E_FRAME)
    ADD A,A                    ; DW pointer offset
    LD E,A
    LD D,0
    LD HL,ENEMY_FRAMES
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
    RET

; OUT: DE=attribute source (1 byte small / 2 bytes large).
; Keeps HL on the destination screen address; IX/BC preserved.
GET_ENEMY_COLOUR:
    PUSH HL
    LD A,(IX+E_SHADE)
    LD E,A
    LD D,0
    LD HL,ENEMY_SMALL_COLOURS
    LD A,(IX+E_TYPE)
    OR A
    JR Z,.LOOKUP
    SLA E                       ; large palette: two attributes/pair
    LD HL,ENEMY_LARGE_COLOURS
.LOOKUP:
    ADD HL,DE
    EX DE,HL
    POP HL
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
    CALL GET_ENEMY_COLOUR
    LD A,(IX+E_TYPE)
    OR A
    JR NZ,.ATTR_WIDE
    CALL RESTORE_ATTR_1_1
    JR .SPRITE
.ATTR_WIDE:
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

; ===== boss.asm =====
; -------------------------------------------------------------
; SpaceCan Step 22: centered 3x2 demo boss at DEMO_BOSS_SCORE.
; Its separate state survives a lost player life; the current boss
; battle is the DEMO END. Future shooters will precede this battle.
; -------------------------------------------------------------

MAYBE_START_BOSS:
    LD A,(BOSS_STARTED)
    OR A
    RET NZ
    LD DE,DEMO_BOSS_SCORE & #FFFF
    LD A,DEMO_BOSS_SCORE >> 16
    CALL SCORE_AT_LEAST
    RET C                          ; before configured score threshold
    JP START_BOSS_PHASE

START_BOSS_PHASE:
    LD A,1
    LD (BOSS_STARTED),A
    LD A,BOSS_MAX_HP
    LD (BOSS_HP),A
    CALL BOSS_DISABLE_ASTEROIDS
    CALL RESET_HOSTILE_BULLETS
    ; An asteroid killed at the score threshold may still be exploding.
    ; Let the normal renderer erase its last frame before boss entry.
    XOR A
    LD (BLAST_ACTIVE),A
    LD A,1
    LD (BLAST_DIRTY),A
    XOR A
    LD (SHOOT_WARNING_ACTIVE),A
    LD (MISS_TRAVEL_ROWS),A
    LD A,1
    LD (GAUGE_DIRTY),A
    JP BOSS_RESET_ENTRY

; Restart boss encounter after ship death, preserving damage/HP.
BOSS_RESET_ENTRY:
    CALL BOSS_DISABLE_ASTEROIDS
    LD A,BOSS_X_CENTER
    LD (BOSS_X),A
    LD A,BOSS_START_Y
    LD (BOSS_Y),A
    XOR A
    LD (BOSS_DRAWN),A
    LD (BOSS_FRAME),A
    LD A,BOSS_ENTRY_DELAY
    LD (BOSS_ENTRY_TIMER),A
    LD A,BOSS_ANIM_DELAY
    LD (BOSS_ANIM_TIMER),A
    LD A,BOSS_FIRE_DELAY
    LD (BOSS_FIRE_TIMER),A
    LD A,1
    LD (BOSS_ACTIVE),A
    LD (BOSS_DIRTY),A
    LD (GAUGE_DIRTY),A
    LD A,STATE_BOSS
    LD (GAME_STATE),A
    RET

; Leave DRAWN flag alone: renderer must erase old asteroid pixels.
BOSS_DISABLE_ASTEROIDS:
    PUSH BC
    PUSH DE
    PUSH IX
    LD IX,ENEMY_POOL
    LD B,MAX_ENEMIES
.NEXT:
    XOR A
    LD (IX+E_ACTIVE),A
    LD A,1
    LD (IX+E_DIRTY),A
    LD DE,ENEMY_SLOT_SIZE
    ADD IX,DE
    DJNZ .NEXT
    POP IX
    POP DE
    POP BC
    RET

UPDATE_BOSS:
    LD A,(BOSS_ACTIVE)
    OR A
    RET Z
    ; Boss descends to the center before starting to fire.
    LD A,(BOSS_Y)
    CP BOSS_TARGET_Y
    JR NC,.CENTERED
    LD HL,BOSS_ENTRY_TIMER
    DEC (HL)
    RET NZ
    LD (HL),BOSS_ENTRY_DELAY
    LD HL,BOSS_Y
    INC (HL)
    LD A,1
    LD (BOSS_DIRTY),A
    RET
.CENTERED:
    LD HL,BOSS_ANIM_TIMER
    DEC (HL)
    JR NZ,.FIRE
    LD (HL),BOSS_ANIM_DELAY
    LD HL,BOSS_FRAME
    LD A,(HL)
    XOR 1
    LD (HL),A
    LD A,1
    LD (BOSS_DIRTY),A
.FIRE:
    LD HL,BOSS_FIRE_TIMER
    DEC (HL)
    RET NZ
    LD (HL),BOSS_FIRE_DELAY
    JP BOSS_FIRE_PAIR

; Two muzzles, left and right outside the cockpit.
BOSS_FIRE_PAIR:
    LD A,(BOSS_Y)
    ADD A,2
    LD B,A
    LD A,(BOSS_X)
    LD C,A
    CALL SPAWN_HOSTILE_BULLET     ; preserves BC
    LD A,(BOSS_X)
    ADD A,2
    LD C,A
    JP SPAWN_HOSTILE_BULLET

; IN IX=player bullet. CARRY SET iff bullet consumed on boss.
CHECK_BULLET_BOSS:
    LD A,(BOSS_ACTIVE)
    OR A
    JR Z,.MISS
    LD A,(IX+B_Y)
    LD C,A
    LD A,(BOSS_Y)
    CP C
    JR Z,.CHECK_X
    INC A
    CP C
    JR NZ,.MISS
.CHECK_X:
    LD A,(IX+B_X)
    LD C,A
    LD A,(BOSS_X)
    LD D,A
    LD A,C
    SUB D
    JR C,.LEFT
    CP 3
    JR NC,.MISS
    JR .HIT
.LEFT:
    CP #FF
    JR NZ,.MISS
    LD A,(IX+B_HALF)
    OR A
    JR Z,.MISS
.HIT:
    ; The boss must reach the centre before its HP can be damaged.
    ; Shots during entry hit the armour but do not reduce its gauge.
    LD A,(BOSS_Y)
    CP BOSS_TARGET_Y
    CALL Z,BOSS_TAKE_HIT
    CALL DEACTIVATE_BULLET
    SCF
    RET
.MISS:
    OR A
    RET

; The same gauge holds 10 boss HP. Each player hit removes one.
BOSS_TAKE_HIT:
    LD HL,BOSS_HP
    LD A,(HL)
    OR A
    RET Z
    DEC (HL)
    LD A,1
    LD (GAUGE_DIRTY),A
    LD (BOSS_DIRTY),A
    LD A,(HL)
    OR A
    JR Z,.DEFEATED
    LD A,SFX_HIT
    JP SFX_START
.DEFEATED:
    XOR A
    LD (BOSS_ACTIVE),A
    LD A,STATE_VICTORY
    LD (GAME_STATE),A
    LD A,SFX_KILL
    JP SFX_START

RENDER_ERASE_BOSS:
    LD A,(BOSS_DIRTY)
    OR A
    RET Z
    LD A,(BOSS_DRAWN)
    OR A
    JR Z,.NEW
    LD A,(BOSS_DRAW_Y)
    LD B,A
    LD A,(BOSS_DRAW_X)
    LD C,A
    LD DE,#0302
    CALL STARFIELD_MARK_RECT
    XOR A
    LD (BOSS_DRAWN),A
.NEW:
    LD A,(BOSS_ACTIVE)
    OR A
    RET Z
    LD A,(BOSS_Y)
    LD B,A
    LD A,(BOSS_X)
    LD C,A
    LD DE,#0302
    JP STARFIELD_MARK_RECT

RENDER_DRAW_BOSS:
    LD A,(BOSS_DIRTY)
    OR A
    RET Z
    XOR A
    LD (BOSS_DIRTY),A
    LD A,(BOSS_ACTIVE)
    OR A
    RET Z
    LD A,(BOSS_FRAME)
    OR A
    LD DE,BOSS_SPRITE_0
    JR Z,.TOP
    LD DE,BOSS_SPRITE_1
.TOP:
    XOR A
    CALL DRAW_BOSS_ROW
    LD A,(BOSS_FRAME)
    OR A
    LD DE,BOSS_SPRITE_0+24
    JR Z,.BOTTOM
    LD DE,BOSS_SPRITE_1+24
.BOTTOM:
    LD A,1
    CALL DRAW_BOSS_ROW
    LD A,(BOSS_X)
    LD (BOSS_DRAW_X),A
    LD A,(BOSS_Y)
    LD (BOSS_DRAW_Y),A
    LD A,1
    LD (BOSS_DRAWN),A
    RET

; A=0/1 row, DE=24 bitmap bytes of that row, width 3 cells.
; No special renderer: 3 direct bitmap writes x 8 scan lines.
DRAW_BOSS_ROW:
    PUSH DE
    LD B,A                        ; row offset 0 or 1
    LD A,(BOSS_Y)
    ADD A,B
    LD B,A                        ; absolute screen Y
    LD A,(BOSS_X)
    LD C,A
    CALL GET_SCREEN_ADDR
    PUSH HL
    LD A,H
    RRCA
    RRCA
    RRCA
    AND 3
    OR #58
    LD H,A
    LD A,#45                     ; bright cyan wings
    LD (HL),A
    INC L
    LD A,#42                     ; red cockpit
    LD (HL),A
    INC L
    LD A,#45
    LD (HL),A
    POP HL
    POP DE
    LD B,8
.PIXEL:
    LD A,(DE)
    LD (HL),A
    INC DE
    INC L
    LD A,(DE)
    LD (HL),A
    INC DE
    INC L
    LD A,(DE)
    LD (HL),A
    INC DE
    DEC L
    DEC L
    INC H
    DJNZ .PIXEL
    RET

; Two 24x16 frames; 3 bytes per scanline, 48 bytes each.
BOSS_SPRITE_0:
    DB #80,#00,#01
    DB #C0,#18,#03
    DB #E1,#3C,#87
    DB #FB,#7E,#DF
    DB #FF,#FF,#FF
    DB #7F,#FF,#FE
    DB #37,#E7,#EC
    DB #3F,#FF,#FC
    DB #3F,#FF,#FC
    DB #1F,#FF,#F8
    DB #0F,#DB,#F0
    DB #07,#BD,#E0
    DB #03,#FF,#C0
    DB #03,#7E,#C0
    DB #02,#3C,#40
    DB #02,#18,#40

BOSS_SPRITE_1:
    DB #80,#00,#01
    DB #C1,#18,#83
    DB #E3,#3C,#C7
    DB #FB,#7E,#DF
    DB #FF,#FF,#FF
    DB #7F,#E7,#FE
    DB #37,#FF,#EC
    DB #3F,#DB,#FC
    DB #3F,#DB,#FC
    DB #1F,#FF,#F8
    DB #0F,#FF,#F0
    DB #07,#BD,#E0
    DB #03,#FF,#C0
    DB #03,#7E,#C0
    DB #02,#3C,#40
    DB #02,#18,#40

; ===== starfield.asm =====
; -------------------------------------------------------------
; STARFIELD: 16 moving single-pixel stars, two slower layers.
;
; Record: X character cell, Y pixel, pixel bit mask, period mask.
; Period 1: +1..3 pixels every 2 frames.
; Period 3: +1..3 pixels every 4 frames.
; Half-speed stages alternate +1/+2 or +2/+3 pixel steps.
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
    ; Smooth stages 1,1.5,2,2.5,3 using STAR_CLOCK bit 2.
    LD A,(SCROLL_SPEED)
    LD C,A
    LD A,(SPEED_LEVEL)
    AND 1
    JR Z,.STEP_READY
    LD A,(STAR_CLOCK)
    AND 4
    JR Z,.STEP_READY
    INC C
.STEP_READY:
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
    LD DE,#0101                ; aligned 8px -> 1 cell
    LD A,(SHIP_CUR_HALF)
    OR A
    JR Z,.TEST_SHIP
    LD D,2                     ; shifted 8px -> 2 cells
.TEST_SHIP:
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
    JR NZ,.BLAST_WIDE
    LD A,(BLAST_OWNER)
    OR A
    JR Z,.BLAST_RECT
    LD A,(BLAST_HALF)
    OR A
    JR Z,.BLAST_RECT
.BLAST_WIDE:
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
    LD DE,#0101
    LD A,(IX+B_DRAW_HALF)
    OR A
    JR Z,.BULLET_RECT
    LD D,2
.BULLET_RECT:
    CALL STARFIELD_TEST_RECT
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

    ; Invalidate stationary boss / hostile shots touched by stars.
    LD A,(BOSS_DRAWN)
    OR A
    JR Z,.HOSTILE
    LD A,(BOSS_DRAW_Y)
    LD B,A
    LD A,(BOSS_DRAW_X)
    LD C,A
    LD DE,#0302
    CALL STARFIELD_TEST_RECT
    OR A
    JR Z,.HOSTILE
    LD A,1
    LD (BOSS_DIRTY),A

.HOSTILE:
    LD A,(BOSS_STARTED)
    OR A
    RET Z
    LD IX,HOSTILE_BULLET_POOL
    LD B,MAX_HOSTILE_BULLETS
.NEXT_HOSTILE:
    PUSH BC
    LD A,(IX+HB_DRAWN)
    OR A
    JR Z,.SKIP_HOSTILE
    LD B,(IX+HB_DRAW_Y)
    LD C,(IX+HB_DRAW_X)
    LD DE,#0101
    CALL STARFIELD_TEST_RECT
    OR A
    JR Z,.SKIP_HOSTILE
    LD A,1
    LD (IX+HB_DIRTY),A
.SKIP_HOSTILE:
    POP BC
    LD DE,HOSTILE_BULLET_SIZE
    ADD IX,DE
    DJNZ .NEXT_HOSTILE
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
    CALL RENDER_ERASE_HOSTILE_BULLETS
    CALL RENDER_ERASE_ENEMIES
    CALL RENDER_ERASE_BOSS

    LD A,(SHIP_DIRTY)
    OR A
    JR Z,.SHIP_ERASE_DONE
    LD A,(SHIP_DRAWN)
    OR A
    CALL NZ,ERASE_SHIP
    XOR A
    LD (SHIP_DRAWN),A
.SHIP_ERASE_DONE:
    ; Rebuild stars in any newly touched ship cell as well.
    ; Without this, directly writing the 8x8/12x8 bitmap could
    ; erase star pixels in the destination without restoring them.
    LD A,(SHIP_DIRTY)
    OR A
    JR Z,.SHIP_NEW_DONE
    LD A,(SHIP_VISIBLE)
    OR A
    JR Z,.SHIP_NEW_DONE
    LD BC,(SHIP_NEW_POS)
    LD DE,#0101
    LD A,(SHIP_HALF_POS)
    OR A
    JR Z,.MARK_NEW
    LD D,2
.MARK_NEW:
    CALL STARFIELD_MARK_RECT
.SHIP_NEW_DONE:
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
    LD A,(SHIP_HALF_POS)
    LD (SHIP_CUR_HALF),A
    LD A,1
    LD (SHIP_DRAWN),A
.SHIP_DONE:
    CALL RENDER_DRAW_ENEMIES
    CALL RENDER_DRAW_BOSS
    CALL RENDER_DRAW_BULLETS
    CALL RENDER_DRAW_HOSTILE_BULLETS

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
    
; A four-pixel horizontal shift splits each source byte in two.
; RRCA x4 swaps nibbles: low nibble -> first cell's right side,
; high nibble -> second cell's left side.
; IN HL=top-left bitmap byte, DE=8 sprite rows.
; OUT: 8 rows of 2 screen bytes. Clobbers AF, BC, DE, HL.
DRAW_SHIFT4_1_1:
    LD B,8
.ROW:
    LD A,(DE)
    RRCA
    RRCA
    RRCA
    RRCA
    LD C,A
    AND #0F
    LD (HL),A                   ; pixel columns 4..7 in first cell
    INC L
    LD A,C
    AND #F0
    LD (HL),A                   ; columns 0..3 in second cell
    DEC L
    INC H
    INC DE
    DJNZ .ROW
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

; ===== ui.asm =====
; -------------------------------------------------------------
; SpaceCan Step 21: HUD + blinking SHOOT! warning after 1 missed screen.
; RLE artwork is unpacked once; only HUD numerals/attributes change.
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
    ; Middle window Y=2, X=14..17: four heart sprites.
    ; Right window Y=2, X=25..30: 6 score digits, without label.

    ; Gauge at Y=3, X=11..20, centered over the corridor.
    ; Its bitmap is static; only the 10 attribute bytes change.
    CALL DRAW_PRESSURE_BAR

    ; Save original Y=2, X=13..18 pixels/attrs (between hearts and
    ; gauge); flashing text must not destroy the .SCR decoration.
    JP SAVE_SHOOT_BACKGROUND

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

; Dynamic HUD updates only when values change.
RENDER_HUD:
    LD A,(HUD_DIRTY)
    OR A
    JR Z,.GAUGE
    XOR A
    LD (HUD_DIRTY),A

    ; Left window: 1 / 1.5 / 2 / 2.5 / 3, clearing the old suffix.
    LD A,(SCROLL_SPEED)
    ADD A,'0'
    LD BC,#0207
    CALL DRAW_CHAR_AT
    LD A,(SPEED_LEVEL)
    AND 1
    JR Z,.WHOLE_SPEED
    LD A,'.'
    LD BC,#0208
    CALL DRAW_CHAR_AT
    LD A,'5'
    JR .SPEED_SUFFIX
.WHOLE_SPEED:
    LD A,' '
    LD BC,#0208
    CALL DRAW_CHAR_AT
    LD A,' '
.SPEED_SUFFIX:
    LD BC,#0209
    CALL DRAW_CHAR_AT

    ; Middle window: 4 filled/hollow hearts at X=14..17.
    CALL DRAW_LIVES_HEARTS

    ; Right window: six actual decimal digits, 000000..999999.
    LD BC,#0219                  ; Y=2, X=25
    CALL PRINT_DEC6
.GAUGE:
    LD A,(GAUGE_DIRTY)
    OR A
    JR Z,.WARNING
    XOR A
    LD (GAUGE_DIRTY),A
    CALL RENDER_PRESSURE_GAUGE
.WARNING:
    ; Called every active game frame, independent of HUD_DIRTY.
    JP RENDER_SHOOT_WARNING

; Warning between hearts (actual draw row Y=1) and gauge (Y=3).
; No bitmap writes from IM2: blink in the foreground, paused game freezes.
; OFF restores exact bitmap and attributes, rather than painting spaces.
RENDER_SHOOT_WARNING:
    LD A,(SHOOT_WARNING_ACTIVE)
    OR A
    JR Z,.HIDE
    LD A,(GAME_STATE)
    CP STATE_PLAYING
    JR NZ,.HIDE
    LD HL,SHOOT_BLINK_COUNTER
    LD A,(HL)                    ; show 0..15, hide 16..31
    INC (HL)
    AND SHOOT_BLINK_MASK
    JR NZ,.HIDE
    LD A,(SHOOT_VISIBLE)
    OR A
    RET NZ                       ; no redraw on an unchanged blink frame
    LD A,1
    LD (SHOOT_VISIBLE),A
    LD BC,SHOOT_TEXT_Y*256+SHOOT_TEXT_X
    LD DE,HUD_LABEL_SHOOT
    CALL PRINT_TEXT
    LD HL,#5800+SHOOT_TEXT_Y*32+SHOOT_TEXT_X
    LD B,SHOOT_TEXT_WIDTH
    LD A,#46                     ; bright yellow on black
.ATTR:
    LD (HL),A
    INC HL
    DJNZ .ATTR
    RET
.HIDE:
    LD A,(SHOOT_VISIBLE)
    OR A
    RET Z
    XOR A
    LD (SHOOT_VISIBLE),A
    JP RESTORE_SHOOT_BACKGROUND

; Capture the six cells directly from the original .SCR HUD.
; Called every DRAW_STATIC_UI, including after respawn/Game Over.
SAVE_SHOOT_BACKGROUND:
    LD DE,SHOOT_SAVED_BITMAP
    LD C,SHOOT_TEXT_X
    LD A,SHOOT_TEXT_WIDTH
.NEXT_CELL:
    PUSH AF
    PUSH BC
    LD B,SHOOT_TEXT_Y
    CALL GET_SCREEN_ADDR
    LD B,8
.NEXT_ROW:
    LD A,(HL)
    LD (DE),A
    INC DE
    INC H
    DJNZ .NEXT_ROW
    POP BC
    INC C
    POP AF
    DEC A
    JR NZ,.NEXT_CELL
    LD HL,#5800+SHOOT_TEXT_Y*32+SHOOT_TEXT_X
    LD DE,SHOOT_SAVED_ATTR
    LD BC,SHOOT_TEXT_WIDTH
    LDIR
    XOR A
    LD (SHOOT_VISIBLE),A
    RET

; Recover all original pixels/attrs underneath the word.
RESTORE_SHOOT_BACKGROUND:
    LD DE,SHOOT_SAVED_BITMAP
    LD C,SHOOT_TEXT_X
    LD A,SHOOT_TEXT_WIDTH
.NEXT_CELL:
    PUSH AF
    PUSH BC
    LD B,SHOOT_TEXT_Y
    CALL GET_SCREEN_ADDR
    LD B,8
.NEXT_ROW:
    LD A,(DE)
    LD (HL),A
    INC DE
    INC H
    DJNZ .NEXT_ROW
    POP BC
    INC C
    POP AF
    DEC A
    JR NZ,.NEXT_CELL
    LD HL,SHOOT_SAVED_ATTR
    LD DE,#5800+SHOOT_TEXT_Y*32+SHOOT_TEXT_X
    LD BC,SHOOT_TEXT_WIDTH
    LDIR
    RET

; Draw four hearts in Y=1, X=14..17. Each slot index is compared
; to remaining SHIP_LIVES; lost lives remain visible as outlines.
DRAW_LIVES_HEARTS:
    LD C,14
    LD A,START_LIVES
.NEXT_HEART:
    PUSH AF
    PUSH BC
    LD B,1
    CALL GET_SCREEN_ADDR
    LD A,(SHIP_LIVES)
    ADD A,14
    CP C
    JR C,.SPENT
    JR Z,.SPENT
    LD DE,HEART_FILLED
    PUSH DE
    LD DE,HEART_ACTIVE_ATTR
    CALL RESTORE_ATTR_1_1
    POP DE
    JR .DRAW
.SPENT:
    LD DE,HEART_OUTLINE
    PUSH DE
    LD DE,HEART_SPENT_ATTR
    CALL RESTORE_ATTR_1_1
    POP DE
.DRAW:
    CALL DRAW_1_1
    POP BC
    INC C
    POP AF
    DEC A
    JR NZ,.NEXT_HEART
    RET

; Print a narrow bright pixel bar in the topmost corridor border.
; First clear the original .SCR bitmap in exactly 10 cells, then
; draw a fixed 8-row glyph to give each attribute its own visible bar.
DRAW_PRESSURE_BAR:
    LD C,11                      ; centered 10 cells (X=11..20)
    LD A,PRESSURE_SEGMENTS
.NEXT:
    PUSH AF
    PUSH BC
    LD B,3                       ; directly above playfield top (Y=4)
    CALL GET_SCREEN_ADDR
    LD DE,PRESSURE_SEGMENT_PIXELS
    CALL DRAW_1_1
    POP BC
    INC C
    POP AF
    DEC A
    JR NZ,.NEXT
    XOR A
    LD (GAUGE_DIRTY),A
    JP RENDER_PRESSURE_GAUGE

; Only 10 attribute writes per penalty. Green on the left,
; red grows from the RIGHT. Full red is shown during the blast.
RENDER_PRESSURE_GAUGE:
    LD A,(BOSS_STARTED)
    OR A
    JR Z,.PRESSURE
    ; Boss HP repurposes the ten green/red penalty segments.
    LD A,(BOSS_HP)
    LD B,A
    LD C,PRESSURE_SEGMENTS
    LD HL,#5800+3*32+11
.BOSS_NEXT:
    LD A,C
    CP B
    JR C,.BOSS_ALIVE
    JR Z,.BOSS_ALIVE
    LD A,#42                     ; red = depleted boss health
    JR .BOSS_STORE
.BOSS_ALIVE:
    LD A,#45                     ; bright cyan = remaining boss HP
.BOSS_STORE:
    LD (HL),A
    INC HL
    DEC C
    JR NZ,.BOSS_NEXT
    RET
.PRESSURE:
    LD A,(PRESSURE_LEVEL)
    LD B,A
    LD C,PRESSURE_SEGMENTS
    LD HL,#5800+3*32+11
.NEXT:
    LD A,C
    CP B
    JR C,.RED
    JR Z,.RED
    LD A,#44                     ; bright green ink / black paper
    JR .STORE
.RED:
    LD A,#42                     ; bright red ink / black paper
.STORE:
    LD (HL),A
    INC HL
    DEC C
    JR NZ,.NEXT
    RET

PRESSURE_SEGMENT_PIXELS:
    DB #00,#7E,#7E,#7E,#7E,#7E,#7E,#00

; Draw six digits of 24-bit SCORE (little endian) in decimal.
; IN BC=YX of first digit. Scratch is SCORE_PRINT_WORK; SCORE is kept.
; This routine runs only on HUD updates or in Game Over.
PRINT_DEC6:
    LD HL,(SCORE)
    LD (SCORE_PRINT_WORK),HL
    LD A,(SCORE+2)
    LD (SCORE_PRINT_WORK+2),A
    LD IX,SCORE_DECIMAL_PLACES
    LD A,5                        ; five 24-bit divisors, then units
.NEXT_PLACE:
    PUSH AF
    CALL PRINT_DEC24_PLACE
    LD DE,3
    ADD IX,DE
    POP AF
    DEC A
    JR NZ,.NEXT_PLACE
    LD A,(SCORE_PRINT_WORK)       ; final remainder is 0..9
    ADD A,'0'
    JP DRAW_CHAR_AT

; IN IX -> three-byte divisor, BC=YX. Draws one digit, increments C.
; Each place subtracts at most nine times. Preserves IX and B.
PRINT_DEC24_PLACE:
    LD D,'0'
.TRY:
    LD A,(SCORE_PRINT_WORK+2)
    CP (IX+2)
    JR C,.WRITE
    JR NZ,.SUBTRACT
    LD A,(SCORE_PRINT_WORK+1)
    CP (IX+1)
    JR C,.WRITE
    JR NZ,.SUBTRACT
    LD A,(SCORE_PRINT_WORK)
    CP (IX+0)
    JR C,.WRITE
.SUBTRACT:
    LD A,(SCORE_PRINT_WORK)
    SUB (IX+0)
    LD (SCORE_PRINT_WORK),A
    LD A,(SCORE_PRINT_WORK+1)
    SBC A,(IX+1)
    LD (SCORE_PRINT_WORK+1),A
    LD A,(SCORE_PRINT_WORK+2)
    SBC A,(IX+2)
    LD (SCORE_PRINT_WORK+2),A
    INC D
    JR .TRY
.WRITE:
    LD A,D
    PUSH BC
    CALL DRAW_CHAR_AT
    POP BC
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
SHIP_ATTR_PAIR:
    DB #46,#46                  ; when shifted, ship spans 2 cells
SHIP_CUR_POS:
    DB 15,22                   ; last drawn character X / Y
SHIP_CUR_HALF:
    DB 0                       ; last drawn 4px offset (0 or 1)
SHIP_NEW_POS:
    DB 15,22                   ; logical base cell X / Y
SHIP_HALF_POS:
    DB 0                       ; current 4px offset (0 or 1)
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
MISS_TRAVEL_ROWS:
    DB 0                        ; 0..59 asteroid-movement rows since last kill
MISS_KILLED_THIS_TICK:
    DB 0                        ; don't count the movement before a kill
PRESSURE_LEVEL:
    DB 0                        ; 0..10, persistent red segments right-to-left
BOSS_STARTED:         DB 0      ; boss phase reached this game
BOSS_ACTIVE:          DB 0
BOSS_HP:              DB 0      ; 10 HP shown by shared gauge
BOSS_X:               DB BOSS_X_CENTER
BOSS_Y:               DB BOSS_START_Y
BOSS_DRAWN:           DB 0
BOSS_DRAW_X:          DB BOSS_X_CENTER
BOSS_DRAW_Y:          DB BOSS_START_Y
BOSS_DIRTY:           DB 0
BOSS_ENTRY_TIMER:     DB BOSS_ENTRY_DELAY
BOSS_ANIM_TIMER:      DB BOSS_ANIM_DELAY
BOSS_FRAME:           DB 0
BOSS_FIRE_TIMER:      DB BOSS_FIRE_DELAY
HOSTILE_BULLET_CLOCK: DB HOSTILE_MOVE_DELAY
HOSTILE_BULLET_POOL:  DS MAX_HOSTILE_BULLETS*HOSTILE_BULLET_SIZE,0
SHOOT_WARNING_ACTIVE:
    DB 0                        ; latch after >=20 travel rows; clear on kill/life
SHOOT_VISIBLE:
    DB 0                        ; screen currently contains SHOOT! text
SHOOT_BLINK_COUNTER:
    DB 0                        ; increments only while warning/play active
SHOOT_SAVED_BITMAP:
    DS SHOOT_TEXT_WIDTH*8,0      ; original 48 HUD pixel bytes
SHOOT_SAVED_ATTR:
    DS SHOOT_TEXT_WIDTH,0        ; original six attributes
PAUSE_KEY_HELD:
    DB 1                        ; ENTER edge latch (1 while entering game)
PAUSE_PREVIOUS_STATE:
    DB STATE_PLAYING            ; playing or exploding before pause
PAUSE_SAVED_BITMAP:
    DS PAUSE_TEXT_WIDTH*8,0     ; pixel bytes underneath "PAUSED"
PAUSE_SAVED_ATTR:
    DS PAUSE_TEXT_WIDTH,0       ; exact attributes for screen restore
SHIP_MOVE_TIMER:
    DB 0                        ; frames until next horizontal step

; On a new game OR after a ship explosion, all asteroids start
; a fresh approach at the TOP, never next to the respawned ship.
; TYPE, ENTRY_Y, ANIM_PHASE, START_DELAY (50 Hz game frames).
; The first asteroid starts now; the other three join at intervals.
; This keeps at least 3 empty rows between successive arrivals.
ENEMY_START_TABLE:
    DB 0,PLAYFIELD_TOP,1,0       ; small: immediate, Y=4
    DB 1,PLAYFIELD_TOP,3,20      ; large: after 20 ticks, Y=4..5
    DB 0,PLAYFIELD_TOP,5,40      ; small: after 40 ticks
    DB 1,PLAYFIELD_TOP,7,60      ; large: after 60 ticks

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

; Every spawned asteroid picks one of eight shades. The 16x16
; asteroid uses a dim/bright pair of attributes for a two-tone look.
; Attribute values: bright bit #40, paper 0 (black), ink 0..7.
ENEMY_SMALL_COLOURS:
    DB #07,#47,#05,#45,#03,#43,#06,#46
    ; gray, white, dark cyan, cyan, dark violet, violet, ochre, gold

ENEMY_LARGE_COLOURS:
    DB #07,#47                   ; slate + ice
    DB #47,#07                   ; ice + slate
    DB #05,#45                   ; blue-green
    DB #45,#05
    DB #03,#43                   ; purple
    DB #43,#03
    DB #06,#46                   ; golden rock
    DB #46,#06

ENEMY_FRAMES:
    ; SMALL: [0] classic, [1] chipped, [2] crater, [3] splinter.
    ; Each group has four clockwise-rotation frames.
    DW ENEMY_SMALL_0,ENEMY_SMALL_1,ENEMY_SMALL_2,ENEMY_SMALL_3
    DW ENEMY_SMALL_CHIP_0,ENEMY_SMALL_CHIP_1,ENEMY_SMALL_CHIP_2,ENEMY_SMALL_CHIP_3
    DW ENEMY_SMALL_CRATER_0,ENEMY_SMALL_CRATER_1,ENEMY_SMALL_CRATER_2,ENEMY_SMALL_CRATER_3
    DW ENEMY_SMALL_SPLINTER_0,ENEMY_SMALL_SPLINTER_1,ENEMY_SMALL_SPLINTER_2,ENEMY_SMALL_SPLINTER_3
    ; LARGE: [0] classic, [1] jagged, [2] crater, [3] shard.
    DW ENEMY_LARGE_0,ENEMY_LARGE_1,ENEMY_LARGE_2,ENEMY_LARGE_3
    DW ENEMY_LARGE_JAGGED_0,ENEMY_LARGE_JAGGED_1,ENEMY_LARGE_JAGGED_2,ENEMY_LARGE_JAGGED_3
    DW ENEMY_LARGE_CRATER_0,ENEMY_LARGE_CRATER_1,ENEMY_LARGE_CRATER_2,ENEMY_LARGE_CRATER_3
    DW ENEMY_LARGE_SHARD_0,ENEMY_LARGE_SHARD_1,ENEMY_LARGE_SHARD_2,ENEMY_LARGE_SHARD_3

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


; Additional asteroid silhouettes. Rotation frames are precomputed
; OFFLINE; the Z80 still draws directly without shifts or masks.
ENEMY_SMALL_CHIP_0:
    DB %00111000
    DB %01111100
    DB %11111110
    DB %11110111
    DB %01111111
    DB %00101110
    DB %00011100
    DB %00001000
ENEMY_SMALL_CHIP_1:
    DB %00001100
    DB %00011110
    DB %00111111
    DB %01011111
    DB %11110111
    DB %01111110
    DB %00111100
    DB %00011000
ENEMY_SMALL_CHIP_2:
    DB %00010000
    DB %00111000
    DB %01110100
    DB %11111110
    DB %11101111
    DB %01111111
    DB %00111110
    DB %00011100
ENEMY_SMALL_CHIP_3:
    DB %00011000
    DB %00111100
    DB %01111110
    DB %11101111
    DB %11111010
    DB %11111100
    DB %01111000
    DB %00110000
ENEMY_SMALL_CRATER_0:
    DB %00011000
    DB %01111110
    DB %11100111
    DB %11000011
    DB %11010011
    DB %11100111
    DB %01111110
    DB %00011000
ENEMY_SMALL_CRATER_1:
    DB %00111100
    DB %01111110
    DB %01100110
    DB %11010011
    DB %11000011
    DB %01100110
    DB %01111110
    DB %00111100
ENEMY_SMALL_CRATER_2:
    DB %00011000
    DB %01111110
    DB %11100111
    DB %11001011
    DB %11000011
    DB %11100111
    DB %01111110
    DB %00011000
ENEMY_SMALL_CRATER_3:
    DB %00111100
    DB %01111110
    DB %01100110
    DB %11000011
    DB %11001011
    DB %01100110
    DB %01111110
    DB %00111100
ENEMY_SMALL_SPLINTER_0:
    DB %00100100
    DB %01111100
    DB %11111110
    DB %01101111
    DB %11111110
    DB %00111100
    DB %01111110
    DB %00010100
ENEMY_SMALL_SPLINTER_1:
    DB %00010100
    DB %01011110
    DB %01111111
    DB %11110110
    DB %01111110
    DB %11111111
    DB %01011100
    DB %00001000
ENEMY_SMALL_SPLINTER_2:
    DB %00101000
    DB %01111110
    DB %00111100
    DB %01111111
    DB %11110110
    DB %01111111
    DB %00111110
    DB %00100100
ENEMY_SMALL_SPLINTER_3:
    DB %00010000
    DB %00111010
    DB %11111111
    DB %01111110
    DB %01101111
    DB %11111110
    DB %01111010
    DB %00101000
ENEMY_LARGE_JAGGED_0:
    DB #03,#80
    DB #0F,#C0
    DB #1F,#E0
    DB #3E,#F0
    DB #7F,#F8
    DB #FF,#FC
    DB #7F,#FE
    DB #3F,#FF
    DB #1F,#FF
    DB #0F,#FE
    DB #3F,#FC
    DB #7F,#F8
    DB #6F,#F0
    DB #3F,#E0
    DB #1F,#80
    DB #06,#00
ENEMY_LARGE_JAGGED_1:
    DB #00,#20
    DB #18,#70
    DB #3C,#F8
    DB #6D,#FC
    DB #7F,#FE
    DB #FF,#FE
    DB #FF,#FF
    DB #7F,#F7
    DB #7F,#FF
    DB #3F,#FE
    DB #3F,#FC
    DB #1F,#F8
    DB #0F,#F0
    DB #07,#E0
    DB #03,#C0
    DB #01,#80
ENEMY_LARGE_JAGGED_2:
    DB #00,#60
    DB #01,#F8
    DB #07,#FC
    DB #0F,#F6
    DB #1F,#FE
    DB #3F,#FC
    DB #7F,#F0
    DB #FF,#F8
    DB #FF,#FC
    DB #7F,#FE
    DB #3F,#FF
    DB #1F,#FE
    DB #0F,#7C
    DB #07,#F8
    DB #03,#F0
    DB #01,#C0
ENEMY_LARGE_JAGGED_3:
    DB #01,#80
    DB #03,#C0
    DB #07,#E0
    DB #0F,#F0
    DB #1F,#F8
    DB #3F,#FC
    DB #7F,#FC
    DB #FF,#FE
    DB #EF,#FE
    DB #FF,#FF
    DB #7F,#FF
    DB #7F,#FE
    DB #3F,#B6
    DB #1F,#3C
    DB #0E,#18
    DB #04,#00
ENEMY_LARGE_CRATER_0:
    DB #07,#C0
    DB #1F,#F0
    DB #3F,#F8
    DB #7F,#FC
    DB #FF,#FE
    DB #F8,#3F
    DB #F0,#1F
    DB #E0,#0F
    DB #E0,#1F
    DB #F0,#3F
    DB #F8,#7E
    DB #7F,#FE
    DB #3F,#FC
    DB #1F,#F8
    DB #0F,#E0
    DB #03,#80
ENEMY_LARGE_CRATER_1:
    DB #07,#F0
    DB #0F,#F8
    DB #1F,#FC
    DB #3E,#7E
    DB #7C,#3E
    DB #78,#1F
    DB #F8,#1F
    DB #F8,#1F
    DB #F8,#1F
    DB #7C,#1F
    DB #7E,#3E
    DB #3F,#7E
    DB #3F,#FC
    DB #1F,#F8
    DB #0F,#F0
    DB #03,#E0
ENEMY_LARGE_CRATER_2:
    DB #01,#C0
    DB #07,#F0
    DB #1F,#F8
    DB #3F,#FC
    DB #7F,#FE
    DB #7E,#1F
    DB #FC,#0F
    DB #F8,#07
    DB #F0,#07
    DB #F8,#0F
    DB #FC,#1F
    DB #7F,#FF
    DB #3F,#FE
    DB #1F,#FC
    DB #0F,#F8
    DB #03,#E0
ENEMY_LARGE_CRATER_3:
    DB #07,#C0
    DB #0F,#F0
    DB #1F,#F8
    DB #3F,#FC
    DB #7E,#FC
    DB #7C,#7E
    DB #F8,#3E
    DB #F8,#1F
    DB #F8,#1F
    DB #F8,#1F
    DB #F8,#1E
    DB #7C,#3E
    DB #7E,#7C
    DB #3F,#F8
    DB #1F,#F0
    DB #0F,#E0
ENEMY_LARGE_SHARD_0:
    DB #01,#80
    DB #0F,#E0
    DB #1E,#F0
    DB #3F,#F8
    DB #7F,#7C
    DB #7C,#3E
    DB #FD,#7F
    DB #FF,#FF
    DB #FB,#FE
    DB #78,#FE
    DB #7F,#FC
    DB #3F,#B8
    DB #1F,#F0
    DB #1D,#E0
    DB #0F,#80
    DB #05,#00
ENEMY_LARGE_SHARD_1:
    DB #01,#C0
    DB #07,#F0
    DB #0F,#F8
    DB #3F,#FC
    DB #7F,#FE
    DB #FC,#FE
    DB #5D,#9E
    DB #FD,#DB
    DB #7F,#8F
    DB #37,#DE
    DB #3F,#FE
    DB #1F,#FC
    DB #0F,#F8
    DB #07,#F0
    DB #03,#E0
    DB #00,#C0
ENEMY_LARGE_SHARD_2:
    DB #00,#A0
    DB #01,#F0
    DB #07,#B8
    DB #0F,#F8
    DB #1D,#FC
    DB #3F,#FE
    DB #7F,#1E
    DB #7F,#DF
    DB #FF,#FF
    DB #FE,#BF
    DB #7C,#3E
    DB #3E,#FE
    DB #1F,#FC
    DB #0F,#78
    DB #07,#F0
    DB #01,#80
ENEMY_LARGE_SHARD_3:
    DB #03,#00
    DB #07,#C0
    DB #0F,#E0
    DB #1F,#F0
    DB #3F,#F8
    DB #7F,#FC
    DB #7B,#EC
    DB #F1,#FE
    DB #DB,#BF
    DB #79,#BA
    DB #7F,#3F
    DB #7F,#FE
    DB #3F,#FC
    DB #1F,#F0
    DB #0F,#E0
    DB #03,#80

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
BULLET_ATTR_PAIR:
    DB #47,#47                 ; bullet spans two cells at +4px

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
    DB 0,0                      ; base cell X/Y for blast
BLAST_HALF:
    DB 0                        ; 4px offset of ship blast (0 or 1)
BLAST_ATTR_PAIR:
    DB #46,#46                 ; dynamically selected ship blast colors
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
    ; Far layer: 1..3 pixels (with half-stages) every four frames.
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
SCROLL_SPEED:      DB 1        ; integer portion of motion speed (1..3)
SPEED_LEVEL:       DB 0        ; stages 0..4: 1,1.5,2,2.5,3
ENEMY_SPEED_PHASE: DB 0        ; alternates 4/3 or 3/2 enemy intervals
SCORE:             DB 0,0,0    ; 24-bit little endian, capped at 999999
SCORE_PRINT_WORK:  DB 0,0,0    ; scratch remainder for decimal output
HUD_DIRTY:         DB 1        ; refresh speed, score and lives
GAUGE_DIRTY:       DB 1        ; gauge colors need redraw
SPACE_HELD:        DB 0

HUD_LABEL_TITLE:  DB "SPACECAN: SPACE SODA",0
HUD_LABEL_SPEED:  DB "SPEED",0
HUD_LABEL_SHOOT:  DB "SHOOT!",0

; Each life is one 8x8 character, active vs spent.
HEART_FILLED:
    DB %00000000
    DB %01100110
    DB %11111111
    DB %11111111
    DB %11111111
    DB %01111110
    DB %00111100
    DB %00011000
HEART_OUTLINE:
    DB %00000000
    DB %01100110
    DB %10011001
    DB %10000001
    DB %10000001
    DB %01000010
    DB %00100100
    DB %00011000
HEART_ACTIVE_ATTR: DB #42    ; bright red ink on black
HEART_SPENT_ATTR:  DB #07    ; dim white ink on black

; 100000, 10000, 1000, 100, 10 as 24-bit little-endian divisors.
SCORE_DECIMAL_PLACES:
    DB #A0,#86,#01
    DB #10,#27,#00
    DB #E8,#03,#00
    DB #64,#00,#00
    DB #0A,#00,#00

CAN_LABEL_LEFT:   DB "SPA",0
CAN_LABEL_RIGHT:  DB "CAN",0
CAN_LABEL_VOLUME: DB "0.33",0

PROGRAM_END:

; ===== artwork.asm =====
; Z80_POCKET_IDE_SCREEN_RLE_ZERO_V1
; Escape: 00,count,byte = repeat; all nonzero bytes are literals.
; Expands to 6144 bitmap + 768 attributes at $4000.
SPACE_CAN_SCREEN_RLE:
    DB $CC,$CC,$CC,$00,$1A,$00,$CC,$CC,$CC,$00,$20,$FF,$00,$0A,$00,$80
    DB $00,$0B,$00,$80,$00,$13,$00,$80,$00,$0B,$00,$80,$00,$29,$00,$3D
    DB $F7,$DF,$7B,$EF,$01,$97,$FF,$00,$10,$00,$FF,$F5,$80,$F7,$DE,$FB
    DB $EF,$BC,$3D,$F6,$84,$7B,$EF,$31,$80,$00,$11,$00,$80,$00,$01,$00
    DB $4C,$F7,$DE,$21,$6F,$BC,$3D,$F5,$D0,$EB,$EF,$7F,$16,$EF,$00,$10
    DB $00,$F9,$E9,$FE,$F7,$D7,$03,$AF,$BC,$CC,$CC,$CC,$00,$1A,$00,$CC
    DB $CC,$CC,$00,$0A,$00,$80,$00,$0B,$00,$80,$00,$13,$00,$80,$00,$0B
    DB $00,$80,$00,$13,$00,$80,$00,$0B,$00,$80,$00,$09,$00,$3D,$F7,$DF
    DB $7B,$EF,$00,$16,$00,$F7,$DE,$FB,$EF,$BC,$3D,$F7,$DF,$7B,$EF,$01
    DB $BF,$FF,$00,$10,$00,$2F,$A9,$80,$F7,$DE,$FB,$EF,$BC,$3D,$F6,$86
    DB $3B,$EF,$30,$3F,$FF,$00,$10,$00,$3F,$FC,$0C,$F7,$DC,$61,$6F,$BC
    DB $3D,$F0,$83,$EB,$EF,$79,$52,$27,$00,$10,$00,$71,$CD,$FE,$F7,$D7
    DB $C9,$0F,$BC,$33,$33,$33,$00,$19,$00,$01,$33,$33,$33,$00,$0A,$00
    DB $80,$00,$0B,$00,$80,$00,$13,$00,$80,$00,$0B,$00,$80,$00,$13,$00
    DB $80,$00,$0B,$00,$80,$00,$09,$00,$3D,$F7,$DF,$7B,$EF,$00,$16,$00
    DB $F7,$DE,$FB,$EF,$BC,$3D,$F7,$DF,$7B,$EF,$00,$02,$00,$FF,$00,$13
    DB $00,$F7,$DE,$FB,$EF,$BC,$3D,$F6,$87,$9B,$EF,$71,$FF,$FF,$00,$10
    DB $00,$7F,$FF,$8E,$F7,$D9,$E1,$6F,$BC,$3D,$F1,$C3,$CB,$EF,$73,$11
    DB $3F,$00,$10,$00,$75,$ED,$9E,$F7,$D3,$C3,$8F,$BC,$33,$33,$33,$00
    DB $19,$00,$01,$33,$33,$33,$00,$0A,$00,$80,$00,$0B,$00,$80,$00,$13
    DB $00,$80,$00,$0B,$00,$80,$00,$13,$00,$80,$00,$0B,$00,$80,$00,$09
    DB $00,$3D,$F7,$DF,$7B,$EF,$00,$01,$00,$0F,$FF,$00,$10,$00,$FF,$F0
    DB $00,$01,$00,$F7,$DE,$FB,$EF,$BC,$3D,$F7,$DF,$7B,$EF,$01,$03,$FF
    DB $00,$10,$00,$23,$E0,$80,$F7,$DE,$FB,$EF,$BC,$3D,$F6,$87,$CB,$EF
    DB $67,$FF,$F7,$00,$10,$00,$7F,$FF,$E6,$F7,$D3,$E1,$6F,$BC,$3D,$E7
    DB $E1,$9B,$EF,$73,$2D,$FF,$00,$10,$00,$75,$E9,$9E,$F7,$D9,$8F,$EF
    DB $BC,$CC,$CC,$CC,$00,$1A,$00,$CC,$CC,$CC,$00,$0A,$00,$80,$00,$0B
    DB $00,$80,$00,$13,$00,$80,$00,$0B,$00,$80,$00,$13,$00,$80,$00,$0B
    DB $00,$80,$00,$09,$00,$3D,$F7,$DF,$7B,$EF,$00,$01,$00,$7E,$00,$12
    DB $00,$7E,$00,$01,$00,$F7,$DE,$FB,$EF,$BC,$3D,$F7,$03,$7B,$EF,$07
    DB $17,$FF,$00,$10,$00,$83,$C0,$40,$F7,$DE,$C0,$EF,$BC,$3D,$F6,$97
    DB $EB,$EF,$5F,$FF,$A7,$00,$10,$00,$FF,$FF,$FA,$F7,$D7,$E1,$6F,$BC
    DB $3D,$E7,$F0,$3B,$EF,$79,$6F,$DF,$00,$10,$00,$F5,$4F,$FE,$F7,$DC
    DB $0F,$E7,$BC,$CC,$CC,$CC,$00,$1A,$00,$CC,$CC,$CC,$00,$0A,$00,$80
    DB $00,$0B,$00,$80,$00,$13,$00,$80,$00,$0B,$00,$80,$00,$13,$00,$80
    DB $00,$0B,$00,$80,$00,$09,$00,$3D,$F7,$DF,$7B,$EF,$00,$01,$00,$F0
    DB $E0,$00,$10,$00,$03,$8F,$00,$01,$00,$F7,$DE,$FB,$EF,$BC,$3D,$F7
    DB $3B,$7B,$EF,$02,$2F,$FF,$00,$10,$00,$2B,$EA,$70,$F7,$DE,$DE,$EF
    DB $BC,$3D,$F6,$87,$EB,$EF,$7F,$FF,$2F,$00,$10,$00,$7F,$FF,$FE,$F7
    DB $D7,$E9,$6F,$BC,$3D,$CF,$FA,$7B,$EF,$7D,$7D,$8F,$00,$10,$00,$71
    DB $FF,$FE,$F7,$DE,$1F,$F3,$BC,$33,$33,$33,$00,$19,$00,$01,$33,$33
    DB $33,$00,$0A,$00,$80,$00,$0B,$00,$80,$00,$13,$00,$80,$00,$0B,$00
    DB $80,$00,$09,$00,$00,$20,$FF,$3D,$F7,$DF,$7B,$EF,$00,$01,$00,$87
    DB $FE,$00,$10,$00,$7F,$F1,$80,$F7,$DE,$FB,$EF,$BC,$3D,$F6,$7D,$7B
    DB $EF,$0C,$0F,$FF,$00,$10,$00,$05,$F0,$30,$F7,$DE,$1E,$6F,$BC,$3D
    DB $F4,$87,$EB,$EF,$7F,$F2,$67,$00,$10,$00,$7F,$F9,$FE,$F7,$D7,$E1
    DB $2F,$BC,$3D,$CF,$F8,$7B,$EF,$79,$F8,$AF,$00,$10,$00,$73,$FE,$1E
    DB $F7,$DE,$1F,$F3,$BC,$00,$2A,$00,$80,$00,$0B,$00,$80,$00,$13,$00
    DB $80,$00,$0B,$00,$80,$00,$29,$00,$3D,$F7,$DF,$7B,$EF,$00,$01,$00
    DB $9F,$FE,$00,$10,$00,$7F,$F8,$80,$F7,$DE,$FB,$EF,$BC,$3D,$F6,$CC
    DB $7B,$EF,$19,$7F,$FF,$00,$10,$00,$2B,$FA,$98,$F7,$DE,$33,$6F,$BC
    DB $3D,$F4,$87,$6B,$EF,$7F,$B2,$EF,$00,$10,$00,$7F,$CD,$FE,$F7,$D7
    DB $E9,$2F,$BC,$3D,$DF,$EC,$7B,$EF,$73,$CA,$8F,$00,$10,$00,$7F,$E2
    DB $FE,$F7,$DE,$3F,$FB,$BC,$3D,$9F,$FC,$7B,$EF,$7E,$AA,$8F,$00,$10
    DB $00,$FF,$87,$FE,$F7,$DE,$3F,$F9,$BC,$3D,$1F,$F6,$7B,$EF,$7F,$8F
    DB $FF,$00,$10,$00,$FC,$EF,$FE,$F7,$DE,$7F,$F0,$BC,$3D,$F7,$DF,$7B
    DB $EF,$60,$7F,$FF,$00,$10,$00,$80,$00,$01,$00,$12,$F7,$DE,$FB,$EF
    DB $BC,$38,$00,$03,$00,$EF,$63,$C0,$1F,$00,$10,$00,$81,$FF,$0E,$F7
    DB $00,$03,$00,$1C,$3B,$00,$02,$00,$06,$EF,$61,$F0,$3F,$00,$10,$00
    DB $E0,$33,$B6,$F7,$60,$00,$02,$00,$DC,$3B,$01,$00,$01,$00,$36,$EF
    DB $67,$EF,$9F,$00,$10,$00,$B0,$7F,$26,$F7,$60,$20,$17,$DC,$3B,$5F
    DB $F0,$26,$EF,$6F,$98,$3F,$00,$10,$00,$9C,$07,$DE,$F7,$69,$EE,$04
    DB $DC,$3B,$7F,$00,$01,$00,$86,$EF,$60,$FC,$0F,$00,$10,$00,$FF,$0F
    DB $FE,$F7,$67,$E0,$10,$DC,$3D,$B0,$06,$7B,$EF,$7C,$AA,$AF,$00,$10
    DB $00,$7E,$3F,$FE,$F7,$DE,$60,$0D,$BC,$3D,$1F,$FE,$7B,$EF,$7E,$3F
    DB $FF,$00,$10,$00,$78,$FF,$FE,$F7,$DE,$5F,$E8,$BC,$3D,$F7,$DF,$7B
    DB $EF,$60,$07,$FF,$00,$12,$00,$22,$F7,$DE,$FB,$EF,$BC,$38,$00,$03
    DB $00,$EF,$61,$80,$FF,$00,$10,$00,$03,$FC,$06,$F7,$00,$03,$00,$1C
    DB $3B,$0C,$00,$01,$00,$06,$EF,$67,$C0,$78,$00,$11,$00,$3B,$F6,$F7
    DB $61,$80,$00,$01,$00,$DC,$3B,$02,$00,$01,$00,$B6,$EF,$6F,$BB,$9E
    DB $00,$10,$00,$30,$FF,$0E,$F7,$60,$40,$56,$DC,$3B,$7B,$40,$66,$EF
    DB $67,$B0,$7E,$00,$10,$00,$08,$1F,$BE,$F7,$6F,$70,$0C,$DC,$3B,$3C
    DB $01,$C6,$EF,$61,$F0,$FE,$00,$10,$00,$7C,$3F,$FE,$F7,$63,$80,$18
    DB $DC,$3D,$BF,$FE,$7B,$EF,$79,$A9,$FF,$00,$10,$00,$7C,$FF,$FE,$F7
    DB $DE,$7F,$FD,$BC,$3D,$27,$E9,$7B,$EF,$7C,$FF,$FF,$00,$10,$00,$70
    DB $05,$FE,$F7,$DE,$AF,$E8,$BC,$3D,$F7,$DF,$7B,$EF,$60,$01,$FF,$00
    DB $11,$00,$24,$32,$F7,$DE,$FB,$EF,$BC,$38,$00,$03,$00,$EF,$61,$81
    DB $FE,$00,$10,$00,$0F,$E0,$06,$F7,$00,$03,$00,$1C,$3B,$0E,$00,$01
    DB $00,$06,$EF,$67,$80,$F8,$00,$10,$00,$06,$7B,$F6,$F7,$61,$C0,$00
    DB $01,$00,$DC,$3B,$04,$17,$B6,$EF,$6F,$BB,$FC,$00,$10,$00,$30,$CF
    DB $1E,$F7,$60,$83,$D6,$DC,$3B,$30,$01,$C6,$EF,$67,$81,$FE,$00,$11
    DB $00,$3F,$66,$F7,$66,$40,$38,$DC,$3B,$00,$02,$00,$C6,$EF,$63,$E0
    DB $1E,$00,$10,$00,$78,$07,$FE,$F7,$60,$00,$01,$00,$18,$DC,$3D,$9F
    DB $FC,$7B,$EF,$78,$AB,$FF,$00,$10,$00,$7B,$FF,$FE,$F7,$DE,$3F,$F9
    DB $BC,$3D,$5A,$AA,$7B,$EF,$79,$FF,$FF,$00,$10,$00,$60,$BF,$FE,$F7
    DB $DE,$25,$F6,$BC,$3D,$F7,$DF,$7B,$EF,$70,$80,$FF,$00,$11,$00,$08
    DB $32,$F7,$DE,$FB,$EF,$BC,$3B,$FF,$FF,$FE,$EF,$60,$87,$F8,$00,$10
    DB $00,$1F,$C0,$36,$F7,$7F,$FF,$FF,$DC,$3B,$0C,$01,$E6,$EF,$6F,$06
    DB $DE,$00,$10,$00,$0E,$7B,$F6,$F7,$60,$80,$7E,$DC,$3B,$00,$01,$00
    DB $3D,$F6,$EF,$7D,$FF,$F8,$00,$10,$00,$30,$CC,$3E,$F7,$60,$0E,$BF
    DB $DC,$3B,$70,$03,$06,$EF,$6F,$83,$F8,$00,$11,$00,$FC,$FE,$F7,$6E
    DB $00,$01,$00,$E0,$DC,$3B,$00,$02,$00,$86,$EF,$67,$C0,$FE,$00,$10
    DB $00,$60,$BF,$9E,$F7,$60,$00,$02,$00,$DC,$3D,$83,$E0,$7B,$EF,$7C
    DB $8F,$C7,$00,$10,$00,$FF,$FE,$12,$F7,$DE,$07,$C1,$BC,$3D,$5B,$D6
    DB $7B,$EF,$7F,$FF,$FF,$00,$10,$00,$80,$3F,$FE,$F7,$DE,$57,$F6,$BC
    DB $3D,$F7,$DF,$7B,$EF,$61,$80,$3F,$00,$10,$00,$80,$12,$02,$F7,$DE
    DB $FB,$EF,$BC,$3B,$FF,$FF,$FE,$EF,$70,$1F,$E0,$00,$10,$00,$BF,$00
    DB $01,$00,$36,$F7,$7F,$FF,$FF,$DC,$3B,$00,$01,$00,$0F,$B6,$EF,$7C
    DB $04,$DF,$00,$10,$00,$8E,$7B,$76,$F7,$60,$03,$E6,$DC,$3B,$00,$01
    DB $00,$75,$F6,$EF,$79,$FF,$E1,$00,$10,$00,$B0,$C0,$7E,$F7,$60,$0A
    DB $BD,$DC,$3B,$40,$0E,$06,$EF,$7E,$07,$F1,$00,$10,$00,$83,$F8,$EA
    DB $F7,$68,$01,$C0,$DC,$3B,$00,$02,$00,$06,$EF,$6F,$00,$01,$00,$57
    DB $00,$10,$00,$C0,$BE,$1E,$F7,$60,$00,$02,$00,$DC,$3D,$BF,$FA,$7B
    DB $EF,$7E,$FE,$1F,$00,$10,$00,$7F,$F0,$BE,$F7,$DE,$7F,$FF,$BC,$3D
    DB $28,$2A,$7B,$EF,$7F,$FF,$FF,$00,$11,$00,$07,$FE,$F7,$DE,$8A,$8B
    DB $BC,$3D,$F7,$DF,$7B,$EF,$61,$80,$1F,$00,$11,$00,$17,$FA,$F7,$DE
    DB $FB,$EF,$BC,$3B,$FF,$FF,$FE,$EF,$60,$3F,$80,$00,$10,$00,$7C,$01
    DB $36,$F7,$7F,$FF,$FF,$DC,$3B,$00,$01,$00,$3C,$06,$EF,$7C,$0F,$9E
    DB $00,$10,$00,$1E,$7B,$76,$F7,$60,$07,$80,$DC,$3B,$0B,$9D,$E6,$EF
    DB $79,$FF,$40,$00,$10,$00,$3B,$C0,$FE,$F7,$61,$EB,$A8,$DC,$3B,$00
    DB $01,$00,$38,$06,$EF,$7C,$1F,$C4,$00,$10,$00,$07,$F0,$FE,$F7,$60
    DB $0F,$80,$DC,$3B,$00,$02,$00,$06,$EF,$7E,$00,$01,$00,$0C,$00,$11
    DB $00,$0C,$7E,$F7,$60,$00,$02,$00,$DC,$3D,$D7,$FC,$7B,$EF,$78,$F0
    DB $7F,$00,$10,$00,$7F,$C3,$FE,$F7,$DE,$5F,$FD,$BC,$3D,$5B,$2A,$7B
    DB $EF,$7F,$FF,$FF,$00,$11,$00,$FF,$FE,$F7,$DE,$65,$54,$BC,$3D,$F7
    DB $DF,$7B,$EF,$61,$80,$0F,$00,$11,$00,$1F,$FE,$F7,$DE,$FB,$EF,$BC
    DB $3B,$00,$02,$00,$06,$EF,$60,$7E,$06,$00,$10,$00,$7C,$03,$B6,$F7
    DB $60,$00,$02,$00,$DC,$3B,$00,$01,$00,$70,$06,$EF,$70,$6F,$98,$00
    DB $10,$00,$18,$5B,$76,$F7,$60,$0C,$00,$01,$00,$DC,$3B,$3F,$17,$06
    DB $EF,$5D,$9B,$06,$00,$10,$00,$3F,$C1,$F6,$F7,$67,$F2,$C0,$DC,$3B
    DB $01,$F0,$06,$EF,$78,$3F,$82,$00,$10,$00,$0F,$C0,$EE,$F7,$64,$3E
    DB $00,$01,$00,$DC,$3B,$00,$02,$00,$06,$EF,$7C,$00,$01,$00,$FE,$00
    DB $11,$00,$38,$FE,$F7,$60,$00,$02,$00,$DC,$3D,$EF,$FA,$7B,$EF,$79
    DB $E3,$FF,$00,$10,$00,$7F,$0D,$7E,$F7,$DE,$7F,$FB,$BC,$3D,$18,$50
    DB $7B,$EF,$7F,$FF,$FF,$00,$11,$00,$BF,$FE,$F7,$DE,$4A,$90,$BC,$3D
    DB $F7,$DF,$7B,$EF,$67,$E0,$0F,$00,$11,$00,$7F,$FE,$F7,$DE,$FB,$EF
    DB $BC,$3B,$00,$02,$00,$06,$EF,$60,$F8,$0E,$00,$10,$00,$70,$33,$B6
    DB $F7,$60,$00,$02,$00,$DC,$3B,$00,$01,$00,$C0,$06,$EF,$71,$EF,$98
    DB $00,$10,$00,$38,$FB,$36,$F7,$60,$18,$00,$01,$00,$DC,$3B,$7F,$98
    DB $06,$EF,$7F,$98,$0E,$00,$10,$00,$1E,$03,$EE,$F7,$6D,$FB,$00,$01
    DB $00,$DC,$3B,$67,$E0,$06,$EF,$60,$7E,$04,$00,$10,$00,$3F,$80,$FE
    DB $F7,$66,$F8,$00,$01,$00,$DC,$3B,$FF,$FF,$FE,$EF,$78,$00,$01,$00
    DB $26,$00,$11,$00,$01,$FE,$F7,$7F,$FF,$FF,$DC,$3B,$FF,$FF,$FE,$EF
    DB $70,$00,$01,$00,$FF,$00,$10,$00,$86,$03,$7E,$F7,$7F,$FF,$FF,$DC
    DB $3D,$F7,$DF,$7B,$EF,$60,$FF,$35,$00,$10,$00,$81,$BB,$7E,$F7,$BE
    DB $FB,$EF,$BC,$00,$05,$00,$6F,$3F,$05,$00,$10,$00,$81,$F3,$5E,$00
    DB $0A,$00,$67,$87,$E1,$00,$10,$00,$8B,$02,$7E,$00,$05,$00,$32,$00
    DB $02,$00,$02,$EC,$67,$8F,$5F,$00,$10,$00,$80,$AB,$BE,$37,$40,$00
    DB $02,$00,$4C,$32,$41,$0A,$12,$EC,$65,$7F,$FF,$00,$10,$00,$AA,$FF
    DB $FE,$37,$44,$00,$01,$00,$10,$4C,$32,$41,$0A,$12,$EC,$6F,$FF,$FF
    DB $00,$10,$00,$BF,$FF,$FE,$37,$44,$00,$01,$00,$10,$4C,$1F,$00,$01
    DB $00,$7F,$C0,$FF,$73,$07,$E1,$00,$10,$00,$86,$D0,$FC,$7D,$01,$FF
    DB $00,$01,$00,$F4,$3B,$FF,$FF,$FE,$EF,$60,$00,$01,$00,$8E,$00,$10
    DB $00,$06,$06,$7E,$F7,$7F,$FF,$FF,$DC,$3D,$F7,$DF,$7B,$EF,$61,$FE
    DB $7E,$00,$10,$00,$03,$BE,$3E,$F7,$BE,$FB,$EF,$BC,$00,$05,$00,$60
    DB $7E,$08,$00,$10,$00,$03,$F2,$7E,$00,$05,$00,$3F,$00,$04,$FF,$63
    DB $0F,$CC,$00,$10,$00,$1E,$0F,$FE,$00,$04,$FF,$FC,$32,$6A,$AA,$82
    DB $EC,$6F,$8B,$FC,$00,$11,$00,$AA,$FE,$B7,$4A,$29,$A4,$4C,$32,$62
    DB $85,$22,$EC,$60,$3F,$FE,$00,$11,$00,$7F,$FE,$B7,$4A,$2A,$22,$4C
    DB $32,$62,$85,$22,$EC,$6F,$FF,$FC,$00,$10,$00,$2F,$FF,$FA,$B7,$4A
    DB $2A,$22,$4C,$2E,$05,$FF,$F0,$FE,$7B,$3F,$FE,$00,$10,$00,$7F,$80
    DB $FC,$3B,$2F,$FF,$C0,$BE,$38,$00,$03,$00,$EF,$60,$00,$01,$00,$44
    DB $00,$10,$00,$0F,$07,$5E,$F7,$00,$03,$00,$1C,$3D,$F7,$DF,$7B,$EF
    DB $63,$FD,$E6,$00,$10,$00,$03,$76,$3E,$F7,$BE,$FB,$EF,$BC,$7F,$00
    DB $04,$FF,$60,$3C,$04,$00,$10,$00,$03,$60,$FE,$00,$04,$FF,$FE,$3F
    DB $00,$04,$FF,$63,$1F,$00,$11,$00,$06,$06,$7E,$00,$04,$FF,$FC,$32
    DB $85,$55,$42,$ED,$7F,$10,$5C,$00,$11,$00,$01,$76,$37,$44,$10,$08
    DB $4C,$32,$A0,$00,$01,$00,$52,$ED,$60,$7F,$FE,$00,$10,$00,$2B,$7F
    DB $FE,$B7,$44,$15,$00,$01,$00,$4C,$32,$A0,$00,$01,$00,$52,$ED,$67
    DB $FF,$FE,$00,$10,$00,$1F,$FF,$F6,$B7,$44,$15,$00,$01,$00,$4C,$35
    DB $00,$01,$00,$7F,$E8,$FD,$79,$1F,$FE,$00,$10,$00,$5F,$FC,$F8,$35
    DB $03,$FF,$00,$01,$00,$F4,$3D,$F7,$DF,$7B,$EF,$60,$00,$01,$00,$FE
    DB $00,$10,$00,$06,$0F,$DE,$F7,$BE,$FB,$EF,$BC,$3D,$F7,$DF,$7B,$EF
    DB $67,$E7,$CE,$00,$10,$00,$06,$7D,$FE,$F7,$BE,$FB,$EF,$BC,$3F,$00
    DB $04,$FF,$60,$00,$01,$00,$0A,$00,$10,$00,$06,$E0,$FE,$00,$04,$FF
    DB $FC,$30,$00,$03,$00,$E0,$60,$7E,$D4,$00,$10,$00,$0C,$02,$FE,$FF
    DB $00,$03,$00,$0C,$32,$46,$AA,$92,$EC,$7E,$3F,$FE,$00,$10,$00,$02
    DB $AF,$FE,$B7,$4A,$28,$24,$4C,$32,$42,$B2,$92,$EC,$6F,$FF,$FE,$00
    DB $10,$00,$2A,$FF,$FE,$37,$4A,$2A,$84,$4C,$32,$42,$B2,$92,$EC,$70
    DB $FF,$FE,$00,$10,$00,$3F,$FF,$8E,$B7,$4A,$2A,$84,$4C,$3F,$06,$FF
    DB $FC,$FF,$3F,$BF,$FE,$00,$10,$00,$7F,$FB,$F8,$3F,$3F,$FF,$E0,$FC
    DB $3D,$F7,$DF,$7B,$EF,$60,$38,$15,$00,$10,$00,$84,$0F,$DE,$F7,$BE
    DB $FB,$EF,$BC,$3D,$F7,$DF,$7B,$EF,$6D,$9F,$9F,$00,$10,$00,$84,$7D
    DB $BE,$F7,$BE,$FB,$EF,$BC,$00,$05,$00,$60,$00,$01,$00,$01,$00,$10
    DB $00,$86,$C0,$FE,$00,$05,$00,$30,$00,$03,$00,$E0,$60,$FC,$01,$00
    DB $10,$00,$8C,$02,$7E,$07,$00,$03,$00,$0C,$32,$61,$01,$12,$ED,$7C
    DB $01,$77,$00,$10,$00,$80,$0D,$7E,$37,$45,$10,$00,$01,$00,$4C,$32
    DB $00,$02,$00,$22,$ED,$60,$7F,$FD,$00,$10,$00,$81,$7F,$FE,$B7,$44
    DB $15,$00,$01,$00,$4C,$32,$00,$02,$00,$22,$ED,$78,$3F,$A3,$00,$10
    DB $00,$85,$3C,$3E,$B7,$44,$15,$00,$01,$00,$4C,$3F,$00,$01,$00,$3F
    DB $D0,$7A,$0F,$DB,$F5,$00,$10,$00,$AB,$EB,$F0,$7B,$01,$FF,$00,$01
    DB $00,$AC,$3D,$F7,$DF,$7B,$EF,$60,$7E,$0E,$00,$11,$00,$1F,$BE,$F7
    DB $BE,$FB,$EF,$BC,$3D,$F7,$DF,$7B,$EF,$6C,$7C,$0C,$00,$11,$00,$8B
    DB $7E,$F7,$BE,$FB,$EF,$BC,$3F,$00,$04,$FF,$60,$00,$01,$00,$1E,$00
    DB $10,$00,$07,$80,$FE,$00,$04,$FF,$FC,$33,$FF,$FF,$FE,$EF,$61,$F8
    DB $00,$11,$00,$08,$00,$01,$00,$7E,$F7,$7F,$FF,$FF,$CC,$32,$20,$90
    DB $92,$EC,$78,$FF,$FE,$00,$10,$00,$0A,$AF,$FE,$B7,$4A,$80,$AA,$4C
    DB $32,$2A,$2A,$42,$ED,$6B,$FF,$FE,$00,$10,$00,$2F,$FF,$FE,$B7,$4A
    DB $20,$2A,$4C,$00,$05,$00,$6F,$C0,$00,$12,$00,$03,$FA,$00,$05,$00
    DB $3E,$03,$FF,$F8,$FE,$04,$00,$14,$00,$20,$EF,$1F,$FF,$E0,$FC,$3D
    DB $F7,$DF,$7B,$EF,$60,$FF,$F4,$00,$11,$00,$5F,$BE,$F7,$BE,$FB,$EF
    DB $BC,$3D,$F7,$DF,$7B,$EF,$7D,$F1,$BE,$00,$10,$00,$01,$C3,$7E,$F7
    DB $BE,$FB,$EF,$BC,$3F,$00,$04,$FF,$63,$00,$01,$00,$7E,$00,$10,$00
    DB $0D,$80,$7E,$00,$04,$FF,$FC,$33,$FF,$FF,$FE,$EF,$61,$E3,$54,$00
    DB $10,$00,$18,$22,$FE,$F7,$7F,$FF,$FF,$CC,$32,$45,$08,$42,$EC,$70
    DB $7F,$FE,$00,$10,$00,$0A,$FF,$FE,$37,$4C,$42,$94,$4C,$32,$50,$15
    DB $12,$EC,$6F,$FF,$FE,$00,$10,$00,$2F,$FF,$FE,$37,$48,$0A,$14,$4C
    DB $00,$05,$00,$65,$FF,$FE,$00,$10,$00,$7F,$FF,$A2,$00,$05,$00,$3F
    DB $00,$01,$00,$3F,$C0,$FF,$02,$00,$14,$00,$40,$7F,$01,$FE,$00,$01
    DB $00,$FC,$3D,$F7,$DF,$7B,$EF,$60,$FF,$F6,$00,$11,$00,$FF,$3E,$F7
    DB $BE,$FB,$EF,$BC,$3D,$F7,$DF,$7B,$EF,$7F,$CF,$0E,$00,$10,$00,$01
    DB $F3,$7E,$F7,$BE,$FB,$EF,$BC,$00,$05,$00,$63,$01,$F8,$00,$10,$00
    DB $0B,$02,$FE,$00,$05,$00,$32,$00,$02,$00,$02,$EC,$63,$C0,$00,$11
    DB $00,$10,$00,$01,$00,$FE,$37,$40,$00,$02,$00,$4C,$32,$AA,$95,$A2
    DB $ED,$70,$07,$FC,$00,$11,$00,$1F,$FE,$B7,$42,$2D,$4A,$4C,$32,$AA
    DB $2A,$82,$ED,$65,$FF,$FE,$00,$10,$00,$17,$FF,$FE,$B7,$44,$95,$AA
    DB $4C,$00,$05,$00,$66,$C0,$00,$12,$00,$03,$62,$00,$05,$00,$3F,$01
    DB $FF,$F8,$FF,$01,$AA,$AA,$00,$10,$00,$2A,$BA,$80,$FF,$0F,$FF,$C0
    DB $FC,$05,$05,$05,$00,$17,$46,$01,$01,$00,$24,$05,$00,$07,$47,$44
    DB $47,$47,$05,$00,$05,$47,$00,$05,$46,$47,$05,$00,$09,$47,$00,$20
    DB $05,$00,$06,$04,$07,$07,$00,$10,$47,$07,$07,$07,$00,$0A,$04,$07
    DB $07,$27,$00,$10,$47,$07,$07,$07,$00,$07,$04,$06,$04,$04,$06,$06
    DB $06,$00,$10,$47,$06,$06,$06,$04,$04,$06,$00,$04,$04,$06,$04,$04
    DB $06,$06,$06,$00,$10,$47,$06,$06,$06,$04,$04,$06,$04,$04,$04,$06
    DB $06,$04,$04,$06,$06,$06,$00,$10,$47,$06,$06,$06,$04,$04,$06,$06
    DB $04,$04,$26,$26,$04,$04,$06,$06,$06,$00,$10,$47,$06,$06,$06,$04
    DB $04,$26,$26,$00,$06,$04,$06,$06,$06,$00,$11,$47,$06,$06,$00,$06
    DB $04,$06,$06,$06,$04,$06,$06,$06,$00,$10,$47,$06,$06,$07,$04,$06
    DB $06,$06,$04,$04,$06,$06,$06,$04,$06,$07,$07,$00,$10,$47,$07,$07
    DB $07,$04,$06,$06,$06,$04,$04,$06,$06,$06,$04,$07,$07,$07,$00,$10
    DB $47,$07,$07,$06,$04,$06,$06,$06,$04,$04,$06,$06,$06,$04,$07,$06
    DB $06,$00,$10,$47,$06,$06,$06,$04,$06,$06,$06,$04,$04,$06,$06,$06
    DB $04,$06,$06,$06,$00,$10,$47,$06,$06,$06,$04,$06,$06,$06,$00,$06
    DB $04,$06,$06,$06,$00,$10,$47,$07,$07,$06,$00,$0A,$04,$06,$06,$06
    DB $00,$10,$47,$07,$07,$06,$00,$05,$04,$00,$08,$06,$00,$10,$47,$00
    DB $08,$06,$00,$05,$04,$06,$06,$06,$00,$10,$47,$06,$07,$06,$00,$0A
    DB $04,$06,$06,$06,$00,$10,$47,$06,$06,$06,$00,$0A,$04,$06,$06,$06
    DB $00,$10,$47,$06,$06,$06,$00,$0A,$04,$06,$06,$06,$00,$10,$47,$06
    DB $06,$06,$00,$05,$04,$02,$16,$16,$16,$02,$07,$07,$07,$00,$10,$47
    DB $07,$07,$07,$02,$16,$16,$16,$02
SPACE_CAN_SCREEN_END:

; ===== im2.asm =====
; -------------------------------------------------------------
; IM2 frame interrupt for Spectrum 48K / clones. INT = frame start.
;
; Install in RAM at runtime (avoids padding the game binary to #FF00).
; Full 257-byte table: #FE00..#FF00 is filled with #FD.
; I = #FE, bus byte can be anything 00..FF, vector always #FDFD.
; #FDFD..#FDFF contains JP IM2_HANDLER; NOT inside table.
; #FDFD stack top (downward only); reserve 512 stack bytes below it.
;
; This differs from a table starting at #FF00: on a bus #FF, the
; second byte would come from ROM #0000, so full-table safety fails.
;
; ISR saves registers touched by AY_TICK (AF BC DE HL).
; AY_TICK must never modify IX/IY or alternate register banks.
; No screen writes, keyboard scan, beeper waveforms or ROM calls.
; -------------------------------------------------------------

IM2_TABLE       EQU #FE00
IM2_GATE        EQU #FDFD
IM2_STACK_TOP   EQU IM2_GATE
IM2_STACK_GUARD EQU IM2_STACK_TOP-512

; Called at boot with DI and SP already set to IM2_STACK_TOP.
; Clobbers AF,BC,DE,HL. Leaves interrupts disabled; caller does EI.
IM2_INSTALL:
    LD HL,IM2_TABLE
    LD DE,IM2_TABLE+1
    LD (HL),#FD
    LD BC,256                      ; first + 256 bytes = 257 total
    LDIR

    LD A,#C3                       ; opcode JP nn at #FDFD
    LD (IM2_GATE),A
    LD HL,IM2_HANDLER
    LD (IM2_GATE+1),HL

    XOR A
    LD (IM2_FRAME_COUNTER),A
    LD (IM2_FRAME_COUNTER+1),A
    LD A,#FE
    LD I,A
    IM 2
    RET

; Frame interrupt: HALT in main/game/menu waits for this handler.
; IRQ fires at the beginning of the frame (on the modified clone).
IM2_HANDLER:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL

    LD HL,IM2_FRAME_COUNTER
    INC (HL)
    JR NZ,.FRAME_WORK
    INC HL
    INC (HL)
.FRAME_WORK:
    IF AY_MUSIC_ENABLED
        CALL AY_TICK
    ENDIF

    POP HL
    POP DE
    POP BC
    POP AF
    EI
    RETI

IM2_FRAME_COUNTER: DW 0


PROGRAM_IMAGE_END:
    ; Stack reserve begins below #FDFD; reject builds that overlap it.
    ASSERT PROGRAM_IMAGE_END < IM2_STACK_GUARD
