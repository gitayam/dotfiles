"""Company route and configuration regression checks; no network or real home writes."""
import importlib.machinery
import importlib.util
import os
import sys
import io
from contextlib import redirect_stdout
import json
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from setup_work_hermes import hermes_config, SLOTS, write, paperclip_context, repair_paperclip_shim, company_shell_text, model_policy, existing_tailscale_cli
from setup_work_desktop import desktop_config, ui_readiness, worker_config

loader=importlib.machinery.SourceFileLoader('work_ai',str(Path(__file__).parents[1]/'shared/bin/work-ai'))
spec=importlib.util.spec_from_loader(loader.name,loader)
ai=importlib.util.module_from_spec(spec);loader.exec_module(ai)
ROUTES={key:dict(name=key,url=f'http://127.0.0.1:{port}/v1',model=model,context=ctx)
        for key,port,model,ctx in [('local',8080,'gemma-4-26b-a4b',131072),
          ('1',8001,'glm-5.3-flash',262144),('2',8002,'openai/gpt-oss-120b',49152)]}
CFG=dict(routes=ROUTES,scope='workspace',workspace='/tmp/company',enterprise_org='test-org')


class WorkRoutes(unittest.TestCase):
    def test_server_names_preserve_legacy_routes_and_explicit_child_limits(self):
        cfg=hermes_config({'delegation':{'max_iterations':7,'max_concurrent_children':2}},ROUTES,Path('/tmp/company'))
        for old,new in [('z1','server1'),('z2','server2')]:
            self.assertEqual(cfg['providers'][old]['base_url'],cfg['providers'][new]['base_url'])
            self.assertEqual(cfg['providers'][old]['models'],cfg['providers'][new]['models'])
        self.assertEqual(cfg['delegation']['max_iterations'],7)
        self.assertEqual(cfg['delegation']['max_concurrent_children'],2)
        self.assertEqual(cfg['delegation']['oneshot_max_children'],6)
        self.assertEqual(cfg['delegation']['max_spawn_depth'],1)
        self.assertTrue(cfg['delegation']['worktree_isolation'])
        self.assertNotIn('subagent_auto_approve',cfg['delegation'])
        local=hermes_config({},ROUTES,Path('/tmp/company'),delegation_model='local')
        self.assertEqual(local['delegation']['provider'],'local')
        for bad in ['2','unknown',[]]:
            with self.assertRaises(ValueError):model_policy(dict(routes=ROUTES,delegation_model=bad))

    def test_new_and_legacy_cli_aliases_pin_every_claude_model_tier(self):
        cfg=dict(CFG,claude='/approved/claude')
        for alias,key in [('zf-server1','1'),('zf-z1','1'),('zf-server2','2'),('zf-z2','2')]:
            with patch.object(ai,'config',return_value=cfg),patch.object(sys,'argv',[alias]),patch.object(ai.os,'execve',side_effect=RuntimeError('captured')) as run:
                with self.assertRaisesRegex(RuntimeError,'captured'):ai.main()
            env=run.call_args.args[2]
            self.assertEqual(env['ANTHROPIC_BASE_URL'],ROUTES[key]['url'].removesuffix('/v1'))
            self.assertEqual(env['CLAUDE_CODE_SUBAGENT_MODEL'],ROUTES[key]['model'])
            self.assertIsNone(ai.check_claude(cfg,env))
        for route,key in [('server1','1'),('server2','2'),('1','1'),('2','2')]:
            with patch.object(ai,'config',return_value=cfg),patch.object(sys,'argv',['zf-zq',route,'synthetic']),patch.object(ai,'request',return_value={'choices':[{'message':{'content':'ok'}}]}) as req,redirect_stdout(io.StringIO()):
                self.assertEqual(ai.main(),0)
            self.assertEqual(req.call_args.args[1]['model'],ROUTES[key]['model'])

    def test_existing_tailscale_cli_is_opt_in_and_preserves_other_installations(self):
        with tempfile.TemporaryDirectory() as tmp:
            h=Path(tmp);app=h/'Tailscale';app.write_text('fixture')
            path=h/'.local/bin/tailscale'
            existing_tailscale_cli(h,False,app)
            self.assertFalse(path.exists())
            existing_tailscale_cli(h,True,app)
            self.assertEqual(path.resolve(),app.resolve())
            existing_tailscale_cli(h,True,app)
            self.assertFalse(list(path.parent.glob('*.backup.*')))
            path.unlink();path.write_text('unmanaged CLI')
            existing_tailscale_cli(h,True,app)
            self.assertEqual(path.read_text(),'unmanaged CLI')
            path.unlink();path.symlink_to(h/'missing-executable')
            existing_tailscale_cli(h,True,app)
            self.assertEqual(path.readlink(),h/'missing-executable')

    def test_task_assignments_keep_independent_fallbacks_and_worker_budgets(self):
        policy={'role_models':{'zf-planner':'1'},
                'auxiliary_models':{'title_generation':'local','review':'1'},'routes':ROUTES}
        roles,aux=model_policy(policy)
        cfg=worker_config({'agent':{'max_turns':24}},ROUTES,Path('/tmp/company'),roles['zf-planner'],aux)
        self.assertEqual(cfg['model']['provider'],'server1')
        self.assertEqual(cfg['agent']['max_turns'],24)
        self.assertEqual(cfg['auxiliary']['title_generation']['provider'],'local')
        self.assertEqual(cfg['auxiliary']['title_generation']['fallback_chain'],[{'provider':'server1','model':ROUTES['1']['model']}])
        self.assertEqual(cfg['auxiliary']['review']['provider'],'server1')
        self.assertEqual(cfg['auxiliary']['review']['fallback_chain'],[{'provider':'local','model':ROUTES['local']['model']}])
        self.assertEqual(cfg['auxiliary']['vision']['fallback_chain'],[])
        self.assertEqual(cfg['delegation']['provider'],'server1')

    def test_task_policy_rejects_short_context_unverified_vision_and_typos(self):
        for policy in [{'role_models':{'zf-planner':'2'}},
                       {'role_models':{'zf-plannner':'1'}},
                       {'auxiliary_models':{'vision':'1'}},
                       {'auxiliary_models':{'review':'openrouter'}},
                       {'auxiliary_models':{'typo':'local'}},
                       {'auxiliary_models':[]},
                       {'role_models':{'zf-reviewer':[]}}]:
            with self.assertRaises(ValueError):model_policy(dict(routes=ROUTES,**policy))

    def test_unattended_roles_keep_approval_policy_and_usable_tools(self):
        policy={'mode':'off','single_query_mode':'ask','deny':['sentinel']}
        cfg=worker_config({'approvals':policy},ROUTES,Path('/tmp/company'),'local')
        self.assertEqual(cfg['approvals'],policy)
        self.assertNotIn('code_execution',cfg['platform_toolsets']['cli'])
        self.assertTrue({'terminal','file','kanban','skills'}.issubset(cfg['platform_toolsets']['cli']))
        self.assertIn('code_execution',hermes_config({},ROUTES,Path('/tmp/company'))['platform_toolsets']['cli'])
        self.assertEqual(cfg['fallback_providers'],[{'provider':'server1','model':'glm-5.3-flash'}])
        self.assertEqual(cfg['agent']['run_budget_seconds'],900)
        self.assertEqual(cfg['agent']['max_turns'],16)
        custom=worker_config({'agent':{'run_budget_seconds':300,'max_turns':8}},ROUTES,Path('/tmp/company'),'local')
        self.assertEqual(custom['agent']['run_budget_seconds'],300)
        self.assertEqual(custom['agent']['max_turns'],8)

    def test_company_shell_selects_managed_cli_after_brew_and_preserves_user_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            home=Path(tmp);managed=home/'.local/bin';managed.mkdir(parents=True)
            brew=home/'brew';brew.mkdir()
            for folder,result in [(managed,'managed'),(brew,'brew')]:
                exe=folder/'hermes';exe.write_text('#!/bin/sh\necho '+result+'\n');exe.chmod(0o700)
            original=f'export PATH="{brew}:$PATH"\n# user setting\n'
            configured=company_shell_text(original)
            shell=home/'shell.zsh';shell.write_text(configured)
            run=subprocess.run(['zsh','-f','-c','source "$1"; hermes','_',str(shell)],
                env=dict(os.environ,HOME=str(home)),capture_output=True,text=True)
            self.assertEqual(run.stdout.strip(),'managed')
            self.assertIn('# user setting',configured)
            self.assertEqual(company_shell_text(configured),configured)
            changed=company_shell_text(configured+'# later user setting\n')
            self.assertIn('# later user setting',changed)
            self.assertEqual(changed.count('# >>> company managed launchers >>>'),1)

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

    def test_main_auxiliary_and_delegation_fallback_stays_on_approved_routes(self):
        cfg=hermes_config({'delegation':{'provider':'llamacpp','model':'qwen'},
            'fallback_providers':[{'provider':'openrouter'}],
            'approvals':{'mode':'off','deny':['sentinel']}},ROUTES,Path('/tmp/company'),company_roles=True)
        self.assertEqual(cfg['model']['provider'],'local')
        self.assertEqual(cfg['delegation']['provider'],'server1')
        expected=[{'provider':'server1','model':'glm-5.3-flash'}]
        self.assertEqual(cfg['fallback_providers'],expected)
        self.assertNotIn('fallback_model',cfg)
        self.assertEqual(cfg['delegation']['fallback_providers'],[{'provider':'local','model':ROUTES['local']['model']}])
        for slot in SLOTS:
            self.assertEqual(cfg['auxiliary'][slot]['base_url'],ROUTES['local']['url'])
            self.assertEqual(cfg['auxiliary'][slot]['fallback_chain'],[] if slot=='vision' else expected)
        self.assertEqual(cfg['providers']['z2']['models']['openai/gpt-oss-120b']['context_length'],49152)
        self.assertTrue(cfg['memory']['write_approval'])
        self.assertEqual(cfg['approvals'],{'mode':'off','deny':['sentinel']})
        self.assertEqual(cfg['agent']['api_max_retries'],1)
        self.assertEqual(cfg['agent']['auto_recovery_cycles'],1)
        self.assertEqual(cfg['kanban']['default_assignee'],'zf-developer')
        self.assertEqual(cfg['kanban']['orchestrator_profile'],'zf-planner')

    def test_fallback_uses_other_approved_route_and_rejects_short_main_context(self):
        cfg=hermes_config({},ROUTES,Path('/tmp/company'),'1')
        self.assertEqual(cfg['fallback_providers'],[{'provider':'local','model':'gemma-4-26b-a4b'}])
        self.assertEqual(cfg['auxiliary']['vision']['provider'],'local')
        self.assertEqual(cfg['auxiliary']['vision']['fallback_chain'],[])
        with self.assertRaises(ValueError):hermes_config({},ROUTES,Path('/tmp/company'),'2')
        routes={key:dict(value) for key,value in ROUTES.items()};routes['1']['context']=49152
        cfg=hermes_config({},routes,Path('/tmp/company'))
        self.assertEqual(cfg['fallback_providers'],[])

    def test_personal_workspace_does_not_invent_work_mac_assignees(self):
        cfg=hermes_config({},ROUTES,Path('/tmp/company'))
        self.assertNotIn('default_assignee',cfg['kanban'])
        self.assertNotIn('orchestrator_profile',cfg['kanban'])

    def test_dry_run_and_backup_preserve_user_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            f=Path(tmp)/'config';f.write_text('original')
            write(f,'new',False);self.assertEqual(f.read_text(),'original')
            write(f,'new',True);self.assertEqual(f.read_text(),'new')
            self.assertEqual(next(Path(tmp).glob('config.backup.*')).read_text(),'original')
            write(f,'new',True)
            self.assertEqual(len(list(Path(tmp).glob('config.backup.*'))),1)


if __name__=='__main__':unittest.main()
