#!/usr/bin/env python3
"""Read-only company Paperclip drift checks; never upgrade or restart a service."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
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
    with urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect).open(req,timeout=10) as r:return json.load(r)


REVISION=re.compile(r'[0-9a-f]{40}(?:[0-9a-f]{24})?')
PLAIN=re.compile(r'[A-Za-z0-9][A-Za-z0-9._+:-]{0,39}')


def hermes_runtime(home):
    """Installed Hermes revision, when the checkout last moved to it and what moved it. Files only.

    The revision and the time are the checkout's own HEAD and reflog. The version and the
    initiator come from Hermes's update receipt for that exact revision, when one exists.
    """
    home=Path(home);git=home/'hermes-agent/.git'
    scope=('Read from the checkout and its update receipts; a version is shown only when a receipt matches '
           'the installed revision. Installed is not accepted: acceptance is what the qualification receipt names.')
    try:
        head=(git/'HEAD').read_text().strip()
        if head.startswith('ref: '):
            ref=head[5:]
            if not re.fullmatch(r'refs/[A-Za-z0-9._/-]+',ref) or '..' in ref:raise ValueError('Unknown HEAD reference.')
            head=(git/ref).read_text().strip() if (git/ref).is_file() else next(
                line.split()[0] for line in (git/'packed-refs').read_text().splitlines() if line.endswith(' '+ref))
        if not REVISION.fullmatch(head):raise ValueError('Unknown revision.')
    except (OSError,ValueError,StopIteration):
        return {'status':'unverified','scope':scope}
    moved=None
    try:
        for line in (git/'logs/HEAD').read_text().splitlines():
            fields=line.split('\t')[0].split()
            # A checkout of the revision already checked out is logged too; only a real move counts.
            if len(fields)>=4 and fields[0]!=fields[1] and fields[1]==head:moved=int(fields[-2])
    except (OSError,ValueError):moved=None
    plain=lambda value:value if isinstance(value,str) and PLAIN.fullmatch(value) else None
    runtime={'revision':head,'version':None,'last_update':None,'scope':scope,
             'changed_at':datetime.datetime.fromtimestamp(moved,datetime.timezone.utc).isoformat() if moved else None}
    for receipt in sorted((home/'logs/update_receipts').glob('update_*.json')):
        try:
            if receipt.stat().st_size>1<<20:continue
            update=json.loads(receipt.read_text())
            post=update.get('post_update') or {};pre=update.get('pre_update') or {}
            # A later run that found nothing to update has the same revision on both sides: not what moved it.
            if post.get('sha')!=head or pre.get('sha')==head or update.get('outcome')!='success':continue
            runtime['version']=plain(post.get('version'))
            runtime['last_update']={'finished_at':plain(update.get('finished_at')),'from_version':plain(pre.get('version')),
                                    'initiator':plain(update.get('initiator'))}
        except (OSError,ValueError,AttributeError):continue
    return runtime


def collect(state,api=None):
    state=Path(state);reg=json.loads((state/'paperclip-hermes.json').read_text())
    if reg.get('scope')!='device':raise ValueError('Run this on the enrolled company work Mac.')
    api=api or (lambda path:http_json(reg['api_base'],path))
    checks={};contract=reg.get('contract') or {}
    runtime=hermes_runtime(reg['hermes_home']);runtime['accepted_revision']=None
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
        # A receipt that names the runtime it accepted is held to it; one that names none adds no check.
        named=accepted.get('hermes_runtime') if isinstance(accepted.get('hermes_runtime'),dict) else {}
        if named.get('revision'):
            valid=isinstance(named['revision'],str) and bool(REVISION.fullmatch(named['revision']))
            runtime['accepted_revision']=named['revision'] if valid else 'invalid'
            checks['hermes_runtime_accepted']=valid and named['revision']==runtime.get('revision')
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
            'paperclip_version':version,'hermes':runtime,'agents':agents,'active_runs':active,'company_run_queue_idle':not active,
            'scope':'configuration and company run metadata; not a new model/artifact/cancellation qualification or permission to restart; inspect other companies and gateway users separately'}


def latest_stable():
    request=urllib.request.Request('https://api.github.com/repos/paperclipai/paperclip/releases/latest',headers={'User-Agent':'Company-Paperclip-Audit/1.0','Accept':'application/vnd.github+json'})
    with urllib.request.urlopen(request,timeout=15) as r:v=json.load(r)
    if v.get('prerelease') or v.get('draft'):raise ValueError('Expected a stable public release.')
    return {'version':v['tag_name'].removeprefix('v'),'published_at':v['published_at'],'url':v['html_url']}


def service_health(state, report, api=None):
    """Add service evidence without treating recovery counters as stuck workers."""
    reg=json.loads((Path(state)/'paperclip-hermes.json').read_text())
    api=api or (lambda path:http_json(reg['api_base'],path))
    health=api('/api/health')
    backup=health.get('databaseBackup') or {}
    report['checks']['service_ready']=health.get('status')=='ok' and (health.get('startupRecovery') or {}).get('phase')=='ready'
    report['checks']['service_version_matches_source']=bool(report['paperclip_version']) and health.get('version')==report['paperclip_version']
    report['checks']['database_backup_healthy']=backup.get('enabled') is True and backup.get('status')=='ok'
    report['service']={
        'version':health.get('version'),
        'startup_phase':(health.get('startupRecovery') or {}).get('phase'),
        'backup':{'enabled':backup.get('enabled'),'status':backup.get('status'),
                  'age_hours':(backup.get('latestBackup') or {}).get('ageHours')},
        'native_recovery_counts':{k:v for k,v in (health.get('nativeRecovery') or {}).items()
                                  if isinstance(v,int) and not isinstance(v,bool) and v>=0},
        'recovery_scope':'Instance-wide counters can describe historical or other-company work. Reconcile issue/run records before taking action.',
    }
    report['all_pass']=all(report['checks'].values())
    report['scope']+='; running service version, startup and database backup health; recovery counters are advisory'
    return report


def write_report(path, report):
    """Replace only the latest private snapshot, including incomplete checks."""
    path=Path(path).expanduser();path.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
    name=None
    try:
        with tempfile.NamedTemporaryFile(mode='w',dir=path.parent,prefix='.'+path.name+'.',delete=False) as f:
            name=f.name
            json.dump(report,f,indent=2);f.write('\n');f.flush();os.fsync(f.fileno())
        os.replace(name,path)
    finally:
        if name and os.path.exists(name):os.unlink(name)


def board_health(state, board, run=subprocess.run, now=None):
    """Use native JSON output; never infer that a held card should be released."""
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,63}',board):raise ValueError('Invalid board slug.')
    state=Path(state);reg=json.loads((state/'paperclip-hermes.json').read_text())
    cfg=json.loads((state/'config.json').read_text())
    if reg.get('scope')!='device' or cfg.get('scope')!='device' or cfg.get('hermes_home')!=reg.get('hermes_home'):
        raise ValueError('Board checks require the enrolled device profile.')
    if not (Path(reg['hermes_home'])/'kanban/boards'/board/'kanban.db').is_file():
        raise ValueError('The board must already exist; the audit does not create it.')
    env=dict(os.environ,HERMES_HOME=reg['hermes_home'])
    for key in ['HERMES_PROFILE','HERMES_PROFILE_NAME','HERMES_KANBAN_BOARD']:env.pop(key,None)
    result=run([cfg['hermes'],'--profile','default','kanban','--board',board,'list','--json'],
               capture_output=True,text=True,timeout=30,check=True,stdin=subprocess.DEVNULL,env=env)
    rows=json.loads(result.stdout)
    if not isinstance(rows,list):raise ValueError('Unknown native board output shape.')
    counts={};ready=[];now=time.time() if now is None else now
    for row in rows:
        status=row['status'];counts[status]=counts.get(status,0)+1
        if status=='ready' and isinstance(row.get('created_at'),(int,float)):
            ready.append(max(0,now-row['created_at']))
    return {'board':board,'status_counts':counts,
            'oldest_ready_card_age_seconds':round(max(ready),1) if ready else None,
            'scope':'Card age is since creation, not ready transition. Blocked/todo counts are advisory; inspect dependencies and owner decisions before recovery.'}


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--state',type=Path,default=Path.home()/'zenithflow/.workstation')
    p.add_argument('--check-releases',action='store_true',help='Read official GitHub stable release metadata; never install it.')
    p.add_argument('--health',action='store_true',help='Also check running version, startup and backup health; recovery counts remain advisory.')
    p.add_argument('--output',type=Path,help='Atomically write a mode-600 latest snapshot, including failed or incomplete checks.')
    p.add_argument('--board',action='append',default=[],help='Also summarize an existing enrolled Hermes board through its native read-only CLI.')
    a=p.parse_args()
    try:
        report=collect(a.state)
        if a.health:service_health(a.state,report)
        if a.board:report['boards']=[board_health(a.state,b) for b in a.board]
    except (OSError,ValueError,KeyError,TypeError,subprocess.SubprocessError):
        report={'observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'all_pass':False,
                'incomplete':True,'error':'Enrollment, configuration or service unavailable; inspect private state. No service or task changed.'}
    if a.check_releases:
        try:
            release=latest_stable();report['latest_stable']=release
            report['upgrade_review_needed']=release['version']!=report['paperclip_version']
            report['upgrade_action']='Separate canary, backup/restore and contract acceptance required before changing the live instance.'
        except Exception:report['latest_stable']={'status':'unverified'}
    if a.output:
        report['fresh_until']=(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(minutes=15)).isoformat()
        write_report(a.output,report)
    print(json.dumps(report,indent=2));return 0 if report['all_pass'] else 2


if __name__=='__main__':
    try:raise SystemExit(main())
    except (OSError,ValueError,KeyError):raise SystemExit('Audit incomplete: inspect private enrollment/configuration and service availability; no changes made.')
