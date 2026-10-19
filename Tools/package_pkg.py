#!/usr/bin/env python3
"""Package an unchanged notarized Host for Apple's native Installer.

prepare/advance/verify never install or launch an app. The payload has no scripts,
and its app identity, pairing namespace and embedded Viewer remain unchanged.
This does not promise to override a delivery app's macOS quarantine decision.
"""
import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

from package_dmg import release_state
from release import ROOT, digest, notary, run
from signing import verify_app

PACKAGE_ID = 'local.retinalink.pkg.Host'
COMPONENT_FILE = 'RetinaLinkHost.pkg'
RESOURCES = ('Welcome.html', 'ReadMe.html', 'Conclusion.html')


def installer_identities():
    # Installer identities are omitted by security's codesigning policy. Only
    # public certificate labels/fingerprints are read; no key is exported.
    output = subprocess.check_output(['/usr/bin/security', 'find-identity', '-v'], text=True)
    found = []
    for fingerprint, name in re.findall(r'\b([A-Fa-f0-9]{40})\s+"([^"]+)"', output):
        team = re.search(r'\(([A-Z0-9]{10})\)$', name)
        if name.startswith('Developer ID Installer: ') and team:
            found.append({'identity': fingerprint.upper(), 'name': name, 'team': team[1]})
    return found


def select_installer_identity(team, requested=None):
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('Invalid application signing team.')
    found = [entry for entry in installer_identities() if entry['team'] == team]
    if requested:
        found = [entry for entry in found if requested in (entry['identity'], entry['name'])
                 or requested.upper() == entry['identity']]
    if len(found) != 1:
        raise ValueError('Select one valid Developer ID Installer identity from the same team as Host. An Application or Mac App Store Installer certificate cannot sign this package.')
    return found[0]


def package_version(version, build):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'\d+', str(build)):
        raise ValueError('Package version requires a three-part release version and numeric build.')
    return version + '.' + str(build)


def component_policy():
    # Explicit even where the build OS has different defaults. Never find and
    # replace relocated developer builds or merge obsolete executable resources.
    return [{'RootRelativeBundlePath': 'Applications/RetinaLink Host.app',
             'BundleIsRelocatable': False, 'BundleIsVersionChecked': True,
             'BundleHasStrictIdentifier': True, 'BundleOverwriteAction': 'upgrade'}]


def distribution_xml(version):
    root = ET.Element('installer-gui-script', {'minSpecVersion': '2'})
    ET.SubElement(root, 'title').text = 'RetinaLink Host'
    for tag, filename in [('welcome', 'Welcome.html'), ('readme', 'ReadMe.html'), ('conclusion', 'Conclusion.html')]:
        ET.SubElement(root, tag, {'file': filename, 'mime-type': 'text/html'})
    ET.SubElement(root, 'options', {'customize': 'never', 'require-scripts': 'false',
                                  'rootVolumeOnly': 'true', 'hostArchitectures': 'arm64'})
    ET.SubElement(root, 'domains', {'enable_anywhere': 'false', 'enable_currentUserHome': 'false',
                                  'enable_localSystem': 'true'})
    volumes = ET.SubElement(ET.SubElement(root, 'volume-check'), 'allowed-os-versions')
    ET.SubElement(volumes, 'os-version', {'min': '13.0'})
    ET.SubElement(ET.SubElement(root, 'choices-outline'), 'line', {'choice': 'retinalink-host'})
    choice = ET.SubElement(root, 'choice', {'id': 'retinalink-host', 'visible': 'false', 'title': 'RetinaLink Host'})
    ET.SubElement(choice, 'pkg-ref', {'id': PACKAGE_ID})
    ET.SubElement(root, 'pkg-ref', {'id': PACKAGE_ID, 'version': version,
                                  'onConclusion': 'none'}).text = COMPONENT_FILE
    ET.indent(root, space='  ')
    return ET.tostring(root, encoding='utf-8', xml_declaration=True) + b'\n'


