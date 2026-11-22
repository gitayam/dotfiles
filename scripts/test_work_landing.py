"""Tests for report_work_landing.py, on repositories and a board built here with invented data."""
import contextlib
import io
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import report_work_landing as landing  # noqa: E402

NOW = 2_000_000_000.0
HOUR, DAY = 3600, 86400
QUIET = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull}


def g(cwd: str, *args: str) -> str:
    """One git command with no user configuration, no signing and a fixed author."""
    done = subprocess.run(["git", "-c", "user.name=Tester", "-c", "user.email=tester@example.invalid", "-c", "commit.gpgsign=false", *args],
                          cwd=cwd, check=True, capture_output=True, text=True, env=QUIET)
    return done.stdout.strip()


def put(folder: str, name: str, text: str) -> None:
    with open(os.path.join(folder, name), "w", encoding="utf-8") as handle:
        handle.write(text)


def commit(folder: str, name: str, text: str, subject: str) -> None:
    put(folder, name, text)
    g(folder, "add", name)
    g(folder, "commit", "-q", "-m", subject)


def make_repositories(root: str) -> dict[str, str]:
    """A repository with a remote and one worktree per way work can end, and one repository with no remote."""
    g(root, "init", "-q", "--bare", "-b", "main", "origin.git")
    g(root, "init", "-q", "-b", "main", "repo")
    repo = os.path.join(root, "repo")
    g(repo, "remote", "add", "origin", os.path.join(root, "origin.git"))
    commit(repo, "c.txt", "one\ntwo\nthree\n", "start")
    g(repo, "push", "-q", "-u", "origin", "main")
    trees = {}
    for name in ("merged", "squashed", "resquashed", "picked", "local", "pushed", "dirty", "clean"):
        trees[name] = os.path.join(root, "wt-" + name)
        g(repo, "worktree", "add", "-q", "-b", name, trees[name], "main")
    commit(trees["merged"], "m.txt", "merged\n", "a change merged as it is")
    commit(trees["squashed"], "s.txt", "one\n", "first half")
    commit(trees["squashed"], "s.txt", "one\ntwo\n", "second half")
    commit(trees["resquashed"], "u.txt", "one\n", "first half")
    commit(trees["resquashed"], "u.txt", "one\ntwo\n", "second half")
    commit(trees["picked"], "c.txt", "one\nTWO\nthree\n", "a change picked across")
    commit(trees["local"], "l.txt", "local\n", "a change nobody pushed")
    commit(trees["pushed"], "p.txt", "pushed\n", "a change pushed and not merged")
    g(trees["pushed"], "push", "-q", "origin", "pushed")
    put(trees["dirty"], "d.txt", "never committed\n")
    os.mkdir(os.path.join(trees["local"], "sub"))
    g(repo, "merge", "-q", "--ff-only", "merged")
    for name in ("squashed", "resquashed"):
        g(repo, "merge", "-q", "--squash", name)
        g(repo, "commit", "-q", "-m", f"{name}, as one commit")
    commit(repo, "u.txt", "one\ntwo\nthree\n", "the same file changed again afterwards")
    g(repo, "cherry-pick", "picked")
    commit(repo, "c.txt", "one\nTWO\nthree and more\n", "the same file changed again afterwards")
    g(repo, "push", "-q", "origin", "main")
    g(root, "init", "-q", "-b", "main", "solo")
    solo = os.path.join(root, "solo")
    commit(solo, "a.txt", "one\n", "start")
    trees["solo"] = os.path.join(root, "wt-solo")
    g(solo, "worktree", "add", "-q", "-b", "kept", trees["solo"], "main")
    commit(trees["solo"], "k.txt", "kept\n", "a change in a repository with no remote")
    trees["plain"] = os.path.join(root, "plain")
    os.mkdir(trees["plain"])
    trees["gone"] = os.path.join(root, "removed")
    return trees


