#!/usr/bin/env python3
"""Offline boundary checks for the installer and native task launcher."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
LAUNCHER = ROOT / "shared/bin/oc-task"


class SetupTests(unittest.TestCase):
    def load_gateway(self):
        loader = importlib.machinery.SourceFileLoader("cc_opencode", str(ROOT / "shared/bin/cc-opencode"))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        module = importlib.util.module_from_spec(spec)
        loader.exec_module(module)
        return module

    def test_gateway_key_precedence_and_private_file(self):
        gateway = self.load_gateway()
        with tempfile.TemporaryDirectory() as tmp:
            key = Path(tmp) / "key"
            key.write_text("synthetic-file-key")
            key.chmod(0o600)
            with patch.object(gateway, "KEY_FILE", key), patch.dict(os.environ, {"OPENCODE_GO_API_KEY": "synthetic-env-key"}, clear=True):
                self.assertEqual(gateway.credential(), ("synthetic-env-key", "OPENCODE_GO_API_KEY"))
            with patch.object(gateway, "KEY_FILE", key), patch.dict(os.environ, {}, clear=True):
                self.assertEqual(gateway.credential()[0], "synthetic-file-key")
                key.chmod(0o644)
                with self.assertRaises(SystemExit):
                    gateway.credential()

    def test_gateway_keeps_token_out_of_argv_and_clears_provider_routes(self):
        gateway = self.load_gateway()
        env = {"ANTHROPIC_API_KEY": "synthetic-old", "ANTHROPIC_BASE_URL": "https://wrong.invalid",
               "CLAUDE_CODE_USE_BEDROCK": "1", "CLAUDE_CODE_OAUTH_TOKEN": "synthetic-oauth"}
        with patch.dict(os.environ, env, clear=True), patch.object(sys, "argv", ["cc-opencode", "-p", "fixture"]), \
             patch.object(gateway, "credential", return_value=("synthetic-new-token", "fixture")), \
             patch.object(gateway.shutil, "which", return_value="/synthetic/claude"), \
             patch.object(gateway.os, "execve") as execute:
            gateway.main()
            binary, argv, child_env = execute.call_args.args
            self.assertNotIn("synthetic-new-token", json.dumps(argv))
            self.assertEqual(child_env["ANTHROPIC_AUTH_TOKEN"], "synthetic-new-token")
            self.assertNotIn("ANTHROPIC_API_KEY", child_env)
            self.assertNotIn("CLAUDE_CODE_OAUTH_TOKEN", child_env)
            self.assertNotIn("CLAUDE_CODE_USE_BEDROCK", child_env)
            self.assertEqual(child_env["ANTHROPIC_BASE_URL"], gateway.ENDPOINT)
            self.assertEqual(child_env["CLAUDE_CODE_SUBAGENT_MODEL"], "qwen3.7-plus")

    def test_install_preserves_auth_adjacent_files_and_backs_up_corruption(self):
        loader = importlib.machinery.SourceFileLoader("installer", str(ROOT / "scripts/install_opencode.py"))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        installer = importlib.util.module_from_spec(spec)
        loader.exec_module(installer)
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            old = home / ".claude/skills/team-swarm/SKILL.md"
            old.parent.mkdir(parents=True)
            old.write_bytes(b"\0" * 20)
            adjacent = old.parent / "operator-note.txt"
            adjacent.write_text("preserve")
            service = home / ".config/opencode/service.json"
            service.parent.mkdir(parents=True)
            service.write_text("synthetic-placeholder")
            receipt = installer.install(home)
            self.assertEqual(service.read_text(), "synthetic-placeholder")
            self.assertEqual(adjacent.read_text(), "preserve")
            self.assertNotIn(b"\0", old.read_bytes())
            self.assertEqual((Path(receipt["backup"]) / old.relative_to(home)).read_bytes(), b"\0" * 20)
            self.assertEqual(old.stat().st_mode & 0o777, 0o600)
            self.assertEqual((home / ".local/bin/oc-task").stat().st_mode & 0o777, 0o700)

    def fake_run(self, *, write=False, export=True, check=True):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cwd = root / "workspace"
            cwd.mkdir()
            binary = root / "opencode"
            binary.write_text(f'''#!{sys.executable}
import json,os,pathlib,sys
if sys.argv[1]=='run':
    assert pathlib.Path.cwd()==pathlib.Path(os.environ['PWD'])
    {'pathlib.Path("answer.txt").write_text("correct")' if write else 'pass'}
    print(json.dumps({{"type":"text","sessionID":"synthetic","part":{{"text":"DONE"}}}}))
else:
    print(json.dumps({{"messages":{ '[{"model":{"providerID":"opencode-go","id":"qwen3.7-plus"},"tokens":{"cache":{"read":3,"write":0}},"cost":0.01}]' if export else '[]' }}}))
''')
            binary.chmod(0o700)
            argv = [sys.executable, str(LAUNCHER), "--cwd", str(cwd), "--timeout", "5",
                    "--artifacts", str(root / "evidence"), "--prompt", "synthetic"]
            if check:
                argv += ["--check-command", json.dumps([sys.executable, "-I", "-c",
                         "from pathlib import Path;assert Path('answer.txt').read_text()=='correct'"])]
            proc = subprocess.run(argv, env=dict(os.environ, PATH=str(root)+os.pathsep+os.environ["PATH"], PWD="/"),
                                  capture_output=True, text=True, timeout=10)
            return proc.returncode, json.loads((root / "evidence/result.json").read_text())

    def test_done_exit_zero_without_artifact_is_failure(self):
        rc, receipt = self.fake_run()
        self.assertEqual(rc, 2)
        self.assertEqual(receipt["exit"], 0)
        self.assertEqual(receipt["acceptance"], "failed")

    def test_actual_artifact_check_and_model_identity_accept(self):
        rc, receipt = self.fake_run(write=True)
        self.assertEqual(rc, 0)
        self.assertTrue(receipt["complete"])
        self.assertEqual(receipt["retained_parent_model_turns"], 1)

    def test_missing_usage_cannot_qualify_model(self):
        rc, receipt = self.fake_run(write=True, export=False)
        self.assertEqual(rc, 2)
        self.assertFalse(receipt["complete"])

    def test_unchecked_task_never_claims_acceptance(self):
        rc, receipt = self.fake_run(write=True, check=False)
        self.assertEqual(rc, 2)
        self.assertEqual(receipt["acceptance"], "unchecked")

    def test_deadline_stops_child_even_when_parent_exits_on_term(self):
        loader = importlib.machinery.SourceFileLoader("oc_task", str(LAUNCHER))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        launcher = importlib.util.module_from_spec(spec)
        loader.exec_module(launcher)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            marker = root / "escaped"
            child = "import signal,time,pathlib;signal.signal(signal.SIGTERM,signal.SIG_IGN);time.sleep(1);pathlib.Path('escaped').touch()"
            parent = "import subprocess,sys,time;subprocess.Popen([sys.executable,'-c',sys.argv[1]]);time.sleep(10)"
            result = launcher.bounded([sys.executable, "-c", parent, child], cwd=root,
                                      env=dict(os.environ, PWD=str(root)), timeout=0.2,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.assertTrue(result["deadline_reached"])
            # This wait is an offline failure-boundary test, not production polling.
            import time
            time.sleep(1.1)
            self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
