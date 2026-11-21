; -------------------------------------------------------------
; SpaceCan: external versioned AYM1/AYM2 resources (mixed formats).
; The first four bytes of each INCBIN asset select the player codec.
; Two large tracks use AYM2 v1; short ending themes remain AYM1.
;
; Target AY clock: 2000000 Hz. If your board uses a different clock,
; export the .aym files for that clock; source assembly no longer
; recalculates the notes contained in these binary resources.
; -------------------------------------------------------------

    IF AY_MUSIC_ENABLED
AY_MUSIC_TITLE:
    INCBIN "assets/music/main_menu1.aym"

AY_MUSIC_GAME:
    INCBIN "assets/music/midiver1.aym"

AY_MUSIC_GAME_OVER:
    INCBIN "assets/music/game_over.aym"

AY_MUSIC_VICTORY:
    INCBIN "assets/music/victory.aym"
    ENDIF
