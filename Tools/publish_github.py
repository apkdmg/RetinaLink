#!/usr/bin/env python3
"""Publish a completed signed release to GitHub Releases and GitHub Pages.

`plan` writes a local hash-pinned manifest without contacting GitHub. `publish`
resumes that exact plan: it never replaces an asset or moves a release tag.
Apple and Sparkle signing remain local; this tool does not read signing keys.
"""
import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_REPOSITORY = 'apkdmg/RetinaLink'
ALLOWED_PAGES = {'.nojekyll', 'updates/host/appcast.xml', 'updates/viewer/appcast.xml'}
SHA = re.compile(r'[0-9a-f]{64}')


def digest(path):
    value = hashlib.sha256()
    with pathlib.Path(path).open('rb') as file:
        for block in iter(lambda: file.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def repository_name(value):
    if value.startswith('https://github.com/'):
        parsed = urllib.parse.urlsplit(value)
        if parsed.query or parsed.fragment or parsed.username or parsed.password or parsed.port:
            raise ValueError('Use a plain GitHub owner/repository or HTTPS repository URL.')
        value = parsed.path.strip('/').removesuffix('.git')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}', value):
        raise ValueError('Use a GitHub owner/repository, not an account, SSH URL or arbitrary host.')
    if value.split('/')[1] in ('.', '..'):
        raise ValueError('Invalid repository name.')
    return value


def locations(repository, version):
    owner, name = repository.split('/')
    return (f'https://{owner.lower()}.github.io/{name}/updates',
            f'https://github.com/{repository}/releases/download/v{version}')


def ordinary_file(path):
    path = pathlib.Path(path).absolute()
    if path.is_symlink() or not path.is_file():
        raise ValueError('Publication inputs must be ordinary files: ' + str(path))
    return path.resolve()


def file_record(path):
    path = ordinary_file(path)
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', path.name):
        raise ValueError('Release asset names must use letters, numbers, dots, hyphens or underscores.')
    return {'path': str(path), 'name': path.name, 'size': path.stat().st_size, 'sha256': digest(path)}


def assert_record(record):
    if not SHA.fullmatch(record.get('sha256', '')):
        raise ValueError('Invalid planned SHA-256.')
    actual = file_record(record['path'])
    if actual != record:
        raise ValueError('A planned publication file changed: ' + record.get('name', '?'))


