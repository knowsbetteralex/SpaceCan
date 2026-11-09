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
