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

    def test_a_hair_of_difference_between_two_clock_readings_is_no_sleep(self):
        comp.compensate(self.db, self.state, now=2000, sleep_total=100.0, apply=True)
        result = comp.compensate(self.db, self.state, now=2060, sleep_total=100.0004, apply=True)
        self.assertEqual((result["sleep_delta"], result["compensated"]), (0, 0))
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
    def test_the_sleep_log_is_read_into_windows_and_wake_requests_are_not_wakes(self):
        log = "\n".join([
            "2026-11-23 09:12:12 -0500 Sleep               \tEntering Sleep state due to 'Clamshell Sleep':TCPKeepAlive=active Using Batt (Charge:92%) 904 secs",
            "2026-11-23 09:12:14 -0500 Wake Requests       \t[process=mDNSResponder request=Maintenance deltaSecs=7198]",
            "2026-11-23 09:27:14 -0500 DarkWake            \tDarkWake from Deep Idle [CDN] : due to smc.sysState.Wake",
            "2026-11-23 09:27:59 -0500 Sleep               \tEntering Sleep state due to 'Maintenance Sleep'",
            "2026-11-23 09:28:01 -0500 Assertions          \tPID 1 Created PreventUserIdleSystemSleep",
            "2026-11-23 17:10:49 -0500 Wake                \tWake from Deep Idle [CDNVA] : due to lid",
            "2026-11-23 17:10:50 -0500 Wake                \tWake from Deep Idle again, with no sleep before it",
            "2026-11-23 18:00:00 -0500 Sleep               \tEntering Sleep state, and the log ends here",
        ])
        windows = comp.sleep_windows(log)
        self.assertEqual([woke - fell for fell, woke in windows], [902, 27770])
        self.assertEqual(comp.sleep_windows("nothing of the kind"), [])

    def test_only_an_attempt_ended_from_outside_counts_as_stopped_by_a_wake(self):
        say = lambda **said: json.dumps(said)
        self.assertTrue(comp.stopped_by_wake(say(trigger_outcome="timed_out", error="elapsed 1207s > limit 1200s")))
        self.assertTrue(comp.stopped_by_wake(say(trigger_outcome="reclaimed", error="stale_lock=host:1")))
        self.assertTrue(comp.stopped_by_wake(say(trigger_outcome="crashed", error="pid 5 exited with code 130 [owner admission settled interrupted]")))
        self.assertFalse(comp.stopped_by_wake(say(trigger_outcome="crashed", error="pid 5 exited with code 1")))
        self.assertFalse(comp.stopped_by_wake(say(trigger_outcome="timed_out", error="Iteration budget exhausted (40/40)")))
        self.assertFalse(comp.stopped_by_wake(say(error="blocked by its worker")))
        self.assertFalse(comp.stopped_by_wake("not json"))
        self.assertFalse(comp.stopped_by_wake(None))


def make_stopped_board(root: str, now: int) -> str:
    """A board with blocked cards: who stopped each, and when, is in its records."""
    path = os.path.join(root, "stopped.db")
    db = sqlite3.connect(path)
    db.executescript("""
        create table tasks (id text primary key, status text);
        create table task_events (id integer primary key, task_id text, kind text, payload text, created_at integer);
    """)
    wake = now - 600                      # the Mac woke ten minutes ago, after an hour asleep
    interrupted = json.dumps({"trigger_outcome": "crashed", "error": "pid 9 exited with code 130 [owner admission settled interrupted]"})
    timed_out = json.dumps({"trigger_outcome": "timed_out", "error": "elapsed 1207s > limit 1200s"})
    out_of_steps = json.dumps({"trigger_outcome": "timed_out", "error": "Iteration budget exhausted (40/40)"})
    cards = [
        ("t_slept", "blocked", [("gave_up", interrupted, wake + 20)]),                       # stopped by the wake
        ("t_timer", "blocked", [("gave_up", timed_out, wake + 4)]),                           # its timer billed the sleep
        ("t_steps", "blocked", [("gave_up", out_of_steps, wake + 5)]),                        # ran out of steps: not the sleep
        ("t_person", "blocked", [("gave_up", interrupted, wake + 20), ("blocked", "{}", wake + 300)]),  # a person blocked it afterwards
        ("t_awake", "blocked", [("gave_up", interrupted, wake - 2000)]),                      # stopped while the Mac was awake
        ("t_old", "blocked", [("gave_up", interrupted, now - 3 * 24 * 3600)]),                # days ago
        ("t_done", "done", [("gave_up", interrupted, wake + 20)]),                            # not blocked any more
    ]
    serial = 0
    for task_id, status, events in cards:
        db.execute("insert into tasks values (?, ?)", (task_id, status))
        for kind, payload, at in events:
            serial += 1
            db.execute("insert into task_events values (?, ?, ?, ?, ?)", (serial, task_id, kind, payload, at))
    db.commit()
    db.close()
    return path


