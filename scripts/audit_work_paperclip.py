#!/usr/bin/env python3
"""Read-only company Paperclip drift checks; never upgrade or restart a service."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import urllib.parse
import urllib.request


def digest(path):
    try:return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except OSError:return None


def http_json(base,path):
    parsed=urllib.parse.urlsplit(base)
    if parsed.scheme!='http' or parsed.hostname not in {'localhost','127.0.0.1','::1'} or parsed.username or parsed.password:
        raise ValueError('The company service must be loopback.')
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self,*args,**kwargs):return None
    req=urllib.request.Request(base.rstrip('/')+path,headers={'User-Agent':'Company-Paperclip-Audit/1.0'})
    with urllib.request.build_opener(NoRedirect).open(req,timeout=10) as r:return json.load(r)


def collect(state,api=None):
    state=Path(state);reg=json.loads((state/'paperclip-hermes.json').read_text())
    if reg.get('scope')!='device':raise ValueError('Run this on the enrolled company work Mac.')
    api=api or (lambda path:http_json(reg['api_base'],path))
    checks={};contract=reg.get('contract') or {}
    paths={'runtime_sha256':state/'bin/work-paperclip','intake_sha256':state/'bin/work-orchestrate',
           'graph_module_sha256':state/'lib/work_paperclip_graph.py','native_stage_sha256':Path(contract.get('native_stage_file','/unconfigured-paperclip-source'))}
    for key,path in paths.items():checks[key]=bool(contract.get(key)) and digest(path)==contract[key]
    checks['qualified']=reg.get('qualified') is True
    q=reg.get('qualification') or {};checks['qualification_receipt']=bool(q.get('sha256')) and digest(q.get('file','/unconfigured-qualification'))==q['sha256']
    if checks['qualification_receipt']:
        accepted=json.loads(Path(q['file']).read_text());checks['qualification_contract']=accepted.get('accepted') is True and accepted.get('contract')==contract
        pins=accepted.get('profiles') or {}
        checks['qualification_profiles']=bool(pins) and set(pins)==set(reg['profiles']) and all(
            all(reg['profiles'][role].get(k)==v for k,v in fields.items()) for role,fields in pins.items())
    agents=[]
    for role,p in reg['profiles'].items():
        checks[role+'_config']=digest(Path(reg['hermes_home'])/'profiles'/role/'config.yaml')==p['config_sha256']
        checks[role+'_context']=p.get('context',0)>=65536
        a=api('/api/agents/'+p['agent_id']);cfg=a.get('adapterConfig') or {};heartbeat=(a.get('runtimeConfig') or {}).get('heartbeat') or {}
        checks[role+'_binding']=a.get('companyId')==reg['company_id'] and a.get('adapterType')=='hermes_local' and cfg.get('hermesCommand')==str(state/'bin/hermes-paperclip')
        checks[role+'_timers_off']=heartbeat.get('enabled') is False
        checks[role+'_one_run']=heartbeat.get('maxConcurrentRuns')==1
        checks[role+'_available']=a.get('status') in {'idle','running'}
        agents.append({'profile':role,'status':a.get('status'),'provider':p.get('provider'),'model':p.get('model'),'max_turns':p.get('max_turns')})
    live=api('/api/companies/'+reg['company_id']+'/live-runs');live=live.get('items',live) if isinstance(live,dict) else live
    active=[{'id':r['id'],'status':r['status']} for r in live if r['status'] in {'running','queued','scheduled_retry'}]
    package=paths['native_stage_sha256'].parent.parent.parent/'package.json'
    version=json.loads(package.read_text()).get('version') if package.is_file() else None
    return {'observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'all_pass':all(checks.values()),'checks':checks,
            'paperclip_version':version,'agents':agents,'active_runs':active,'company_run_queue_idle':not active,
            'scope':'configuration and company run metadata; not a new model/artifact/cancellation qualification or permission to restart; inspect other companies and gateway users separately'}


def latest_stable():
    request=urllib.request.Request('https://api.github.com/repos/paperclipai/paperclip/releases/latest',headers={'User-Agent':'Company-Paperclip-Audit/1.0','Accept':'application/vnd.github+json'})
    with urllib.request.urlopen(request,timeout=15) as r:v=json.load(r)
    if v.get('prerelease') or v.get('draft'):raise ValueError('Expected a stable public release.')
    return {'version':v['tag_name'].removeprefix('v'),'published_at':v['published_at'],'url':v['html_url']}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--state',type=Path,default=Path.home()/'zenithflow/.workstation')
    p.add_argument('--check-releases',action='store_true',help='Read official GitHub stable release metadata; never install it.')
    a=p.parse_args();report=collect(a.state)
    if a.check_releases:
        try:
            release=latest_stable();report['latest_stable']=release
            report['upgrade_review_needed']=release['version']!=report['paperclip_version']
            report['upgrade_action']='Separate canary, backup/restore and contract acceptance required before changing the live instance.'
        except Exception:report['latest_stable']={'status':'unverified'}
    print(json.dumps(report,indent=2));return 0 if report['all_pass'] else 2


if __name__=='__main__':
    try:raise SystemExit(main())
    except (OSError,ValueError,KeyError):raise SystemExit('Audit incomplete: inspect private enrollment/configuration and service availability; no changes made.')
