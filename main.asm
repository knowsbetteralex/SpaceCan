; ZX Space Demo - Step 02: six independent bullets.
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

    XOR A
    LD (SHIP_DRAWN),A
    LD (BLAST_ACTIVE),A
    LD (BLAST_DRAWN),A
    LD (STAR_DRAWN),A
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
    LD (STAR_ALIVE),A
    LD (STAR_DIRTY),A
    LD (SHIP_DIRTY),A

    LD HL,(SHIP_START_POS)
    LD (SHIP_CUR_POS),HL
    LD (SHIP_NEW_POS),HL
    LD HL,(STAR_START_POS)
    LD (STAR_POS),HL
    LD HL,BLAST_FRAME_0
    LD (BLAST_FRAME_PTR),HL

    IM 1                         ; 48K ROM interrupt handler
    EI

MAIN_LOOP:
    HALT
    CALL RENDER_FRAME            ; all graphics first
    CALL RENDER_HUD              ; only when UI fields changed
    CALL READ_INPUT              ; capture next game state
    CALL UPDATE_GAME             ; movement, hits, animations
    JR MAIN_LOOP

    INCLUDE "logic.asm"
    INCLUDE "bullets.asm"
    INCLUDE "renderer.asm"
    INCLUDE "graphics.asm"
    INCLUDE "objects.asm"
    INCLUDE "ui.asm"
    INCLUDE "data.asm"
