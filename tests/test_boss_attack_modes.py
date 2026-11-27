"""Boss-attack selector and trajectory invariants (non-emulator checks)."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def asm(path):
    return (ROOT / path).read_text(encoding="utf-8")


def equ(path, name):
    match = re.search(
        rf"(?m)^{re.escape(name)}\s+EQU\s+(\d+)", asm(path)
    )
    if match is None:
        raise AssertionError(f"Missing decimal constant: {name}")
    return int(match.group(1))


class BossAttackModes(unittest.TestCase):
    def test_fixed_mix_and_six_cell_avoid_plasma_hud(self):
        src = asm("boss_attacks.asm")
        self.assertNotIn("BOSS_READ_ATTACK_KEYS:", src)
        self.assertNotIn("BOSS_MODE_TEXT_MIX:", src)
        self.assertNotIn("BOSS_ATTACK_MODE:", src)
        self.assertIn("BOSS_FIRE_DISPATCH:", src)
        self.assertIn("LD A,(BOSS_ATTACK_CYCLE)", src)
        self.assertIn("BOSS_AVOID_TEXT: DB \"AVOID\",0", src)
        self.assertIn("LD BC,#020D", src)
        self.assertIn("LD BC,#0212", src)
        self.assertIn("LD DE,HOSTILE_PLASMA_SPRITE", src)
        self.assertIn("LD A,(HOSTILE_PLASMA_ATTR)", src)
        self.assertIn("JP READ_FIRE_KEY", asm("logic.asm"))
        self.assertIn("JP RENDER_BOSS_ATTACK_MODE", asm("ui.asm"))
        self.assertNotIn("BOSS_DEFAULT_ATTACK_MODE", asm("main.asm"))

    def test_projectile_pool_and_kinds(self):
        main, shots = asm("main.asm"), asm("hostile_bullets.asm")
        self.assertEqual(equ("main.asm", "MAX_HOSTILE_BULLETS"), 12)
        self.assertEqual(equ("main.asm", "HOSTILE_BULLET_SIZE"), 10)
        self.assertIn("HB_KIND     EQU 8", shots)
        self.assertIn("HB_STEP     EQU 9", shots)
        self.assertIn("LD (IX+HB_KIND),A", shots)
        self.assertIn("LD (IX+HB_STEP),A", shots)
        self.assertIn("CP STATE_BOSS", shots)
        self.assertIn("LD (BOSS_FIGHT_READY),A", shots)

    def test_plasma_warning_and_invulnerable_clash(self):
        attacks, hostile = asm("boss_attacks.asm"), asm("hostile_bullets.asm")
        self.assertEqual(equ("main.asm", "BOSS_PLASMA_WARMUP"), 12)
        self.assertIn("LD (BOSS_PLASMA_CHARGE),A", attacks)
        self.assertIn("LD A,HB_KIND_PLASMA", attacks)
        self.assertIn("LD A,(BOSS_PLASMA_CHARGE)", asm("boss.asm"))
        self.assertRegex(
            hostile, r"CP HB_KIND_PLASMA\s+JR Z,\.SPARK_ONLY\s+"
            r"XOR A\s+LD \(IY\+HB_ACTIVE\),A"
        )
        self.assertIn("HOSTILE_PLASMA_SPRITE:", hostile)

    def test_double_and_homing_are_avoidable(self):
        attacks, hostile = asm("boss_attacks.asm"), asm("hostile_bullets.asm")
        self.assertEqual(equ("main.asm", "BOSS_DOUBLE_DELAY"), 10)
        self.assertIn("LD (BOSS_DOUBLE_WAIT),A", attacks)
        self.assertIn("LD (BOSS_DOUBLE_TARGET),A", attacks)
        self.assertIn("LD A,(BOSS_DOUBLE_TARGET)", attacks)
        self.assertIn("INC (IX+HB_STEP)", hostile)
        self.assertIn("CP PLAYFIELD_BOTTOM-5", hostile)
        self.assertIn("LD (IX+HB_TARGET_X),A", hostile)

    def test_idle_player_forces_plasma_and_movement_resets(self):
        attacks = asm("boss_attacks.asm")
        self.assertEqual(equ("main.asm", "BOSS_STILL_LIMIT"), 100)
        self.assertIn("BOSS_TRACK_STILLNESS:", attacks)
        self.assertIn("LD (BOSS_STILL_FRAMES),A", attacks)
        self.assertIn("LD A,(SHIP_HALF_POS)", attacks)
        self.assertIn("LD (BOSS_SELECTED_ATTACK),A", attacks)
        self.assertIn("CP BOSS_MAX_HP/2+1", attacks)

    def test_fan_spreads_three_safe_lane_targets(self):
        left, right = 8, 23
        for player_x in range(left, right + 1):
            targets = (max(left, player_x - 2),
                       player_x,
                       min(right, player_x + 2))
            self.assertTrue(all(left <= x <= right for x in targets))
            self.assertEqual(targets, tuple(sorted(targets)))
            self.assertEqual(targets[1], player_x)

    def test_mix_keeps_queued_and_plasma_attacks(self):
        src = asm("boss_attacks.asm")
        self.assertIn("CALL BOSS_TICK_DOUBLE", src)
        self.assertIn("JP BOSS_TICK_PLASMA", src)
        self.assertIn("LD (BOSS_ATTACK_CYCLE),A", src)
        self.assertIn("LD (BOSS_SELECTED_ATTACK),A", src)
        self.assertIn("JP BOSS_FIRE_CHOSEN", src)
        self.assertIn("LD A,2                    ; anti-camping plasma", src)


if __name__ == "__main__":
    unittest.main()
