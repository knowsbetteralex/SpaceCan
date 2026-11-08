; -------------------------------------------------------------
; Border phase diagnostics for ZX Spectrum 48K.
;
; Set DEBUG_BORDER=0 for a normal game build (no phase code emitted).
; Phase writes must update SFX_FE_BASE before touching port #FE
; so sound pulses preserve border colour and MIC state.
; -------------------------------------------------------------

DEBUG_BORDER EQU 0

DBG_RENDER_COLOUR EQU 2  ; red: sprites/background
DBG_HUD_COLOUR    EQU 6  ; yellow: HUD
DBG_INPUT_COLOUR  EQU 5  ; cyan: keyboard
DBG_LOGIC_COLOUR  EQU 4  ; green: game update
DBG_IDLE_COLOUR   EQU 1  ; blue: remainder of frame / HALT

MACRO DEBUG_PHASE colour
    IF DEBUG_BORDER
        LD A,colour
        LD (SFX_FE_BASE),A
        OUT (#FE),A
    ENDIF
ENDM
