; -------------------------------------------------------------
; SpaceCan Step 15.1 — deeper, noise-based ship blast on ZX #FE.
; No AY access here: three AY voices remain free for future music.
;
; SFX_START: A=1..5. Clobbers AF,DE,HL, preserves BC/IX.
; SFX_TICK:  one bounded burst/frame; clobbers AF,BC,DE,HL.
; Ship explosion uses a dedicated irregular pulse routine.
; SFX_STOP:  silence immediately, preserving border (clobbers AF).
; Priority: SHIP > PENALTY > KILL > HIT > SHOT.
; Only called from mainline, never from IM1 ISR.
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
