#!/usr/bin/env python3
"""Install a read-only macOS company audit every five minutes. Dry run by default."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys

from setup_work_hermes import write

LABEL='io.zenithflow.agent-audit'
MARKER='Managed by dotfiles: read-only company agent audit'


def monitor_plist(state, script, python):
    state=Path(state).resolve()
    return {'Label':LABEL,'Comment':MARKER,
            'ProgramArguments':[str(python),str(Path(script).resolve()),'--state',str(state),
                                '--health','--board','zenithflow','--output',str(state/'monitor/paperclip-latest.json')],
            'RunAtLoad':True,'StartInterval':300,'ProcessType':'Background',
            'LowPriorityIO':True,'StandardOutPath':'/dev/null','StandardErrorPath':'/dev/null'}


def check_owned(path):
    path=Path(path)
    if path.is_symlink():raise ValueError('Preserve an existing symlink; reconcile monitor ownership first.')
    if path.exists() and plistlib.loads(path.read_bytes()).get('Comment')!=MARKER:
        raise ValueError('Preserve the unmanaged LaunchAgent; reconcile ownership first.')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--state',type=Path,default=Path.home()/'zenithflow/.workstation')
    p.add_argument('--apply',action='store_true');a=p.parse_args()
    if sys.platform!='darwin':p.error('This LaunchAgent is for macOS; run the audit directly elsewhere.')
    state=a.state.expanduser().resolve()
    reg=json.loads((state/'paperclip-hermes.json').read_text())
    if reg.get('scope')!='device':raise ValueError('Install on the enrolled work Mac, not the personal relay.')
    script=Path(__file__).with_name('audit_work_paperclip.py')
    target=Path.home()/'Library/LaunchAgents'/f'{LABEL}.plist'
    check_owned(target)
    content=plistlib.dumps(monitor_plist(state,script,sys.executable))
    changed=not target.exists() or target.read_bytes()!=content
    domain='gui/'+str(os.getuid());loaded=subprocess.run(['launchctl','print',domain+'/'+LABEL],capture_output=True).returncode==0
    if loaded and changed:raise ValueError('The managed monitor is loaded with different settings; stop only that monitor before updating.')
    write(target,content,a.apply)
    if a.apply and not loaded:
        subprocess.run(['launchctl','bootstrap',domain,str(target)],check=True)
    print(json.dumps({'applied':a.apply,'interval_seconds':300,'report':str(state/'monitor/paperclip-latest.json'),
                     'scope':'Read-only configuration, service, backup and primary-board counts. No release polling, models, task dispatch, recovery or restarts.'}))


if __name__=='__main__':main()
