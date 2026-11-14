# SpaceCan demo / Демоверсия SpaceCan

**Русский:** скачайте `SpaceCan.tap` из Assets, на ZX Spectrum используйте `LOAD ""`.

**English:** Download `SpaceCan.tap` from Assets; run `LOAD ""` on ZX Spectrum.

### Изменения / What's new

- Босс стреляет из двух пушек в сторону запомненной позиции корабля, вместо фиксированных X=14/16 / Boss volleys now aim at the player's position at firing time, rather than staying in fixed lanes.
- Во время боя с боссом выстрелы игрока ограничены одним за 18 кадров / Player firing limited to once every 18 frames in the boss fight.
- У босса 10 делений по 2 попадания: первое заставляет мигать деление, второе делает его красным / Boss HP gauge: 10 segments, two hits each; first blinks, second turns red.
- Босс находится выше, на Y=7 вместо Y=12 / Boss stops higher on the screen.
- Обновлён необязательный звук двигателя; сейчас переключатель `BEEPER_ENGINE_ENABLED` стоит в `0` — установите `1`, чтобы услышать новый вариант / Optional engine buzz was varied; build currently leaves its switch off to respect current configuration.

[Полная история / Full changelog](https://github.com/knowsbetteralex/SpaceCan/blob/main/CHANGELOG.md)
