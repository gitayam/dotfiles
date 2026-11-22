#!/usr/bin/env python3
"""Read-only report of where the work of finished Hermes Kanban cards stands: on a default branch, or only on this machine.

    report_work_landing.py                                    # every board under ~/.hermes/kanban/boards
    report_work_landing.py --board work --json                # one board, as JSON
    report_work_landing.py --board work --older-than-hours 24 # list only work that has sat for a day

"Done" says a run ended. It does not say the work left the checkout the worker used.
For every done or archived card whose workspace is a git checkout, each distinct
checkout gets one class:

  on_default_branch  the default branch lacks nothing the checkout holds
  uncommitted        changed or new files that are in no commit
  local_only         commits the default branch lacks, on no remote branch
  pushed             commits the default branch lacks, on another remote branch
  no_default_branch  nothing to compare with
  unreadable         a git command failed or ran out of time
  gone               the folder no longer exists (usually removed after integration)
  plain_folder       the card worked in a folder that is not a checkout

Commits count as on the default branch when the tip is an ancestor of it; or every
commit has an equivalent patch there (`git cherry`: a rebase, a cherry-pick, a squash
of one commit); or the default branch holds every file they touched exactly as the tip
has it, or has one commit carrying the same change as all of them together (a squash of
several). An ancestry test alone calls every squash merge unlanded.

The default branch is the remote's (`origin/HEAD`, else `origin/main` or
`origin/master`) as of the last fetch: this tool never fetches, and prints how old the
fetch is. A checkout with no remote is compared with its local `main` or `master`, and
the report says so. What it cannot see: a commit cherry-picked onto another pushed
branch reads as local_only until that branch merges, and a squash whose lines the
default branch changed before and after it can read as unlanded.

It opens the board database read-only and runs git read commands only, with optional
locks off, so reading the status of a checkout a worker is using writes nothing there.
It prints card ids, checkout paths and branch names: never a title or a diff.
"""
from __future__ import annotations

import argparse
import collections
import glob
import json
import os
import subprocess
import sys
import time

from report_work_board import columns, open_ro

FINISHED = ("done", "archived")
NOT_LANDED = ("uncommitted", "local_only", "pushed")
LISTED = NOT_LANDED + ("no_default_branch", "unreadable")
GIT_ENV = {"GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"}
MANY_PATHS = 200


def some(count: int, noun: str) -> str:
    return f"{count} {noun}{'' if count == 1 else 's'}"


def git(path: str, *args: str, stdin: str | None = None, timeout: float = 60) -> tuple[int, str, str]:
    """Exit status, output and error text of one git read command in `path`; status -1 when it could not run."""
    command = ["git", "-C", path, "--literal-pathspecs", "-c", "core.fsmonitor=false", *args]
    try:
        done = subprocess.run(command, input=stdin, capture_output=True, text=True, errors="replace", timeout=timeout, env={**os.environ, **GIT_ENV})
    except (OSError, subprocess.TimeoutExpired):
        return -1, "", ""
    return done.returncode, done.stdout.strip(), done.stderr


