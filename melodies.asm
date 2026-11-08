; -------------------------------------------------------------
; SpaceCan Step 14: original beeper title/end tunes and pause cue.
;
; MELODY_PLAY: HL -> [half-period, cycles] pairs, terminated by 0,0.
; This is a foreground player used ONLY in menu/gameover/pause, never
; during active gameplay. Its DI tone loop is intentionally blocking
; and avoids ROM interrupt jitter, with one 50Hz silent gap per note.
;
; On a 3.5 MHz Z80 each pulse is approximately 41+32*period T:
;   E5=165 (~658 Hz), C5=208 (~523 Hz), etc.
; Each note's cycle count is 1..255, giving independent durations.
; EAR bit 4 toggles; port shadow SFX_FE_BASE preserves border/MIC.
; In: HL tune pointer. Out: none. Destroys AF,BC,DE,HL.
; Preserves IX; enters/exits with interrupts enabled on 48K IM1.
; -------------------------------------------------------------

MELODY_PLAY:
    PUSH IX
    PUSH HL
    POP IX                        ; tune pointer stays in IX
    DI
.NEXT_NOTE:
    LD C,(IX+0)                  ; half-cycle delay, 0 = end
    LD A,C
    OR A
    JR Z,.DONE
    LD B,(IX+1)                  ; number of complete square-wave cycles
    INC IX
    INC IX
    CALL MELODY_TONE
    ; One 50Hz silent tick makes neighboring notes distinct.
    ; This is safe only in menu, Game Over or frozen PAUSED state.
    EI
    HALT
    DI
    JR .NEXT_NOTE
.DONE:
    LD A,(SFX_FE_BASE)
    AND #0F
    OUT (#FE),A                   ; EAR low, same colour as gameplay
    EI
    POP IX
    RET

; IN B=pulses (nonzero), C=half-period delay.
; Output square wave with accurate enough pitch for short melodies.
; Interrupted drawing is safe: this is called ONLY in non-play states.
MELODY_TONE:
    LD A,(SFX_FE_BASE)
    AND #0F
    LD D,A                        ; low EAR, preserve border and MIC
    OR #10
    LD E,A                        ; high EAR, preserve border and MIC
.CYCLE:
    LD A,E
    OUT (#FE),A
    LD A,C
.HIGH:
    DEC A
    JR NZ,.HIGH
    LD A,D
    OUT (#FE),A
    LD A,C
.LOW:
    DEC A
    JR NZ,.LOW
    DJNZ .CYCLE
    RET

; Calculated for 3.5 MHz Spectrum, 41+32*N T per cycle.
NOTE_C5 EQU 208
NOTE_D5 EQU 185
NOTE_E5 EQU 165
NOTE_F5 EQU 155
NOTE_G5 EQU 138
NOTE_A5 EQU 123
NOTE_B5 EQU 109
NOTE_C6 EQU 103
NOTE_D6 EQU 92

; Four supplied notes: E5 - C5 - E5 - C5 held.
; A short pause-like signal, without copying full game music.
MELODY_PAUSE:
    DB NOTE_E5,58                 ; ~88 ms
    DB NOTE_C5,45                 ; ~86 ms
    DB NOTE_E5,58                 ; ~88 ms
    DB NOTE_C5,200                ; ~383 ms
    DB 0,0

; Original, ascending cosmic fanfare for title screen.
MELODY_TITLE:
    DB NOTE_C5,44
    DB NOTE_E5,58
    DB NOTE_G5,70
    DB NOTE_C6,120
    DB NOTE_D6,85
    DB NOTE_C6,100
    DB NOTE_G5,100
    DB NOTE_E5,100
    DB NOTE_C6,180
    DB 0,0

; Original descending Game Over theme (separate from game SFX).
MELODY_GAME_OVER:
    DB NOTE_C6,85
    DB NOTE_B5,90
    DB NOTE_A5,78
    DB NOTE_G5,90
    DB NOTE_E5,110
    DB NOTE_D5,110
    DB NOTE_C5,190
    DB 0,0