def save_json(path, value):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.next')
    with os.fdopen(os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as file:
        json.dump(value, file, indent=2)
        file.write('\n')
    temporary.replace(path)


def verify_source(source, manifest_path, commit, version, build):
    manifest = json.loads(ordinary_file(manifest_path).read_text())
    if (manifest.get('schemaVersion') != 1 or manifest.get('sourceCommit') != commit or
            manifest.get('version') != version or str(manifest.get('build')) != build or
            manifest.get('license') != 'GPL-3.0-only' or manifest.get('sha256') != source['sha256'] or
            pathlib.Path(manifest.get('archive', '')).resolve() != pathlib.Path(source['path']) or
            manifest.get('excludedTrackedPaths') != [] or
            not re.fullmatch(r'[0-9a-f]{40}', manifest.get('sourceTree', ''))):
        raise ValueError('Corresponding-source metadata must match this exact clean release commit and archive.')
    dependencies = manifest.get('dependencies', [])
    if not dependencies or not any(dependency.get('name') == 'Sparkle' for dependency in dependencies):
        raise ValueError('Corresponding source must include the bundled Sparkle dependency source.')
    for dependency in dependencies:
        if (not re.fullmatch(r'[0-9a-f]{40}', dependency.get('commit', '')) or
                not SHA.fullmatch(dependency.get('archiveSHA256', '')) or
                not str(dependency.get('sourceDirectory', '')).startswith('VendorSources/')):
            raise ValueError('Dependency source metadata is incomplete.')
    with tarfile.open(source['path'], 'r:gz') as archive:
        member = archive.getmember('RetinaLink-' + version + '-source/SOURCE_MANIFEST.json')
        if not member.isfile() or member.size > 1024 * 1024:
            raise ValueError('The corresponding-source archive manifest is invalid.')
        with archive.extractfile(member) as file:
            internal = json.load(file)
    if internal != {key: value for key, value in manifest.items() if key not in ('archive', 'sha256')}:
        raise ValueError('The corresponding-source archive and external source manifest differ.')
    return file_record(manifest_path)


def prepare_plan(directory, feeds, source_archive, assets, repository, output, source_manifest=None):
    repository = repository_name(repository)
    directory, feeds = pathlib.Path(directory).resolve(), pathlib.Path(feeds).resolve()
    state = json.loads((directory / 'release-state.json').read_text())
    if not state.get('complete') or state.get('source_dirty') is not False:
        raise ValueError('Public releases require a completed release built from a clean source commit.')
    commit = state.get('source_commit', '')
    if not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise ValueError('Release source_commit must be a full Git commit SHA.')
    version, build = state['apps']['Host']['version'], str(state['apps']['Host']['build'])
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'[1-9]\d*', build):
        raise ValueError('A three-part version and positive numeric build are required.')
    for role in ('Host', 'Viewer'):
        app, submission = state['apps'][role], state['submissions'][role]
        if (app['version'] != version or str(app['build']) != build or
                submission.get('status') != 'Accepted' or not submission.get('stapled')):
            raise ValueError('Both matching apps must be accepted and stapled.')
    distribution = state['distribution']
    if digest(ordinary_file(directory / distribution['file'])) != distribution['sha256']:
        raise ValueError('The completed release distribution changed.')
    feed_base, archive_base = locations(repository, version)
    manifest = json.loads((feeds / 'release.json').read_text())
    if (manifest.get('version') != version or str(manifest.get('build')) != build or
            manifest.get('baseURL') != feed_base or manifest.get('archiveBaseURL') != archive_base):
        raise ValueError('Feeds must pin this repository, version and immutable GitHub Release archive URLs.')
    archives, pages = [], []
    for role in ('Host', 'Viewer'):
        folder = feeds / role.lower()
        entry = manifest['roles'][role]
        archive = file_record(folder / entry['archive'])
        feed = file_record(folder / 'appcast.xml')
        if (archive['sha256'] != entry['sha256'] or feed['sha256'] != entry['feedSHA256'] or
                entry['archiveURL'] != archive_base + '/' + archive['name'] or
                entry['feedURL'] != feed_base + '/' + role.lower() + '/appcast.xml'):
            raise ValueError(role + ' feed/archive bytes or URLs differ from the signed manifest.')
        verify_feed(feed['path'], entry['archiveURL'], build, archive['size'])
        pages.append({'destination': f'updates/{role.lower()}/appcast.xml', 'file': feed,
                      'url': entry['feedURL']})
        archives.append(archive)
    source = file_record(source_archive)
    if not source['name'].endswith('.tar.gz') or not source_manifest:
        raise ValueError('Provide source_archive.py’s .tar.gz and --source-manifest for the exact source commit.')
    source_metadata = verify_source(source, source_manifest, commit, version, build)
    archives += [source] + [file_record(path) for path in assets]
    names = [record['name'] for record in archives]
    if len(names) != len(set(names)) or 'SHA256SUMS' in names:
        raise ValueError('Release asset names must be unique; SHA256SUMS is reserved.')
    output = pathlib.Path(output).resolve()
    checksums = output.parent / ('v' + version + '-SHA256SUMS')
    checksum_bytes = ''.join(record['sha256'] + '  ' + record['name'] + '\n'
                             for record in sorted(archives, key=lambda item: item['name'])).encode()
    if checksums.exists() and checksums.read_bytes() != checksum_bytes:
        raise ValueError('An existing checksum file describes different release bytes.')
    checksums.parent.mkdir(parents=True, exist_ok=True)
    checksums.write_bytes(checksum_bytes)
    archives.append(file_record(checksums))
    plan = {'format': 1, 'repository': repository, 'version': version, 'build': build,
            'tag': 'v' + version, 'sourceCommit': commit, 'sourceArchive': source['name'],
            'sourceManifest': source_metadata,
            'feedBaseURL': feed_base, 'archiveBaseURL': archive_base,
            'assets': archives, 'pages': pages}
    if output.exists() and json.loads(output.read_text()) != plan:
        raise ValueError('This plan already pins different bytes; use a new plan path.')
    save_json(output, plan)
    return plan


def verify_feed(path, archive_url, build, size):
    # Preserve the signed XML exactly; parsing here only rejects a misrouted feed.
    root = ET.parse(path).getroot()
    if max(feed_builds(root)) != int(build):
        raise ValueError('The staged feed must have this release as its newest build.')
    items = root.findall('./channel/item')
    matching = []
    sparkle = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    for item in items:
        for enclosure in item.findall('enclosure'):
            if enclosure.get('url') == archive_url:
                matching.append((item, enclosure))
    if (len(matching) != 1 or
            (matching[0][0].findtext(sparkle + 'version') or matching[0][1].get(sparkle + 'version')) != build or
            matching[0][1].get('length') != str(size) or not matching[0][1].get(sparkle + 'edSignature')):
        raise ValueError('The signed feed must enclose the exact build, archive URL and byte length.')


