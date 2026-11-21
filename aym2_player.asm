; -------------------------------------------------------------
; SpaceCan AYM2 v1 decoder (normative 2026-11-21 codec).
; Called by AY_PLAY_RAW on signature "AYM2" or AY_TICK_INTERNAL.
; Full AYM1 playback remains in ay_player.asm.
;
; On disk: 24-byte header, bytecode 24..stream_end-1 (END),
; table of up to 96 two-byte offsets, packed full FRAME bodies.
; One timed command per IM2 AY_TICK; dictionary expansion does
; not consume any additional time slots. No IX/IY usage.
; -------------------------------------------------------------

; IN HL = AY_BASE+3 (points at the '2' in signature).
; On failure mute and leave AY_ACTIVE zero.
AYM2_PLAY_HEADER:
    INC HL                       ; +4: format version
    LD A,(HL)
    CP 1
    JP NZ,AY_STOP_RAW
    INC HL                       ; +5: 50 frames per second
    LD A,(HL)
    CP 50
    JP NZ,AY_STOP_RAW
    INC HL                       ; +6: flags
    LD A,(HL)
    LD (AY_FLAGS),A
    AND #FE
    JP NZ,AY_STOP_RAW
    INC HL                       ; +7: dictionary entries (0..96)
    LD A,(HL)
    CP 97
    JP NC,AY_STOP_RAW
    LD (AYM2_DICT_COUNT),A
    INC HL                       ; +8: total file length
    LD E,(HL)
    INC HL
    LD D,(HL)
    LD (AY_LENGTH),DE
    INC HL                       ; +10: loop offset
    LD E,(HL)
    INC HL
    LD D,(HL)
    LD (AY_LOOP_OFFSET),DE
    INC HL                       ; +12: target AY clock, nonzero
    LD B,4
    XOR A
.CLOCK:
    OR (HL)
    INC HL
    DJNZ .CLOCK
    JP Z,AY_STOP_RAW
    LD E,(HL)                    ; +16: exclusive stream end
    INC HL
    LD D,(HL)
    LD (AYM2_STREAM_END_OFFSET),DE
    INC HL                       ; +18: first dictionary body
    LD E,(HL)
    INC HL
    LD D,(HL)
    LD (AYM2_DICT_BODY_OFFSET),DE
    INC HL                       ; +20: reserved 4 bytes
    LD B,4
.RESERVED:
    LD A,(HL)
    OR A
    JP NZ,AY_STOP_RAW
    INC HL
    DJNZ .RESERVED
    LD (AY_POS),HL               ; +24: first command

    LD HL,(AY_LENGTH)
    LD DE,25                     ; must hold header + at least END
    OR A
    SBC HL,DE
    JP C,AY_STOP_RAW
    LD HL,(AY_BASE)
    LD DE,(AY_LENGTH)
    ADD HL,DE
    JP C,AY_STOP_RAW             ; refuse any wrap at #10000
    LD (AY_END_PTR),HL

    ; Stream contains at least one command and END.
    LD HL,(AYM2_STREAM_END_OFFSET)
    LD DE,26                     ; header + timed command + END
    OR A
    SBC HL,DE
    JP C,AY_STOP_RAW
    LD HL,(AY_LENGTH)
    LD DE,(AYM2_STREAM_END_OFFSET)
    OR A
    SBC HL,DE
    JP C,AY_STOP_RAW

    ; Dictionary pointers occupy exactly 2 * count bytes.
    LD A,(AYM2_DICT_COUNT)
    ADD A,A                      ; count <= 96, so no 8-bit wrap
    LD E,A
    LD D,0
    LD HL,(AYM2_STREAM_END_OFFSET)
    ADD HL,DE
    JP C,AY_STOP_RAW
    LD DE,(AYM2_DICT_BODY_OFFSET)
    OR A
    SBC HL,DE
    JP NZ,AY_STOP_RAW
    LD HL,(AY_LENGTH)
    LD DE,(AYM2_DICT_BODY_OFFSET)
    OR A
    SBC HL,DE
    JP C,AY_STOP_RAW

    LD HL,(AY_BASE)
    LD DE,(AYM2_STREAM_END_OFFSET)
    ADD HL,DE
    JP C,AY_STOP_RAW
    LD (AYM2_STREAM_END_PTR),HL
    DEC HL
    LD A,(HL)
    OR A
    JP NZ,AY_STOP_RAW            ; last byte of stream is END
    LD HL,(AY_BASE)
    LD DE,(AYM2_DICT_BODY_OFFSET)
    ADD HL,DE
    JP C,AY_STOP_RAW
    LD (AYM2_DICT_BODY_PTR),HL
    LD HL,(AY_BASE)
    LD DE,(AYM2_STREAM_END_OFFSET)
    ADD HL,DE
    LD (AYM2_DICT_TABLE_PTR),HL

    ; Loop offset must point inside timed stream, never to END.
    LD A,(AY_FLAGS)
    AND 1
    JR Z,.NO_LOOP
    LD HL,(AY_LOOP_OFFSET)
    LD DE,24
    OR A
    SBC HL,DE
    JP C,AY_STOP_RAW
    LD HL,(AYM2_STREAM_END_OFFSET)
    DEC HL                       ; END offset: exclusive upper bound
    LD DE,(AY_LOOP_OFFSET)
    OR A
    SBC HL,DE
    JP Z,AY_STOP_RAW
    JP C,AY_STOP_RAW
    LD HL,(AY_BASE)
    LD DE,(AY_LOOP_OFFSET)
    ADD HL,DE
    JP C,AY_STOP_RAW
    LD (AY_LOOP_PTR),HL
    JR .VALIDATE
