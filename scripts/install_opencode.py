#!/usr/bin/env python3
"""Install only managed OpenCode assets and shared skills, with private backups."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]


def assets(home):
    items = [(p, home / ".config/opencode" / p.relative_to(ROOT / "shared/opencode"))
             for p in sorted((ROOT / "shared/opencode").rglob("*")) if p.is_file()]
    items += [(p, home / ".claude/skills" / p.relative_to(ROOT / "shared/skills"))
              for p in sorted((ROOT / "shared/skills").rglob("*")) if p.is_file()]
    items += [(ROOT / "shared/bin" / name, home / ".local/bin" / name)
              for name in ("cc-opencode", "oc-task")]
    return items


def install(home):
    selected = assets(home)
    for source, _ in selected:
        data = source.read_bytes()
        if not data or b"\0" in data:
            raise ValueError(f"Invalid managed source: {source.relative_to(ROOT)}")
    os.umask(0o077)
    state = home / ".local/state/opencode-setup"
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    backup = Path(tempfile.mkdtemp(prefix=time.strftime("%Y%m%d-%H%M%S-"), dir=state))
    manifest = []
    for source, target in selected:
        data = source.read_bytes()
        if not data or b"\0" in data:
            raise ValueError(f"Invalid managed source: {source.relative_to(ROOT)}")
        target.parent.mkdir(parents=True, exist_ok=True)
        # Back up each replaced file and preserve symlink identity for rollback.
        original = backup / target.relative_to(home)
        existed = target.exists() or target.is_symlink()
        if existed:
            original.parent.mkdir(parents=True, exist_ok=True)
            if target.is_symlink():
                original.symlink_to(os.readlink(target))
            else:
                shutil.copy2(target, original)
                original.chmod(0o600)
        fd, temporary = tempfile.mkstemp(prefix=".opencode-install-", dir=target.parent)
        try:
            with os.fdopen(fd, "wb") as out:
                out.write(data)
            os.chmod(temporary, 0o700 if target.parent == home / ".local/bin" else 0o600)
            os.replace(temporary, target)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        manifest.append({"target": str(target.relative_to(home)), "existed": existed,
                         "sha256": hashlib.sha256(data).hexdigest()})
    receipt = {"backup": str(backup), "source_root": str(ROOT), "files": manifest}
    (backup / "manifest.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({"backup": str(backup), "managed_files": len(manifest)}))
    return receipt


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--home", type=Path, default=Path.home(), help="Installation root; defaults to current user")
    install(p.parse_args().home.resolve())
