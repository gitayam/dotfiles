"""Detect drift and preserve active work without exposing adapter environment."""
import json
from pathlib import Path
import tempfile
import unittest
from audit_work_paperclip import collect,digest

class Audit(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        files={'runtime_sha256':'bin/work-paperclip','intake_sha256':'bin/work-orchestrate','graph_module_sha256':'lib/work_paperclip_graph.py','native_stage_sha256':'server/dist/routes/issues.js'}
        contract={}
        for k,rel in files.items():
            f=self.root/rel;f.parent.mkdir(parents=True,exist_ok=True);f.write_text('frozen fixture');contract[k]=digest(f)
        contract['native_stage_file']=str(self.root/files['native_stage_sha256'])
        (self.root/'server/package.json').write_text(json.dumps({'version':'2026.1106.0'}))
        cfg=self.root/'hermes/profiles/zf-planner/config.yaml';cfg.parent.mkdir(parents=True);cfg.write_text('synthetic config')
        q=self.root/'qualification.json';q.write_text(json.dumps({'accepted':True,'contract':contract}))
        self.reg={'scope':'device','qualified':True,'contract':contract,'qualification':{'file':str(q),'sha256':digest(q)},'hermes_home':str(self.root/'hermes'),'company_id':'company','profiles':{'zf-planner':{'agent_id':'agent','provider':'server1','model':'synthetic','max_turns':24,'context':262144,'config_sha256':digest(cfg)}}}
        (self.root/'paperclip-hermes.json').write_text(json.dumps(self.reg))
        self.agent={'companyId':'company','status':'idle','adapterType':'hermes_local','adapterConfig':{'hermesCommand':str(self.root/'bin/hermes-paperclip'),'env':{'SYNTHETIC_KEY':'must-not-appear'}},'runtimeConfig':{'heartbeat':{'enabled':False,'maxConcurrentRuns':1}}};self.live=[]
    def api(self,path):return self.live if path.endswith('/live-runs') else self.agent
    def test_active_work_is_reported_without_being_a_failure_or_mutation(self):
        self.live=[{'id':'owned-run','status':'running'}];r=collect(self.root,self.api)
        self.assertTrue(r['all_pass']);self.assertFalse(r['company_run_queue_idle']);self.assertEqual(r['active_runs'],self.live)
        self.assertNotIn('must-not-appear',json.dumps(r))
    def test_changed_runtime_or_profile_fails_the_drift_check(self):
        (self.root/'bin/work-paperclip').write_text('changed');r=collect(self.root,self.api)
        self.assertFalse(r['all_pass']);self.assertFalse(r['checks']['runtime_sha256'])
    def test_foreign_agent_and_invalid_gate_are_visible(self):
        self.agent['companyId']='another';self.agent['runtimeConfig']['heartbeat']['enabled']=True
        r=collect(self.root,self.api);self.assertFalse(r['checks']['zf-planner_binding']);self.assertFalse(r['checks']['zf-planner_timers_off'])
    def test_error_state_does_not_hide_behind_matching_fingerprints(self):
        self.agent['status']='error';r=collect(self.root,self.api)
        self.assertFalse(r['all_pass']);self.assertFalse(r['checks']['zf-planner_available'])

if __name__=='__main__':unittest.main()
