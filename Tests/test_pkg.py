"""Offline Installer policy tests; no package execution or Apple impersonation."""
import argparse
import json
import pathlib
import plistlib
import sys
import tempfile
import types
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'Tools'))
import package_pkg


TEAM = 'ABCDE12345'
INSTALLER = {'identity': 'B' * 40, 'name': 'Developer ID Installer: Example (' + TEAM + ')', 'team': TEAM}


class PackagePolicyTests(unittest.TestCase):
    def test_installer_identity_requires_installer_certificate_from_app_team(self):
        listing = '\n'.join([
            '1) ' + 'A' * 40 + ' "Developer ID Application: Example (' + TEAM + ')"',
            '2) ' + 'B' * 40 + ' "' + INSTALLER['name'] + '"',
            '3) ' + 'C' * 40 + ' "Developer ID Installer: Other (FGHIJ67890)"',
            '4) ' + 'D' * 40 + ' "3rd Party Mac Developer Installer: Example (' + TEAM + ')"'])
        with patch.object(package_pkg.subprocess, 'check_output', return_value=listing) as query:
            self.assertEqual(package_pkg.select_installer_identity(TEAM), INSTALLER)
            self.assertEqual(query.call_args.args[0], ['/usr/bin/security', 'find-identity', '-v'])
            for fingerprint in ['A' * 40, 'C' * 40, 'D' * 40]:
                with self.assertRaises(ValueError):
                    package_pkg.select_installer_identity(TEAM, fingerprint)

    def test_ambiguous_installer_identity_is_not_silently_selected(self):
        other = dict(INSTALLER, identity='E' * 40)
        with patch.object(package_pkg, 'installer_identities', return_value=[INSTALLER, other]):
            with self.assertRaisesRegex(ValueError, 'Select one'):
                package_pkg.select_installer_identity(TEAM)

    def test_installer_signature_rejects_wrong_certificate_or_team(self):
        valid = ('Status: signed by a certificate trusted by macOS\n'
                 'Signed with a trusted timestamp on: 2026-10-19 04:17:58 +0000\n'
                 ' 1. ' + INSTALLER['name'] + '\n'
                 ' 2. Developer ID Certification Authority\n 3. Apple Root CA\n')
        with patch.object(package_pkg, 'run', return_value=types.SimpleNamespace(stdout=valid, stderr='')):
            package_pkg.verify_signature(pathlib.Path('fixture.pkg'), INSTALLER)
            for invalid in [dict(INSTALLER, name='Developer ID Application: Example (' + TEAM + ')'),
                            dict(INSTALLER, name='Developer ID Installer: Other (FGHIJ67890)')]:
                with self.assertRaises(ValueError):
                    package_pkg.verify_signature(pathlib.Path('fixture.pkg'), invalid)
        with patch.object(package_pkg, 'run', return_value=types.SimpleNamespace(stdout=valid.replace('Apple Root CA', 'Unrelated Root'), stderr='')):
            with self.assertRaisesRegex(ValueError, 'trusted Apple'):
                package_pkg.verify_signature(pathlib.Path('fixture.pkg'), INSTALLER)

    def test_real_apple_distribution_signature_output_is_accepted(self):
        output = ('Package "RetinaLink-Probe.pkg":\n'
                  '   Status: signed by a developer certificate issued by Apple for distribution\n'
                  '   Notarization: trusted by the Apple notary service\n'
                  '   Signed with a trusted timestamp on: 2026-10-19 04:17:58 +0000\n'
                  '   Certificate Chain:\n    1. ' + INSTALLER['name'] + '\n'
                  '       Expires: 2027-02-01 22:12:15 +0000\n'
                  '    2. Developer ID Certification Authority\n    3. Apple Root CA\n')
        with patch.object(package_pkg, 'run', return_value=types.SimpleNamespace(stdout=output, stderr='')):
            package_pkg.verify_signature(pathlib.Path('fixture.pkg'), INSTALLER)
        for invalid in [output.replace('Signed with a trusted timestamp on:', 'Timestamp unavailable:'),
                        output.replace('signed by a developer certificate issued by Apple for distribution', 'invalid signature')]:
            with patch.object(package_pkg, 'run', return_value=types.SimpleNamespace(stdout=invalid, stderr='')):
                with self.assertRaises(ValueError):
                    package_pkg.verify_signature(pathlib.Path('fixture.pkg'), INSTALLER)

    def test_bundle_policy_never_relocates_merges_or_downgrades(self):
        self.assertEqual(package_pkg.component_policy(), [{
            'RootRelativeBundlePath': 'Applications/RetinaLink Host.app',
            'BundleIsRelocatable': False, 'BundleIsVersionChecked': True,
            'BundleHasStrictIdentifier': True, 'BundleOverwriteAction': 'upgrade'}])

    def test_distribution_is_script_free_arm64_boot_system_only(self):
        root = ET.fromstring(package_pkg.distribution_xml('0.7.0.59'))
        self.assertEqual(root.find('options').attrib,
                         {'customize': 'never', 'require-scripts': 'false', 'rootVolumeOnly': 'true', 'hostArchitectures': 'arm64'})
        self.assertEqual(root.find('domains').attrib,
                         {'enable_anywhere': 'false', 'enable_currentUserHome': 'false', 'enable_localSystem': 'true'})
        self.assertEqual(root.find('volume-check/allowed-os-versions/os-version').attrib, {'min': '13.0'})
        self.assertIsNone(root.find('script'))
        self.assertEqual(root.findall('pkg-ref')[0].attrib['onConclusion'], 'none')

    def test_distribution_rejects_script_or_destination_change(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / 'Distribution'
            original = package_pkg.distribution_xml('0.7.0.59')
            path.write_bytes(original)
            package_pkg.verify_distribution(path, '0.7.0.59')
            for changed in [original.replace(b'enable_anywhere="false"', b'enable_anywhere="true"'),
                            original.replace(b'arm64', b'x86_64'),
                            original.replace(b'</installer-gui-script>', b'<script>system.run()</script></installer-gui-script>'),
                            original.replace(b'RetinaLinkHost.pkg', b'https://example.com/Remote.pkg')]:
                path.write_bytes(changed)
                with self.assertRaisesRegex(ValueError, 'distribution changed'):
                    package_pkg.verify_distribution(path, '0.7.0.59')

    def test_manifest_detects_file_mode_link_and_bytes_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            app = pathlib.Path(folder) / 'Host.app'
            app.mkdir()
            file = app / 'binary'
            file.write_bytes(b'original')
            file.chmod(0o755)
            app.chmod(0o755)
            original = package_pkg.app_manifest(app)
            app.chmod(0o700)
            self.assertNotEqual(original, package_pkg.app_manifest(app))
            app.chmod(0o755)
            file.write_bytes(b'changed')
            self.assertNotEqual(original, package_pkg.app_manifest(app))
            file.write_bytes(b'original')
            file.chmod(0o644)
            self.assertNotEqual(original, package_pkg.app_manifest(app))
            (app / 'unsafe-link').symlink_to('/Applications')
            with self.assertRaisesRegex(ValueError, 'outside its own bundle'):
                package_pkg.app_manifest(app)

    def test_incomplete_release_never_stages_or_builds_package(self):
        with patch.object(package_pkg, 'release_state', side_effect=ValueError('completed release required')), patch.object(package_pkg, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'completed release'):
                package_pkg.prepare(argparse.Namespace(release=pathlib.Path('/fixture'), directory=pathlib.Path('/fixture/output'), identity=None))
            run.assert_not_called()

    def test_changed_submitted_package_does_not_reuse_apple_approval(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            (directory / 'test.pkg').write_bytes(b'changed')
            state = {'file': 'test.pkg', 'identity': INSTALLER, 'complete': False, 'prepared_sha256': 'different',
                     'notarization': {'id': 'fixture', 'status': 'In Progress'}}
            package_pkg.save(directory, state)
            with patch.object(package_pkg, 'verify_signature'), patch.object(package_pkg, 'notary') as notary:
                with self.assertRaisesRegex(ValueError, 'PKG changed'):
                    package_pkg.advance(argparse.Namespace(directory=directory))
                notary.assert_not_called()

    def test_failed_prepare_payload_validation_cannot_be_resumed_into_upload(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            package = directory / 'test.pkg'
            package.write_bytes(b'original')
            state = {'file': package.name, 'identity': INSTALLER, 'complete': False,
                     'prepared_sha256': package_pkg.digest(package)}
            package_pkg.save(directory, state)
            with patch.object(package_pkg, 'verify_signature'), patch.object(package_pkg, 'verify_contents', side_effect=ValueError('invalid payload')) as contents, patch.object(package_pkg, 'notary') as notary:
                with self.assertRaisesRegex(ValueError, 'invalid payload'):
                    package_pkg.advance(argparse.Namespace(directory=directory))
                contents.assert_called_once()
                notary.assert_not_called()

    def test_apple_rejection_never_staples_or_exports(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            package = directory / 'test.pkg'
            package.write_bytes(b'original')
            state = {'file': package.name, 'identity': INSTALLER, 'profile': 'fixture', 'complete': False,
                     'prepared_sha256': package_pkg.digest(package), 'notarization': {'id': 'fixture', 'status': 'In Progress'}}
            package_pkg.save(directory, state)
            with patch.object(package_pkg, 'verify_signature'), patch.object(package_pkg, 'run') as run, patch.object(package_pkg, 'notary', side_effect=[{'status': 'Invalid'}, {'issues': ['fixture rejection']}]):
                with self.assertRaisesRegex(ValueError, 'Apple rejected'):
                    package_pkg.advance(argparse.Namespace(directory=directory))
                run.assert_not_called()
            self.assertFalse(json.loads((directory / 'pkg-state.json').read_text())['complete'])

    def test_gatekeeper_failure_after_acceptance_keeps_package_incomplete(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            package = directory / 'test.pkg'
            package.write_bytes(b'original')
            state = {'file': package.name, 'identity': INSTALLER, 'profile': 'fixture', 'complete': False,
                     'prepared_sha256': package_pkg.digest(package), 'notarization': {'id': 'fixture', 'status': 'In Progress'}}
            package_pkg.save(directory, state)
            with patch.object(package_pkg, 'verify_signature'), patch.object(package_pkg, 'notary', return_value={'status': 'Accepted'}), patch.object(package_pkg, 'run', side_effect=[None, None, package_pkg.subprocess.CalledProcessError(1, 'spctl')]), patch.object(package_pkg, 'verify_contents') as contents:
                with self.assertRaises(package_pkg.subprocess.CalledProcessError):
                    package_pkg.advance(argparse.Namespace(directory=directory))
                contents.assert_not_called()
            self.assertFalse(json.loads((directory / 'pkg-state.json').read_text())['complete'])

    def test_incomplete_or_changed_completed_package_cannot_be_exported(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            package = directory / 'test.pkg'
            package.write_bytes(b'changed')
            for state, message in [({'complete': False, 'notarization': {'status': 'Invalid'}}, 'not complete'),
                                   ({'complete': True, 'notarization': {'status': 'Accepted'}, 'sha256': 'different'}, 'completed PKG changed')]:
                package_pkg.save(directory, dict(state, file=package.name))
                output = directory / 'public.pkg'
                with self.assertRaisesRegex(ValueError, message):
                    package_pkg.verify(argparse.Namespace(directory=directory, output=output))
                self.assertFalse(output.exists())


class PayloadPolicyTests(unittest.TestCase):
    def fixture(self, directory, mutation=None, metadata=None):
        host = {'bundle_id': 'local.retinalink.Host', 'version': '0.7.0', 'build': '59'}
        source = directory / 'source.app'
        (source / 'Contents/Resources').mkdir(parents=True)
        (source / 'Contents/Resources/RetinaLink Viewer.zip').write_bytes(b'signed viewer')
        state = {'file': 'fixture.pkg', 'package_version': '0.7.0.59', 'app_identity': {}, 'host': host,
                 'app_manifest_sha256': package_pkg.app_manifest(source),
                 'viewer_archive_sha256': package_pkg.digest(source / 'Contents/Resources/RetinaLink Viewer.zip'),
                 'resources': {name: package_pkg.hashlib.sha256(name.encode()).hexdigest() for name in package_pkg.RESOURCES}}
        def expand(arguments, **kwargs):
            if arguments[:2] != ['/usr/sbin/pkgutil', '--expand-full']:
                return
            expanded = pathlib.Path(arguments[-1])
            expanded.mkdir()
            (expanded / 'Distribution').write_bytes(package_pkg.distribution_xml('0.7.0.59'))
            resources = expanded / 'Resources'; resources.mkdir()
            for name in package_pkg.RESOURCES:
                (resources / name).write_bytes(name.encode())
            component = expanded / package_pkg.COMPONENT_FILE
            component.mkdir()
            (component / 'Bom').write_bytes(b'fixture')
            (component / 'PackageInfo').write_text('''<pkg-info identifier="local.retinalink.pkg.Host" version="0.7.0.59" install-location="/" relocatable="false" auth="root" postinstall-action="none">
              <payload numberOfFiles="3" installKBytes="1"/>
              <bundle path="./Applications/RetinaLink Host.app" id="local.retinalink.Host" CFBundleShortVersionString="0.7.0" CFBundleVersion="59"/>
              <bundle-version><bundle id="local.retinalink.Host"/></bundle-version>
              <upgrade-bundle><bundle id="local.retinalink.Host"/></upgrade-bundle>
              <strict-identifier><bundle id="local.retinalink.Host"/></strict-identifier>
              <update-bundle/><atomic-update-bundle/><relocate/>
            </pkg-info>''')
            payload = component / 'Payload'
            (payload / 'Applications').mkdir(parents=True)
            package_pkg.shutil.copytree(source, payload / 'Applications/RetinaLink Host.app')
            if mutation:
                mutation(expanded, component, payload)
        with patch.object(package_pkg, 'run', side_effect=expand), patch.object(package_pkg, 'verify_app', return_value=metadata or host):
            package_pkg.verify_contents(directory, state)

    def test_exact_payload_verifies_without_installing_or_launching(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            self.fixture(directory)
            report = json.loads((directory / 'contents-validation.json').read_text())
            self.assertTrue(report['noAppsLaunchedOrInstalled'])
            self.assertFalse(report['quarantineDeliveryCompatibilityTested'])
            self.assertFalse(report['installerScriptsPresent'])

    def test_script_payload_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, 'scripts or unexpected'):
                self.fixture(pathlib.Path(folder), lambda expanded, component, payload: (component / 'Scripts').mkdir())

    def test_files_outside_app_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, 'only /Applications'):
                self.fixture(pathlib.Path(folder), lambda expanded, component, payload: (payload / 'Library').mkdir())

    def test_wrong_app_build_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, 'Host differs'):
                self.fixture(pathlib.Path(folder), metadata={'bundle_id': 'local.retinalink.Host', 'version': '0.7.0', 'build': '60'})

    def test_changed_app_bytes_are_rejected_even_with_same_metadata(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, 'paths, bytes or permissions'):
                self.fixture(pathlib.Path(folder), lambda expanded, component, payload:
                             (payload / 'Applications/RetinaLink Host.app/Contents/Resources/RetinaLink Viewer.zip').write_bytes(b'changed'))

    def test_changed_installer_readme_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, 'Installer resource changed'):
                self.fixture(pathlib.Path(folder), lambda expanded, component, payload:
                             (expanded / 'Resources/ReadMe.html').write_bytes(b'changed'))

    def test_disabled_version_or_identifier_checks_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            def remove_check(expanded, component, payload):
                path = component / 'PackageInfo'
                root = ET.parse(path).getroot()
                root.remove(root.find('bundle-version'))
                path.write_bytes(ET.tostring(root))
            with self.assertRaisesRegex(ValueError, 'version-check'):
                self.fixture(pathlib.Path(folder), remove_check)


if __name__ == '__main__':
    unittest.main()
