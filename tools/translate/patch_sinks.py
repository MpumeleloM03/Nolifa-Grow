#!/usr/bin/env python3
"""Wraps the string arguments that are not shown through a Text (hints, labels,
tooltips) in tr()/trn() so they are translated too. Idempotent."""
import os, re
ROOTS = {
    '/Users/kingmidus/nolifa-ios/lib': 'pkg',
    '/Users/kingmidus/nolifa-ios/packages/ubuntu_core/lib': 'core',
    '/Users/kingmidus/ubuntu-drop/lib': 'pkg',
    '/Users/kingmidus/nolifa-delivery/lib': 'pkg',
}
CORE = '/Users/kingmidus/nolifa-ios/packages/ubuntu_core/lib'
LIT = r"""'(?:[^'\\\n]|\\.)*'"""
PAT = re.compile(r"\b(labelText|hintText|helperText|errorText|tooltip):\s*(" + LIT + r"|[A-Za-z_][\w.]*)(?=\s*[,)])")
n_files = n_edits = 0
for root, kind in ROOTS.items():
    for dp, _, files in os.walk(root):
        for f in files:
            if not f.endswith('.dart') or f in ('tr.dart', 'tr_text.dart', 'zulu_strings.dart'): continue
            p = os.path.join(dp, f)
            s = open(p, encoding='utf-8').read()
            def rep(m):
                global n_edits
                key, val = m.group(1), m.group(2)
                if val in ('null', 'true', 'false') or val.startswith('tr(') or val.startswith('trn('): return m.group(0)
                n_edits += 1
                fn = 'tr' if val.startswith("'") else 'trn'
                return f"{key}: {fn}({val})"
            n = PAT.sub(rep, s)
            if n == s: continue
            # a const constructor cannot hold a function call
            n = re.sub(r"const (InputDecoration|IconButton|Tooltip)\(([^\n]*\b(?:tr|trn)\()", r"\1(\2", n)
            if 'tr.dart' not in n:
                if kind == 'core':
                    imp = "import '%s' show tr, trn;\n" % os.path.relpath(os.path.join(CORE, 'tr.dart'), dp)
                else:
                    imp = "import 'package:ubuntu_core/tr.dart' show tr, trn;\n"
                last = list(re.finditer(r"^(import|export)\s+[^;]*;\s*$", n, re.M))
                pos = last[-1].end() + 1 if last else 0
                n = n[:pos] + imp + n[pos:]
            open(p, 'w', encoding='utf-8').write(n); n_files += 1
print('files', n_files, 'edits', n_edits)
