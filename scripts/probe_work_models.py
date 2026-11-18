#!/usr/bin/env python3
"""Opt-in synthetic qualification of approved workstation routes; no tools execute.

Uses only loopback endpoints from the private workstation config. Outputs contain
synthetic answers and numeric telemetry, never credentials or reasoning bodies.
Dedicated reasoning fields are omitted; a malformed server may place reasoning
inside its answer content, which is retained only in the private receipt.
These small checks qualify this fixture set, not general model capability.
"""
import argparse
import datetime
import hashlib
import json
import math
from pathlib import Path
import socket
import time
import urllib.error
import urllib.parse
import urllib.request


CASES = {
    'triage': {
        'prompt': 'Facts: E1: checkout returns HTTP 503 since release R7. E2: customer count and owner are unknown. Return a raw JSON object without Markdown fences, with exactly keys priority, owner, customer_count, evidence. priority must be incident; preserve unknowns as null. evidence must be exactly the ID array ["E1", "E2"], with no citation text.',
        'answer': {'priority':'incident','owner':None,'customer_count':None,'evidence':['E1','E2']},
    },
    'decision': {
        'prompt': 'Evidence: E1: disabling the new feature flag restored checkout in staging. E2: production impact is not measured. E3: no migration is required. Choose the next recommendation from validate_flag_rollback, rewrite_service, declare_resolved. Return a raw JSON object without Markdown fences, with exactly keys recommendation, production_resolved, evidence. Use false for production_resolved unless the evidence proves production recovery. evidence must be exactly the ID array ["E1", "E2"], with no citation text.',
        'answer': {'recommendation':'validate_flag_rollback','production_resolved':False,'evidence':['E1','E2']},
    },
    'review': {
        'prompt': 'Review this Python function against its contract: sum integers 1 through n inclusive for nonnegative n. Line 1: def total(n): Line 2: return sum(range(1, n)). Return a raw JSON object without Markdown fences, with exactly keys defect_line, counterexample_n, actual, expected. Use the smallest nonnegative failing n.',
        'answer': {'defect_line':2,'counterexample_n':1,'actual':0,'expected':1},
    },
    'tool_arguments': {
        'prompt': 'Read the evidence before deciding. Request exactly one read_evidence call with path issue.json. Do not answer the issue or request other tools.',
        'tools': [{'type':'function','function':{'name':'read_evidence',
            'description':'Read a synthetic evidence fixture (this probe never executes the call).',
            'parameters':{'type':'object','properties':{'path':{'type':'string'}},
                          'required':['path'],'additionalProperties':False}}}],
        'answer': {'path':'issue.json'},
    },
}


def score(case, message, finish_reason):
    if finish_reason == 'length':
        return 'output_limit'
    if not isinstance(message,dict):
        return 'invalid_artifact'
    try:
        if case == 'tool_arguments':
            calls = message.get('tool_calls', [])
            if len(calls) != 1 or calls[0]['function']['name'] != 'read_evidence':
                return 'invalid_tool_call'
            answer = json.loads(calls[0]['function']['arguments'])
        else:
            answer = json.loads(message.get('content') or '')
        # bool and int compare equal in Python: JSON types are part of the oracle.
        if json.dumps(answer, sort_keys=True) == json.dumps(CASES[case]['answer'], sort_keys=True):
            return 'accepted'
        return 'incorrect_artifact'
    except (ValueError, TypeError, KeyError):
        return 'invalid_artifact'


def qualify_oracles():
    for name, case in CASES.items():
        message = {'content':json.dumps(case['answer'])}
        if name == 'tool_arguments':
            message = {'tool_calls':[{'function':{'name':'read_evidence',
                       'arguments':json.dumps(case['answer'])}}]}
        if (score(name,message,'stop')!='accepted'
                or score(name,{'content':'{}'},'stop')=='accepted'
                or score(name,message,'length')!='output_limit'):
            raise RuntimeError('Oracle controls failed: '+name)


def endpoint(route):
    parsed = urllib.parse.urlsplit(route['url'])
    if (parsed.scheme != 'http' or parsed.hostname not in {'127.0.0.1','::1'}
            or parsed.username or parsed.password or parsed.query or parsed.fragment
            or parsed.path.rstrip('/') != '/v1'):
        raise ValueError('Probe routes must be HTTP loopback /v1 endpoints.')
    return route['url'].rstrip('/')+'/chat/completions'


def numeric_usage(value):
    if isinstance(value, dict):
        return {k:numeric_usage(v) for k,v in value.items()
                if isinstance(v, (dict,int,float)) and not isinstance(v,bool)}
    return value if math.isfinite(value) else None


