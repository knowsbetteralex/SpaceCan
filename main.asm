; ZX Space Demo - Step 05.3: compact 8x8 ship, slower banking.
; ZX Spectrum 48K / Delta-C, sjasmplus syntax.
;
; Coordinates are in 8x8 character cells: X in low byte, Y in high byte.
; Cockpit HUD: Y=0..3; playfield: X=6..25, Y=4..23.
; Render after HALT; update logic and moving stars for NEXT frame.

    ORG #9000

BLAST_FRAME_DURATION EQU 4
BLAST_FRAME_COUNT    EQU 4
PLAYFIELD_TOP        EQU 4
SHIP_BANK_DELAY      EQU 5    ; ticks between 8x8 banking poses
SHIP_BANK_HOLD       EQU 14   ; keep tilt after releasing O/P
MAX_BULLETS          EQU 6
BULLET_SLOT_SIZE     EQU 8
MAX_ENEMIES          EQU 4
ENEMY_SLOT_SIZE      EQU 13
ENEMY_FRAME_DELAY    EQU 4
ENEMY_RESPAWN_DELAY  EQU 24

; One 13-byte enemy slot: state + animation + last drawn position.
E_ACTIVE       EQU 0
E_TYPE         EQU 1           ; 0=8x16, 1=16x16
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
    CALL CLEAR_BITMAP
    CALL DRAW_STATIC_UI
    LD A,1
    OUT (#FE),A                  ; blue border

    ; Initialise bullet slots (state only, no saved background).
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
    LD (SCORE),A
    LD (BULLET_COUNT),A
    LD (SPACE_HELD),A
    LD (SPEED_UP_HELD),A
    LD (SPEED_DOWN_HELD),A
    LD (BLAST_DIRTY),A

    LD A,1
    LD (SCROLL_SPEED),A         ; stars and asteroid speed
    LD (HUD_DIRTY),A
    LD (SHIP_DIRTY),A

    LD HL,(SHIP_START_POS)
    LD (SHIP_CUR_POS),HL
    LD (SHIP_NEW_POS),HL
    LD A,2
    LD (SHIP_BANK),A
    LD (SHIP_BANK_TARGET),A
    XOR A
    LD (SHIP_BANK_TIMER),A
    LD (SHIP_BANK_HOLD_TIMER),A
    LD (BLAST_TYPE),A
    LD HL,BLAST_FRAME_0
    LD (BLAST_FRAME_PTR),HL

    IM 1                         ; 48K ROM interrupt handler
    EI

MAIN_LOOP:
    HALT
    DEBUG_PHASE DBG_RENDER_COLOUR
    CALL RENDER_FRAME            ; all graphics first
    DEBUG_PHASE DBG_HUD_COLOUR
    CALL RENDER_HUD              ; only when UI fields changed
    DEBUG_PHASE DBG_INPUT_COLOUR
    CALL READ_INPUT              ; capture next game state
    DEBUG_PHASE DBG_LOGIC_COLOUR
    CALL UPDATE_GAME             ; movement, hits, animations
    DEBUG_PHASE DBG_IDLE_COLOUR ; visible idle border during HALT
    JR MAIN_LOOP

    INCLUDE "logic.asm"
    INCLUDE "bullets.asm"
    INCLUDE "enemies.asm"
    INCLUDE "starfield.asm"
    INCLUDE "renderer.asm"
    INCLUDE "graphics.asm"
    INCLUDE "objects.asm"
    INCLUDE "tiles.asm"
    INCLUDE "ui.asm"
    INCLUDE "data.asm"
