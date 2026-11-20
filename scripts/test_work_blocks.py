"""Tests for report_work_blocks.py, on a database built here with invented data."""
import contextlib
import io
import json
import os
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import report_work_blocks as blocks  # noqa: E402

NOW = 100_000.0


def make_home(root: str) -> str:
    home = os.path.join(root, "hermes")
    os.makedirs(os.path.join(home, "kanban", "boards", "work"))
    db = sqlite3.connect(os.path.join(home, "kanban", "boards", "work", "kanban.db"))
    db.executescript("""
        create table tasks (id text primary key, title text, body text, status text, assignee text, created_by text, created_at integer);
        create table task_runs (id integer primary key, task_id text, profile text, started_at integer, ended_at integer);
        create table task_links (parent_id text, child_id text);
        create table task_events (id integer primary key, task_id text, kind text, payload text, created_at integer);
        create table task_comments (id integer primary key, task_id text, author text, body text, created_at integer);
    """)
    tasks = [  # id, status, assignee, author, created
        ("t_decide01", "blocked", None, "default", 10_000),         # waits for a person, answered by a person afterwards
        ("t_decide02", "blocked", "builder", "default", 10_000),    # waits for a person, only a worker commented
        ("t_steps001", "blocked", "checker", "auto-decomposer", 20_000),   # ran out of steps
        ("t_crash001", "blocked", "builder", "operator", 20_000),   # failed another way
        ("t_behind01", "todo", "checker", "auto-decomposer", 20_000),      # behind t_steps001
        ("t_root0001", "todo", "planner", "default", 5_000),        # behind t_steps001 directly and through t_behind01
        ("t_free0001", "todo", "builder", "operator", 30_000),      # todo with no open parent
        ("t_ready001", "ready", "builder", "operator", 30_000),
        ("t_done0001", "done", "builder", "operator", 1_000),
        ("t_wait0001", "done", "builder", "operator", 50_000),      # for the waiting split
    ]
    db.executemany("insert into tasks values (?, 'a title that must never be printed', 'a body that must never be printed', ?, ?, ?, ?)", tasks)
    events = [
        ("t_decide01", "blocked", {"kind": "needs_input", "reason": "a reason that must never be printed"}, 40_000),
        ("t_decide02", "blocked", {"kind": "needs_input"}, 40_000),
        ("t_steps001", "timed_out", {"error": "Iteration budget exhausted (16/16) — task could not complete"}, 60_000),
        ("t_steps001", "gave_up", {"error": "Iteration budget exhausted (16/16) — task could not complete", "failures": 2}, 61_000),
        ("t_steps001", "blocked", {}, 61_000),
        ("t_crash001", "crashed", {"error": "pid 1 exited with code 2"}, 62_000),
        ("t_crash001", "blocked", {}, 62_000),
        ("t_wait0001", "created", {"status": "ready"}, 50_000),
    ]
    db.executemany("insert into task_events (task_id, kind, payload, created_at) values (?, ?, ?, ?)", [(t, k, json.dumps(p), at) for t, k, p, at in events])
    db.executemany("insert into task_comments (task_id, author, body, created_at) values (?, ?, 'a comment that must never be printed', ?)", [
        ("t_decide01", "default", 39_000),   # before the block: does not count
        ("t_decide01", "desktop", 41_000),   # a person, after the block
        ("t_decide02", "builder", 41_000),   # a worker profile, after the block
        ("t_decide02", "auto-decomposer", 42_000),
    ])
    db.executemany("insert into task_links values (?, ?)", [("t_steps001", "t_behind01"), ("t_steps001", "t_root0001"), ("t_behind01", "t_root0001"), ("t_done0001", "t_free0001")])
    runs = [  # the waiting card became ready at 50,000 and started at 50,600
        ("t_done0001", "builder", 49_900, 50_100),   # same profile: 100 s of one-per-role
        ("t_decide02", "checker", 50_100, 50_400),   # with the next one: 200 s of the total limit (50,200 to 50,400)
        ("t_steps001", "planner", 50_200, 50_400),
        ("t_wait0001", "builder", 50_600, 50_700),   # 50,400 to 50,600: nothing running; 50,100 to 50,200: one other run only
        ("t_crash001", "builder", 62_000, 62_000),   # no duration: not a run to measure against
    ]
    db.executemany("insert into task_runs (task_id, profile, started_at, ended_at) values (?, ?, ?, ?)", runs)
    db.commit()
    db.close()
    return home


