"""Structural regression checks for asteroid reset after ship death.

These tests validate the control-flow and spawn-table invariants directly
against the ASM sources. They do not replace a ZX Spectrum runtime test.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source(name):
    return (ROOT / name).read_text(encoding="utf-8")


def routine(text, label, next_global=None):
    start = re.search(r"^" + re.escape(label) + r":\s*$", text, re.M)
    if not start:
        raise AssertionError(f"Missing label: {label}")
    if next_global:
        end = re.search(r"^" + re.escape(next_global) + r":\s*$", text[start.end():], re.M)
        if not end:
            raise AssertionError(f"Missing end label: {next_global}")
        return text[start.start():start.end() + end.start()]
    return text[start.start():]


class RespawnInvariants(unittest.TestCase):
    def test_respawn_precedes_render(self):
        main = source("main.asm")
        loop = routine(main, "MAIN_LOOP")
        self.assertRegex(loop, r"CP STATE_RESPAWN\s+JP Z,RESTART_ROUND")
        self.assertLess(loop.index("JP Z,RESTART_ROUND"), loop.index("CALL RENDER_FRAME"))
        self.assertLess(loop.index("CALL RENDER_FRAME"), loop.index("CALL UPDATE_GAME"))

    def test_ship_explosion_stops_asteroid_updates(self):
        main = source("main.asm")
        loop = routine(main, "MAIN_LOOP")
        after_explosion = loop.split(".EXPLODING:", 1)[1].split(".FRAME_SOUND:", 1)[0]
        self.assertIn("CALL UPDATE_BLAST_ANIM", after_explosion)
        self.assertNotIn("UPDATE_GAME", after_explosion)
        self.assertNotIn("UPDATE_ENEMIES", after_explosion)
        logic = source("logic.asm")
        self.assertIn("LD A,STATE_EXPLODING\n    LD (GAME_STATE),A", logic)
        self.assertRegex(
            logic,
            r"LD A,\(SHIP_LIVES\)\s+OR A\s+LD A,STATE_RESPAWN"
            r"\s+JR NZ,\.NEXT_MODE\s+LD A,STATE_GAME_OVER",
        )
        self.assertIsNotNone(re.search(
            r"UPDATE_ENEMY_SLOT:.*?LD A,\\(GAME_STATE\\)\\s+CP STATE_PLAYING\\s+RET NZ",
            source("enemies.asm"), re.S,
        ))

    def test_full_screen_clear_before_slot_reset(self):
        main = source("main.asm")
        restart = routine(main, "RESTART_ROUND", "MAIN_LOOP")
        self.assertLess(restart.index("CALL DRAW_STATIC_UI"),
                        restart.index("CALL RESET_ROUND_OBJECTS"))
        self.assertLess(restart.index("CALL RESET_ROUND_OBJECTS"),
                        restart.index("LD A,STATE_PLAYING"))
        self.assertIn("CALL LOAD_SPACE_CAN_SCREEN", routine(source("ui.asm"), "DRAW_STATIC_UI"))
        load = routine(source("ui.asm"), "LOAD_SPACE_CAN_SCREEN", "RENDER_HUD")
        self.assertIn("LD DE,#4000", load)
        self.assertIn("CP #5B", load)
        reset = routine(source("menu.asm"), "RESET_ROUND_OBJECTS")
        self.assertIn("CALL INIT_ENEMIES", reset)

    def test_all_astroid_slots_are_reset(self):
        enemies = routine(source("enemies.asm"), "INIT_ENEMIES", "UPDATE_ENEMIES")
        self.assertIn("LD HL,ENEMY_POOL", enemies)
        self.assertIn("LD (HL),0", enemies)
        self.assertIn("LD DE,ENEMY_POOL+1", enemies)
        self.assertIn("LD BC,MAX_ENEMIES*ENEMY_SLOT_SIZE-1", enemies)
        self.assertIn("LDIR", enemies)
        self.assertIn("LD HL,ENEMY_START_TABLE", enemies)
        self.assertIn("LD (IX+E_RESPAWN),A", enemies)
        self.assertIn("JR NZ,.SKIP_ACTIVE", enemies)
        self.assertIn("LD (IX+E_ACTIVE),A", enemies)
        self.assertIn("DJNZ .NEXT", enemies)

    def test_all_spawn_at_top_with_staggered_delays(self):
        data = source("data.asm")
        table = routine(data, "ENEMY_START_TABLE", "ENEMY_MOVE_TIMER")
        rows = re.findall(
            r"^\s*DB\s+([01]),PLAYFIELD_TOP,(\d+),(\d+)",
            table, re.M,
        )
        self.assertEqual([(int(t), int(p), int(d)) for t, p, d in rows],
                         [(0, 1, 0), (1, 3, 20), (0, 5, 40), (1, 7, 60)])
        self.assertIn("PLAYFIELD_TOP        EQU 4", source("main.asm"))
        update = routine(source("enemies.asm"), "UPDATE_ENEMY_SLOT",
                         "SELECT_ENEMY_SPAWN_X")
        self.assertIsNotNone(re.search(
            r"\\.INACTIVE:.*?LD A,\\(IX\\+E_RESPAWN\\)"
            r".*?DEC A.*?LD \\(IX\\+E_RESPAWN\\),A\\s+RET NZ"
            r".*?\\.RESPAWN:.*?LD A,PLAYFIELD_TOP\\s+LD \\(IX\\+E_Y\\),A",
            update, re.S,
        ))
        self.assertIn("CALL ENEMY_SPAWN_GAP_CLEAR", update)

    def test_initial_wave_spacing_at_both_demo_speeds(self):
        # Simple timing model of the ASM spawn table (not a CPU emulator).
        # Moves occur every 5-SCROLL_SPEED frames. Incoming slots are
        # postponed until 3 full rows separate asteroid footprints.
        table = [(0, 0), (1, 20), (0, 40), (1, 60)]
        for speed in (1, 2):
            with self.subTest(scroll_speed=speed):
                slots = [dict(height=1+t, delay=delay, y=4, active=(i == 0))
                         for i, (t, delay) in enumerate(table)]
                slots[0]["spawn_frame"] = 0
                for frame in range(1, 61):
                    move_now = frame % (5-speed) == 0
                    for i, obj in enumerate(slots):
                        if obj["active"]:
                            if move_now:
                                if obj["y"] + obj["height"] - 1 >= 23:
                                    obj["active"] = False
                                    obj["delay"] = 24
                                else:
                                    obj["y"] += 1
                        else:
                            if obj["delay"] > 0:
                                obj["delay"] -= 1
                            if obj["delay"] == 0:
                                clear = all(
                                    not other["active"]
                                    or (4 + obj["height"] + 3 <= other["y"])
                                    or (other["y"] + other["height"] + 3 <= 4)
                                    for j, other in enumerate(slots) if j != i
                                )
                                if clear:
                                    obj["active"] = True
                                    obj["y"] = 4
                                    obj["spawn_frame"] = frame
                    active = sorted((o for o in slots if o["active"]),
                                    key=lambda o: o["y"])
                    for low, high in zip(active, active[1:]):
                        self.assertGreaterEqual(
                            high["y"] - (low["y"] + low["height"]), 3,
                            f"speed={speed} frame={frame}",
                        )
                self.assertEqual(slots[0]["spawn_frame"], 0)
                self.assertGreaterEqual(slots[1]["spawn_frame"], 20)
                self.assertGreaterEqual(slots[2]["spawn_frame"], 40)


if __name__ == "__main__":
    unittest.main()