def make_home(root: str, trees: dict[str, str]) -> str:
    home = os.path.join(root, "hermes")
    os.makedirs(os.path.join(home, "kanban", "boards", "work"))
    db = sqlite3.connect(os.path.join(home, "kanban", "boards", "work", "kanban.db"))
    db.execute("create table tasks (id text primary key, title text, status text, workspace_path text, created_at integer, started_at integer, completed_at integer)")
    cards = [  # id, status, workspace, finished
        ("t_merged01", "done", trees["merged"], NOW - 3 * DAY),
        ("t_squash01", "done", trees["squashed"], NOW - 3 * DAY),
        ("t_resqsh01", "done", trees["resquashed"], NOW - 3 * DAY),
        ("t_picked01", "done", trees["picked"], NOW - 3 * DAY),
        ("t_local001", "done", trees["local"], NOW - 4 * DAY),
        ("t_local002", "archived", os.path.join(trees["local"], "sub"), NOW - 5 * DAY),   # a folder inside the same checkout
        ("t_pushed01", "done", trees["pushed"], NOW - 2 * HOUR),
        ("t_dirty001", "done", trees["dirty"], NOW - HOUR),
        ("t_clean001", "done", trees["clean"], NOW - 3 * DAY),
        ("t_solo0001", "done", trees["solo"], NOW - 2 * DAY),
        ("t_plain001", "done", trees["plain"], NOW - 3 * DAY),
        ("t_gone0001", "done", trees["gone"], NOW - 3 * DAY),
        ("t_nowhere1", "done", None, NOW - 3 * DAY),
        ("t_open0001", "running", trees["dirty"], None),                                  # not finished: never reported
    ]
    db.executemany("insert into tasks values (?, 'a title that must never be printed', ?, ?, 1, 2, ?)", cards)
    db.commit()
    db.close()
    return home


