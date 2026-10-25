#!/usr/bin/env python3
"""Creates the three demo accounts in the Nolifa cloud: a farmer (Fatboy Butcheries), a
customer and a driver. Needs SUPABASE_URL and SUPABASE_SERVICE_KEY in the environment.
The passwords are generated here and written to ~/nolifa-accounts.local.txt (never to the
repo, never to the console). Safe to run again: an existing account is given a new password.

    EMAIL_BASE=attiiweb15 python3 tools/create_test_accounts.py
"""
import json, os, secrets, string, urllib.request

URL, KEY = os.environ['SUPABASE_URL'], os.environ['SUPABASE_SERVICE_KEY']
BASE = os.environ.get('EMAIL_BASE', 'attiiweb15')
OUT = os.path.expanduser('~/nolifa-accounts.local.txt')

ACCOUNTS = [
    ('fatboy', 'Islilo Farming', 'livestock', 'Greater Durban'),
    ('customer', 'Zanele Customer', 'community', 'Greater Durban'),
    ('driver', 'Sipho Driver', 'driver', 'Greater Durban'),
]

def call(method, path, body=None):
    req = urllib.request.Request(URL + path, data=json.dumps(body).encode() if body is not None else None, method=method,
        headers={'apikey': KEY, 'Authorization': 'Bearer ' + KEY, 'Content-Type': 'application/json'})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=60).read() or b'null')
    except urllib.error.HTTPError as e:
        raise SystemExit('%s %s -> %s %s' % (method, path, e.code, e.read().decode()[:300]))

def password():
    a = string.ascii_letters + string.digits
    return ''.join(secrets.choice(a) for _ in range(12)) + '-9a'

existing = {u['email']: u for u in call('GET', '/auth/v1/admin/users?per_page=200')['users']}
lines = []
for key, name, farm_type, region in ACCOUNTS:
    email = '%s+%s@gmail.com' % (BASE, key)
    pw = password()
    if email in existing:
        uid = existing[email]['id']
        call('PUT', '/auth/v1/admin/users/' + uid, {'password': pw, 'email_confirm': True})
    else:
        uid = call('POST', '/auth/v1/admin/users', {'email': email, 'password': pw, 'email_confirm': True})['id']
    call('POST', '/rest/v1/users?on_conflict=uid', [{'uid': uid, 'data': {'uid': uid, 'name': name, 'email': email, 'region': region, 'farmType': farm_type}}])
    lines.append('%-9s %s  %s  (uid %s)' % (key, email, pw, uid))
with open(OUT, 'a') as f:
    f.write('\n# Nolifa test accounts\n' + '\n'.join(lines) + '\n')
os.chmod(OUT, 0o600)
print('created %d accounts; logins are in %s' % (len(lines), OUT))