def feed_builds(root):
    sparkle = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    result = []
    for item in root.findall('./channel/item'):
        values = [node.text for node in item.findall(sparkle + 'version')]
        values += [node.get(sparkle + 'version') for node in item.findall('enclosure')
                   if node.get(sparkle + 'version') is not None]
        if (not values or any(not re.fullmatch(r'[1-9]\d*', value or '') for value in values)
                or len(set(values)) != 1):
            raise ValueError('An existing feed item has missing, invalid or conflicting build versions.')
        result.append(int(values[0]))
    if not result:
        raise ValueError('An existing feed has no recognizable build versions.')
    return result


class GitHub:
    def __init__(self, executable, repository):
        self.executable, self.repository = str(executable), repository_name(repository)

    def api(self, suffix, method='GET', data=None, allow_missing=False):
        arguments = [self.executable, 'api', '--hostname', 'github.com',
                     '-H', 'Accept: application/vnd.github+json',
                     '-H', 'X-GitHub-Api-Version: 2022-11-28',
                     '--method', method, 'repos/' + self.repository + suffix]
        if data is not None:
            arguments += ['--input', '-']
        result = subprocess.run(arguments, input=json.dumps(data) if data is not None else None,
                                text=True, capture_output=True)
        if result.returncode:
            if allow_missing and re.search(r'\bHTTP 404\b', result.stderr):
                return None
            raise RuntimeError('GitHub API failed: ' + result.stderr.strip())
        return json.loads(result.stdout) if result.stdout.strip() else None

    def verify_access(self):
        result = self.api('')
        if (result.get('full_name', '').lower() != self.repository.lower() or result.get('private') is not False or
                not result.get('permissions', {}).get('push') or not result.get('permissions', {}).get('admin')):
            raise ValueError('Authenticate gh with administrator access to the exact public repository.')

    def upload(self, tag, record):
        # No --clobber: release assets are immutable, including draft retries.
        subprocess.run([self.executable, 'release', 'upload', tag, record['path'],
                        '--repo', self.repository], check=True)

    def verify_asset(self, remote, expected):
        if (remote.get('name') != expected['name'] or remote.get('size') != expected['size'] or
                remote.get('state') != 'uploaded'):
            raise ValueError('A GitHub asset is incomplete or has a different name/size.')
        advertised = remote.get('digest')
        if advertised and advertised != 'sha256:' + expected['sha256']:
            raise ValueError('GitHub reports different asset bytes: ' + expected['name'])
        with tempfile.TemporaryFile() as downloaded:
            subprocess.run([self.executable, 'api', '--hostname', 'github.com',
                            '-H', 'Accept: application/octet-stream',
                            'repos/' + self.repository + '/releases/assets/' + str(int(remote['id']))],
                           check=True, stdout=downloaded)
            downloaded.seek(0)
            value = hashlib.sha256()
            for block in iter(lambda: downloaded.read(1024 * 1024), b''):
                value.update(block)
            if downloaded.tell() != expected['size'] or value.hexdigest() != expected['sha256']:
                raise ValueError('Downloaded GitHub asset does not match the plan: ' + expected['name'])


def release_body(plan):
    return (f'RetinaLink {plan["version"]} (build {plan["build"]}).\n\n'
            'Developer ID signed and Apple-notarized Host and Viewer. Automatic updates '
            'are signed separately with the existing Sparkle update key.\n\n'
            f'GPL-3.0-only corresponding source: `{plan["sourceArchive"]}`, '
            f'commit `{plan["sourceCommit"]}`. Existing pairing is retained.\n')


