#!/usr/bin/env python3
"""List what each Hermes Kanban worker actually ran, and flag anything outside its contract.

    audit_work_cards.py --board work --card t_1234abcd --card t_5678ef90 \\
        --allow '^cat /srv/pack/INPUT\\.md$' --allow '^cat > /srv/out/[A-Z][0-9]\\.md' \\
        --allow-read-under /srv/pack --write-suffix .md

    audit_work_cards.py --board work --cards-file cards.txt --allow-file allow.txt --full

A card's summary is the worker's own claim. This reads the tool calls the worker made
from the profile's session store (read-only) and checks every shell command against the
patterns the contract allowed. It never changes a card, a session or a file.

A cards file has one card per line: `<label> <card id> [<profile>]` or just `<card id>`.
An allow file has one regular expression per line; blank lines and `#` lines are skipped.

Before a command is split into parts, here-documents and quoted text are set aside.
Without that, a worker that writes its notes with `cat > file <<'EOF'` has every
sentence containing a semicolon reported as a command (271 false flags in one round of
nine cards), and a multi-line quoted argument is reported line by line.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys

SHELL_TOOLS = {"terminal", "shell", "bash", "execute_command", "run_command"}
WRITE_TOOLS = {"write_file", "write", "create_file", "patch", "edit_file", "apply_patch"}
# Never part of a read-or-write-one-file contract. Override with --prohibit.
DEFAULT_PROHIBITED = r"(rm|mv|cp|chmod|chown|sudo|git (commit|push|add|checkout|reset|merge|rebase|clean|stash)|curl|wget|ssh|scp|rsync|node|npm|npx|pip|brew|docker|kill|launchctl)"
# A bare echo that writes nowhere: workers print separators between two commands.
ECHO = re.compile(r"^\s*echo [^>|]*$")
HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?[^\n]*\n.*?\n[ \t]*\1[ \t]*(?=\n|$)", re.S)
# A here-document whose delimiter is quoted: the shell copies its body and expands nothing in it.
HEREDOC_LITERAL = re.compile(r"<<-?\s*(['\"])(\w+)\1[^\n]*\n.*?\n[ \t]*\2[ \t]*(?=\n|$)", re.S)
# `$(...)` or backticks: one command run inside another. The shell expands them everywhere
# except inside single quotes and inside a here-document whose delimiter is quoted.
SUBSTITUTION = re.compile(r"\$\(|`")
# A character after a backslash is itself and starts nothing (`\$(`, an escaped backtick).
ESCAPED = re.compile(r"\\.", re.S)
QUOTED = re.compile(r"\"(?:[^\"\\]|\\.)*\"|'[^']*'")
# A name set to a plain path or word (`F=/srv/pack/a.md`), and a use of one (`$F`, `${F}`).
NAME_SET = re.compile(r"^[A-Za-z_]\w*=[\w./@+-]+$")
NAME_USE = re.compile(r"\$\{([A-Za-z_]\w*)\}|\$([A-Za-z_]\w*)")
SEPARATOR = re.compile(r"\s*(?:;|&&|\|\||\n)\s*")


def strip_heredocs(command: str) -> str:
    """The command with each here-document's body removed (the redirection itself stays)."""
    return HEREDOC.sub("<<HEREDOC", command)


def split_commands(command: str) -> list[str]:
    """The separate commands of one shell line: split on `;`, `&&`, `||` and newlines that
    are outside quotes and outside here-documents. Quoted text comes back unchanged."""
    shell = strip_heredocs(command)
    shell = QUOTED.sub(lambda m: m.group(0).replace(";", "\x00").replace("&", "\x01").replace("\n", "\x02").replace("|", "\x03"), shell)
    parts = []
    for part in SEPARATOR.split(shell):
        part = part.replace("\x00", ";").replace("\x01", "&").replace("\x02", "\n").replace("\x03", "|").strip()
        if part:
            parts.append(part)
    return parts


class ReadUnder:
    """Matches a read of files under one folder. Used like a compiled pattern: `.search(command)`."""

    def __init__(self, folder: str):
        self.root = os.path.abspath(folder).rstrip("/") + "/"
        root = re.escape(self.root)
        # A double-quoted pattern may hold escaped characters (`grep -c "key: \\"x\\"" file`), and
        # nothing the shell expands inside double quotes: no bare `$`, no bare backtick.
        quoted = r"(?:'[^']*'|\"(?:[^\"\\$`]|\\.)*\")"
        # A grep pattern is quoted, or one bare word (`grep -c NEW file`): nothing a shell would expand or redirect.
        word = r"[A-Za-z0-9_.^-]+"
        self.path = re.compile(rf"['\"]?({root}[\w./@+-]+)['\"]?")
        self.pattern = re.compile(rf"^\s*(?:cat|wc -[lwc]+|head(?: -n? ?\d+)?|tail(?: -n? ?\d+)?|grep -[A-Za-z]+ (?:{quoted}|{word})|sed -n {quoted})((?: {self.path.pattern})+)\s*$")

    def search(self, command: str):
        found = self.pattern.search(command)
        if not found:
            return None
        # `/pack/../other` begins with the folder and is not under it.
        for path in self.path.findall(found.group(1)):
            if not (os.path.normpath(path) + "/").startswith(self.root):
                return None
        return found


