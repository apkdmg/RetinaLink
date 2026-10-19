"""Offline publication-policy tests; no GitHub writes or credentials are used."""
import copy
import hashlib
import json
import io
import pathlib
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'Tools'))
import publish_github as publisher


class GitHubPublicationTests(unittest.TestCase):
    def fixture(self, folder):
        folder = pathlib.Path(folder)
        release, feeds = folder / 'release', folder / 'feeds'
        release.mkdir(); feeds.mkdir()
        distribution = release / 'RetinaLink-1.2.3.zip'
        distribution.write_bytes(b'notarized-distribution-fixture')
        state = {'complete': True, 'source_dirty': False, 'source_commit': 'a' * 40,
                 'distribution': {'file': distribution.name, 'sha256': publisher.digest(distribution)},
                 'apps': {role: {'version': '1.2.3', 'build': '123'} for role in ('Host', 'Viewer')},
                 'submissions': {role: {'status': 'Accepted', 'stapled': True} for role in ('Host', 'Viewer')}}
        (release / 'release-state.json').write_text(json.dumps(state))
        base, archive_base = publisher.locations('apkdmg/RetinaLink', '1.2.3')
        manifest = {'version': '1.2.3', 'build': '123', 'baseURL': base,
                    'archiveBaseURL': archive_base, 'roles': {}}
        for role in ('Host', 'Viewer'):
            directory = feeds / role.lower(); directory.mkdir()
            archive = directory / ('RetinaLink-' + role + '-1.2.3-123.zip')
            archive.write_bytes((role + ' accepted app').encode())
            archive_url = archive_base + '/' + archive.name
            feed = directory / 'appcast.xml'
            feed.write_bytes(('<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
                '<channel><item><sparkle:version>123</sparkle:version><enclosure url="' + archive_url + '" length="' + str(archive.stat().st_size) +
                '" sparkle:edSignature="signed-fixture"/></item></channel></rss><!-- sparkle-signatures: fixture -->\n').encode())
            manifest['roles'][role] = {'archive': archive.name, 'sha256': publisher.digest(archive),
                                      'feedSHA256': publisher.digest(feed), 'archiveURL': archive_url,
                                      'feedURL': base + '/' + role.lower() + '/appcast.xml'}
        (feeds / 'release.json').write_text(json.dumps(manifest))
        source = folder / 'RetinaLink-1.2.3-source.tar.gz'
        metadata = {'schemaVersion': 1, 'sourceCommit': 'a' * 40, 'sourceTree': 'b' * 40,
                    'version': '1.2.3', 'build': '123', 'license': 'GPL-3.0-only',
                    'excludedTrackedPaths': [], 'dependencies': [
                        {'name': 'Sparkle', 'version': '2.9.6', 'commit': 'c' * 40,
                         'archiveSHA256': 'd' * 64, 'sourceDirectory': 'VendorSources/Sparkle-2.9.6'}]}
        content = json.dumps(metadata).encode()
        with tarfile.open(source, 'w:gz') as archive:
            member = tarfile.TarInfo('RetinaLink-1.2.3-source/SOURCE_MANIFEST.json'); member.size = len(content)
            archive.addfile(member, io.BytesIO(content))
        metadata.update(archive=str(source.resolve()), sha256=publisher.digest(source))
        (folder / 'source-manifest.json').write_text(json.dumps(metadata))
        output = folder / 'publication' / 'plan.json'
        return release, feeds, source, output

    def plan(self, folder):
        release, feeds, source, output = self.fixture(folder)
        return publisher.prepare_plan(release, feeds, source, [], 'apkdmg/RetinaLink', output, pathlib.Path(folder) / 'source-manifest.json'), output

    def test_repository_url_accepts_only_github_owner_repository(self):
        self.assertEqual(publisher.repository_name('https://github.com/apkdmg/RetinaLink.git'), 'apkdmg/RetinaLink')
        for value in ('apkdmg', 'git@github.com:apkdmg/RetinaLink.git', 'https://evil.example/apkdmg/RetinaLink',
                      'https://github.com/apkdmg/RetinaLink?token=secret', 'apkdmg/..', 'a/b/c'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                publisher.repository_name(value)

    def test_plan_pins_source_assets_and_exact_feed_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            plan, output = self.plan(folder)
            self.assertEqual(publisher.load_plan(output), plan)
            self.assertEqual(plan['sourceCommit'], 'a' * 40)
            self.assertEqual(len(plan['assets']), 4)
            self.assertEqual(len(plan['pages']), 2)
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)

    def test_dirty_or_incomplete_release_cannot_be_published(self):
        for changed in ({'source_dirty': True}, {'complete': False}):
            with self.subTest(changed=changed), tempfile.TemporaryDirectory() as folder:
                release, feeds, source, output = self.fixture(folder)
                state_path = release / 'release-state.json'
                state = json.loads(state_path.read_text()); state.update(changed)
                state_path.write_text(json.dumps(state))
                with self.assertRaises(ValueError):
                    publisher.prepare_plan(release, feeds, source, [], 'apkdmg/RetinaLink', output, pathlib.Path(folder) / 'source-manifest.json')
                self.assertFalse(output.exists())

    def test_wrong_archive_hash_or_feed_url_is_rejected(self):
        for field, wrong in (('sha256', '0' * 64), ('archiveURL', 'https://example.org/other.zip')):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as folder:
                release, feeds, source, output = self.fixture(folder)
                manifest_path = feeds / 'release.json'
                manifest = json.loads(manifest_path.read_text()); manifest['roles']['Host'][field] = wrong
                manifest_path.write_text(json.dumps(manifest))
                with self.assertRaises(ValueError):
                    publisher.prepare_plan(release, feeds, source, [], 'apkdmg/RetinaLink', output, pathlib.Path(folder) / 'source-manifest.json')

    def test_missing_input_and_same_named_assets_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            release, feeds, source, output = self.fixture(folder)
            with self.assertRaises(ValueError):
                publisher.prepare_plan(release, feeds, source, [source], 'apkdmg/RetinaLink', output, pathlib.Path(folder) / 'source-manifest.json')
            source.unlink()
            with self.assertRaises(ValueError):
                publisher.prepare_plan(release, feeds, source, [], 'apkdmg/RetinaLink', output, pathlib.Path(folder) / 'source-manifest.json')

    def test_corresponding_source_must_match_release_commit_and_inside_archive(self):
        for change in ({'sourceCommit': 'e' * 40}, {'sourceTree': 'e' * 40}, {'excludedTrackedPaths': ['Sources/Viewer.swift']}):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as folder:
                release, feeds, source, output = self.fixture(folder)
                metadata = pathlib.Path(folder) / 'source-manifest.json'
                content = json.loads(metadata.read_text()); content.update(change)
                metadata.write_text(json.dumps(content))
                with self.assertRaises(ValueError):
                    publisher.prepare_plan(release, feeds, source, [], 'apkdmg/RetinaLink', output, metadata)

    def test_plan_retry_never_changes_existing_pinned_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            plan, output = self.plan(folder)
            pathlib.Path(plan['assets'][0]['path']).write_bytes(b'changed later')
            with self.assertRaises(ValueError):
                publisher.load_plan(output)

    def test_public_release_changed_asset_is_never_replaced(self):
        with tempfile.TemporaryDirectory() as folder:
            plan, _ = self.plan(folder)
            client = FakeGitHub(plan, draft=False, changed=True)
            with self.assertRaises(ValueError):
                publisher.publish_release(client, plan)
            self.assertEqual(client.uploads, [])
            self.assertEqual(client.publications, [])

    def test_public_release_missing_asset_cannot_be_appended(self):
        with tempfile.TemporaryDirectory() as folder:
            plan, _ = self.plan(folder)
            client = FakeGitHub(plan, draft=False)
            client.remote.pop()
            with self.assertRaises(ValueError):
                publisher.publish_release(client, plan)
            self.assertEqual(client.uploads, [])

    def test_older_plan_cannot_become_latest_when_newer_public_release_exists(self):
        with tempfile.TemporaryDirectory() as folder:
            plan, _ = self.plan(folder)
            client = FakeGitHub(plan, draft=True)
            ordinary_api = client.api
            def with_newer(suffix, *args, **kwargs):
                result = ordinary_api(suffix, *args, **kwargs)
                if suffix.startswith('/releases?'):
                    result = result + [{'tag_name': 'v9.0.0', 'draft': False, 'prerelease': False}]
                return result
            with patch.object(client, 'api', side_effect=with_newer), self.assertRaises(ValueError):
                publisher.publish_release(client, plan)
            self.assertEqual(client.created, 0)
            self.assertEqual(client.publications, [])

    def test_staged_feed_cannot_include_an_unplanned_newer_build(self):
        with tempfile.TemporaryDirectory() as folder:
            plan, _ = self.plan(folder)
            feed = pathlib.Path(plan['pages'][0]['file']['path'])
            feed.write_text(feed.read_text().replace('</channel>',
                '<item><sparkle:version>999</sparkle:version></item></channel>'))
            with self.assertRaises(ValueError):
                publisher.verify_feed(feed, plan['archiveBaseURL'] + '/' + plan['assets'][0]['name'],
                                      plan['build'], plan['assets'][0]['size'])

    def test_draft_all_assets_verified_before_publication_and_retry_is_idempotent(self):
        with tempfile.TemporaryDirectory() as folder:
            plan, _ = self.plan(folder)
            client = FakeGitHub(plan, draft=True)
            client.remote = []
            publisher.publish_release(client, plan)
            self.assertEqual(len(client.uploads), len(plan['assets']))
            self.assertEqual(client.publications, [len(plan['assets'])])
            uploads = list(client.uploads)
            publisher.publish_release(client, plan)
            self.assertEqual(client.uploads, uploads)
            self.assertEqual(client.publications, [len(plan['assets'])])

    def test_draft_retry_uses_release_list_without_creating_duplicate(self):
        with tempfile.TemporaryDirectory() as folder:
            plan, _ = self.plan(folder)
            client = FakeGitHub(plan, draft=True)
            publisher.publish_release(client, plan)
            self.assertEqual(client.created, 0)
            self.assertTrue(any(path.startswith('/releases?') for path in client.requests))
            self.assertFalse(any(path.startswith('/releases/tags/') for path in client.requests))

    def test_failed_download_keeps_complete_asset_set_in_draft(self):
        with tempfile.TemporaryDirectory() as folder:
            plan, _ = self.plan(folder)
            client = FakeGitHub(plan, draft=True)
            with patch.object(client, 'verify_asset', side_effect=ValueError('Download hash mismatch')):
                with self.assertRaises(ValueError):
                    publisher.publish_release(client, plan)
            self.assertTrue(client.release['draft'])
            self.assertEqual(client.publications, [])
            publisher.publish_release(client, plan)
            self.assertEqual(client.uploads, [])
            self.assertEqual(client.publications, [len(plan['assets'])])

    def test_download_hash_is_checked_even_if_server_digest_matches(self):
        expected = {'name': 'asset.zip', 'size': 4, 'sha256': hashlib.sha256(b'good').hexdigest()}
        remote = dict(expected, id=4, state='uploaded', digest='sha256:' + expected['sha256'])
        def wrong_download(args, **kwargs):
            kwargs['stdout'].write(b'evil')
        with patch.object(publisher.subprocess, 'run', side_effect=wrong_download), self.assertRaises(ValueError):
            publisher.GitHub('/fake/gh', 'apkdmg/RetinaLink').verify_asset(remote, expected)

    def test_pages_writes_signed_bytes_only_without_touching_checkout(self):
        with tempfile.TemporaryDirectory() as folder:
            plan, _ = self.plan(folder)
            expected = [b''] + [pathlib.Path(entry['file']['path']).read_bytes() for entry in plan['pages']]
            commands, blobs = [], []
            def fake_git(args, **kwargs):
                commands.append(args)
                if args[0] == 'hash-object':
                    blobs.append(kwargs['data']); return 'b' * 40
                if args[0] in ('write-tree', 'commit-tree'):
                    return 'c' * 40
                return ''
            with patch.object(publisher, 'git', side_effect=fake_git):
                publisher.publish_pages(plan)
            self.assertEqual(blobs, expected)
            self.assertFalse(any('checkout' in command for command in commands))
            self.assertEqual([cmd for cmd in commands if 'push' in cmd],
                             [['-c', 'push.followTags=false', 'push', 'https://github.com/apkdmg/RetinaLink.git', 'c' * 40 + ':refs/heads/gh-pages']])
            self.assertEqual(len([cmd for cmd in commands if cmd[0] == 'update-index']), 3)

    def test_existing_pages_config_is_not_overridden(self):
        client = FakeGitHub({}, draft=True)
        client.api = lambda *args, **kwargs: {'build_type': 'workflow', 'source': {'branch': 'main', 'path': '/'}}
        with self.assertRaises(ValueError):
            publisher.enable_pages(client)

    def test_pages_refuses_newer_feed_and_unexpected_files(self):
        for unexpected in (True, False):
            with self.subTest(unexpected=unexpected), tempfile.TemporaryDirectory() as folder:
                plan, _ = self.plan(folder)
                def fake_git(args, **kwargs):
                    if args[0] == 'ls-remote':
                        return 'e' * 40 + '\trefs/heads/gh-pages'
                    if args[0] == 'rev-parse':
                        return 'e' * 40
                    if args[0] == 'ls-tree':
                        return ('unrelated-secret.txt' if unexpected else 'updates/host/appcast.xml')
                    if args[0] == 'show':
                        return '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>999</sparkle:version></item></channel></rss>'
                    if 'push' in args:
                        raise AssertionError('Unsafe push')
                    return ''
                with patch.object(publisher, 'git', side_effect=fake_git), self.assertRaises(ValueError):
                    publisher.publish_pages(plan)

    def test_pages_rejects_legacy_newer_build_same_build_changed_bytes_and_unknown_versions(self):
        feeds = [
            '<item><enclosure sparkle:version="999"/></item>',
            '<item><sparkle:version>123</sparkle:version><description>Changed bytes</description></item>',
            '<item><sparkle:version>invalid</sparkle:version></item>',
            '<item><enclosure/></item>', '',
            '<item><sparkle:version>123</sparkle:version><enclosure sparkle:version="12"/></item>']
        for content in feeds:
            with self.subTest(content=content), tempfile.TemporaryDirectory() as folder:
                plan, _ = self.plan(folder)
                def fake_git(args, **kwargs):
                    if args[0] == 'ls-remote':
                        return 'e' * 40 + '\trefs/heads/gh-pages'
                    if args[0] == 'rev-parse':
                        return 'e' * 40
                    if args[0] == 'ls-tree':
                        return 'updates/host/appcast.xml'
                    if args[0] == 'show':
                        return ('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>' + content + '</channel></rss>').encode()
                    if 'push' in args:
                        raise AssertionError('Unsafe push')
                    return ''
                with patch.object(publisher, 'git', side_effect=fake_git), self.assertRaises(ValueError):
                    publisher.publish_pages(plan)

    def test_pages_real_git_roundtrip_has_exact_bytes_and_idempotent_retry(self):
        with tempfile.TemporaryDirectory() as folder:
            plan, _ = self.plan(folder)
            remote = pathlib.Path(folder) / 'pages-remote.git'
            subprocess.run(['/usr/bin/git', 'init', '--bare', str(remote)], check=True, capture_output=True)
            actual_git = publisher.git
            def local_git(arguments, **kwargs):
                arguments = [str(remote) if value == 'https://github.com/apkdmg/RetinaLink.git' else value
                             for value in arguments]
                return actual_git(arguments, **kwargs)
            with patch.object(publisher, 'git', side_effect=local_git):
                publisher.publish_pages(plan, push=False)
                self.assertEqual(actual_git(['ls-remote', str(remote), 'refs/heads/gh-pages']), '')
                first = publisher.publish_pages(plan)
                second = publisher.publish_pages(plan)
            self.assertEqual(first, second)
            files = actual_git(['ls-tree', '-r', '--name-only', first], cwd=remote).splitlines()
            self.assertEqual(set(files), publisher.ALLOWED_PAGES)
            for entry in plan['pages']:
                self.assertEqual(actual_git(['show', first + ':' + entry['destination']], cwd=remote, raw=True),
                                 pathlib.Path(entry['file']['path']).read_bytes())

    def test_public_download_uses_native_tls_and_checks_downloaded_size(self):
        data = b'exact signed bytes'
        calls = []
        def download(arguments, **kwargs):
            calls.append(arguments)
            kwargs['stdout'].write(data)
            return type('Result', (), {'returncode': 0})()
        with patch.object(publisher.subprocess, 'run', side_effect=download):
            self.assertEqual(publisher.public_digest('https://example.org/appcast.xml', len(data)),
                             (hashlib.sha256(data).hexdigest(), len(data)))
        self.assertEqual(calls[0][0], '/usr/bin/curl')
        self.assertIn('--proto-redir', calls[0])
        self.assertNotIn('--insecure', calls[0])
        with patch.object(publisher.subprocess, 'run', side_effect=download), self.assertRaises(ValueError):
            publisher.public_digest('https://example.org/appcast.xml', len(data) - 1)

    def test_tag_cannot_be_retargeted(self):
        plan = {'repository': 'apkdmg/RetinaLink', 'tag': 'v1.2.3', 'sourceCommit': 'a' * 40}
        with patch.object(publisher, 'git', return_value='b' * 40 + '\trefs/tags/v1.2.3') as git:
            with self.assertRaises(ValueError):
                publisher.ensure_tag(plan)
            self.assertEqual(git.call_count, 1)

    def test_failed_external_https_check_remains_unverified(self):
        with tempfile.TemporaryDirectory() as folder:
            plan, _ = self.plan(folder)
            with patch.object(publisher, 'public_digest', side_effect=OSError('not deployed yet')):
                result = publisher.verify_public(plan)
            self.assertFalse(result['complete'])
            self.assertTrue(all(not item['verified'] for item in result['files']))


