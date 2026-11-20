#!/usr/bin/env python3
"""Read-only summary of how Hermes Kanban cards ended, by profile, model and card author.

    report_work_board.py                       # every board under ~/.hermes/kanban/boards
    report_work_board.py --board work --json   # one board, as JSON

It opens the board database and each profile's session store read-only and never
dispatches, retries, edits or restarts anything. It prints counts only: no card
title, body, summary or message text.

What it is for: after a few days of use, see which cards finish on the first run and
which do not, and whether that follows the profile, the model, the step limit or the
way the card was written. Three traps it avoids, each learned from a wrong first count:

- A "blocked" run with no worker is a hold someone placed, not a failed run. Only runs
  where a worker started are counted as attempts.
- The model a run used is read from the worker's session when one is recorded. When
  none is (most failed runs), the card's own model override or the profile's default is
  used and the row is marked "assumed".
- A card that waits for a parent card is waiting by design. Waiting time is measured on
  cards with no parent.
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sqlite3
import statistics
import sys

COMPLETED = "completed"
BUDGET = re.compile(r"Iteration budget exhausted \((\d+)/(\d+)\)")
TIME_LIMIT = re.compile(r"elapsed \d+s > limit \d+s")


def open_ro(path: str) -> sqlite3.Connection:
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True)


def columns(db: sqlite3.Connection, table: str) -> set[str]:
    return {row[1] for row in db.execute(f"pragma table_info({table})")}


def read_scalar(config_path: str, section: str, key: str) -> str | None:
    """`section.key` from a YAML file, for a top-level section and a key directly under it.

    Enough for `agent.max_turns` and `model.default`; avoids needing a YAML package.
    """
    try:
        with open(config_path, encoding="utf-8") as handle:
            lines = handle.read().split("\n")
    except OSError:
        return None
    inside = False
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if not line.startswith((" ", "\t")):
            inside = line.split(":")[0].strip() == section
            continue
        if inside:
            match = re.match(r"^\s{1,4}([A-Za-z0-9_]+):\s*(.*?)\s*$", line)
            if match and match.group(1) == key and len(line) - len(line.lstrip()) <= 4:
                return match.group(2).strip("'\"") or None
    return None


def profile_homes(hermes_home: str) -> dict[str, str]:
    """Profile name to its home folder; the default profile is the Hermes home itself."""
    homes = {"default": hermes_home}
    root = os.path.join(hermes_home, "profiles")
    if os.path.isdir(root):
        for name in sorted(os.listdir(root)):
            if os.path.isdir(os.path.join(root, name)):
                homes[name] = os.path.join(root, name)
    return homes


def profile_facts(hermes_home: str) -> dict[str, dict]:
    facts = {}
    for name, home in profile_homes(hermes_home).items():
        config = os.path.join(home, "config.yaml")
        cap = read_scalar(config, "agent", "max_turns")
        facts[name] = {
            "home": home,
            "step_cap": int(cap) if cap and cap.isdigit() else None,
            "default_model": read_scalar(config, "model", "default"),
        }
    return facts


def load(board_db: sqlite3.Connection) -> dict:
    task_cols = columns(board_db, "tasks")
    override = "model_override" if "model_override" in task_cols else "null"
    tasks = {}
    for row in board_db.execute(
        f"select id, status, created_by, {override}, created_at, started_at, completed_at from tasks"
    ):
        tasks[row[0]] = dict(status=row[1], created_by=row[2] or "(none)", override=row[3], created_at=row[4], started_at=row[5], completed_at=row[6])
    run_cols = columns(board_db, "task_runs")
    pid = "worker_pid" if "worker_pid" in run_cols else "null"
    wstart = "worker_started_at" if "worker_started_at" in run_cols else "null"
    runs = []
    for row in board_db.execute(
        f"select task_id, profile, coalesce(outcome, status), started_at, ended_at, error, metadata, {pid}, {wstart} from task_runs"
    ):
        try:
            session = (json.loads(row[6] or "{}") or {}).get("worker_session_id")
        except (ValueError, AttributeError):
            session = None
        runs.append(dict(task=row[0], profile=row[1] or "(none)", outcome=row[2] or "(none)", started_at=row[3], ended_at=row[4],
                         error=row[5] or "", session=session, worker=bool(row[7] or row[8]) or bool(row[3] and row[4] and row[4] > row[3])))
    children = {row[0] for row in board_db.execute("select child_id from task_links")} if "task_links" in tables(board_db) else set()
    events = dict(board_db.execute("select kind, count(*) from task_events group by 1")) if "task_events" in tables(board_db) else {}
    return dict(tasks=tasks, runs=runs, children=children, events=events)


def tables(db: sqlite3.Connection) -> set[str]:
    return {row[0] for row in db.execute("select name from sqlite_master where type='table'")}


def session_reader(facts: dict[str, dict]):
    """Returns `lookup(profile, session_id) -> (model, tool_calling_turns)`; both None when not found."""
    stores: dict[str, sqlite3.Connection | None] = {}

    def lookup(profile: str, session: str | None):
        if not session or profile not in facts:
            return None, None
        if profile not in stores:
            path = os.path.join(facts[profile]["home"], "state.db")
            try:
                stores[profile] = open_ro(path) if os.path.exists(path) else None
            except sqlite3.Error:
                stores[profile] = None
        store = stores[profile]
        if store is None:
            return None, None
        try:
            model = store.execute("select model from sessions where id=?", (session,)).fetchone()
            turns = store.execute(
                "select count(*) from messages where session_id=? and role='assistant' and tool_calls is not null and tool_calls not in ('', '[]', 'null')",
                (session,),
            ).fetchone()
        except sqlite3.Error:
            return None, None
        return (model[0] if model and model[0] else None), (turns[0] if turns else None)

    def close():
        for store in stores.values():
            if store is not None:
                store.close()
        stores.clear()

    lookup.close = close
    return lookup


def percentile(values: list, share: float):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * share))]


def summarise(data: dict, facts: dict[str, dict], lookup=lambda profile, session: (None, None)) -> dict:
    tasks, runs = data["tasks"], data["runs"]
    by_model: dict[tuple, collections.Counter] = collections.defaultdict(collections.Counter)
    by_creator: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    steps: dict[str, list] = collections.defaultdict(list)
    holds = collections.Counter()
    budgets = collections.Counter()
    budget_by_creator = collections.Counter()
    time_limits = 0
    attempts_per_card = collections.Counter()
    for run in runs:
        task = tasks.get(run["task"], {})
        if not run["worker"]:
            holds[run["outcome"]] += 1
            continue
        attempts_per_card[run["task"]] += 1
        model, turns = lookup(run["profile"], run["session"])
        source = "session"
        if not model:
            model = task.get("override") or (facts.get(run["profile"], {}).get("default_model")) or "unknown"
            source = "assumed"
        by_model[(run["profile"], model, source)][run["outcome"]] += 1
        by_creator[task.get("created_by", "(none)")][run["outcome"]] += 1
        if turns is not None and run["outcome"] == COMPLETED:
            steps[run["profile"]].append(turns)
        match = BUDGET.search(run["error"])
        if match:
            budgets[f"{match.group(1)}/{match.group(2)} {run['profile']}"] += 1
            budget_by_creator[task.get("created_by", "(none)")] += 1
        if TIME_LIMIT.search(run["error"]):
            time_limits += 1

    def rows(groups: dict) -> list:
        out = []
        for key, outcomes in sorted(groups.items(), key=lambda item: (-sum(item[1].values()), str(item[0]))):
            total = sum(outcomes.values())
            out.append(dict(key=list(key) if isinstance(key, tuple) else key, runs=total, completed=outcomes.get(COMPLETED, 0),
                            other={name: count for name, count in sorted(outcomes.items()) if name != COMPLETED}))
        return out

    waits = [t["started_at"] - t["created_at"] for tid, t in tasks.items() if t["started_at"] and t["created_at"] and tid not in data["children"]]
    lasted = [t["completed_at"] - t["started_at"] for t in tasks.values() if t["started_at"] and t["completed_at"]]
    step_rows = []
    for profile, used in sorted(steps.items()):
        cap = facts.get(profile, {}).get("step_cap")
        step_rows.append(dict(profile=profile, cap=cap, runs=len(used), median=statistics.median(used), p90=percentile(used, 0.9), max=max(used),
                              at_cap_or_one_below=sum(1 for n in used if cap and n >= cap - 1) if cap else None))
    auto = collections.Counter(t["status"] for t in tasks.values() if t["created_by"] == "auto-decomposer")
    summary = dict(
        cards=dict(collections.Counter(t["status"] for t in tasks.values())),
        cards_total=len(tasks),
        runs_total=len(runs),
        worker_runs=sum(attempts_per_card.values()),
        holds_without_a_worker=dict(holds),
        by_profile_and_model=rows(by_model),
        by_card_author=rows(by_creator),
        cards_by_number_of_attempts=dict(sorted(collections.Counter(attempts_per_card.values()).items())),
        steps_on_completed_runs=step_rows,
        step_budget_exhausted=dict(budgets),
        step_budget_exhausted_by_card_author=dict(budget_by_creator),
        time_limit_exceeded=time_limits,
        block_loops_detected=data["events"].get("block_loop_detected", 0),
        decompositions=data["events"].get("decomposed", 0),
        auto_created_cards=dict(auto),
        wait_seconds_no_parent=dict(cards=len(waits), median=statistics.median(waits) if waits else None, p90=percentile(waits, 0.9)),
        run_seconds=dict(cards=len(lasted), median=statistics.median(lasted) if lasted else None, p90=percentile(lasted, 0.9)),
    )
    summary["look_at"] = look_at(summary)
    return summary


def look_at(summary: dict, small: int = 10) -> list[str]:
    """Plain sentences about what the counts suggest. A group under `small` runs is never compared."""
    notes = []
    authors = {row["key"]: row for row in summary["by_card_author"] if row["runs"] >= small}
    if len(authors) > 1:
        best = max(authors.values(), key=lambda row: row["completed"] / row["runs"])
        for name, row in authors.items():
            share, top = row["completed"] / row["runs"], best["completed"] / best["runs"]
            if row is not best and top - share >= 0.2:
                notes.append(f"Cards written by {name} completed {row['completed']} of {row['runs']} runs ({share:.0%}); cards written by {best['key']} completed {best['completed']} of {best['runs']} ({top:.0%}). Look at how the two kinds of card are written before changing a model or a limit.")
    exhausted = sum(summary["step_budget_exhausted"].values())
    if exhausted:
        by = ", ".join(f"{name} {count}" for name, count in sorted(summary["step_budget_exhausted_by_card_author"].items(), key=lambda item: -item[1]))
        notes.append(f"The step budget ran out on {exhausted} runs (by card author: {by}). A card that needs more steps than the profile allows cannot finish however often it is retried: split it or shorten its contract.")
    for row in summary["steps_on_completed_runs"]:
        if row["cap"] and row["runs"] >= small and row["at_cap_or_one_below"] / row["runs"] >= 0.1:
            notes.append(f"{row['profile']}: {row['at_cap_or_one_below']} of {row['runs']} completed runs used the last or second-last allowed step (limit {row['cap']}). Contracts for this profile are close to the limit.")
    auto = summary["auto_created_cards"]
    if sum(auto.values()) >= 5 and auto.get("done", 0) / sum(auto.values()) < 0.7:
        notes.append(f"Of {sum(auto.values())} cards the board created by itself, {auto.get('done', 0)} are done. Read what it wrote into them before releasing more.")
    if summary["block_loops_detected"]:
        notes.append(f"A second block on the same card was treated as a loop {summary['block_loops_detected']} times. Do not block a card twice: answer the question, or archive it and write a new card.")
    return notes


def as_text(board: str, s: dict) -> str:
    out = [f"Board {board}: {s['cards_total']} cards ({', '.join(f'{k} {v}' for k, v in sorted(s['cards'].items(), key=lambda i: -i[1]))}); {s['runs_total']} runs, of which a worker started {s['worker_runs']}."]
    if s["holds_without_a_worker"]:
        out.append(f"  Holds with no worker (not attempts): {', '.join(f'{k} {v}' for k, v in s['holds_without_a_worker'].items())}.")
    out.append("  Worker runs by profile and model (model read from the session, or assumed from the card or profile):")
    for row in s["by_profile_and_model"]:
        profile, model, source = row["key"]
        other = ", ".join(f"{k} {v}" for k, v in row["other"].items())
        out.append(f"    {profile:<14} {model:<26} {'(assumed)' if source == 'assumed' else '':<9} {row['completed']:>4} of {row['runs']:<4} completed{'; ' + other if other else ''}")
    out.append("  Worker runs by who created the card:")
    for row in s["by_card_author"]:
        other = ", ".join(f"{k} {v}" for k, v in row["other"].items())
        out.append(f"    {row['key']:<26} {row['completed']:>4} of {row['runs']:<4} completed{'; ' + other if other else ''}")
    out.append(f"  Cards by number of attempts: {', '.join(f'{k}: {v}' for k, v in s['cards_by_number_of_attempts'].items())}.")
    for row in s["steps_on_completed_runs"]:
        cap = f"limit {row['cap']}" if row["cap"] else "limit not read"
        near = f"; {row['at_cap_or_one_below']} at the limit or one below" if row["cap"] else ""
        out.append(f"  Steps on completed runs, {row['profile']} ({cap}): median {row['median']}, 90th percentile {row['p90']}, most {row['max']}{near}.")
    if s["step_budget_exhausted"]:
        out.append(f"  Step budget exhausted: {', '.join(f'{k} x{v}' for k, v in s['step_budget_exhausted'].items())}. Time limit exceeded: {s['time_limit_exceeded']}.")
    out.append(f"  Block loops detected: {s['block_loops_detected']}. Decompositions: {s['decompositions']}. Cards the board created itself: {s['auto_created_cards'] or 'none'}.")
    wait, run = s["wait_seconds_no_parent"], s["run_seconds"]
    if wait["cards"]:
        out.append(f"  Waiting before the first start (cards with no parent, {wait['cards']}): median {wait['median']:.0f} s, 90th percentile {wait['p90']:.0f} s. Running: median {run['median']:.0f} s, 90th percentile {run['p90']:.0f} s.")
    for note in s["look_at"]:
        out.append(f"  LOOK AT: {note}")
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read-only summary of how Hermes Kanban cards ended. Prints counts only.")
    parser.add_argument("--hermes-home", default=os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes"))
    parser.add_argument("--board", action="append", help="board name (repeatable); default: every board found")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    boards_root = os.path.join(args.hermes_home, "kanban", "boards")
    names = args.board or (sorted(os.listdir(boards_root)) if os.path.isdir(boards_root) else [])
    facts = profile_facts(args.hermes_home)
    lookup = session_reader(facts)
    result, missing = {}, []
    for name in names:
        path = os.path.join(boards_root, name, "kanban.db")
        if not os.path.exists(path):
            missing.append(name)
            continue
        board = open_ro(path)
        try:
            result[name] = summarise(load(board), facts, lookup)
        finally:
            board.close()
    lookup.close()
    if args.json:
        print(json.dumps(dict(boards=result, missing=missing, profiles={k: {a: b for a, b in v.items() if a != "home"} for k, v in facts.items()}), indent=2))
    else:
        for name, summary in result.items():
            print(as_text(name, summary))
        for name in missing:
            print(f"Board {name}: no database found under {boards_root}.")
        if not names:
            print(f"No boards found under {boards_root}.")
    return 1 if missing or not names else 0


if __name__ == "__main__":
    sys.exit(main())
