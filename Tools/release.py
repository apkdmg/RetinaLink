#!/usr/bin/env python3
"""Developer ID build, resumable Apple notarization, stapling and packaging.

Credentials are read by Apple's notarytool from Keychain, never from this script
or a configuration file. Nothing is installed or published by these commands.
"""
import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import time

from signing import identities, select_identity, sign, verify_app

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROFILE = 'RetinaLink-Notary'


def run(arguments, **kwargs):
    return subprocess.run([str(a) for a in arguments], check=True, **kwargs)


def notary(arguments, profile):
    result = run(['/usr/bin/xcrun', 'notarytool']+arguments+['--keychain-profile', profile, '--output-format', 'json'], capture_output=True, text=True)
    return json.loads(result.stdout)


def digest(path):
    return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()


def save(directory, state):
    path = directory/'release-state.json'
    temp = directory/'release-state.next'
    temp.write_text(json.dumps(state, indent=2)+'\n')
    temp.replace(path)


def archive(app, destination):
    if destination.exists():
        destination.unlink()
    run(['/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, destination])


def credentials(args):
    # Never record input, command arguments, or Apple's interactive output.
    # Password entry stays attached directly to Apple's secure Terminal prompt.
    marker = ROOT/'work/notary-credentials-ready.json'
    report = ROOT/'work/notary-credentials-status.json'
    report.parent.mkdir(parents=True, exist_ok=True)
    marker.unlink(missing_ok=True)
    status = {'profile': args.profile, 'authenticated': False, 'stage': 'terminal',
              'time': time.time()}

    def checkpoint(stage, **details):
        status.update(stage=stage, time=time.time(), **details)
        temporary = report.with_suffix('.next')
        # Create privately even when the user's default umask is permissive.
        with os.fdopen(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as file:
            json.dump(status, file, indent=2)
            file.write('\n')
        temporary.replace(report)

    checkpoint('terminal')
    try:
        _store_credentials(args, marker, checkpoint)
    except (Exception, KeyboardInterrupt) as error:
        details = {'result': 'failed', 'error_type': type(error).__name__}
        if isinstance(error, subprocess.CalledProcessError):
            details['exit_code'] = error.returncode
        checkpoint(status['stage'], **details)
        print('Setup diagnostic (no credentials): '+str(report), file=sys.stderr)
        raise


def _store_credentials(args, marker, checkpoint):
    if not sys.stdin.isatty():
        raise ValueError('Run python3 Tools/release.py credentials in your own Terminal. The password is entered only into Apple’s hidden prompt.')
    checkpoint('signing_identity')
    identity = select_identity(args.identity)
    checkpoint('apple_id_entry', team=identity['team'])
    apple_id = input('Developer Apple ID (email): ').strip()
    if not apple_id or any(c.isspace() for c in apple_id):
        raise ValueError('Enter a valid Developer Apple ID.')
    print('Enter an app-specific password at Apple’s secure prompt. RetinaLink does not read or save it.')
    checkpoint('apple_validation_and_keychain_save')
    run(['/usr/bin/xcrun', 'notarytool', 'store-credentials', args.profile,
         '--apple-id', apple_id, '--team-id', identity['team'], '--validate'])
    # Verify the same profile immediately; a successful interactive command
    # must not be mistaken for a usable saved login in another context.
    checkpoint('saved_profile_verification')
    notary(['history'], args.profile)
    marker.write_text(json.dumps({'profile':args.profile, 'team':identity['team'],
                                 'authenticated':True, 'time':time.time()}, indent=2)+'\n')
    checkpoint('complete', result='success', authenticated=True)
    print('Saved and verified notarization profile: '+args.profile)


def doctor(args):
    found = identities()
    print(json.dumps({'developer_id_application_identities': found, 'notary_profile': args.profile}, indent=2))
    select_identity(args.identity)
    notary(['history'], args.profile)
    print('Developer ID identity and notarization Keychain profile are ready.')


def prepare(args):
    identity = select_identity(args.identity)
    directory = args.directory.resolve()
    if directory.exists() and any(directory.iterdir()):
        raise ValueError('Choose an empty release directory; an in-flight release must be resumed, not overwritten.')
    directory.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ, RETINALINK_BUILD_DIR=str(directory/'build'), RETINALINK_SIGN_IDENTITY=identity['identity'])
    if args.build_number:
        environment['RETINALINK_BUILD_NUMBER'] = str(args.build_number)
    run(['/bin/bash', ROOT/'build.sh'], cwd=ROOT, env=environment)
    apps = {role: verify_app(directory/f'build/apps/RetinaLink {role}.app', identity, role) for role in ['Host', 'Viewer']}
    if apps['Host']['version'] != apps['Viewer']['version'] or apps['Host']['build'] != apps['Viewer']['build']:
        raise ValueError('Host and Viewer versions must match')
    source_commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=normal'], cwd=ROOT, text=True).strip())
    state = {'format': 1, 'identity': identity, 'profile': args.profile, 'source_commit': source_commit,
             'source_dirty': dirty, 'apps': apps, 'submissions': {}, 'complete': False}
    save(directory, state)
    print('Signed with Hardened Runtime, secure timestamps and stable designated requirements. Next: advance.')


def submission(directory, state, role, app):
    record = state['submissions'].get(role)
    if record is None:
        upload = directory/f'{role}-notary-upload.zip'
        archive(app, upload)
        result = notary(['submit', str(upload), '--no-wait'], state['profile'])
        record = {'id': result['id'], 'archive': upload.name, 'sha256': digest(upload), 'status': result.get('status', 'In Progress')}
        state['submissions'][role] = record
        save(directory, state)
        print(f'{role} submitted to Apple: {record["id"]}. Resume with advance; do not rebuild.')
        return False
    if digest(directory/record['archive']) != record['sha256']:
        raise ValueError('The submitted archive changed; refusing to reuse its notarization result.')
    result = notary(['info', record['id']], state['profile'])
    record['status'] = result['status']
    save(directory, state)
    print(role+': '+record['status'])
    if record['status'] == 'Accepted':
        if not record.get('stapled'):
            run(['/usr/bin/xcrun', 'stapler', 'staple', app])
            run(['/usr/bin/xcrun', 'stapler', 'validate', app])
            run(['/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=2', app])
            record['stapled'] = True
            save(directory, state)
        return True
    if record['status'] != 'In Progress':
        log = notary(['log', record['id']], state['profile'])
        (directory/(role+'-notary-log.json')).write_text(json.dumps(log, indent=2)+'\n')
        raise ValueError(role+' notarization failed; inspect '+role+'-notary-log.json. No distributable was created.')
    return False


def advance(args):
    directory = args.directory.resolve()
    state = json.loads((directory/'release-state.json').read_text())
    identity = select_identity(state['identity']['identity'])
    if identity['team'] != state['identity']['team']:
        raise ValueError('The release signing team changed')
    apps = {role: directory/f'build/apps/RetinaLink {role}.app' for role in ['Host', 'Viewer']}
    for role, app in apps.items():
        actual = verify_app(app, identity, role)
        if actual != state['apps'][role]:
            raise ValueError(role+' executable or identity changed during notarization')
    if state.get('complete'):
        published = directory/state['distribution']['file']
        if digest(published) != state['distribution']['sha256']:
            raise ValueError('The completed distribution archive changed')
        for app in apps.values():
            run(['/usr/bin/xcrun', 'stapler', 'validate', app])
        print('Already complete; the existing distribution archive is unchanged: '+str(published))
        return 0
    if not submission(directory, state, 'Viewer', apps['Viewer']):
        return 3
    viewer_zip = apps['Host']/'Contents/Resources/RetinaLink Viewer.zip'
    if not state.get('stapled_viewer_embedded'):
        if 'Host' in state['submissions']:
            raise ValueError('Host was submitted before its stapled Viewer was embedded')
        archive(apps['Viewer'], viewer_zip)
        sign(apps['Host'], identity)
        sealed = verify_app(apps['Host'], identity, 'Host')
        if any(sealed[k] != state['apps']['Host'][k] for k in sealed if k != 'executable_sha256'):
            raise ValueError('Re-signing changed the stable Host identity')
        # The secure timestamp and sealed-resource digest change the signature
        # bytes inside the Mach-O even though the executable code is unchanged.
        state['apps']['Host'] = sealed
        state['stapled_viewer_embedded'] = digest(viewer_zip)
        save(directory, state)
    if digest(viewer_zip) != state['stapled_viewer_embedded']:
        raise ValueError('Bundled Viewer changed after sealing Host')
    if not submission(directory, state, 'Host', apps['Host']):
        return 3
    # Verify the ticket survives extraction of the exact ZIP that Host deploys.
    with tempfile.TemporaryDirectory(dir=directory, prefix='verify-viewer-') as temp:
        run(['/usr/bin/ditto', '-x', '-k', viewer_zip, temp])
        viewer = pathlib.Path(temp)/'RetinaLink Viewer.app'
        if verify_app(viewer, identity, 'Viewer') != state['apps']['Viewer']:
            raise ValueError('Bundled Viewer differs from the notarized app')
        run(['/usr/bin/xcrun', 'stapler', 'validate', viewer])
    for app in apps.values():
        run(['/usr/bin/xcrun', 'stapler', 'validate', app])
    version = state['apps']['Host']['version']
    package = directory/f'RetinaLink-{version}'
    package.mkdir(exist_ok=True)
    run(['/usr/bin/ditto', apps['Host'], package/'RetinaLink Host.app'])
    (package/'Start Here.txt').write_text(
        'Open RetinaLink Host on your main Mac from a permanent Applications folder. Choose Add Display.\n'
        'Viewer is included and installed from Host. Enable Remote Login and sign in on a new iMac once.\n'
        'Allow Screen Recording on the main Mac when macOS asks. After setup, Viewer starts fullscreen after sign-in and reconnects automatically.\n'
        'FileVault and login settings stay unchanged. FileVault on an Intel iMac still needs disk unlock after restart.\n'
        'For future Viewer upgrades, choose Update Display Software on Host. Pairing is retained between releases signed by the same developer.\n')
    final_zip = directory/(package.name+'.zip')
    archive(package, final_zip)
    state['complete'] = True
    state['distribution'] = {'file': final_zip.name, 'sha256': digest(final_zip), 'viewer_ticket_embedded': True}
    save(directory, state)
    print('Accepted, stapled and Gatekeeper-verified: '+str(final_zip))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['doctor', 'credentials', 'prepare', 'advance'])
    parser.add_argument('--identity', default=os.environ.get('RETINALINK_SIGN_IDENTITY'))
    parser.add_argument('--profile', default=os.environ.get('RETINALINK_NOTARY_PROFILE', PROFILE))
    version = json.loads((ROOT/'Resources/Release.json').read_text())
    parser.add_argument('--directory', type=pathlib.Path,
                        default=ROOT/f'work/release-{version["version"]}-build{version["build"]}')
    parser.add_argument('--build-number', type=int)
    args = parser.parse_args()
    if args.build_number is not None and args.build_number < 1:
        parser.error('Build number must be positive')
    try:
        return {'doctor': doctor, 'credentials': credentials, 'prepare': prepare, 'advance': advance}[args.command](args) or 0
    except subprocess.CalledProcessError as error:
        # notarytool diagnostic text names missing profiles or rejected access;
        # authentication values are never supplied in its arguments here.
        print(error.stderr if isinstance(error.stderr, str) else str(error), file=sys.stderr)
        return 1
    except (ValueError, OSError, KeyError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