class FakeGitHub:
    def __init__(self, plan, draft, changed=False):
        self.release = {'id': 7, 'tag_name': plan.get('tag'), 'draft': draft, 'prerelease': False}
        self.remote = [dict(record, id=index, state='uploaded') for index, record in enumerate(plan.get('assets', []))]
        if changed:
            self.remote[0]['sha256'] = '0' * 64
        self.uploads, self.verified, self.publications = [], [], []
        self.created = 0
        self.requests = []

    def api(self, suffix, method='GET', data=None, **kwargs):
        self.requests.append(suffix)
        if suffix.startswith('/releases?'):
            return [self.release]
        if suffix == '/releases' and method == 'POST':
            self.created += 1
            return self.release
        if '/assets?' in suffix:
            return self.remote
        if method == 'PATCH':
            self.publications.append(len(self.verified)); self.release['draft'] = False
            return self.release
        raise AssertionError((suffix, method))

    def upload(self, tag, record):
        self.uploads.append(record['name'])
        self.remote.append(dict(record, id=len(self.remote), state='uploaded'))

    def verify_asset(self, remote, expected):
        if remote['sha256'] != expected['sha256']:
            raise ValueError('Different remote bytes')
        self.verified.append(expected['name'])


if __name__ == '__main__':
    unittest.main()