.NO_LOOP:
    LD HL,(AY_LOOP_OFFSET)
    LD A,H
    OR L
    JP NZ,AY_STOP_RAW
.VALIDATE:
    CALL AYM2_VALIDATE_DICTIONARY
    JP C,AY_STOP_RAW
    LD A,2
    LD (AY_MODE),A
    LD A,1
    LD (AY_ACTIVE),A
    RET

; Validate dictionary pointer layout exactly once at play start:
; offsets must target densely packed, non-recursive full FRAME
; templates ending exactly at AY_END_PTR.
; This is deliberately outside the IM2 hot path.
; OUT carry=error, carry clear=valid. Clobbers AF BC DE HL.
AYM2_VALIDATE_DICTIONARY:
    LD HL,(AYM2_DICT_TABLE_PTR)
    LD (AYM2_SCAN_PTR),HL
    LD HL,(AYM2_DICT_BODY_PTR)
    LD (AYM2_EXPECT_PTR),HL
    LD A,(AYM2_DICT_COUNT)
    LD (AYM2_SCAN_LEFT),A
.NEXT:
    LD A,(AYM2_SCAN_LEFT)
    OR A
    JR Z,.DONE
    LD HL,(AYM2_SCAN_PTR)
    LD E,(HL)
    INC HL
    LD D,(HL)
    INC HL
    LD (AYM2_SCAN_PTR),HL
    LD HL,(AY_BASE)
    ADD HL,DE
    JR C,.ERROR
    LD DE,(AYM2_EXPECT_PTR)
    OR A
    SBC HL,DE
    JR NZ,.ERROR
    LD HL,(AYM2_EXPECT_PTR)
    LD A,(HL)
    CP #80                       ; dictionary contains only full FRAME
    JR NZ,.ERROR
    INC HL
    LD C,(HL)
    INC HL
    LD B,(HL)
    INC HL
    LD A,B
    AND #C0                      ; only 14 AY register mask bits
    JR NZ,.ERROR
    LD D,14
.MASK:
    SRL B
    RR C
    JR NC,.SKIP
    INC HL
.SKIP:
    DEC D
    JR NZ,.MASK
    PUSH HL
    LD DE,(AY_END_PTR)
    OR A
    SBC HL,DE
    POP HL
    JR C,.SAVE_NEXT
    JR NZ,.ERROR                ; exactly END is valid on final entry
.SAVE_NEXT:
    LD (AYM2_EXPECT_PTR),HL
    LD HL,AYM2_SCAN_LEFT
    DEC (HL)
    JR .NEXT
.DONE:
    LD HL,(AYM2_EXPECT_PTR)
    LD DE,(AY_END_PTR)
    OR A
    SBC HL,DE
    JR NZ,.ERROR
    OR A                         ; clear carry for caller
    RET
.ERROR:
    SCF
    RET

; Called only when AY_MODE=2 and AY_WAIT is zero.
AYM2_TICK_DECODE:
.DECODE:
    LD HL,(AY_POS)
    LD DE,(AYM2_STREAM_END_PTR)
    PUSH HL
    OR A
    SBC HL,DE
    POP HL
    JP NC,AY_STOP_RAW
    LD A,(HL)
    INC HL
    OR A
    JP Z,.END                   ; distant loop/stop handler
    CP #80
    JR Z,.FULL
    JR C,.WAIT
    CP #A0
    JR NC,.TOKEN
    CP #81
    JP C,AY_STOP_RAW
    CP #8F
    JR C,.ONE_REG
    CP #92
    JR C,.MUTE
    CP #9D
    JR C,.SHORT
    JP AY_STOP_RAW               ; 9D..9F are reserved
.WAIT:
    DEC A
    LD (AY_WAIT),A
    LD (AY_POS),HL
    RET
.FULL:
    XOR A
    LD (AYM2_FROM_DICT),A
    JP AYM2_READ_FRAME           ; HL points at mask16
.ONE_REG:
    SUB #81
    LD D,A                       ; R0..R13
    LD E,(HL)
    INC HL
    LD (AY_POS),HL
    JP AYM2_WRITE_ONE
.MUTE:
    SUB #8F
    ADD A,8
    LD D,A                       ; R8 / R9 / R10
    LD E,0
    LD (AY_POS),HL
    JP AYM2_WRITE_ONE
