#!/usr/bin/env python3
"""Package an existing notarized RetinaLink release, without rebuilding/installing it.

Use prepare, then advance until Apple accepts the signed DMG. Credentials stay
in the existing notarytool Keychain profile. No Finder automation is used.
"""
import argparse
import contextlib
import html
import json
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile

from release import ROOT, digest, notary, run
from signing import select_identity, verify_app

LOCATIONS = {'RetinaLink Host.app': (220, 260), 'Applications': (580, 260),
             'Setup Guide.html': (666, 449)}


def save(directory, state):
    temp = directory/'dmg-state.next'
    temp.write_text(json.dumps(state, indent=2)+'\n')
    temp.replace(directory/'dmg-state.json')


def release_state(directory):
    state = json.loads((directory/'release-state.json').read_text())
    if not state.get('complete') or not state.get('stapled_viewer_embedded'):
        raise ValueError('DMG packaging requires a completed release with a stapled bundled Viewer.')
    for role in ('Host', 'Viewer'):
        if state['submissions'][role].get('status') != 'Accepted' or not state['submissions'][role].get('stapled'):
            raise ValueError(role+' must already be notarized and stapled.')
        app = directory/f'build/apps/RetinaLink {role}.app'
        if verify_app(app, state['identity'], role) != state['apps'][role]:
            raise ValueError(role+' differs from the completed release.')
        run(['/usr/bin/xcrun', 'stapler', 'validate', app])
    host = directory/'build/apps/RetinaLink Host.app'
    if digest(host/'Contents/Resources/RetinaLink Viewer.zip') != state['stapled_viewer_embedded']:
        raise ValueError('The bundled Viewer differs from the completed release.')
    if digest(directory/state['distribution']['file']) != state['distribution']['sha256']:
        raise ValueError('The completed ZIP changed.')
    return state


def prepare(args):
    import dmgbuild  # Project-local build dependency, never shipped to users.
    release = release_state(args.release.resolve())
    identity = select_identity(release['identity']['identity'])
    directory = args.directory.resolve()
    if directory.exists() and any(directory.iterdir()):
        raise ValueError('Choose an empty DMG directory, or resume it with advance.')
    directory.mkdir(parents=True, exist_ok=True)
    version = release['apps']['Host']['version']
    build = release['apps']['Host']['build']
    assets = directory/'artwork'; assets.mkdir()
    guide = assets/'Setup Guide.html'
    guide.write_text((ROOT/'Resources/Installer/Setup Guide.html').read_text()
                     .replace('@VERSION@', html.escape(version)).replace('@BUILD@', html.escape(build)))
    app = args.release.resolve()/'build/apps/RetinaLink Host.app'
    run(['/usr/bin/xcrun', 'swiftc', '-module-cache-path', directory/'module-cache',
         ROOT/'Tools/MakeInstallerArtwork.swift', '-o', directory/'make-artwork'])
    run([directory/'make-artwork', assets, version+' · '+build, app])
    image = directory/f'RetinaLink-{version}.dmg'
    settings = {
        'format': 'UDZO', 'filesystem': 'HFS+', 'compression_level': 9,
        'files': [str(app), str(guide)], 'symlinks': {'Applications': '/Applications'},
        'icon': str(app/'Contents/Resources/AppIcon.icns'),
        'background': str(assets/'Installer Background.tiff'),
        # Hiding an app extension adds FinderInfo that strict codesign rejects.
        # Never add Finder decorations to a signed application bundle.
        'icon_locations': LOCATIONS, 'hide_extensions': ['Setup Guide.html'],
        'window_rect': ((140, 140), (800, 570)), 'default_view': 'icon-view',
        'show_status_bar': False, 'show_tab_view': False, 'show_toolbar': False,
        'show_pathbar': False, 'show_sidebar': False, 'show_icon_preview': False,
        'include_icon_view_settings': True, 'include_list_view_settings': False,
        'arrange_by': None, 'grid_spacing': 80, 'scroll_position': (0, 0),
        'label_pos': 'bottom', 'text_size': 13, 'icon_size': 96,
    }
    dmgbuild.build_dmg(str(image), 'RetinaLink', settings=settings)
    run(['/usr/bin/codesign', '--sign', identity['identity'], '--timestamp',
         '--identifier', 'local.retinalink.Installer', image])
    verify_signature(image, identity)
    state = {'format': 1, 'release_directory': str(args.release.resolve()),
             'identity': identity, 'profile': release['profile'], 'apps': release['apps'],
             'viewer_archive_sha256': release['stapled_viewer_embedded'],
             'file': image.name, 'prepared_sha256': digest(image), 'complete': False}
    save(directory, state)
    # Check the exact image before uploading; never install or launch its app.
    verify_contents(directory, state)
    print('DMG prepared and contents verified. Next: advance.')
    return 0


