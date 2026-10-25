#!/usr/bin/env python3
"""Walks the real demo accounts through the staff-facing parts of the system in the Nolifa
cloud, the way the apps and the back office do, and checks each step:

  farm application with logo and store picture -> staff approval -> farm published and told
  -> a plan switch (checkout started, then paid) -> driver application -> staff approval

Needs SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_KEY. The logins come from
~/nolifa-accounts.local.txt (see tools/create_test_accounts.py). The ID photos it uploads are
plain grey placeholders named TEST. A short-lived staff account is made for the approvals and
removed at the end."""
import json, os, re, secrets, string, struct, sys, urllib.request, zlib

URL, ANON, KEY = os.environ['SUPABASE_URL'], os.environ['SUPABASE_ANON_KEY'], os.environ['SUPABASE_SERVICE_KEY']
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
ok_count = 0
RUN = secrets.token_hex(3)  # file names are new each run: the apps never overwrite a file

def check(cond, what):
    global ok_count
    if not cond:
        print('FAIL', what); sys.exit(1)
    ok_count += 1
    print('ok  ', what)

def call(method, path, body=None, token=None, key=ANON, raw=None, ctype='application/json', extra=None):
    h = {'apikey': key, 'Authorization': 'Bearer ' + (token or key)}
    if raw is None: h['Content-Type'] = ctype
    else: h['Content-Type'] = ctype
    h.update(extra or {})
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(URL + path, data=data, method=method, headers=h)
    try:
        out = urllib.request.urlopen(req, timeout=90).read()
        return json.loads(out) if out else None
    except urllib.error.HTTPError as e:
        return {'__error__': e.code, 'body': e.read().decode()[:300]}

def failed(r): return isinstance(r, dict) and '__error__' in r

def accounts():
    out = {}
    for line in open(os.path.expanduser('~/nolifa-accounts.local.txt')):
        m = re.match(r'(fatboy|customer|driver)\s+(\S+)\s+(\S+)\s+\(uid (\S+)\)', line)
        if m: out[m.group(1)] = {'email': m.group(2), 'password': m.group(3), 'uid': m.group(4)}
    return out

def login(email, password):
    r = call('POST', '/auth/v1/token?grant_type=password', {'email': email, 'password': password})
    check(not failed(r) and 'access_token' in r, 'signed in as ' + email)
    return r['access_token']

def png(grey=170, size=96):
    rows = b''.join(b'\x00' + bytes([grey]) * size * 3 for _ in range(size))
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')

def upload(bucket, path, data, ctype, token):
    r = call('POST', '/storage/v1/object/%s/%s' % (bucket, path), raw=data, ctype=ctype, token=token)
    check(not failed(r), 'uploaded %s/%s' % (bucket, path))

acc = accounts()
check(set(acc) == {'fatboy', 'customer', 'driver'}, 'the three demo accounts are in the logins file')
farm, driver = acc['fatboy'], acc['driver']