class OpenCards(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = make_home(self.tmp.name)
        db = blocks.open_ro(os.path.join(self.home, "kanban", "boards", "work", "kanban.db"))
        self.summary = blocks.summarise(blocks.load(db), NOW)
        db.close()
        self.cards = {card["id"]: card for card in self.summary["cards"]}

    def tearDown(self):
        self.tmp.cleanup()

    def test_every_open_card_gets_one_class_and_closed_cards_are_left_out(self):
        self.assertEqual({k: v["class"] for k, v in self.cards.items()}, {
            "t_decide01": "waits_for_a_person", "t_decide02": "waits_for_a_person", "t_steps001": "out_of_steps",
            "t_crash001": "failed", "t_behind01": "behind", "t_root0001": "behind", "t_free0001": "todo", "t_ready001": "ready"})
        self.assertEqual(self.summary["open_cards"], 8)
        self.assertEqual(self.summary["by_class"], {"waits_for_a_person": 2, "out_of_steps": 1, "failed": 1, "behind": 2, "todo": 1, "ready": 1})

    def test_only_a_person_s_comment_after_the_block_counts_as_an_answer(self):
        self.assertEqual(self.cards["t_decide01"]["answered"], 1)
        self.assertEqual(self.cards["t_decide02"]["answered"], 0)       # a worker profile and the decomposer are not people
        self.assertEqual(self.summary["answered_but_still_blocked"], ["t_decide01"])
        self.assertIn("1 blocked cards have a person's comment", self.summary["look_at"][0])

    def test_root_blockers_are_the_head_of_the_chain_even_when_reached_two_ways(self):
        self.assertEqual(self.cards["t_behind01"]["behind"], ["t_steps001"])
        self.assertEqual(self.cards["t_root0001"]["behind"], ["t_steps001"])    # not t_behind01, which waits behind the same root
        self.assertEqual(self.summary["root_blockers"], ["t_steps001"])
        self.assertNotIn("behind", self.cards["t_free0001"])                    # its only parent is done

    def test_out_of_steps_names_who_wrote_the_card_and_hours_run_from_the_block(self):
        self.assertEqual(self.summary["out_of_steps_by_card_author"], {"auto-decomposer": 1})
        self.assertEqual(self.cards["t_steps001"]["hours"], round((NOW - 61_000) / 3600, 1))
        self.assertEqual(self.cards["t_ready001"]["hours"], round((NOW - 30_000) / 3600, 1))   # no block: from creation

    def test_waiting_is_split_by_what_else_was_running(self):
        waiting = self.summary["waiting"]
        self.assertEqual(waiting["runs_measured"], 1)                    # the other runs have no ready event before their start
        self.assertEqual(waiting["seconds"], {"one_per_role": 100, "total_limit": 200, "nothing_running": 300})
        self.assertEqual(waiting["median_seconds"], 600)

    def test_a_cycle_in_the_links_does_not_hang(self):
        db = sqlite3.connect(os.path.join(self.home, "kanban", "boards", "work", "kanban.db"))
        db.execute("insert into task_links values ('t_root0001', 't_behind01')")
        db.commit(); db.close()
        ro = blocks.open_ro(os.path.join(self.home, "kanban", "boards", "work", "kanban.db"))
        summary = blocks.summarise(blocks.load(ro), NOW); ro.close()
        self.assertEqual({c["id"]: c.get("behind") for c in summary["cards"] if c["class"] == "behind"}["t_root0001"], ["t_steps001"])

    def run_tool(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = blocks.main(["--hermes-home", self.home, *args], now=NOW)
        return code, out.getvalue()

    def test_prints_no_title_body_comment_or_reason_unless_titles_are_asked_for(self):
        for args in ([], ["--json"]):
            code, text = self.run_tool(*args)
            self.assertEqual(code, 0)
            for private in ("must never be printed",):
                self.assertNotIn(private, text)
        code, text = self.run_tool("--titles")
        self.assertIn("a title that must never be printed", text)
        self.assertNotIn("a body that must never be printed", text)
        self.assertNotIn("a comment that must never be printed", text)
        self.assertNotIn("a reason that must never be printed", text)
        self.assertIn("Board work: 8 open cards", text)
        self.assertIn("one per role 17%, total limit 33%, nothing running 50%", text)

    def test_a_missing_board_is_reported_and_fails(self):
        code, text = self.run_tool("--board", "nowhere")
        self.assertEqual(code, 1)
        self.assertIn("no database found", text)


if __name__ == "__main__":
    unittest.main()
