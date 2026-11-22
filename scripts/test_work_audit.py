"""Detect drift and preserve active work without exposing adapter environment."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from audit_work_paperclip import collect,digest,service_health,write_report,board_health,hermes_runtime
from setup_work_monitor import monitor_plist,check_owned,MARKER

OLD='a'*40;NEW='b'*40

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
        q=self.root/'qualification.json'
        self.reg={'scope':'device','qualified':True,'contract':contract,'qualification':{'file':str(q),'sha256':digest(q)},'hermes_home':str(self.root/'hermes'),'company_id':'company','profiles':{'zf-planner':{'agent_id':'agent','provider':'server1','model':'synthetic','max_turns':24,'context':262144,'config_sha256':digest(cfg)}}}
        q.write_text(json.dumps({'accepted':True,'contract':contract,'profiles':self.reg['profiles']}))
        self.reg['qualification']['sha256']=digest(q)
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
    def test_missing_registered_role_cannot_report_a_healthy_empty_team(self):
        self.reg['profiles']={};(self.root/'paperclip-hermes.json').write_text(json.dumps(self.reg))
        r=collect(self.root,self.api);self.assertFalse(r['all_pass']);self.assertFalse(r['checks']['qualification_profiles'])
    def install(self,head=NEW,moves=((OLD,NEW,1000),),receipts=()):
        """A synthetic Hermes checkout: HEAD, its reflog and any update receipts."""
        git=self.root/'hermes/hermes-agent/.git';(git/'logs').mkdir(parents=True,exist_ok=True)
        (git/'HEAD').write_text(head+'\n')
        (git/'logs/HEAD').write_text(''.join(f'{old} {new} Tester <t@example.invalid> {at} -0500\tcheckout: moving\n' for old,new,at in moves))
        folder=self.root/'hermes/logs/update_receipts';folder.mkdir(parents=True,exist_ok=True)
        for n,receipt in enumerate(receipts):(folder/f'update_2026010{n}_000000_1_x.json').write_text(json.dumps(receipt))
    def accept(self,**fields):
        q=Path(self.reg['qualification']['file']);q.write_text(json.dumps({**json.loads(q.read_text()),**fields}))
        self.reg['qualification']['sha256']=digest(q);(self.root/'paperclip-hermes.json').write_text(json.dumps(self.reg))
    def receipt(self,sha=NEW,**fields):
        return {'outcome':'success','finished_at':'2026-01-02T03:04:05.000000+00:00','initiator':'desktop',
                'pre_update':{'sha':OLD,'version':'1.2.2'},'post_update':{'sha':sha,'version':'1.2.3'},**fields}
    def test_installed_runtime_is_read_from_the_checkout_and_its_matching_receipt(self):
        # The second reflog line is a checkout of the revision already checked out: it must not move the time.
        # The third receipt is a later run that found nothing to update: it must not replace the real one.
        self.install(moves=((OLD,NEW,1000),(NEW,NEW,2000)),receipts=[self.receipt(sha=OLD,initiator='cli'),self.receipt(),
            self.receipt(initiator='cli',pre_update={'sha':NEW,'version':'1.2.3'})])
        r=collect(self.root,self.api);h=r['hermes']
        self.assertEqual((h['revision'],h['version'],h['changed_at']),(NEW,'1.2.3','1970-01-01T00:16:40+00:00'))
        self.assertEqual(h['last_update'],{'finished_at':'2026-01-02T03:04:05.000000+00:00','from_version':'1.2.2','initiator':'desktop'})
        # A receipt that names no runtime adds no check: the count and the result stay as they were.
        self.assertIsNone(h['accepted_revision']);self.assertNotIn('hermes_runtime_accepted',r['checks']);self.assertTrue(r['all_pass'])
    def test_a_receipt_that_names_its_runtime_fails_once_the_runtime_moves(self):
        self.install();self.accept(hermes_runtime={'revision':NEW})
        r=collect(self.root,self.api);self.assertTrue(r['checks']['hermes_runtime_accepted']);self.assertTrue(r['all_pass'])
        self.install(head=OLD,moves=((OLD,NEW,1000),(NEW,OLD,3000)))
        r=collect(self.root,self.api);self.assertFalse(r['checks']['hermes_runtime_accepted']);self.assertFalse(r['all_pass'])
        self.assertEqual((r['hermes']['revision'],r['hermes']['accepted_revision']),(OLD,NEW))
    def test_an_unreadable_runtime_is_unverified_and_never_satisfies_a_named_revision(self):
        self.assertEqual(collect(self.root,self.api)['hermes']['status'],'unverified')
        for head in ['not-a-revision','ref: refs/heads/../../outside','ref: refs/heads/missing']:
            with self.subTest(head=head):
                self.install(head=head);self.assertEqual(hermes_runtime(self.root/'hermes')['status'],'unverified')
        self.accept(hermes_runtime={'revision':NEW});r=collect(self.root,self.api)
        self.assertFalse(r['checks']['hermes_runtime_accepted']);self.assertFalse(r['all_pass'])
        self.install();self.accept(hermes_runtime={'revision':'PRIVATE'})
        r=collect(self.root,self.api);self.assertFalse(r['checks']['hermes_runtime_accepted'])
        self.assertEqual(r['hermes']['accepted_revision'],'invalid');self.assertNotIn('PRIVATE',json.dumps(r))
    def test_a_branch_checkout_resolves_and_receipt_text_is_never_copied_unchecked(self):
        self.install(head='ref: refs/heads/main',moves=((OLD,NEW,1000),),receipts=[
            self.receipt(initiator='PRIVATE VALUE',finished_at=['PRIVATE'],pre_update={'version':'x'*41}),
            self.receipt(outcome='failed',initiator='cli'),'PRIVATE'])
        git=self.root/'hermes/hermes-agent/.git';(git/'packed-refs').write_text(f'# pack-refs\n{NEW} refs/heads/main\n')
        h=hermes_runtime(self.root/'hermes');self.assertEqual((h['revision'],h['version']),(NEW,'1.2.3'))
        self.assertEqual(h['last_update'],{'finished_at':None,'from_version':None,'initiator':None})
        self.assertNotIn('PRIVATE',json.dumps(h))
        (git/'refs/heads').mkdir(parents=True);(git/'refs/heads/main').write_text(OLD+'\n')
        h=hermes_runtime(self.root/'hermes');self.assertEqual((h['revision'],h['version'],h['changed_at']),(OLD,None,None))
    def health(self):
        return {'status':'ok','version':'2026.1106.0','startupRecovery':{'phase':'ready'},
                'databaseBackup':{'enabled':True,'status':'ok','backupDir':'PRIVATE_PATH',
                                  'latestBackup':{'ageHours':0.5}},
                'nativeRecovery':{'blocked':1,'resuming_session':1,'private':'PRIVATE_VALUE'}}
    def test_historical_instance_recovery_does_not_imply_a_stuck_company_worker(self):
        r=service_health(self.root,collect(self.root,self.api),lambda _:self.health())
        self.assertTrue(r['all_pass']);self.assertTrue(r['company_run_queue_idle'])
        self.assertEqual(r['service']['native_recovery_counts'],{'blocked':1,'resuming_session':1})
        self.assertNotIn('PRIVATE',json.dumps(r))
    def test_service_mismatch_recovery_and_backup_fail_independently(self):
        for field,value,check in [('version','other','service_version_matches_source'),
                                  ('startupRecovery',{'phase':'recovering'},'service_ready'),
                                  ('databaseBackup',{'enabled':False},'database_backup_healthy')]:
            with self.subTest(field=field):
                h=self.health();h[field]=value
                r=service_health(self.root,collect(self.root,self.api),lambda _:h)
                self.assertFalse(r['all_pass']);self.assertFalse(r['checks'][check])
    def test_private_snapshot_replaces_symlink_without_touching_target(self):
        target=self.root/'unrelated';target.write_text('preserve')
        out=self.root/'latest.json';out.symlink_to(target)
        write_report(out,{'all_pass':False,'incomplete':True})
        self.assertEqual(target.read_text(),'preserve');self.assertFalse(out.is_symlink())
        self.assertEqual(os.stat(out).st_mode&0o777,0o600)
        self.assertFalse(json.loads(out.read_text())['all_pass'])
    def test_unavailable_enrollment_writes_a_failed_receipt_instead_of_leaving_stale_success(self):
        out=self.root/'latest.json';write_report(out,{'all_pass':True})
        r=subprocess.run([sys.executable,str(Path(__file__).with_name('audit_work_paperclip.py')),
                          '--state',str(self.root/'missing'),'--health','--output',str(out)],capture_output=True,text=True)
        self.assertEqual(r.returncode,2);report=json.loads(out.read_text())
        self.assertFalse(report['all_pass']);self.assertTrue(report['incomplete'])
        self.assertEqual(json.loads(r.stdout),report)
    def test_monitor_has_bounded_read_only_invocation_and_no_release_polling(self):
        p=monitor_plist(self.root,'audit.py',sys.executable)
        self.assertEqual(p['StartInterval'],300);self.assertNotIn('KeepAlive',p)
        self.assertIn('--health',p['ProgramArguments']);self.assertNotIn('--check-releases',p['ProgramArguments'])
        self.assertEqual(p['StandardOutPath'],'/dev/null')
    def test_monitor_preserves_unmanaged_plist_and_symlink(self):
        target=self.root/'monitor.plist';target.write_bytes(plistlib.dumps({'Label':'other'}))
        original=target.read_bytes()
        with self.assertRaises(ValueError):check_owned(target)
        self.assertEqual(target.read_bytes(),original)
        target.write_bytes(plistlib.dumps({'Comment':MARKER}));check_owned(target)
        link=self.root/'link';link.symlink_to(target)
        with self.assertRaises(ValueError):check_owned(link)
    def test_native_board_counts_do_not_emit_private_task_content_or_release_holds(self):
        home=self.root/'hermes';db=home/'kanban/boards/zenithflow/kanban.db';db.parent.mkdir(parents=True);db.touch()
        (self.root/'config.json').write_text(json.dumps({'scope':'device','hermes_home':str(home),'hermes':'/synthetic/hermes'}))
        def run(argv,**kwargs):
            self.assertEqual(argv[-3:],['zenithflow','list','--json']);self.assertEqual(kwargs['env']['HERMES_HOME'],str(home))
            return subprocess.CompletedProcess(argv,0,json.dumps([
                {'status':'blocked','body':'PRIVATE_BODY','title':'PRIVATE_TITLE','created_at':1},
                {'status':'ready','body':'PRIVATE_BODY','created_at':80}]))
        report=board_health(self.root,'zenithflow',run,now=100)
        self.assertEqual(report['status_counts'],{'blocked':1,'ready':1})
        self.assertEqual(report['oldest_ready_card_age_seconds'],20)
        self.assertNotIn('PRIVATE',json.dumps(report))
        for board in ['missing','../zenithflow']:
            with self.assertRaises(ValueError):board_health(self.root,board,run)

if __name__=='__main__':unittest.main()
