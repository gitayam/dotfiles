#!/usr/bin/env python3
"""Park raw dashboard cards before they burn their step budget. Dry run by default.

    guard_raw_cards.py --board zenithflow [--max-age-minutes 10] [--apply]

A request typed into the dashboard becomes a card with no work contract and
dispatches the moment it exists. A request that bundles research, a multi-file
build and verification cannot finish within any step budget, so it dies at the
ceiling twice, trips the circuit breaker and waits for a human anyway
(t_2e84dbe7 spent two 40-turn runs that way on 2026-11-20). This guard runs on
the same minute sweep as the triage specifier and parks such a card early:
a dashboard card younger than the age limit, still queued or running, whose body
carries no work contract, is reclaimed and blocked with a comment that names the
sizing rule and the way out. A card that finishes inside the sweep interval
escapes; a blocked card is never targeted twice; any card whose body carries the
contract marker is left alone. Nothing else is read, changed or dispatched.
"""
import argparse
import datetime
import json
import subprocess
import sys
from pathlib import Path

MARKER = 'WORK CONTRACT'
REASON = ('Unsized request parked by the intake guard: the body carries no work contract, and a card '
          'that bundles research, multi-file build and verification cannot finish within any step budget '
          '(a dashboard card on 2026-11-20 spent two 40-turn runs that way). Split it into a research card '
          'that writes a facts file and a bounded build card that reads it, or unblock this card to run it as-is.')


def run(argv):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise RuntimeError(f'{" ".join(argv)} failed: {result.stderr.strip()[:200]}')
    return result.stdout


def targets(tasks, now, max_age_minutes):
    for task in tasks:
        if task.get('created_by') != 'dashboard':
            continue
        if task.get('status') not in ('ready', 'running'):
            continue
        created = task.get('created_at') or 0
        if not isinstance(created, (int, float)) or (now - created) > max_age_minutes * 60:
            continue
        body = task.get('body') or ''
        if MARKER in body:
            continue
        yield task['id'], task.get('status')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--board', required=True)
    parser.add_argument('--hermes', default=str(Path.home() / '.local' / 'bin' / 'hermes'))
    parser.add_argument('--max-age-minutes', type=float, default=10.0)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    now = datetime.datetime.now(datetime.timezone.utc).timestamp()
    listing = run([args.hermes, 'kanban', '--board', args.board, 'list', '--json'])
    parsed = json.loads(listing)
    tasks = parsed if isinstance(parsed, list) else parsed.get('tasks', parsed.get('items', []))
    found = list(targets(tasks, now, args.max_age_minutes))
    for task_id, status in found:
        print(f'{"PARK" if args.apply else "WOULD PARK"} {task_id} ({status})')
        if not args.apply:
            continue
        if status == 'running':
            run([args.hermes, 'kanban', '--board', args.board, 'reclaim', task_id])
        run([args.hermes, 'kanban', '--board', args.board, 'block', task_id, '--kind', 'needs_input', REASON])
    if not found:
        print('no raw dashboard cards to park')
    return 0


if __name__ == '__main__':
    sys.exit(main())
