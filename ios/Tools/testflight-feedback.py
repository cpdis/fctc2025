#!/usr/bin/env python3
"""List TestFlight tester feedback (screenshot reports and crash reports),
newest first, and save each screenshot and crash log.

    python3 ios/Tools/testflight-feedback.py
    python3 ios/Tools/testflight-feedback.py --build 14
    python3 ios/Tools/testflight-feedback.py --no-save

Files go to review/testflight-feedback/, which git ignores. Keep them there:
this repo is public, and the screenshots show member names. Apple's
screenshot links expire about a week after each fetch, so the saved file is
the copy that lasts. A file that is already saved is not fetched again.

Auth reuses asc-api.py and its App Store Connect API key. Apple allows the
Admin, App Manager and Developer roles to read feedback.
"""
import argparse, importlib.util, os, sys, urllib.request
from datetime import datetime

# asc-api.py has a hyphen in its name, so load it by path, not by import.
TOOLS = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('asc_api', os.path.join(TOOLS, 'asc-api.py'))
asc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(asc)

BUNDLE_ID = 'com.cpdis.fctc-attendance'
OUT = os.path.normpath(os.path.join(TOOLS, '..', '..', 'review', 'testflight-feedback'))
# Only the build number and the tester's name come back for the linked
# resources; the tester's email stays out of the output.
QUERY = 'include=build,tester&fields[builds]=version&fields[betaTesters]=firstName,lastName&limit=200'


def get(path):
    """GET one page, or stop with the API's own error text."""
    status, data = asc.call('GET', path)
    if status >= 400:
        errors = data.get('errors') or [{'title': f'HTTP {status}'}]
        sys.exit(f'GET {path} failed ({status}):\n  ' + '\n  '.join(
            f"{e.get('title', '')}: {e.get('detail', '')}" for e in errors))
    return data


def get_all(path):
    """GET every page of a list. Returns the items and the included
    resources, keyed by (type, id)."""
    items, included = [], {}
    while path:
        page = get(path)
        items += page.get('data', [])
        for resource in page.get('included', []):
            included[resource['type'], resource['id']] = resource['attributes']
        path = page.get('links', {}).get('next', '').removeprefix(asc.BASE)
    return items, included


def linked(item, name, included):
    """Attributes of the resource that `item` links to as `name`, or {}."""
    ref = item.get('relationships', {}).get(name, {}).get('data')
    return included.get((ref['type'], ref['id']), {}) if ref else {}


def save_files(kind, item, stem):
    """Save the screenshots or the crash log for one report. Returns the paths."""
    if kind == 'crash':
        path = f'{stem}.crash'
        if not os.path.exists(path):
            log = get(f'/v1/betaFeedbackCrashSubmissions/{item["id"]}/crashLog')
            with open(path, 'w') as f:
                f.write(log['data']['attributes']['logText'])
        return [path]
    paths = []
    # Apple serves the screenshots as JPEG.
    for n, shot in enumerate(item['attributes'].get('screenshots') or [], 1):
        path = f'{stem}-{n}.jpg'
        if not os.path.exists(path):
            urllib.request.urlretrieve(shot['url'], path)
        paths.append(path)
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--build', help='only this build number (CFBundleVersion), e.g. 14')
    parser.add_argument('--out', default=OUT, help='folder for screenshots and crash logs')
    parser.add_argument('--no-save', action='store_true', help='print the feedback; save no files')
    args = parser.parse_args()

    apps = get(f'/v1/apps?filter[bundleId]={BUNDLE_ID}').get('data', [])
    if not apps:
        sys.exit(f'No app with bundle ID {BUNDLE_ID}.')
    app_id = apps[0]['id']

    reports = []
    for kind in ('screenshot', 'crash'):
        items, included = get_all(f'/v1/apps/{app_id}/betaFeedback{kind.title()}Submissions?{QUERY}')
        for item in items:
            build = linked(item, 'build', included).get('version', '?')
            tester = linked(item, 'tester', included)
            name = ' '.join(filter(None, (tester.get('firstName'), tester.get('lastName'))))
            reports.append((item['attributes']['createdDate'], kind, item, build, name or 'unknown tester'))
    if args.build:
        reports = [r for r in reports if r[3] == args.build]
    if not reports:
        sys.exit('No feedback' + (f' for build {args.build}.' if args.build else '.'))
    reports.sort(key=lambda r: r[0], reverse=True)
    if not args.no_save:
        os.makedirs(args.out, exist_ok=True)

    for created, kind, item, build, name in reports:
        a = item['attributes']
        # Times print in this Mac's time zone.
        when = datetime.fromisoformat(created).astimezone()
        print(f"{when:%Y-%m-%d %H:%M}  build {build}  {kind}  {name}  "
              f"{a.get('deviceModel')} iOS {a.get('osVersion')}")
        if a.get('comment'):
            print('  ' + a['comment'].strip().replace('\n', '\n  '))
        if not args.no_save:
            stem = os.path.join(args.out, f'{when:%Y-%m-%d-%H%M%S}-build{build}-{kind}')
            for path in save_files(kind, item, stem):
                print('  ->', os.path.relpath(path))
        print()
    print(f'{len(reports)} report(s).')


if __name__ == '__main__':
    main()
