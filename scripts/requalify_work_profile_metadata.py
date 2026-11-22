#!/usr/bin/env python3
"""Requalify only added native Hermes version metadata and YAML formatting.

Dry run by default. No profile, model, worker or runtime is changed. Requires
PyYAML. A semantic reconstruction must hash to the exact accepted profile bytes;
any behavioral change requires the ordinary qualification workflow instead.
"""
import argparse
import copy
import datetime
import hashlib
import json
from pathlib import Path

import yaml

from audit_work_paperclip import collect, digest
from work_paperclip_graph import atomic_json, locked


class UniqueKeys(yaml.SafeLoader):
    pass


def unique_mapping(loader, node, deep=False):
    result={}
    for key_node,value_node in node.value:
        key=loader.construct_object(key_node,deep=deep)
        if key in result:raise ValueError('Duplicate YAML keys require manual review.')
        result[key]=loader.construct_object(value_node,deep=deep)
    return result


UniqueKeys.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,unique_mapping)


def reconstruct_accepted(raw, expected):
    parsed=yaml.load(raw,Loader=UniqueKeys)
    if not isinstance(parsed,dict):raise ValueError('Expected a profile mapping.')
    version=parsed.pop('_config_version',None)
    if isinstance(version,bool) or not isinstance(version,int) or version<1:
        raise ValueError('Only an added integer native configuration-version marker is eligible.')
    reconstructed=yaml.safe_dump(parsed,sort_keys=False,default_flow_style=False).encode()
    if hashlib.sha256(reconstructed).hexdigest()!=expected:
        raise ValueError('The profile is not byte-equivalent to the accepted settings after metadata reconstruction; run ordinary qualification.')
    return version


def plan(state, api=None):
    state=Path(state);file=state/'paperclip-hermes.json';raw_registry=file.read_bytes();reg=json.loads(raw_registry)
    registry_sha256=hashlib.sha256(raw_registry).hexdigest()
    audit=collect(state,api)
    allowed={role+'_config' for role in reg['profiles']}
    if any(not ok and key not in allowed for key,ok in audit['checks'].items()):
        raise ValueError('An enrollment, receipt, runtime, binding or policy check failed; metadata refresh is not applicable.')
    if audit['active_runs'] or any(a['status']!='idle' for a in audit['agents']):
        raise ValueError('Wait for the enrolled Paperclip agents and company run queue to be idle. No worker was interrupted.')
    profiles={}
    for role,pin in reg['profiles'].items():
        path=Path(reg['hermes_home'])/'profiles'/role/'config.yaml';raw=path.read_bytes()
        actual=hashlib.sha256(raw).hexdigest()
        if actual==pin['config_sha256']:continue
        version=reconstruct_accepted(raw,pin['config_sha256'])
        profiles[role]={'previous_sha256':pin['config_sha256'],'current_sha256':actual,
                        'native_config_version':version,'reconstruction_matches_accepted_bytes':True}
    if digest(file)!=registry_sha256:raise ValueError('Enrollment changed during inspection; repeat the preview after reconciliation.')
    return {'registry_sha256':registry_sha256,'profiles':profiles,
            'scope':'Only native version metadata and YAML serialization; no new behavior, graph, cancellation or artifact acceptance.'},reg


def refresh(state, receipt, expected, api=None):
    state=Path(state);receipt=Path(receipt).resolve()
    if not receipt.is_relative_to(state.resolve()/'reviews'):
        raise ValueError('Store the private receipt under workstation reviews, outside repositories.')
    with locked(state/'paperclip-registry.lock'):
        current,reg=plan(state,api)
        if current!=expected:raise ValueError('Enrollment or profile bytes changed after the preview; reconcile before applying.')
        if not current['profiles']:return {'changed':False,'profiles':{}}
        if receipt.exists() or (receipt.parent/'registry-before.json').exists():
            raise ValueError('Existing receipt or write intent: reconcile it before retrying.')
        prior=reg['qualification'];prior_data=json.loads(Path(prior['file']).read_text())
        if digest(prior['file'])!=prior['sha256']:raise ValueError('The preceding qualification changed during inspection.')
        updated=copy.deepcopy(reg)
        for role,proof in current['profiles'].items():
            updated['profiles'][role]['config_sha256']=proof['current_sha256']
        accepted={'accepted':True,'observed_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'modes':prior_data.get('modes',[]),'workflow':prior_data.get('workflow'),
                  'contract':reg['contract'],
                  'profiles':{r:{k:p[k] for k in ['provider','model','agent_id','config_sha256','max_turns']}
                              for r,p in updated['profiles'].items()},
                  'predecessor_qualification':{'file':prior['file'],'sha256':prior['sha256']},
                  'profile_metadata_migration':current['profiles'],
                  'limits':prior_data.get('limits',[])+[current['scope']]}
        # Record prior state before replacing the manifest. An interruption leaves
        # evidence to reconcile; it never creates a second worker or relaxes a gate.
        atomic_json(receipt.parent/'registry-before.json',reg)
        atomic_json(receipt,accepted)
        updated['qualification']={**prior,'file':str(receipt),'sha256':digest(receipt)}
        atomic_json(state/'paperclip-hermes.json',updated)
    return {'changed':True,'profiles':list(current['profiles']),'qualification':str(receipt)}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--state',type=Path,default=Path.home()/'zenithflow/.workstation')
    p.add_argument('--apply',action='store_true');p.add_argument('--receipt',type=Path)
    a=p.parse_args();state=a.state.expanduser().resolve();preview,_=plan(state)
    if not a.apply:print(json.dumps(preview,indent=2));return
    if not a.receipt:p.error('--apply requires a new private --receipt path under workstation reviews')
    print(json.dumps(refresh(state,a.receipt.expanduser(),preview),indent=2))


if __name__=='__main__':
    try:main()
    except (OSError,ValueError,KeyError,TypeError,yaml.YAMLError):
        raise SystemExit('Metadata requalification refused; inspect the receipt, active work and profile changes. No model or runtime settings were changed.')
