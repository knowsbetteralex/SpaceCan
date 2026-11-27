"""Source contracts and distance-based models for MOVE!/SHOOT! pressure.

These tests do not emulate the Spectrum CPU; GitHub Actions also assembles
the program with sjasmplus.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCREEN_ROWS = 20
PENALTY_ROWS = 60


def src(filename):
    return (ROOT / filename).read_text(encoding="utf-8")


def simulate(events):
    move_rows = shoot_rows = 0
    move_warn = shoot_warn = 0
    penalties = []
    for frame, (world_step, moved, kill) in enumerate(events):
        if moved:
            move_rows, move_warn = 0, 0
        if kill:
            shoot_rows, shoot_warn = 0, 0
        if not world_step:
            continue
        if not moved:
            move_rows += 1
            if move_rows == SCREEN_ROWS:
                move_warn = 1
            if move_rows == PENALTY_ROWS:
                move_rows, shoot_rows = 0, 0
                penalties.append((frame, "MOVE"))
                continue
        if not kill:
            shoot_rows += 1
            if shoot_rows == SCREEN_ROWS:
                shoot_warn = 1
            if shoot_rows == PENALTY_ROWS:
                shoot_rows = 0
                if not move_warn:
                    penalties.append((frame, "SHOOT"))
    return move_warn, shoot_warn, penalties


class PriorityWarningTests(unittest.TestCase):
    def test_actual_movement_and_separate_counters(self):
        logic = src("logic.asm")
        main = src("main.asm")
        data = src("data.asm")
        self.assertIn("CALL RESET_MOVE_TRAVEL", logic)
        self.assertIn("LD (MOVE_CHANGED_THIS_TICK),A", logic)
        self.assertIn("LD (MOVE_WARNING_ACTIVE),A", logic)
        self.assertIn("LD (MOVE_TRAVEL_ROWS),A", logic)
        self.assertIn("LD (MISS_KILLED_THIS_TICK),A", logic)
        self.assertIn("LD (MISS_TRAVEL_ROWS),A", logic)
        self.assertIn("CP MOVE_DISTANCE_LIMIT", logic)
        self.assertIn("CP MISS_DISTANCE_LIMIT", logic)
        self.assertIn("LD A,(ENEMY_MOVE_NOW)", logic)
        self.assertIn("MOVE_DISTANCE_LIMIT   EQU MISS_SCREEN_ROWS*3", main)
        self.assertIn("MOVE_TRAVEL_ROWS:", data)
        self.assertIn("MOVE_WARNING_ACTIVE:", data)
        self.assertIn("MOVE_CHANGED_THIS_TICK:", data)
        self.assertNotIn("BOSS_DEFAULT_ATTACK_MODE", main)
        self.assertIn("Fixed demo boss MIX", main)

    def test_warning_select_and_restore_same_window(self):
        ui = src("ui.asm")
        self.assertIn("LD A,(MOVE_WARNING_ACTIVE)", ui)
        self.assertIn("LD A,(SHOOT_WARNING_ACTIVE)", ui)
        self.assertLess(ui.index("LD A,(MOVE_WARNING_ACTIVE)"),
                        ui.index("LD A,(SHOOT_WARNING_ACTIVE)"))
        self.assertIn("LD E,2", ui)
        self.assertIn("LD E,1", ui)
        self.assertIn("JP RESTORE_SHOOT_BACKGROUND", ui)
        self.assertIn("LD DE,HUD_LABEL_MOVE", ui)
        self.assertIn('DB "MOVE! ",0', src("data.asm"))
        self.assertIn("CALL RENDER_SHOOT_WARNING", ui)
        self.assertIn("JP RENDER_BOSS_ATTACK_MODE", ui)

    def test_reset_on_respawn_and_new_game(self):
        main = src("main.asm")
        begin = main.index("START_NEW_GAME:")
        end = main.index("MAIN_LOOP:", begin)
        segment = main[begin:end]
        self.assertGreaterEqual(segment.count("LD (MOVE_WARNING_ACTIVE),A"), 2)
        self.assertGreaterEqual(segment.count("LD (MOVE_TRAVEL_ROWS),A"), 2)
        self.assertIn("LD (SHOOT_WARNING_ACTIVE),A", segment)
        self.assertIn("LD (MISS_TRAVEL_ROWS),A", segment)

    def test_move_priority_when_standing_and_shooting(self):
        warn, _, penalties = simulate([(True, False, True)] * 60)
        self.assertEqual(warn, 1)
        self.assertEqual(penalties, [(59, "MOVE")])

    def test_no_double_penalty_when_standing_and_not_shooting(self):
        move, shoot, penalties = simulate([(True, False, False)] * 120)
        self.assertEqual((move, shoot), (1, 1))
        self.assertEqual(penalties, [(59, "MOVE"), (119, "MOVE")])

    def test_shoot_penalty_only_while_moving(self):
        move, shoot, penalties = simulate([(True, True, False)] * 60)
        self.assertEqual(move, 0)
        self.assertEqual(shoot, 1)
        self.assertEqual(penalties, [(59, "SHOOT")])

    def test_motion_without_world_step_does_not_count(self):
        self.assertEqual(simulate([(False, False, False)] * 90),
                         (0, 0, []))
        self.assertEqual(simulate([(True, False, False)] * 19),
                         (0, 0, []))
        move, shoot, penalties = simulate([(True, False, False)] * 20)
        self.assertEqual((move, shoot), (1, 1))
        self.assertEqual(penalties, [])

    def test_one_half_cell_move_resets_only_move_counter(self):
        events = [(True, False, False)] * 35
        events += [(True, True, False)]
        events += [(True, True, False)] * 24
        move, shoot, penalties = simulate(events)
        self.assertEqual(move, 0)
        self.assertEqual(shoot, 1)
        self.assertEqual(penalties, [(59, "SHOOT")])

    def test_no_world_step_on_movement_tick(self):
        # One movement and a simultaneous world step do not pre-charge MOVE.
        warn, _, _ = simulate([(True, True, True)] + [(True, False, True)] * 19)
        self.assertEqual(warn, 0)


if __name__ == "__main__":
    unittest.main()