def verify_distribution(path, version):
    root = ET.parse(path).getroot()
    if root.tag != 'installer-gui-script':
        raise ValueError('Unexpected Installer distribution document.')
    expected = ET.fromstring(distribution_xml(version))
    app_version, build = version.rsplit('.', 1)
    for node in list(root):
        # productbuild can insert declarative bundle metadata. It may describe
        # this one component, but must never introduce another payload or code.
        if node.tag == 'product':
            if node.attrib != {'id': PACKAGE_ID, 'version': version} or len(node):
                raise ValueError('Unexpected Installer product metadata.')
            root.remove(node)
        elif node.tag == 'pkg-ref' and node.find('bundle-version') is not None:
            if node.attrib != {'id': PACKAGE_ID} or len(node) != 1 or (node.text or '').strip():
                raise ValueError('Unexpected Installer component metadata.')
            bundles = list(node[0])
            if node[0].attrib or len(bundles) != 1 or bundles[0].tag != 'bundle':
                raise ValueError('Unexpected Installer bundle metadata.')
            attributes = dict(bundles[0].attrib)
            path = attributes.pop('path', '').removeprefix('./')
            if (attributes != {'CFBundleShortVersionString': app_version, 'CFBundleVersion': build,
                               'id': 'local.retinalink.Host'}
                    or path != 'Applications/RetinaLink Host.app' or len(bundles[0])):
                raise ValueError('Installer bundle metadata differs from Host.')
            root.remove(node)
    # productbuild may supply an installation size, but it must not introduce
    # executable scripts, remote packages, new choices or different destinations.
    def normalized(node):
        attributes = dict(node.attrib)
        for generated in ('installKBytes', 'updateKBytes'):
            if generated in attributes:
                if node.tag != 'pkg-ref' or not re.fullmatch(r'\d+', attributes[generated]):
                    raise ValueError('Unexpected generated Installer size metadata.')
                del attributes[generated]
        text = (node.text or '').strip()
        if node.tag == 'pkg-ref' and text == '#' + COMPONENT_FILE:
            text = COMPONENT_FILE
        return node.tag, attributes, text, [normalized(child) for child in node]
    if normalized(root) != normalized(expected):
        raise ValueError('Installer distribution changed its destinations, requirements, resources or script-free policy.')


def app_manifest(app):
    """Digest every path, file, link and mode; archive UID/GID are deliberately different."""
    app = pathlib.Path(app)
    root_metadata = app.lstat()
    if not stat.S_ISDIR(root_metadata.st_mode):
        raise ValueError('Host app must be an ordinary directory bundle.')
    entries = [{'path': '.', 'mode': stat.S_IMODE(root_metadata.st_mode), 'type': 'directory'}]
    for base, directories, files in os.walk(app, followlinks=False):
        for name in sorted(directories + files):
            path = pathlib.Path(base) / name
            relative = path.relative_to(app).as_posix()
            metadata = path.lstat()
            entry = {'path': relative, 'mode': stat.S_IMODE(metadata.st_mode)}
            if stat.S_ISLNK(metadata.st_mode):
                entry.update(type='link', target=os.readlink(path))
                if not path.resolve().is_relative_to(app.resolve()):
                    raise ValueError('App contains a link outside its own bundle: ' + relative)
            elif stat.S_ISREG(metadata.st_mode):
                entry.update(type='file', sha256=digest(path))
            elif stat.S_ISDIR(metadata.st_mode):
                entry.update(type='directory')
            else:
                raise ValueError('App contains an unsupported special file: ' + relative)
            entries.append(entry)
    encoded = json.dumps(sorted(entries, key=lambda entry: entry['path']), sort_keys=True).encode()
    return hashlib.sha256(encoded).hexdigest()


def save(directory, state):
    temporary = directory / 'pkg-state.next'
    temporary.write_text(json.dumps(state, indent=2) + '\n')
    temporary.replace(directory / 'pkg-state.json')


