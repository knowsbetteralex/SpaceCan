; -------------------------------------------------------------
; SpaceCan pre-final demo: four independent AYM2 v1 music tracks.
; Menu / in-game / victory / defeat. No AY music runs during beeper intro.
; Victory and defeat AYM2 tracks are placeholders until final tunes arrive.
; AY_PLAY reads all tracks through the same versioned decoder.
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
    INCBIN "assets/music/game_over1.aym"

AY_MUSIC_VICTORY:
    INCBIN "assets/music/victory1.aym"
    ENDIF