def publish_release(client, plan):
    # The tag endpoint documents published releases only. Listing releases as a
    # push-authorized user includes drafts, so an interrupted draft is resumable.
    matches = []
    published_versions = []
    for page in range(1, 11):
        batch = client.api('/releases?per_page=100&page=' + str(page))
        matches += [entry for entry in batch if entry.get('tag_name') == plan['tag']]
        for entry in batch:
            version = re.fullmatch(r'v(\d+)\.(\d+)\.(\d+)', entry.get('tag_name', ''))
            if version and not entry.get('draft') and not entry.get('prerelease'):
                published_versions.append(tuple(int(part) for part in version.groups()))
        if len(batch) < 100:
            break
    else:
        raise ValueError('Unexpectedly many existing releases; refusing an ambiguous creation.')
    if len(matches) > 1:
        raise ValueError('Multiple releases use this tag; refusing to guess which draft to update.')
    if any(version > tuple(int(part) for part in plan['version'].split('.')) for version in published_versions):
        raise ValueError('A newer public release already exists; an older plan cannot become the latest release.')
    release = matches[0] if matches else None
    if not release:
        release = client.api('/releases', 'POST', {'tag_name': plan['tag'],
                             'target_commitish': plan['sourceCommit'], 'name': 'RetinaLink ' + plan['version'],
                             'body': release_body(plan), 'draft': True, 'prerelease': False})
    if release.get('tag_name') != plan['tag'] or release.get('prerelease'):
        raise ValueError('Existing release does not match this publication plan.')
    # Paginate assets explicitly; never overlook a conflicting asset after page one.
    remote = []
    for page in range(1, 11):
        batch = client.api('/releases/' + str(int(release['id'])) + '/assets?per_page=100&page=' + str(page))
        remote += batch
        if len(batch) < 100:
            break
    else:
        raise ValueError('Unexpectedly many existing release assets.')
    by_name = {entry['name']: entry for entry in remote}
    if len(by_name) != len(remote):
        raise ValueError('Duplicate remote release asset names.')
    expected_names = {entry['name'] for entry in plan['assets']}
    if set(by_name) - expected_names:
        raise ValueError('Existing release contains assets outside this plan; refusing to alter it.')
    for expected in plan['assets']:
        entry = by_name.get(expected['name'])
        if entry is None:
            if not release.get('draft'):
                raise ValueError('A public release is missing an asset; never append or replace public release assets.')
            client.upload(plan['tag'], expected)
            batch = client.api('/releases/' + str(int(release['id'])) + '/assets?per_page=100')
            entry = next((item for item in batch if item['name'] == expected['name']), None)
            if entry is None:
                raise ValueError('Uploaded asset is missing; leave the release draft and retry.')
        client.verify_asset(entry, expected)
    if release.get('draft'):
        client.api('/releases/' + str(int(release['id'])), 'PATCH', {'draft': False, 'make_latest': 'true'})
    return 'https://github.com/' + plan['repository'] + '/releases/tag/' + plan['tag']


def git(arguments, *, cwd=ROOT, data=None, environment=None, raw=False):
    value = subprocess.check_output(['/usr/bin/git'] + [str(value) for value in arguments], cwd=cwd,
                                    input=data, env=environment)
    return value if raw else value.decode().strip()


def ensure_tag(plan):
    remote = 'https://github.com/' + plan['repository'] + '.git'
    tag = 'refs/tags/' + plan['tag']
    rows = git(['ls-remote', remote, tag, tag + '^{}']).splitlines()
    values = {line.split()[1]: line.split()[0] for line in rows if line.strip()}
    if values:
        if values.get(tag + '^{}', values.get(tag)) != plan['sourceCommit']:
            raise ValueError('The remote release tag already points to different source; it will not be moved.')
        return
    if git(['rev-parse', '--verify', plan['sourceCommit'] + '^{commit}']) != plan['sourceCommit']:
        raise ValueError('The exact release source commit is unavailable locally.')
    # Only this immutable lightweight tag is pushed, never --tags, --all or --mirror.
    git(['-c', 'push.followTags=false', 'push', remote, plan['sourceCommit'] + ':' + tag])


