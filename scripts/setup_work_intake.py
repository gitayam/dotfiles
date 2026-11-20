#!/usr/bin/env python3
"""Install a macOS board intake that specifies Triage cards every minute. Dry run by default.

For a board whose root Hermes config has kanban.auto_decompose off: a Triage card
then stays in Triage until `specify` runs. --remove unloads and deletes this job.
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

LABEL='io.zenithflow.board-intake'
MARKER='Managed by dotfiles: company board intake'
SCOPE='Specifies Triage cards into one card each. Makes one auxiliary model call per Triage card. Does not dispatch, retry, decompose or restart anything.'


def intake_plist(state, hermes, board):
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,63}',board):raise ValueError('Invalid board slug.')
    log=str(Path(state).resolve()/'intake/board-intake.log')
    # No EnvironmentVariables: the launcher's own defaults select the device Hermes home.
    return {'Label':LABEL,'Comment':MARKER,
            'ProgramArguments':[str(hermes),'kanban','--board',board,'specify','--all','--author','intake'],
            'RunAtLoad':True,'StartInterval':60,'ProcessType':'Background',
            'LowPriorityIO':True,'StandardOutPath':log,'StandardErrorPath':log}


def check_owned(path):
    path=Path(path)
    if path.is_symlink():raise ValueError('Preserve an existing symlink; reconcile intake ownership first.')
    if path.exists() and plistlib.loads(path.read_bytes()).get('Comment')!=MARKER:
        raise ValueError('Preserve the unmanaged LaunchAgent; reconcile ownership first.')


def check_launcher(path):
    """Absolute, not resolved: a launcher can depend on the name it is started by."""
    path=Path(os.path.abspath(Path(path).expanduser()))
    if not path.is_file() or not os.access(path,os.X_OK):
        raise ValueError('The Hermes launcher is missing or not executable; pass --hermes.')
    return path


def decomposition_off(config):
    """True only when the root config plainly says `kanban.auto_decompose: false`.

    Read line by line, as report_work_board.py reads a scalar, so no YAML package is
    needed. Absent, quoted, repeated with another value or unreadable all count as on.
    """
    try:lines=Path(config).read_text().split('\n')
    except (OSError,UnicodeError):return False
    inside=False;indent=None;values=[]
    for line in lines:
        if not line.strip() or line.lstrip().startswith('#'):continue
        if not line.startswith((' ','\t')):
            inside=line.split(':')[0].strip()=='kanban';indent=None;continue
        if not inside:continue
        if indent is None:indent=len(line)-len(line.lstrip())
        match=re.match(r'^( +)auto_decompose:\s*(\S*)\s*(#.*)?$',line)
        if match and len(match.group(1))==indent:values.append(match.group(2))
    return bool(values) and all(value in {'false','False','FALSE'} for value in values)


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
    p.add_argument('--board',help='Board slug whose Triage cards are specified; required to install')
    p.add_argument('--hermes',type=Path,default=Path.home()/'.local/bin/hermes',help='Hermes launcher the job runs')
    p.add_argument('--hermes-home',type=Path,default=Path.home()/'.hermes',
                   help='Hermes home whose root config is checked; the job itself uses the launcher default')
    p.add_argument('--state',type=Path,default=Path.home()/'zenithflow/.workstation')
    p.add_argument('--remove',action='store_true',help='Unload the job and delete only its own plist')
    p.add_argument('--apply',action='store_true');a=p.parse_args(argv)
    if sys.platform!='darwin':p.error('This LaunchAgent is for macOS; run the specify sweep directly elsewhere.')
    if not a.remove and not a.board:p.error('--board is required to install the intake.')
    target=Path.home()/'Library/LaunchAgents'/f'{LABEL}.plist'
    domain='gui/'+str(os.getuid());service=domain+'/'+LABEL
    check_owned(target)
    if a.remove:
        loaded=run(['launchctl','print',service],capture_output=True).returncode==0
        removed=remove(target,a.apply,(lambda:run(['launchctl','bootout',service],check=True)) if loaded else None)
        print(json.dumps({'applied':a.apply,'removed':removed and a.apply,'plist_present':removed,'loaded_before':loaded,
                         'scope':'Unloads and deletes only the LaunchAgent this script installed. Cards, boards and Hermes are untouched.'}))
        return
    hermes=check_launcher(a.hermes)
    if not decomposition_off(a.hermes_home.expanduser()/'config.yaml'):
        # With decomposition on the dispatcher already handles Triage; a second intake would race it.
        raise ValueError('The root Hermes config does not set kanban.auto_decompose to false; set kanban_auto_decompose false in the private configuration and refresh first.')
    state=a.state.expanduser().resolve()
    if not state.is_dir():raise ValueError('The state folder does not exist; pass --state.')
    content=plistlib.dumps(intake_plist(state,hermes,a.board))
    changed=not target.exists() or target.read_bytes()!=content
    loaded=run(['launchctl','print',service],capture_output=True).returncode==0
    if loaded and changed:raise ValueError('The managed intake is loaded with different settings; run --remove --apply before updating.')
    if a.apply:(state/'intake').mkdir(mode=0o700,exist_ok=True)
    write(target,content,a.apply)
    if a.apply and not loaded:
        run(['launchctl','bootstrap',domain,str(target)],check=True)
    print(json.dumps({'applied':a.apply,'board':a.board,'interval_seconds':60,'log':str(state/'intake/board-intake.log'),
                     'scope':SCOPE}))


if __name__=='__main__':main()
