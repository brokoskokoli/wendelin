#!/usr/bin/env python3
"""Aufrufbudget je Agent/Sitzung (WP110): `budget.py pre|post`.

post (PostToolUse "*"): zählt Werkzeugaufrufe; ab WARN (60) kommt additionalContext
„jetzt übergeben“. pre (PreToolUse "*"): ab BLOCK (90) erlaubt nur Write/Edit und
git add/commit/status (exit 2 sonst), damit die Übergabe möglich bleibt.
Zählschlüssel: agent_id, sonst transcript_path, sonst session_id. Zähler unter
${WENDELIN_HOOK_DIR:-${TMPDIR:-/tmp}/wendelin-hooks} (außerhalb des Repos).
Aktiv nur in Worktrees unter .../james-wt/ (Paket-Sitzungen und ihre Sub-Agenten;
der Orchestrator im Haupt-Checkout bleibt unbehindert) oder mit
WENDELIN_CALL_LIMIT=1; WENDELIN_CALL_LIMIT=0 schaltet ab. Reviewer zählen nicht.
Schwellen: WENDELIN_CALL_WARN / WENDELIN_CALL_BLOCK. Fail-open bei Fehlern.
"""
import fcntl
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shellparse import split_commands  # noqa: E402

EDIT_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
GIT_OK = {"add", "commit", "status"}


def active(data):
    flag = os.environ.get("WENDELIN_CALL_LIMIT")
    if flag == "0":
        return False
    if (data.get("agent_type") or "") == "wendelin-reviewer":
        return False
    proj = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or ""
    return flag == "1" or "/james-wt/" in proj + "/"


def counter_file(data):
    key = data.get("agent_id") or data.get("transcript_path") or data.get("session_id") or "x"
    base = os.environ.get("WENDELIN_HOOK_DIR") or os.path.join(os.environ.get("TMPDIR", "/tmp"), "wendelin-hooks")
    os.makedirs(base, exist_ok=True)
    return os.path.join(base, hashlib.sha1(key.encode()).hexdigest()[:16] + ".count")


def read_count(path):
    try:
        with open(path) as f:
            return int(f.read().strip() or 0)
    except (OSError, ValueError):
        return 0


def increment(path):
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    with os.fdopen(fd, "r+") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            n = int(f.read().strip() or 0) + 1
        except ValueError:
            n = 1
        f.seek(0)
        f.truncate()
        f.write(str(n))
    return n


def only_commit_git(command):
    """Wahr, wenn der Aufruf nur aus git add/commit/status (ggf. verkettet) besteht."""
    cmds = split_commands(command)
    if not cmds:
        return False
    for c in cmds:
        if os.path.basename(c[0]) != "git":
            return False
        i = 1
        while i < len(c) and c[i].startswith("-"):
            i += 2 if c[i] in ("-C", "-c") else 1
        if i >= len(c) or c[i] not in GIT_OK:
            return False
    return True


def main(mode):
    try:
        data = json.load(sys.stdin)
        if not active(data):
            return 0
        warn = int(os.environ.get("WENDELIN_CALL_WARN", 60))
        block = int(os.environ.get("WENDELIN_CALL_BLOCK", 90))
        path = counter_file(data)
        if mode == "post":
            n = increment(path)
            if n >= warn:
                msg = ("Aufrufbudget: %d Werkzeugaufrufe erreicht (Grenze %d, danach nur noch Write/Edit und git commit). "
                       "Jetzt übergeben: WIP-Commit, Übergabedatei nach ../james-wt/handoff/<wp>.md, "
                       "Abschluss mit ÜBERGABE: <pfad> (docs/agents/common.md)." % (n, block))
                print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": msg}}))
            return 0
        if read_count(path) < block:
            return 0
        tool = data.get("tool_name") or ""
        if tool in EDIT_TOOLS:
            return 0
        if tool == "Bash" and only_commit_git((data.get("tool_input") or {}).get("command") or ""):
            return 0
        sys.stderr.write("Wendelin-Hook: Aufrufbudget (%d) erschöpft. Erlaubt sind nur noch Write/Edit und git add/commit/status. "
                         "Übergabedatei schreiben (docs/agents/common.md) und mit ÜBERGABE: <pfad> enden.\n" % block)
        return 2
    except Exception:
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "pre"))