def publish_pages(plan, *, push=True):
    remote = 'https://github.com/' + plan['repository'] + '.git'
    with tempfile.TemporaryDirectory(prefix='retinalink-pages-') as folder:
        folder = pathlib.Path(folder)
        git(['init', '--bare', folder], cwd=folder)
        env = dict(os.environ, GIT_INDEX_FILE=str(folder / 'publication-index'),
                   GIT_AUTHOR_NAME='RetinaLink Releases', GIT_AUTHOR_EMAIL='releases@users.noreply.github.com',
                   GIT_COMMITTER_NAME='RetinaLink Releases', GIT_COMMITTER_EMAIL='releases@users.noreply.github.com')
        rows = git(['ls-remote', remote, 'refs/heads/gh-pages'], cwd=folder).splitlines()
        parent = None
        if rows:
            parent = rows[0].split()[0]
            git(['fetch', '--no-tags', '--depth=1', remote, 'refs/heads/gh-pages'], cwd=folder)
            if git(['rev-parse', 'FETCH_HEAD'], cwd=folder) != parent:
                raise ValueError('Pages changed during preparation; retry without overwriting it.')
            paths = set(git(['ls-tree', '-r', '--name-only', parent], cwd=folder).splitlines())
            if paths - ALLOWED_PAGES:
                raise ValueError('The Pages branch contains unexpected files; refusing to rewrite it.')
            for path in sorted(paths - {'.nojekyll'}):
                old_bytes = git(['show', parent + ':' + path], cwd=folder, raw=True)
                old_feed = ET.fromstring(old_bytes)
                latest = max(feed_builds(old_feed))
                if latest > int(plan['build']):
                    raise ValueError('The live Pages feed contains a newer build; publication will not roll it back.')
                planned = next(entry for entry in plan['pages'] if entry['destination'] == path)
                if latest == int(plan['build']) and old_bytes != pathlib.Path(planned['file']['path']).read_bytes():
                    raise ValueError('The live feed already publishes this build with different signed bytes; bump the build.')
            git(['read-tree', parent], cwd=folder, environment=env)
        else:
            git(['read-tree', '--empty'], cwd=folder, environment=env)
        entries = [('.nojekyll', b'')] + [(entry['destination'], pathlib.Path(entry['file']['path']).read_bytes())
                                         for entry in plan['pages']]
        if {path for path, _ in entries} != ALLOWED_PAGES:
            raise ValueError('Pages may contain only the two exact signed feeds and .nojekyll.')
        for path, content in entries:
            blob = git(['hash-object', '-w', '--stdin'], cwd=folder, data=content)
            git(['update-index', '--add', '--cacheinfo', '100644,' + blob + ',' + path],
                cwd=folder, environment=env)
        tree = git(['write-tree'], cwd=folder, environment=env)
        if parent and git(['rev-parse', parent + '^{tree}'], cwd=folder) == tree:
            return parent
        args = ['commit-tree', tree] + (['-p', parent] if parent else [])
        commit = git(args, cwd=folder, data=('Publish signed RetinaLink ' + plan['version'] + ' feeds\n').encode(), environment=env)
        # A normal push rejects races and never force-replaces another deployment.
        if push:
            git(['-c', 'push.followTags=false', 'push', remote, commit + ':refs/heads/gh-pages'], cwd=folder)
        return commit


def pages_configuration(client):
    pages = client.api('/pages', allow_missing=True)
    expected = {'branch': 'gh-pages', 'path': '/'}
    if pages is not None and (pages.get('build_type') != 'legacy' or pages.get('source') != expected):
        raise ValueError('Existing Pages configuration uses a different source; it will not be changed.')
    return pages


def enable_pages(client):
    pages = pages_configuration(client)
    if pages is None:
        return client.api('/pages', 'POST', {'build_type': 'legacy', 'source': {'branch': 'gh-pages', 'path': '/'}})
    return pages


def public_digest(url, maximum_size):
    if urllib.parse.urlsplit(url).scheme != 'https':
        raise ValueError('Public verification requires HTTPS.')
    # Use macOS's native TLS trust store. Never disable certificate verification
    # to work around an independently installed Python's missing CA bundle.
    value, total = hashlib.sha256(), 0
    with tempfile.TemporaryFile() as downloaded:
        result = subprocess.run(['/usr/bin/curl', '--fail', '--location', '--silent', '--show-error',
                                 '--proto', '=https', '--proto-redir', '=https', '--max-time', '300',
                                 '--max-filesize', str(maximum_size),
                                 '--user-agent', 'RetinaLink-release-verification/1', url],
                                stdout=downloaded, stderr=subprocess.PIPE)
        if result.returncode:
            raise OSError('Public HTTPS download failed: ' + result.stderr.decode(errors='replace').strip())
        downloaded.seek(0)
        for block in iter(lambda: downloaded.read(1024 * 1024), b''):
            total += len(block)
            if total > maximum_size:
                raise ValueError('Public server returned more bytes than the planned file.')
            value.update(block)
    return value.hexdigest(), total


