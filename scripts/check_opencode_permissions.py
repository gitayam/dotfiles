#!/usr/bin/env python3
"""Exercise OpenCode's real permission evaluator without executing model tools."""
import argparse
import json
import os
from pathlib import Path
import subprocess


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("session", help="Existing disposable session in the intended project location")
    p.add_argument("--agent", choices=("scout", "reviewer"), required=True,
                   help="Role of this actual child session")
    p.add_argument("--cwd", type=Path, required=True)
    args = p.parse_args()
    cwd = args.cwd.resolve()
    env = dict(os.environ, PWD=str(cwd))
    loaded = subprocess.run(["opencode", "api", "get", f"/api/session/{args.session}"],
                            cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                            capture_output=True, text=True, timeout=10)
    session = json.loads(loaded.stdout)
    if session.get("data", session).get("agent") != args.agent:
        raise SystemExit("Use the actual child session for this role")
    cases = [("read", "calc.py", "allow"), ("glob", "*.py", "allow"),
             ("edit", "calc.py", "deny"), ("shell", "printf canary", "deny"),
             ("subagent", "scout", "deny"), ("execute", "*", "deny"),
             ("unregistered_mcp_write", "*", "deny"),
             ("external_directory", "/private/tmp/unrelated/*", "deny"),
             ("read", ".env", "deny"), ("read", "nested/.env.production", "deny"),
             ("read", ".env.example", "allow"), ("grep", "anything", "deny")]
    receipts = []
    for role in (args.agent,):
        for action, resource, expected in cases:
            body = json.dumps({"agent": role, "action": action, "resources": [resource]})
            result = subprocess.run(["opencode", "api", "post", f"/api/session/{args.session}/permission", "--data", body],
                                    cwd=cwd, env=env,
                                    stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10)
            response = json.loads(result.stdout)
            effect = response.get("data", response).get("effect")
            receipts.append({"agent": role, "action": action, "resource": resource,
                             "expected": expected, "actual": effect, "passed": effect == expected})
    print(json.dumps(receipts, indent=2))
    if not all(r["passed"] for r in receipts):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
