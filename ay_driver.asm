; -------------------------------------------------------------
; AY-3-891x hardware access: ZX 128-compatible I/O decode.
; Delta-C uses an external AY board; confirm #FFFD/#BFFD decoding.
; IN  AY_WRITE_REG: A=register 0..13, E=value
; OUT: AF/flags destroyed; BC, DE, HL, IX preserved.
; R14/R15 (GPIO) are never accessed by the music player.
; -------------------------------------------------------------
AY_PORT_SELECT EQU #FFFD
AY_PORT_WRITE  EQU #BFFD

AY_WRITE_REG:
    PUSH BC
    LD BC,AY_PORT_SELECT
    OUT (C),A
    LD BC,AY_PORT_WRITE
    LD A,E
    OUT (C),A
    POP BC
    RET

; Hardware mute: R7 disables all tone/noise and R8-R10 are zero.
; R7 bits 6/7 are zero (GPIO inputs), not used for peripherals.
; Clobbers AF, E. Preserves BC, HL, IX.
AY_SILENCE:
    LD E,#3F
    LD A,7
    CALL AY_WRITE_REG
    LD E,0
    LD A,8
    CALL AY_WRITE_REG
    LD A,9
    CALL AY_WRITE_REG
    LD A,10
    JP AY_WRITE_REG