# A short-lived staff account for the approvals.
pw = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(14)) + '-7q'
qa_email = 'qa-staff-%s@example.com' % secrets.token_hex(3)
qa = call('POST', '/auth/v1/admin/users', {'email': qa_email, 'password': pw, 'email_confirm': True, 'app_metadata': {'admin': True}}, key=KEY)
check(not failed(qa), 'staff account made for the checks')
try:
    boss = login(qa_email, pw)
    f_tok = login(farm['email'], farm['password'])
    d_tok = login(driver['email'], driver['password'])
    fid, did = farm['uid'], driver['uid']

    # ---- farm application ----
    r = call('POST', '/rest/v1/rpc/save_application', {'p_data': {
        'fullName': 'Islilo Farming', 'idNumber': '8001015009087', 'phone': '0821234567', 'farmName': 'Fatboy Butcheries',
        'province': 'KwaZulu-Natal', 'town': 'uMhlanga', 'lat': -29.72, 'lng': 31.08, 'sizeHa': 1.0, 'farmKind': 'livestock',
        'kind': 'company', 'businessName': 'Islilo Farming', 'consent': True,
        'practices': {'feeds': ['Bought feed'], 'vaccineProgramme': 'Supplier certified'},
        'products': ['Beef', 'Chicken', 'Sausage']}}, token=f_tok)
    check(not failed(r), 'farm application saved')
    r = call('POST', '/rest/v1/rpc/submit_application', {}, token=f_tok)
    check(failed(r) and 'Still missing' in r['body'], 'submit refused without the photos, logo and store picture')
    for kind in ('id_front', 'selfie_with_id', 'land_photo'):
        p = '%s/%s-%s-TEST.png' % (fid, kind, RUN)
        upload('verification', p, png(), 'image/png', f_tok)
        check(not failed(call('POST', '/rest/v1/rpc/add_application_file', {'p_kind': kind, 'p_path': p}, token=f_tok)), 'registered ' + kind)
    r = call('POST', '/rest/v1/rpc/submit_application', {}, token=f_tok)
    check(failed(r), 'submit still refused: the logo and store picture are required')
    assets = os.path.join(ROOT, 'packages', 'ubuntu_core', 'assets', 'farms')
    for kind, fname, ct in (('farm_logo', 'logo_fatboy.png', 'image/png'), ('farm_banner', 'banner_fatboy.jpg', 'image/jpeg')):
        p = '%s/%s-%s-%s' % (fid, kind, RUN, fname)
        upload('farm-brand', p, open(os.path.join(assets, fname), 'rb').read(), ct, f_tok)
        check(not failed(call('POST', '/rest/v1/rpc/add_application_file', {'p_kind': kind, 'p_path': p}, token=f_tok)), 'registered ' + kind)
    check(not failed(call('POST', '/rest/v1/rpc/submit_application', {}, token=f_tok)), 'farm application submitted')

    # ---- staff approve ----
    r = call('POST', '/rest/v1/rpc/review_application', {'p_uid': fid, 'p_decision': 'approved', 'p_note': ''}, token=f_tok)
    check(failed(r), 'a farmer cannot approve their own application')
    r = call('POST', '/rest/v1/rpc/review_application', {'p_uid': fid, 'p_decision': 'approved', 'p_note': 'Checked in the e2e run'}, token=boss)
    check(not failed(r), 'staff approved the farm')
    prof = call('GET', '/rest/v1/farm_profiles?uid=eq.%s&select=data' % fid, token=login(acc['customer']['email'], acc['customer']['password']))
    check(prof and prof[0]['data'].get('logo') and prof[0]['data'].get('banner'), 'buyers can read the farm profile with its logo and store picture')
    logo_url = '%s/storage/v1/object/public/farm-brand/%s' % (URL, prof[0]['data']['logo'])
    check(urllib.request.urlopen(logo_url).status == 200, 'the logo loads without signing in')
    notes = call('GET', '/rest/v1/notifications?uid=eq.%s&select=kind,title' % fid, token=f_tok)
    check(any(n['kind'] == 'farm_application' for n in notes), 'the farm was told it is approved: ' + [n['title'] for n in notes if n['kind'] == 'farm_application'][0])
    check(call('GET', '/rest/v1/verified_users?uid=eq.%s' % fid, token=f_tok) != [], 'the farm is verified, so selling opens')

    # ---- plan switch ----
    r = call('POST', '/functions/v1/yoco-checkout', {'plan': 'grow'}, token=f_tok)
    check(not failed(r) and str(r.get('url', '')).startswith('https://'), 'checkout for the Grow plan started (a card page opens)')
    r = call('POST', '/functions/v1/yoco-checkout', {'plan': 'starter'}, token=f_tok)
    check(failed(r) and r['__error__'] == 409, 'switching to the plan you are on is refused')
    pays = call('GET', '/rest/v1/payments?uid=eq.%s&kind=eq.plan&select=id,checkout_id,amount_cents,tier' % fid, token=f_tok)
    check(pays and pays[0]['amount_cents'] == 9900 and pays[0]['tier'] == 'grow', 'the server priced it at R99')
    r = call('POST', '/rest/v1/rpc/activate_plan_paid', {'p_payment': pays[0]['id'], 'p_checkout': pays[0]['checkout_id']}, token=f_tok)
    check(failed(r), 'a phone cannot confirm its own payment')
    r = call('POST', '/rest/v1/rpc/activate_plan_paid', {'p_payment': pays[0]['id'], 'p_checkout': pays[0]['checkout_id']}, key=KEY)
    check(r == 'activated', 'the signed payment switches the plan on')
    check(call('GET', '/rest/v1/seller_plans?uid=eq.%s&select=plan' % fid, token=f_tok)[0]['plan'] == 'grow', 'the farm sees Grow at once')

    # ---- driver application ----
    r = call('POST', '/rest/v1/rpc/save_driver_application', {'p_data': {
        'fullName': 'Sipho Driver', 'idNumber': '8001015009087', 'phone': '0829876543', 'vehicle': 'motorbike', 'plate': 'ND 12345', 'licenceCode': 'A', 'consent': True}}, token=d_tok)
    check(not failed(r), 'driver application saved')
    for kind in ('driver_id_front', 'driver_selfie_with_id', 'driver_licence', 'driver_vehicle'):
        p = '%s/%s-%s-TEST.png' % (did, kind, RUN)
        upload('verification', p, png(150), 'image/png', d_tok)
        check(not failed(call('POST', '/rest/v1/rpc/add_application_file', {'p_kind': kind, 'p_path': p}, token=d_tok)), 'registered ' + kind)
    check(not failed(call('POST', '/rest/v1/rpc/submit_driver_application', {}, token=d_tok)), 'driver application submitted')
    check(call('GET', '/rest/v1/approved_drivers?uid=eq.%s' % did, token=d_tok) == [], 'a driver cannot take jobs before approval')
    check(not failed(call('POST', '/rest/v1/rpc/review_driver_application', {'p_uid': did, 'p_decision': 'approved', 'p_note': ''}, token=boss)), 'staff approved the driver')
    check(call('GET', '/rest/v1/approved_drivers?uid=eq.%s' % did, token=d_tok) != [], 'the driver is approved')
    dn = call('GET', '/rest/v1/notifications?uid=eq.%s&select=kind,title' % did, token=d_tok)
    check(any(n['kind'] == 'driver_application' for n in dn), 'the driver was told: ' + [n['title'] for n in dn if n['kind'] == 'driver_application'][0])
finally:
    for u in call('GET', '/auth/v1/admin/users?per_page=1000', key=KEY)['users']:
        if u['email'] == qa_email:
            call('DELETE', '/auth/v1/admin/users/' + u['id'], key=KEY)
print('\n%d checks passed' % ok_count)
