; -------------------------------------------------------------
; SpaceCan AYM1 v1 player: register deltas at 50Hz, no MIDI parsing.
;
; AY_INIT     reset hardware/shadow
; AY_PLAY     HL -> AYM1 blob (header + command stream)
; AY_TICK     one stream frame (preserves BC,DE,HL,IX)
; AY_PAUSE    mute and freeze stream; do not reset AY R13
; AY_RESUME   restore R7 and R8-R10 from last logical frame
; AY_STOP     stop stream, mute hardware
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

AY_STOP:
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
    PUSH HL
    CALL AY_STOP
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
    JP AY_STOP                    ; malformed header -> silence

AY_PAUSE:
    LD A,(AY_ACTIVE)
    OR A
    RET Z
    LD A,1
    LD (AY_PAUSED),A
    JP AY_SILENCE                 ; keep AY_SHADOW unchanged

AY_RESUME:
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
    JP NC,AY_STOP
    LD A,(HL)
    INC HL
    OR A
    JP Z,.TRACK_END
    CP #80
    JP Z,.REG_FRAME
    BIT 7,A
    JP NZ,AY_STOP                 ; 81..FF reserved
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
    JP NZ,AY_STOP                 ; bits 14/15 reserved
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
    JP Z,AY_STOP
    LD HL,(AY_LOOP_PTR)
    LD A,(HL)
    OR A
    JP Z,AY_STOP                  ; no endless zero-length loop
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
