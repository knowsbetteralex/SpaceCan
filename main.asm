; ZX Space Demo - Step 03: moving asteroids and hit points.
; ZX Spectrum 48K / Delta-C, sjasmplus syntax.
;
; Coordinates are in 8x8 character cells: X in low byte, Y in high byte.
; HUD: Y=0..1, corridor: X=6..25, Y=2..23.
; Render immediately after HALT. Logic prepares the NEXT frame.

    ORG #9000

BLAST_FRAME_DURATION EQU 4
BLAST_FRAME_COUNT    EQU 4
PLAYFIELD_TOP        EQU 2
MAX_BULLETS          EQU 6
BULLET_SLOT_SIZE     EQU 16
MAX_ENEMIES          EQU 4
ENEMY_SLOT_SIZE      EQU 32
ENEMY_FRAME_DELAY    EQU 6
ENEMY_RESPAWN_DELAY  EQU 24

; One 32-byte slot for either an 8x8 or a 16x8 enemy.
E_ACTIVE       EQU 0
E_TYPE         EQU 1           ; 0=8x8, 1=16x8
E_HP           EQU 2
E_X            EQU 3
E_Y            EQU 4
E_DRAWN        EQU 5
E_DRAW_X       EQU 6
E_DRAW_Y       EQU 7
E_DIRTY        EQU 8
E_FRAME        EQU 9
E_ANIM_TIMER   EQU 10
E_BG_ATTR      EQU 11          ; two attribute bytes
E_BG_BITMAP    EQU 13          ; sixteen bitmap bytes
E_RESPAWN      EQU 29

    INCLUDE "diagnostics.asm"

; Each bullet slot is exactly 16 bytes (offsets from IX).
B_ACTIVE    EQU 0  ; 0=free, 1=just spawned, 2=flying
B_X         EQU 1
B_Y         EQU 2
B_DRAWN     EQU 3
B_DRAW_X    EQU 4
B_DRAW_Y    EQU 5
B_DIRTY     EQU 6
B_BG_ATTR   EQU 7
B_BG_BITMAP EQU 8       ; 8 bytes at offsets 8..15

START:
    DI
    CALL CLEAR_BITMAP
    CALL DRAW_STATIC_UI
    LD A,1
    OUT (#FE),A                  ; blue border

    ; Fully clear bullet slots, including their saved backgrounds.
    LD HL,BULLET_POOL
    LD (HL),0
    LD DE,BULLET_POOL+1
    LD BC,MAX_BULLETS*BULLET_SLOT_SIZE-1
    LDIR

    CALL INIT_ENEMIES

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
    LD (SCROLL_SPEED),A         ; scroll starts at a later step
    LD (HUD_DIRTY),A
    LD (SHIP_DIRTY),A

    LD HL,(SHIP_START_POS)
    LD (SHIP_CUR_POS),HL
    LD (SHIP_NEW_POS),HL
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
    INCLUDE "renderer.asm"
    INCLUDE "graphics.asm"
    INCLUDE "objects.asm"
    INCLUDE "ui.asm"
    INCLUDE "data.asm"
