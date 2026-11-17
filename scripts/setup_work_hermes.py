#!/usr/bin/env python3
"""Configure an isolated company Hermes workspace. Dry run unless --apply.

Requires PyYAML: uv run --with pyyaml python scripts/setup_work_hermes.py --help
Existing files are backed up when changed. No credentials or personal memories
are copied, no packages installed, and no services restarted by this script.
"""
import argparse
import datetime
import json
from pathlib import Path
import shutil
import re
import stat

REPO = Path(__file__).resolve().parents[1]
NAMES = ['zf-claude','zf-z1','zf-z2','zf-local','zf-zq','zf-orca','zf-status','zf-decide',
         'zf-paperclip','hermes-zenithflow']
SLOTS = ['vision','compression','approval','review','mcp','title_generation',
         'memory_query_rewrite','tts_audio_tags','voice_chat','triage_specifier',
         'kanban_decomposer','profile_describer','goal_judge','group_router','curator',
         'monitor','background_review','moa_reference','moa_aggregator']


def write(path, content, apply, mode=0o600):
    content = content.encode() if isinstance(content,str) else content
    if path.exists() and path.read_bytes() == content:
        if apply:
            path.chmod(mode)
        return
    print(('WRITE ' if apply else 'WOULD WRITE ')+str(path))
    if not apply:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() or path.is_symlink():
        backup = path.with_name(path.name+'.backup.'+datetime.datetime.now().strftime('%Y%m%d%H%M%S%f'))
        if path.is_symlink():
            path.rename(backup)
        else:
            shutil.copy2(path, backup)
    tmp = path.with_name(path.name+'.work-ai.tmp')
    tmp.write_bytes(content)
    tmp.chmod(mode)
    tmp.replace(path)


def link(path,target,apply):
    if path.is_symlink() and path.resolve()==target:
        return
    print(('LINK ' if apply else 'WOULD LINK ')+str(path))
    if not apply:return
    path.parent.mkdir(parents=True,exist_ok=True)
    if path.exists() or path.is_symlink():
        path.rename(path.with_name(path.name+'.backup.'+datetime.datetime.now().strftime('%Y%m%d%H%M%S%f')))
    path.symlink_to(target)


def install_issue_strategy(target,apply,platform='generic'):
    source=REPO/'shared/skills/issue-strategy'
    if platform not in {'generic','claude-code','hermes','codex'}:
        raise ValueError('Unknown issue strategy adapter.')
    if not (source/'SKILL.md').is_file():
        raise FileNotFoundError('Issue strategy source is missing; use the complete dotfiles checkout.')
    entry=source/'SKILL.md' if platform=='generic' else source/'adapters'/(platform+'.md')
    for path in sorted(source.rglob('*')):
        if path.is_file() and path.suffix in {'.md','.py'} and '__pycache__' not in path.parts:
            relative=path.relative_to(source)
            if relative.parts[0]=='adapters':continue
            content=entry.read_bytes() if relative==Path('SKILL.md') else path.read_bytes()
            write(target/relative,content,apply,0o700 if relative.parts[0]=='scripts' else 0o600)


def hermes_config(existing, routes, workspace, default='local'):
    cfg = dict(existing)
    provider = lambda key: {'1':'z1','2':'z2'}.get(key,key)
    cfg['model'] = {'provider':provider(default),'default':routes[default]['model']}
    cfg['providers'] = {provider(key): {'name':provider(key),'base_url':r['url'],'api_key':'selfhosted',
        'api_mode':'chat_completions','model':r['model'],
        'models':{r['model']:{'context_length':r['context'],'supports_vision':key!='2'}}}
        for key,r in routes.items()}
    cfg['fallback_model'] = []
    cfg['fallback_providers'] = []
    cfg['model_aliases'] = {}
    aux = dict(cfg.get('auxiliary',{}))
    for slot in SLOTS:
        entry = dict(aux.get(slot,{}) if isinstance(aux.get(slot,{}),dict) else {})
        entry.update({'provider':provider(default),'model':routes[default]['model'],
            'base_url':routes[default]['url'],'api_key':'selfhosted',
            'api_mode':'chat_completions','fallback_chain':[]})
        aux[slot] = entry
    cfg['auxiliary'] = aux
    for k in ['memory','skills']:
        cfg.setdefault(k,{})['write_approval'] = True
    cfg.setdefault('terminal',{}).update({'backend':'local','cwd':str(workspace)})
    cfg.setdefault('kanban',{}).update({'dispatch_interval_seconds':10,
        'auto_decompose':True,'max_in_progress':2,'max_in_progress_per_profile':1})
    cfg.setdefault('delegation',{}).update({'provider':provider(default),'model':routes[default]['model']})
    # Model-backed media tools may route to cloud providers independently of auxiliary.*.
    tools=['browser','clarify','code_execution','computer_use','delegation','file',
           'kanban','memory','session_search','skills','terminal','todo','vision','web']
    cfg.setdefault('platform_toolsets',{})['cli'] = tools
    return cfg


