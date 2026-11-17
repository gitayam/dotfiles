"""Company route and configuration regression checks; no network or real home writes."""
import importlib.machinery
import importlib.util
import os
import json
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from setup_work_hermes import hermes_config, SLOTS, write

loader=importlib.machinery.SourceFileLoader('work_ai',str(Path(__file__).parents[1]/'shared/bin/work-ai'))
spec=importlib.util.spec_from_loader(loader.name,loader)
ai=importlib.util.module_from_spec(spec);loader.exec_module(ai)
ROUTES={key:dict(name=key,url=f'http://127.0.0.1:{port}/v1',model=model,context=ctx)
        for key,port,model,ctx in [('local',8080,'gemma-4-26b-a4b',131072),
          ('1',8001,'glm-5.3-flash',262144),('2',8002,'openai/gpt-oss-120b',49152)]}
CFG=dict(routes=ROUTES,scope='workspace',workspace='/tmp/company',enterprise_org='test-org')


class WorkRoutes(unittest.TestCase):
    def test_device_refresh_skips_personal_alias_installer(self):
        repo=Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as tmp:
            h=Path(tmp);cfg=h/'zenithflow/.workstation/config.json';cfg.parent.mkdir(parents=True)
            cfg.write_text(json.dumps({'scope':'device'}))
            b=h/'bin';b.mkdir();uv=b/'uv';uv.write_text('#!/bin/sh\nprintf "WORK_REFRESH %s\\n" "$*"\n');uv.chmod(0o700)
            env=dict(os.environ,HOME=str(h),DOTFILES=str(repo),PATH=str(b)+os.pathsep+os.environ['PATH'])
            r=subprocess.run(['bash',str(repo/'scripts/install-claude-aliases.sh')],env=env,capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertIn('--from-config',r.stdout)
            self.assertFalse((h/'.local/bin/claude-switch').exists())

    def test_device_registry_overrides_stale_personal_registry(self):
        repo=Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as tmp:
            h=Path(tmp);cfg=h/'.config/ai-policy/device-models.conf';cfg.parent.mkdir(parents=True)
            cfg.write_text('2,gptoss chat dl 127.0.0.1:8008 8002 openai/gpt-oss-120b -\n')
            b=h/'bin';b.mkdir();autossh=b/'autossh'
            autossh.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n');autossh.chmod(0o700)
            env=dict(os.environ,HOME=str(h),ZMODELS_CONF=str(repo/'shared/llm/models.conf'),PATH=str(b)+os.pathsep+os.environ['PATH'])
            r=subprocess.run(['bash',str(repo/'shared/bin/claude-z'),'tunnel-run','dl'],env=env,capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertIn('8002:127.0.0.1:8008',r.stdout)
            self.assertNotIn('8003:',r.stdout)

    def test_approved_routes_and_tiers(self):
        for key in ROUTES:
            env=ai.model_env(CFG,key,{})
            self.assertIsNone(ai.check_claude(CFG,env))
            env['ANTHROPIC_DEFAULT_HAIKU_MODEL']='qwen3'
            self.assertIsNotNone(ai.check_claude(CFG,env))

    def test_no_arbitrary_localhost_or_cloud_vendor_route(self):
        for url in ['https://api.z.ai','https://api.anthropic.com',
                    'http://127.0.0.1:9999','http://127.0.0.1.evil.invalid:8001']:
            self.assertIsNotNone(ai.check_claude(CFG,dict(ANTHROPIC_BASE_URL=url,
                                                        ANTHROPIC_MODEL='glm-5.3-flash')))

    def test_api_and_alternate_cloud_modes_denied(self):
        for key in ['ANTHROPIC_API_KEY','CLAUDE_CODE_USE_VERTEX','CLAUDE_CODE_USE_BEDROCK']:
            env=ai.model_env(CFG,'1',{});env[key]='set'
            self.assertIsNotNone(ai.check_claude(CFG,env))

    def test_missing_enterprise_account_is_not_permission(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(ai.Path,'home',return_value=Path(tmp)):
            self.assertIsNotNone(ai.check_claude(CFG,{}))

    def test_enterprise_org_and_subscription_both_required(self):
        import json
        with tempfile.TemporaryDirectory() as tmp,patch.object(ai.Path,'home',return_value=Path(tmp)):
            p=Path(tmp)/'.claude.json'
            for org,tier,allowed in [('other-org','claude_enterprise',False),
                                    ('test-org','claude_pro',False),('test-org','claude_enterprise',True)]:
                p.write_text(json.dumps({'oauthAccount':{'organizationUuid':org,'organizationType':tier}}))
                self.assertEqual(ai.check_claude(CFG,{}) is None,allowed)

    def test_scope_and_personal_default_separation(self):
        self.assertTrue(ai.in_scope(CFG,'/tmp/company/project'))
        self.assertTrue(ai.in_scope(dict(CFG,scope='device'),'/tmp/personal'))
        with tempfile.TemporaryDirectory() as tmp:
            self.assertFalse(ai.in_scope(CFG,tmp))

    def test_launcher_scrubs_inherited_personal_routing(self):
        with patch.dict(os.environ,{'OPENAI_API_KEY':'test','ANTHROPIC_API_KEY':'test',
                                    'CLAUDE_CODE_USE_VERTEX':'1','HERMES_HOME':'/personal'}):
            env=ai.clean_env(CFG)
        for key in ['OPENAI_API_KEY','ANTHROPIC_API_KEY','CLAUDE_CODE_USE_VERTEX','HERMES_HOME']:
            self.assertNotIn(key,env)

    def test_main_auxiliary_and_delegation_have_no_cloud_fallback(self):
        cfg=hermes_config({'delegation':{'provider':'llamacpp','model':'qwen'},
            'fallback_providers':[{'provider':'openrouter'}]},ROUTES,Path('/tmp/company'))
        self.assertEqual(cfg['model']['provider'],'local')
        self.assertEqual(cfg['delegation']['provider'],'local')
        self.assertEqual(cfg['fallback_providers'],[])
        for slot in SLOTS:
            self.assertEqual(cfg['auxiliary'][slot]['base_url'],ROUTES['local']['url'])
            self.assertEqual(cfg['auxiliary'][slot]['fallback_chain'],[])
        self.assertEqual(cfg['providers']['z2']['models']['openai/gpt-oss-120b']['context_length'],49152)
        self.assertTrue(cfg['memory']['write_approval'])

    def test_dry_run_and_backup_preserve_user_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            f=Path(tmp)/'config';f.write_text('original')
            write(f,'new',False);self.assertEqual(f.read_text(),'original')
            write(f,'new',True);self.assertEqual(f.read_text(),'new')
            self.assertEqual(next(Path(tmp).glob('config.backup.*')).read_text(),'original')
            write(f,'new',True)
            self.assertEqual(len(list(Path(tmp).glob('config.backup.*'))),1)


if __name__=='__main__':unittest.main()