def verify_signature(image, identity):
    requirement = ('anchor apple generic and identifier "local.retinalink.Installer" and '
                   'certificate leaf[subject.OU] = "'+identity['team']+'"')
    run(['/usr/bin/codesign', '--verify', '--strict', '-R='+requirement, image])


@contextlib.contextmanager
def mounted(image, directory):
    mount = directory/'verify-mount'
    mount.mkdir(exist_ok=True)
    result = run(['/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-noautoopen',
                  '-mountpoint', mount, '-plist', image], capture_output=True)
    entities = plistlib.loads(result.stdout)['system-entities']
    device = next(e['dev-entry'] for e in entities if e.get('mount-point') == str(mount))
    try:
        yield mount
    finally:
        run(['/usr/bin/hdiutil', 'detach', device])


def verify_contents(directory, state):
    from ds_store import DSStore
    image = directory/state['file']
    run(['/usr/bin/hdiutil', 'verify', image], capture_output=True)
    with mounted(image, directory) as mount:
        visible = {p.name for p in mount.iterdir() if not p.name.startswith('.')}
        if visible != set(LOCATIONS):
            raise ValueError('Unexpected visible items in DMG: '+repr(visible))
        if not (mount/'Applications').is_symlink() or (mount/'Applications').readlink() != pathlib.Path('/Applications'):
            raise ValueError('Applications shortcut must point to /Applications.')
        with DSStore.open(str(mount/'.DS_Store'), 'r') as store:
            for name, expected in LOCATIONS.items():
                if tuple(store[name]['Iloc'][:2]) != expected:
                    raise ValueError('Finder icon position differs: '+name)
            view = store['.']['icvp']
            if view['iconSize'] != 96 or view['textSize'] != 13 or view['backgroundType'] != 2:
                raise ValueError('Missing custom Finder appearance.')
            window = store['.']['bwsp']
            if window['ShowToolbar'] or window['ShowSidebar'] or window['ShowStatusBar']:
                raise ValueError('Unexpected Finder chrome in installer.')
        app = mount/'RetinaLink Host.app'
        if verify_app(app, state['identity'], 'Host') != state['apps']['Host']:
            raise ValueError('Host in the DMG differs from the signed release.')
        run(['/usr/bin/xcrun', 'stapler', 'validate', app])
        run(['/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=2', app])
        viewer_zip = app/'Contents/Resources/RetinaLink Viewer.zip'
        if digest(viewer_zip) != state['viewer_archive_sha256']:
            raise ValueError('Bundled Viewer changed while packaging.')
        with tempfile.TemporaryDirectory(prefix='verify-install-', dir=directory) as folder:
            # A drag-copy equivalent to a disposable folder, leaving /Applications
            # and the currently running app/pairing untouched.
            copied = pathlib.Path(folder)/app.name
            run(['/usr/bin/ditto', app, copied])
            if verify_app(copied, state['identity'], 'Host') != state['apps']['Host']:
                raise ValueError('Host identity was not preserved by copying.')
            run(['/usr/bin/xcrun', 'stapler', 'validate', copied])
            run(['/usr/bin/ditto', '-x', '-k', viewer_zip, folder])
            viewer = pathlib.Path(folder)/'RetinaLink Viewer.app'
            if verify_app(viewer, state['identity'], 'Viewer') != state['apps']['Viewer']:
                raise ValueError('Embedded Viewer differs from the signed release.')
            run(['/usr/bin/xcrun', 'stapler', 'validate', viewer])
            run(['/usr/sbin/spctl', '--assess', '--type', 'execute', '--verbose=2', viewer])
        report = {'hostIdentityUnchanged': True, 'bundledViewerUnchanged': True,
                  'hostAndViewerTicketsValid': True, 'copyPreservesHostIdentity': True,
                  'applicationsShortcutValid': True, 'finderIconPositionsValid': True,
                  'finderWindow': window, 'visibleItems': sorted(visible),
                  'noAppsLaunchedOrInstalled': True, 'uiCaptureHelperUsed': False}
    (directory/'contents-validation.json').write_text(json.dumps(report, indent=2)+'\n')


