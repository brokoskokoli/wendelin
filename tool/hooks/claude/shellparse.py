"""Kleiner Shell-Zerleger für die Claude-Code-Hooks (WP110).

`commands(text)` liefert die einfachen Kommandos eines Bash-Aufrufs als Tokenlisten:
getrennt an ; & | ( ) und Zeilenumbruch außerhalb von Anführungszeichen. Quotes und
Backslashes werden aufgelöst (`"git" push 'main'` -> git push main). `$(…)` in
Anführungszeichen bleibt Teil des Tokens (Commit-Texte mit Heredoc lösen so keinen
Fehlalarm aus). Heredoc-Inhalte werden übersprungen.
"""


def split_commands(text):
    cmds, cur, tok, has, heredocs = [], [], [], False, []
    i, n = 0, len(text)

    def flush_tok():
        nonlocal tok, has
        if has:
            cur.append("".join(tok))
        tok, has = [], False

    def flush_cmd():
        nonlocal cur
        flush_tok()
        if cur:
            cmds.append(cur)
        cur = []

    while i < n:
        c = text[i]
        if c == "\\" and i + 1 < n:
            if text[i + 1] != "\n":
                tok.append(text[i + 1]); has = True
            i += 2
        elif c == "'":
            j = text.find("'", i + 1)
            j = n if j < 0 else j
            tok.append(text[i + 1:j]); has = True
            i = j + 1
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                if text[j] == "\\" and j + 1 < n:
                    j += 1
                    tok.append(text[j])
                else:
                    tok.append(text[j])
                j += 1
            has = True
            i = j + 1
        elif c in " \t":
            flush_tok(); i += 1
        elif c == "<" and text[i:i + 2] == "<<" and text[i:i + 3] != "<<<":
            j = i + 2
            strip = j < n and text[j] == "-"
            j += 1 if strip else 0
            while j < n and text[j] in " \t":
                j += 1
            k = j
            while k < n and text[k] not in " \t\n;&|()<>":
                k += 1
            heredocs.append((text[j:k].strip("'\""), strip))
            flush_tok()
            i = k
        elif c == "\n" and heredocs:
            flush_cmd()
            i += 1
            for delim, strip in heredocs:
                while i < n:
                    e = text.find("\n", i)
                    e = n if e < 0 else e
                    line = text[i:e]
                    i = min(e + 1, n)
                    if (line.lstrip("\t") if strip else line) == delim:
                        break
            heredocs = []
        elif c in ";&|()\n`":
            flush_cmd(); i += 1
        elif c == "#" and not has:
            while i < n and text[i] != "\n":
                i += 1
        else:
            tok.append(c); has = True; i += 1
    flush_cmd()
    return cmds