def attempt(key, route, name, timeout, max_tokens, options):
    case = CASES[name]
    payload = {'model':route['model'],'messages':[{'role':'user','content':case['prompt']}],
               'max_tokens':max_tokens,'stream':False,**options}
    if 'tools' in case:
        payload['tools'] = case['tools']
    url = endpoint(route)
    row = {'route':key,'requested_model':route['model'],'context':route['context'],
           'case':name,'requested_options':options,'max_tokens':max_tokens,
           'prompt_sha256':hashlib.sha256(case['prompt'].encode()).hexdigest()}
    started = time.monotonic()
    try:
        req = urllib.request.Request(url,json.dumps(payload).encode(),
              {'Content-Type':'application/json','Authorization':'Bearer selfhosted'})
        # Loopback requests must not inherit HTTP_PROXY or an operator proxy handler.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(req,timeout=timeout) as response:
            result = json.load(response)
        choice = result['choices'][0]
        message = choice['message']
        if not isinstance(message,dict):
            raise ValueError('Invalid message shape')
        row.update(outcome=score(name,message,choice.get('finish_reason')),
                   served_model=result.get('model'),finish_reason=choice.get('finish_reason'),
                   usage=numeric_usage(result.get('usage') or {}),
                   content=message.get('content'),tool_calls=message.get('tool_calls'),
                   reasoning_characters=len(message.get('reasoning_content') or message.get('reasoning') or ''))
    except urllib.error.HTTPError as exc:
        row.update(outcome='provider_error',http_status=exc.code)
    except (TimeoutError, socket.timeout):
        row['outcome'] = 'deadline'
    except urllib.error.URLError as exc:
        row['outcome'] = 'deadline' if isinstance(exc.reason, (TimeoutError,socket.timeout)) else 'connection_error'
    except OSError:
        row['outcome'] = 'connection_error'
    except (ValueError, KeyError, TypeError, IndexError):
        row['outcome'] = 'invalid_response'
    row['wall_seconds'] = round(time.monotonic()-started,3)
    return row


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--from-config',type=Path,required=True)
    p.add_argument('--routes',nargs='+',choices=['local','1','2'],default=['local','1','2'])
    p.add_argument('--cases',nargs='+',choices=list(CASES),default=list(CASES))
    p.add_argument('--repeats',type=int,default=2)
    p.add_argument('--timeout',type=int,default=120)
    p.add_argument('--max-tokens',type=int,default=2048)
    p.add_argument('--reasoning-effort',choices=['low','medium','high'])
    p.add_argument('--thinking',choices=['on','off'])
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--run',action='store_true',help='Actually send synthetic inference requests')
    a = p.parse_args()
    if not 1 <= a.repeats <= 10 or not 1 <= a.timeout <= 300 or not 128 <= a.max_tokens <= 8192:
        p.error('Use 1..10 repeats, 1..300 seconds and 128..8192 output tokens.')
    qualify_oracles()
    cfg = json.loads(a.from_config.expanduser().read_text())
    for key in a.routes:
        endpoint(cfg['routes'][key])
    options = {}
    if a.reasoning_effort:
        options['reasoning_effort'] = a.reasoning_effort
    if a.thinking:
        options['chat_template_kwargs'] = {'enable_thinking':a.thinking=='on'}
    if not a.run:
        print(json.dumps({'oracle_controls':'passed','requests':len(a.routes)*len(a.cases)*a.repeats,
                          'network':'not invoked','requested_options':options}))
        return
    # Exclusive creation prevents overwriting prior/ambiguous experiment evidence.
    a.output.parent.mkdir(parents=True,exist_ok=True)
    with a.output.open('x') as out:
        a.output.chmod(0o600)
        out.write(json.dumps({'kind':'manifest','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'harness_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            'oracle_controls':'passed','timeout_seconds':a.timeout,
            'sampling_unit':'one serial request; no retries or tool execution',
            'limitations':'small synthetic smoke; options requested, not proven applied; no TTFT or native-agent qualification'})+'\n')
        out.flush()
        for repeat in range(a.repeats):
            # Reverse route order on alternating rounds to reduce fixed ordering bias.
            for key in a.routes[::1 if repeat%2==0 else -1]:
                for name in a.cases:
                    row = attempt(key,cfg['routes'][key],name,a.timeout,a.max_tokens,options)
                    row['repeat'] = repeat+1
                    out.write(json.dumps(row)+'\n');out.flush()
                    print(key,name,row['outcome'],row['wall_seconds'],flush=True)


if __name__ == '__main__':
    main()
