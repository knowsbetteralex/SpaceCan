; -------------------------------------------------------------
; AYM1 v1 built-in test tracks (not converted MIDI).
; Future converter writes ready .aym files for INCBIN:
;    AY_MUSIC_GAME: INCBIN "assets/music/game.aym"
; The music player itself never parses MIDI, notes or instruments.
; Each first frame sets frequencies, mixer and channel levels.
; Target AY clock is AY_TARGET_CLOCK (default 2 MHz).
; -------------------------------------------------------------

AY_MUSIC_TITLE:
    DB "AYM1",50,1               ; looped
    DW AY_TITLE_END-AY_MUSIC_TITLE
    DW AY_TITLE_LOOP-AY_MUSIC_TITLE
    DW 0
    DW AY_TARGET_CLOCK & #FFFF, AY_TARGET_CLOCK >> 16
AY_TITLE_LOOP:
    DB #80
    DW #07BF                     ; R0..5, R7, R8..10
    DW 239,319,379               ; C5 + G4 + E4 (three overlapping voices)
    DB #38,8,4,3                 ; tone only on A/B/C, distinct volumes
    DB 7                          ; 7 unchanged video frames
    DB #80
    DW #0003
    DW 213                       ; D5 melody, other voices sustain
    DB 7
    DB #80
    DW #0003
    DW 190                       ; E5
    DB 7
    DB #80
    DW #0003
    DW 159                       ; G5
    DB 7
    DB #80
    DW #0003
    DW 239                       ; C5 again
    DB 7
    DB 0                          ; loop
AY_TITLE_END:

AY_MUSIC_GAME:
    DB "AYM1",50,1
    DW AY_GAME_END-AY_MUSIC_GAME
    DW AY_GAME_LOOP-AY_MUSIC_GAME
    DW 0
    DW AY_TARGET_CLOCK & #FFFF, AY_TARGET_CLOCK >> 16
AY_GAME_LOOP:
    DB #80
    DW #07BF
    DW 239,638,478               ; C5 + G3 + C4, sustained overlap
    DB #38,5,3,3
    DB 11
    DB #80
    DW #0003
    DW 190                       ; E5
    DB 11
    DB #80
    DW #0003
    DW 159                       ; G5
    DB 11
    DB #80
    DW #0003
    DW 190                       ; E5
    DB 11
    DB 0
AY_GAME_END:

AY_MUSIC_GAME_OVER:
    DB "AYM1",50,0               ; one-shot ending
    DW AY_OVER_END-AY_MUSIC_GAME_OVER
    DW 0
    DW 0
    DW AY_TARGET_CLOCK & #FFFF, AY_TARGET_CLOCK >> 16
    DB #80
    DW #07BF
    DW 239,638,478               ; C5 and muted supporting channels
    DB #3E,8,0,0                 ; only A tone enabled
    DB 7
    DB #80
    DW #0003
    DW 284                       ; A4
    DB 7
    DB #80
    DW #0003
    DW 319                       ; G4
    DB 7
    DB #80
    DW #0003
    DW 379                       ; E4
    DB 7
    DB #80
    DW #0780                     ; R7 + R8-R10
    DB #3F,0,0,0
    DB 0                          ; END, stop/mute
AY_OVER_END:
