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

REPO = Path(__file__).resolve().parents[1]
NAMES = ['zf-claude','zf-z1','zf-z2','zf-local','zf-zq','zf-orca','zf-status','zf-decide',
         'hermes-zenithflow']
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
    cfg={'workspace':str(w),'scope':a.scope,'hermes_home':str(hh),'routes':routes,
         'default_model':a.default_model,
         'enterprise_org':a.enterprise_org,'claude_config_dir':str(claude_dir),
         'hermes':str(home/'.local/bin/hermes'),'claude':shutil.which('claude') or '/opt/homebrew/bin/claude',
         'orca':shutil.which('orca') or '/opt/homebrew/bin/orca',
         'decide_url':f'http://127.0.0.1:{a.decide_port}',
         'decide_key_file':str(state/'secrets/decide-api-key')}
    write(state/'config.json',json.dumps(cfg,indent=2)+'\n',a.apply)
    if a.scope=='device':
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
Paperclip must use the real Claude Code legacy runner and these approved routes;
heartbeats off, no self-assignment to Hermes, no automatic merges/deployments.
AnyJev is advisory; keep uncertain work visible for review.
'''
    write(hh/'skills/autonomous-ai-agents/company-coding-stack/SKILL.md',skill,a.apply)
    print('Configuration prepared. Services and authentication require independent live verification.')


if __name__=='__main__':main()