def verify_signature(package, identity):
    if (not identity.get('name', '').startswith('Developer ID Installer: ')
            or not re.fullmatch(r'[A-Z0-9]{10}', identity.get('team', ''))
            or not identity['name'].endswith('(' + identity['team'] + ')')):
        raise ValueError('A Developer ID Installer identity is required.')
    environment = dict(os.environ, LC_ALL='C', LANG='C')
    result = run(['/usr/sbin/pkgutil', '--check-signature', package], capture_output=True, text=True, env=environment)
    text = result.stdout + result.stderr
    trusted_status = re.search(
        r'^\s*Status:\s+(?:signed by a developer certificate issued by Apple for distribution|'
        r'signed by a certificate trusted by (?:macOS|Mac OS X))\s*$', text, re.M)
    if (not re.search(r'^\s*1\.\s+' + re.escape(identity['name']) + r'\s*$', text, re.M)
            or not trusted_status
            or not re.search(r'^\s*Signed with a trusted timestamp on:\s+\S.+$', text, re.M)
            or 'Developer ID Certification Authority' not in text
            or 'Apple Root CA' not in text):
        raise ValueError('Package signature is not the expected trusted Apple Developer ID Installer chain.')
    return text


def verify_component_info(path, version, host):
    info = ET.parse(path).getroot()
    if (info.tag != 'pkg-info' or info.get('identifier') != PACKAGE_ID
            or info.get('version') != version or info.get('install-location') != '/'
            or info.get('auth') != 'root' or info.get('postinstall-action') != 'none'
            or info.get('relocatable') != 'false'):
        raise ValueError('Component package identity, destination or installation policy changed.')
    allowed = {'payload', 'bundle', 'bundle-version', 'upgrade-bundle', 'update-bundle',
               'atomic-update-bundle', 'strict-identifier', 'relocate'}
    if any(node.tag not in allowed for node in info):
        raise ValueError('Component cannot contain scripts or unexpected installation actions.')
    for section in ('bundle-version', 'upgrade-bundle', 'strict-identifier'):
        nodes = info.findall(section)
        if (len(nodes) != 1 or nodes[0].attrib or len(nodes[0]) != 1
                or nodes[0][0].tag != 'bundle'
                or nodes[0][0].attrib != {'id': 'local.retinalink.Host'} or len(nodes[0][0])):
            raise ValueError('Component must version-check and atomically upgrade the strict Host identifier.')
    for section in ('update-bundle', 'atomic-update-bundle', 'relocate'):
        nodes = info.findall(section)
        if len(nodes) != 1 or nodes[0].attrib or len(nodes[0]) or (nodes[0].text or '').strip():
            raise ValueError('Component cannot merge, relocate or introduce additional bundles.')
    bundles = info.findall('bundle')
    if len(bundles) != 1:
        raise ValueError('Component must describe only the Host app.')
    bundle = dict(bundles[0].attrib)
    bundle_path = bundle.pop('path', '').removeprefix('./')
    if (bundle_path != 'Applications/RetinaLink Host.app'
            or bundle != {'id': 'local.retinalink.Host', 'CFBundleShortVersionString': host['version'],
                          'CFBundleVersion': host['build']} or len(bundles[0])):
        raise ValueError('Component bundle metadata differs from the accepted Host.')


