#!/usr/bin/env python3
"""Removes accounts from the Nolifa cloud, with everything they own: rows in every table
that names them, and their files. Needs SUPABASE_URL, SUPABASE_SERVICE_KEY and
SUPABASE_ACCESS_TOKEN (the management token) in the environment.

    python3 tools/wipe_accounts.py '%@example.com'          # the throwaway users the live tests make
    python3 tools/wipe_accounts.py a@x.com b@y.com           # named accounts

Staff accounts are never touched unless you name them. Orders are deleted outright, so use
this for test data, not for real people (a real person deletes their account in the app,
which keeps orders for accounting)."""
import json, os, sys, urllib.request

URL, KEY, TOKEN = os.environ['SUPABASE_URL'], os.environ['SUPABASE_SERVICE_KEY'], os.environ['SUPABASE_ACCESS_TOKEN']
REF = URL.split('//')[1].split('.')[0]

def api(method, path, body=None):
    r = urllib.request.Request(URL + path, data=json.dumps(body).encode() if body is not None else None, method=method,
        headers={'apikey': KEY, 'Authorization': 'Bearer ' + KEY, 'Content-Type': 'application/json'})
    try:
        return json.loads(urllib.request.urlopen(r, timeout=60).read() or b'null')
    except urllib.error.HTTPError as e:
        return {'error': e.code, 'body': e.read().decode()[:200]}

def sql(q):
    r = urllib.request.Request('https://api.supabase.com/v1/projects/%s/database/query' % REF, data=json.dumps({'query': q}).encode(),
        headers={'Authorization': 'Bearer ' + TOKEN, 'Content-Type': 'application/json', 'User-Agent': 'curl/8'})
    try:
        return json.loads(urllib.request.urlopen(r, timeout=120).read())
    except urllib.error.HTTPError as e:
        raise SystemExit('sql failed: %s' % e.read().decode()[:400])

patterns = sys.argv[1:]
if not patterns: raise SystemExit(__doc__)
def match(email):
    for p in patterns:
        if p.startswith('%') and email.endswith(p[1:]): return True
        if email == p: return True
    return False

users = [u for u in api('GET', '/auth/v1/admin/users?per_page=1000')['users'] if match(u['email'])]
ids = [u['id'] for u in users]
if not ids: raise SystemExit('nothing matches')
arr = "array[%s]::text[]" % ','.join("'%s'" % i for i in ids)
cols = "array['uid','owner_id','farmer_id','customer_id','driver_id','sender','reporter_id']"
sql("""do $$
declare r record; ids text[] := %s;
begin
  perform set_config('nolifa.internal','1',true);
  delete from public.reserve_collections where reserve_id in (select id from public.water_reserves where borehole_id in (select id from public.borehole_requests where uid::text = any(ids)));
  delete from public.water_reserves where borehole_id in (select id from public.borehole_requests where uid::text = any(ids));
  for r in select c.table_name, c.column_name from information_schema.columns c
    join information_schema.tables t on t.table_name=c.table_name and t.table_schema=c.table_schema and t.table_type='BASE TABLE'
    where c.table_schema='public' and c.column_name = any(%s)
  loop
    execute format('delete from public.%%I where %%I::text = any($1)', r.table_name, r.column_name) using ids;
  end loop;
  delete from public.order_pins where order_id not in (select id from public.market_orders);
end $$""" % (arr, cols))
for b in ('verification', 'consult-videos', 'farm-brand'):
    for i in ids:
        lst = api('POST', '/storage/v1/object/list/' + b, {'prefix': i + '/', 'limit': 500})
        if isinstance(lst, list) and lst:
            api('DELETE', '/storage/v1/object/' + b, {'prefixes': [i + '/' + x['name'] for x in lst]})
for u in users:
    api('DELETE', '/auth/v1/admin/users/' + u['id'])
print('removed %d accounts and what they owned' % len(users))
