"""Board intake LaunchAgent: plist content, refusals and removal. Never runs launchctl or hermes."""
import io
import json
from contextlib import redirect_stdout
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import setup_work_intake as intake
from setup_work_intake import intake_plist,check_owned,check_launcher,decomposition_off,remove,LABEL,MARKER


class Intake(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name).resolve()
        self.home=self.root/'home';self.state=self.root/'state';self.state.mkdir()
        # A launcher that fails if anything ever starts it.
        self.hermes=self.home/'.local/bin/hermes';self.hermes.parent.mkdir(parents=True)
        self.hermes.write_text('#!/bin/sh\nexit 97\n');self.hermes.chmod(0o700)
        self.config=self.home/'.hermes/config.yaml';self.config.parent.mkdir();self.decompose('false')
        self.target=self.home/'Library/LaunchAgents'/f'{LABEL}.plist';self.calls=[]
    def decompose(self,value):
        """A root config as the installer dumps it; another section's key must not count."""
        own='' if value is None else f'  auto_decompose: {value}\n'
        self.config.write_text('model:\n  default: synthetic\nkanban:\n  dispatch_interval_seconds: 10\n'+own+
                               '  max_in_progress: 2\n  nested:\n    auto_decompose: false\nagent:\n  auto_decompose: false\n')
    def main(self,*args,loaded=False):
        def run(argv,**kwargs):
            self.calls.append(argv[:2])
            return subprocess.CompletedProcess(argv,0 if loaded or argv[1]!='print' else 113)
        out=io.StringIO()
        with patch.object(Path,'home',return_value=self.home),patch.object(intake.sys,'platform','darwin'),redirect_stdout(out):
            intake.main(['--state',str(self.state),*args],run)
        return json.loads(out.getvalue().splitlines()[-1])
    def files(self):
        return sorted(str(p.relative_to(self.root)) for p in self.root.rglob('*') if not p.is_dir())
    def refused(self,pattern,*args):
        before=self.files();self.calls=[]
        with self.assertRaisesRegex(ValueError,pattern):self.main(*args)
        self.assertEqual(self.files(),before);self.assertFalse([c for c in self.calls if c[1]!='print'])

    def test_plist_runs_the_specify_sweep_and_the_guard_a_minute_with_a_log_and_no_environment(self):
        p=intake_plist(self.state,self.hermes,'work');log=str(self.state/'intake/board-intake.log')
        guard=str(self.state/'bin/guard_raw_cards.py')
        self.assertEqual(p,{'Label':'io.zenithflow.board-intake','Comment':MARKER,
            'ProgramArguments':['/bin/sh','-c',
                f'{self.hermes} kanban --board work specify --all --author intake; '
                f'{sys.executable} -I {guard} --board work --apply'],
            'RunAtLoad':True,'StartInterval':60,'ProcessType':'Background','LowPriorityIO':True,
            'StandardOutPath':log,'StandardErrorPath':log})
        self.assertEqual(plistlib.loads(plistlib.dumps(p)),p)
        for board in ['','--all','../work','Work','a b']:
            with self.assertRaises(ValueError):intake_plist(self.state,self.hermes,board)

    def test_refuses_unless_the_root_config_plainly_turns_decomposition_off(self):
        for value in ['false','False','false  # decided by the owner']:
            self.decompose(value);self.assertTrue(decomposition_off(self.config),value)
        for value in ['true',None,"'false'",'"false"','off','0','']:
            self.decompose(value);self.assertFalse(decomposition_off(self.config),value)
            self.refused('kanban.auto_decompose','--board','work','--apply')
        self.config.write_text('kanban:\n  auto_decompose: false\nkanban:\n  auto_decompose: true\n')
        self.assertFalse(decomposition_off(self.config))
        self.config.write_text('kanban: {auto_decompose: false}\n');self.assertFalse(decomposition_off(self.config))
        self.config.unlink();self.assertFalse(decomposition_off(self.config))
        self.refused('kanban.auto_decompose','--board','work','--apply')

    def test_refuses_an_unmanaged_plist_and_a_symlink(self):
        self.target.parent.mkdir(parents=True);self.target.write_bytes(plistlib.dumps({'Label':LABEL}))
        with self.assertRaises(ValueError):check_owned(self.target)
        for args in [['--board','work','--apply'],['--remove','--apply']]:
            self.refused('unmanaged LaunchAgent',*args)
        self.target.unlink();other=self.root/'other.plist';other.write_bytes(plistlib.dumps({'Comment':MARKER}))
        check_owned(other);self.target.symlink_to(other)
        with self.assertRaises(ValueError):check_owned(self.target)
        for args in [['--board','work','--apply'],['--remove','--apply']]:
            self.refused('existing symlink',*args)
        self.assertTrue(self.target.is_symlink());self.assertEqual(plistlib.loads(other.read_bytes()),{'Comment':MARKER})

    def test_refuses_a_missing_or_non_executable_launcher(self):
        self.assertEqual(check_launcher(self.hermes),self.hermes)
        self.hermes.chmod(0o600)
        with self.assertRaises(ValueError):check_launcher(self.hermes)
        self.refused('launcher is missing or not executable','--board','work','--apply')
        self.hermes.unlink()
        with self.assertRaises(ValueError):check_launcher(self.hermes)
        self.refused('launcher is missing or not executable','--board','work','--apply')
        self.refused('launcher is missing or not executable','--board','work','--hermes',str(self.root/'absent'),'--apply')

    def test_dry_run_writes_nothing_and_states_its_scope(self):
        before=self.files();report=self.main('--board','work')
        self.assertEqual(self.files(),before);self.assertFalse((self.state/'intake').exists())
        self.assertEqual(self.calls,[['launchctl','print']])
        self.assertEqual(report,{'applied':False,'board':'work','interval_seconds':60,
            'log':str(self.state/'intake/board-intake.log'),
            'scope':'Specifies Triage cards into one card each and parks raw dashboard cards before they burn their step budget. Makes one auxiliary model call per Triage card. Does not dispatch, retry, decompose or restart anything.'})
        with self.assertRaises(SystemExit),redirect_stdout(io.StringIO()),patch('sys.stderr',io.StringIO()):self.main()

    def test_apply_loads_once_and_never_changes_a_loaded_job(self):
        self.assertTrue(self.main('--board','work','--apply')['applied'])
        self.assertEqual(self.calls,[['launchctl','print'],['launchctl','bootstrap']])
        self.assertEqual(plistlib.loads(self.target.read_bytes()),intake_plist(self.state,self.hermes,'work'))
        self.assertTrue((self.state/'intake').is_dir())
        self.calls=[];self.main('--board','work','--apply',loaded=True)
        self.assertEqual(self.calls,[['launchctl','print']]);self.assertFalse(list(self.target.parent.glob('*.backup.*')))
        original=self.target.read_bytes()
        with self.assertRaisesRegex(ValueError,'loaded with different settings'):self.main('--board','other','--apply',loaded=True)
        self.assertEqual(self.target.read_bytes(),original)

    def test_remove_deletes_only_a_plist_carrying_the_marker(self):
        self.target.parent.mkdir(parents=True);self.assertFalse(remove(self.target,True))
        self.target.write_bytes(plistlib.dumps({'Label':LABEL,'Comment':'someone else'}));unloaded=[]
        with self.assertRaises(ValueError):remove(self.target,True,lambda:unloaded.append(1))
        self.assertTrue(self.target.exists());self.assertEqual(unloaded,[])
        self.target.write_bytes(plistlib.dumps(intake_plist(self.state,self.hermes,'work')))
        neighbour=self.target.with_name('io.example.other.plist');neighbour.write_bytes(plistlib.dumps({'Label':'other'}))
        with redirect_stdout(io.StringIO()):
            self.assertTrue(remove(self.target,False,lambda:unloaded.append(1)))
            self.assertTrue(self.target.exists());self.assertEqual(unloaded,[])
            self.assertTrue(remove(self.target,True,lambda:unloaded.append(self.target.exists())))
        self.assertEqual(unloaded,[True]);self.assertFalse(self.target.exists());self.assertTrue(neighbour.exists())
        self.target.write_bytes(plistlib.dumps(intake_plist(self.state,self.hermes,'work')))
        self.assertEqual(self.main('--remove')['removed'],False);self.assertTrue(self.target.exists())
        self.calls=[];report=self.main('--remove','--apply',loaded=True)
        self.assertEqual(self.calls,[['launchctl','print'],['launchctl','bootout']])
        self.assertTrue(report['removed']);self.assertFalse(self.target.exists());self.assertTrue(neighbour.exists())
        self.calls=[];self.assertFalse(self.main('--remove','--apply',loaded=True)['removed'])
        self.assertEqual(self.calls,[['launchctl','print']])


if __name__=='__main__':unittest.main()
