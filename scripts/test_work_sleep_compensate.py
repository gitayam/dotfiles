"""Tests for work_sleep_compensate.py, on a board database built here."""
import json
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import work_sleep_compensate as comp  # noqa: E402


def make_board(root: str) -> str:
    db = sqlite3.connect(os.path.join(root, "kanban.db"))
    db.executescript("""
        create table tasks (id text primary key, status text, started_at integer, worker_pid integer, current_run_id integer);
        create table task_runs (id integer primary key, task_id text, started_at integer);
    """)
    # task, status, task start, current-run id
    tasks = [("t_run", "running", 1000, 1, 1),      # running with a run row: the run row's start is the active start
             ("t_notask", "running", 1500, None, None),  # running with no run row: the task's own start is the active start
             ("t_late", "running", 5000, 2, 2),          # started inside the sleep window: left alone
             ("t_done", "done", 1000, 3, 3)]             # not running: never touched
    db.executemany("insert into tasks values (?, ?, ?, ?, ?)", tasks)
    db.executemany("insert into task_runs values (?, ?, ?)",
                   [(1, "t_run", 900), (2, "t_late", 5000), (3, "t_done", 800)])
    db.commit()
    db.close()
    return os.path.join(root, "kanban.db")


class SleepCompensation(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = make_board(self.tmp.name)
        self.state = Path(self.tmp.name) / "state.json"

    def tearDown(self):
        self.tmp.cleanup()

    def starts(self):
        db = sqlite3.connect(self.db)
        rows = {tid: (db.execute("select started_at, current_run_id from tasks where id=?", (tid,)).fetchone()[0],
                      db.execute("select started_at from task_runs where id=?", (rid,)).fetchone()[0] if rid else None)
                for tid, rid in [("t_run", 1), ("t_notask", None), ("t_late", 2), ("t_done", 3)]}
        db.close()
        return rows

    def test_the_first_tick_only_records_the_ledger(self):
        out = comp.compensate(self.db, self.state, now=2000, sleep_total=120.0, apply=True)
        self.assertEqual((out["sleep_delta"], out["compensated"], out["reset"]), (0, 0, False))
        self.assertEqual(self.starts()["t_run"], (1000, 900))

    def test_a_sleep_shifts_running_workers_started_before_the_previous_tick(self):
        comp.compensate(self.db, self.state, now=2000, sleep_total=120.0, apply=True)
        out = comp.compensate(self.db, self.state, now=3000, sleep_total=720.0, apply=True)
        self.assertEqual(out["sleep_delta"], 600)
        self.assertEqual(out["compensated"], 2)
        starts = self.starts()
        self.assertEqual(starts["t_run"], (1000, 900 + 600))       # the run row moved: it is the active start
        self.assertEqual(starts["t_notask"], (1500 + 600, None))   # no run row: the task's own start moved
        self.assertEqual(starts["t_late"], (5000, 5000))            # started inside the sleep window: untouched
        self.assertEqual(starts["t_done"], (1000, 800))             # not running: untouched

    def test_a_dry_run_reports_the_shift_but_writes_nothing(self):
        comp.compensate(self.db, self.state, now=2000, sleep_total=120.0, apply=True)
        out = comp.compensate(self.db, self.state, now=3000, sleep_total=720.0, apply=False)
        self.assertEqual((out["sleep_delta"], out["compensated"]), (600, 2))
        self.assertEqual(self.starts()["t_run"], (1000, 900))

    def test_the_state_advances_on_a_dry_run_so_a_later_apply_never_double_shifts(self):
        comp.compensate(self.db, self.state, now=2000, sleep_total=120.0, apply=True)
        comp.compensate(self.db, self.state, now=3000, sleep_total=720.0, apply=False)   # dry run consumed the sleep
        out = comp.compensate(self.db, self.state, now=3060, sleep_total=720.0, apply=True)
        self.assertEqual(out["sleep_delta"], 0)
        self.assertEqual(self.starts()["t_run"], (1000, 900))

    def test_a_reboot_resets_the_ledger_and_compensates_nothing(self):
        comp.compensate(self.db, self.state, now=2000, sleep_total=3600.0, apply=True)
        out = comp.compensate(self.db, self.state, now=2100, sleep_total=10.0, apply=True)
        self.assertTrue(out["reset"])
        self.assertEqual(out["compensated"], 0)

    def test_the_shift_is_capped_at_wall_time_plus_one_interval(self):
        comp.compensate(self.db, self.state, now=2000, sleep_total=120.0, apply=True)
        out = comp.compensate(self.db, self.state, now=2060, sleep_total=999999.0, apply=True)
        self.assertEqual(out["sleep_delta"], 60 + 60)   # 60 s wall since the last tick, plus one 60 s interval
        self.assertEqual(self.starts()["t_run"][1], 900 + 120)

    def test_a_row_whose_start_the_dispatcher_would_fall_back_to_read_is_counted_and_left(self):
        db = sqlite3.connect(self.db)
        db.execute("update task_runs set started_at = '2026-11-21 17:00:00' where id = 1")
        db.commit(); db.close()
        comp.compensate(self.db, self.state, now=2000, sleep_total=120.0, apply=True)
        out = comp.compensate(self.db, self.state, now=3000, sleep_total=720.0, apply=True)
        self.assertEqual(out["skipped_unreadable"], 1)
        self.assertEqual(out["compensated"], 1)         # only t_notask shifted


class SleptSeconds(unittest.TestCase):
    def test_it_runs_on_this_machine_and_is_not_negative(self):
        if sys.platform != "darwin":
            self.skipTest("mach_continuous_time is macOS only")
        self.assertGreaterEqual(comp.slept_seconds(), 0.0)


if __name__ == "__main__":
    unittest.main()
