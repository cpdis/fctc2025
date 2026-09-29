#!/usr/bin/env python3
"""Set TestFlight "What to Test" notes on one exact build, optionally attach it
to external tester groups, and report where it is available.

Usage (after an upload finishes):
    python3 ios/Tools/testflight-notes.py --build 9 --file ios/testflight-build-9.txt
    python3 ios/Tools/testflight-notes.py --build 9 --file notes.txt --group "FCTC Friends"

--build is the exact CFBundleVersion, never "the latest upload": a build still
processing, or a newer test upload, must not get another build's notes.
Without --group the build stays with the internal groups (FCTC Internal gets
every build on its own). Name an external group to release to it; its first
build of a version may then need Apple's beta review.

Auth uses the App Store Connect API key in ~/.appstoreconnect/private_keys.
No third-party dependencies (JWT is signed through the openssl CLI).
"""
import argparse, base64, json, os, subprocess, sys, tempfile, time, urllib.request

KEY_ID = os.environ.get('ASC_KEY_ID', 'NJDJN4V5L3')
ISSUER = os.environ.get('ASC_ISSUER_ID', '69a6de7a-eb61-47e3-e053-5b8c7c11a4d1')
KEY_PATH = os.path.expanduser(f'~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8')
BUNDLE_ID = 'com.cpdis.fctc-attendance'
LOCALE = 'en-AU'
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
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--build', required=True, help='exact build number (CFBundleVersion), e.g. 9')
    parser.add_argument('--file', required=True, help='What to Test notes, plain text')
    parser.add_argument('--group', action='append', default=[],
                        help='external group to attach the build to; repeat for more')
    args = parser.parse_args()
    notes = open(args.file).read().strip()
    if not notes:
        sys.exit('Empty notes.')

    _, data = call('GET', f'/v1/apps?filter[bundleId]={BUNDLE_ID}')
    app_id = data['data'][0]['id']

    # This exact build; wait for it to appear and finish processing.
    for _ in range(60):
        _, data = call('GET', f'/v1/builds?filter[app]={app_id}&filter[version]={args.build}&limit=1')
        builds = data.get('data', [])
        state = builds[0]['attributes']['processingState'] if builds else 'NOT UPLOADED YET'
        if state == 'VALID':
            break
        if state in ('FAILED', 'INVALID'):
            sys.exit(f'Build {args.build} is {state}.')
        print(f'build {args.build} is {state}; waiting...')
        time.sleep(30)
    else:
        sys.exit(f'Build {args.build} did not become VALID in 30 minutes.')
    build_id = builds[0]['id']
    print(f'build {args.build} ({build_id})')

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
    groups = {g['attributes']['name']: g for g in data.get('data', [])}
    for name in args.group:
        group = groups.get(name)
        if not group or group['attributes'].get('isInternalGroup'):
            sys.exit(f'No external group named {name!r}.')
        status, err = call('POST', f'/v1/betaGroups/{group["id"]}/relationships/builds',
                           {'data': [{'type': 'builds', 'id': build_id}]})
        print(f'attach to {name}:', 'done' if status in (200, 201, 204) else json.dumps(err)[:200])

    # Where the build stands now: group membership alone does not prove access.
    _, data = call('GET', f'/v1/builds/{build_id}/buildBetaDetail')
    detail = data.get('data', {}).get('attributes', {})
    print('internal state:', detail.get('internalBuildState'))
    print('external state:', detail.get('externalBuildState'))
    _, data = call('GET', f'/v1/betaGroups?filter[builds]={build_id}')
    print('groups with the build:', ', '.join(g['attributes']['name'] for g in data.get('data', [])) or 'none listed')


if __name__ == '__main__':
    main()
