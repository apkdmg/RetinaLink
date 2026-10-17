"""Installer integrity policy, independent of Apple and mounting privileges."""
import argparse
import json
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]/'Tools'))
import package_dmg


class DMGPolicyTests(unittest.TestCase):
    def test_incomplete_app_release_cannot_be_packaged(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root/'release-state.json').write_text('{"complete": false}')
            with patch.object(package_dmg, 'verify_app') as verify:
                with self.assertRaisesRegex(ValueError, 'completed release'):
                    package_dmg.release_state(root)
                verify.assert_not_called()

    def test_changed_submitted_image_cannot_reuse_apple_approval(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root/'test.dmg').write_bytes(b'changed')
            state = {'file':'test.dmg', 'identity':{}, 'complete':False,
                     'prepared_sha256':'other', 'notarization':{'id':'fixture', 'status':'In Progress'}}
            package_dmg.save(root, state)
            with patch.object(package_dmg, 'verify_signature'), patch.object(package_dmg, 'notary') as notary:
                with self.assertRaisesRegex(ValueError, 'DMG changed'):
                    package_dmg.advance(argparse.Namespace(directory=root))
                notary.assert_not_called()

    def test_rejected_image_cannot_be_exported(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            state = {'file':'test.dmg', 'complete':False, 'notarization':{'status':'Invalid'}}
            package_dmg.save(root, state)
            with self.assertRaisesRegex(ValueError, 'not complete'):
                package_dmg.verify(argparse.Namespace(directory=root, output=root/'export.dmg'))
            self.assertFalse((root/'export.dmg').exists())

    def test_changed_completed_image_cannot_be_exported(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            (root/'test.dmg').write_bytes(b'changed')
            state = {'file':'test.dmg', 'complete':True, 'notarization':{'status':'Accepted'}, 'sha256':'other'}
            package_dmg.save(root, state)
            with self.assertRaisesRegex(ValueError, 'completed DMG changed'):
                package_dmg.verify(argparse.Namespace(directory=root, output=root/'export.dmg'))
            self.assertFalse((root/'export.dmg').exists())


if __name__ == '__main__':
    unittest.main()
