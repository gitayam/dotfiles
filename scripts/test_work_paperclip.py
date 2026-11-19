"""Protocol and refusal checks; no model calls or operator credentials."""
import hashlib
import importlib.machinery
import importlib.util
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
import urllib.error
import copy
import io
import sqlite3
from contextlib import closing
from setup_work_paperclip import validate_routing
from setup_work_hermes import hermes_config
import work_paperclip_graph as intake

loader=importlib.machinery.SourceFileLoader('work_paperclip',str(Path(__file__).parents[1]/'shared/bin/work-paperclip'))
spec=importlib.util.spec_from_loader(loader.name,loader);runtime=importlib.util.module_from_spec(spec);loader.exec_module(runtime)


class Protocol(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
        self.registry={'scope':'device','state':str(self.root/'state'),'hermes_home':str(self.root/'hermes'),
            'hermes':'/approved/hermes','api_base':'http://127.0.0.1:3100','company_id':'company','profiles':{}}
        for role,provider,model in [('zf-planner','server1','glm-5.3-flash'),('zf-developer','local','gemma-4-26b-a4b'),('zf-reviewer','server1','glm-5.3-flash')]:
            f=Path(self.registry['hermes_home'])/'profiles'/role/'config.yaml';f.parent.mkdir(parents=True);f.write_text('approved fixture\n')
            self.registry['profiles'][role]={'provider':provider,'model':model,'context':262144,'max_turns':16,
                'config_sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'toolsets':['file','terminal','skills','delegation','kanban','code_execution'],'agent_id':role+'-agent'}
        self.work=self.root/'workspace';self.work.mkdir();self.message=self.work/'result.md';self.message.write_text('Checked the independent artifact.')
        run=Path(self.registry['state'])/'paperclip-runs/run-one';run.mkdir(parents=True)
        self.context=run/'context.json';self.data={'api_base':self.registry['api_base'],'company_id':'company',
            'agent_id':'zf-planner-agent','profile':'zf-planner','run_id':'run-one','issue_id':'issue-one',
            'workspace':str(self.work),'state':self.registry['state'],'api_token':'synthetic-not-a-real-credential','team':{k:v['agent_id'] for k,v in self.registry['profiles'].items()}}
        self.socktmp=tempfile.TemporaryDirectory(prefix='zfpt-',dir='/private/tmp' if Path('/private/tmp').is_dir() else None);self.addCleanup(self.socktmp.cleanup)
        self.socket=Path(self.socktmp.name)/'rpc';self.broker=runtime.CallbackBroker(self.socket,self.context,self.data)
        self.thread=threading.Thread(target=self.broker.serve_forever,kwargs={'poll_interval':0.01},daemon=True);self.thread.start()
        self.addCleanup(self.cleanup_broker)
        self.context.write_text(json.dumps({'socket_path':str(self.socket)}));self.issue={'id':'issue-one','companyId':'company','assigneeAgentId':'zf-planner-agent','executionState':None,
          'executionPolicy':{'commentRequired':True,'stages':[
            {'type':'review','participants':[{'type':'agent','agentId':'zf-reviewer-agent'}]},
            {'type':'approval','participants':[{'type':'agent','agentId':'zf-planner-agent'}]}]}}

    def cleanup_broker(self):
        if self.thread.is_alive():self.broker.shutdown();self.thread.join(timeout=1)
        self.broker.server_close()

    def call(self, action, api):
        with patch.object(runtime,'load_registry',return_value=self.registry),patch.object(runtime,'api',side_effect=api):
            return runtime.callback(self.context,action,str(self.message))

    def test_native_arguments_keep_route_and_approval_policy(self):
        command,removed=runtime.build_command(self.registry,'zf-planner',['chat','-q','synthetic','-m','auto','--yolo','--source','tool'])
        self.assertTrue(removed);self.assertNotIn('--yolo',command);self.assertIn('--oneshot',command)
        self.assertEqual(command[:4],['/approved/hermes','--profile','zf-planner','chat'])
        self.assertEqual(command[-4:],['--provider','server1','--model','glm-5.3-flash'])
        tools=command[command.index('--toolsets')+1].split(',');self.assertNotIn('kanban',tools);self.assertNotIn('code_execution',tools)
        for role in runtime.ROLES:
            command,_=runtime.build_command(self.registry,role,['chat','-q','synthetic'])
            self.assertEqual(command[-1],self.registry['profiles'][role]['model'])

    def test_readiness_probe_is_literal_tool_free_and_pins_real_profile(self):
        args=['chat','-Q','-q',runtime.PROBE_QUERY,'--max-turns','1','-m','auto']
        command=runtime.probe_command(self.registry,'zf-planner',args)
        self.assertEqual(command[-1],'glm-5.3-flash');self.assertIn('bot_room',command)
        for changed in [args+['--yolo'],args[:-1]+['foreign'],['chat','-q','do work']]:
            with self.assertRaises(runtime.RuntimeErrorSafe):runtime.probe_command(self.registry,'zf-planner',changed)

    def test_foreign_routes_bypass_flags_and_unqualified_resume_refused(self):
        for extra in [['--provider','anthropic'],['--model','unapproved'],['--resume','old'],['--ignore-rules'],
                      ['--max-turns','17'],['--max-turns','0'],['--toolsets','code_execution'],['--toolsets','kanban'],
                      ['--run-budget','30'],['--query-file','/predictable/secret']]:
            with self.subTest(extra=extra),self.assertRaises(runtime.RuntimeErrorSafe):
                runtime.build_command(self.registry,'zf-planner',['chat','-q','synthetic',*extra])

    def test_profile_drift_is_not_silently_retargeted(self):
        f=Path(self.registry['hermes_home'])/'profiles/zf-planner/config.yaml';f.write_text('changed')
        with self.assertRaisesRegex(runtime.RuntimeErrorSafe,'configuration changed'):
            runtime.build_command(self.registry,'zf-planner',['chat','-q','synthetic'])

    def test_context_file_mutation_cannot_retarget_broker_scope(self):
        public={'socket_path':str(self.socket),'issue_id':'other','workspace':'/','api_base':'https://other.example','agent_id':'other'}
        self.context.write_text(json.dumps(public))
        with patch.object(runtime,'load_registry',return_value=self.registry),patch.object(runtime,'api',return_value=self.issue) as api:
            self.assertEqual(runtime.callback(self.context,'show')['id'],'issue-one')
            self.assertEqual(api.call_args.args[2],'/api/issues/issue-one')
        outside=self.root/'outside';outside.write_text('not owned')
        with patch.object(runtime,'load_registry',return_value=self.registry),patch.object(runtime,'api',return_value=self.issue) as api,self.assertRaises(runtime.RuntimeErrorSafe):
            runtime.callback(self.context,'finish',str(outside))
        self.assertEqual(api.call_count,1)

    def test_successful_handoff_repeated_after_assignment_change_does_not_write_twice(self):
        calls=[];current=dict(self.issue)
        def api(context,method,path,body=None):
            calls.append((method,path,body))
            if method=='PATCH':current.update(assigneeAgentId=body['assigneeAgentId'],status=body['status'])
            return dict(current)
        self.call('handoff',api);self.call('handoff',api)
        writes=[c for c in calls if c[0]=='PATCH'];self.assertEqual(len(writes),1)
        self.assertEqual(writes[0][2]['assigneeAgentId'],'zf-developer-agent')
        self.assertNotIn('executionPolicy',writes[0][2])

    def test_lost_write_response_is_reconciled_without_resending(self):
        self.issue['executionState']={'currentStageType':'approval'}
        comments=[];calls=[]
        def api(context,method,path,body=None):
            calls.append(method)
            if method=='PATCH':
                comments.append({'body':body['comment'],'authorAgentId':context['agent_id']})
                raise urllib.error.URLError('simulated lost response')
            return comments if path.endswith('/comments') else dict(self.issue)
        with self.assertRaises(runtime.RuntimeErrorSafe):self.call('finish',api)
        self.call('finish',api);self.assertEqual(calls.count('PATCH'),1)

    def test_ambiguous_write_without_positive_receipt_is_not_retried(self):
        self.issue['executionState']={'currentStageType':'approval'}
        calls=[]
        def api(context,method,path,body=None):
            calls.append(method)
            if method=='PATCH':raise urllib.error.URLError('simulated network failure')
            return [] if path.endswith('/comments') else dict(self.issue)
        with self.assertRaises(runtime.RuntimeErrorSafe):self.call('finish',api)
        with self.assertRaisesRegex(runtime.RuntimeErrorSafe,'unknown'):self.call('finish',api)
        self.assertEqual(calls.count('PATCH'),1)

    def test_expired_credentials_and_secret_bearing_comments_refused(self):
        self.message.write_text('synthetic-not-a-real-credential')
        with self.assertRaisesRegex(runtime.RuntimeErrorSafe,'credential'):self.call('finish',lambda *x:self.issue)
        self.assertNotIn(self.data['api_token'],self.context.read_text())
        self.cleanup_broker()
        with self.assertRaisesRegex(runtime.RuntimeErrorSafe,'expired'):self.call('finish',lambda *x:self.issue)

    def test_approval_phase_cannot_reenter_planning_handoff(self):
        self.issue['executionState']={'currentStageType':'approval'}
        with self.assertRaisesRegex(runtime.RuntimeErrorSafe,'initial planner'):self.call('handoff',lambda *x:self.issue)

    def test_coding_planner_cannot_skip_development_but_analysis_can_finish(self):
        with self.assertRaisesRegex(runtime.RuntimeErrorSafe,'hand off'):self.call('finish',lambda *x:self.issue)
        self.issue['executionPolicy']['stages']=self.issue['executionPolicy']['stages'][:1]
        calls=[]
        def api(ctx,method,path,body=None):
            calls.append(method);return dict(self.issue)
        self.call('finish',api);self.assertEqual(calls.count('PATCH'),1)
        with self.assertRaisesRegex(runtime.RuntimeErrorSafe,'initial planner'):self.call('handoff',lambda *x:self.issue)

    def test_unresolved_execution_fences_later_runs_even_after_pid_exit(self):
        f=runtime.reserve_issue(self.registry,'issue-one','run-first','zf-planner')
        with self.assertRaisesRegex(runtime.RuntimeErrorSafe,'unresolved'):
            runtime.reserve_issue(self.registry,'issue-one','run-second','zf-developer')
        runtime.atomic_json(f,{'state':'unknown','pid':99999999})
        with self.assertRaises(runtime.RuntimeErrorSafe):runtime.reserve_issue(self.registry,'issue-one','run-third','zf-developer')
        runtime.atomic_json(f,{'state':'exited'})
        runtime.reserve_issue(self.registry,'issue-one','run-next','zf-developer')

    def test_native_expected_cancellation_needs_committed_marker_and_termination(self):
        old={'state':'unknown','run_id':'run-one','profile':'zf-planner'}
        directory=self.context.parent
        terminal={'session_id':'exact-run-session','ended_at':123,'cwd':str(self.work),'children_terminal':True}
        result={'child_reaped':True,'process_group_absent':True,'hermes_termination':terminal}
        record={'state':'unknown','action':'handoff','marker':'unique-marker','issue_id':'issue-one','run_id':'run-one',
          'profile':'zf-planner','agent_id':'zf-planner-agent','workspace':str(self.work),'expected_assignee':'zf-developer-agent'}
        next_context={**self.data,'agent_id':'zf-developer-agent','profile':'zf-developer','run_id':'next-run'}
        prior={'status':'cancelled','errorCode':'issue_reassigned','companyId':'company','agentId':'zf-planner-agent',
          'contextSnapshot':{'issueId':'issue-one'},'resultJson':{'reassignmentStopConfirmed':True}}
        issue={**self.issue,'assigneeAgentId':'zf-developer-agent','status':'todo'}
        comments=[{'body':'proof unique-marker','authorAgentId':'zf-planner-agent','createdByRunId':'run-one'}]
        def api(ctx,method,path,body=None):
            return prior if '/heartbeat-runs/' in path else comments if path.endswith('/comments') else issue
        def write():
            runtime.atomic_json(directory/'process-result.json',result);runtime.atomic_json(directory/'callback-test.json',record)
        write()
        with patch.object(runtime,'api',side_effect=api):
            evidence=runtime.reconcile_transition(self.registry,old,next_context)
            self.assertEqual(evidence['predecessor_run'],'run-one')
            for broken in ['missing_marker','wrong_cancellation','live_gateway','live_group','wrong_author']:
                saved=copy.deepcopy((result,prior,comments))
                if broken=='missing_marker':comments[0]['body']='no proof'
                elif broken=='wrong_cancellation':prior['errorCode']='operator_cancel'
                elif broken=='live_gateway':result['hermes_termination']['ended_at']=None
                elif broken=='live_group':result['process_group_absent']=False
                else:comments[0]['authorAgentId']='other'
                write()
                with self.subTest(broken=broken),self.assertRaises(runtime.RuntimeErrorSafe):
                    runtime.reconcile_transition(self.registry,old,next_context)
                result,prior,comments=saved
            write()

    def test_intake_uses_native_review_and_a_single_durable_issue(self):
        request={'request_key':'owned-request','kind':'coding','title':'Synthetic','description':'Owned paths and acceptance.',
          'project_id':'00000000-0000-4000-8000-000000000001','project_workspace_id':'00000000-0000-4000-8000-000000000002'}
        coding=intake.preview(request)
        self.assertEqual(coding['children'],['plan','develop','review'])
        self.assertFalse(coding['starts_automatically']);self.assertTrue(coding['isolated_worktree'])
        analysis=intake.preview({**request,'kind':'analysis'})
        self.assertEqual(analysis['children'],['analysis','review'])
        for changed in [{**request,'kind':'unknown'},{**request,'extra':'unsupported'},{**request,'project_id':'not-a-project'}]:
            with self.assertRaises(ValueError):intake.preview(changed)

    def test_native_session_id_binds_terminal_record_when_gemma_omits_prompt_and_cwd(self):
        role='zf-developer';p=Path(self.registry['hermes_home'])/'profiles'/role/'state.db'
        with closing(sqlite3.connect(p)) as c:
            c.execute('CREATE TABLE sessions(id TEXT,ended_at REAL,end_reason TEXT,cwd TEXT,model TEXT,system_prompt TEXT,parent_session_id TEXT)')
            c.execute('INSERT INTO sessions VALUES(?,?,?,?,?,?,?)',('local-'+'a'*64,123,'cli_close',None,'gemma-4-26b-a4b',None,None))
            c.commit()
        class Target:
            buffer=io.BytesIO()
        runtime.relay_output(io.BytesIO(('\nsession_id: local-'+'a'*64+'\n').encode()),Target(),self.context.parent,str(self.work),True)
        result=runtime.session_termination(self.registry,role,self.context)
        self.assertEqual(result['session_id'],'local-'+'a'*64);self.assertTrue(result['children_terminal'])
        self.assertEqual(result['cwd'],str(self.work));self.assertEqual(result['binding_source'],'native-cli-stderr')
        runtime.relay_output(io.BytesIO(('session_id: local-'+'b'*64+'\n').encode()),Target(),self.context.parent,str(self.work),True)
        self.assertIsNone(runtime.session_termination(self.registry,role,self.context))

    def test_graph_keeps_static_owner_and_requires_completed_children(self):
        self.data['graph']={'kind':'coding','phase':'approve','parent_id':None,'workspace':str(self.work),
          'depends_on':['child-review'],'children':['child-review']}
        self.issue['executionPolicy']['stages']=[]
        child={'id':'child-review','companyId':'company','parentId':'issue-one','status':'in_progress'};calls=[]
        def api(ctx,method,path,body=None):
            calls.append((method,path,body));return child if path.endswith('/child-review') else dict(self.issue)
        with self.assertRaisesRegex(runtime.RuntimeErrorSafe,'incomplete'):self.call('finish',api)
        self.assertFalse(any(c[0]=='PATCH' for c in calls))
        child['status']='done'
        with patch.object(runtime,'wait_for_graph_dependency'):self.call('finish',api)
        writes=[c for c in calls if c[0]=='PATCH'];self.assertEqual(len(writes),1)
        self.assertNotIn('assigneeAgentId',writes[0][2])
        with patch.object(runtime,'wait_for_graph_dependency'),self.assertRaisesRegex(runtime.RuntimeErrorSafe,'fixed owners'):self.call('handoff',api)

    def test_graph_waits_for_actual_predecessor_exit_after_native_done(self):
        dep={'id':'child','companyId':'company','status':'done','assigneeAgentId':'zf-developer-agent'}
        lease=Path(self.registry['state'])/'paperclip-leases/child.json'
        runtime.atomic_json(lease,{'state':'running','run_id':'previous'})
        result={'child_reaped':True,'process_group_absent':True,'interrupted':False,
          'hermes_termination':{'ended_at':123,'children_terminal':True,'cwd':str(self.work)}}
        runtime.atomic_json(Path(self.registry['state'])/'paperclip-runs/previous/process-result.json',result)
        native={'status':'succeeded','exitCode':0,'companyId':'company','agentId':'zf-developer-agent','contextSnapshot':{'issueId':'child'}}
        def exited(_):runtime.atomic_json(lease,{'state':'exited','run_id':'previous'})
        with patch.object(runtime.time,'sleep',side_effect=exited) as wait,patch.object(runtime,'api',return_value=native) as api:
            runtime.wait_for_graph_dependency(self.data,dep)
        self.assertEqual(wait.call_count,1);self.assertEqual(api.call_count,1)
        result['process_group_absent']=False
        runtime.atomic_json(Path(self.registry['state'])/'paperclip-runs/previous/process-result.json',result)
        with patch.object(runtime,'api',return_value=native),self.assertRaisesRegex(runtime.RuntimeErrorSafe,'termination receipt'):
            runtime.wait_for_graph_dependency(self.data,dep)

    def test_delegated_children_cannot_finish_parent_issue(self):
        with patch.dict('os.environ',{'HERMES_DELEGATED_CHILD_CONTEXT':'1'}),self.assertRaisesRegex(runtime.RuntimeErrorSafe,'children'):
            self.call('finish',lambda *x:self.issue)


class Enrollment(unittest.TestCase):
    def test_provider_endpoint_and_auxiliary_drift_are_refused(self):
        routes={key:{'name':key,'url':'http://127.0.0.1:'+str(port)+'/v1','model':model,'context':context}
                for key,port,model,context in [('local',8080,'gemma-4-26b-a4b',131072),('1',8001,'glm-5.3-flash',262144),('2',8002,'openai/gpt-oss-120b',49152)]}
        cfg={'routes':routes};valid=hermes_config({},routes,Path('/tmp/company'))
        validate_routing(cfg,valid)
        for mutation in ['provider','auxiliary','fallback']:
            changed=copy.deepcopy(valid)
            if mutation=='provider':changed['providers']['local']['base_url']='https://unapproved.example/v1'
            elif mutation=='auxiliary':changed['auxiliary']['review']['base_url']='https://unapproved.example/v1'
            else:changed['fallback_providers']=[{'provider':'server2','model':routes['2']['model']}]
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):validate_routing(cfg,changed)


if __name__=='__main__':unittest.main()
