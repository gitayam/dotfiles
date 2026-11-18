#!/usr/bin/env python3
"""Provision company Hermes Desktop roles and boards. Dry run unless --apply.

Run after setup_work_hermes.py on a company-only device. Uses native Hermes
profile/board commands, preserves existing state, and never restarts a gateway.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

from setup_work_hermes import hermes_config, write, install_issue_strategy, model_policy

ROLES = {
    'zf-planner': 'Plan company engineering work: inspect requirements and source, write bounded tasks and acceptance criteria. Do not implement source changes.',
    'zf-developer': 'Implement company engineering tasks in the assigned isolated workspace, using approved Claude Code launchers when useful. Run relevant tests and retain artifacts for review.',
    'zf-reviewer': 'Independently review company diffs and artifacts, run focused checks and report concrete findings. Do not edit implementation or accept unchecked worker claims.',
}


def command(hermes, args, apply, env):
    print(('RUN ' if apply else 'WOULD RUN ')+'hermes '+' '.join(args))
    if apply:
        result=subprocess.run([hermes,'--profile','default',*args],env=env,
                              capture_output=True,text=True,timeout=90)
        if result.returncode:
            raise RuntimeError('Native Hermes command failed; inspect the selected profile/board before retrying.')


def desktop_config(existing):
    cfg=dict(existing)
    cfg['webapp']={**cfg.get('webapp',{}),'enabled':True,'host':'127.0.0.1',
                   'port':9120,'public_url':''}
    cfg['gateway']={**cfg.get('gateway',{}),'multiplex_profiles':True}
    return cfg


def worker_config(existing,routes,workspace,default,auxiliary_models=None,delegation_model=None):
    cfg=hermes_config(existing,routes,workspace,default,company_roles=True,auxiliary_models=auxiliary_models,delegation_model=delegation_model)
    cfg['gateway']={**cfg.get('gateway',{}),'standalone':False}
    cfg.pop('webapp',None)
    cfg['agent'].setdefault('run_budget_seconds',900)
    cfg['agent'].setdefault('max_turns',16)
    # Native -q policy requires a separate approval for arbitrary Python cells.
    # Do not advertise that unavailable tool to unattended workers or widen policy.
    cfg['platform_toolsets']['cli']=[t for t in cfg['platform_toolsets']['cli'] if t!='code_execution']
    return cfg


def ui_readiness(previous, confirmed=False):
    """UI preferences are renderer-local; never infer them from backend toolsets."""
    return {'desktop_plugins': 'user-confirmed' if confirmed else previous.get('desktop_plugins','action-required'),
            'required_plugins':['Desktop: Kanban','Desktop: Bots'],
            'browser_plugins':'check-per-browser',
            'instruction':'Capabilities → Plugins: enable Desktop: Kanban and Desktop: Bots. Browser preferences are separate from Electron Desktop.'}


def main():
    import yaml
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--from-config',type=Path,required=True)
    parser.add_argument('--apply',action='store_true')
    parser.add_argument('--confirm-desktop-plugins',action='store_true',
                        help='Record that the user enabled Kanban and Bots in this Mac\'s Desktop; does not toggle UI settings')
    args=parser.parse_args()
    cfg=json.loads(args.from_config.expanduser().read_text())
    if cfg['scope']!='device':
        parser.error('Desktop roles belong on the company-only work Mac; use its SSH relay from personal devices.')
    role_models,auxiliary_models=model_policy(cfg)
    home=Path(cfg['hermes_home']);workspace=Path(cfg['workspace']);state=workspace/'.workstation'
    env=dict(os.environ,HERMES_HOME=str(home),PATH=str(Path(cfg['hermes']).parent)+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin')
    for key in ['HERMES_PROFILE','HERMES_PROFILE_NAME']:
        env.pop(key,None)
    registry=state/'desktop-profiles.json'
    owned=json.loads(registry.read_text()) if registry.exists() else []
    for name in ROLES:
        if (home/'profiles'/name).exists() and name not in owned:
            raise RuntimeError('An unmanaged specialist profile exists; reconcile it before provisioning.')
    # Record ownership intent first, so interrupted native creates can be reconciled.
    write(registry,json.dumps(sorted(set(owned)|set(ROLES)),indent=2)+'\n',args.apply)
    skill=(home/'skills/autonomous-ai-agents/company-coding-stack/SKILL.md').read_text()
    for name,role in ROLES.items():
        target=home/'profiles'/name
        if not target.exists():
            command(cfg['hermes'],['profile','create',name,'--no-credentials','--no-alias','--description',role],args.apply,env)
        config=target/'config.yaml'
        existing=yaml.safe_load(config.read_text()) if config.exists() else {}
        configured=worker_config(existing or {},cfg['routes'],workspace,
            role_models.get(name,cfg['default_model']),auxiliary_models,cfg.get('delegation_model'))
        write(config,yaml.safe_dump(configured,sort_keys=False),args.apply)
        soul=target/'SOUL.md';text=soul.read_text() if soul.exists() else ''
        marker='<!-- work-desktop-role -->'
        text=text.split(marker)[0].rstrip()+'\n\n'+marker+'\n'+role+f'''
Company workspace: {workspace}. Read WORKSTATION.md and the company-coding-stack
skill. Use only local Gemma, approved organization models or real Enterprise
Claude Code. AnyJev advises; Orca's company lane is read-only; Paperclip is a
separate company issue board. Reconcile existing issue/run IDs before retrying.
Preserve dirty work, independently verify artifacts and report actual checks.
Never publish, merge, deploy or send messages without task-specific authority.
Unattended roles use ordinary file/terminal tools under the current policy;
execute_code is not exposed because single-query mode requires separate approval.
Never wrap a denied operation in another tool to evade its guard.
'''
        write(soul,text,args.apply)
        write(target/'skills/autonomous-ai-agents/company-coding-stack/SKILL.md',skill,args.apply)
        install_issue_strategy(target/'skills/management/issue-strategy',args.apply,'hermes')
    root=home/'config.yaml'
    write(root,yaml.safe_dump(desktop_config(yaml.safe_load(root.read_text()) or {}),sort_keys=False),args.apply)
    # Board creation is native and leaves prior default-board tasks untouched.
    for slug,label in [('zenithflow','ZenithFlow'),('omnicore','OmniCore'),('omnicore-platform','OmniCore Platform')]:
        board=home/'kanban/boards'/slug
        if not board.exists():
            command(cfg['hermes'],['kanban','boards','create',slug,'--name',label],args.apply,env)
        repository=workspace/slug
        metadata=board/'board.json'
        current=json.loads(metadata.read_text()) if metadata.exists() else {}
        if slug!='zenithflow' and repository.is_dir() and not current.get('default_workdir'):
            command(cfg['hermes'],['kanban','boards','set-default-workdir',slug,str(repository)],args.apply,env)
    command(cfg['hermes'],['kanban','boards','switch','zenithflow'],args.apply,env)
    readiness=state/'desktop-readiness.json'
    previous=json.loads(readiness.read_text()) if readiness.exists() else {}
    ready=ui_readiness(previous,args.confirm_desktop_plugins)
    write(readiness,json.dumps(ready,indent=2)+'\n',args.apply)
    write(state/'DESKTOP-SETUP.md',f'''# Hermes Desktop readiness

Backend profiles: {', '.join(ROLES)}. Boards: ZenithFlow and the two company projects.

Desktop plugins: **{ready['desktop_plugins']}**. This is a user confirmation,
not an automated observation. In Hermes Desktop open **Capabilities → Plugins**
and enable **Desktop: Kanban** and **Desktop: Bots**. Kanban ships hidden by
default in Hermes 0.23.2. Enabling the agent's kanban tools does not enable this
Desktop pane. This CLI cannot toggle renderer-local preferences.

Select the local work-Mac connection; open Bots to find the three zf-* roles.
Open Kanban and choose ZenithFlow or the intended project board. Verify the
workspace/assignee before submitting work. Project boards use their repository's
default workdir; choose a project/worktree for edits.

The browser workspace has separate plugin preferences: repeat the switches for
each new browser profile/origin. Build it with `hermes webapp --build-only`, then
use `hermes webapp` for a private one-use sign-in. The listener is loopback-only
on port 9120. A new listener requires a safe gateway restart; a live-work refusal
means wait, not force. Native Desktop uses the running gateway directly.

After enabling the native Desktop switches, rerun setup_work_desktop.py with
`--from-config {args.from_config.expanduser()} --apply --confirm-desktop-plugins`.
This records the manual step; it never claims end-to-end task acceptance.
''',args.apply)
    print('DESKTOP PLUGINS: '+ready['desktop_plugins']+' — '+ready['instruction'])
    print('Roles and boards prepared. Build the Webapp, check active work, then restart the named gateway to enable its loopback listener.')


if __name__=='__main__':main()
