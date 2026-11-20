"""Intake recovery and ownership tests with a real local Git fixture."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid
import work_paperclip_graph as graph
from setup_work_paperclip import enroll_project

class GraphIntake(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.state=self.root/'.workstation';self.state.mkdir()
        self.repo=self.root/'source';self.repo.mkdir()
        def git(*args):return subprocess.run(['git','-C',str(self.repo),*args],check=True,capture_output=True)
        git('init');git('config','user.email','fixture@example.invalid');git('config','user.name','Fixture')
        (self.repo/'candidate.txt').write_text('committed baseline');git('add','.');git('commit','-m','fixture')
        (self.repo/'candidate.txt').write_text('preserved dirty source')
        self.pid=str(uuid.uuid4());self.wid=str(uuid.uuid4())
        self.request=dict(request_key='bounded-fixture',kind='coding',title='Fixture',description='No external actions.',project_id=self.pid,project_workspace_id=self.wid)
        self.registry={'company_id':'company','profiles':{r:{'agent_id':r} for r in set(graph.ROLES.values())}}
        (self.state/'paperclip-hermes.json').write_text(json.dumps(self.registry))
        self.project={'id':self.pid,'name':'Fixture project','companyId':'company','visibility':'private','executionWorkspacePolicy':{'sharedWorkspaceConcurrency':'serialize'}}
        self.workspaces=[{'id':self.wid,'cwd':str(self.repo)}];self.issues={};self.posts=[];self.writes=[];self.lose=None
    def api(self,path,method='GET',body=None):
        self.writes.append((path,method,copy.deepcopy(body)))
        if path=='/api/projects/'+self.pid:return copy.deepcopy(self.project)
        if path.endswith('/access-members'):return [{'subjectType':'agent','subjectId':p['agent_id']} for p in self.registry['profiles'].values()]
        if path.endswith('/workspaces'):
            if method=='GET':return copy.deepcopy(self.workspaces)
            result={**body,'id':str(uuid.uuid4())};self.workspaces.append(result)
        elif path.startswith('/api/companies/company/issues'):
            if method=='GET':return list(copy.deepcopy(self.issues).values())
            result={**body,'id':str(uuid.uuid4()),'companyId':'company','statusVersion':1};self.issues[result['id']]=result
        else:
            iid=path.rsplit('/',1)[-1];result=self.issues[iid]
            if method=='PATCH':result.update(body);result['statusVersion']+=1
            return copy.deepcopy(result)
        self.posts.append(path)
        if self.lose==path:self.lose=None;raise OSError('simulated lost response after native commit')
        return copy.deepcopy(result)
    def create(self):return graph.create_graph(self.state,self.registry,self.request,self.api)
    def test_graph_preserves_source_and_reuses_exact_request(self):
        record=self.create();again=self.create()
        self.assertEqual(record,again);self.assertEqual(len(self.posts),5)
        self.assertEqual((self.repo/'candidate.txt').read_text(),'preserved dirty source')
        self.assertEqual((Path(record['workspace'])/'candidate.txt').read_text(),'committed baseline')
        root=self.issues[record['phase_ids']['approve']]
        self.assertEqual(set(root['blockedByIssueIds']),set(record['phase_ids'].values())-{root['id']})
        self.assertTrue(all(i['status']=='backlog' and not i.get('assigneeAgentId') for i in self.issues.values()))
        self.request['description']='different work'
        with self.assertRaisesRegex(ValueError,'reused'):self.create()
    def test_lost_workspace_response_adopts_positive_receipt_without_duplicate_post(self):
        self.lose='/api/projects/'+self.pid+'/workspaces'
        with self.assertRaises(OSError):self.create()
        record=self.create();self.assertEqual(record['state'],'staged');self.assertEqual(len(self.posts),5)
    def test_missing_positive_receipt_refuses_repeat_write(self):
        self.lose='/api/companies/company/issues'
        with self.assertRaises(OSError):self.create()
        self.issues.clear();before=len(self.posts)
        with self.assertRaisesRegex(ValueError,'unresolved'):self.create()
        self.assertEqual(len(self.posts),before)
    def test_changed_lost_response_receipt_is_not_adopted(self):
        self.lose='/api/companies/company/issues'
        with self.assertRaises(OSError):self.create()
        next(iter(self.issues.values()))['description']='changed task'
        before=len(self.posts)
        with self.assertRaisesRegex(ValueError,'differs'):self.create()
        self.assertEqual(len(self.posts),before)
    def test_distinct_keys_with_same_human_title_have_distinct_native_titles(self):
        first=self.create();self.request['request_key']='another-bounded-fixture';second=self.create()
        self.assertNotEqual(first['phase_ids']['approve'],second['phase_ids']['approve'])
        self.assertNotEqual(self.issues[first['phase_ids']['approve']]['title'],self.issues[second['phase_ids']['approve']]['title'])
    def test_changed_contract_or_owner_prevents_all_activation_writes(self):
        record=self.create();iid=record['phase_ids']['develop'];original=copy.deepcopy(self.issues[iid])
        for changes in [{'assigneeAgentId':'other-agent'}, {'description':'different work'},
                        {'blockedByIssueIds':[]}, {'workspaceSelection':{'kind':'other'}},
                        {'executionPolicy':{'mode':'normal','stages':[{'type':'review'}]}}]:
            self.issues[iid]={**copy.deepcopy(original),**changes};self.writes=[]
            with self.subTest(changes=changes),self.assertRaises(ValueError):graph.activate(record,self.registry,self.api)
            self.assertFalse([w for w in self.writes if w[1]!='GET'])
    def test_project_or_membership_refusal_precedes_worktree_or_post(self):
        self.project['executionWorkspacePolicy']={}
        with self.assertRaisesRegex(ValueError,'serialize'):self.create()
        self.project['executionWorkspacePolicy']={'sharedWorkspaceConcurrency':'serialize'}
        original=self.api
        def no_members(path,*args):return [] if path.endswith('/access-members') else original(path,*args)
        with self.assertRaisesRegex(ValueError,'access'):graph.create_graph(self.state,self.registry,self.request,no_members)
        self.assertFalse(self.posts)
    def test_activation_is_ordered_and_repeat_does_not_duplicate_events(self):
        record=self.create();self.writes=[];graph.activate(record,self.registry,self.api)
        promotions=[self.issues[p.rsplit('/',1)[-1]]['billingCode'].rsplit(':',1)[-1] for p,m,b in self.writes if m=='PATCH' and 'status' in b]
        self.assertEqual(promotions,['approve','review','develop','plan'])
        before=len([x for x in self.writes if x[1]=='PATCH']);graph.activate(record,self.registry,self.api)
        self.assertEqual(len([x for x in self.writes if x[1]=='PATCH']),before)
    def test_project_enrollment_preserves_other_policy_and_dry_run(self):
        self.workspaces[0]['isPrimary']=True
        self.project['executionWorkspacePolicy']={'enabled':True,'defaultMode':'isolated_workspace','sharedWorkspaceConcurrency':'allow'}
        self.writes=[];enroll_project(self.pid,'company',self.root,self.api,False)
        self.assertFalse([w for w in self.writes if w[1]!='GET'])
        def api(path,method='GET',body=None):
            if method=='PATCH':self.project.update(body);return copy.deepcopy(self.project)
            return self.api(path,method,body)
        value=enroll_project(self.pid,'company',self.root,api,True)
        self.assertEqual(value['project_workspace_id'],self.wid)
        self.assertEqual(self.project['executionWorkspacePolicy']['defaultMode'],'isolated_workspace')
        self.assertEqual(self.project['executionWorkspacePolicy']['sharedWorkspaceConcurrency'],'serialize')
        with self.assertRaisesRegex(ValueError,'another company'):enroll_project(self.pid,'other',self.root,self.api,True)

if __name__=='__main__':unittest.main()
