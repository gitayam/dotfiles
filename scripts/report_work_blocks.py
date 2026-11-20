#!/usr/bin/env python3
"""Read-only report of why open Hermes Kanban cards are open, and where waiting time went.

    report_work_blocks.py                        # every board under ~/.hermes/kanban/boards
    report_work_blocks.py --board work --json    # one board, as JSON
    report_work_blocks.py --board work --titles  # also print card titles

It opens the board database read-only and never dispatches, unblocks, edits or
restarts anything. By default it prints counts and card ids only: no title, body,
comment or block reason. Each card that is not done or archived gets one class:

  waits_for_a_person   blocked, with no failed run behind it; `answered` counts the
                       comments written since the block by an author that is not a worker
                       (a comment does not release a card, so answered ones are listed apart)
  out_of_steps         blocked after a run ended at its step budget
  failed               blocked after another kind of give-up, timeout or crash
  behind               waiting with an open parent; the root blockers are named
  ready, running, triage, todo, other

Waiting time is split by what else was running while a ready card waited: a run of the
same profile (one per role), otherwise two or more runs of other profiles (the total
limit), otherwise nothing.
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import statistics
import sys
import time

from report_work_board import columns, open_ro, percentile, tables

CLOSED = {"done", "archived"}
SYSTEM_AUTHORS = {"auto-decomposer", "specifier", "intake", "dispatcher", "system", "worker"}
READY_KINDS = ("promoted", "unblocked", "specified", "timed_out", "crashed", "reclaimed")
FAIL_KINDS = ("gave_up", "timed_out", "crashed")


def payload(raw) -> dict:
    try:
        value = json.loads(raw or "{}")
    except ValueError:
        return {}
    return value if isinstance(value, dict) else {}


def load(db) -> dict:
    task_cols = columns(db, "tasks")
    title = "title" if "title" in task_cols else "''"
    assignee = "assignee" if "assignee" in task_cols else "null"
    tasks = {row[0]: dict(id=row[0], status=row[1], created_by=row[2] or "(none)", created_at=row[3] or 0, title=row[4] or "", assignee=row[5])
             for row in db.execute(f"select id, status, created_by, created_at, {title}, {assignee} from tasks")}
    parents = collections.defaultdict(list)
    if "task_links" in tables(db):
        for parent, child in db.execute("select parent_id, child_id from task_links"):
            parents[child].append(parent)
    events = collections.defaultdict(list)
    if "task_events" in tables(db):
        for task, kind, raw, at in db.execute("select task_id, kind, payload, created_at from task_events order by id"):
            events[task].append((kind, payload(raw), at or 0))
    comments = collections.defaultdict(list)
    if "task_comments" in tables(db):
        for task, author, at in db.execute("select task_id, author, created_at from task_comments order by id"):
            comments[task].append((author or "", at or 0))
    runs = [dict(task=row[0], profile=row[1] or "(none)", start=row[2], end=row[3])
            for row in db.execute("select task_id, profile, started_at, ended_at from task_runs where started_at is not null")]
    return dict(tasks=tasks, parents=parents, events=events, comments=comments, runs=runs)


def root_blockers(task: str, data: dict, path: frozenset = frozenset()) -> list[str]:
    """The open cards at the head of every chain this card waits behind.

    `path` guards against a cycle only. It is not shared between sibling parents: a card
    that waits behind both a blocked card and a card that itself waits behind that blocked
    card has one root, the blocked card.
    """
    roots = set()
    for parent in data["parents"].get(task, []):
        if parent in path or parent not in data["tasks"] or data["tasks"][parent]["status"] in CLOSED:
            continue
        deeper = root_blockers(parent, data, path | {task})
        roots.update(deeper if deeper else [parent])
    return sorted(roots)


def classify(task: dict, data: dict, workers: set[str], now: float) -> dict:
    events = data["events"].get(task["id"], [])
    blocks = [at for kind, _, at in events if kind == "blocked"]
    since = blocks[-1] if blocks else task["created_at"]
    entry = dict(id=task["id"], status=task["status"], created_by=task["created_by"], assignee=task["assignee"],
                 hours=round(max(0.0, now - since) / 3600, 1))
    if task["status"] == "blocked":
        failures = [(kind, body) for kind, body, _ in events if kind in FAIL_KINDS]
        last_error = str(failures[-1][1].get("error") or "") if failures else ""
        if failures and "budget exhausted" in last_error.lower():
            entry["class"] = "out_of_steps"
        elif failures:
            entry["class"] = "failed"
        else:
            entry["class"] = "waits_for_a_person"
            entry["answered"] = sum(1 for author, at in data["comments"].get(task["id"], []) if at > since and author not in workers)
    elif task["status"] == "todo":
        roots = root_blockers(task["id"], data)
        entry["class"] = "behind" if roots else "todo"
        if roots:
            entry["behind"] = roots
    elif task["status"] in ("ready", "running", "triage"):
        entry["class"] = task["status"]
    else:
        entry["class"] = "other"
    return entry


def waiting(data: dict) -> dict:
    runs = sorted((r for r in data["runs"] if r["end"] and r["end"] > r["start"]), key=lambda r: r["start"])
    totals = collections.Counter()
    waits = []
    for run in runs:
        ready_at = None
        for kind, body, at in data["events"].get(run["task"], []):
            if at > run["start"]:
                continue
            if kind in READY_KINDS or (kind == "created" and body.get("status") == "ready"):
                ready_at = at if ready_at is None else max(ready_at, at)
        if ready_at is None or run["start"] <= ready_at:
            continue
        points = sorted({ready_at, run["start"]} | {x for other in runs for x in (other["start"], other["end"]) if ready_at < x < run["start"]})
        for low, high in zip(points, points[1:]):
            middle = (low + high) / 2
            active = [other for other in runs if other is not run and other["start"] <= middle < other["end"]]
            if any(other["profile"] == run["profile"] for other in active):
                totals["one_per_role"] += high - low
            elif len(active) >= 2:
                totals["total_limit"] += high - low
            else:
                totals["nothing_running"] += high - low
        waits.append(run["start"] - ready_at)
    total = sum(totals.values())
    return dict(runs_measured=len(waits), hours=round(total / 3600, 1),
                seconds={key: round(totals.get(key, 0)) for key in ("one_per_role", "total_limit", "nothing_running")},
                median_seconds=statistics.median(waits) if waits else None, p90_seconds=percentile(waits, 0.9))


def summarise(data: dict, now: float) -> dict:
    workers = {run["profile"] for run in data["runs"]} | SYSTEM_AUTHORS
    cards = [classify(task, data, workers, now) for task in sorted(data["tasks"].values(), key=lambda t: t["created_at"]) if task["status"] not in CLOSED]
    counts = collections.Counter(card["class"] for card in cards)
    answered = [card["id"] for card in cards if card.get("answered")]
    out_by = collections.Counter(card["created_by"] for card in cards if card["class"] == "out_of_steps")
    roots = sorted({root for card in cards for root in card.get("behind", [])})
    look = []
    if answered:
        look.append(f"{len(answered)} blocked cards have a person's comment since they were blocked and are still blocked: a comment does not release a card. Unblock or complete them with the answer recorded.")
    if out_by:
        look.append(f"{sum(out_by.values())} cards ran out of steps (written by: {', '.join(f'{k} {v}' for k, v in out_by.most_common())}). A retry needs the same steps: shorten or split the card, or raise the role's limit.")
    if counts.get("behind"):
        look.append(f"{counts['behind']} cards wait behind {len(roots)} open cards. Release the roots, not the chain.")
    return dict(open_cards=len(cards), by_class=dict(counts), answered_but_still_blocked=answered,
                out_of_steps_by_card_author=dict(out_by), root_blockers=roots, cards=cards, waiting=waiting(data), look_at=look)


def as_text(board: str, s: dict, titles: dict | None) -> str:
    out = [f"Board {board}: {s['open_cards']} open cards ({', '.join(f'{k} {v}' for k, v in sorted(s['by_class'].items(), key=lambda i: -i[1])) or 'none'})."]
    for card in s["cards"]:
        extra = ""
        if card["class"] == "waits_for_a_person":
            extra = f" | comments by a person since: {card.get('answered', 0)}"
        if card.get("behind"):
            extra = f" | behind {', '.join(card['behind'])}"
        name = f" | {titles[card['id']][:70]}" if titles else ""
        out.append(f"  {card['id']} {card['class']:<19} {card['hours']:>7} h | by {card['created_by']} -> {card['assignee'] or '-'}{extra}{name}")
    w = s["waiting"]
    if w["runs_measured"]:
        total = sum(w["seconds"].values()) or 1
        shares = ", ".join(f"{key.replace('_', ' ')} {value / total:.0%}" for key, value in w["seconds"].items())
        out.append(f"  Waiting before a start, {w['runs_measured']} runs: {w['hours']} h in total ({shares}); median {w['median_seconds']:.0f} s, 90th percentile {w['p90_seconds']:.0f} s.")
    for note in s["look_at"]:
        out.append(f"  LOOK AT: {note}")
    return "\n".join(out)


def main(argv: list[str] | None = None, now: float | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read-only report of why open Hermes Kanban cards are open. Counts and ids only unless --titles.")
    parser.add_argument("--hermes-home", default=os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes"))
    parser.add_argument("--board", action="append", help="board name (repeatable); default: every board found")
    parser.add_argument("--titles", action="store_true", help="also print card titles (they may hold private text)")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    now = time.time() if now is None else now
    root = os.path.join(args.hermes_home, "kanban", "boards")
    names = args.board or (sorted(os.listdir(root)) if os.path.isdir(root) else [])
    result, missing, titles = {}, [], {}
    for name in names:
        path = os.path.join(root, name, "kanban.db")
        if not os.path.exists(path):
            missing.append(name)
            continue
        db = open_ro(path)
        try:
            data = load(db)
        finally:
            db.close()
        result[name] = summarise(data, now)
        titles[name] = {task["id"]: task["title"] for task in data["tasks"].values()}
    if args.json:
        if args.titles:
            for name, summary in result.items():
                for card in summary["cards"]:
                    card["title"] = titles[name][card["id"]]
        print(json.dumps(dict(boards=result, missing=missing), indent=2))
    else:
        for name, summary in result.items():
            print(as_text(name, summary, titles[name] if args.titles else None))
        for name in missing:
            print(f"Board {name}: no database found under {root}.")
        if not names:
            print(f"No boards found under {root}.")
    return 1 if missing or not names else 0


if __name__ == "__main__":
    sys.exit(main())