def advance(args):
    directory = args.directory.resolve()
    state = json.loads((directory/'dmg-state.json').read_text())
    image = directory/state['file']
    verify_signature(image, state['identity'])
    if state['complete']:
        return verify(args)
    record = state.get('notarization')
    # A stapled image is different from the submitted bytes. A resumed accepted
    # submission may already have been stapled before the final state was saved.
    if digest(image) != state['prepared_sha256']:
        if not record or record.get('status') != 'Accepted':
            raise ValueError('The prepared/submitted DMG changed; refusing to reuse approval.')
        run(['/usr/bin/xcrun', 'stapler', 'validate', image])
    if not record:
        result = notary(['submit', str(image), '--no-wait'], state['profile'])
        state['notarization'] = {'id': result['id'], 'status': result.get('status', 'In Progress')}
        save(directory, state)
        print('DMG submitted: '+result['id']+'. Resume with advance.')
        return 3
    result = notary(['info', record['id']], state['profile'])
    record['status'] = result['status']; save(directory, state)
    if record['status'] == 'In Progress':
        print('Apple is still processing the DMG. Resume with advance.')
        return 3
    if record['status'] != 'Accepted':
        log = notary(['log', record['id']], state['profile'])
        (directory/'dmg-notary-log.json').write_text(json.dumps(log, indent=2)+'\n')
        raise ValueError('Apple rejected the DMG; nothing exported. Inspect dmg-notary-log.json.')
    run(['/usr/bin/xcrun', 'stapler', 'staple', image])
    run(['/usr/bin/xcrun', 'stapler', 'validate', image])
    run(['/usr/sbin/spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', image])
    verify_contents(directory, state)
    state['sha256'] = digest(image); state['complete'] = True
    save(directory, state)
    return verify(args)


def verify(args):
    directory = args.directory.resolve()
    state = json.loads((directory/'dmg-state.json').read_text())
    image = directory/state['file']
    if not state.get('complete') or state['notarization']['status'] != 'Accepted':
        raise ValueError('DMG is not complete; run advance first.')
    if digest(image) != state['sha256']:
        raise ValueError('The completed DMG changed.')
    verify_signature(image, state['identity'])
    run(['/usr/bin/xcrun', 'stapler', 'validate', image])
    run(['/usr/sbin/spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', '--verbose=2', image])
    print('Signed, Apple-accepted, stapled DMG: '+str(image))
    if args.output:
        output = args.output.resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        if output.exists() and digest(output) != state['sha256']:
            raise ValueError('Refusing to overwrite a different exported DMG.')
        if output != image:
            shutil.copy2(image, output)
        output.with_suffix('.dmg.sha256').write_text(state['sha256']+'  '+output.name+'\n')
        print('Exported: '+str(output))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'advance', 'verify'])
    version = json.loads((ROOT/'Resources/Release.json').read_text())
    stem = version['version']+'-build'+str(version['build'])
    parser.add_argument('--release', type=pathlib.Path, default=ROOT/('work/release-'+stem))
    parser.add_argument('--directory', type=pathlib.Path, default=ROOT/('work/dmg-'+stem))
    parser.add_argument('--output', type=pathlib.Path)
    args = parser.parse_args()
    try:
        return {'prepare': prepare, 'advance': advance, 'verify': verify}[args.command](args)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
