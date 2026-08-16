#!/usr/bin/env python3
"""Minimal App Store Connect API client (no dependencies).

Signs the JWT through the openssl CLI using the key in
~/.appstoreconnect/private_keys. Used for the release chores the runbook
documents: certificate renewal, provisioning profiles, tester management.

    python3 ios/Tools/asc-api.py GET  /v1/apps
    python3 ios/Tools/asc-api.py POST /v1/betaTesters '{"data": ...}'

Override ASC_KEY_ID / ASC_ISSUER_ID via the environment if the key changes.
"""
import base64, json, os, subprocess, sys, tempfile, time, urllib.request

KEY_ID = os.environ.get('ASC_KEY_ID', 'NJDJN4V5L3')
ISSUER = os.environ.get('ASC_ISSUER_ID', '69a6de7a-eb61-47e3-e053-5b8c7c11a4d1')
KEY_PATH = os.path.expanduser(f'~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8')
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


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    method, path = sys.argv[1], sys.argv[2]
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    status, data = call(method, path, body)
    print(status)
    print(json.dumps(data, indent=1))
