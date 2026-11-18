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
NAMES = ['zf-claude','zf-server1','zf-server2','zf-z1','zf-z2','zf-local','zf-zq','zf-orca','zf-status','zf-decide',
         'zf-paperclip','hermes-zenithflow']
SLOTS = ['vision','compression','approval','review','mcp','title_generation',
         'memory_query_rewrite','tts_audio_tags','voice_chat','triage_specifier',
         'kanban_decomposer','profile_describer','goal_judge','group_router','curator',
         'monitor','background_review','moa_reference','moa_aggregator']
COMPANY_ROLES = {'zf-planner','zf-developer','zf-reviewer'}


def model_policy(cfg):
    """Validate explicit private assignments before any configuration is written."""
    delegated=cfg.get('delegation_model')
    if delegated is None:
        delegated='1' if cfg['routes']['1']['context']>=65536 else 'local'
    if not isinstance(delegated,str) or delegated not in {'local','1'} or cfg['routes'][delegated]['context']<65536:
        raise ValueError('Delegation requires an approved full-context route.')
    roles=cfg.get('role_models',{})
    auxiliary=cfg.get('auxiliary_models',{})
    for values,known in [(roles,COMPANY_ROLES),(auxiliary,set(SLOTS))]:
        if not isinstance(values,dict) or set(values)-known:
            raise ValueError('Unknown company model policy assignment.')
        for key in values.values():
            if not isinstance(key,str) or key not in {'local','1'} or cfg['routes'][key]['context']<65536:
                raise ValueError('Company Hermes assignments require an approved full-context route.')
    if auxiliary.get('vision','local')!='local':
        raise ValueError('Vision stays local until another served route is qualified.')
    return roles,auxiliary


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


def link(path,target,apply,backup_dir=None):
    if path.is_symlink() and path.resolve()==target:
        return
    print(('LINK ' if apply else 'WOULD LINK ')+str(path))
    if not apply:return
    path.parent.mkdir(parents=True,exist_ok=True)
    if path.exists() or path.is_symlink():
        backup_dir=backup_dir or path.parent
        backup_dir.mkdir(parents=True,exist_ok=True)
        path.rename(backup_dir/(path.name+'.backup.'+datetime.datetime.now().strftime('%Y%m%d%H%M%S%f')))
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


def hermes_config(existing, routes, workspace, default='local', company_roles=False, auxiliary_models=None, delegation_model=None):
    cfg = dict(existing)
    _,auxiliary_models=model_policy({'routes':routes,'auxiliary_models':{} if auxiliary_models is None else auxiliary_models})
    provider = lambda key: {'1':'server1','2':'server2'}.get(key,key)
    if default not in {'local','1'} or routes[default]['context']<65536:
        raise ValueError('Hermes main routing requires an approved route with at least 64K context.')
    # Only these approved routes can carry a full Hermes session. z2 remains
    # available to bounded CLI tasks, but its 49,152-token window is too small.
    fallback=[{'provider':provider(key),'model':routes[key]['model']}
              for key in ['local','1'] if key!=default and routes[key]['context']>=65536]
    cfg['model'] = {'provider':provider(default),'default':routes[default]['model']}
    cfg['providers'] = {provider(key): {'name':provider(key),'base_url':r['url'],'api_key':'selfhosted',
        'api_mode':'chat_completions','model':r['model'],'request_timeout_seconds':120,
        'models':{r['model']:{'context_length':r['context'],'supports_vision':key=='local'}}}
        for key,r in routes.items()}
    for old,new in [('z1','server1'),('z2','server2')]:
        cfg['providers'][old]=dict(cfg['providers'][new],name=old)
    cfg.pop('fallback_model',None)
    cfg['fallback_providers'] = fallback
    cfg['model_aliases'] = {}
    aux = dict(cfg.get('auxiliary',{}))
    for slot in SLOTS:
        entry = dict(aux.get(slot,{}) if isinstance(aux.get(slot,{}),dict) else {})
        selected=auxiliary_models.get(slot,'local' if slot=='vision' else default)
        slot_fallback=[{'provider':provider(key),'model':routes[key]['model']}
                       for key in ['local','1'] if key!=selected and routes[key]['context']>=65536]
        entry.update({'provider':provider(selected),'model':routes[selected]['model'],
            'base_url':routes[selected]['url'],'api_key':'selfhosted',
            'api_mode':'chat_completions','fallback_chain':[] if slot=='vision' else slot_fallback})
        aux[slot] = entry
    cfg['auxiliary'] = aux
    for k in ['memory','skills']:
        cfg.setdefault(k,{})['write_approval'] = True
    cfg.setdefault('terminal',{}).update({'backend':'local','cwd':str(workspace)})
    cfg.setdefault('kanban',{}).update({'dispatch_interval_seconds':10,
        'auto_decompose':True,'max_in_progress':2,'max_in_progress_per_profile':1})
    if company_roles:
        cfg['kanban'].update({'default_assignee':'zf-developer','orchestrator_profile':'zf-planner'})
    cfg.setdefault('agent',{}).update({'api_max_retries':1,'auto_recovery_cycles':1,
        'tool_use_enforcement':True,'intent_ack_continuation':True})
    if delegation_model is None:
        delegation_model='1' if routes['1']['context']>=65536 else default
    if not isinstance(delegation_model,str) or delegation_model not in {'local','1'} or routes[delegation_model]['context']<65536:
        raise ValueError('Delegation requires an approved full-context route.')
    delegation=cfg.setdefault('delegation',{})
    delegation.update({'provider':provider(delegation_model),'model':routes[delegation_model]['model'],
        'fallback_providers':[{'provider':provider(k),'model':routes[k]['model']}
            for k in ['local','1'] if k!=delegation_model and routes[k]['context']>=65536]})
    for key,value in {'max_concurrent_children':3,'max_spawn_depth':1,'oneshot_max_children':6,
                      'max_iterations':12,'child_timeout_seconds':300,'worktree_isolation':True}.items():
        delegation.setdefault(key,value)
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


