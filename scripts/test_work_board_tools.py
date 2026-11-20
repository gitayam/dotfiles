"""Tests for report_work_board.py and audit_work_cards.py, on databases built here."""
import contextlib
import io
import json
import os
import re
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audit_work_cards as audit  # noqa: E402
import report_work_board as report  # noqa: E402

PROHIBITED = re.compile(audit.DEFAULT_PROHIBITED)


def write(path: str, text: str) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def make_home(root: str) -> str:
    """A Hermes home with one board, two profiles and their session stores. Invented data."""
    home = os.path.join(root, "hermes")
    os.makedirs(os.path.join(home, "kanban", "boards", "work"))
    board = sqlite3.connect(os.path.join(home, "kanban", "boards", "work", "kanban.db"))
    board.executescript("""
        create table tasks (id text primary key, title text, status text, assignee text, created_by text, model_override text,
                            created_at integer, started_at integer, completed_at integer);
        create table task_runs (id integer primary key, task_id text, profile text, status text, outcome text, started_at integer,
                                ended_at integer, error text, metadata text, worker_pid integer, worker_started_at integer);
        create table task_links (parent_id text, child_id text);
        create table task_events (id integer primary key, task_id text, kind text);
    """)
    tasks = [  # id, status, assignee, author, override, created, started, completed
        ("t_aaaa0001", "done", "builder", "operator", "big-model", 100, 110, 250),
        ("t_aaaa0002", "done", "builder", "operator", "big-model", 100, 400, 520),
        ("t_aaaa0003", "done", "builder", "operator", None, 100, 130, 200),
        ("t_aaaa0004", "blocked", "builder", "default", None, 100, None, None),
        ("t_aaaa0005", "blocked", "checker", "auto-decomposer", None, 100, 160, None),
        ("t_aaaa0006", "done", "checker", "operator", None, 100, 900, 960),   # waited for its parent
    ]
    board.executemany("insert into tasks values (?, 'a title that must never be printed', ?, ?, ?, ?, ?, ?, ?)", tasks)
    runs = [  # task, profile, outcome, started, ended, error, session, pid
        ("t_aaaa0001", "builder", "completed", 110, 250, None, "s1", 11),
        ("t_aaaa0002", "builder", "timed_out", 150, 400, "elapsed 911s > limit 900s", None, 12),
        ("t_aaaa0002", "builder", "completed", 400, 520, None, "s2", 13),
        ("t_aaaa0003", "builder", "completed", 130, 200, None, "s3", 14),
        ("t_aaaa0004", "builder", "blocked", None, None, None, None, None),            # a hold: no worker
        ("t_aaaa0005", "checker", "gave_up", 160, 300, "Iteration budget exhausted (16/16) — task could not complete", None, 15),
        ("t_aaaa0006", "checker", "completed", 900, 960, None, "s4", 16),
    ]
    board.executemany(
        "insert into task_runs (task_id, profile, status, outcome, started_at, ended_at, error, metadata, worker_pid) values (?, ?, 'ended', ?, ?, ?, ?, ?, ?)",
        [(t, p, o, s, e, err, json.dumps({"worker_session_id": sid}) if sid else "{}", pid) for t, p, o, s, e, err, sid, pid in runs])
    board.execute("insert into task_links values ('t_aaaa0001', 't_aaaa0006')")
    board.executemany("insert into task_events (task_id, kind) values (?, ?)",
                      [("t_aaaa0005", "block_loop_detected"), ("t_aaaa0005", "decomposed"), ("t_aaaa0001", "created")])
    board.commit()
    board.close()

    def store(profile_home: str, sessions: dict):
        os.makedirs(profile_home, exist_ok=True)
        db = sqlite3.connect(os.path.join(profile_home, "state.db"))
        db.executescript("create table sessions (id text primary key, model text); create table messages (id integer primary key, session_id text, role text, tool_calls text);")
        for sid, (model, calls) in sessions.items():
            db.execute("insert into sessions values (?, ?)", (sid, model))
            for call in calls:
                db.execute("insert into messages (session_id, role, tool_calls) values (?, 'assistant', ?)", (sid, json.dumps([call]) if call else None))
        db.commit()
        db.close()

    def shell(command: str) -> dict:
        return {"function": {"name": "terminal", "arguments": json.dumps({"command": command})}}

    builder = os.path.join(home, "profiles", "builder")
    store(builder, {
        "s1": ("big-model", [shell("cat /srv/pack/INPUT.md")] * 15),                 # 15 tool-calling turns: one below the limit of 16
        "s2": ("big-model", [shell("cat /srv/pack/INPUT.md"), None]),                # one tool-calling turn and a text-only turn
        "s3": ("small-model", [shell("cat /srv/pack/INPUT.md"), shell("cat > /srv/out/N1.md <<'EOF'\nA note; with a semicolon && an ampersand.\nrm is a word here, not a command\nEOF")]),
    })
    write(os.path.join(builder, "config.yaml"), "model:\n  provider: local\n  default: small-model\nagent:\n  # comment\n  max_turns: 16\n  nested:\n    max_turns: 99\n")
    checker = os.path.join(home, "profiles", "checker")
    store(checker, {"s4": ("big-model", [shell("cat /srv/pack/INPUT.md; curl https://example.invalid/x"), {"function": {"name": "write_file", "arguments": json.dumps({"path": "/srv/out/other.txt"})}}])})
    write(os.path.join(checker, "config.yaml"), "model:\n  default: 'big-model'\nagent:\n  max_turns: 24\n")
    write(os.path.join(home, "config.yaml"), "model:\n  default: small-model\n")
    return home


