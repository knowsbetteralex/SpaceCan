# SpaceCan demo / Демоверсия SpaceCan

**Русский:** скачайте `SpaceCan.tap` из Assets, на ZX Spectrum используйте `LOAD ""`.

**English:** Download `SpaceCan.tap` from Assets; run `LOAD ""` on ZX Spectrum.

### Изменения / What's new

- Декодер AY теперь читает **AYM1 и AYM2** в одной сборке: сжатые треки меню и игры используют AYM2 v1, а финалы сохраняют AYM1. / Dual AYM1/AYM2 playback, compressed main/menu music without changing the sounds.
- Сжатые два главных трека занимают 4 475 вместо 8 600 байт (минус 47,97% данных; дополнительный код плеера учитывается отдельно). / The two compressed themes save 4,125 bytes of music data.

- Добавлено `MOVE!`: после одной высоты коридора без движения предупреждение, через три — штраф. При движении, но отсутствии уничтоженных астероидов по-прежнему работает `SHOOT!` / New priority MOVE! idle movement warning and penalty after three corridor traversals; SHOOT! stays for missed kills while moving.
- По-прежнему основной режим босса — `0:MIX` со всеми предыдущими атаками / MIX remains the default boss attack pattern.

- Новая лаборатория стрельбы босса: переключайте **0=MIX, 1=AIM, 2=FAN, 3=PLASMA, 4=DOUBLE, 5=HOMING, 6=ADAPT** прямо во время боя / Press 0..6 during the boss encounter to switch attack patterns.
- Фиолетовая плазма не уничтожается нашими пулями, после предупреждения кабины; жёлтые ракеты подруливают, двойные залпы догоняют друг друга / Invulnerable plasma, homing rounds, delayed double bursts, and spread volleys.
- В смешанном режиме двойные залпы включаются при HP босса ≤ 50%, а стоящий 2 секунды игрок провоцирует плазму / MIX activates delayed bursts at half health and fires plasma at a camping player.

- Десятикадровый взрыв босса (область до 72×64 пикселей) с отдельными шумовыми эффектами beeper и AY / 10-stage cinematic boss explosion with beeper and AY noise.
- Поединок начинается после первого залпа босса; взаимное уничтожение пуль сопровождается анимацией / The boss fires first; bullet clashes animate.
- Раздельные победная и проигрышная концовки для обоих аудиоустройств; биперная мелодия звучит первой / Distinct win and lose jingles for beeper and AY, played in that order.

- Босс стреляет из двух пушек в сторону запомненной позиции корабля, вместо фиксированных X=14/16 / Boss volleys now aim at the player's position at firing time, rather than staying in fixed lanes.
- Во время боя с боссом выстрелы игрока ограничены одним за 18 кадров / Player firing limited to once every 18 frames in the boss fight.
- У босса 10 делений по 2 попадания: первое заставляет мигать деление, второе делает его красным / Boss HP gauge: 10 segments, two hits each; first blinks, second turns red.
- Босс находится выше, на Y=7 вместо Y=12 / Boss stops higher on the screen.
- Обновлён необязательный звук двигателя; сейчас переключатель `BEEPER_ENGINE_ENABLED` стоит в `0` — установите `1`, чтобы услышать новый вариант / Optional engine buzz was varied; build currently leaves its switch off to respect current configuration.

[Полная история / Full changelog](https://github.com/knowsbetteralex/SpaceCan/blob/main/CHANGELOG.md)
