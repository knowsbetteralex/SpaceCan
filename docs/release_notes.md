# SpaceCan — предфинальная демоверсия / Pre-final demo

**Русский:** В Assets лежат **два** TAP: `SpaceCan-AY.tap`
(для Spectrum 48K с AY) и `SpaceCan-Beeper.tap` (без AY).
Оба запускаются через `LOAD ""`.

**English:** Two builds: `SpaceCan-AY.tap` (AY + beeper)
and `SpaceCan-Beeper.tap` (beeper only). Both autostart via `LOAD ""`.

## Что нового / What's new

- Пороги зафиксированы: **2048** очков — ускорение 2×, **4096** — бой с боссом / 2× speed at 2048 points; boss at 4096.
- Босс всегда использует **MIX**: прицельные, веер, несбиваемая плазма, двойные и самонаводящиеся атаки. Экспериментальные клавиши 0–6 отключены / Fixed mixed boss attacks, no experimental mode selection.
- На панели вместо `0:MIX` выводится **AVOID** и пурпурная 8×8 пиктограмма **реального несбиваемого снаряда** / Boss HUD shows AVOID and the actual invulnerable plasma sprite.
- В версии с AY подключены ровно **4 AYM2 v1**: меню, игра, победа, поражение. Все три сюжетные биперные мелодии разные; каждая звучит **до AY-трека** на своём экране / Four AYM2 tunes, three distinct beeper jingles, beeper before AY in menu/endings.
- При победе отображается **FINAL SCORE**; финальный экран остаётся до конца AY (минимум 3 с, максимум 60 с) / Victory score and non-truncated ending music.
- Сохранены предупреждения `MOVE!`/`SHOOT!`, 10-сегментный штраф, 4 жизни и все ранее реализованные эффекты / Previous gameplay retained.
- Сборка выпускает два самостоятельных TAP без необходимости переключать исходники вручную; в beeper-only AY-код и AYM2-ресурсы исключены / Two independently assembled variants.

**Ожидается только новая AY-музыка победы и поражения** (пока там
раздельные временные темы). После её добавления — окончательный демо-релиз.

**The two separate ending AY tracks are placeholders pending final compositions.**

[История / Changelog](https://github.com/knowsbetteralex/SpaceCan/blob/main/CHANGELOG.md)
