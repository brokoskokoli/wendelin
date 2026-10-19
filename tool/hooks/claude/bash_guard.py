#!/usr/bin/env python3
"""PreToolUse-Hook für Bash (WP110): lehnt verbotene Befehle ab (exit 2 + Begründung).

Gesperrt: --no-verify (und commit -n), git push auf main ohne WENDELIN_PUSH_MAIN=1,
pkill/killall, git -c user.*/core.hooksPath, git config user.*/core.hooksPath,
GIT_AUTHOR_*/GIT_COMMITTER_*-Zuweisungen. Erkennt Ketten, env/export, Quotes,
bash -c/eval, git -C, HEAD:main, refs/heads/main, +main. Quelle der Regeln:
docs/agents/common.md. Fail-open bei Fehlern im Hook selbst.
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shellparse import split_commands  # noqa: E402

ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)
IDENT_VAR = re.compile(r"^GIT_(AUTHOR|COMMITTER)_[A-Z_]+$|^GIT_CONFIG_(COUNT|PARAMETERS|KEY_\d+|VALUE_\d+)$")
WRAPPERS = {"env", "command", "builtin", "exec", "sudo", "nohup", "time", "nice", "export", "declare", "typeset", "local"}
# Shell-Schlüsselwörter, hinter denen ein Kommando steht (if/while/!/{ …).
KEYWORDS = {"if", "then", "elif", "else", "do", "while", "until", "!", "{", "}", "coproc"}
# Programme, die ein weiteres Kommando mit eigenen Optionen/Werten starten: alle Suffixe prüfen.
SCAN_PROGS = {"timeout", "nice", "sudo", "nohup", "xargs", "doas", "setsid", "ionice", "caffeinate"}
EXEC_FLAGS = {"-exec", "-execdir", "-ok", "-okdir"}
SHELLS = {"bash", "sh", "zsh", "dash"}
BAD_CFG = re.compile(r"^(user\.|author\.|committer\.|core\.hookspath)", re.I)
GIT_VALUE_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix", "--config-env"}
PUSH_VALUE_OPTS = {"-o", "--push-option", "--repo", "--receive-pack", "--exec", "--force-with-lease-x"}
COMMIT_VALUE_LETTERS = set("mFCctS")
COMMIT_VALUE_OPTS = {"-m", "-F", "-C", "-c", "-t", "--message", "--file", "--author", "--date", "--template", "--reuse-message", "--reedit-message"}


class Deny(Exception):
    pass


def current_branch(cwd):
    try:
        r = subprocess.run(["git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
                           capture_output=True, text=True, timeout=5)
        return r.stdout.strip()
    except Exception:
        return ""


def targets_main(args, cwd):
    """Wahr, wenn der push-Aufruf (Argumente nach `push`) main beschreibt."""
    pos, i = [], 0
    while i < len(args):
        a = args[i]
        if a in ("--all", "--mirror"):
            return True
        if a in PUSH_VALUE_OPTS:
            i += 2
            continue
        if a.startswith("-") and a != "-":
            i += 1
            continue
        pos.append(a)
        i += 1
    refspecs = pos[1:]
    if not refspecs:
        return current_branch(cwd) == "main"
    for spec in refspecs:
        spec = spec.lstrip("+")
        dst = spec.split(":")[-1]
        if dst in ("HEAD", "@") and ":" not in spec:
            dst = current_branch(cwd)
        dst = re.sub(r"^(refs/)?heads/", "", dst)
        if dst == "main" or "*" in dst:
            return True
    return False


def check_commit(args):
    j = 0
    while j < len(args):
        a = args[j]
        if a in COMMIT_VALUE_OPTS:
            j += 2
            continue
        if re.match(r"^-[A-Za-z]+$", a):
            for k, ch in enumerate(a[1:], 1):
                if ch == "n":
                    raise Deny("git commit -n (= --no-verify) ist verboten.")
                if ch in COMMIT_VALUE_LETTERS:
                    if k == len(a) - 1:
                        j += 1  # Wert steht im nächsten Token
                    break
        j += 1


def check_git(tokens, state, cwd):
    i, n = 1, len(tokens)
    gcwd = cwd
    while i < n:
        t = tokens[i]
        if t == "-c" and i + 1 < n:
            key = tokens[i + 1].split("=", 1)[0]
            if BAD_CFG.match(key):
                raise Deny("git -c %s: Identität/Hooks nicht per Override ändern (docs/agents/common.md)." % key)
            i += 2
        elif t.startswith("--config-env=") or t == "--config-env":
            key = (t.split("=", 1)[1] if "=" in t else (tokens[i + 1] if i + 1 < n else "")).split("=", 1)[0]
            if BAD_CFG.match(key):
                raise Deny("git --config-env %s: Identität/Hooks nicht ändern." % key)
            i += 1 if "=" in t else 2
        elif t == "-C":
            if i + 1 < n:
                gcwd = os.path.join(gcwd, tokens[i + 1])
            i += 2
        elif t in GIT_VALUE_OPTS:
            i += 2
        elif t.startswith("-"):
            i += 1
        else:
            break
    if i >= n:
        return
    sub, args = tokens[i], tokens[i + 1:]
    for a in args:
        o = a.split("=", 1)[0]
        # Git akzeptiert eindeutige Abkürzungen langer Optionen (--no-v, --no-veri …).
        if len(o) >= 6 and "--no-verify".startswith(o):
            raise Deny("--no-verify ist verboten (Hooks sind verbindlich, docs/agents/common.md).")
    if sub == "commit":
        check_commit(args)
    elif sub == "config":
        keys = [a for a in args if not a.startswith("-")]
        writes = len(keys) >= 2 or any(a in ("--unset", "--unset-all", "--replace-all", "--add") for a in args)
        if keys and writes and BAD_CFG.match(keys[0]):
            raise Deny("git config %s: Identität/Hooks nicht ändern (docs/agents/common.md)." % keys[0])
    elif sub == "push":
        if state.get("WENDELIN_PUSH_MAIN") != "1" and targets_main(args, gcwd):
            raise Deny("Push auf main nur für Orchestrator/Integrator mit WENDELIN_PUSH_MAIN=1 "
                       "(nach tool/merge_wp.sh bzw. reinem Doku-Commit). Arbeitsbranch: git push origin wp/<nr>-<slug>.")


def check_cmd(tokens, state, cwd, depth=0):
    """Prüft ein Kommando; Zuweisungen ohne Kommando (und export) wirken auf [state]."""
    if depth > 4:
        return
    i, assigns, persist, scan = 0, {}, False, False
    while i < len(tokens):
        t = tokens[i]
        m = ASSIGN.match(t)
        if m:
            if IDENT_VAR.match(m.group(1)):
                raise Deny("%s setzen ist verboten (Identität, docs/agents/common.md)." % m.group(1))
            assigns[m.group(1)] = m.group(2)
            i += 1
        elif t in KEYWORDS:
            i += 1
        elif os.path.basename(t) in WRAPPERS:
            wrapper = os.path.basename(t)
            scan = scan or wrapper in SCAN_PROGS
            persist = persist or wrapper in ("export", "declare", "typeset")
            i += 1
            while i < len(tokens) and tokens[i].startswith("-"):
                i += 2 if wrapper == "env" and tokens[i] in ("-u", "-C", "-S") else 1
        else:
            break
    rest = tokens[i:]
    if not rest:
        if persist or not tokens or ASSIGN.match(tokens[0]):
            state.update(assigns)
        return
    local = {**state, **assigns}
    prog = os.path.basename(rest[0])
    if scan or prog in SCAN_PROGS:
        # Optionen mit Werten (timeout 5, nice -n 5, sudo -u x, xargs -n1 …): jedes Suffix prüfen.
        carry = dict(local)
        for k in range(1, len(rest)):
            m = ASSIGN.match(rest[k - 1])
            if m and k > 1:
                carry[m.group(1)] = m.group(2)
            check_cmd(rest[k:], carry, cwd, depth + 1)
    elif prog == "find":
        for k, a in enumerate(rest):
            if a in EXEC_FLAGS:
                check_cmd(rest[k + 1:], local, cwd, depth + 1)
    if prog in ("pkill", "killall"):
        raise Deny("%s ist verboten (fremde Prozesse nicht anfassen, docs/agents/common.md)." % prog)
    if prog == "git":
        check_git(rest, local, cwd)
    elif prog in SHELLS or prog == "eval":
        sub = None
        if prog == "eval":
            sub = " ".join(rest[1:])
        else:
            for k, a in enumerate(rest[1:], 1):
                if re.match(r"^-[a-z]*c[a-z]*$", a) and k + 1 < len(rest):
                    sub = rest[k + 1]
                    break
        for c in split_commands(sub or ""):
            check_cmd(c, local, cwd, depth + 1)


def check(command, cwd):
    state = {}
    for tokens in split_commands(command):
        check_cmd(tokens, state, cwd)


def main():
    try:
        data = json.load(sys.stdin)
        command = (data.get("tool_input") or {}).get("command") or ""
        cwd = data.get("cwd") or os.getcwd()
    except Exception:
        return 0
    try:
        check(command, cwd)
    except Deny as e:
        sys.stderr.write("Wendelin-Hook: abgelehnt. %s\n" % e)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
