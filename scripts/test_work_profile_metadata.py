import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import yaml

from audit_work_paperclip import collect, digest
from requalify_work_profile_metadata import plan, refresh, reconstruct_accepted


class MetadataQualification(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.state=Path(self.tmp.name);self.home=self.state/'hermes'
        paths={'runtime_sha256':'bin/work-paperclip','intake_sha256':'bin/work-orchestrate',
               'graph_module_sha256':'lib/work_paperclip_graph.py','native_stage_sha256':'server/dist/routes/issues.js'}
        contract={}
        for key,rel in paths.items():
            f=self.state/rel;f.parent.mkdir(parents=True,exist_ok=True);f.write_text('frozen runtime')
            contract[key]=digest(f)
        contract['native_stage_file']=str(self.state/paths['native_stage_sha256'])
        (self.state/'server/package.json').write_text(json.dumps({'version':'2026.1106.0'}))
        self.config={'model':{'provider':'server1','default':'synthetic'},'agent':{'max_turns':24},
                     'providers':{'server1':{'api_key':'PRIVATE_FIXTURE'}},'note':'bounded evidence '*20}
        accepted=yaml.safe_dump(self.config,sort_keys=False,default_flow_style=False).encode()
        self.accepted_hash=hashlib.sha256(accepted).hexdigest()
        self.file=self.home/'profiles/zf-planner/config.yaml';self.file.parent.mkdir(parents=True)
        self.native=copy.deepcopy(self.config);self.native['_config_version']=54
        self.write_native()
        role={'agent_id':'agent','provider':'server1','model':'synthetic','max_turns':24,
              'context':262144,'config_sha256':self.accepted_hash}
        self.qual=self.state/'reviews/prior/qualification.json';self.qual.parent.mkdir(parents=True)
        self.qual.write_text(json.dumps({'accepted':True,'contract':contract,'profiles':{'zf-planner':role},
                                        'modes':['coding','analysis'],'workflow':'fixed graph','limits':['existing limits']}))
        self.reg={'scope':'device','qualified':True,'contract':contract,'hermes_home':str(self.home),
                  'company_id':'company','profiles':{'zf-planner':role},
                  'qualification':{'file':str(self.qual),'sha256':digest(self.qual)}}
        self.registry=self.state/'paperclip-hermes.json';self.registry.write_text(json.dumps(self.reg))
        self.live=[];self.agent={'companyId':'company','status':'idle','adapterType':'hermes_local',
            'adapterConfig':{'hermesCommand':str(self.state/'bin/hermes-paperclip')},
            'runtimeConfig':{'heartbeat':{'enabled':False,'maxConcurrentRuns':1}}}
    def write_native(self):
        self.file.write_text(yaml.safe_dump(self.native,sort_keys=False,width=120))
    def api(self,path):return self.live if path.endswith('/live-runs') else self.agent
    def test_raw_gate_fails_before_refresh_then_exact_reconstruction_restores_it(self):
        self.assertFalse(collect(self.state,self.api)['all_pass'])
        before=self.registry.read_bytes();profile=self.file.read_bytes();prior=self.qual.read_bytes()
        preview,_=plan(self.state,self.api)
        self.assertEqual(self.registry.read_bytes(),before)
        self.assertNotIn('PRIVATE_FIXTURE',json.dumps(preview))
        receipt=self.state/'reviews/new/qualification.json'
        result=refresh(self.state,receipt,preview,self.api)
        self.assertTrue(result['changed']);self.assertTrue(collect(self.state,self.api)['all_pass'])
        self.assertEqual(self.file.read_bytes(),profile);self.assertEqual(self.qual.read_bytes(),prior)
        q=json.loads(receipt.read_text());self.assertEqual(q['predecessor_qualification']['sha256'],digest(self.qual))
        self.assertEqual(q['limits'],['existing limits',preview['scope']])
    def test_model_tool_or_budget_changes_require_ordinary_qualification(self):
        for change in [{'model':{'provider':'other','default':'different'}},{'agent':{'max_turns':40}},
                       {'platform_toolsets':{'cli':['code_execution']}}]:
            with self.subTest(change=change):
                self.native={**copy.deepcopy(self.config),'_config_version':54,**change};self.write_native()
                with self.assertRaises(ValueError):plan(self.state,self.api)
    def test_corrupted_receipt_cannot_use_metadata_path(self):
        self.qual.write_text('{}')
        with self.assertRaises(ValueError):plan(self.state,self.api)
    def test_changed_runtime_cannot_use_metadata_path(self):
        (self.state/'bin/work-paperclip').write_text('changed runtime')
        with self.assertRaises(ValueError):plan(self.state,self.api)
    def test_active_work_refuses_refresh_without_touching_state(self):
        before=self.registry.read_bytes();self.live=[{'id':'live','status':'running'}]
        with self.assertRaises(ValueError):plan(self.state,self.api)
        self.assertEqual(self.registry.read_bytes(),before)
        self.live=[];self.agent['status']='running'
        with self.assertRaises(ValueError):plan(self.state,self.api)
    def test_preview_race_preserves_the_newer_config_and_manifest(self):
        preview,_=plan(self.state,self.api);before=self.registry.read_bytes()
        self.native['agent']['max_turns']=40;self.write_native()
        with self.assertRaises(ValueError):refresh(self.state,self.state/'reviews/new/q.json',preview,self.api)
        self.assertEqual(self.registry.read_bytes(),before)
    def test_manifest_change_during_inspection_is_not_lost(self):
        def racing_api(path):
            changed=copy.deepcopy(self.reg);changed['new_owner_field']='preserve'
            self.registry.write_text(json.dumps(changed))
            return self.api(path)
        with self.assertRaises(ValueError):plan(self.state,racing_api)
        self.assertEqual(json.loads(self.registry.read_text())['new_owner_field'],'preserve')
    def test_duplicate_keys_and_noninteger_version_markers_are_rejected(self):
        with self.assertRaises(ValueError):reconstruct_accepted(self.file.read_bytes()+b'agent: {}\n',self.accepted_hash)
        self.native['_config_version']=True;self.write_native()
        with self.assertRaises(ValueError):plan(self.state,self.api)
    def test_repeat_does_not_rewrite_an_accepted_receipt(self):
        preview,_=plan(self.state,self.api);receipt=self.state/'reviews/new/qualification.json'
        refresh(self.state,receipt,preview,self.api);accepted=receipt.read_bytes()
        again,_=plan(self.state,self.api)
        self.assertFalse(refresh(self.state,receipt,again,self.api)['changed'])
        self.assertEqual(receipt.read_bytes(),accepted)


if __name__=='__main__':unittest.main()
