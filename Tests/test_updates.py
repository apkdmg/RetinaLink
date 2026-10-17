"""Offline update configuration policy; installation is tested on the real Macs."""
import pathlib
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'Tools'))
import sparkle


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


if __name__=='__main__':unittest.main()
