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