def existing_tailscale_cli(home, apply, executable=Path('/Applications/Tailscale.app/Contents/MacOS/Tailscale')):
    """Expose an existing native app's CLI without replacing another installation."""
    path=home/'.local/bin/tailscale'
    if executable.is_file() and not path.exists() and not path.is_symlink():
        link(path,executable,apply)


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
    saved={}
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
          ('1','Server1 GLM','glm-5.3-flash',262144,a.z1_port),
          ('2','Server2 gpt-oss','openai/gpt-oss-120b',49152,a.z2_port)]}
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
    for name in ['role_models','auxiliary_models','delegation_model']:
        if name in saved:cfg[name]=saved[name]
    _,auxiliary_models=model_policy(cfg)
    write(state/'config.json',json.dumps(cfg,indent=2)+'\n',a.apply)
    repair_paperclip_shim(Path(cfg['paperclip']),Path('/opt/homebrew/opt/node/bin/node'),a.apply)
    metadata=state/'paperclip.json'
    if metadata.exists():
        context=paperclip_context(json.loads(metadata.read_text()),paperclip_base)
        write(state/'paperclip-context.json',json.dumps(context,indent=2)+'\n',a.apply)
    else:
        print('INFO company Paperclip metadata not provisioned; zf-paperclip will refuse API commands.')
    if a.scope=='device':
        existing_tailscale_cli(home,a.apply)
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
    write(hp,yaml.safe_dump(hermes_config(existing or {},routes,w,a.default_model,
        company_roles=a.scope=='device',auxiliary_models=auxiliary_models,
        delegation_model=cfg.get('delegation_model')),sort_keys=False),a.apply)
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
`zf-local` (Gemma on the work Mac), `zf-server1` (GLM), `zf-server2` (gpt-oss),
`zf-claude` (real Enterprise Claude Code), `zf-zq local|server1|server2 "prompt"`,
`zf-status`, `zf-decide` (JSON on stdin), `zf-orca dispatch --agent claude`.
Use `ZF_MODEL=1|2|local` to choose the Orca model; the Claude adapter is read-only.
For edits call a Claude Code launcher directly with a bounded file/task contract
and check its diff and tests independently. Do not mistake a successful process
exit for a correct result. server2 serves 49,152 tokens and is unsuitable as the main
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
Paperclip invokes claude directly with its own stored environment. Pin the
self-hosted child model and CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 there separately
from work-ai; keep the engine, permissions and heartbeat policy. Preserve native
typed environment/secret bindings instead of storing redaction placeholders.
A task-scoped assigneeAdapterOverrides.adapterConfig.extraArgs grant can permit
Read/Edit for an exact owned file. It does not grant arbitrary repository writes.
Keep the native issue-disposition step executable. If the operator owns final
acceptance, reconcile all runs and queued continuations before closing the issue
and removing the temporary grant. Process success alone does not accept an edit.
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
real Claude Code CLI engine (adapterConfig.engine: cli) with approved model/tier
environment; do not rely on an unset engine's current default. There is no
community broker/ship service connected to this workstation.
An accepted read-only issue does not qualify Paperclip editing. Require a native
edit's actual file/tests; exit zero with denied tools is not acceptance. Use
only authorized owned-path Edit/Read selectors (absolute // paths), not
Write(path). Respect native execution-reconciliation guards and revoke temporary
grants; never reset state or duplicate an issue to evade them.
Named boards keep current tasks under ~/.hermes/kanban/boards/<board>/kanban.db;
the root kanban.db may be legacy. Inspect the intended board before counting
workers, and keep input/dependency/ownership holds separate from model failover.
AnyJev is advisory; keep uncertain work visible for review.
Hermes automatically falls back between eligible local Gemma and server1 routes on
provider failures; its delegated and text auxiliary calls have their own approved
chains. Vision stays on the verified local multimodal route. server2 is not a main
fallback. Use the real zf-claude CLI for Enterprise work, never its subscription
token in a generic inference client. A model-quality problem needs an independent
check and bounded escalation, not an invented confidence threshold.
Use actual profile names from the roster: zf-planner, zf-developer, zf-reviewer.
Before authorized worker execution, write its scope, isolated worktree, owned
paths, prohibited actions, acceptance commands and stop condition. Approvals
being off is not by itself a reason to hold authorized work indefinitely. A
written contract is not an OS sandbox. Respect explicit operator ownership and
real permission denials; reconcile the same run and artifacts before release or
retry. Model fallback never unblocks a card or transfers ownership.
For CTO-level issue/backlog analysis, load the issue-strategy skill. It produces
evidence-backed problem/option/priority recommendations, including non-code
interventions; analysis alone never assigns, closes or implements issues.
Private config role_models and auxiliary_models preserve explicit route
assignments across installer refreshes. Use dotfiles docs/company-model-policy.md
and scripts/probe_work_models.py to qualify a candidate policy with synthetic
evidence, then independently check bounded native tasks. Do not confuse direct
API probes with native adapter acceptance or HTTP 200 with applied reasoning
controls. Effort differs by model/template. Real zf-claude accepts --effort for a
session; inherited CLAUDE_CODE_* effort variables are scrubbed by the wrapper.
Keep AnyJev advice separate from deterministic context/modality/policy gates.
For roaming SSH read WORKSTATION.md and dotfiles docs/company-connectivity.md.
An existing Tailscale app may already belong to the company tailnet; check it
before installing another client or changing membership/routes. Native macOS
Remote Login over an approved transport preserves the existing SSH identity.
Bonjour names help only on the same LAN. A restricted outbound SSH bastion can
keep tailnets separate; it needs a verified endpoint and end-to-end host keys.
An SSH-only Cloudflare Access route can also preserve tailnets: exact operator
Service Auth policy, origin audience validation, native SSH pin, loopback SSH
only and a supervised connector. Keep operator and connector credentials in
separate private files, with expiry/revocation details in workstation inventory.
The connector needs outbound TCP 7844 and GUI login. Retain a LAN alias and
preserve active relay sessions. Verify a saved LuLu Always rule on the actual
binary with a fresh process; another program's TCP success is insufficient.
Qualify SSH nonce, denied Access/native-auth controls and connector restart
recovery. A same-LAN public-edge round trip is not different-network acceptance.
Server1/server2 are friendly server route names, not model families. Legacy z1/z2
providers, zf-z1/zf-z2 launchers and numeric 1/2 selectors remain compatibility
aliases. Read the served model/context; a host can run several models, including
models excluded by company policy or non-coding embedding/ASR services.
For independent investigation/review work, use native delegate_task with 2–3
concrete leaf tasks when it improves the task. State owned paths, inputs,
acceptance and stop conditions. Native Hermes agents can use tools directly;
Claude Code CLI is an optional harness, not a mandatory step or a cloud model.
Delegated children default to full-context Server1, with approved local fallback;
Server2 stays for bounded Claude Code/direct work below Hermes's context floor.
The company defaults allow 3 concurrent children, 6 total in a one-shot session,
one spawn level, 12 child iterations and a 300-second child deadline. Explicit
operator limits survive refresh. Keep subagent_auto_approve off. Use isolated
Git worktrees for parallel edits and integrate returned diffs deliberately;
worktree isolation is not a security sandbox and does not apply outside Git.
Current queued dir-workspace cards retain one Kanban writer per profile. Do not
raise shared-directory writer concurrency or change live task ownership merely
to increase the agent count. Read-only side tasks can run independently; verify
artifacts and actual native child sessions rather than reporting a planned fan-out.
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
            link(alias,codex_skill,a.apply,state/'backups')
        else:
            print('INFO existing Codex issue-strategy installation retained; company copy is under .workstation/skills/codex.')
    print('Configuration prepared. Services and authentication require independent live verification.')


if __name__=='__main__':main()