def read_pattern(folder: str) -> ReadUnder:
    """A read of one or more files under `folder`: cat, head, tail, wc, grep or sed -n, with no redirect or pipe."""
    return ReadUnder(folder)


def substitutions(command: str) -> list[str]:
    """Each place where the command runs another command inside it, as the text around it."""
    found = []
    # A here-document with an unquoted delimiter is expanded like a double-quoted string, apostrophes and all.
    literal_removed = HEREDOC_LITERAL.sub("<<HEREDOC", command)
    for body in HEREDOC.finditer(literal_removed):
        if SUBSTITUTION.search(ESCAPED.sub("", body.group(0).split("\n", 1)[1])):
            found.append(f"in the body of a here-document whose delimiter is not quoted (<<{body.group(1)})")
    rest = re.sub(r"'[^']*'", "''", HEREDOC.sub("<<HEREDOC", literal_removed))
    for part in SEPARATOR.split(rest):
        if SUBSTITUTION.search(ESCAPED.sub("", part)):
            found.append(part.strip()[:100])
    return list(dict.fromkeys(found))


def resolve_names(parts: list[str]) -> list[str]:
    """The commands with each plain name put in place: after `F=/srv/pack/a.md`, `wc -l $F`
    reads as `wc -l /srv/pack/a.md`. Only a value made of path characters counts (a later
    one may use an earlier one), and a part that only sets such names is dropped: it does
    nothing by itself. Anything else is left exactly as written."""
    names: dict[str, str] = {}
    resolved = []
    for part in parts:
        text = NAME_USE.sub(lambda m: names.get(m.group(1) or m.group(2), m.group(0)), part)
        settings = text.split()
        if settings and all(NAME_SET.match(word) for word in settings):
            names.update(word.split("=", 1) for word in settings)
            continue
        resolved.append(text)
    return resolved


def audit_command(command: str, allowed: list[re.Pattern], prohibited: re.Pattern) -> list[str]:
    flags = []
    parts = resolve_names(split_commands(command))
    for part in parts:
        if not any(pattern.search(part) for pattern in allowed) and not ECHO.match(part):
            flags.append(f"command outside the contract: {part.splitlines()[0][:100]}")
    # Checked on the text outside quotes and here-documents: a sentence in the worker's notes is not a command.
    # Checked again with names put in place, so that `C=rm; $C file` is seen for what it runs.
    bare = QUOTED.sub("QUOTED", strip_heredocs(command))
    named = "\n".join(QUOTED.sub("QUOTED", part) for part in parts)
    if any(re.search(rf"(^|[;&|\n(]\s*){prohibited.pattern}\b", text) for text in (bare, named)):
        flags.append(f"prohibited: {bare.splitlines()[0][:100]}")
    # Quoting hides a command from the checks above, so a command run inside another is flagged whatever it is.
    for where in substitutions(command):
        flags.append(f"runs a command inside another ($( ) or backticks): {where}")
    return flags


def audit_calls(calls: list[tuple[str, dict]], allowed: list[re.Pattern], prohibited: re.Pattern, write_suffix: str | None) -> dict:
    """`calls` is (tool name, arguments) in order. Returns counts and flags."""
    flags, shell, writes, shown = [], 0, 0, []
    for name, args in calls:
        target = args.get("command") or args.get("path") or args.get("file_path") or json.dumps(args)[:200]
        shown.append((name, str(target)))
        if name in SHELL_TOOLS:
            shell += 1
            flags += audit_command(str(args.get("command") or ""), allowed, prohibited)
        elif name in WRITE_TOOLS:
            writes += 1
            path = str(args.get("path") or args.get("file_path") or "")
            if write_suffix is not None and not path.endswith(write_suffix):
                flags.append(f"wrote another file: {path}")
    return dict(tool_calls=len(calls), shell_calls=shell, write_calls=writes, flags=flags, calls=shown)


def tool_calls_of(store: sqlite3.Connection, session: str) -> tuple[int, list[tuple[str, dict]]]:
    rows = store.execute("select tool_calls from messages where session_id=? order by id", (session,)).fetchall()
    calls = []
    for (raw,) in rows:
        if not raw:
            continue
        try:
            listed = json.loads(raw)
        except ValueError:
            continue
        for call in listed if isinstance(listed, list) else []:
            function = call.get("function", {}) if isinstance(call, dict) else {}
            try:
                args = json.loads(function.get("arguments") or "{}")
            except ValueError:
                args = {"raw": function.get("arguments")}
            calls.append((function.get("name") or "?", args if isinstance(args, dict) else {"raw": args}))
    return len(rows), calls


