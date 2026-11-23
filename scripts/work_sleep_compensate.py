#!/usr/bin/env python3
"""Compensate the board's wall-clock run timers for the time this Mac spent asleep.

The dispatcher measures a worker's runtime and a claim's age from unix epochs
(``now - active_started_at``, where the active start is the current run's
``started_at`` or, failing that, the task's). macOS sleep is billed as work:
closing the lid for an hour inflates every running worker's elapsed time by
that hour, so on wake the dispatcher kills workers as timed out and reclaims
claims that never actually went stale. The work was frozen, not slow.

This tool is meant to run every minute from a LaunchAgent. Each tick it reads
the machine's total slept seconds since boot (``mach_continuous_time -
mach_absolute_time``, scaled) and compares it with the total recorded in a
small state file from the previous tick. When the total grew by D seconds, the
Mac slept D seconds since the last tick, and every running worker whose active
start predates that tick has its active start pushed forward by D in the board
database, so elapsed time counts only awake time.

Two deliberate limits, both on the generous side:

- A run started after the previous tick (within one interval of the lid
  closing) is left alone and may be under-compensated by up to one interval.
- The sleep delta is capped at the wall time between the ticks plus one
  interval, so a clock jump cannot hand a worker hours of invented credit.

A reboot resets nothing worth keeping: the slept-since-boot total shrinks back
towards zero, which is read as a reboot, the state is re-recorded and nothing
is compensated. The state file is written on every tick whether or not the
board is touched, so a re-run never compensates the same sleep twice. Read-only
on the board unless ``--apply``; it touches only the two columns the
dispatcher's timers read, on tasks that are running right now, and nothing
else.

What the shift cannot do, measured on 2026-11-23 (66 ticks that saw a sleep, 3
that still found a running card to shift): a worker does not survive a sleep of
more than a few minutes whatever its timers say. Its turn lease lapses while the
Mac is asleep and it is interrupted on wake, and the dispatcher's own pass runs
within seconds of the wake, before this tick. So ``--recover`` does the other
half: a card whose one attempt was ended by a wake is released again, by the
board's own ``unblock``, once the lid is open and the Mac has stayed awake for a
moment. A card is released at most a few times, never when it ran out of steps
or was blocked by a person or by its own worker, and never while the lid is
closed, where the next sleep would only stop it again.
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

STATE_VERSION = 1
GRACE_SECONDS = 180          # an attempt ended this soon after a wake was ended by it
MIN_SLEEP_SECONDS = 120      # shorter naps stop nobody
SETTLE_SECONDS = 90          # a dark wake lasts under a minute: wait until the Mac has stayed awake
MAX_RELEASES = 3             # per card, ever: a card that keeps stopping stays for a person
RECENT_SECONDS = 48 * 3600   # older stops are history, not work in flight
STOPPED_BY_WAKE = ("timed_out", "reclaimed", "crashed")
SLEEP_LINE = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) ([+-]\d{4}) (Sleep|Wake|DarkWake) {2,}\t")


def slept_seconds() -> float:
    """Total seconds this Mac has spent asleep since boot (macOS only).

    ``mach_continuous_time`` advances through sleep, ``mach_absolute_time`` does
    not, so their difference is the slept time since boot. Both must be declared
    64-bit: ctypes defaults to a 32-bit return, which truncates the counter and
    produces a small negative nonsense.
    """
    import ctypes

    libc = ctypes.CDLL(None)
    libc.mach_absolute_time.restype = ctypes.c_uint64
    libc.mach_continuous_time.restype = ctypes.c_uint64
    timebase = ctypes.c_uint32 * 2  # numer, denom
    tb = timebase()
    if libc.mach_timebase_info(tb) != 0:
        raise OSError("mach_timebase_info failed")
    scale = tb[0] / tb[1] / 1e9
    # Read the non-sleeping clock first: read second, it has moved on and an awake Mac reports a
    # few hundred nanoseconds of negative sleep (macOS CI, 2026-11-22). Clamp what is left.
    absolute = libc.mach_absolute_time()
    continuous = libc.mach_continuous_time()
    return max(0, continuous - absolute) * scale


def sleep_windows(log_text: str) -> list[tuple[int, int]]:
    """Every (fell asleep, woke) pair of epochs in the text of ``pmset -g log``, oldest first.

    A wake that follows no sleep line and a sleep the log has no wake for yet are left out.
    """
    windows, asleep_from = [], None
    for line in log_text.splitlines():
        found = SLEEP_LINE.match(line)
        if not found:
            continue
        try:
            at = int(time.mktime(time.strptime(found.group(1), "%Y-%m-%d %H:%M:%S")))
        except ValueError:
            continue
        if found.group(3) == "Sleep":
            if asleep_from is None:
                asleep_from = at
        elif asleep_from is not None:
            windows.append((asleep_from, at))
            asleep_from = None
    return windows


def stopped_by_wake(payload: str) -> bool:
    """Whether a card's ``gave_up`` record says the attempt was ended from outside, the way a wake ends one.

    A timer that ran out, a claim taken back, a worker interrupted (exit 130) or lost: yes.
    A worker that ran out of steps, and anything this cannot read: no.
    """
    try:
        said = json.loads(payload or "")
    except ValueError:
        return False
    if not isinstance(said, dict):
        return False
    error = str(said.get("error") or "")
    if "budget exhausted" in error:
        return False
    outcome = said.get("trigger_outcome")
    if outcome == "crashed":
        return "code 130" in error or "worker lost" in error or "settled interrupted" in error
    return outcome in STOPPED_BY_WAKE


def stopped_cards(db_path: str, windows: list[tuple[int, int]] | None, now: int) -> list[tuple[str, int]]:
    """(card, the wake that stopped it) for every blocked card whose last attempt a wake ended.

    The card's newest record among gave_up, blocked, unblocked and completed has to be the
    ``gave_up`` itself: a card a person or its own worker blocked afterwards is theirs.
    With ``windows`` None the sleep log is not consulted: the answer is every card that
    MIGHT have been stopped by a wake (with 0 for the wake), a cheap first look.
    """
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=10)
    try:
        rows = conn.execute(
            "SELECT t.id, e.kind, e.payload, e.created_at FROM tasks t JOIN task_events e ON e.id = ("
            "  SELECT id FROM task_events WHERE task_id = t.id AND kind IN ('gave_up', 'blocked', 'unblocked', 'completed')"
            "  ORDER BY created_at DESC, id DESC LIMIT 1) "
            "WHERE t.status = 'blocked'"
        ).fetchall()
    finally:
        conn.close()
    found = []
    for task_id, kind, payload, at in rows:
        if kind != "gave_up" or not isinstance(at, (int, float)) or now - at > RECENT_SECONDS:
            continue
        if not stopped_by_wake(payload):
            continue
        if windows is None:
            found.append((task_id, 0))
            continue
        for fell_asleep, woke in windows:
            if woke - fell_asleep >= MIN_SLEEP_SECONDS and woke <= at <= woke + GRACE_SECONDS:
                found.append((task_id, woke))
                break
    return found


def recover(db_path: str, state_path: Path, *, now: int, windows: list[tuple[int, int]], lid_open: bool,
            unblock, apply: bool = False) -> dict:
    """Release the cards a wake stopped, when the Mac is open and has stayed awake.

    ``unblock(ids, reason)`` is the board's own command; it is called once, with every card
    to release. The count of releases per card is kept in a file of its own beside the
    state file, so a card is released at most MAX_RELEASES times.
    """
    result: dict = {"stopped": [], "released": [], "held": ""}
    stopped = stopped_cards(db_path, windows, now)
    result["stopped"] = [task_id for task_id, _ in stopped]
    if not stopped:
        return result
    if not lid_open:
        result["held"] = "the lid is closed"
        return result
    if windows and now - windows[-1][1] < SETTLE_SECONDS:
        result["held"] = "the Mac has only just woken"
        return result
    counts_path = state_path.with_name(state_path.stem + "-released.json")
    try:
        counts = json.loads(counts_path.read_text())
    except (OSError, ValueError):
        counts = {}
    if not isinstance(counts, dict):
        counts = {}
    due = [(task_id, woke) for task_id, woke in stopped if counts.get(task_id, 0) < MAX_RELEASES]
    if not due:
        result["held"] = f"each was already released {MAX_RELEASES} times"
        return result
    result["released"] = [task_id for task_id, _ in due]
    if apply:
        woke = time.strftime("%H:%M", time.localtime(max(at for _, at in due)))
        unblock(result["released"], f"Stopped when this Mac slept (it woke at {woke}); released by the sleep compensator.")
        for task_id in result["released"]:
            counts[task_id] = counts.get(task_id, 0) + 1
        counts_path.parent.mkdir(parents=True, exist_ok=True)
        counts_path.write_text(json.dumps(counts))
    return result


def lid_is_open() -> bool:
    """Whether the lid is open; a Mac with no lid counts as open."""
    out = subprocess.run(["/usr/sbin/ioreg", "-r", "-k", "AppleClamshellState", "-d", "4"],
                         capture_output=True, text=True, timeout=20).stdout
    return '"AppleClamshellState" = Yes' not in out


def load_state(path: Path) -> dict | None:
    try:
        state = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(state, dict) or state.get("version") != STATE_VERSION:
        return None
    return state


def compensate(db_path: str, state_path: Path, *, now: int | None = None,
               sleep_total: float | None = None, apply: bool = False,
               interval: int = 60, clock=time.time) -> dict:
    """Push running workers' active starts forward by the sleep since the last tick.

    The state file advances on every tick, with or without ``--apply``, so a
    dry run followed by an apply compensates the same sleep once, not twice.
    """
    now = int(clock()) if now is None else int(now)
    if sleep_total is None:
        sleep_total = slept_seconds()
    state = load_state(state_path)
    result: dict = {"sleep_delta": 0, "compensated": 0, "skipped_unreadable": 0, "reset": False}
    if state is not None:
        last_sleep = state.get("sleep_total", 0)
        last_wall = state.get("wall", 0)
        if sleep_total + 0.5 < last_sleep:
            result["reset"] = True            # the machine rebooted; start the ledger again
        elif now >= last_wall:
            delta = min(sleep_total - last_sleep, now - last_wall + interval)
            # Two readings of the clocks an instant apart differ by a hair on an awake Mac:
            # under a second is no sleep, and no reason to write to the board every minute.
            if delta >= 1:
                result["sleep_delta"] = round(delta, 3)
                result["compensated"], result["skipped_unreadable"] = _shift_runs(
                    db_path, last_wall, delta, apply)
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps({"version": STATE_VERSION, "wall": now, "sleep_total": sleep_total}))
    return result


def _shift_runs(db_path: str, before_wall: int, delta: float, apply: bool) -> tuple[int, int]:
    """Add ``delta`` to the active start of every running worker started before ``before_wall``.

    The dispatcher reads ``COALESCE(r.started_at, t.started_at)`` for both the
    runtime kill and the stale-claim reclaim, so one shift covers both.
    """
    conn = sqlite3.connect(db_path, timeout=10)
    try:
        conn.execute("PRAGMA busy_timeout=10000")
        rows = conn.execute(
            "SELECT t.id, r.id AS run_id, COALESCE(r.started_at, t.started_at) AS started "
            "FROM tasks t LEFT JOIN task_runs r ON r.id = t.current_run_id "
            "WHERE t.status = 'running' AND COALESCE(r.started_at, t.started_at) IS NOT NULL"
        ).fetchall()
        touched, skipped = 0, 0
        for task_id, run_id, started in rows:
            if not isinstance(started, (int, float)):
                skipped += 1          # a format _to_epoch might read; leave the dispatcher's fallback to it
                continue
            if started >= before_wall:
                continue              # started inside the sleep window; at most one interval under-compensated
            table, row_id = ("task_runs", run_id) if run_id else ("tasks", task_id)
            if apply:
                conn.execute(f"UPDATE {table} SET started_at = started_at + ? WHERE id = ?",
                             (delta, row_id))  # noqa: S608 - table comes from the branch above, never input
            touched += 1
        if apply:
            conn.commit()
    finally:
        conn.close()
    return touched, skipped


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--board", default="zenithflow", help="Board slug; its database lives under the Hermes home")
    p.add_argument("--hermes-home", type=Path, default=Path.home() / ".hermes")
    p.add_argument("--db", help="Board database path override, for tests")
    p.add_argument("--state", type=Path, help="State file; defaults to a file beside the board database")
    p.add_argument("--apply", action="store_true", help="Write the shift to the board; without it, report only")
    p.add_argument("--recover", action="store_true",
                   help="Also release cards whose one attempt a wake ended, once the lid is open (with --apply; else report)")
    p.add_argument("--hermes", type=Path, default=Path.home() / ".local/bin/hermes", help="The board's own command")
    a = p.parse_args(argv)
    if sys.platform != "darwin" and not a.db:
        p.error("This tool reads macOS sleep time; pass --db with an injected sleep total to test it elsewhere.")
    db = a.db or str(a.hermes_home.expanduser() / "kanban" / "boards" / a.board / "kanban.db")
    if not Path(db).exists():
        print(f"no board database at {db}", file=sys.stderr)
        return 1
    state = a.state or (Path(db).parent / "sleep-compensate-state.json")
    result = compensate(db, state, apply=a.apply)
    result["applied"] = a.apply
    if a.recover:
        now = int(time.time())
        # The sleep log is read (about a second) only when a blocked card might be waiting on it.
        if stopped_cards(db, None, now):
            log = subprocess.run(["/usr/bin/pmset", "-g", "log"], capture_output=True, text=True, timeout=60).stdout

            def unblock(ids, reason):
                subprocess.run([str(a.hermes), "kanban", "--board", a.board, "unblock", "--reason", reason, *ids],
                               capture_output=True, text=True, timeout=120, check=True)

            result["recover"] = recover(db, state, now=now, windows=sleep_windows(log), lid_open=lid_is_open(),
                                        unblock=unblock, apply=a.apply)
    result["at"] = time.strftime("%Y-%m-%d %H:%M:%S")
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
