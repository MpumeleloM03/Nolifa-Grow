#!/usr/bin/env python3
"""Pulls every user-facing English string out of the apps' Dart source.

Writes strings.json: {template: [files...]}. A template is the string with each
interpolation replaced by {0}, {1}, ... so `'R${fee} delivery'` becomes
`R{0} delivery`. The Zulu dictionary is keyed by these templates.
"""
import json, os, re, sys

ROOTS = [
    '/Users/kingmidus/nolifa-ios/lib',
    '/Users/kingmidus/nolifa-ios/packages/ubuntu_core/lib',
    '/Users/kingmidus/ubuntu-drop/lib',
    '/Users/kingmidus/nolifa-delivery/lib',
    '/Users/kingmidus/nolifa-ios/backoffice/lib',
]
SKIP_FILES = ('translations.dart', 'zulu_strings.dart', '.g.dart')
SKIP_LINE = re.compile(r"^\s*(import|export|part)\b|debugPrint\(|\bprint\(|\bthrow\b|Exception\(|StateError\(|ArgumentError\(|\bassert\(|ValueKey\(|\bKey\(|^\s*@|RegExp\(|Uri\.parse\(|\.from\(|\.rpc\(|\.select\(|\.stream\(|\.eq\(|\.inFilter\(|\.order\(|\.invoke\(|getString\(|setString\(|SharedPreferences|containsKey|logErr|_log\(|developer\.log|\.storage\b|\.channel\(|fromEnvironment|rootBundle|Image\.asset|AssetImage|\.contains\(|\.startsWith\(|\.endsWith\(|\.split\(|\.replaceAll\(|\.replaceFirst\(")

def decode(body, raw):
    if raw: return body
    out, i = [], 0
    esc = {'n': '\n', 't': '\t', 'r': '\r', "'": "'", '"': '"', '\\': '\\', '$': '$'}
    while i < len(body):
        c = body[i]
        if c == '\\' and i + 1 < len(body):
            n = body[i + 1]
            if n == 'u' and i + 5 < len(body) + 1:
                m = re.match(r'u\{([0-9a-fA-F]+)\}|u([0-9a-fA-F]{4})', body[i + 1:])
                if m:
                    out.append(chr(int(m.group(1) or m.group(2), 16))); i += 1 + len(m.group(0)); continue
            out.append(esc.get(n, n)); i += 2
        else:
            out.append(c); i += 1
    return ''.join(out)

def scan(src):
    """Yield (template, line_no) for each string literal in a Dart file."""
    i, n, line = 0, len(src), 1
    while i < n:
        c = src[i]
        if c == '\n': line += 1; i += 1; continue
        if src.startswith('//', i):
            j = src.find('\n', i); i = n if j < 0 else j; continue
        if src.startswith('/*', i):
            j = src.find('*/', i + 2); j = n if j < 0 else j + 2
            line += src.count('\n', i, j); i = j; continue
        raw = False
        k = i
        if c == 'r' and i + 1 < n and src[i + 1] in '\'"' and (i == 0 or not (src[i - 1].isalnum() or src[i - 1] == '_')):
            raw = True; k = i + 1
        if src[k] in '\'"' and (raw or c in '\'"'):
            q = src[k]
            triple = src.startswith(q * 3, k)
            delim = q * 3 if triple else q
            j = k + len(delim)
            parts, lit, depth_text = [], [], None
            start_line = line
            tmpl = []
            body_start = j
            while j < n:
                if not raw and src[j] == '\\':
                    tmpl.append(src[j:j + 2]); j += 2; continue
                if src.startswith(delim, j):
                    break
                if not raw and src[j] == '$':
                    if j + 1 < n and src[j + 1] == '{':
                        d, m = 1, j + 2
                        while m < n and d:
                            if src[m] == '{': d += 1
                            elif src[m] == '}': d -= 1
                            elif src[m] in '\'"':  # nested string inside the expression
                                qq = src[m]; m += 1
                                while m < n and src[m] != qq:
                                    if src[m] == '\\': m += 1
                                    m += 1
                            m += 1
                        tmpl.append('\x00'); j = m; continue
                    m = re.match(r'\$[A-Za-z_][A-Za-z_0-9]*', src[j:])
                    if m:
                        tmpl.append('\x00'); j += len(m.group(0)); continue
                if src[j] == '\n':
                    if not triple: break
                tmpl.append(src[j]); j += 1
            body = ''.join(tmpl)
            line += src.count('\n', i, j)
            i = j + len(delim)
            yield decode(body, raw), start_line
            continue
        i += 1

def number(s):
    k = 0
    def sub(_):
        nonlocal k
        r = '{%d}' % k; k += 1; return r
    return re.sub('\x00', sub, s)

IDENT = re.compile(r'^[a-z][A-Za-z0-9_.\-:/]*$')
def user_facing(t):
    plain = re.sub(r'\{\d+\}', '', t).strip()
    if not re.search(r'[A-Za-z]{2,}', plain): return False
    if len(plain) < 2: return False
    if re.match(r'^(https?:|package:|assets/|mailto:|tel:|dart:|/)', t): return False
    if re.match(r'^[\w.+-]+@[\w-]+\.[\w.]+$', t): return False
    if IDENT.match(plain) and ' ' not in plain: return False           # keys, ids, routes
    if re.match(r'^[a-z]+([A-Z][a-z]+)+$', plain): return False        # camelCase
    if re.match(r'^[A-Z0-9_]+$', plain) and len(plain) > 3: return False  # CONSTANTS
    if ' ' not in plain and not re.match(r'^[A-Z][a-z]{2,}', plain): return False
    if re.search(r'select|insert|update .* set|create table', plain, re.I) and ',' in plain and len(plain.split()) < 6: return False
    return True

def main():
    found = {}
    for root in ROOTS:
        for dp, _, files in os.walk(root):
            for f in files:
                if not f.endswith('.dart') or f.endswith(SKIP_FILES): continue
                p = os.path.join(dp, f)
                src = open(p, encoding='utf-8').read()
                lines = src.split('\n')
                for t, ln in scan(src):
                    if SKIP_LINE.search(lines[ln - 1]): continue
                    t = number(t)
                    if not user_facing(t): continue
                    found.setdefault(t, []).append('%s:%d' % (p.replace('/Users/kingmidus/', ''), ln))
    json.dump(found, open(os.path.join(os.path.dirname(__file__), 'strings.json'), 'w'), indent=0, ensure_ascii=False)
    exact = [t for t in found if '{' not in t]
    tmpl = [t for t in found if re.search(r'\{\d+\}', t)]
    print('strings', len(found), 'exact', len(exact), 'templates', len(tmpl), 'words', sum(len(t.split()) for t in found))

main()
