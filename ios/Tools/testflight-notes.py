#!/usr/bin/env python3
"""Set TestFlight "What to Test" notes on the latest build and attach it to
the tester groups.

Usage (after an upload finishes):
    python3 ios/Tools/testflight-notes.py "Notes for testers."
    python3 ios/Tools/testflight-notes.py --file notes.txt

Auth uses the App Store Connect API key in ~/.appstoreconnect/private_keys.
No third-party dependencies (JWT is signed through the openssl CLI).
"""
import base64, json, os, subprocess, sys, tempfile, time, urllib.request

KEY_ID = os.environ.get('ASC_KEY_ID', 'NJDJN4V5L3')
ISSUER = os.environ.get('ASC_ISSUER_ID', '69a6de7a-eb61-47e3-e053-5b8c7c11a4d1')
KEY_PATH = os.path.expanduser(f'~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8')
BUNDLE_ID = 'com.cpdis.fctc-attendance'
LOCALE = 'en-AU'
# Groups every new build should reach. Internal groups with access-to-all-builds
# pick builds up automatically; external groups need the explicit attach.
EXTERNAL_GROUPS = ['FCTC Friends']
BASE = 'https://api.appstoreconnect.apple.com'


def b64u(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=')


def der_to_raw(der):
    i = 2
    assert der[i] == 0x02; l = der[i + 1]; r = der[i + 2:i + 2 + l]; i += 2 + l
    assert der[i] == 0x02; l = der[i + 1]; s = der[i + 2:i + 2 + l]
    return r.lstrip(b'\x00').rjust(32, b'\x00') + s.lstrip(b'\x00').rjust(32, b'\x00')


def token():
    header = b64u(json.dumps({'alg': 'ES256', 'kid': KEY_ID, 'typ': 'JWT'}).encode())
    now = int(time.time())
    payload = b64u(json.dumps({'iss': ISSUER, 'iat': now, 'exp': now + 900,
                               'aud': 'appstoreconnect-v1'}).encode())
    signing_input = header + b'.' + payload
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(signing_input)
        path = f.name
    sig = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', KEY_PATH, path],
                        capture_output=True, check=True).stdout
    os.unlink(path)
    return (signing_input + b'.' + b64u(der_to_raw(sig))).decode()


def call(method, path, body=None):
    req = urllib.request.Request(
        BASE + path, method=method,
        headers={'Authorization': f'Bearer {token()}',
                 'Content-Type': 'application/json'},
        data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req) as r:
            text = r.read()
            return r.status, json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b'{}')


def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    notes = open(args[1]).read().strip() if args[0] == '--file' else ' '.join(args)
    if not notes:
        sys.exit('Empty notes.')

    _, data = call('GET', f'/v1/apps?filter[bundleId]={BUNDLE_ID}')
    app_id = data['data'][0]['id']

    # Latest build; wait for processing to finish so the notes attach cleanly.
    for _ in range(60):
        _, data = call('GET', f'/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=1')
        build = data['data'][0]
        state = build['attributes']['processingState']
        if state == 'VALID':
            break
        if state in ('FAILED', 'INVALID'):
            sys.exit(f'Build {build["attributes"]["version"]} is {state}.')
        print(f'build {build["attributes"]["version"]} is {state}; waiting...')
        time.sleep(30)
    build_id = build['id']
    print(f'build {build["attributes"]["version"]} ({build_id})')

    _, data = call('GET', f'/v1/builds/{build_id}/betaBuildLocalizations')
    existing = [l for l in data.get('data', [])
                if l['attributes'].get('locale') == LOCALE]
    if existing:
        status, data = call('PATCH', f'/v1/betaBuildLocalizations/{existing[0]["id"]}', {
            'data': {'type': 'betaBuildLocalizations', 'id': existing[0]['id'],
                     'attributes': {'whatsNew': notes}}})
    else:
        status, data = call('POST', '/v1/betaBuildLocalizations', {
            'data': {'type': 'betaBuildLocalizations',
                     'attributes': {'locale': LOCALE, 'whatsNew': notes},
                     'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})
    print('what to test:', 'set' if status in (200, 201) else json.dumps(data)[:300])

    _, data = call('GET', f'/v1/apps/{app_id}/betaGroups')
    for group in data.get('data', []):
        if group['attributes']['name'] in EXTERNAL_GROUPS:
            status, err = call('POST', f'/v1/betaGroups/{group["id"]}/relationships/builds',
                               {'data': [{'type': 'builds', 'id': build_id}]})
            ok = status in (200, 201, 204)
            print(f'attach to {group["attributes"]["name"]}:',
                  'done' if ok else json.dumps(err)[:200])


if __name__ == '__main__':
    main()
