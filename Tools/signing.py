#!/usr/bin/env python3
"""Developer ID policy shared by the build and notarization tools. No secrets."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess


def identities():
    output = subprocess.check_output(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    found = []
    for digest, name in re.findall(r'\b([A-Fa-f0-9]{40})\s+"([^"]+)"', output):
        team = re.search(r'\(([A-Z0-9]{10})\)$', name)
        if name.startswith('Developer ID Application: ') and team:
            found.append({'identity': digest.upper(), 'name': name, 'team': team[1]})
    return found


def select_identity(requested=None):
    found = identities()
    if requested:
        found = [item for item in found if requested in (item['identity'], item['name']) or requested.upper() == item['identity']]
    if len(found) != 1:
        raise ValueError('Select one valid Developer ID Application identity in Xcode → Settings → Accounts → Manage Certificates. Apple Development and Apple Distribution cannot notarize this app.')
    return found[0]


def requirement(team, bundle_id):
    if not re.fullmatch(r'[A-Z0-9]{10}', team) or bundle_id not in ('local.retinalink.Host', 'local.retinalink.Viewer'):
        raise ValueError('Invalid signing team or RetinaLink bundle identifier')
    return (f'anchor apple generic and identifier "{bundle_id}" and '
            'certificate 1[field.1.2.840.113635.100.6.2.6] exists and '
            'certificate leaf[field.1.2.840.113635.100.6.1.13] exists and '
            f'certificate leaf[subject.OU] = "{team}"')


def sign(app, identity):
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', identity['identity'], '--options', 'runtime', '--timestamp', str(app)], check=True)


def verify_app(app, identity, role):
    app = pathlib.Path(app)
    info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
    bundle_id = 'local.retinalink.' + role
    if info.get('CFBundleIdentifier') != bundle_id or info.get('RetinaLinkSigningTeam') != identity['team']:
        raise ValueError('Unexpected bundle identifier or signing-team metadata')
    if info.get('RetinaLinkTrustNamespace') != 'local.retinalink.device-trust':
        raise ValueError('Distribution builds must retain the stable pairing namespace')
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', '--deep', '-R='+requirement(identity['team'], bundle_id), str(app)], check=True)
    details = subprocess.check_output(['/usr/bin/codesign', '-dvvv', str(app)], stderr=subprocess.STDOUT, text=True)
    dr = subprocess.check_output(['/usr/bin/codesign', '-d', '-r-', str(app)], stderr=subprocess.STDOUT, text=True)
    entitlements = subprocess.run(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True, check=True).stdout
    if 'runtime' not in details or not re.search(r'^Timestamp=', details, re.M):
        raise ValueError('Hardened Runtime and a secure timestamp are required')
    if 'cdhash' in dr or identity['team'] not in dr:
        raise ValueError('The designated requirement must be stable across builds')
    if entitlements.strip() and plistlib.loads(entitlements).get('com.apple.security.get-task-allow'):
        raise ValueError('Distribution must not allow debugger attachment')
    exe = app/'Contents/MacOS/RetinaLink'
    return {'bundle_id': bundle_id, 'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
            'team': identity['team'], 'designated_requirement': dr.split('designated => ', 1)[-1].strip(),
            'executable_sha256': hashlib.sha256(exe.read_bytes()).hexdigest()}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['identity'])
    parser.add_argument('--identity')
    args = parser.parse_args()
    try:
        print(json.dumps(select_identity(args.identity)))
    except (ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error)+'\n')
