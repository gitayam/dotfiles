#!/usr/bin/env python3
"""Read-only summary of how Hermes Kanban cards ended, by profile, model and card author.

    report_work_board.py                       # every board under ~/.hermes/kanban/boards
    report_work_board.py --board work --json   # one board, as JSON
    report_work_board.py --since-hours 24      # only runs that started in the last day

It opens the board database and each profile's session store read-only and never
dispatches, retries, edits or restarts anything. It prints counts only: no card
title, body, summary or message text.

What it is for: after a few days of use, see which cards finish on the first run and
which do not, and whether that follows the profile, the model, the step limit or the
way the card was written. Three traps it avoids, each learned from a wrong first count:

- A "blocked" run with no worker is a hold someone placed, not a failed run. Only runs
  where a worker started are counted as attempts.
- The model a run used is read from the worker's session. A completed run names its
  session in its own record; a run that ended any other way names none, but the board's
  admission event for that run does. Only a run with neither falls back to the card's
  model override or the profile's default, and that row is marked "assumed". Assuming
  where a record existed once charged 22 of a role's 37 failed runs to the model the role
  runs today instead of the ones they ran on.
- A card that waits for a parent card is waiting by design. Waiting time is measured on
  cards with no parent.

Every figure covers the board's whole history unless `--since-hours` is given. A board
whose limits, models or prompts changed last week mixes two systems in one row: give the
hours since the change. The window keeps runs that started inside it and the cards that
were created or run inside it.

It also prints how many model turns a minute the board made at each number of workers
running, from the times the sessions recorded. A board setting says how many workers may
run; only this says whether the model behind them kept up: how much slower each worker
gets as the board widens, and whether the board as a whole still gains. It is what
happened, not a test: the bands differ in hour and in what the cards asked, and a shared
model server has other users. Compare two windows before acting on one.
"""
from __future__ import annotations

import argparse
import bisect
import collections
import json
import os
import re
import sqlite3
import statistics
import sys
import time

COMPLETED = "completed"
BUDGET = re.compile(r"Iteration budget exhausted \((\d+)/(\d+)\)")
TIME_LIMIT = re.compile(r"elapsed (\d+)s > limit (\d+)s")
WIDTHS = ((1, 1), (2, 2), (3, 4), (5, 6), (7, 8), (9, 10), (11, None))


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


def load(board_db: sqlite3.Connection, since: float | None = None) -> dict:
    """Cards, runs and event counts. With `since`: runs that started from then on, and the cards created or run from then on."""
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
    admitted = admitted_sessions(board_db)
    runs = []
    for row in board_db.execute(
        f"select task_id, profile, coalesce(outcome, status), started_at, ended_at, error, metadata, {pid}, {wstart}, id from task_runs"
    ):
        try:
            session = (json.loads(row[6] or "{}") or {}).get("worker_session_id")
        except (ValueError, AttributeError):
            session = None
        from_admission = not session and bool(admitted.get(row[9]))
        runs.append(dict(task=row[0], profile=row[1] or "(none)", outcome=row[2] or "(none)", started_at=row[3], ended_at=row[4],
                         error=row[5] or "", session=session or admitted.get(row[9]), session_from_admission=from_admission,
                         worker=bool(row[7] or row[8]) or bool(row[3] and row[4] and row[4] > row[3])))
    children = {row[0] for row in board_db.execute("select child_id from task_links")} if "task_links" in tables(board_db) else set()
    events = {}
    if "task_events" in tables(board_db):
        dated = since is not None and "created_at" in columns(board_db, "task_events")
        events = dict(board_db.execute(f"select kind, count(*) from task_events {'where created_at >= ?' if dated else ''} group by 1", (since,) if dated else ()))
    cards = tasks
    if since is not None:
        runs = [run for run in runs if (run["started_at"] or 0) >= since]
        ran = {run["task"] for run in runs}
        cards = {tid: task for tid, task in tasks.items() if tid in ran or (task["created_at"] or 0) >= since}
    return dict(tasks=tasks, cards=cards, runs=runs, children=children, events=events)


def tables(db: sqlite3.Connection) -> set[str]:
    return {row[0] for row in db.execute("select name from sqlite_master where type='table'")}


