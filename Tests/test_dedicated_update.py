"""Exercise maintenance rollback with fake authorization/signature tools.

Only a controlled script copy and temporary fixture apps are executed. These
tests validate transaction behavior, not Apple's signatures or real privileges.
"""
import json
import os
from pathlib import Path
import plistlib
import shlex
import stat
import subprocess
import sys
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / 'Tools/update_dedicated_viewer.sh'
MOCK = r'''
import json, os, pathlib, plistlib, shutil, sys
root=pathlib.Path(os.environ['RETINALINK_MOCK_ROOT'])
mode=os.environ['RETINALINK_MOCK_MODE']
tool=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
target=root/'target/Applications/RetinaLink Viewer.app'
state_path=root/'mock-state.json'
state=json.loads(state_path.read_text()) if state_path.exists() else {}
def save():state_path.write_text(json.dumps(state))
def build(app):return plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleVersion']
def inside(path):
    path=pathlib.Path(path)
    if root not in path.resolve().parents:raise RuntimeError('Mock mutation escaped its fixture')
    return path
with (root/'commands.jsonl').open('a') as log:log.write(json.dumps([tool]+args)+'\n')
if tool=='id':print('502' if len(args)>1 else '0')
elif tool=='ps':
    state['ps_calls']=state.get('ps_calls',0)+1;save()
    if mode=='busy' or (mode=='became_busy' and state['ps_calls']>1):
        print('502 '+str(target/'Contents/MacOS/RetinaLink'))
elif tool=='codesign':
    requirement=next((a for a in args if a.startswith('-R=')), '')
    if not all(value in requirement for value in ['anchor apple generic','local.retinalink.Viewer',
        '1.2.840.113635.100.6.2.6','1.2.840.113635.100.6.1.13','ZPCS5VQL89']):sys.exit(90)
    app=pathlib.Path(args[-1])
    if mode=='reject_clone' and app.name=='New Viewer.app':sys.exit(1)
    fail_final={'bad_final_signature','quarantine_fails','restore_copy_fails','restore_verify_fails'}
    if mode in fail_final and app==target and build(app)=='59':sys.exit(1)
    if mode=='restore_verify_fails' and app==target and state.get('backup_created'):sys.exit(1)
elif tool=='PlistBuddy':print(plistlib.loads(pathlib.Path(args[-1]).read_bytes())['CFBundleVersion'])
elif tool=='spctl':pass
elif tool=='chown':pass
elif tool=='stat':print('999:20' if mode=='bad_final_owner' and build(target)=='59' else '502:20')
elif tool=='ditto':
    source,destination=map(inside,args)
    if mode=='restore_copy_fails' and source.name=='Previous Viewer.app':sys.exit(1)
    shutil.copytree(source,destination,symlinks=True)
elif tool=='mv':
    source,destination=map(inside,args)
    if mode=='install_move_fails' and source.name=='New Viewer.app':sys.exit(1)
    if mode=='quarantine_fails' and destination.name=='Failed Viewer.app':sys.exit(1)
    shutil.move(str(source),str(destination))
    if destination.name=='Previous Viewer.app':state['backup_created']=True;save()
else:raise RuntimeError('Unknown mock tool '+tool)
'''


class DedicatedViewerUpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='retinalink-update-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / 'source/RetinaLink Viewer.app'
        self.target = self.root / 'target/Applications/RetinaLink Viewer.app'
        self.make_app(self.source, 59)
        self.make_app(self.target, 53)
        self.sentinel = self.root / 'target/Library/Application Support/RetinaLink/dedicated-enrollment.json'
        self.sentinel.parent.mkdir(parents=True)
        self.sentinel.write_bytes(b'untouched private fixture')
        tools = self.root / 'tools'
        tools.mkdir()
        mock = tools / 'mock'
        mock.write_text('#!' + sys.executable + '\n' + MOCK)
        mock.chmod(0o700)
        commands = {'/usr/bin/id': 'id', '/bin/ps': 'ps', '/usr/bin/codesign': 'codesign',
                    '/usr/libexec/PlistBuddy': 'PlistBuddy', '/usr/sbin/spctl': 'spctl',
                    '/usr/sbin/chown': 'chown', '/usr/bin/stat': 'stat',
                    '/usr/bin/ditto': 'ditto', '/bin/mv': 'mv'}
        script = SOURCE.read_text()
        for original, name in commands.items():
            (tools / name).symlink_to(mock.name)
            script = script.replace(original, shlex.quote(str(tools / name)))
        script = script.replace('target_home="/Users/$account"',
                                'target_home=' + shlex.quote(str(self.root / 'target')))
        script = script.replace('/private/var/tmp/retinalink-viewer-update.XXXXXX',
                                str(self.root / 'stage.XXXXXX'))
        lines = script.splitlines()
        for index, line in enumerate(lines):
            if line.startswith('case "$source_app" in '):
                lines[index] = 'case "$source_app" in ' + shlex.quote(str(self.source)) + ') ;; *) exit 1;; esac'
        self.script = self.root / 'update.sh'
        self.script.write_text('\n'.join(lines) + '\n')

    @staticmethod
    def make_app(path, build):
        (path / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
        (path / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleVersion': str(build)}))
        (path / 'Contents/MacOS/RetinaLink').write_bytes(('signed fixture build ' + str(build)).encode())

    @staticmethod
    def build(path):
        return plistlib.loads((path / 'Contents/Info.plist').read_bytes())['CFBundleVersion']

    def run_update(self, mode='normal'):
        env = dict(os.environ, RETINALINK_MOCK_ROOT=str(self.root), RETINALINK_MOCK_MODE=mode)
        result = subprocess.run(['/bin/bash', str(self.script), str(self.source), '59'],
                                env=env, text=True, capture_output=True, timeout=20)
        self.assertNotIn('Traceback', result.stderr, 'Unexpected mock failure: ' + result.stderr)
        self.assertEqual(self.sentinel.read_bytes(), b'untouched private fixture')
        return result

    def assert_restored(self, mode):
        result = self.run_update(mode)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.build(self.target), '53')
        self.assertFalse(list(self.root.glob('stage.*')), result.stderr)

    def assert_backup_retained(self, mode):
        result = self.run_update(mode)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        stages = list(self.root.glob('stage.*'))
        self.assertEqual(len(stages), 1, result.stderr)
        self.assertEqual(stat.S_IMODE(stages[0].stat().st_mode), 0o700)
        self.assertEqual(self.build(stages[0] / 'Previous Viewer.app'), '53')
        self.assertIn('private backup was retained', result.stderr)

    def test_success_commits_only_verified_app(self):
        result = self.run_update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.build(self.target), '59')
        self.assertFalse(list(self.root.glob('stage.*')))
        status = json.loads(result.stdout)
        self.assertEqual(status['previousBuild'], '53')
        self.assertFalse(status['pairingChanged'] or status['fileVaultChanged'] or status['loginSettingsChanged'])

    def test_clone_rejection_preserves_original(self):
        self.assert_restored('reject_clone')

    def test_install_move_failure_restores_original(self):
        self.assert_restored('install_move_fails')

    def test_final_signature_failure_restores_original(self):
        self.assert_restored('bad_final_signature')

    def test_final_owner_failure_restores_original(self):
        self.assert_restored('bad_final_owner')

    def test_failed_quarantine_retains_private_backup(self):
        self.assert_backup_retained('quarantine_fails')

    def test_failed_restore_copy_retains_private_backup(self):
        self.assert_backup_retained('restore_copy_fails')

    def test_failed_restore_verification_retains_private_backup(self):
        self.assert_backup_retained('restore_verify_fails')

    def test_running_target_is_not_replaced(self):
        self.assert_restored('busy')

    def test_target_started_during_staging_is_not_replaced(self):
        self.assert_restored('became_busy')


if __name__ == '__main__':
    unittest.main()
