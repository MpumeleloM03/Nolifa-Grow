#!/usr/bin/env python3
"""Sets Fatboy Butcheries up as a real seller in the Nolifa cloud: verified, farm
application approved, plan on, and the warehouse stock and room temperatures their
farmer screen shows. Needs SUPABASE_URL and SUPABASE_SERVICE_KEY in the environment.
Safe to run again: it replaces its own rows.

The warehouse quantities and temperatures are SEEDED so the pitch has something to
show. They are labelled 'Demo stock' in the lot note. Real deposits and readings come
from the warehouse desk in the back office."""
import json, os, time, urllib.request

URL, KEY = os.environ['SUPABASE_URL'], os.environ['SUPABASE_SERVICE_KEY']
FATBOY = os.environ.get('FATBOY_UID', '037e1d9f-87a4-452a-bb94-6df869881233')

def call(method, path, body=None, prefer='return=minimal'):
    req = urllib.request.Request(URL + path, data=json.dumps(body).encode() if body is not None else None, method=method,
        headers={'apikey': KEY, 'Authorization': 'Bearer ' + KEY, 'Content-Type': 'application/json', 'Prefer': prefer})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=60).read() or b'null')
    except urllib.error.HTTPError as e:
        raise SystemExit('%s %s -> %s %s' % (method, path, e.code, e.read().decode()[:300]))

now = int(time.time() * 1000)
day = 86400000
call('POST', '/rest/v1/verified_users?on_conflict=uid', [{'uid': FATBOY}], 'resolution=merge-duplicates,return=minimal')
call('POST', '/rest/v1/farm_applications?on_conflict=uid', [{
    'uid': FATBOY, 'status': 'approved', 'reviewed_at': '2026-10-25T08:00:00Z', 'review_note': '',
    'data': {'fullName': 'Islilo Farming', 'farmName': 'Fatboy Butcheries', 'province': 'KwaZulu-Natal', 'town': 'uMhlanga',
             'businessKind': 'company', 'sells': 'Beef, chicken and sausage, cut to order'}}], 'resolution=merge-duplicates,return=minimal')
call('POST', '/rest/v1/seller_plans?on_conflict=uid', [{'uid': FATBOY, 'plan': 'grow'}], 'resolution=merge-duplicates,return=minimal')

# Their logo and store picture, the way a farm uploads them with its application.
def upload(path, local, mime):
    req = urllib.request.Request(URL + '/storage/v1/object/farm-brand/' + path, data=open(local, 'rb').read(), method='POST',
        headers={'apikey': KEY, 'Authorization': 'Bearer ' + KEY, 'Content-Type': mime, 'x-upsert': 'true'})
    try:
        urllib.request.urlopen(req, timeout=60).read()
    except urllib.error.HTTPError as e:
        raise SystemExit('upload %s -> %s %s' % (path, e.code, e.read().decode()[:300]))
ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'packages', 'ubuntu_core', 'assets', 'farms')
logo, banner = FATBOY + '/logo-fatboy.png', FATBOY + '/banner-fatboy.jpg'
upload(logo, os.path.join(ASSETS, 'logo_fatboy.png'), 'image/png')
upload(banner, os.path.join(ASSETS, 'banner_fatboy.jpg'), 'image/jpeg')
call('DELETE', '/rest/v1/application_files?uid=eq.%s&kind=in.(farm_logo,farm_banner)' % FATBOY)
call('POST', '/rest/v1/application_files', [{'uid': FATBOY, 'kind': 'farm_logo', 'path': logo}, {'uid': FATBOY, 'kind': 'farm_banner', 'path': banner}])
call('POST', '/rest/v1/farm_profiles?on_conflict=uid', [{'uid': FATBOY, 'data': {
    'farmName': 'Fatboy Butcheries', 'province': 'KwaZulu-Natal', 'town': 'uMhlanga', 'farmKind': 'livestock',
    'products': [], 'practices': {}, 'registered': False, 'logo': logo, 'banner': banner}}], 'resolution=merge-duplicates,return=minimal')

prods = call('GET', '/rest/v1/market_products?owner_id=eq.%s&select=id,data' % FATBOY)
# What each product has in the warehouse: (room, kg deposited, kg left, days to use-by, bay)
PLAN = {
    'Beef mince': ('chilled', 60, 48, 6, 'C1-01'), 'Beef fillet': ('chilled', 20, 14, 6, 'C1-02'), 'Beef stew': ('chilled', 40, 31, 6, 'C1-03'),
    'Beef T-bone': ('chilled', 30, 22, 6, 'C1-04'), 'Brisket': ('chilled', 25, 25, 6, 'C1-05'), 'Beef sausage': ('chilled', 35, 27, 8, 'C1-06'),
    'Chicken breast': ('frozen', 80, 64, 90, 'F1-01'), 'Chicken thighs': ('frozen', 60, 52, 90, 'F1-02'),
    'Chicken drumsticks': ('frozen', 50, 41, 90, 'F1-03'), 'Chicken wings': ('frozen', 45, 36, 90, 'F1-04'),
}
call('DELETE', '/rest/v1/warehouse_lots?farmer_id=eq.%s' % FATBOY)
lots = []
for i, p in enumerate(prods):
    name = p['data']['name']
    zone, qty, left, days, bay = PLAN.get(name, ('chilled', 20, 15, 6, 'C2-%02d' % i))
    lots.append({'id': 'LOT-FB-%02d' % (i + 1), 'farmer_id': FATBOY, 'data': {
        'id': 'LOT-FB-%02d' % (i + 1), 'hub': 'Durban hub', 'farmerId': FATBOY, 'farmName': 'Fatboy Butcheries', 'product': name,
        'category': 'meat', 'unit': 'kg', 'qty': qty, 'remaining': left, 'zone': zone, 'useBy': now + days * day, 'expectedAt': now - day,
        'status': 'stored', 'tag': 'NLF-FB-%02d' % (i + 1), 'bay': bay, 'receivedAt': now - day,
        'receivedTempC': 2.2 if zone == 'chilled' else -19.0, 'note': 'Demo stock for the pitch', 'events': []}})
call('POST', '/rest/v1/warehouse_lots', lots)
# Room temperatures. The latest row per room is what a farmer sees.
for rid, zone, c in (('R-SEED-C', 'chilled', 2.4), ('R-SEED-F', 'frozen', -19.6), ('R-SEED-K', 'cool', 10.1), ('R-SEED-A', 'ambient', 18.0)):
    call('DELETE', '/rest/v1/warehouse_readings?id=eq.%s' % rid)
    call('POST', '/rest/v1/warehouse_readings', [{'id': rid, 'at': now, 'data': {'hub': 'Durban hub', 'zone': zone, 'c': c, 'at': now, 'manual': True}}])
print('Fatboy set up: %d products, %d warehouse lots' % (len(prods), len(lots)))
