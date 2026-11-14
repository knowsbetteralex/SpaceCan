"""Boss balance regression checks (source contracts and frame-level models).

These checks are not a CPU/ZX Spectrum emulator. The full game is also
assembled with sjasmplus by the release workflow.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def asm(path):
    return (ROOT / path).read_text(encoding="utf-8")


def equ(name):
    m = re.search(r"(?m)^" + re.escape(name) + r"\s+EQU\s+(\d+)", asm("main.asm"))
    assert m, name
    return int(m.group(1))


def aimed_pair(player_x):
    """The two target cells selected by BOSS_FIRE_PAIR."""
    last = equ("PLAYFIELD_RIGHT")
    return (min(player_x, last - 1), min(player_x + 1, last))


def approach(spawn_x, target_x, spawn_y, player_y):
    """One cell horizontally and one vertically per hostile move tick."""
    x = spawn_x
    ys = []
    for y in range(spawn_y + 1, player_y + 1):
        if x < target_x:
            x += 1
        elif x > target_x:
            x -= 1
        ys.append((x, y))
    return ys


class BossFightChecks(unittest.TestCase):
    def test_boss_position_and_slow_fire(self):
        self.assertEqual(equ("BOSS_TARGET_Y"), 7)
        self.assertEqual(equ("BOSS_PLAYER_SHOT_DELAY"), 18)
        self.assertEqual(equ("BOSS_FIRE_DELAY"), 45)
        bullets = asm("bullets.asm")
        self.assertIn("LD A,(BOSS_SHOT_CLOCK)", bullets)
        self.assertIn("RET NZ", bullets)
        self.assertIn("LD (BOSS_SHOT_CLOCK),A", bullets)
        self.assertIn("LD A,BOSS_PLAYER_SHOT_DELAY", bullets)
        logic = asm("logic.asm")
        self.assertIn("UPDATE_BOSS_GAME:", logic)
        self.assertIn("LD HL,BOSS_SHOT_CLOCK", logic)

    def test_two_cannons_are_aimed_and_targets_are_frozen(self):
        hostile = asm("hostile_bullets.asm")
        boss = asm("boss.asm")
        self.assertEqual(equ("HOSTILE_BULLET_SIZE"), 8)
        self.assertIn("HB_TARGET_X EQU 7", hostile)
        self.assertIn("LD (IX+HB_TARGET_X),E", hostile)
        self.assertIn("LD A,(IX+HB_TARGET_X)", hostile)
        self.assertIn("INC (IX+HB_X)", hostile)
        self.assertIn("DEC (IX+HB_X)", hostile)
        self.assertIn("BOSS_FIRE_PAIR:", boss)
        self.assertIn("CALL SPAWN_HOSTILE_BULLET", boss)
        self.assertIn("JP SPAWN_HOSTILE_BULLET", boss)
        self.assertIn("JP START_SHIP_EXPLOSION", hostile)

    def test_center_is_not_a_safe_lane(self):
        # Old cannon paths were X=14 and X=16 forever, with ship at X=15.
        # New paths head toward a snapshot of the player's current lane.
        y0 = equ("BOSS_TARGET_Y") + 2
        ship_y = 22
        left_x = equ("BOSS_X_CENTER")
        right_x = left_x + 2
        for player_x in range(8, 24):
            with self.subTest(player_x=player_x):
                left_target, right_target = aimed_pair(player_x)
                left = approach(left_x, left_target, y0, ship_y)
                right = approach(right_x, right_target, y0, ship_y)
                self.assertEqual(left[-1], (left_target, ship_y))
                self.assertEqual(right[-1], (right_target, ship_y))
                self.assertTrue(
                    any(x == player_x for x, y in (left[-1], right[-1])),
                    f"Player lane {player_x} should be threatened if stationary",
                )
                # Both projectiles have the same Y but different X.
                for (a, _), (b, _) in zip(left, right):
                    self.assertLess(a, b)

    def test_two_hits_per_segment_and_blink(self):
        boss = asm("boss.asm")
        ui = asm("ui.asm")
        self.assertIn("BOSS_HIT_HALF:", asm("data.asm"))
        self.assertIn("BOSS_BLINK_COUNTER:", asm("data.asm"))
        self.assertIn("JR NZ,.SECOND_HIT", boss)
        self.assertIn("DEC (HL)", boss)
        self.assertIn("LD (BOSS_HIT_HALF),A", boss)
        self.assertIn("CALL BOSS_UPDATE_HALF_BLINK", boss)
        self.assertIn("AND 7", boss)
        self.assertIn("LD A,(BOSS_BLINK_COUNTER)", ui)
        self.assertIn("LD A,#46", ui)
        self.assertIn("LD A,#42", ui)
        remaining, half = 10, 0
        for hit in range(1, 21):
            if half:
                half = 0
                remaining -= 1
            else:
                half = 1
            self.assertEqual(remaining, 10 - hit // 2)
            self.assertEqual(half, hit % 2)
        self.assertEqual((remaining, half), (0, 0))

    def test_pause_and_respawn_keep_existing_invariants(self):
        main = asm("main.asm")
        boss = asm("boss.asm")
        self.assertIn("CP STATE_PAUSED", main)
        self.assertIn("CALL BOSS_RESET_ENTRY", main)
        self.assertIn("LD (BOSS_SHOT_CLOCK),A", boss)
        # Half-damaged segment should not be reset on player respawn.
        start = boss.index("BOSS_RESET_ENTRY:")
        end = boss.index("BOSS_DISABLE_ASTEROIDS:", start)
        self.assertNotIn("LD (BOSS_HIT_HALF),A", boss[start:end])


if __name__ == "__main__":
    unittest.main()