class Landing(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = os.path.realpath(tempfile.mkdtemp())
        cls.trees = make_repositories(cls.root)
        cls.home = make_home(cls.root, cls.trees)
        db = landing.open_ro(os.path.join(cls.home, "kanban", "boards", "work", "kanban.db"))
        cls.summary = landing.summarise(*landing.load(db), NOW)
        db.close()
        cls.places = {place["path"]: place for place in cls.summary["everything"]}

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.root, ignore_errors=True)

    def place(self, name: str) -> dict:
        return self.places[self.trees[name]]

    def test_each_way_work_can_end_gets_its_class(self):
        self.assertEqual({name: self.place(name)["class"] for name in self.trees}, {
            "merged": "on_default_branch", "squashed": "on_default_branch", "resquashed": "on_default_branch", "picked": "on_default_branch",
            "clean": "on_default_branch", "local": "local_only", "pushed": "pushed", "dirty": "uncommitted", "solo": "local_only",
            "plain": "plain_folder", "gone": "gone"})

    def test_a_squash_merge_is_on_the_default_branch_though_none_of_its_commits_is_an_ancestor(self):
        for name in ("squashed", "resquashed"):                    # the second: the default branch changed the file again afterwards
            self.assertEqual(g(self.trees[name], "rev-list", "--count", "origin/main..HEAD"), "2")
            self.assertEqual(g(self.trees[name], "cherry", "origin/main", "HEAD").count("+"), 2)
            self.assertEqual(self.place(name)["commits"], 0)
        self.assertEqual(g(self.trees["picked"], "rev-list", "--count", "origin/main..HEAD"), "1")
        self.assertEqual(self.place("picked")["commits"], 0)

    def test_unlanded_work_says_how_much_and_whether_a_remote_has_it(self):
        self.assertEqual((self.place("local")["commits"], self.place("local")["remote_branches"], self.place("local")["branch"]), (1, 0, "local"))
        self.assertEqual((self.place("pushed")["commits"], self.place("pushed")["remote_branches"]), (1, 1))
        self.assertEqual((self.place("dirty")["commits"], self.place("dirty")["changed_files"]), (0, 1))
        self.assertEqual((self.place("local")["base"], self.place("local")["base_is_local"]), ("origin/main", False))

    def test_a_checkout_with_no_remote_is_compared_with_its_own_main_and_says_so(self):
        self.assertEqual((self.place("solo")["base"], self.place("solo")["base_is_local"], self.place("solo")["commits"]), ("main", True, 1))
        self.assertNotIn("fetched_hours", self.place("solo"))

    def test_cards_in_one_checkout_share_a_row_and_open_cards_are_left_out(self):
        self.assertEqual(self.place("local")["cards"], [{"id": "t_local001", "status": "done"}, {"id": "t_local002", "status": "archived"}])
        self.assertEqual(self.place("local")["hours"], 96.0)                              # from the last card to finish there
        self.assertEqual([card["id"] for card in self.place("dirty")["cards"]], ["t_dirty001"])
        self.assertEqual((self.summary["finished_cards"], self.summary["cards_with_a_workspace"], self.summary["places"]), (13, 12, 11))
        self.assertEqual(self.summary["by_class"]["local_only"], {"places": 2, "cards": 3})

    def test_the_note_counts_only_work_that_has_sat_for_a_day(self):
        self.assertEqual([place["path"] for place in self.summary["not_on_a_default_branch"]], [self.trees[name] for name in ("local", "solo", "pushed", "dirty")])
        self.assertEqual(len(self.summary["look_at"]), 2)
        self.assertIn("3 finished cards left work in 2 checkouts", self.summary["look_at"][0])
        self.assertIn("the longest 4.0 days", self.summary["look_at"][0])
        self.assertIn("local_only 2", self.summary["look_at"][0])
        self.assertIn("1 of those checkouts last fetched", self.summary["look_at"][1])    # the one with a remote; nothing here ever fetched

    def test_a_fetch_from_any_worktree_counts_and_its_age_is_reported(self):
        root = os.path.join(self.root, "fetching")                                        # its own repositories: a fetch changes what the others report
        os.mkdir(root)
        g(root, "init", "-q", "--bare", "-b", "main", "origin.git")
        g(root, "init", "-q", "-b", "main", "repo")
        repo, tree, other = (os.path.join(root, name) for name in ("repo", "wt-work", "wt-other"))
        g(repo, "remote", "add", "origin", os.path.join(root, "origin.git"))
        commit(repo, "a.txt", "one\n", "start")
        g(repo, "push", "-q", "-u", "origin", "main")
        g(repo, "worktree", "add", "-q", "-b", "work", tree, "main")
        g(repo, "worktree", "add", "-q", "-b", "other", other, "main")
        commit(tree, "w.txt", "work\n", "a change nobody pushed")
        self.assertIsNone(landing.fetched_at(tree))
        g(other, "fetch", "-q", "origin")
        fetched = landing.fetched_at(tree)
        self.assertIsNotNone(fetched)
        summary = landing.summarise(1, [dict(id="t_work0001", status="done", path=tree, ended=fetched - 4 * DAY)], fetched + HOUR)
        self.assertEqual(summary["not_on_a_default_branch"][0]["fetched_hours"], 1.0)
        self.assertEqual(len(summary["look_at"]), 1)
        self.assertIn("1 finished card left work in 1 checkout that", summary["look_at"][0])

    def test_reading_a_checkout_writes_nothing_in_it(self):
        tree = self.trees["clean"]
        index = g(tree, "rev-parse", "--path-format=absolute", "--git-path", "index")
        os.utime(os.path.join(tree, "c.txt"), (1_000_000_000, 1_000_000_000))             # same bytes, another time: a plain status would refresh the index
        with open(index, "rb") as handle:
            before = handle.read()
        self.assertEqual(landing.inspect(tree)["class"], "on_default_branch")
        with open(index, "rb") as handle:
            self.assertEqual(handle.read(), before)
        g(tree, "status", "--porcelain")                                                  # and a plain status does rewrite it, so the check above means something
        with open(index, "rb") as handle:
            self.assertNotEqual(handle.read(), before)

    def run_tool(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = landing.main(["--hermes-home", self.home, *args], now=NOW)
        return code, out.getvalue()

    def test_prints_ids_paths_and_branches_and_never_a_title(self):
        code, text = self.run_tool()
        self.assertEqual(code, 0)
        self.assertNotIn("must never be printed", text)
        self.assertIn("Board work: 13 finished cards, 12 of them with a workspace, in 11 distinct places.", text)
        self.assertIn("on_default_branch 5 (5)", text)
        self.assertIn(f"  {'local_only':<17} {96.0:>7} h | {self.trees['local']} | branch local | 1 commit, 0 changed files | against origin/main (never fetched) | cards t_local001 (done), t_local002 (archived)", text)
        self.assertIn("| branch dirty | 0 commits, 1 changed file |", text)
        self.assertIn("against main (local, no remote)", text)
        self.assertNotIn(self.trees["merged"], text)
        code, text = self.run_tool("--json")
        self.assertNotIn("must never be printed", text)
        self.assertEqual(json.loads(text)["boards"]["work"]["by_class"]["gone"], {"places": 1, "cards": 1})

    def test_older_than_lists_only_work_that_has_waited_that_long(self):
        code, text = self.run_tool("--older-than-hours", "24")
        self.assertIn(self.trees["local"], text)
        self.assertIn(self.trees["solo"], text)
        self.assertNotIn(self.trees["pushed"], text)
        self.assertNotIn(self.trees["dirty"], text)

    def test_a_board_that_records_no_workspace_reports_none(self):
        home = os.path.join(self.root, "old")
        os.makedirs(os.path.join(home, "kanban", "boards", "work"))
        db = sqlite3.connect(os.path.join(home, "kanban", "boards", "work", "kanban.db"))
        db.execute("create table tasks (id text primary key, status text)")
        db.execute("insert into tasks values ('t_old00001', 'done')")
        db.commit()
        db.close()
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = landing.main(["--hermes-home", home], now=NOW)
        self.assertEqual(code, 0)
        self.assertIn("1 finished card, 0 of them with a workspace, in 0 distinct places", out.getvalue())

    def test_a_missing_board_is_reported_and_fails(self):
        code, text = self.run_tool("--board", "nowhere")
        self.assertEqual(code, 1)
        self.assertIn("no database found", text)


if __name__ == "__main__":
    unittest.main()