.SHORT:
    LD (AYM2_STREAM_RESUME),HL   ; opcode's operands start here
    SUB #92
    ADD A,A
    LD E,A
    LD D,0
    LD HL,AYM2_SHORT_MASKS
    ADD HL,DE
    LD C,(HL)
    INC HL
    LD B,(HL)
    LD HL,(AYM2_STREAM_RESUME)
    XOR A
    LD (AYM2_FROM_DICT),A
    JP AYM2_APPLY_MASK           ; HL=values, BC=mask
.TOKEN:
    LD (AYM2_STREAM_RESUME),HL   ; actual stream resumes here
    SUB #A0
    LD E,A
    LD A,(AYM2_DICT_COUNT)
    CP E
    JP Z,AY_STOP_RAW
    JP C,AY_STOP_RAW
    LD A,E
    ADD A,A
    LD E,A
    LD D,0
    LD HL,(AYM2_DICT_TABLE_PTR)
    ADD HL,DE
    LD E,(HL)
    INC HL
    LD D,(HL)
    LD HL,(AY_BASE)
    ADD HL,DE
    JP C,AY_STOP_RAW
    LD DE,(AYM2_DICT_BODY_PTR)
    PUSH HL
    OR A
    SBC HL,DE
    POP HL
    JP C,AY_STOP_RAW
    LD A,(HL)
    CP #80
    JP NZ,AY_STOP_RAW
    INC HL
    LD A,1
    LD (AYM2_FROM_DICT),A
    JP AYM2_READ_FRAME
.END:
    LD A,(AY_FLAGS)
    AND 1
    JP Z,AY_STOP_RAW
    LD HL,(AY_LOOP_PTR)
    LD A,(HL)
    OR A
    JP Z,AY_STOP_RAW
    LD (AY_POS),HL
    JP .DECODE                   ; loop takes no extra 20ms slot

; Full FRAME and dictionary bodies have exactly the same layout.
; IN HL -> mask16, AYM2_FROM_DICT selects frame cursor source.
AYM2_READ_FRAME:
    LD C,(HL)
    INC HL
    LD B,(HL)
    INC HL
    LD A,B
    AND #C0
    JP NZ,AY_STOP_RAW
    JP AYM2_APPLY_MASK

; IN HL -> values, BC = 14-bit mask; one AY register per set bit.
; R13 ALWAYS writes (even if value and shadow match).
AYM2_APPLY_MASK:
    LD D,0
.NEXT:
    LD A,B
    OR C
    JR Z,.DONE
    BIT 0,C
    JR Z,.ADVANCE
    LD E,(HL)
    INC HL
    CALL AYM2_WRITE_ONE
.ADVANCE:
    SRL B
    RR C
    INC D
    JR .NEXT
.DONE:
    LD A,(AYM2_FROM_DICT)
    OR A
    JR Z,.DIRECT
    LD HL,(AYM2_STREAM_RESUME)   ; keep dictionary data out of stream
.DIRECT:
    LD (AY_POS),HL
    RET

; IN D=register (0..13), E=value. Preserve BC/DE/HL.
; R7 GPIO bits 6/7 must remain 0. The hardware register write
; is mandatory even if the shadow already holds the same value.
AYM2_WRITE_ONE:
    LD A,D
    CP 7
    JR NZ,.STORE
    LD A,E
    AND #3F
    LD E,A
.STORE:
    PUSH HL
    LD HL,AY_SHADOW
    LD A,D
    ADD A,L
    LD L,A
    JR NC,.INDEX_OK
    INC H
.INDEX_OK:
    LD (HL),E
    LD A,D
    CALL AY_WRITE_REG
    POP HL
    RET

; 92..9C short operand masks, in opcode order.
AYM2_SHORT_MASKS:
    DW #0103                    ; 92: R0,R1,R8
    DW #020C                    ; 93: R2,R3,R9
    DW #0430                    ; 94: R4,R5,R10
    DW #0003                    ; 95: R0,R1
    DW #000C                    ; 96: R2,R3
    DW #0030                    ; 97: R4,R5
    DW #01C0                    ; 98: R6,R7,R8
    DW #02C0                    ; 99: R6,R7,R9
    DW #04C0                    ; 9A: R6,R7,R10
    DW #0700                    ; 9B: R8,R9,R10
    DW #0780                    ; 9C: R7,R8,R9,R10

AYM2_DICT_COUNT:         DB 0
AYM2_FROM_DICT:          DB 0
AYM2_SCAN_LEFT:          DB 0
AYM2_STREAM_END_OFFSET:  DW 0
AYM2_DICT_BODY_OFFSET:   DW 0
AYM2_STREAM_END_PTR:     DW 0
AYM2_DICT_TABLE_PTR:     DW 0
AYM2_DICT_BODY_PTR:      DW 0
AYM2_STREAM_RESUME:      DW 0
AYM2_SCAN_PTR:           DW 0
AYM2_EXPECT_PTR:         DW 0