def card_runs(board: sqlite3.Connection, card: str) -> dict | None:
    """Status, assignee and the newest run that recorded a worker session, read from the board itself."""
    task = board.execute("select status, assignee from tasks where id=?", (card,)).fetchone()
    if task is None:
        return None
    session, profile, runs = None, task[1], 0
    for run_profile, metadata in board.execute("select profile, metadata from task_runs where task_id=? order by id", (card,)):
        runs += 1
        try:
            found = (json.loads(metadata or "{}") or {}).get("worker_session_id")
        except (ValueError, AttributeError):
            found = None
        if found:
            session, profile = found, run_profile or profile
    return dict(status=task[0], profile=profile, session=session, runs=runs)


def profile_store(hermes_home: str, profile: str | None) -> str:
    return os.path.join(hermes_home, "state.db") if profile in (None, "", "default") else os.path.join(hermes_home, "profiles", profile, "state.db")


def read_cards(args) -> list[tuple[str, str]]:
    cards = [(card, card) for card in args.card or []]
    if args.cards_file:
        with open(args.cards_file, encoding="utf-8") as handle:
            lines = handle.read().split("\n")
        for line in lines:
            words = line.split()
            if not words or words[0].startswith("#"):
                continue
            ids = [word for word in words if re.fullmatch(r"t_[0-9a-f]{6,}", word)]
            if ids:
                cards.append((words[0], ids[0]))
    return cards


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read-only audit of the tool calls Hermes Kanban workers made, against the patterns their contract allowed.")
    parser.add_argument("--hermes-home", default=os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes"))
    parser.add_argument("--board", required=True)
    parser.add_argument("--card", action="append", help="card id (repeatable)")
    parser.add_argument("--cards-file", help="one card per line: '<label> <card id> [profile]' or '<card id>'")
    parser.add_argument("--allow", action="append", default=[], help="regular expression a command may match (repeatable)")
    parser.add_argument("--allow-file", help="file of regular expressions, one per line")
    parser.add_argument("--allow-read-under", action="append", default=[], help="folder whose files may be read with cat, head, tail, wc, grep or sed -n (repeatable)")
    parser.add_argument("--write-suffix", help="a file-writing tool may only write a path ending with this")
    parser.add_argument("--prohibit", default=DEFAULT_PROHIBITED, help="regular expression of commands that are never allowed")
    parser.add_argument("--full", action="store_true", help="also list every tool call (may show file paths and command text)")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    patterns = list(args.allow)
    if args.allow_file:
        with open(args.allow_file, encoding="utf-8") as handle:
            patterns += [line.strip() for line in handle.read().split("\n") if line.strip() and not line.lstrip().startswith("#")]
    allowed = [re.compile(pattern) for pattern in patterns] + [read_pattern(folder) for folder in args.allow_read_under]
    prohibited = re.compile(args.prohibit)
    cards = read_cards(args)
    if not cards:
        parser.error("name at least one card with --card or --cards-file")

    board_path = os.path.join(args.hermes_home, "kanban", "boards", args.board, "kanban.db")
    if not os.path.exists(board_path):
        print(f"No database for board {args.board} under {os.path.dirname(os.path.dirname(board_path))}.", file=sys.stderr)
        return 2
    board = sqlite3.connect(f"file:{board_path}?mode=ro", uri=True)
    results, flagged = [], 0
    for label, card in cards:
        found = card_runs(board, card)
        if found is None:
            results.append(dict(label=label, card=card, problem="no such card on this board"))
            flagged += 1
            continue
        entry = dict(label=label, card=card, **found)
        store_path = profile_store(args.hermes_home, found["profile"])
        if not found["session"] or not os.path.exists(store_path):
            entry["problem"] = "no worker session recorded: nothing to audit (a run that failed before or without a session leaves none)"
            flagged += 1
        else:
            store = sqlite3.connect(f"file:{store_path}?mode=ro", uri=True)
            try:
                messages, calls = tool_calls_of(store, found["session"])
            finally:
                store.close()
            entry.update(messages=messages, **audit_calls(calls, allowed, prohibited, args.write_suffix))
            flagged += 1 if entry["flags"] else 0
            if not args.full:
                entry.pop("calls")
        results.append(entry)
    board.close()

    if args.json:
        print(json.dumps(dict(board=args.board, cards=results, cards_with_flags=flagged), indent=2))
    else:
        for entry in results:
            if "problem" in entry and "tool_calls" not in entry:
                print(f"{entry['label']} {entry['card']}: {entry.get('status', '?')} | {entry['problem']}")
                continue
            print(f"{entry['label']} {entry['card']} {entry['profile']}: status={entry['status']} runs={entry['runs']} messages={entry['messages']} tool calls={entry['tool_calls']} (shell {entry['shell_calls']}, file writes {entry['write_calls']})")
            for flag in entry["flags"]:
                print("    FLAG", flag)
            for name, target in entry.get("calls", []):
                print("     ", name, "|", target.replace("\n", " ")[:170])
        print(f"{len(results)} cards, {flagged} with something to look at.")
    return 1 if flagged else 0


if __name__ == "__main__":
    sys.exit(main())
