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

from setup_work_hermes import hermes_config, SLOTS, write, paperclip_context, repair_paperclip_shim
from setup_work_desktop import desktop_config, ui_readiness

loader=importlib.machinery.SourceFileLoader('work_ai',str(Path(__file__).parents[1]/'shared/bin/work-ai'))
spec=importlib.util.spec_from_loader(loader.name,loader)
ai=importlib.util.module_from_spec(spec);loader.exec_module(ai)
ROUTES={key:dict(name=key,url=f'http://127.0.0.1:{port}/v1',model=model,context=ctx)
        for key,port,model,ctx in [('local',8080,'gemma-4-26b-a4b',131072),
          ('1',8001,'glm-5.3-flash',262144),('2',8002,'openai/gpt-oss-120b',49152)]}
CFG=dict(routes=ROUTES,scope='workspace',workspace='/tmp/company',enterprise_org='test-org')


class WorkRoutes(unittest.TestCase):
    def test_backend_setup_does_not_imply_desktop_plugins_are_enabled(self):
        self.assertEqual(ui_readiness({})['desktop_plugins'],'action-required')
        confirmed=ui_readiness({},True)
        self.assertEqual(confirmed['desktop_plugins'],'user-confirmed')
        self.assertEqual(ui_readiness(confirmed)['desktop_plugins'],'user-confirmed')
        self.assertEqual(confirmed['browser_plugins'],'check-per-browser')

    def test_desktop_listener_is_private_and_keeps_gateway_settings(self):
        cfg=desktop_config({'webapp':{'host':'0.0.0.0','public_url':'https://example.invalid'},
                            'gateway':{'max_concurrent_sessions':2}})
        self.assertEqual(cfg['webapp'],{'enabled':True,'host':'127.0.0.1','port':9120,'public_url':''})
        self.assertEqual(cfg['gateway']['max_concurrent_sessions'],2)
        self.assertTrue(cfg['gateway']['multiplex_profiles'])

    def test_native_binary_is_not_treated_as_a_shell_shim(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'cli';path.write_bytes(b'\x00\xff\xfe\x80')
            repair_paperclip_shim(path,path,True)
            self.assertEqual(path.read_bytes(),b'\x00\xff\xfe\x80')

    def test_paperclip_stale_node_pin_repaired_without_replacing_payload(self):
        with tempfile.TemporaryDirectory() as tmp:
            h=Path(tmp);shim=h/'paperclip';node=h/'node'
            shim.write_text('#!/bin/sh\nexec /opt/homebrew/Cellar/node/0/bin/node company-cli "$@"\n');shim.chmod(0o700)
            node.write_text('#!/bin/sh\nprintf "%s\\n" "$*"\n');node.chmod(0o700)
            self.assertNotEqual(subprocess.run([str(shim),'--version'],capture_output=True).returncode,0)
            repair_paperclip_shim(shim,node,False)
            self.assertNotEqual(subprocess.run([str(shim),'--version'],capture_output=True).returncode,0)
            repair_paperclip_shim(shim,node,True)
            result=subprocess.run([str(shim),'--version'],capture_output=True,text=True)
            self.assertEqual(result.returncode,0)
            self.assertEqual(result.stdout.strip(),'company-cli --version')
            self.assertIn('Cellar/node/0',next(h.glob('paperclip.backup.*')).read_text())

    def test_paperclip_uses_company_context_and_refuses_route_overrides(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'context.json';p.write_text(json.dumps(paperclip_context(
                {'company_id':'12345678-1234-1234-1234-123456789abc'},'http://127.0.0.1:13100')))
            cfg=dict(CFG,paperclip='/private/cli',paperclip_context=str(p),
                     paperclip_api_base='http://127.0.0.1:13100')
            argv=ai.paperclip_args(cfg,['agent','list','--json'])
            self.assertEqual(argv[-6:],['--context',str(p),'--profile','company',
                                       '--api-base','http://127.0.0.1:13100'])
            self.assertIn('--company-id',argv)
            self.assertEqual(argv[argv.index('--company-id')+1],'12345678-1234-1234-1234-123456789abc')
            self.assertNotIn('--company-id',ai.paperclip_args(cfg,['issue','get','ZEN-1']))
            for extra in [['--profile','personal'],['--api-base=https://other.invalid'],
                          ['-C','other'],['-Cother'],['-c','personal.json'],['-cpersonal.json'],['-d/tmp/other']]:
                with self.assertRaises(ValueError):ai.paperclip_args(cfg,['agent','list',*extra])
            p.unlink()
            with self.assertRaises(ValueError):ai.paperclip_args(cfg,['agent','list'])

    def test_paperclip_context_keeps_company_identity_without_credentials(self):
        d=paperclip_context({'company_id':'12345678-1234-1234-1234-123456789abc'},'http://127.0.0.1:3100')
        self.assertEqual(d['profiles']['company']['companyId'],'12345678-1234-1234-1234-123456789abc')
        self.assertEqual(set(d['profiles']['company']),{'apiBase','companyId','persona'})
        self.assertEqual(d['currentProfile'],'company')
        with self.assertRaises(ValueError):paperclip_context({'company_id':'not-a-company'},'http://127.0.0.1:3100')

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