def default_branch(top: str) -> tuple[str | None, bool]:
    """The branch to compare with, and whether it is a local one because the checkout has no remote."""
    code, ref, _ = git(top, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
    if code == 0 and ref:
        return ref, False
    for ref in ("origin/main", "origin/master"):
        if git(top, "rev-parse", "--verify", "--quiet", f"refs/remotes/{ref}^{{commit}}")[0] == 0:
            return ref, False
    code, remotes, _ = git(top, "remote")
    if code == 0 and not remotes:
        for ref in ("main", "master"):
            if git(top, "rev-parse", "--verify", "--quiet", f"refs/heads/{ref}^{{commit}}")[0] == 0:
                return ref, True
    return None, False


def patch_ids(top: str, *args: str) -> set[str]:
    code, patch, _ = git(top, *args)
    if code != 0 or not patch:
        return set()
    code, ids, _ = git(top, "patch-id", "--stable", stdin=patch + "\n")
    return {line.split()[0] for line in ids.splitlines() if line.strip()} if code == 0 else set()


def carried_another_way(top: str, base: str) -> bool:
    """True when the default branch has the commits' change though no commit of theirs has an equivalent there.

    Either it holds every file they touched exactly as the tip has it, or one of its commits
    since the fork carries the same change as all of them together: a squash merge both ways.
    """
    code, fork, _ = git(top, "merge-base", base, "HEAD")
    if code != 0 or not fork:
        return False
    code, names, _ = git(top, "diff", "--name-only", "-z", "--no-renames", fork, "HEAD")
    if code != 0:
        return False
    paths = [name for name in names.split("\0") if name]
    if not paths:
        return True
    if all(git(top, "diff", "--quiet", "--no-ext-diff", base, "HEAD", "--", *paths[start:start + MANY_PATHS])[0] == 0
           for start in range(0, len(paths), MANY_PATHS)):
        return True
    if len(paths) > MANY_PATHS:
        return False
    together = patch_ids(top, "diff", "--no-ext-diff", "--no-textconv", "--no-renames", fork, "HEAD")
    there = patch_ids(top, "log", "-p", "--no-ext-diff", "--no-textconv", "--no-renames", "--no-merges", "--format=commit %H", f"{fork}..{base}", "--", *paths)
    return bool(together) and together <= there


def fetched_at(top: str) -> float | None:
    """When any worktree of this repository last fetched; None when none ever did."""
    code, common, _ = git(top, "rev-parse", "--git-common-dir")
    if code != 0 or not common:
        return None
    common = os.path.join(top, common)
    times = [os.path.getmtime(path) for path in [os.path.join(common, "FETCH_HEAD"), *glob.glob(os.path.join(glob.escape(common), "worktrees", "*", "FETCH_HEAD"))] if os.path.exists(path)]
    return max(times) if times else None


def inspect(path: str) -> dict:
    """Where one workspace stands."""
    if not os.path.isdir(path):
        return {"class": "gone"}
    code, top, error = git(path, "rev-parse", "--show-toplevel")
    if code != 0 or not top:
        return {"class": "plain_folder" if "not a git repository" in error else "unreadable"}
    state = {"class": "unreadable", "top": top}
    code, branch, _ = git(top, "rev-parse", "--abbrev-ref", "HEAD")
    state["branch"] = branch if code == 0 and branch != "HEAD" else None
    code, status, _ = git(top, "status", "--porcelain")
    if code != 0:
        return state
    state["changed_files"] = sum(1 for line in status.splitlines() if line.strip())
    base, local = default_branch(top)
    if not base:
        return {**state, "class": "no_default_branch"}
    state.update(base=base, base_is_local=local, fetched_at=None if local else fetched_at(top))
    code, ahead, _ = git(top, "rev-list", "--count", f"{base}..HEAD")
    if code != 0 or not ahead.isdigit():
        return state
    missing = int(ahead)
    if missing:
        code, cherry, _ = git(top, "cherry", base, "HEAD")
        if code != 0:
            return state
        missing = sum(1 for line in cherry.splitlines() if line.startswith("+"))
    if missing and carried_another_way(top, base):
        missing = 0
    state["commits"] = missing
    if missing:
        code, refs, _ = git(top, "for-each-ref", "--contains", "HEAD", "--format=%(refname)", "refs/remotes")
        if code != 0:
            return state
        state["remote_branches"] = sum(1 for ref in refs.splitlines() if ref and not ref.endswith("/HEAD"))
        state["class"] = "pushed" if state["remote_branches"] else "local_only"
    else:
        state["class"] = "uncommitted" if state["changed_files"] else "on_default_branch"
    return state


def load(db) -> tuple[int, list[dict]]:
    """How many cards are finished, and those of them that name a workspace."""
    cols = columns(db, "tasks")
    finished = db.execute(f"select count(*) from tasks where status in {FINISHED}").fetchone()[0]
    if "workspace_path" not in cols:
        return finished, []
    ended = ", ".join(name for name in ("completed_at", "started_at", "created_at") if name in cols) or "null"
    rows = db.execute(f"select id, status, workspace_path, coalesce({ended}, 0) from tasks where status in {FINISHED} and workspace_path is not null and workspace_path != ''")
    return finished, [dict(id=row[0], status=row[1], path=row[2], ended=row[3] or 0) for row in rows]


def summarise(finished: int, cards: list[dict], now: float, older_than_hours: float = 0, look=inspect) -> dict:
    by_path = collections.defaultdict(list)
    for card in cards:
        by_path[card["path"]].append(card)
    places: dict[str, dict] = {}
    for path, here in sorted(by_path.items()):
        state = look(path)
        key = state.pop("top", None) or path
        place = places.setdefault(key, {**state, "path": key, "cards": []})
        place["cards"] += [dict(id=card["id"], status=card["status"], ended=card["ended"]) for card in here]
    for place in places.values():
        place["hours"] = round((now - max(card.pop("ended") for card in place["cards"])) / 3600, 1)
        if place.get("fetched_at") is not None:
            place["fetched_hours"] = round((now - place["fetched_at"]) / 3600, 1)
        place.pop("fetched_at", None)
        place["cards"].sort(key=lambda card: card["id"])
    by_class = {}
    for name in sorted({place["class"] for place in places.values()}):
        of = [place for place in places.values() if place["class"] == name]
        by_class[name] = dict(places=len(of), cards=sum(len(place["cards"]) for place in of))
    listed = sorted((place for place in places.values() if place["class"] in LISTED and place["hours"] >= older_than_hours), key=lambda place: (-place["hours"], place["path"]))
    stale = [place for place in places.values() if place["class"] in NOT_LANDED and place["hours"] >= 24]
    notes = []
    if stale:
        kinds = collections.Counter(place["class"] for place in stale)
        notes.append(f"{some(sum(len(place['cards']) for place in stale), 'finished card')} left work in {some(len(stale), 'checkout')} that is not on a default branch and has sat for more than a day "
                     f"(the longest {max(place['hours'] for place in stale) / 24:.1f} days): {', '.join(f'{kind} {count}' for kind, count in sorted(kinds.items()))}. "
                     "Done says a run ended, not that the work landed. Give each checkout an end: a request opened or merged, a decision the owner's list carries, or the work rejected and the checkout removed.")
        unfetched = [place for place in stale if not place.get("base_is_local") and place.get("fetched_hours", 24) >= 24]
        if unfetched:
            notes.append(f"{len(unfetched)} of those checkouts last fetched from the remote a day or more ago, or never. Fetch before trusting that the work is not on the default branch.")
    return dict(finished_cards=finished, cards_with_a_workspace=len(cards), places=len(places), by_class=by_class, not_on_a_default_branch=listed,
                everything=sorted(places.values(), key=lambda place: place["path"]), look_at=notes)


def as_text(board: str, s: dict, home: str) -> str:
    counts = ", ".join(f"{name} {row['places']} ({row['cards']})" for name, row in sorted(s["by_class"].items(), key=lambda item: -item[1]["places"])) or "none"
    out = [f"Board {board}: {some(s['finished_cards'], 'finished card')}, {s['cards_with_a_workspace']} of them with a workspace, in {some(s['places'], 'distinct place')}.",
           f"  Where the work stands, as places (cards): {counts}."]
    for place in s["not_on_a_default_branch"]:
        path = "~" + place["path"][len(home):] if home and place["path"].startswith(home + os.sep) else place["path"]
        detail = []
        if place.get("branch"):
            detail.append(f"branch {place['branch']}")
        if "commits" in place or "changed_files" in place:
            detail.append(f"{some(place.get('commits', 0), 'commit')}, {some(place.get('changed_files', 0), 'changed file')}")
        if place.get("base"):
            fetched = "local, no remote" if place.get("base_is_local") else f"fetched {place['fetched_hours']} h ago" if "fetched_hours" in place else "never fetched"
            detail.append(f"against {place['base']} ({fetched})")
        detail.append("cards " + ", ".join(f"{card['id']} ({card['status']})" for card in place["cards"]))
        out.append(f"  {place['class']:<17} {place['hours']:>7} h | {path} | {' | '.join(detail)}")
    for note in s["look_at"]:
        out.append(f"  LOOK AT: {note}")
    return "\n".join(out)


def main(argv: list[str] | None = None, now: float | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read-only report of whether finished Hermes Kanban cards' work reached a default branch. Ids, paths and branch names only.")
    parser.add_argument("--hermes-home", default=os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes"))
    parser.add_argument("--board", action="append", help="board name (repeatable); default: every board found")
    parser.add_argument("--older-than-hours", type=float, default=0, help="list only work whose last card finished at least this long ago")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    now = time.time() if now is None else now
    root = os.path.join(args.hermes_home, "kanban", "boards")
    names = args.board or (sorted(os.listdir(root)) if os.path.isdir(root) else [])
    result, missing = {}, []
    for name in names:
        path = os.path.join(root, name, "kanban.db")
        if not os.path.exists(path):
            missing.append(name)
            continue
        db = open_ro(path)
        try:
            finished, cards = load(db)
        finally:
            db.close()
        result[name] = summarise(finished, cards, now, args.older_than_hours)
    if args.json:
        print(json.dumps(dict(boards=result, missing=missing), indent=2))
    else:
        for name, summary in result.items():
            print(as_text(name, summary, os.path.expanduser("~")))
        for name in missing:
            print(f"Board {name}: no database found under {root}.")
        if not names:
            print(f"No boards found under {root}.")
    return 1 if missing or not names else 0


if __name__ == "__main__":
    sys.exit(main())
