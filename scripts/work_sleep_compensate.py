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
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import time
from pathlib import Path

STATE_VERSION = 1


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
            if delta > 0:
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
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
