"""Offline update configuration policy; installation is tested on the real Macs."""
import pathlib
import argparse
import json
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'Tools'))
import sparkle
import release


class UpdatePolicyTests(unittest.TestCase):
    def configure(self, base):
        with tempfile.TemporaryDirectory() as folder:
            app=pathlib.Path(folder); (app/'Contents').mkdir()
            info=app/'Contents/Info.plist'; info.write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.retinalink.Host'}))
            config=dict(sparkle.CONFIG,baseURL=base)
            with patch.object(sparkle,'CONFIG',config):sparkle.configure(app,'Host')
            return plistlib.loads(info.read_bytes())

    def test_public_feeds_require_https_without_credentials(self):
        for base in ['http://example.com','https://user:secret@example.com','https://example.com?token=secret','https://example.com#other']:
            with self.subTest(base=base),self.assertRaises(ValueError):self.configure(base)

    def test_both_feed_and_archive_signatures_are_mandatory(self):
        info=self.configure('https://updates.example.com/retinalink')
        self.assertEqual(info['SUFeedURL'],'https://updates.example.com/retinalink/host/appcast.xml')
        self.assertTrue(info['SUVerifyUpdateBeforeExtraction'])
        self.assertTrue(info['SURequireSignedFeed'])
        self.assertEqual(info['SUSignedFeedFailureExpirationInterval'],0)
        self.assertFalse(info['SUEnableSystemProfiling'])

    def test_unconfigured_hosting_does_not_invent_a_production_endpoint(self):
        info=self.configure(None)
        self.assertNotIn('SUFeedURL',info)
        self.assertTrue(info['SUAutomaticallyUpdate'])

    def test_same_version_archive_cannot_be_reused_for_different_executable(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder); source=root/'release'; source.mkdir()
            app=source/'build/apps/RetinaLink Host.app/Contents'; app.mkdir(parents=True)
            (app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':'1.0','CFBundleVersion':'2',
                'SUPublicEDKey':sparkle.CONFIG['publicEdKey'],'SURequireSignedFeed':True,'SUVerifyUpdateBeforeExtraction':True}))
            state={'complete':True,'identity':{'team':'ABCDE12345'},'apps':{'Host':{'version':'1.0','build':'2','executable_sha256':'new-code'}}}
            (source/'release-state.json').write_text(json.dumps(state))
            output=root/'updates'; role=output/'host';role.mkdir(parents=True)
            archive=role/'RetinaLink-Host-1.0-2.zip'; archive.write_bytes(b'previous immutable release')
            (role/'.release-records.json').write_text(json.dumps({'baseURL':'https://updates.example.com',
                'archives':{archive.name:{'sha256':release.digest(archive),'executableSHA256':'old-code'}}}))
            args=argparse.Namespace(directory=source,update_base_url='https://updates.example.com',local_test=False,updates_directory=output)
            with patch.object(sparkle,'fetch',return_value=root),patch.object(release.subprocess,'check_output',return_value=sparkle.CONFIG['publicEdKey']),patch.object(release,'verify_app',return_value=state['apps']['Host']),patch.object(release,'run') as sign:
                with self.assertRaises(ValueError):release.update_feed(args)
                sign.assert_not_called()
            self.assertEqual(archive.read_bytes(),b'previous immutable release')


if __name__=='__main__':unittest.main()
