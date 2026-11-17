import importlib.util
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import urllib.error
from unittest.mock import patch

from setup_work_hermes import install_issue_strategy

ROOT=Path(__file__).parents[1]
SPEC=importlib.util.spec_from_file_location('collector',ROOT/'shared/skills/issue-strategy/scripts/collect_github.py')
api=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(api)


class IssueEvidence(unittest.TestCase):
    def test_native_entrypoints_keep_identical_workflow_and_helpers(self):
        with tempfile.TemporaryDirectory() as temp:
            installs={}
            for platform in ['generic','claude-code','hermes','codex']:
                out=Path(temp)/platform
                install_issue_strategy(out,True,platform);installs[platform]=out
                self.assertTrue((out/'WORKFLOW.md').is_file())
                self.assertFalse((out/'adapters').exists())
                before={str(p.relative_to(out)):p.read_bytes() for p in out.rglob('*') if p.is_file()}
                install_issue_strategy(out,True,platform)
                self.assertEqual(before,{str(p.relative_to(out)):p.read_bytes() for p in out.rglob('*') if p.is_file()})
            for name in ['WORKFLOW.md','references/decision-brief.md','scripts/collect_github.py']:
                self.assertEqual(len({(p/name).read_bytes() for p in installs.values()}),1)
            self.assertEqual(len({(p/'SKILL.md').read_bytes() for p in installs.values()}),4)
            self.assertIn('$ARGUMENTS',(installs['claude-code']/'SKILL.md').read_text())
            self.assertNotIn('$ARGUMENTS',(installs['hermes']/'SKILL.md').read_text())
            self.assertIn('file_path="WORKFLOW.md"',(installs['hermes']/'SKILL.md').read_text())

    def test_cli_does_not_report_success_for_an_inaccessible_open_list(self):
        class Client:
            base='https://api.github.com/repos/example/repo'
            def get(self,path,query=None):
                if not path:return {'default_branch':'main'}
                if path.startswith('/commits/'):return {'sha':'abc'}
                raise api.ReadError('HTTP 403')
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp)/'snapshot'
            argv=['collect','--repo','example/repo','--repo-dir',temp,'--output',str(out)]
            with patch.object(api.sys,'argv',argv),patch.object(api,'credential',return_value='test'),patch.object(api,'Client',return_value=Client()),contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(api.main(),2)
            m=json.loads((out/'manifest.json').read_text())
            self.assertFalse(m['coverage']['open_issues']['complete'])

    def test_pr_only_page_does_not_end_issue_pagination(self):
        def get(path,query):
            if query['page']==1:return [{'number':n,'pull_request':{}} for n in range(100)]
            return [{'number':101,'title':'A customer problem','labels':[]}]
        class Client:
            base='https://api.github.com/repos/example/repo'
            def get(self,path,query=None):
                if not path:return {'default_branch':'main'}
                if path.startswith('/commits/'):return {'sha':'abc'}
                return get(path,query)
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp)/'snapshot';m=api.collect(Client(),out)
            self.assertEqual(m['open_issue_count'],1)
            self.assertTrue(m['coverage']['open_issues']['complete'])
            self.assertEqual(m['coverage']['open_issues']['pages'],2)
            self.assertEqual(json.loads((out/'open-issues.json').read_text())[0]['number'],101)
            self.assertEqual(out.stat().st_mode & 0o777,0o700)
            self.assertTrue(all(p.stat().st_mode & 0o777==0o600 for p in out.iterdir()))

    def test_page_failure_retains_evidence_and_marks_incomplete(self):
        def get(path,query):
            if query['page']==1:return list(range(100))
            raise api.ReadError('HTTP 403')
        rows,coverage=api.pages(get,'/issues')
        self.assertEqual(len(rows),100);self.assertFalse(coverage['complete'])
        self.assertEqual(coverage['pages'],1)

    def test_page_budget_is_not_claimed_as_complete(self):
        _,coverage=api.pages(lambda path,query:list(range(100)),'/issues',max_pages=1)
        self.assertFalse(coverage['complete'])

    def test_inaccessible_dependencies_are_not_empty_verified_graph(self):
        class Client:
            base='https://api.github.com/repos/example/repo'
            def get(self,path,query=None):
                if not path:return {'default_branch':'main'}
                if path.startswith('/commits/'):return {'sha':'abc'}
                if path=='/issues/7':return {'number':7,'title':'Problem'}
                if path.endswith('/comments') or path.endswith('/timeline'):return []
                raise api.ReadError('HTTP 404')
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp)/'snapshot';api.collect(Client(),out,[7])
            detail=json.loads((out/'issue-7.json').read_text())
            self.assertTrue(detail['comments']['coverage']['complete'])
            self.assertFalse(detail['blocked_by']['coverage']['complete'])
            self.assertFalse(detail['parent']['available'])

    def test_existing_snapshot_is_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp);(out/'evidence').write_text('keep')
            with self.assertRaises(FileExistsError):api.collect(None,out)
            self.assertEqual((out/'evidence').read_text(),'keep')

    def test_http_diagnostic_does_not_echo_auth_or_response(self):
        client=api.Client('example/repo','private-sentinel')
        with patch.object(client.opener,'open',side_effect=urllib.error.HTTPError(
            client.base,403,'private-sentinel',{},None)):
            with self.assertRaises(api.ReadError) as error:client.get('/issues')
        self.assertNotIn('private-sentinel',str(error.exception))

    def test_issue_skill_install_preserves_existing_file_and_relocates_resources(self):
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp)/'skill'
            install_issue_strategy(out,False);self.assertFalse(out.exists())
            install_issue_strategy(out,True)
            script=out/'scripts/collect_github.py'
            result=subprocess.run([__import__('sys').executable,str(script),'--help'],capture_output=True,text=True)
            self.assertEqual(result.returncode,0);self.assertIn('--repo-dir',result.stdout)
            self.assertTrue((out/'references/decision-brief.md').is_file())
            f=out/'SKILL.md';f.write_text('customized')
            install_issue_strategy(out,True)
            self.assertIn('customized',[p.read_text() for p in out.glob('SKILL.md.backup.*')])
            before=len(list(out.rglob('*.backup.*')));install_issue_strategy(out,True)
            self.assertEqual(before,len(list(out.rglob('*.backup.*'))))


if __name__=='__main__':unittest.main()