def verify_contents(directory, state):
    package = directory / state['file']
    with tempfile.TemporaryDirectory(prefix='verify-pkg-', dir=directory) as temporary:
        expanded = pathlib.Path(temporary) / 'expanded'
        run(['/usr/sbin/pkgutil', '--expand-full', package, expanded])
        if {p.name for p in expanded.iterdir()} != {'Distribution', 'Resources', COMPONENT_FILE}:
            raise ValueError('Unexpected files in Installer product archive.')
        verify_distribution(expanded / 'Distribution', state['package_version'])
        resources = expanded / 'Resources'
        if {p.name for p in resources.iterdir()} != set(RESOURCES):
            raise ValueError('Unexpected Installer resources.')
        for filename, expected in state['resources'].items():
            path = resources / filename
            if not path.is_file() or path.is_symlink() or digest(path) != expected:
                raise ValueError('Installer resource changed: ' + filename)
        component = expanded / COMPONENT_FILE
        if {p.name for p in component.iterdir()} != {'Bom', 'PackageInfo', 'Payload'}:
            raise ValueError('Component contains scripts or unexpected metadata.')
        verify_component_info(component / 'PackageInfo', state['package_version'], state['host'])
        payload = component / 'Payload'
        applications = payload / 'Applications'
        if ({p.name for p in payload.iterdir()} != {'Applications'}
                or applications.is_symlink() or not applications.is_dir()
                or {p.name for p in applications.iterdir()} != {'RetinaLink Host.app'}):
            raise ValueError('Payload must contain only /Applications/RetinaLink Host.app.')
        app = applications / 'RetinaLink Host.app'
        if app.is_symlink() or not app.is_dir():
            raise ValueError('Host app payload must be an ordinary app bundle.')
        if verify_app(app, state['app_identity'], 'Host') != state['host']:
            raise ValueError('Packaged Host differs from the accepted release.')
        if app_manifest(app) != state['app_manifest_sha256']:
            raise ValueError('Packaged app paths, bytes or permissions differ from the accepted release.')
        if digest(app / 'Contents/Resources/RetinaLink Viewer.zip') != state['viewer_archive_sha256']:
            raise ValueError('Bundled Viewer changed while packaging.')
        run(['/usr/bin/xcrun', 'stapler', 'validate', app])
        run(['/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=2', app])
    report = {'appIdentityUnchanged': True, 'allAppPathsBytesAndModesUnchanged': True,
              'bundledViewerUnchanged': True, 'hostTicketValid': True,
              'onlyPayload': '/Applications/RetinaLink Host.app', 'installerScriptsPresent': False,
              'appRelocationEnabled': False, 'minimumMacOS': '13.0', 'architectures': ['arm64'],
              'currentBootSystemOnly': True, 'noAppsLaunchedOrInstalled': True,
              'uiCaptureHelperUsed': False, 'quarantineDeliveryCompatibilityTested': False}
    (directory / 'contents-validation.json').write_text(json.dumps(report, indent=2) + '\n')


def prepare(args):
    release_directory = args.release.resolve()
    release = release_state(release_directory)
    identity = select_installer_identity(release['identity']['team'], args.identity)
    directory = args.directory.resolve()
    if directory.exists() and any(directory.iterdir()):
        raise ValueError('Choose an empty PKG directory, or resume the existing one with advance.')
    app = release_directory / 'build/apps/RetinaLink Host.app'
    metadata = release['apps']['Host']
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    architectures = subprocess.check_output(['/usr/bin/lipo', '-archs', app / 'Contents/MacOS/RetinaLink'], text=True).strip().split()
    if architectures != ['arm64'] or info.get('LSMinimumSystemVersion') != '13.0':
        raise ValueError('This installer requires the existing Apple silicon, macOS 13+ Host release.')
    directory.mkdir(parents=True, exist_ok=True)
    version = package_version(metadata['version'], metadata['build'])
    stage = directory / 'payload-root'
    stage_app = stage / 'Applications/RetinaLink Host.app'
    stage_app.parent.mkdir(parents=True)
    run(['/usr/bin/ditto', app, stage_app])
    manifest = app_manifest(app)
    if verify_app(stage_app, release['identity'], 'Host') != metadata or app_manifest(stage_app) != manifest:
        raise ValueError('Staging changed the accepted Host app.')
    components = directory / 'components.plist'
    components.write_bytes(plistlib.dumps(component_policy()))
    component = directory / COMPONENT_FILE
    run(['/usr/bin/pkgbuild', '--root', stage, '--component-plist', components,
         '--identifier', PACKAGE_ID, '--version', version, '--install-location', '/',
         '--ownership', 'recommended', component])
    distribution = directory / 'Distribution.xml'
    distribution.write_bytes(distribution_xml(version))
    resources = directory / 'resources'
    resources.mkdir()
    for filename in RESOURCES:
        content = (ROOT / 'Resources/Installer/Package' / filename).read_text()
        (resources / filename).write_text(content.replace('@VERSION@', metadata['version']).replace('@BUILD@', str(metadata['build'])))
    package = directory / ('RetinaLink-Host-' + metadata['version'] + '.pkg')
    run(['/usr/bin/productbuild', '--distribution', distribution, '--resources', resources,
         '--package-path', directory, '--sign', identity['name'], '--timestamp', package])
    verify_signature(package, identity)
    state = {'format': 1, 'role': 'Host', 'release_directory': str(release_directory),
             'identity': identity, 'app_identity': release['identity'], 'profile': release['profile'],
             'host': metadata, 'package_version': version, 'file': package.name,
             'app_manifest_sha256': manifest, 'viewer_archive_sha256': release['stapled_viewer_embedded'],
             'resources': {name: digest(resources / name) for name in RESOURCES},
             'prepared_sha256': digest(package), 'complete': False}
    save(directory, state)
    verify_contents(directory, state)
    print('Signed Host PKG prepared and payload verified. Next: advance. Delivery compatibility is a separate test.')
    return 0