def admitted_sessions(board_db: sqlite3.Connection) -> dict[int, str]:
    """Run id to the session the board admitted for it, for every run including the failed ones.

    A board without that event, or an older one whose events carry no run or payload, gives none.
    """
    if "task_events" not in tables(board_db) or not {"run_id", "payload"} <= columns(board_db, "task_events"):
        return {}
    found = {}
    for run, payload in board_db.execute("select run_id, payload from task_events where kind='owner_admitted' and run_id is not null order by id"):
        try:
            session = (json.loads(payload or "{}") or {}).get("session_id")
        except (ValueError, AttributeError):
            continue
        if isinstance(session, str) and session:
            found[run] = session
    return found


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

    def turn_times(profile: str, session: str | None) -> list[float]:
        """When each model turn of the session was recorded; none when the store keeps no times."""
        if lookup(profile, session)[0] is None:
            return []
        try:
            return [row[0] for row in stores[profile].execute("select timestamp from messages where session_id=? and role='assistant' and timestamp is not null order by timestamp", (session,))]
        except sqlite3.Error:
            return []

    def close():
        for store in stores.values():
            if store is not None:
                store.close()
        stores.clear()

    lookup.turn_times = turn_times
    lookup.close = close
    return lookup


def turns_by_width(runs: list[dict], turn_times, least_seconds: int = 600) -> dict:
    """Model turns a minute across the board, by how many workers were running at that moment.

    A band the board spent under `least_seconds` in is left out. A turn is counted at the width
    the board had when the session recorded it, and only inside its own run: a session's closing
    turn, recorded after the card completed, is not counted.
    """
    spans = [run for run in runs if run["worker"] and run["started_at"] and run["ended_at"] and run["ended_at"] > run["started_at"]]
    starts, ends = sorted(run["started_at"] for run in spans), sorted(run["ended_at"] for run in spans)
    seconds, width, last = collections.Counter(), 0, None
    for at, step in sorted([(at, 1) for at in starts] + [(at, -1) for at in ends]):
        if last is not None and width > 0:
            seconds[width] += at - last
        width, last = width + step, at
    turns, read = collections.Counter(), 0
    for run in spans:
        times = turn_times(run["profile"], run["session"]) if run["session"] else []
        read += bool(times)
        for at in times:
            if run["started_at"] <= at <= run["ended_at"]:
                turns[bisect.bisect_right(starts, at) - bisect.bisect_left(ends, at)] += 1
    rows = []
    for low, high in WIDTHS:
        inside = [n for n in seconds if n >= low and (high is None or n <= high)]
        spent = sum(seconds[n] for n in inside)
        if spent < least_seconds:
            continue
        made = sum(count for n, count in turns.items() if n >= low and (high is None or n <= high))
        worker_seconds = sum(n * seconds[n] for n in inside)
        rows.append(dict(workers=str(low) if low == high else f"{low}-{high}" if high else f"{low}+", minutes=round(spent / 60), turns=made,
                         turns_per_minute=round(made * 60 / spent, 2), per_worker_per_minute=round(made * 60 / worker_seconds, 2)))
    return dict(runs_measured=len(spans), runs_with_turn_times=read, by_width=rows)


def percentile(values: list, share: float):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * share))]


