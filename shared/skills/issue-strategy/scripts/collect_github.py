#!/usr/bin/env python3
"""Read-only GitHub issue evidence. Writes private snapshots, never issue changes."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


class ReadError(Exception):
    pass


def credential(repo, directory, token_env=None):
    if token_env:
        token=os.environ.get(token_env)
        if not token:raise ReadError('The explicitly selected token environment is empty.')
        return token
    result=subprocess.run(['git','-C',str(directory),'credential','fill'],
        input=f'protocol=https\nhost=github.com\npath={repo}.git\n\n',
        env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GIT_ASKPASS='/usr/bin/false'),
        capture_output=True,text=True,timeout=25)
    fields=dict(line.split('=',1) for line in result.stdout.splitlines() if '=' in line)
    if result.returncode or not fields.get('password'):
        raise ReadError('Repository-scoped Git credential unavailable; configure authorized read access.')
    return fields['password']


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        raise ReadError('GitHub redirected the request; verify the canonical repository before retrying.')


class Client:
    def __init__(self,repo,token):
        self.base='https://api.github.com/repos/'+repo
        self.headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json',
                      'X-GitHub-Api-Version':'2022-11-28','User-Agent':'issue-strategy-read-only'}
        self.opener=urllib.request.build_opener(NoRedirect())

    def get(self,path,query=None):
        url=self.base+path+('?' + urllib.parse.urlencode(query) if query else '')
        try:
            with self.opener.open(urllib.request.Request(url,headers=self.headers),timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as exc:
            # No headers, response bodies, credentials or issue text in diagnostics.
            raise ReadError(f'HTTP {exc.code}; permission, SSO, rate-limit or endpoint availability needs review.') from None
        except (urllib.error.URLError,TimeoutError,json.JSONDecodeError):
            raise ReadError('Transport or JSON read failed; this source remains unverified.') from None


def pages(get,path,query=None,max_pages=20):
    rows=[];count=0
    for page in range(1,max_pages+1):
        try:
            batch=get(path,{**(query or {}),'per_page':100,'page':page})
            if not isinstance(batch,list):raise ReadError('Expected a paginated list.')
        except ReadError as exc:
            return rows,{'complete':False,'pages':count,'reason':str(exc)}
        count+=1;rows.extend(batch)
        if len(batch)<100:return rows,{'complete':True,'pages':count}
    return rows,{'complete':False,'pages':count,'reason':'Page budget reached; collection may be truncated.'}


def optional(get,path,max_pages):
    rows,coverage=pages(get,path,max_pages=max_pages)
    return {'items':rows,'coverage':coverage}


def compact(issue):
    return {key:issue.get(key) for key in ['number','title','html_url','state','created_at','updated_at','comments']}|{
        'labels':[label['name'] for label in issue.get('labels',[])],
        'has_assignee':bool(issue.get('assignees')),'has_milestone':bool(issue.get('milestone'))}


def collect(client,out,numbers=(),max_pages=20):
    out.mkdir(parents=True,exist_ok=False,mode=0o700)
    out.chmod(0o700);files={}
    def save(name,value,jsonl=False):
        data=('\n'.join(json.dumps(row,separators=(',',':')) for row in value)+'\n' if jsonl
              else json.dumps(value,indent=2)+'\n').encode()
        path=out/name
        with path.open('xb') as stream:stream.write(data)
        path.chmod(0o600);files[name]=hashlib.sha256(data).hexdigest()
    manifest={'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'source':client.base,'mode':'selected-issues' if numbers else 'open-index',
              'requested_issues':list(numbers),'coverage':{},'files':files}
    try:
        repository=client.get('');manifest['default_branch']=repository['default_branch']
        try:manifest['default_branch_sha']=client.get('/commits/'+urllib.parse.quote(repository['default_branch'],safe=''))['sha']
        except ReadError as exc:manifest['default_branch_error']=str(exc)
        if numbers:
            for number in numbers:
                prefix=f'/issues/{number}'
                try:
                    issue=client.get(prefix)
                    if 'pull_request' in issue:raise ReadError('Selected number is a pull request, not an issue.')
                    detail={'issue':issue}
                    for key,path in [('comments',prefix+'/comments'),('timeline',prefix+'/timeline'),
                                     ('blocked_by',prefix+'/dependencies/blocked_by'),
                                     ('blocking',prefix+'/dependencies/blocking'),('sub_issues',prefix+'/sub_issues')]:
                        detail[key]=optional(client.get,path,max_pages)
                    try:detail['parent']={'item':client.get(prefix+'/parent'),'available':True}
                    except ReadError as exc:detail['parent']={'available':False,'reason':str(exc)}
                    save(f'issue-{number}.json',detail)
                    manifest['coverage'][str(number)]={key:detail[key]['coverage'] for key in ['comments','timeline','blocked_by','blocking','sub_issues']}
                    manifest['coverage'][str(number)]['parent_available']=detail['parent']['available']
                except ReadError as exc:manifest['coverage'][str(number)]={'issue_available':False,'reason':str(exc)}
        else:
            raw,coverage=pages(client.get,'/issues',{'state':'open','sort':'updated','direction':'desc'},max_pages)
            issues=[item for item in raw if 'pull_request' not in item]
            save('open-issues.json',issues);index=[compact(i) for i in sorted(issues,key=lambda i:i['number'])]
            for n in range(0,len(index),200):save(f'index-{n//200+1:02d}.jsonl',index[n:n+200],True)
            manifest['coverage']['open_issues']=coverage;manifest['open_issue_count']=len(issues)
            manifest['label_counts']={name:sum(name in i['labels'] for i in index) for name in sorted({l for i in index for l in i['labels']})}
            manifest['unassigned']=sum(not i['has_assignee'] for i in index)
            manifest['without_milestone']=sum(not i['has_milestone'] for i in index)
    except ReadError as exc:manifest['collection_error']=str(exc)
    finally:
        manifest['finished_at']=datetime.datetime.now(datetime.timezone.utc).isoformat()
        # The manifest describes the snapshot; it does not hash itself.
        data=json.dumps(manifest,indent=2)+'\n';path=out/'manifest.json';path.write_text(data);path.chmod(0o600)
    return manifest


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',required=True,help='OWNER/REPO on github.com')
    parser.add_argument('--repo-dir',type=Path,required=True,help='Existing checkout with correctly scoped Git credential helper')
    parser.add_argument('--output',type=Path,required=True,help='New private directory; existing output is never overwritten')
    parser.add_argument('--issues',nargs='+',type=int,default=[])
    parser.add_argument('--max-pages',type=int,default=20)
    parser.add_argument('--token-env',help='Explicit opt-in environment variable; never a token argument')
    args=parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*',args.repo):parser.error('Use OWNER/REPO, not a URL.')
    if not 1<=args.max_pages<=100 or any(n<=0 for n in args.issues):parser.error('Invalid page budget or issue number.')
    try:
        token=credential(args.repo,args.repo_dir,args.token_env)
        result=collect(Client(args.repo,token),args.output,sorted(set(args.issues)),args.max_pages)
        print(json.dumps({'output':str(args.output),'mode':result['mode'],
                          'open_issues':result.get('open_issue_count'),'coverage':result['coverage'],
                          'collection_error':result.get('collection_error')}))
        incomplete=(result.get('collection_error') or
                    (result['mode']=='open-index' and not result['coverage'].get('open_issues',{}).get('complete')) or
                    any(value.get('issue_available') is False for value in result['coverage'].values()))
        return 2 if incomplete else 0
    except (ReadError,OSError,ValueError,subprocess.SubprocessError) as exc:
        print('Issue collection failed: '+(str(exc) if isinstance(exc,ReadError) else type(exc).__name__),file=sys.stderr)
        return 2


if __name__=='__main__':sys.exit(main())
