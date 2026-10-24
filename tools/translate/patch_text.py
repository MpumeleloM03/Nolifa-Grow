#!/usr/bin/env python3
"""Points every `Text` in the apps at the translating Text (ubuntu_core/lib/tr_text.dart).
Idempotent: run again after adding files."""
import os, re, sys
ROOTS = {
    '/Users/kingmidus/nolifa-ios/lib': 'pkg',
    '/Users/kingmidus/nolifa-ios/packages/ubuntu_core/lib': 'core',
    '/Users/kingmidus/ubuntu-drop/lib': 'pkg',
    '/Users/kingmidus/nolifa-delivery/lib': 'pkg',
    '/Users/kingmidus/nolifa-ios/backoffice/lib': 'pkg',
}
CORE = '/Users/kingmidus/nolifa-ios/packages/ubuntu_core/lib'
USE = re.compile(r'(?<![\w.])Text(\.rich)?\(')
IMPORT = re.compile(r"^import\s+'(package:flutter/(?:material|widgets|cupertino)\.dart)'([^;]*);", re.M)
changed = 0
for root, kind in ROOTS.items():
    for dp, _, files in os.walk(root):
        for f in files:
            if not f.endswith('.dart') or f in ('tr_text.dart', 'tr.dart', 'zulu_strings.dart'): continue
            p = os.path.join(dp, f)
            s = open(p, encoding='utf-8').read()
            if not USE.search(s): continue
            if 'tr_text.dart' in s: continue
            def fix(m):
                tail = m.group(2)
                if ' as ' in tail: return m.group(0)
                sh = re.search(r'\bshow\s+([^;]*)', tail)
                hd = re.search(r'\bhide\s+([^;]*)', tail)
                if sh:
                    names = [n.strip() for n in sh.group(1).split(',') if n.strip() and n.strip() != 'Text']
                    return "import '%s' show %s;" % (m.group(1), ', '.join(names)) if names else "// (material show list was only Text)"
                if hd:
                    return "import '%s'%s, Text;" % (m.group(1), tail.rstrip()) if 'Text' not in hd.group(1) else m.group(0)
                return "import '%s' hide Text;" % m.group(1)
            n = IMPORT.sub(fix, s)
            if n == s and not IMPORT.search(s): continue
            if kind == 'core':
                rel = os.path.relpath(os.path.join(CORE, 'tr_text.dart'), dp)
                imp = "import '%s' show Text;\n" % rel
            else:
                imp = "import 'package:ubuntu_core/tr_text.dart' show Text;\n"
            # after the last import line
            last = list(re.finditer(r"^(import|export)\s+[^;]*;\s*$", n, re.M))
            pos = last[-1].end() + 1 if last else 0
            n = n[:pos] + imp + n[pos:]
            open(p, 'w', encoding='utf-8').write(n)
            changed += 1
print('patched', changed)