def summarise(data: dict, facts: dict[str, dict], lookup=lambda profile, session: (None, None)) -> dict:
    tasks, runs, cards = data["tasks"], data["runs"], data.get("cards", data["tasks"])
    by_model: dict[tuple, collections.Counter] = collections.defaultdict(collections.Counter)
    by_creator: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    steps: dict[str, list] = collections.defaultdict(list)
    holds = collections.Counter()
    budgets = collections.Counter()
    budget_by_creator = collections.Counter()
    time_deaths: list[dict] = []
    attempts_per_card = collections.Counter()
    from_admission = 0
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
        elif run.get("session_from_admission"):
            from_admission += 1
        by_model[(run["profile"], model, source)][run["outcome"]] += 1
        by_creator[task.get("created_by", "(none)")][run["outcome"]] += 1
        if turns is not None and run["outcome"] == COMPLETED:
            steps[run["profile"]].append(turns)
        match = BUDGET.search(run["error"])
        if match:
            budgets[f"{match.group(1)}/{match.group(2)} {run['profile']}"] += 1
            budget_by_creator[task.get("created_by", "(none)")] += 1
        match = TIME_LIMIT.search(run["error"])
        if match:
            time_deaths.append({"limit": int(match.group(2)), "elapsed": int(match.group(1))})

    def rows(groups: dict) -> list:
        out = []
        for key, outcomes in sorted(groups.items(), key=lambda item: (-sum(item[1].values()), str(item[0]))):
            total = sum(outcomes.values())
            out.append(dict(key=list(key) if isinstance(key, tuple) else key, runs=total, completed=outcomes.get(COMPLETED, 0),
                            other={name: count for name, count in sorted(outcomes.items()) if name != COMPLETED}))
        return out

    waits = [t["started_at"] - t["created_at"] for tid, t in cards.items() if t["started_at"] and t["created_at"] and tid not in data["children"]]
    lasted = [t["completed_at"] - t["started_at"] for t in cards.values() if t["started_at"] and t["completed_at"]]
    step_rows = []
    for profile, used in sorted(steps.items()):
        cap = facts.get(profile, {}).get("step_cap")
        step_rows.append(dict(profile=profile, cap=cap, runs=len(used), median=statistics.median(used), p90=percentile(used, 0.9), max=max(used),
                              at_cap_or_one_below=sum(1 for n in used if cap and n >= cap - 1) if cap else None))
    auto = collections.Counter(t["status"] for t in cards.values() if t["created_by"] == "auto-decomposer")
    worst_overrun = max((d["elapsed"] / d["limit"] for d in time_deaths), default=None)
    summary = dict(
        cards=dict(collections.Counter(t["status"] for t in cards.values())),
        cards_total=len(cards),
        runs_total=len(runs),
        worker_runs=sum(attempts_per_card.values()),
        holds_without_a_worker=dict(holds),
        by_profile_and_model=rows(by_model),
        models_read_through_admission=from_admission,
        by_card_author=rows(by_creator),
        cards_by_number_of_attempts=dict(sorted(collections.Counter(attempts_per_card.values()).items())),
        steps_on_completed_runs=step_rows,
        step_budget_exhausted=dict(budgets),
        step_budget_exhausted_by_card_author=dict(budget_by_creator),
        time_limit_exceeded=len(time_deaths),
        time_limit_deaths=dict(
            by_limit=dict(sorted(collections.Counter(d["limit"] for d in time_deaths).items())),
            worst_overrun=round(worst_overrun, 2) if worst_overrun else None,
        ),
        block_loops_detected=data["events"].get("block_loop_detected", 0),
        decompositions=data["events"].get("decomposed", 0),
        auto_created_cards=dict(auto),
        wait_seconds_no_parent=dict(cards=len(waits), median=statistics.median(waits) if waits else None, p90=percentile(waits, 0.9)),
        run_seconds=dict(cards=len(lasted), median=statistics.median(lasted) if lasted else None, p90=percentile(lasted, 0.9)),
        model_turns_by_workers_running=turns_by_width(runs, getattr(lookup, "turn_times", lambda profile, session: [])),
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
    if summary["time_limit_exceeded"] >= 3:
        deaths = summary["time_limit_deaths"]
        worst = f", the worst {deaths['worst_overrun']}x its limit" if deaths["worst_overrun"] else ""
        notes.append(f"{summary['time_limit_exceeded']} runs died at a time limit written on the card{worst}. "
                     "Size a limit from the loaded board's running 90th percentile printed above, not from an idle board; "
                     "a card left without a limit is not killed for time.")
    width = summary.get("model_turns_by_workers_running") or {}
    bands = [row for row in width.get("by_width", []) if row["turns"] >= 30]
    if len(bands) >= 2 and width["runs_with_turn_times"] >= 0.9 * width["runs_measured"]:
        narrow, top, below = bands[0], bands[-1], bands[-2]
        if narrow["workers"] in ("1", "2") and top["per_worker_per_minute"] * 2 <= narrow["per_worker_per_minute"]:
            notes.append(f"A worker made {narrow['per_worker_per_minute']} model turns a minute with {narrow['workers']} running and {top['per_worker_per_minute']} with {top['workers']}: "
                         f"a card takes about {narrow['per_worker_per_minute'] / top['per_worker_per_minute']:.1f} times as long in a wave that wide. Size a card's time limit for the width it will run in.")
        if min(top["minutes"], below["minutes"]) >= 30 and top["turns_per_minute"] <= below["turns_per_minute"] * 1.1:
            notes.append(f"With {top['workers']} workers running the board made {top['turns_per_minute']} model turns a minute over {top['minutes']} minutes, against {below['turns_per_minute']} with {below['workers']}: "
                         "in this window more width was more waiting on the model, not more work. Look at a second window before changing a limit; a shared model server is busier at some hours.")
    if summary["block_loops_detected"]:
        notes.append(f"A second block on the same card was treated as a loop {summary['block_loops_detected']} times. Do not block a card twice: answer the question, or archive it and write a new card.")
    return notes


def as_text(board: str, s: dict, window: str = "") -> str:
    out = [f"Board {board}{window}: {s['cards_total']} cards ({', '.join(f'{k} {v}' for k, v in sorted(s['cards'].items(), key=lambda i: -i[1]))}); {s['runs_total']} runs, of which a worker started {s['worker_runs']}."]
    if s["holds_without_a_worker"]:
        out.append(f"  Holds with no worker (not attempts): {', '.join(f'{k} {v}' for k, v in s['holds_without_a_worker'].items())}.")
    through = f"; {s['models_read_through_admission']} of them found through the board's admission record" if s.get("models_read_through_admission") else ""
    out.append(f"  Worker runs by profile and model (model read from the worker's session{through}; otherwise assumed from the card or profile):")
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
    exhausted = ", ".join(f"{k} x{v}" for k, v in s["step_budget_exhausted"].items())
    limits = ""
    if s["time_limit_exceeded"]:
        deaths = s["time_limit_deaths"]
        limits = f"time limit exceeded on {s['time_limit_exceeded']} runs (limits written at creation: " \
                 f"{', '.join(f'{k} x{v}' for k, v in deaths['by_limit'].items())}"
        if deaths["worst_overrun"]:
            limits += f"; the worst ran {deaths['worst_overrun']}x its limit"
        limits += ")"
    if exhausted or limits:
        out.append("  " + "; ".join(part for part in (exhausted, limits) if part) + ".")
    out.append(f"  Block loops detected: {s['block_loops_detected']}. Decompositions: {s['decompositions']}. Cards the board created itself: {s['auto_created_cards'] or 'none'}.")
    wait, run = s["wait_seconds_no_parent"], s["run_seconds"]
    if wait["cards"]:
        out.append(f"  Waiting before the first start (cards with no parent, {wait['cards']}): median {wait['median']:.0f} s, 90th percentile {wait['p90']:.0f} s. Running: median {run['median']:.0f} s, 90th percentile {run['p90']:.0f} s.")
    width = s.get("model_turns_by_workers_running") or {}
    if width.get("by_width"):
        out.append(f"  Model turns a minute by workers running (turn times read for {width['runs_with_turn_times']} of {width['runs_measured']} runs):")
        for row in width["by_width"]:
            out.append(f"    {row['workers']:>5} running {row['minutes']:>5} min {row['turns']:>6} turns {row['turns_per_minute']:>6.2f} a minute {row['per_worker_per_minute']:>5.2f} per worker")
    for note in s["look_at"]:
        out.append(f"  LOOK AT: {note}")
    return "\n".join(out)


def main(argv: list[str] | None = None, now: float | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read-only summary of how Hermes Kanban cards ended. Prints counts only.")
    parser.add_argument("--hermes-home", default=os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes"))
    parser.add_argument("--board", action="append", help="board name (repeatable); default: every board found")
    parser.add_argument("--since-hours", type=float, help="count only runs that started in the last this many hours, and the cards created or run in them")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    since = None if args.since_hours is None else (time.time() if now is None else now) - args.since_hours * 3600
    window = "" if since is None else f", runs started in the last {args.since_hours:g} h"
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
            result[name] = summarise(load(board, since), facts, lookup)
        finally:
            board.close()
    lookup.close()
    if args.json:
        print(json.dumps(dict(boards=result, missing=missing, since_hours=args.since_hours, profiles={k: {a: b for a, b in v.items() if a != "home"} for k, v in facts.items()}), indent=2))
    else:
        for name, summary in result.items():
            print(as_text(name, summary, window))
        for name in missing:
            print(f"Board {name}: no database found under {boards_root}.")
        if not names:
            print(f"No boards found under {boards_root}.")
    return 1 if missing or not names else 0


if __name__ == "__main__":
    sys.exit(main())
