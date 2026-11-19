#!/usr/bin/env python3
"""Enroll the existing company Hermes profiles as a Paperclip pilot team.

Dry-run by default. Scheduled heartbeats remain off. New workers refuse general
work until a separate, recorded qualification; only named pilot issues can run.
No Hermes configuration, existing agent or service is modified.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import urllib.parse
import urllib.request
import uuid

from setup_work_hermes import write,link,company_skill
from work_paperclip_graph import locked

LABELS={'zf-planner':('Hermes Planner','cto'),'zf-developer':('Hermes Developer','engineer'),
        'zf-reviewer':('Hermes Reviewer','qa')}
MARKER='dotfiles-company-hermes-v1'
BASE_STAGE_SHA256='01a1133fa27dd98a1d2a6cfb16a58e8139ff4cf172be8ea2734f9c56f72da982'


def enroll_project(project_id,company_id,workspace,api,apply):
    uuid.UUID(project_id)
    project=api('/api/projects/'+project_id)
    if project.get('companyId')!=company_id:raise ValueError('The requested project belongs to another company.')
    sources=api('/api/projects/'+project_id+'/workspaces')
    source=next((w for w in sources if w.get('isPrimary') and w.get('cwd')),None)
    if not source or not Path(source['cwd']).resolve().is_relative_to(Path(workspace).resolve()):
        raise ValueError('The selected project needs a primary source inside the company workspace.')
    policy={**(project.get('executionWorkspacePolicy') or {}),'enabled':True,'sharedWorkspaceConcurrency':'serialize'}
    if apply and policy!=project.get('executionWorkspacePolicy'):
        updated=api('/api/projects/'+project_id,'PATCH',{'executionWorkspacePolicy':policy})
        if (updated.get('executionWorkspacePolicy') or {}).get('sharedWorkspaceConcurrency')!='serialize':
            raise ValueError('Project policy update is unresolved; reconcile before intake.')
    return {'project_id':project_id,'name':project['name'],'project_workspace_id':source['id'],
            'source':source['cwd'],'serialization':'serialize','applied':apply}


def validate_routing(cfg,c):
    aliases={'local':'local','server1':'1','z1':'1','server2':'2','z2':'2'}
    def check_entry(entry):
        p=entry.get('provider');k=aliases.get(p);m=entry.get('model') or entry.get('default')
        if p not in c.get('providers',{}):raise ValueError('A runtime provider definition is missing.')
        if k not in {'local','1'} or cfg['routes'][k]['context']<65536 or m!=cfg['routes'][k]['model']:
            raise ValueError('A runtime model-backed call is outside the approved full-context routes.')
        if entry.get('base_url',cfg['routes'][k]['url']).rstrip('/')!=cfg['routes'][k]['url'].rstrip('/'):
            raise ValueError('A runtime entry overrides its approved inference endpoint.')
        if entry.get('api_key','selfhosted')!='selfhosted':raise ValueError('A runtime entry contains unexpected credential settings.')
    for p,definition in c.get('providers',{}).items():
        k=aliases.get(p)
        if k is None or definition.get('base_url','').rstrip('/')!=cfg['routes'][k]['url'].rstrip('/'):
            raise ValueError('The actual Hermes provider endpoint differs from the approved route.')
        if definition.get('api_key')!='selfhosted':raise ValueError('The provider contains unexpected credential settings.')
    check_entry(c['model'])
    if c['model']['provider'] not in c['providers']:raise ValueError('The selected provider is missing.')
    for entry in c.get('fallback_providers',[]):check_entry(entry)
    delegated=c.get('delegation',{});check_entry(delegated)
    for entry in delegated.get('fallback_providers',[]):check_entry(entry)
    for entry in c.get('auxiliary',{}).values():
        check_entry(entry)
        for fallback in entry.get('fallback_chain',[]):check_entry(fallback)


def profile_snapshot(cfg, home):
    import yaml
    if cfg['scope']!='device':raise ValueError('Native Paperclip workers belong on the company work Mac.')
    parsed=urllib.parse.urlsplit(cfg['paperclip_api_base'])
    if parsed.scheme!='http' or parsed.hostname not in {'127.0.0.1','localhost','::1'} or parsed.username or parsed.password:
        raise ValueError('The company API must be the configured loopback service.')
    profiles={}
    for role in LABELS:
        path=Path(cfg['hermes_home'])/'profiles'/role/'config.yaml'
        c=yaml.safe_load(path.read_text());provider=c['model']['provider'];model=c['model']['default']
        validate_routing(cfg,c)
        key={'local':'local','server1':'1','z1':'1'}.get(provider)
        if key is None or cfg['routes'][key]['model']!=model or cfg['routes'][key]['context']<65536:
            raise ValueError('The role requires an already qualified full-context company route.')
        route=urllib.parse.urlsplit(cfg['routes'][key]['url'])
        if route.hostname not in {'127.0.0.1','localhost','::1'} or any(w in model.lower() for w in ['qwen','alibaba','lumo']):
            raise ValueError('Unapproved company inference route.')
        profiles[role]={'provider':provider,'model':model,'context':cfg['routes'][key]['context'],
            'max_turns':c.get('agent',{}).get('max_turns',16),
            'config_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'toolsets':[x for x in c['platform_toolsets']['cli'] if x not in {'kanban','code_execution'}],
            'agent_id':None}
    return profiles


def instructions(role,workspace):
    role_text={
        'zf-planner':'Complete only the registered graph phase: bounded planning, CTO-level analysis, or final approval. In final approval, verify completed children and independent acceptance; never start planning again. Analysis must not implement code or adopt owner policy. Fixed assignments replace handoffs.',
        'zf-developer':'Implement only the assigned bounded change in the Paperclip-owned workspace. Preserve tests, run relevant checks without exposing operator credentials, retain artifacts and finish for independent review.',
        'zf-reviewer':'Independently examine implementation or decision artifacts and actual acceptance evidence. Do not edit implementation. Use changes for a material defect; otherwise finish. A worker claim or exit zero is not evidence.'}[role]
    return f'''# Paperclip-owned Hermes work

{role_text}

Reuse your existing Hermes profile, memory and company-coding-stack skill.
Company workspace: {workspace}. Paperclip is the sole scheduler for this issue;
do not create a matching Hermes Kanban job or send this issue back to intake.
Use the run-scoped callback helper from the ephemeral system instructions.
Do not read credentials, print environment values or replace callbacks with an
unauthenticated/operator API client. Start/check out and inspect this issue, then
leave an evidence comment and its disposition through that helper in this run.
Paperclip owns parent/child dependencies and fixed role assignments. Never
handoff or self-reassign. A changes disposition blocks for coordinator rework;
do not bypass it or approve unchecked artifacts.
Timer heartbeats are off; task assignments drive work. Escalate missing owner
decisions as decisions, not inference failures. Never ship, merge, deploy or send
external communications without task-specific authority. A decision brief does
not authorize its recommendations. Keep writes within the task's owned paths.
'''


def payload(cfg,role,profiles,state,planner_id=None):
    name,title=LABELS[role]
    return {'name':name,'role':title,'runner':'legacy','adapterType':'hermes_local',
        'adapterConfig':{'hermesCommand':str(state/'bin/hermes-paperclip'),
            'model':'auto','provider':'auto','persistSession':False,'quiet':True,
            # Installed 2026.1106.0: select its actual tool-free hello test,
            # avoiding generic cloud-key/provider guesses for named profiles.
            # This is not an AI-account binding or a manufactured test result.
            'managedAiRouting':True,
            'maxTurnsPerRun':profiles[role]['max_turns'],'timeoutSec':900,'graceSec':15,
            'toolsets':','.join(profiles[role]['toolsets']),
            'paperclipApiUrl':cfg['paperclip_api_base'],
            'instructionsFilePath':str(state/'paperclip-instructions'/role/'AGENTS.md'),
            'instructionsBundleMode':'external',
            'env':{'ZF_HERMES_PROFILE':role,'HERMES_HOME':str(Path(cfg['hermes_home'])/'profiles'/role)}},
        'runtimeConfig':{'heartbeat':{'enabled':False,'wakeOnAssignment':True,'wakeOnOnDemand':True,'maxConcurrentRuns':1}},
        'permissions':{'canCreateAgents':False,'canCreateSkills':False},
        'metadata':{'managedBy':MARKER,'hermesProfile':role},
        'reportsTo':planner_id if role!='zf-planner' else None}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--from-config',type=Path,required=True)
    parser.add_argument('--apply',action='store_true')
    parser.add_argument('--project',action='append',default=[],help='Enroll this exact company project for serialized request graphs; repeat for another project.')
    args=parser.parse_args();cfg=json.loads(args.from_config.expanduser().read_text())
    state=Path(cfg['workspace'])/'.workstation';meta=json.loads((state/'paperclip.json').read_text())
    profiles=profile_snapshot(cfg,Path.home());base=cfg['paperclip_api_base'].rstrip('/')
    def api(path,method='GET',body=None):
        req=urllib.request.Request(base+path,json.dumps(body).encode() if body is not None else None,
                                   {'Content-Type':'application/json'},method=method)
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self,*args,**kwargs):return None
        with urllib.request.build_opener(NoRedirect).open(req,timeout=30) as response:return json.load(response)
    agents=api('/api/companies/'+meta['company_id']+'/agents');owned={}
    if args.project:
        live=api('/api/companies/'+meta['company_id']+'/live-runs')
        live=live.get('items',live) if isinstance(live,dict) else live
        if any(r['status'] in {'running','queued','scheduled_retry'} for r in live):
            raise ValueError('Preserve live company runs; enroll project policy after they finish.')
    for role,(name,_) in LABELS.items():
        matches=[a for a in agents if (a.get('metadata') or {}).get('managedBy')==MARKER and (a.get('metadata') or {}).get('hermesProfile')==role]
        if len(matches)>1:raise ValueError('Duplicate managed role; reconcile before creating work.')
        if matches:
            a=matches[0]
            if a['status'] not in {'idle','paused'}:raise ValueError('Preserve the active native worker; retry setup after it ends.')
            owned[role]=a;profiles[role]['agent_id']=a['id']
        elif any(a.get('name')==name for a in agents):raise ValueError('An unmanaged agent owns the requested role name.')
    registry_file=state/'paperclip-hermes.json'
    previous=json.loads(registry_file.read_text()) if registry_file.exists() else {}
    source=Path(__file__).parents[1]
    native=Path.home()/'.paperclip/cli/current/node_modules/@paperclipai/server/dist/routes/issues.js'
    contract={'runtime_sha256':hashlib.sha256((source/'shared/bin/work-paperclip').read_bytes()).hexdigest(),
              'intake_sha256':hashlib.sha256((source/'shared/bin/work-orchestrate').read_bytes()).hexdigest(),
              'graph_module_sha256':hashlib.sha256((source/'scripts/work_paperclip_graph.py').read_bytes()).hexdigest(),
              'native_stage_file':str(native),'native_stage_sha256':hashlib.sha256(native.read_bytes()).hexdigest()}
    registry={'scope':'device','state':str(state),'hermes_home':cfg['hermes_home'],'hermes':cfg['hermes'],
              'company_id':meta['company_id'],'api_base':base,'profiles':profiles,
              'contract':contract,
              'qualified':False,'pilot_issue_ids':previous.get('pilot_issue_ids',[]),
              'graph_tasks':previous.get('graph_tasks',{})}
    unchanged=all(previous.get('profiles',{}).get(k)==v for k,v in profiles.items()) and previous.get('contract')==contract
    if unchanged:registry['qualified']=previous.get('qualified',False)
    if contract['native_stage_sha256']!=BASE_STAGE_SHA256:
        registry['qualified']=False
        print('ACTION native scheduler differs from the graph qualification baseline; review and requalify before general intake.')
    write(state/'bin/work-paperclip',(Path(__file__).parents[1]/'shared/bin/work-paperclip').read_bytes(),args.apply,0o700)
    for name in ['hermes-paperclip','paperclip-run']:
        for directory in [state/'bin',Path.home()/'.local/bin']:link(directory/name,state/'bin/work-paperclip',args.apply)
    write(state/'bin/work-orchestrate',(Path(__file__).parents[1]/'shared/bin/work-orchestrate').read_bytes(),args.apply,0o700)
    write(state/'lib/work_paperclip_graph.py',(source/'scripts/work_paperclip_graph.py').read_bytes(),args.apply,0o600)
    for directory in [state/'bin',Path.home()/'.local/bin']:link(directory/'zf-orchestrate',state/'bin/work-orchestrate',args.apply)
    for role in LABELS:write(state/'paperclip-instructions'/role/'AGENTS.md',instructions(role,cfg['workspace']),args.apply)
    def save_registry():
        if not args.apply:
            write(registry_file,json.dumps(registry,indent=2)+'\n',False);return
        with locked(state/'paperclip-registry.lock'):
            fresh=json.loads(registry_file.read_text()) if registry_file.exists() else {}
            registry['graph_tasks']=fresh.get('graph_tasks',registry['graph_tasks'])
            registry['pilot_issue_ids']=fresh.get('pilot_issue_ids',registry['pilot_issue_ids'])
            if unchanged:
                registry['qualified']=fresh.get('qualified',False)
                if 'qualification' in fresh:registry['qualification']=fresh['qualification']
            write(registry_file,json.dumps(registry,indent=2)+'\n',True)
    save_registry()
    write(state/'PAPERCLIP-HERMES.md',(source/'docs/company-paperclip.md').read_bytes(),args.apply)
    skill=(source/'shared/skills/company-orchestration/SKILL.md').read_bytes()
    for hh in [Path(cfg['hermes_home']),*[Path(cfg['hermes_home'])/'profiles'/r for r in LABELS]]:
        write(hh/'skills/autonomous-ai-agents/company-orchestration/SKILL.md',skill,args.apply)
        write(hh/'skills/autonomous-ai-agents/company-coding-stack/SKILL.md',company_skill(Path(cfg['workspace']),state),args.apply)
    write(Path(cfg['workspace'])/'.claude/skills/company-orchestration/SKILL.md',skill,args.apply)
    write(Path.home()/'.claude/skills/company-orchestration/SKILL.md',skill,args.apply)
    plan=[]
    for role in LABELS:
        desired=payload(cfg,role,profiles,state,profiles['zf-planner']['agent_id']);plan.append({'role':role,'action':'update' if role in owned else 'create','name':desired['name']})
        if not args.apply:continue
        intent=state/('paperclip-create-intent-'+role+'.json')
        if role in owned:
            body={k:v for k,v in desired.items() if k not in {'runner','permissions','metadata'}}
            existing=owned[role]
            body['adapterConfig']['env']={**existing.get('adapterConfig',{}).get('env',{}),**body['adapterConfig']['env']}
            prior_limit=existing.get('adapterConfig',{}).get('maxTurnsPerRun')
            if isinstance(prior_limit,int) and 1<=prior_limit<=profiles[role]['max_turns']:
                body['adapterConfig']['maxTurnsPerRun']=prior_limit
            body['runtimeConfig']=existing.get('runtimeConfig',desired['runtimeConfig'])
            updated=api('/api/agents/'+owned[role]['id'],'PATCH',body)
        else:
            if intent.exists():raise ValueError('An earlier create is unresolved; inspect native agents before retrying.')
            write(intent,json.dumps({'role':role,'company_id':meta['company_id'],'state':'unknown'}),True)
            updated=api('/api/companies/'+meta['company_id']+'/agents','POST',desired)
        if updated.get('adapterType')!='hermes_local':raise ValueError('The native adapter selection changed; do not run tasks.')
        profiles[role]['agent_id']=updated['id'];registry['profiles']=profiles
        save_registry()
        if intent.exists():write(intent,json.dumps({'role':role,'id':updated['id'],'state':'reconciled'}),True)
    projects=[enroll_project(pid,meta['company_id'],cfg['workspace'],api,args.apply) for pid in args.project]
    if projects:
        catalog_file=state/'paperclip-intake-projects.json'
        catalog=json.loads(catalog_file.read_text()) if catalog_file.exists() else {}
        catalog.update({p['name']:p for p in projects});write(catalog_file,json.dumps(catalog,indent=2)+'\n',args.apply)
    print(json.dumps({'apply':args.apply,'plan':plan,'qualified':registry['qualified'],'projects':projects,
                      'old_agents_untouched':True,'scheduled_heartbeats':False,'gateway_restart':False}))


if __name__=='__main__':
    try:main()
    except (OSError,ValueError,KeyError):raise SystemExit('Paperclip setup stopped; inspect private state and reconcile before retrying.')
