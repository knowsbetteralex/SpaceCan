; -------------------------------------------------------------
; SpaceCan demo boss: a fixed MIX of all five avoidable patterns.
; The boss HUD warns about the invulnerable plasma with the same
; 8x8 sprite used for the real projectile, not a mode selector.
; -------------------------------------------------------------

; Draw exactly six cells: AVOID (five ROM glyphs) followed
; by the ACTUAL 8x8 invulnerable plasma sprite in magenta.
; Called from RENDER_HUD, never from IM2.
RENDER_BOSS_AVOID_DIRTY: DB 1
BOSS_ATTACK_CYCLE: DB 0
BOSS_SELECTED_ATTACK: DB 0
BOSS_STILL_LAST_X: DB 0
BOSS_STILL_LAST_HALF: DB 0
BOSS_STILL_FRAMES: DB 0
BOSS_PLASMA_CHARGE: DB 0
BOSS_PLASMA_TARGET: DB 0
BOSS_DOUBLE_WAIT: DB 0
BOSS_DOUBLE_TARGET: DB 0
BOSS_DOUBLE_X: DB 0

BOSS_AVOID_TEXT: DB "AVOID",0
