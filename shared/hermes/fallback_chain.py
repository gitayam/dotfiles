#!/usr/bin/env python3
"""Report, and with --apply set, a fallback chain for every Hermes profile (used by hermes-setup).

Without one, a model that answers empty, rate-limits or goes down ends the turn: "Empty response
... after 3 retries. No fallback available." (a ZenithFlow workstation, 2026-11-17). Hermes switches
to `fallback_providers` on 429, 5xx, auth errors and empty answers; it has no other model switching
(`smart_model_routing` is a leftover setup-wizard key nothing reads).

  fallback_chain.py HERMES_HOME           report: one line per profile, exit 1 if any chain is empty
  fallback_chain.py HERMES_HOME --apply   set empty chains (backup first), then report

An empty chain becomes the CANDIDATES this profile defines, minus its own primary. Existing
chains are never changed. Prints model names and provider ids only, never keys.
"""
import re
import shutil
import sys
import time
from pathlib import Path

# Self-hosted servers reached through claude-z tunnels (dotfiles shared/llm/models.conf).
CANDIDATES = [('z1', 'glm-5.3-flash'), ('z2', 'openai/gpt-oss-120b')]


def configs(home):
    yield 'default', home / 'config.yaml'
    for path in sorted(home.glob('profiles/*/config.yaml')):
        yield path.parent.name, path


def providers(text):
    section = re.search(r'(?ms)^providers:\n(.*?)(?=^\S)', text + '\nEND')
    return set(re.findall(r'(?m)^  ([A-Za-z0-9_.-]+):\n', section.group(1))) if section else set()


def primary(text):
    match = re.search(r'(?m)^model:\n(?:  .*\n)*?  provider: (\S+)\n(?:  .*\n)*?  default: (\S+)', text)
    if not match:
        match = re.search(r'(?m)^model:\n(?:  .*\n)*?  default: (\S+)\n(?:  .*\n)*?  provider: (\S+)', text)
        return (match.group(2), match.group(1)) if match else None
    return match.group(1), match.group(2)


def chain(text):
    block = re.search(r'(?m)^fallback_providers:(.*)\n((?:  .*\n)*)', text)
    if not block or block.group(1).strip() == '[]':
        return []
    return re.findall(r'(?m)^  - provider: (\S+)\n    model: (\S+)', block.group(2))


def with_chain(text, entries):
    body = 'fallback_providers:\n' + ''.join(f'  - provider: {p}\n    model: {m}\n' for p, m in entries)
    if re.search(r'(?m)^fallback_providers:', text):
        return re.sub(r'(?m)^fallback_providers:.*\n(?:  .*\n)*', body, text, count=1)
    return text.rstrip('\n') + '\n' + body


def main(argv):
    if not argv or len(argv) > 2 or (len(argv) == 2 and argv[1] != '--apply'):
        print(__doc__.split('\n\n')[1], file=sys.stderr)
        return 2
    home, apply = Path(argv[0]).expanduser(), argv[1:] == ['--apply']
    empty, models = 0, {}
    for name, path in configs(home):
        text = path.read_text()
        own, entries = primary(text), chain(text)
        models[name] = own
        if not entries and apply:
            wanted = [(p, m) for p, m in CANDIDATES if p in providers(text) and (own is None or p != own[0])]
            if wanted:
                shutil.copy2(path, path.with_name(path.name + time.strftime('.backup.%Y%m%d%H%M%S')))
                path.write_text(with_chain(text, wanted))
                entries = chain(path.read_text())
        shown = ' -> '.join(f'{p}/{m}' for p, m in entries) or 'none'
        label = f'{own[0]}/{own[1]}' if own else 'inherited'
        if entries:
            print(f'PASS  profile {name}: {label}, fallback {shown}')
        else:
            empty += 1
            print(f'FAIL  profile {name}: {label}, no fallback chain (a failing model ends the turn)')
    # A reviewer on the coder's own model shares its blind spots.
    for name, own in models.items():
        if 'review' in name and own:
            coders = [n for n, m in models.items() if m == own and any(w in n for w in ('develop', 'coder', 'default'))]
            if coders:
                print(f'WARN  profile {name} reviews with the same model as {", ".join(coders)} ({own[1]}); '
                      'give reviewers another family (hermes -p NAME config set model.default ...)')
    return 1 if empty else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
