#!/usr/bin/env python3
"""Install a macOS LaunchAgent that keeps the board's run timers sleep-aware. Dry run by default.

Every minute it runs `work_sleep_compensate.py --apply`: when the Mac slept since
the previous tick, every running worker's active start is pushed forward by the
sleep (the dispatcher measures runtime and claim age from wall-clock epochs).
That alone does not carry a worker through a sleep of more than a few minutes:
its turn lease lapses and the dispatcher's pass on wake comes first. With
--recover the job also releases, once the lid is open and the Mac has stayed
awake, the cards whose one attempt a wake ended, through the board's own
unblock, at most three times a card. --remove unloads and deletes this job.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

from setup_work_hermes import write

LABEL='io.zenithflow.board-sleep-compensate'
MARKER='Managed by dotfiles: sleep-aware board run timers'
SCOPE='Every minute, shifts running workers\' active starts forward by the time the Mac slept, so sleep no longer counts against runtime limits or claim age. Writes only those two timer columns on running tasks. Does not dispatch, retry or restart anything.'
RECOVER_SCOPE=' With --recover it also releases cards whose one attempt a wake ended (a timer that billed the sleep, a claim taken back, a worker interrupted), through the board\'s own unblock: only with the lid open, only after the Mac has stayed awake, at most three times a card, never a card that ran out of steps or that a person or its worker blocked.'


def compensate_plist(state, board, recover=False, hermes=None):
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,63}',board):raise ValueError('Invalid board slug.')
    script=str(Path(state).resolve()/'bin/work_sleep_compensate.py')
    log=str(Path(state).resolve()/'sleep-compensate/compensate.log')
    extra=['--recover','--hermes',str(hermes or Path.home()/'.local/bin/hermes')] if recover else []
    return {'Label':LABEL,'Comment':MARKER,
            'ProgramArguments':[sys.executable,'-I',script,'--board',board,'--apply',*extra],
            'RunAtLoad':True,'StartInterval':60,'ProcessType':'Background',
            'LowPriorityIO':True,'StandardOutPath':log,'StandardErrorPath':log}


def check_owned(path):
    if path.exists() and plistlib.loads(path.read_bytes()).get('Comment')!=MARKER:
        raise ValueError('Preserve the unmanaged LaunchAgent; reconcile ownership first.')


def remove(path, apply, unload=None):
    """Delete only a plist this script wrote; unload it first. True when there was one."""
    path=Path(path);check_owned(path)
    if not path.exists():return False
    print(('REMOVE ' if apply else 'WOULD REMOVE ')+str(path))
    if apply:
        if unload:unload()
        path.unlink()
    return True


def main(argv=None, run=subprocess.run):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--board',default='zenithflow',help='Board whose database the job keeps sleep-aware')
    p.add_argument('--state',type=Path,default=Path.home()/'zenithflow/.workstation')
    p.add_argument('--remove',action='store_true',help='Unload the job and delete only its own plist')
    p.add_argument('--recover',action='store_true',help='Also release cards a wake stopped, once the lid is open (see the tool)')
    p.add_argument('--hermes',type=Path,default=Path.home()/'.local/bin/hermes',help='The board command the release uses')
    p.add_argument('--apply',action='store_true');a=p.parse_args(argv)
    if sys.platform!='darwin':p.error('This LaunchAgent is for macOS; run the compensator directly elsewhere.')
    target=Path.home()/'Library/LaunchAgents'/f'{LABEL}.plist'
    domain='gui/'+str(os.getuid());service=domain+'/'+LABEL
    check_owned(target)
    if a.remove:
        loaded=run(['launchctl','print',service],capture_output=True).returncode==0
        removed=remove(target,a.apply,(lambda:run(['launchctl','bootout',service],check=True)) if loaded else None)
        print(json.dumps({'applied':a.apply,'removed':removed and a.apply,'plist_present':removed,'loaded_before':loaded,
                         'scope':'Unloads and deletes only the LaunchAgent this script installed. Cards, boards and Hermes are untouched.'}))
        return
    state=a.state.expanduser().resolve()
    if not state.is_dir():raise ValueError('The state folder does not exist; pass --state.')
    if a.apply:
        (state/'bin').mkdir(mode=0o700,exist_ok=True)
        (state/'sleep-compensate').mkdir(mode=0o700,exist_ok=True)
    write(state/'bin/work_sleep_compensate.py',(Path(__file__).resolve().parent/'work_sleep_compensate.py').read_bytes(),a.apply,0o700)
    if a.recover and not a.hermes.expanduser().exists():raise ValueError('The board command was not found; pass --hermes.')
    content=plistlib.dumps(compensate_plist(state,a.board,a.recover,a.hermes.expanduser()))
    changed=not target.exists() or target.read_bytes()!=content
    loaded=run(['launchctl','print',service],capture_output=True).returncode==0
    if loaded and changed:raise ValueError('The managed compensator is loaded with different settings; run --remove --apply before updating.')
    write(target,content,a.apply)
    if a.apply and not loaded:
        run(['launchctl','bootstrap',domain,str(target)],check=True)
    print(json.dumps({'applied':a.apply,'board':a.board,'interval_seconds':60,'log':str(state/'sleep-compensate/compensate.log'),
                     'recover':a.recover,'scope':SCOPE+(RECOVER_SCOPE if a.recover else '')}))


if __name__=='__main__':main()
