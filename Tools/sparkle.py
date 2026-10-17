#!/usr/bin/env python3
"""Pinned official Sparkle dependency and public updater bundle configuration."""
import argparse
import base64
import hashlib
import json
import pathlib
import plistlib
import subprocess
import tarfile
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT/'Resources/Updates.json').read_text())
DIRECTORY = ROOT/'build/dependencies'/('Sparkle-'+CONFIG['sparkleVersion'])


def fetch():
    archive = DIRECTORY.parent/('Sparkle-'+CONFIG['sparkleVersion']+'.tar.xz')
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        temporary = archive.with_suffix('.download')
        subprocess.run(['/usr/bin/curl', '--fail', '--location', '--silent', '--show-error', CONFIG['sparkleURL'], '-o', str(temporary)], check=True)
        if hashlib.sha256(temporary.read_bytes()).hexdigest() != CONFIG['sparkleSHA256']:
            temporary.unlink()
            raise ValueError('Official Sparkle archive does not match its pinned SHA-256')
        temporary.replace(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != CONFIG['sparkleSHA256']:
        raise ValueError('Cached Sparkle archive changed')
    if not (DIRECTORY/'Sparkle.framework').exists():
        DIRECTORY.mkdir(exist_ok=True)
        with tarfile.open(archive) as source:
            source.extractall(DIRECTORY, filter='data')
    info = plistlib.loads((DIRECTORY/'Sparkle.framework/Resources/Info.plist').read_bytes())
    if info['CFBundleShortVersionString'] != CONFIG['sparkleVersion']:
        raise ValueError('Cached Sparkle version is unexpected')
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', '--deep', str(DIRECTORY/'Sparkle.framework')], check=True)
    return DIRECTORY


def configure(app, role):
    key = base64.b64decode(CONFIG['publicEdKey'], validate=True)
    if len(key) != 32:
        raise ValueError('An Ed25519 public key is required; never embed a private key')
    base = CONFIG['baseURL']
    if base:
        url = urllib.parse.urlparse(base)
        if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
            raise ValueError('Public updates require a stable HTTPS base URL without credentials')
    info_path = pathlib.Path(app)/'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    info.update(SUPublicEDKey=CONFIG['publicEdKey'], SUEnableAutomaticChecks=True,
                SUAutomaticallyUpdate=True, SUAllowsAutomaticUpdates=True,
                SUEnableSystemProfiling=False, SUShowReleaseNotes=False,
                SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True,
                SUSignedFeedFailureExpirationInterval=0,
                SUScheduledCheckInterval=CONFIG['checkInterval'],
                RetinaLinkSparkleVersion=CONFIG['sparkleVersion'])
    if base:
        info['SUFeedURL'] = base.rstrip('/')+'/'+role.lower()+'/appcast.xml'
    info_path.write_bytes(plistlib.dumps(info))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['fetch', 'configure'])
    parser.add_argument('--app', type=pathlib.Path)
    parser.add_argument('--role', choices=['Host', 'Viewer'])
    args = parser.parse_args()
    if args.command == 'fetch':
        print(fetch())
    elif args.app and args.role:
        configure(args.app, args.role)
    else:
        parser.error('configure requires --app and --role')