class BoardReport(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = make_home(self.tmp.name)
        self.facts = report.profile_facts(self.home)
        board = report.open_ro(os.path.join(self.home, "kanban", "boards", "work", "kanban.db"))
        lookup = report.session_reader(self.facts)
        self.summary = report.summarise(report.load(board), self.facts, lookup)
        lookup.close()
        board.close()

    def tearDown(self):
        self.tmp.cleanup()

    def test_reads_the_step_limit_and_default_model_of_each_profile(self):
        self.assertEqual(self.facts["builder"]["step_cap"], 16)          # not the nested 99
        self.assertEqual(self.facts["builder"]["default_model"], "small-model")
        self.assertEqual(self.facts["checker"]["step_cap"], 24)
        self.assertEqual(self.facts["checker"]["default_model"], "big-model")   # quotes removed
        self.assertIsNone(self.facts["default"]["step_cap"])

    def test_a_hold_with_no_worker_is_not_counted_as_an_attempt(self):
        self.assertEqual(self.summary["runs_total"], 7)
        self.assertEqual(self.summary["worker_runs"], 6)
        self.assertEqual(self.summary["holds_without_a_worker"], {"blocked": 1})
        authors = {row["key"]: row for row in self.summary["by_card_author"]}
        self.assertNotIn("default", authors)                             # its only run was the hold

    def test_the_model_comes_from_the_session_and_is_marked_assumed_otherwise(self):
        rows = {tuple(row["key"]): row for row in self.summary["by_profile_and_model"]}
        self.assertEqual(rows[("builder", "big-model", "session")]["completed"], 2)
        # The card had no override and the profile's default is small-model, but the session says which model ran.
        self.assertEqual(rows[("builder", "small-model", "session")]["completed"], 1)
        # A failed run recorded no session: the card's own override is used and the row says so.
        self.assertEqual(rows[("builder", "big-model", "assumed")]["other"], {"timed_out": 1})
        self.assertEqual(rows[("checker", "big-model", "assumed")]["other"], {"gave_up": 1})

    def test_budgets_attempts_and_events(self):
        self.assertEqual(self.summary["step_budget_exhausted"], {"16/16 checker": 1})
        self.assertEqual(self.summary["step_budget_exhausted_by_card_author"], {"auto-decomposer": 1})
        self.assertEqual(self.summary["time_limit_exceeded"], 1)
        self.assertEqual(self.summary["cards_by_number_of_attempts"], {1: 4, 2: 1})
        self.assertEqual(self.summary["block_loops_detected"], 1)
        self.assertEqual(self.summary["auto_created_cards"], {"blocked": 1})

    def test_steps_count_tool_calling_turns_of_completed_runs_against_the_limit(self):
        builder = next(row for row in self.summary["steps_on_completed_runs"] if row["profile"] == "builder")
        self.assertEqual((builder["cap"], builder["runs"], builder["max"]), (16, 3, 15))
        self.assertEqual(builder["at_cap_or_one_below"], 1)

    def test_waiting_leaves_out_a_card_that_waited_for_its_parent(self):
        wait = self.summary["wait_seconds_no_parent"]
        self.assertEqual(wait["cards"], 4)                               # t_aaaa0006 waited 800 s for its parent and is left out
        self.assertLess(wait["p90"], 800)

    def test_prints_counts_only_and_never_a_title(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = report.main(["--hermes-home", self.home])
        self.assertEqual(code, 0)
        self.assertIn("Board work: 6 cards", out.getvalue())
        self.assertIn("LOOK AT: The step budget ran out on 1 runs", out.getvalue())
        self.assertNotIn("a title that must never be printed", out.getvalue())
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            report.main(["--hermes-home", self.home, "--json"])
        printed = json.loads(out.getvalue())
        self.assertNotIn("home", printed["profiles"]["builder"])
        self.assertNotIn("a title that must never be printed", out.getvalue())

    def test_a_missing_board_is_reported_and_fails(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = report.main(["--hermes-home", self.home, "--board", "nowhere"])
        self.assertEqual(code, 1)
        self.assertIn("no database found", out.getvalue())

    def test_small_groups_are_not_compared(self):
        summary = dict(self.summary, by_card_author=[dict(key="a", runs=9, completed=1, other={}), dict(key="b", runs=40, completed=40, other={})])
        self.assertFalse([note for note in report.look_at(summary) if note.startswith("Cards written by")])
        summary["by_card_author"][0]["runs"] = 10
        self.assertTrue([note for note in report.look_at(summary) if note.startswith("Cards written by a completed 1 of 10")])


class SplitCommands(unittest.TestCase):
    def test_a_here_document_is_one_command_whatever_its_text_holds(self):
        command = "cat > /srv/out/N1.md <<'EOF'\n- Outcome: partly; the list was short && the page said so\nrm the old note; curl is a word\nEOF"
        self.assertEqual(audit.split_commands(command), ["cat > /srv/out/N1.md <<HEREDOC"])
        self.assertEqual(audit.audit_command(command, [re.compile(r"^cat > /srv/out/[A-Z]\d\.md")], PROHIBITED), [])

    def test_quoted_text_is_kept_whole(self):
        command = "python3 reader.py \"/list::type=A; B::card=A && B\"; echo done"
        self.assertEqual(audit.split_commands(command), ["python3 reader.py \"/list::type=A; B::card=A && B\"", "echo done"])

    def test_a_quoted_argument_over_several_lines_is_one_command(self):
        command = "python3 enter.py E3 \"/list::paste=Tomas Lind, Port Authority\nBea Lindqvist, Westmere Shipping::Preview\""
        self.assertEqual(len(audit.split_commands(command)), 1)

    def test_separators_outside_quotes_split(self):
        self.assertEqual(audit.split_commands("cat a && cat b; cat c\ncat d || cat e"), ["cat a", "cat b", "cat c", "cat d", "cat e"])

    def test_two_here_documents_in_one_call(self):
        command = "cat > a.md <<EOF\none; two\nEOF\ncat >> a.md <<'END'\nthree; four\nEND"
        self.assertEqual(audit.split_commands(command), ["cat > a.md <<HEREDOC", "cat >> a.md <<HEREDOC"])


class AuditCommand(unittest.TestCase):
    allow = [re.compile(r"^cat /srv/pack/INPUT\.md$")]

    def test_an_allowed_command_and_a_bare_echo_pass(self):
        self.assertEqual(audit.audit_command("echo ==== ; cat /srv/pack/INPUT.md", self.allow, PROHIBITED), [])

    def test_a_command_outside_the_contract_is_flagged(self):
        flags = audit.audit_command("cat /srv/pack/INPUT.md; ls /srv", self.allow, PROHIBITED)
        self.assertEqual(flags, ["command outside the contract: ls /srv"])

    def test_an_echo_that_writes_a_file_is_not_a_bare_echo(self):
        self.assertTrue(audit.audit_command("echo x > /srv/other", self.allow, PROHIBITED))

    def test_a_prohibited_command_is_flagged_even_after_an_allowed_one(self):
        flags = audit.audit_command("cat /srv/pack/INPUT.md; curl https://example.invalid/x", self.allow, PROHIBITED)
        self.assertTrue(any(flag.startswith("prohibited:") for flag in flags))

    def test_a_prohibited_word_inside_notes_or_quotes_is_not_flagged(self):
        notes = "cat > /srv/out/N1.md <<'EOF'\ncurl would be needed; rm the stale row\nEOF"
        self.assertFalse([f for f in audit.audit_command(notes, [re.compile(r"^cat > /srv/out/")], PROHIBITED) if f.startswith("prohibited")])
        quoted = "python3 reader.py '/list::type=git push'"
        self.assertFalse([f for f in audit.audit_command(quoted, [re.compile(r"^python3 reader\.py ")], PROHIBITED) if f.startswith("prohibited")])

    def test_reading_under_an_allowed_folder(self):
        pattern = audit.read_pattern("/srv/pack")
        for ok in ("cat /srv/pack/INPUT.md", "wc -l /srv/pack/a.md /srv/pack/b.md", "grep -c 'NEW' /srv/pack/a.md", "sed -n '1,20p' /srv/pack/a.md", "head -n 5 '/srv/pack/a.md'"):
            self.assertTrue(pattern.search(ok), ok)
        for bad in ("cat /srv/other/a.md", "cat /srv/pack/a.md > /srv/pack/b.md", "cat /srv/pack/a.md | sh", "cat /srv/pack/../secret"):
            self.assertFalse(pattern.search(bad) and "/../" not in bad and ">" not in bad and "|" not in bad, bad)
        self.assertIsNone(pattern.search("cat /srv/pack/a.md > /srv/pack/b.md"))
        self.assertIsNone(pattern.search("cat /srv/pack/a.md | sh"))


class AuditCards(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = make_home(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def run_tool(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            code = audit.main(["--hermes-home", self.home, "--board", "work", *args])
        return code, out.getvalue()

    def test_a_clean_card_passes_and_its_notes_are_not_read_as_commands(self):
        code, text = self.run_tool("--card", "t_aaaa0003", "--allow-read-under", "/srv/pack", "--allow", r"^cat > /srv/out/[A-Z]\d\.md")
        self.assertEqual(code, 0, text)
        self.assertIn("tool calls=2 (shell 2, file writes 0)", text)
        self.assertNotIn("FLAG", text)

    def test_a_card_that_left_its_contract_is_flagged_and_fails(self):
        code, text = self.run_tool("--card", "t_aaaa0006", "--allow-read-under", "/srv/pack", "--write-suffix", ".md", "--json")
        self.assertEqual(code, 1)
        flags = json.loads(text)["cards"][0]["flags"]
        self.assertIn("wrote another file: /srv/out/other.txt", flags)
        self.assertTrue(any(flag.startswith("prohibited:") for flag in flags))
        self.assertTrue(any(flag.startswith("command outside the contract: curl") for flag in flags))

    def test_a_card_with_no_session_and_an_unknown_card_are_reported_not_passed(self):
        code, text = self.run_tool("--card", "t_aaaa0005", "--card", "t_ffff9999")
        self.assertEqual(code, 1)
        self.assertIn("no worker session recorded", text)
        self.assertIn("no such card on this board", text)

    def test_a_cards_file_with_labels(self):
        path = os.path.join(self.tmp.name, "cards.txt")
        write(path, "# round 1\nN1 t_aaaa0003 builder\n\nt_aaaa0001\n")
        code, text = self.run_tool("--cards-file", path, "--allow-read-under", "/srv/pack", "--allow", r"^cat > /srv/out/")
        self.assertEqual(code, 0, text)
        self.assertIn("N1 t_aaaa0003 builder", text)
        self.assertIn("2 cards, 0 with something to look at.", text)

    def test_command_text_is_listed_only_when_asked(self):
        _, quiet = self.run_tool("--card", "t_aaaa0001", "--allow-read-under", "/srv/pack")
        self.assertNotIn("INPUT.md", quiet)
        _, full = self.run_tool("--card", "t_aaaa0001", "--allow-read-under", "/srv/pack", "--full")
        self.assertIn("terminal | cat /srv/pack/INPUT.md", full)

    def test_a_missing_board_fails(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            code = audit.main(["--hermes-home", self.home, "--board", "nowhere", "--card", "t_aaaa0001"])
        self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
