"""Offline release-policy tests. These do not impersonate Apple notarization."""
import argparse
import json
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]/'Tools'))
import release
import signing


class ReleasePolicyTests(unittest.TestCase):
    def test_credential_failure_report_excludes_input_and_command_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root/'work').mkdir()
            marker = root/'work/notary-credentials-ready.json'
            marker.write_text('{"authenticated":true}')
            args = argparse.Namespace(profile='fixture', identity=None)
            error = release.subprocess.CalledProcessError(1, ['secret-command'], output='secret-output', stderr='secret-error')
            with patch.object(release, 'ROOT', root), patch.object(release.sys.stdin, 'isatty', return_value=True), patch.object(release, 'select_identity', return_value={'team':'ABCDE12345'}), patch('builtins.input', return_value='private@example.com'), patch.object(release, 'run', side_effect=error) as run:
                with self.assertRaises(release.subprocess.CalledProcessError):
                    release.credentials(args)
                # Preserve Apple's direct Terminal I/O; never pipe its prompt.
                self.assertEqual(run.call_args.kwargs, {})
                self.assertNotIn('--password', run.call_args.args[0])
            self.assertFalse(marker.exists())
            report = root/'work/notary-credentials-status.json'
            content = report.read_text()
            status = json.loads(content)
            self.assertEqual(status['stage'], 'apple_validation_and_keychain_save')
            self.assertEqual(status['exit_code'], 1)
            self.assertFalse(status['authenticated'])
            for private in ['private@example.com', 'secret-command', 'secret-output', 'secret-error']:
                self.assertNotIn(private, content)
            self.assertEqual(report.stat().st_mode & 0o777, 0o600)

    def test_credentials_only_report_success_after_saved_profile_authenticates(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            args = argparse.Namespace(profile='fixture', identity=None)
            with patch.object(release, 'ROOT', root), patch.object(release.sys.stdin, 'isatty', return_value=True), patch.object(release, 'select_identity', return_value={'team':'ABCDE12345'}), patch('builtins.input', return_value='private@example.com'), patch.object(release, 'run'), patch.object(release, 'notary', side_effect=release.subprocess.CalledProcessError(1, 'history')):
                with self.assertRaises(release.subprocess.CalledProcessError):
                    release.credentials(args)
            self.assertFalse((root/'work/notary-credentials-ready.json').exists())
            status = json.loads((root/'work/notary-credentials-status.json').read_text())
            self.assertEqual(status['stage'], 'saved_profile_verification')
            self.assertEqual(status['result'], 'failed')

    def test_only_usable_developer_id_application_is_selected(self):
        listing = '\n'.join([
            '1) '+('A'*40)+' "Apple Development: Example (ABCDE12345)"',
            '2) '+('B'*40)+' "Developer ID Installer: Example (ABCDE12345)"',
            '3) '+('C'*40)+' "Developer ID Application: Example (ABCDE12345)"'])
        with patch.object(signing.subprocess, 'check_output', return_value=listing):
            self.assertEqual(signing.select_identity()['identity'], 'C'*40)
            with self.assertRaises(ValueError):
                signing.select_identity('Apple Development: Example (ABCDE12345)')

    def test_ambiguous_team_is_not_silently_selected(self):
        with patch.object(signing, 'identities', return_value=[{'identity':'A', 'name':'one'}, {'identity':'B', 'name':'two'}]):
            with self.assertRaises(ValueError):
                signing.select_identity()

    def test_requirement_pins_apple_developer_id_team_and_bundle(self):
        requirement = signing.requirement('ABCDE12345', 'local.retinalink.Viewer')
        for required in ['anchor apple generic', '100.6.1.13', '100.6.2.6', 'subject.OU', 'ABCDE12345', 'local.retinalink.Viewer']:
            self.assertIn(required, requirement)
        self.assertNotIn('cdhash', requirement)
        for team, bundle in [('ABCDE12345" or true', 'local.retinalink.Viewer'), ('ABCDE12345', 'other.app')]:
            with self.assertRaises(ValueError):
                signing.requirement(team, bundle)

    def test_resume_reuses_submission_without_uploading_again(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            upload = directory/'Viewer-notary-upload.zip'; upload.write_bytes(b'original')
            record = {'id':'test-id', 'archive':upload.name, 'sha256':release.digest(upload), 'status':'In Progress'}
            state = {'profile':'test-profile', 'submissions':{'Viewer':record}}
            with patch.object(release, 'notary', return_value={'status':'In Progress'}) as notary:
                self.assertFalse(release.submission(directory, state, 'Viewer', directory/'Viewer.app'))
                self.assertEqual(notary.call_args.args[0], ['info','test-id'])

    def test_changed_upload_cannot_reuse_accepted_ticket(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            upload = directory/'Viewer-notary-upload.zip'; upload.write_bytes(b'original')
            record = {'id':'test-id', 'archive':upload.name, 'sha256':release.digest(upload), 'status':'Accepted'}
            upload.write_bytes(b'changed')
            with patch.object(release, 'notary') as notary:
                with self.assertRaises(ValueError):
                    release.submission(directory, {'profile':'test', 'submissions':{'Viewer':record}}, 'Viewer', directory/'Viewer.app')
                notary.assert_not_called()

    def test_apple_rejection_never_staples_or_packages(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            upload = directory/'Viewer.zip'; upload.write_bytes(b'candidate')
            record = {'id':'test-id', 'archive':upload.name, 'sha256':release.digest(upload)}
            state = {'profile':'test', 'submissions':{'Viewer':record}}
            with patch.object(release, 'notary', side_effect=[{'status':'Invalid'}, {'issues':['Rejected fixture']}]), patch.object(release, 'run') as run:
                with self.assertRaises(ValueError):
                    release.submission(directory, state, 'Viewer', directory/'Viewer.app')
                run.assert_not_called()
                self.assertTrue((directory/'Viewer-notary-log.json').exists())
                self.assertFalse(record.get('stapled', False))

    def test_accepted_ticket_still_requires_gatekeeper_success(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            upload = directory/'Viewer.zip'; upload.write_bytes(b'candidate')
            record = {'id':'test-id', 'archive':upload.name, 'sha256':release.digest(upload)}
            state = {'profile':'test', 'submissions':{'Viewer':record}}
            with patch.object(release, 'notary', return_value={'status':'Accepted'}), patch.object(release, 'run', side_effect=[None,None,release.subprocess.CalledProcessError(1,'spctl')]):
                with self.assertRaises(release.subprocess.CalledProcessError):
                    release.submission(directory, state, 'Viewer', directory/'Viewer.app')
                self.assertFalse(record.get('stapled', False))

    def test_viewer_ticket_is_embedded_before_host_is_signed_or_submitted(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            host = directory/'build/apps/RetinaLink Host.app'
            (host/'Contents/Resources').mkdir(parents=True)
            (host/'Contents/Resources/RetinaLink Viewer.zip').write_bytes(b'old un-stapled archive')
            state = {'identity':{'identity':'fixture', 'team':'ABCDE12345'}, 'profile':'fixture',
                     'apps':{'Host':{'team':'ABCDE12345', 'executable_sha256':'before-sign'}, 'Viewer':{'team':'ABCDE12345', 'executable_sha256':'viewer'}}, 'submissions':{}}
            release.save(directory, state)
            events = []; sealed = False
            def verify(app, identity, role):
                value = dict(state['apps'][role])
                if role == 'Host' and sealed:value['executable_sha256'] = 'after-sign'
                return value
            def ticket(directory, state, role, app):
                events.append(role+' ticket')
                return role == 'Viewer'
            def pack(app, destination):
                events.append('embed stapled Viewer'); destination.write_bytes(b'stapled viewer archive')
            def sign(app, identity):
                nonlocal sealed
                sealed = True; events.append('seal Host')
            with patch.object(release, 'select_identity', return_value=state['identity']), patch.object(release, 'verify_app', side_effect=verify), patch.object(release, 'submission', side_effect=ticket), patch.object(release, 'archive', side_effect=pack), patch.object(release, 'sign', side_effect=sign):
                self.assertEqual(release.advance(argparse.Namespace(directory=directory)), 3)
            self.assertEqual(events, ['Viewer ticket','embed stapled Viewer','seal Host','Host ticket'])
            self.assertEqual(json.loads((directory/'release-state.json').read_text())['apps']['Host']['executable_sha256'], 'after-sign')

    def test_pending_viewer_prevents_host_upload_and_sealing(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = pathlib.Path(folder)
            state = {'identity':{'identity':'fixture','team':'ABCDE12345'}, 'apps':{'Host':{},'Viewer':{}}}
            release.save(directory, state)
            with patch.object(release, 'select_identity', return_value=state['identity']), patch.object(release, 'verify_app', return_value={}), patch.object(release, 'submission', return_value=False) as submit, patch.object(release, 'sign') as sign:
                self.assertEqual(release.advance(argparse.Namespace(directory=directory)),3)
                self.assertEqual(submit.call_args.args[2], 'Viewer')
                self.assertEqual(submit.call_count, 1); sign.assert_not_called()


if __name__ == '__main__':
    unittest.main()