def paperclip_context(metadata, api_base):
    """Paperclip 2026.1106 context v2; no API key is stored in the workspace context."""
    from uuid import UUID
    company=str(UUID(metadata['company_id']))
    return {'version':2,'currentProfile':'company','profiles':{
        'default':{},'company':{'apiBase':api_base,'companyId':company,'persona':'board'}}}


def company_shell_text(existing):
    """Put managed launchers after shell/package-manager PATH initialization."""
    start='# >>> company managed launchers >>>'
    end='# <<< company managed launchers <<<'
    existing=re.sub(re.escape(start)+r'.*?'+re.escape(end)+r'\n?', '', existing, flags=re.S)
    return existing.rstrip()+f'\n\n{start}\nexport PATH="$HOME/.local/bin:$PATH"\n{end}\n'


def repair_paperclip_shim(path, stable_node, apply):
    """Keep an existing managed CLI payload; repair only its Homebrew Node pin."""
    if path.is_symlink() or not path.is_file() or not stable_node.is_file():return
    raw=path.read_bytes()
    if not raw.startswith((b'#!/bin/sh',b'#!/bin/bash')):return
    text=raw.decode()
    fixed=re.sub(r'/opt/homebrew/Cellar/node/[^/\s\"\x27]+/bin/node',str(stable_node),text)
    if fixed!=text:write(path,fixed,apply,stat.S_IMODE(path.stat().st_mode))


