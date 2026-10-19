"""Corresponding-source tests use fixture Git repositories and source-only dependencies."""
import hashlib
import io
import json
import pathlib
import subprocess
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]/'Tools'))
import source_archive


def tar_bytes(files, special=None):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode='w:gz') as archive:
        for name, content in files.items():
            item = tarfile.TarInfo(name)
            item.size = len(content)
            archive.addfile(item, io.BytesIO(content))
        if special:
            archive.addfile(special)
    return output.getvalue()


class SourceArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = pathlib.Path(self.temporary.name)
        self.repo, self.cache = self.base/'repo', self.base/'cache'
        self.repo.mkdir(); self.cache.mkdir()
        self.run_git('init', '-q')
        self.run_git('config', 'user.name', 'Source Fixture')
        self.run_git('config', 'user.email', 'source@example.invalid')
        self.upstream = '1' * 40
        self.root = 'Sparkle-' + self.upstream
        dependency_files = {self.root+'/.gitmodules': b'', self.root+'/LICENSE': b'upstream notice',
                            self.root+'/Vendor/ed25519-sparkle/src/sign.c': b'source, not a framework',
                            self.root+'/Vendor/bsdiff/bsdiff.c': b'bsdiff source'}
        self.dependency_archive = tar_bytes(dependency_files)
        sha = hashlib.sha256(self.dependency_archive).hexdigest()
        self.dep = {'name': 'Sparkle', 'version': '2.9.6',
                    'repository': 'https://github.com/sparkle-project/Sparkle',
                    'commit': self.upstream,
                    'archiveURL': 'https://codeload.github.com/sparkle-project/Sparkle/tar.gz/'+self.upstream,
                    'archiveRoot': self.root, 'archiveSHA256': sha,
                    'binaryArchiveSHA256': '2'*64, 'submodules': [],
                    'requiredSourcePaths': ['.gitmodules', 'LICENSE', 'Vendor/bsdiff/bsdiff.c',
                                            'Vendor/ed25519-sparkle/src/sign.c']}
        (self.cache/(sha+'.tar.gz')).write_bytes(self.dependency_archive)
        self.write('Resources/ThirdPartySources.json', json.dumps({'schemaVersion':1, 'dependencies':[self.dep]}))
        self.write('Resources/Updates.json', json.dumps({'sparkleVersion':'2.9.6', 'sparkleSHA256':'2'*64}))
        self.write('Resources/Release.json', json.dumps({'version':'0.8.1', 'build':61}))
        for name in ['LICENSE', 'SOURCE_BUILD.md', 'build.sh', 'Sources/main.swift']:
            self.write(name, 'committed source')
        (self.repo/'build.sh').chmod(0o755)
        self.commit = self.commit_all()

    def run_git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], stderr=subprocess.DEVNULL)

    def write(self, name, text):
        path = self.repo/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit_all(self):
        self.run_git('add', '.')
        self.run_git('commit', '-qm', 'Source fixture')
        return self.run_git('rev-parse', 'HEAD').decode().strip()

    def package(self, name='source.tar.gz', commit=None):
        return source_archive.package(self.repo, commit or self.commit, self.base/name, self.cache)

    def test_exact_commit_ignores_dirty_and_untracked_files(self):
        self.write('Sources/main.swift', 'dirty changes must not ship')
        self.write('passwords.txt', 'untracked must not ship')
        report = self.package()
        with tarfile.open(report['archive']) as archive:
            names = archive.getnames()
            prefix = 'RetinaLink-0.8.1-source/'
            self.assertEqual(archive.extractfile(prefix+'Sources/main.swift').read(), b'committed source')
            self.assertFalse(any('passwords.txt' in name or '/.git/' in name for name in names))
            manifest = json.load(archive.extractfile(prefix+'SOURCE_MANIFEST.json'))
            self.assertEqual(manifest, {key:value for key,value in report.items() if key not in {'archive','sha256'}})
            self.assertEqual(manifest['sourceCommit'], self.commit)
            self.assertEqual(archive.getmember(prefix+'build.sh').mode, 0o755)
            self.assertEqual(archive.extractfile(prefix+'VendorSources/Sparkle-2.9.6/Vendor/bsdiff/bsdiff.c').read(), b'bsdiff source')

    def test_deterministic_source_archive(self):
        first, second = self.package('one.tar.gz'), self.package('two.tar.gz')
        self.assertEqual(first['sha256'], second['sha256'])

    def test_forbidden_tracked_artifacts_are_excluded(self):
        for name in ['work/test.log', 'build/private.txt', 'outputs/release.pkg', 'SECURITY_REVIEW.md']:
            self.write(name, 'excluded')
        commit = self.commit_all()
        report = self.package(commit=commit)
        self.assertEqual(len(report['excludedTrackedPaths']), 4)
        with tarfile.open(report['archive']) as archive:
            self.assertFalse(any('/SECURITY_REVIEW.md' in m.name or '/work/' in m.name for m in archive))

    def test_requires_full_commit(self):
        for value in ['HEAD', self.commit[:12], '--help']:
            with self.assertRaises(ValueError):
                self.package(commit=value)

    def test_cache_tampering_does_not_package_source(self):
        (self.cache/(self.dep['archiveSHA256']+'.tar.gz')).write_bytes(b'tampered')
        with self.assertRaisesRegex(ValueError, 'SHA-256'):
            self.package()
        self.assertFalse((self.base/'source.tar.gz').exists())

    def test_binary_source_mismatch_rejected(self):
        self.write('Resources/Updates.json', json.dumps({'sparkleVersion':'3.0.0', 'sparkleSHA256':'2'*64}))
        with self.assertRaisesRegex(ValueError, 'pinned binary'):
            self.package(commit=self.commit_all())

    def test_missing_build_material_rejected(self):
        (self.repo/'SOURCE_BUILD.md').unlink()
        with self.assertRaisesRegex(ValueError, 'build material'):
            self.package(commit=self.commit_all())

    def test_git_symlink_rejected(self):
        (self.repo/'Sources/unsafe-link').symlink_to('/private/etc/passwd')
        with self.assertRaisesRegex(ValueError, 'Git submodule or link'):
            self.package(commit=self.commit_all())

    def test_git_export_ignore_cannot_silently_omit_source(self):
        self.write('.gitattributes', 'Sources/main.swift export-ignore\n')
        with self.assertRaisesRegex(ValueError, 'export attributes'):
            self.package(commit=self.commit_all())

    def test_dependency_lock_cannot_switch_to_unverified_download(self):
        self.dep['archiveURL'] = 'https://example.invalid/arbitrary-source.tar.gz'
        self.write('Resources/ThirdPartySources.json', json.dumps({'schemaVersion':1, 'dependencies':[self.dep]}))
        with self.assertRaisesRegex(ValueError, 'pinned binary'):
            self.package(commit=self.commit_all())

    def test_dependency_traversal_and_links_rejected(self):
        for name in [self.root+'/../escape', '/absolute', 'other/LICENSE']:
            path = self.base/'hostile.tar.gz'
            path.write_bytes(tar_bytes({name: b'bad'}))
            with self.assertRaises(ValueError):
                source_archive.dependency_files(self.dep, path)
        link = tarfile.TarInfo(self.root+'/link'); link.type = tarfile.SYMTYPE; link.linkname = '/etc/passwd'
        path.write_bytes(tar_bytes({}, special=link))
        with self.assertRaisesRegex(ValueError, 'Links'):
            source_archive.dependency_files(self.dep, path)

    def test_missing_vendored_sources_rejected(self):
        path = self.base/'missing.tar.gz'
        path.write_bytes(tar_bytes({self.root+'/.gitmodules':b'', self.root+'/LICENSE':b'notice'}))
        with self.assertRaisesRegex(ValueError, 'Missing required dependency source'):
            source_archive.dependency_files(self.dep, path)

    def test_unlisted_dependency_submodules_rejected(self):
        path = self.base/'modules.tar.gz'
        path.write_bytes(tar_bytes({self.root+'/.gitmodules':b'[submodule "missing"]\npath=missing\n'}))
        with self.assertRaisesRegex(ValueError, 'submodules changed'):
            source_archive.dependency_files(self.dep, path)

    def test_refuses_overwrite(self):
        self.package()
        with self.assertRaisesRegex(ValueError, 'overwrite'):
            self.package()


if __name__ == '__main__':
    unittest.main()
