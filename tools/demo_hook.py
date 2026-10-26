#!/usr/bin/env python3
"""Things the recorded demo needs to happen in the backend at a given moment.
    python3 tools/demo_hook.py cold      a staff-typed reading puts the frozen room out of range
    python3 tools/demo_hook.py restore   the room goes back into range
Needs SUPABASE_URL and SUPABASE_SERVICE_KEY. The readings are marked manual (typed by staff), like the real ones."""
import json, os, sys, time, urllib.request
URL, KEY = os.environ['SUPABASE_URL'], os.environ['SUPABASE_SERVICE_KEY']
def post(path, body):
    r = urllib.request.Request(URL + path, data=json.dumps(body).encode(), method='POST',
        headers={'apikey': KEY, 'Authorization': 'Bearer ' + KEY, 'Content-Type': 'application/json', 'Prefer': 'return=minimal'})
    urllib.request.urlopen(r, timeout=30).read()
now = int(time.time() * 1000)
what = sys.argv[1]
c = {'cold': -8.5, 'restore': -19.6}[what]
post('/rest/v1/warehouse_readings', [{'id': 'R-DEMO-%s-%d' % (what, now), 'at': now, 'data': {'hub': 'Durban hub', 'zone': 'frozen', 'c': c, 'at': now, 'manual': True}}])
print('reading', what, c)