class SleepRecovery(unittest.TestCase):
    NOW = 1_795_000_000

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = make_stopped_board(self.tmp.name, self.NOW)
        self.state = Path(self.tmp.name) / "state.json"
        self.windows = [(self.NOW - 3 * 24 * 3600 - 4000, self.NOW - 3 * 24 * 3600 - 10), (self.NOW - 4200, self.NOW - 600)]
        self.calls = []

    def tearDown(self):
        self.tmp.cleanup()

    def run_recover(self, **over):
        given = dict(now=self.NOW, windows=self.windows, lid_open=True, apply=True,
                     unblock=lambda ids, reason: self.calls.append((list(ids), reason)))
        given.update(over)
        return comp.recover(self.db, self.state, **given)

    def test_cards_a_wake_stopped_are_released_and_no_others(self):
        result = self.run_recover()
        self.assertEqual(sorted(result["released"]), ["t_slept", "t_timer"])
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(sorted(self.calls[0][0]), ["t_slept", "t_timer"])
        self.assertIn("slept", self.calls[0][1])

    def test_nothing_is_released_while_the_lid_is_closed(self):
        result = self.run_recover(lid_open=False)
        self.assertEqual(result["released"], [])
        self.assertEqual(result["held"], "the lid is closed")
        self.assertEqual(sorted(result["stopped"]), ["t_slept", "t_timer"])
        self.assertEqual(self.calls, [])

    def test_nothing_is_released_in_the_first_moments_after_a_wake(self):
        result = self.run_recover(now=self.NOW - 600 + 30)
        self.assertEqual(result["released"], [])
        self.assertEqual(result["held"], "the Mac has only just woken")
        self.assertEqual(self.calls, [])

    def test_a_dry_run_names_the_cards_and_releases_nothing(self):
        result = self.run_recover(apply=False)
        self.assertEqual(sorted(result["released"]), ["t_slept", "t_timer"])
        self.assertEqual(self.calls, [])
        self.assertEqual(sorted(self.run_recover()["released"]), ["t_slept", "t_timer"])

    def test_a_card_is_released_three_times_and_then_left_for_a_person(self):
        for _ in range(3):
            self.assertEqual(sorted(self.run_recover()["released"]), ["t_slept", "t_timer"])
        result = self.run_recover()
        self.assertEqual(result["released"], [])
        self.assertEqual(result["held"], "each was already released 3 times")
        self.assertEqual(len(self.calls), 3)

    def test_the_first_look_needs_no_sleep_log(self):
        maybe = sorted(task_id for task_id, _ in comp.stopped_cards(self.db, None, self.NOW))
        self.assertEqual(maybe, ["t_awake", "t_slept", "t_timer"])


class TheJob(unittest.TestCase):
    def test_the_job_releases_stopped_cards_only_when_asked(self):
        import setup_work_sleep_compensate as setup
        with tempfile.TemporaryDirectory() as root:
            plain = setup.compensate_plist(root, "zenithflow")["ProgramArguments"]
            self.assertEqual(plain[-3:], ["--board", "zenithflow", "--apply"])
            asked = setup.compensate_plist(root, "zenithflow", True, Path("/opt/board/hermes"))["ProgramArguments"]
            self.assertEqual(asked[-6:], ["--board", "zenithflow", "--apply", "--recover", "--hermes", "/opt/board/hermes"])


class OnThisMachine(unittest.TestCase):
    def test_it_runs_on_this_machine_and_is_not_negative(self):
        if sys.platform != "darwin":
            self.skipTest("mach_continuous_time is macOS only")
        self.assertGreaterEqual(comp.slept_seconds(), 0.0)


if __name__ == "__main__":
    unittest.main()