def main():
    import yaml
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--workspace',type=Path,default=Path.home()/'zenithflow')
    p.add_argument('--from-config',type=Path,help='Refresh an existing private workstation config')
    p.add_argument('--hermes-home',type=Path)
    p.add_argument('--scope',choices=['workspace','device'],default='workspace')
    p.add_argument('--enterprise-org')
    p.add_argument('--z1-port',type=int,default=8001)
    p.add_argument('--z2-port',type=int,default=8002)
    p.add_argument('--local-port',type=int,default=8080)
    p.add_argument('--decide-port',type=int,default=8137)
    p.add_argument('--paperclip-port',type=int,help='3100 on work Mac; 13100 for personal-Mac relay')
    p.add_argument('--default-model',choices=['local','1'],default='local')
    p.add_argument('--local-context',type=int,default=131072)
    p.add_argument('--apply',action='store_true')
    a=p.parse_args()
    if a.from_config:
        saved=json.loads(a.from_config.expanduser().read_text())
        a.workspace=Path(saved['workspace']);a.hermes_home=Path(saved['hermes_home'])
        a.scope=saved['scope'];a.enterprise_org=saved['enterprise_org']
        a.default_model=saved.get('default_model','local')
        for key,attr in [('1','z1_port'),('2','z2_port'),('local','local_port')]:
            from urllib.parse import urlsplit
            setattr(a,attr,urlsplit(saved['routes'][key]['url']).port)
        a.local_context=saved['routes']['local']['context']
        a.decide_port=urlsplit(saved['decide_url']).port
        a.paperclip_port=urlsplit(saved['paperclip_api_base']).port if saved.get('paperclip_api_base') else a.paperclip_port
    if not a.hermes_home or not a.enterprise_org:
        p.error('--hermes-home and --enterprise-org are required unless --from-config is used')
    w=a.workspace.expanduser().resolve();state=w/'.workstation'
    if a.apply:
        state.mkdir(parents=True,exist_ok=True)
        state.chmod(0o700)
    hh=a.hermes_home.expanduser().resolve();home=Path.home()
    routes={key:dict(name=name,model=model,context=context,url=f'http://127.0.0.1:{port}/v1')
        for key,name,model,context,port in [
          ('local','Work Mac Gemma','gemma-4-26b-a4b',a.local_context,a.local_port),
          ('1','z1 GLM','glm-5.3-flash',262144,a.z1_port),
          ('2','z2 gpt-oss','openai/gpt-oss-120b',49152,a.z2_port)]}
    claude_dir=home/'.claude' if a.scope=='device' else state/'claude-enterprise'
    paperclip_port=a.paperclip_port or (3100 if a.scope=='device' else 13100)
    paperclip_base=f'http://127.0.0.1:{paperclip_port}'
    cfg={'workspace':str(w),'scope':a.scope,'hermes_home':str(hh),'routes':routes,
         'default_model':a.default_model,
         'enterprise_org':a.enterprise_org,'claude_config_dir':str(claude_dir),
         'hermes':str(home/'.local/bin/hermes'),'claude':shutil.which('claude') or '/opt/homebrew/bin/claude',
         'orca':shutil.which('orca') or '/opt/homebrew/bin/orca',
         'paperclip':shutil.which('paperclipai') or str(home/'.local/bin/paperclipai'),
         'paperclip_api_base':paperclip_base,'paperclip_context':str(state/'paperclip-context.json'),
         'decide_url':f'http://127.0.0.1:{a.decide_port}',
         'decide_key_file':str(state/'secrets/decide-api-key')}
    write(state/'config.json',json.dumps(cfg,indent=2)+'\n',a.apply)
    repair_paperclip_shim(Path(cfg['paperclip']),Path('/opt/homebrew/opt/node/bin/node'),a.apply)
    metadata=state/'paperclip.json'
    if metadata.exists():
        context=paperclip_context(json.loads(metadata.read_text()),paperclip_base)
        write(state/'paperclip-context.json',json.dumps(context,indent=2)+'\n',a.apply)
    else:
        print('INFO company Paperclip metadata not provisioned; zf-paperclip will refuse API commands.')
    if a.scope=='device':
        shell=home/'.zshrc'
        if shell.is_symlink():
            print('ACTION REQUIRED: put ~/.local/bin first after all PATH initialization in the source of .zshrc; symlink preserved.')
        else:
            write(shell,company_shell_text(shell.read_text() if shell.exists() else ''),a.apply)
        registry=[]
        for line in (REPO/'shared/llm/models.conf').read_text().splitlines():
            fields=line.split()
            if fields and fields[0].split(',')[0] in {'1','2'}:
                key=fields[0].split(',')[0]
                from urllib.parse import urlsplit
                fields[4]=str(urlsplit(routes[key]['url']).port)
                registry.append(' '.join(fields))
        if len(registry)!=2:
            raise ValueError('Both organization registry rows are required')
        write(home/'.config/ai-policy/device-models.conf','\n'.join(registry)+'\n',a.apply)
        for name in ['claude-z','zq']:
            target=state/'bin'/name
            write(target,(REPO/'shared/bin'/name).read_bytes(),a.apply,0o700)
            link(home/'.local/bin'/name,target,a.apply)
        for name in ['z1','z2']:
            link(home/'.local/bin'/name,state/'bin/claude-z',a.apply)
    write(state/'bin/work-ai',(REPO/'shared/bin/work-ai').read_bytes(),a.apply,0o700)
    for directory in [state/'bin',home/'.local/bin']:
        for name in NAMES:
            dst=directory/name; target=state/'bin/work-ai'
            link(dst,target,a.apply)
    hp=hh/'config.yaml'; existing=yaml.safe_load(hp.read_text()) if hp.exists() else {}
    write(hp,yaml.safe_dump(hermes_config(existing or {},routes,w,a.default_model),sort_keys=False),a.apply)
    # Scope the hook on the personal Mac; the work Mac permits approved routes in every directory.
    hook={'type':'command','command':str(state/'bin/work-ai')+' hook'}
    for cd in {home/'.claude',claude_dir}:
        f=cd/'settings.json';settings=json.loads(f.read_text()) if f.exists() else {}
        entries=settings.setdefault('hooks',{}).setdefault('UserPromptSubmit',[])
        if not any(hook in e.get('hooks',[]) for e in entries):entries.append({'hooks':[hook]})
        if cd==claude_dir:
            settings.update({'forceLoginMethod':'claudeai','forceLoginOrgUUID':a.enterprise_org})
        write(f,json.dumps(settings,indent=2)+'\n',a.apply)
    soul=hh/'SOUL.md'
    text=soul.read_text() if soul.exists() else '# Company coding coordinator\n'
    marker='<!-- work-ai-policy -->'
    text=text.split(marker)[0].rstrip()+'\n\n'+marker+f'''
Company workspace: {w}. Personal repositories: ~/Git. Read WORKSTATION.md and
the selected repository's instructions before working. Approved inference:
the Work Mac's local Gemma, organization z1/z2, and real Claude Code signed into
the company Enterprise organization. Use the company launchers in
{state}/bin. Do not use personal cloud keys, subscription OAuth in Hermes,
Pangolin, Alibaba/Qwen, Lumo, or unapproved model fallbacks for company work.
AnyJev at loopback is advisory routing, never authority to close cards or merge.
Retain memory and skill write approvals. Preserve dirty work; verify artifacts
and tests independently. Do not send communications unless specifically asked.
'''
    write(soul,text,a.apply)
    skill=f'''---
name: company-coding-stack
description: Run company coding work through approved local models or Enterprise Claude Code.
---

Use absolute launchers under `{state}/bin` (desktop PATH is minimal):
`zf-local` (Gemma on the work Mac), `zf-z1` (GLM), `zf-z2` (gpt-oss),
`zf-claude` (real Enterprise Claude Code), `zf-zq local|1|2 "prompt"`,
`zf-status`, `zf-decide` (JSON on stdin), `zf-orca dispatch --agent claude`.
Use `ZF_MODEL=1|2|local` to choose the Orca model; the Claude adapter is read-only.
For edits call a Claude Code launcher directly with a bounded file/task contract
and check its diff and tests independently. Do not mistake a successful process
exit for a correct result. z2 serves 49,152 tokens and is unsuitable as the main
Hermes agent (64K floor); it is usable for bounded direct/Claude Code tasks.
Start company work in `{w}`, personal work in `~/Git`. Do not copy personal
credentials, histories or memories into company repositories. Keep workspace
documentation and workstation state outside the sibling repositories.
For Desktop setup read `{state}/DESKTOP-SETUP.md` when present. Company-only
device roles are zf-planner, zf-developer and zf-reviewer; the work Mac's host
gateway serves them. Native Desktop requires Capabilities → Plugins → Desktop:
Kanban and Desktop: Bots enabled. Backend kanban tools do not enable the pane;
browser preferences are separate. A user-confirmed setup flag is not automated
UI verification. Preserve live work if the gateway refuses a listener restart.
Paperclip is a separate company issue/agent/project board, not a mirror of Hermes
Kanban. Use `{state}/bin/zf-paperclip agent list --json`,
`{state}/bin/zf-paperclip project list --json`, or
`{state}/bin/zf-paperclip issue get <identifier> --json`.
The private context pins the company and server; do not use an unscoped default
client or copy another machine's agent IDs. Read WORKSTATION.md for current IDs.
For requested tracked work, create ONE issue with an explicit approved Claude
agent and project, then inspect that same issue and its runs. A comment can wake
the assignee: do not also invoke a heartbeat or create a duplicate. Reconcile
unknown writes first. On auth/permission errors stop and report; never mint or
forge a token. Heartbeats stay off. Never assign Hermes to call itself.
Use `{state}/bin/zf-orca dispatch --agent claude --cwd <scratch> "<question>"`
for bounded read-only lanes; `inspect <lane>` retrieves the result. This company
wrapper does not provide an Orca edit adapter or a Paperclip-to-Orca handoff.
Orca reports semanticOutcome unknown: independently check the answer/artifacts.
Its read-only adapter may refuse shell commands and files outside the selected
cwd. Supply a sanitized current-state inventory in the prompt, or perform those
checks separately; do not turn a denied check into a claim that software is
missing. Distinguish package installation channel from Enterprise account auth.
Git commits, review, CI and deployment remain separate authorized steps; neither
board nor lane completion grants permission to publish. Paperclip must use the
real Claude Code legacy runner with approved model/tier environment. There is no
community broker/ship service connected to this workstation.
AnyJev is advisory; keep uncertain work visible for review.
For CTO-level issue/backlog analysis, load the issue-strategy skill. It produces
evidence-backed problem/option/priority recommendations, including non-code
interventions; analysis alone never assigns, closes or implements issues.
'''
    write(hh/'skills/autonomous-ai-agents/company-coding-stack/SKILL.md',skill,a.apply)
    install_issue_strategy(hh/'skills/management/issue-strategy',a.apply,'hermes')
    install_issue_strategy(w/'.claude/skills/issue-strategy',a.apply,'claude-code')
    install_issue_strategy(claude_dir/'skills/issue-strategy',a.apply,'claude-code')
    if a.scope=='workspace':
        codex_skill=state/'skills/codex/issue-strategy'
        install_issue_strategy(codex_skill,a.apply,'codex')
        alias=home/'.codex/skills/issue-strategy'
        old_target=w/'.claude/skills/issue-strategy'
        if (not alias.exists() and not alias.is_symlink()) or (alias.is_symlink() and alias.resolve() in {old_target,codex_skill}):
            link(alias,codex_skill,a.apply)
        else:
            print('INFO existing Codex issue-strategy installation retained; company copy is under .workstation/skills/codex.')
    print('Configuration prepared. Services and authentication require independent live verification.')


if __name__=='__main__':main()
