; -------------------------------------------------------------
; SpaceCan Step 18: external AYM1 music resources, zero inline music.
; Drop converted full-format .aym files into assets/music/ and rebuild.
; Each .aym contains a complete 16-byte AYM1 header + register stream.
;
; Target AY clock: 2000000 Hz. If your board uses a different clock,
; export the .aym files for that clock; source assembly no longer
; recalculates the notes contained in these binary resources.
; -------------------------------------------------------------

IF AY_MUSIC_ENABLED
AY_MUSIC_TITLE:
    INCBIN "assets/music/title.aym"

AY_MUSIC_GAME:
    INCBIN "assets/music/midiver.aym"

AY_MUSIC_GAME_OVER:
    INCBIN "assets/music/game_over.aym"
ENDIF
