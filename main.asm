; SpaceCan Step 12: six-digit score, four heart lives, gentler speed stages.
; ZX Spectrum 48K / Delta-C, sjasmplus syntax.
;
; Object coordinates use 8x8 cells; ship also stores a 4-pixel half-cell offset.
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
SPEED_STAGE_COUNT    EQU 5     ; 1 / 1.5 / 2 / 2.5 / 3
START_LIVES          EQU 4
MISS_SCREEN_ROWS      EQU PLAYFIELD_BOTTOM-PLAYFIELD_TOP+1
MISS_DISTANCE_LIMIT   EQU MISS_SCREEN_ROWS*3 ; 3 full corridor heights without kills
PRESSURE_SEGMENTS     EQU 10    ; 10 penalties fill the gauge and cost a life
GAME_OVER_FRAMES     EQU 100   ; 2 seconds at the 50Hz ZX interrupt rate
SHIP_MOVE_DELAY      EQU 2
SHIP_BANK_DELAY      EQU 5    ; ticks between 8x8 banking poses
SHIP_BANK_HOLD       EQU 14   ; keep tilt after releasing O/P
MAX_BULLETS          EQU 6
BULLET_SLOT_SIZE     EQU 9
MAX_ENEMIES          EQU 3
ENEMY_SLOT_SIZE      EQU 13
ENEMY_FRAME_DELAY    EQU 8     ; rotate once every 8 ticks
ENEMY_RESPAWN_DELAY  EQU 24
SHIP_BLAST_DURATION  EQU 5    ; 6 frames x 5 ticks = 0.6 sec
SHIP_BLAST_FRAMES    EQU 6
STATE_MENU           EQU 0
STATE_PLAYING        EQU 1
STATE_EXPLODING      EQU 2
STATE_RESPAWN        EQU 3
STATE_GAME_OVER      EQU 4
STATE_PAUSED         EQU 5
PAUSE_TEXT_Y         EQU 12
PAUSE_TEXT_X         EQU 13
PAUSE_TEXT_WIDTH     EQU 6
PAUSE_ATTR_ADDR      EQU #5800 + PAUSE_TEXT_Y*32 + PAUSE_TEXT_X

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

    INCLUDE "diagnostics.asm"

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
    IM 1                         ; 48K ROM interrupt handler
    EI
    JP SHOW_START_MENU

; New game (from menu or after Game Over):
; only here are score, speed and lives reset.
START_NEW_GAME:
    XOR A
    LD (SCORE),A
    LD (SCORE+1),A
    LD (SCORE+2),A             ; 24-bit score, up to 999999
    LD (SPEED_LEVEL),A        ; 0..4, smooth half-speed stages
    LD (ENEMY_SPEED_PHASE),A
    LD (MISS_TRAVEL_ROWS),A       ; a new game resets travel since last kill
    LD (PRESSURE_LEVEL),A        ; start with ten green segments
    LD A,1
    LD (SCROLL_SPEED),A
    LD A,START_LIVES
    LD (SHIP_LIVES),A
    JP RESTART_ROUND

; Continue after ship explosion, preserving score/speed/lives.
RESTART_ROUND:
    DI
    ; A full red gauge has already consumed one life: recharge only
    ; on respawn. Ordinary asteroid collisions preserve gauge damage.
    LD A,(PRESSURE_LEVEL)
    CP PRESSURE_SEGMENTS
    JR NZ,.KEEP_PRESSURE
    XOR A
    LD (PRESSURE_LEVEL),A
.KEEP_PRESSURE:
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

    INCLUDE "menu.asm"
    INCLUDE "logic.asm"
    INCLUDE "bullets.asm"
    INCLUDE "enemies.asm"
    INCLUDE "starfield.asm"
    INCLUDE "renderer.asm"
    INCLUDE "graphics.asm"
    INCLUDE "objects.asm"
    INCLUDE "ui.asm"
    INCLUDE "data.asm"
    INCLUDE "artwork.asm"