def verify_public(plan):
    records = [(entry['url'], entry['file']) for entry in plan['pages']]
    records += [(plan['archiveBaseURL'] + '/' + entry['name'], entry) for entry in plan['assets']]
    result = []
    for url, record in records:
        try:
            actual, size = public_digest(url, record['size'])
            passed = actual == record['sha256'] and size == record['size']
            result.append({'url': url, 'verified': passed, 'sha256': actual, 'size': size})
        except (OSError, ValueError) as error:
            result.append({'url': url, 'verified': False, 'error': str(error)})
    return {'complete': all(entry['verified'] for entry in result), 'files': result}


def load_plan(path):
    plan = json.loads(pathlib.Path(path).read_text())
    repository = repository_name(plan['repository'])
    feed, archives = locations(repository, plan['version'])
    if (plan.get('format') != 1 or plan.get('tag') != 'v' + plan['version'] or
            not re.fullmatch(r'\d+\.\d+\.\d+', plan['version']) or
            not re.fullmatch(r'[0-9a-f]{40}', plan['sourceCommit']) or
            plan['feedBaseURL'] != feed or plan['archiveBaseURL'] != archives):
        raise ValueError('Invalid publication plan identity or URLs.')
    assets, pages = plan['assets'], plan['pages']
    if len(assets) > 50 or len({record['name'] for record in assets}) != len(assets):
        raise ValueError('Duplicate or excessive planned assets.')
    if plan['sourceArchive'] not in {record['name'] for record in assets}:
        raise ValueError('The GPL corresponding-source archive is missing.')
    if {entry['destination'] for entry in pages} != ALLOWED_PAGES - {'.nojekyll'} or len(pages) != 2:
        raise ValueError('Invalid Pages destinations.')
    for record in assets + [entry['file'] for entry in pages]:
        assert_record(record)
    assert_record(plan['sourceManifest'])
    source = next(record for record in assets if record['name'] == plan['sourceArchive'])
    verify_source(source, plan['sourceManifest']['path'], plan['sourceCommit'], plan['version'], plan['build'])
    for entry in pages:
        if entry['url'] != feed.removesuffix('/updates') + '/' + entry['destination']:
            raise ValueError('Invalid public feed URL.')
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['plan', 'publish', 'verify'])
    parser.add_argument('--directory', type=pathlib.Path)
    parser.add_argument('--feeds', type=pathlib.Path)
    parser.add_argument('--source-archive', type=pathlib.Path)
    parser.add_argument('--source-manifest', type=pathlib.Path, help='Private metadata produced by source_archive.py --manifest; not uploaded.')
    parser.add_argument('--asset', action='append', type=pathlib.Path, default=[])
    parser.add_argument('--repository', default=DEFAULT_REPOSITORY)
    parser.add_argument('--plan', type=pathlib.Path, required=True)
    parser.add_argument('--gh', type=pathlib.Path, help='Explicit path to authenticated GitHub CLI, required for publish.')
    args = parser.parse_args()
    try:
        if args.command == 'plan':
            if not all((args.directory, args.feeds, args.source_archive, args.source_manifest)):
                parser.error('plan requires --directory, --feeds, --source-archive and --source-manifest')
            plan = prepare_plan(args.directory, args.feeds, args.source_archive, args.asset, args.repository, args.plan, args.source_manifest)
            print(json.dumps({'plan': str(args.plan), 'tag': plan['tag'], 'assets': len(plan['assets']), 'published': False}, indent=2))
            return 0
        plan = load_plan(args.plan)
        if args.command == 'publish':
            if not args.gh or not args.gh.is_absolute() or not args.gh.is_file():
                parser.error('publish requires --gh with an explicit GitHub CLI executable path')
            client = GitHub(args.gh, plan['repository'])
            client.verify_access()
            # Prove that the source is already published before creating a tag.
            if client.api('/commits/' + plan['sourceCommit']).get('sha') != plan['sourceCommit']:
                raise ValueError('The exact release source commit is not published in this repository.')
            # Reject wrong Pages configuration/rollback before creating a tag or
            # public release. Recheck again during the actual normal branch push.
            pages_configuration(client)
            publish_pages(plan, push=False)
            ensure_tag(plan)
            url = publish_release(client, plan)
            pages = publish_pages(plan)
            enable_pages(client)
            print(json.dumps({'release': url, 'pagesCommit': pages, 'feeds': plan['feedBaseURL']}, indent=2))
        result = verify_public(plan)
        print(json.dumps(result, indent=2))
        # Deployments can take time: the exact plan can be checked later with verify.
        return 0 if result['complete'] else 3
    except (ValueError, KeyError, OSError, RuntimeError, tarfile.TarError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
