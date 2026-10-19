"""Offline update configuration policy; installation is tested on the real Macs."""
import pathlib
import argparse
import json
import plistlib
import sys
import tempfile
import unittest
from contextlib import contextmanager
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
                'SUPublicEDKey':sparkle.CONFIG['publicEdKey'],'SURequireSignedFeed':True,'SUVerifyUpdateBeforeExtraction':True,
                'SUFeedURL':'https://updates.example.com/host/appcast.xml'}))
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


class UpdateHostingTests(unittest.TestCase):
    @contextmanager
    def staging(self, *, base='https://apkdmg.github.io/RetinaLink/updates', archive_base=None, local=False, embedded_feeds=True):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder); source=root/'release'; source.mkdir()
            state={'complete':True,'identity':{'team':'ABCDE12345'},'apps':{}}
            for role in ['Host','Viewer']:
                app=source/f'build/apps/RetinaLink {role}.app/Contents'; app.mkdir(parents=True)
                info={'CFBundleShortVersionString':'0.8.1','CFBundleVersion':'61',
                      'SUPublicEDKey':sparkle.CONFIG['publicEdKey'],'SURequireSignedFeed':True,'SUVerifyUpdateBeforeExtraction':True}
                if embedded_feeds:info['SUFeedURL']=base.rstrip('/')+'/'+role.lower()+'/appcast.xml'
                (app/'Info.plist').write_bytes(plistlib.dumps(info))
                state['apps'][role]={'version':'0.8.1','build':'61','executable_sha256':role+'-code'}
            (source/'release-state.json').write_text(json.dumps(state))
            args=argparse.Namespace(directory=source,update_base_url=base,archive_base_url=archive_base,
                                    local_test=local,updates_directory=root/'updates')
            def archive(app, destination):
                destination.write_bytes(('notarized '+app.name).encode())
            def run(arguments, **kwargs):
                if pathlib.Path(arguments[0]).name=='generate_appcast':
                    (arguments[-1]/'appcast.xml').write_bytes(b'signed XML bytes')
            with patch.object(sparkle,'fetch',return_value=root), \
                 patch.object(release.subprocess,'check_output',return_value=sparkle.CONFIG['publicEdKey']), \
                 patch.object(release,'verify_app',side_effect=lambda app,identity,role:state['apps'][role]), \
                 patch.object(release,'archive',side_effect=archive) as archive_mock, \
                 patch.object(release,'run',side_effect=run) as sign:
                yield args,source,sign,archive_mock

    def test_github_archives_have_flat_versioned_urls_and_role_specific_feeds(self):
        archive_base='https://github.com/apkdmg/RetinaLink/releases/download/v0.8.1'
        with self.staging(archive_base=archive_base+'/') as (args,source,sign,archive):
            self.assertEqual(release.update_feed(args),0)
            generated=[call.args[0] for call in sign.call_args_list if pathlib.Path(call.args[0][0]).name=='generate_appcast']
            self.assertEqual(len(generated),2)
            for command in generated:
                self.assertEqual(command[command.index('--download-url-prefix')+1],archive_base+'/')
            manifest=json.loads((args.updates_directory/'release.json').read_text())
            self.assertEqual(manifest['archiveBaseURL'],archive_base)
            for role in ['Host','Viewer']:
                record=manifest['roles'][role]
                self.assertEqual(record['archiveURL'],archive_base+f'/RetinaLink-{role}-0.8.1-61.zip')
                self.assertEqual(record['feedURL'],args.update_base_url+'/'+role.lower()+'/appcast.xml')
                self.assertEqual(record['sha256'],release.digest(args.updates_directory/role.lower()/record['archive']))
                bookkeeping=json.loads((args.updates_directory/role.lower()/'.release-records.json').read_text())
                self.assertEqual(bookkeeping['archiveBaseURL'],archive_base)

    def test_default_layout_keeps_archives_in_each_role_directory(self):
        with self.staging() as (args,source,sign,archive):
            release.update_feed(args)
            generated=[call.args[0] for call in sign.call_args_list if pathlib.Path(call.args[0][0]).name=='generate_appcast']
            self.assertEqual([command[command.index('--download-url-prefix')+1] for command in generated],
                             [args.update_base_url+'/host/',args.update_base_url+'/viewer/'])

    def test_archive_override_requires_https_without_auth_query_or_fragment(self):
        for value in ['', 'http://github.com/apkdmg/RetinaLink/releases/download/v0.8.1',
                      'https://user:secret@github.com/assets','https://github.com/assets?token=secret',
                      'https://github.com/assets#other','https:///missing-host']:
            with self.subTest(value=value),self.staging(archive_base=value) as (args,source,sign,archive):
                with self.assertRaises(ValueError):release.update_feed(args)
                archive.assert_not_called(); sign.assert_not_called()

    def test_changing_archive_server_rejects_reused_staging(self):
        first='https://github.com/apkdmg/RetinaLink/releases/download/v0.8.1'
        with self.staging(archive_base=first) as (args,source,sign,archive):
            release.update_feed(args)
            snapshot={path.relative_to(args.updates_directory):path.read_bytes()
                      for path in args.updates_directory.rglob('*') if path.is_file()}
            sign.reset_mock(); archive.reset_mock()
            args.archive_base_url=first+'-changed'
            with self.assertRaisesRegex(ValueError,'fresh staging'):release.update_feed(args)
            sign.assert_not_called(); archive.assert_not_called()
            self.assertEqual(snapshot,{path.relative_to(args.updates_directory):path.read_bytes()
                                      for path in args.updates_directory.rglob('*') if path.is_file()})

    def test_legacy_bookkeeping_works_only_with_legacy_layout(self):
        with self.staging() as (args,source,sign,archive):
            release.update_feed(args)
            for path in args.updates_directory.glob('*/.release-records.json'):
                records=json.loads(path.read_text()); records.pop('archiveBaseURL'); path.write_text(json.dumps(records))
            archive.reset_mock()
            release.update_feed(args)
            archive.assert_not_called()
            args.archive_base_url='https://github.com/apkdmg/RetinaLink/releases/download/v0.8.1'
            sign.reset_mock()
            with self.assertRaisesRegex(ValueError,'fresh staging'):release.update_feed(args)
            sign.assert_not_called()

    def test_production_feed_must_be_pinned_in_signed_app(self):
        with self.staging(embedded_feeds=False) as (args,source,sign,archive):
            with self.assertRaisesRegex(ValueError,'pin this production feed'):release.update_feed(args)
            archive.assert_not_called(); sign.assert_not_called()

    def test_different_embedded_feed_is_rejected(self):
        with self.staging() as (args,source,sign,archive):
            info_path=source/'build/apps/RetinaLink Host.app/Contents/Info.plist'
            info=plistlib.loads(info_path.read_bytes()); info['SUFeedURL']='https://other.example.com/host/appcast.xml'
            info_path.write_bytes(plistlib.dumps(info))
            with self.assertRaisesRegex(ValueError,'pin this production feed'):release.update_feed(args)
            archive.assert_not_called(); sign.assert_not_called()

    def test_explicit_loopback_test_supports_old_unconfigured_releases(self):
        with self.staging(base='http://127.0.0.1:58475',local=True,embedded_feeds=False) as (args,source,sign,archive):
            self.assertEqual(release.update_feed(args),0)
            manifest=json.loads((args.updates_directory/'release.json').read_text())
            self.assertEqual(manifest['roles']['Viewer']['archiveURL'],
                             'http://127.0.0.1:58475/viewer/RetinaLink-Viewer-0.8.1-61.zip')


if __name__=='__main__':unittest.main()
