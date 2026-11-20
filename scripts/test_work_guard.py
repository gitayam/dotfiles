#!/usr/bin/env python3
"""Tests for the raw-card guard: selection rules and the park actions."""
import json
import sys
import unittest
import unittest.mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from guard_raw_cards import MARKER, targets

NOW = 1_800_000_000
MINUTE = 60


def task(ident, status='running', created_by='dashboard', created_minutes_ago=1, body='Goal: do a thing'):
    return {'id': ident, 'status': status, 'created_by': created_by,
            'created_at': NOW - created_minutes_ago * MINUTE, 'body': body}


class Selection(unittest.TestCase):
    def test_a_fresh_raw_dashboard_card_is_selected_whatever_its_queue_state(self):
        for status in ('ready', 'running'):
            self.assertEqual(list(targets([task('t_1', status)], NOW, 10)), [('t_1', status)])

    def test_a_card_with_a_contract_is_never_selected(self):
        self.assertEqual(list(targets([task('t_1', body=MARKER + '. Follow it.')], NOW, 10)), [])

    def test_nothing_but_a_raw_dashboard_card_is_selected(self):
        board = [task('t_1', created_by='claude-operator'), task('t_2', created_by='dashboard'),
                 task('t_3', created_by='dashboard', body=MARKER), task('t_4', created_by='dashboard', status='done'),
                 task('t_5', created_by='dashboard', status='blocked')]
        self.assertEqual(list(targets(board, NOW, 10)), [('t_2', 'running')])

    def test_a_card_older_than_the_limit_is_left_alone(self):
        self.assertEqual(list(targets([task('t_1', created_minutes_ago=11)], NOW, 10)), [])
        self.assertEqual(list(targets([task('t_1', created_minutes_ago=9.5)], NOW, 10)), [('t_1', 'running')])

    def test_a_broken_or_missing_created_at_is_ignored(self):
        broken = task('t_1')
        broken['created_at'] = None
        self.assertEqual(list(targets([broken], NOW, 10)), [])


class Actions(unittest.TestCase):
    def guard_main(self, apply_flag, listing):
        import guard_raw_cards
        with unittest.mock.patch('guard_raw_cards.run') as run:
            run.return_value = listing
            with unittest.mock.patch.object(guard_raw_cards.datetime, 'datetime') as clock:
                clock.now.return_value.timestamp.return_value = NOW
                clock.timezone = guard_raw_cards.datetime.timezone
                argv = ['guard_raw_cards.py', '--board', 'b'] + (['--apply'] if apply_flag else [])
                with unittest.mock.patch('sys.argv', argv):
                    guard_raw_cards.main()
            return [call.args[0] for call in run.call_args_list]

    def test_dry_run_reports_and_runs_nothing(self):
        commands = self.guard_main(False, json.dumps([task('t_1')]))
        self.assertEqual([c for c in commands if 'list' not in c], [])

    def test_a_running_card_is_reclaimed_before_it_is_blocked(self):
        commands = self.guard_main(True, json.dumps([task('t_1')]))
        reclaims = [c for c in commands if 'reclaim' in c]
        blocks = [c for c in commands if 'block' in c]
        self.assertEqual([c[-2:] for c in reclaims], [['reclaim', 't_1']])
        self.assertEqual(len(blocks), 1)
        self.assertIn('--kind', blocks[0])
        self.assertLess(commands.index(reclaims[0]), commands.index(blocks[0]))

    def test_no_cards_means_only_the_listing_call(self):
        commands = self.guard_main(True, json.dumps([]))
        self.assertEqual(len(commands), 1)
        self.assertIn('list', commands[0])


if __name__ == '__main__':
    unittest.main()