def advance(args):
    directory = args.directory.resolve()
    state = json.loads((directory / 'pkg-state.json').read_text())
    package = directory / state['file']
    verify_signature(package, state['identity'])
    if state.get('complete'):
        return verify(args)
    record = state.get('notarization')
    if digest(package) != state['prepared_sha256']:
        if not record or record.get('status') != 'Accepted':
            raise ValueError('The prepared/submitted PKG changed; refusing to reuse Apple approval.')
        # A successful staple changes the archive. Resume only if Apple's exact
        # accepted submission is already recorded and the existing ticket works.
        run(['/usr/bin/xcrun', 'stapler', 'validate', package])
    if not record:
        # prepare records the candidate before the first full expansion. A
        # failed/interrupted validation must never become an upload on resume.
        verify_contents(directory, state)
        result = notary(['submit', str(package), '--no-wait'], state['profile'])
        state['notarization'] = {'id': result['id'], 'status': result.get('status', 'In Progress')}
        save(directory, state)
        print('PKG submitted: ' + result['id'] + '. Resume with advance.')
        return 3
    result = notary(['info', record['id']], state['profile'])
    record['status'] = result['status']
    save(directory, state)
    if record['status'] == 'In Progress':
        print('Apple is still processing the PKG. Resume with advance.')
        return 3
    if record['status'] != 'Accepted':
        log = notary(['log', record['id']], state['profile'])
        (directory / 'pkg-notary-log.json').write_text(json.dumps(log, indent=2) + '\n')
        raise ValueError('Apple rejected the PKG; nothing exported. Inspect pkg-notary-log.json.')
    run(['/usr/bin/xcrun', 'stapler', 'staple', package])
    run(['/usr/bin/xcrun', 'stapler', 'validate', package])
    run(['/usr/sbin/spctl', '--assess', '--type', 'install', '--verbose=2', package])
    verify_contents(directory, state)
    state.update(sha256=digest(package), complete=True)
    save(directory, state)
    return verify(args)


def verify(args):
    directory = args.directory.resolve()
    state = json.loads((directory / 'pkg-state.json').read_text())
    package = directory / state['file']
    if not state.get('complete') or state.get('notarization', {}).get('status') != 'Accepted':
        raise ValueError('PKG is not complete; run advance first.')
    if digest(package) != state['sha256']:
        raise ValueError('The completed PKG changed.')
    verify_signature(package, state['identity'])
    run(['/usr/bin/xcrun', 'stapler', 'validate', package])
    run(['/usr/sbin/spctl', '--assess', '--type', 'install', '--verbose=2', package])
    verify_contents(directory, state)
    print('Developer ID Installer signed, Apple-accepted, stapled Host PKG: ' + str(package))
    if args.output:
        output = args.output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        if output.exists() and digest(output) != state['sha256']:
            raise ValueError('Refusing to overwrite a different exported PKG.')
        if output != package:
            shutil.copy2(package, output)
        output.with_suffix('.pkg.sha256').write_text(state['sha256'] + '  ' + output.name + '\n')
        print('Exported: ' + str(output))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'advance', 'verify'])
    version = json.loads((ROOT / 'Resources/Release.json').read_text())
    stem = version['version'] + '-build' + str(version['build'])
    parser.add_argument('--release', type=pathlib.Path, default=ROOT / ('work/release-' + stem))
    parser.add_argument('--directory', type=pathlib.Path, default=ROOT / ('work/pkg-' + stem))
    parser.add_argument('--identity', help='Developer ID Installer certificate name or public fingerprint.')
    parser.add_argument('--output', type=pathlib.Path)
    args = parser.parse_args()
    try:
        return {'prepare': prepare, 'advance': advance, 'verify': verify}[args.command](args)
    except (ValueError, OSError, KeyError, ET.ParseError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
