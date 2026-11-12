; SpaceCan Step 22: short demo progression (2x at 4096; boss at 8192).
; ZX Spectrum 48K / Delta-C, sjasmplus syntax.
;
; Object coordinates use 8x8 cells; ship also stores a 4-pixel half-cell offset.
; Cockpit HUD: Y=0..3; playfield: X=8..23, Y=4..23.
; Render after HALT; update logic and moving stars for NEXT frame.

    ORG #9000

; -------------------------------------------------------------
; AUDIO SWITCHES: independent compile-time flags (0=OFF, 1=ON).
; Both enabled in the experimental demo, one common TAP build.
; Beeper shots/explosions always work, regardless of both flags.
; -------------------------------------------------------------
AY_MUSIC_ENABLED      EQU 1    ; AY soundtrack in IM2 (needs AY board)
BEEPER_ENGINE_ENABLED EQU 1    ; idle engine buzz on #FE during flight
AY_TARGET_CLOCK       EQU 2000000 ; Delta-C AY oscillator

; BEEPER ENGINE TUNING (only used when BEEPER_ENGINE_ENABLED=1):
; Larger period = lower buzz; higher pulse count = denser sound
; but consumes more CPU each 20 ms frame. Keep PERIOD 1..247.
BEEPER_ENGINE_PERIOD_1X EQU 96
BEEPER_ENGINE_PERIOD_2X EQU 72
BEEPER_ENGINE_PULSES    EQU 2
    ASSERT BEEPER_ENGINE_PERIOD_1X >= 1
    ASSERT BEEPER_ENGINE_PERIOD_1X <= 247
    ASSERT BEEPER_ENGINE_PERIOD_2X >= 1
    ASSERT BEEPER_ENGINE_PERIOD_2X <= 247
    ASSERT BEEPER_ENGINE_PULSES >= 1
    ASSERT BEEPER_ENGINE_PULSES <= 8

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
    ; AY_TICK remains IM2-driven. The foreground beeper outputs a
    ; short engine packet only when no higher-priority SFX is active.
    CALL SFX_TICK                  ; silent on pause/menu/after explosion
.FRAME_END:
    DEBUG_PHASE DBG_IDLE_COLOUR
    JR MAIN_LOOP

    INCLUDE "menu.asm"
    INCLUDE "sfx.asm"
    INCLUDE "melodies.asm"
    INCLUDE "ay_driver.asm"
    INCLUDE "ay_player.asm"
    INCLUDE "music.asm"
    INCLUDE "logic.asm"
    INCLUDE "bullets.asm"
    INCLUDE "hostile_bullets.asm"
    INCLUDE "enemies.asm"
    INCLUDE "boss.asm"
    INCLUDE "starfield.asm"
    INCLUDE "renderer.asm"
    INCLUDE "graphics.asm"
    INCLUDE "objects.asm"
    INCLUDE "ui.asm"
    INCLUDE "data.asm"
    INCLUDE "artwork.asm"
    INCLUDE "im2.asm"

PROGRAM_IMAGE_END:
    ; Stack reserve begins below #FDFD; reject builds that overlap it.
    ASSERT PROGRAM_IMAGE_END < IM2_STACK_GUARD
