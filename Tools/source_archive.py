#!/usr/bin/env python3
"""Package one committed RetinaLink tree and verified corresponding dependency source."""
import argparse
import gzip
import hashlib
import io
import json
import os
import pathlib
import re
import subprocess
import tarfile
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
EXCLUDED_ROOTS = {'.git', '.build', 'build', 'work', 'outputs', '__pycache__'}
MAX_SOURCE_BYTES = 256 * 1024 * 1024


def digest(path):
    value = hashlib.sha256()
    with pathlib.Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def safe_path(name):
    path = pathlib.PurePosixPath(name)
    if not name or path.is_absolute() or '..' in path.parts or '\\' in name:
        raise ValueError('Unsafe source archive path')
    return path


def excluded(name):
    path = safe_path(name)
    return (path.parts[0] in EXCLUDED_ROOTS or
            bool(re.fullmatch(r'build[0-9]+', path.parts[0])) or
            any(part.lower() == 'security_review.md' for part in path.parts) or
            '.git' in path.parts)


def git(repo, *args):
    return subprocess.check_output(['git', '--literal-pathspecs', '-C', str(repo), *args])


def committed_tree(repo, revision):
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Use the full 40-character source commit, not a branch or tag')
    commit = git(repo, 'rev-parse', '--verify', revision + '^{commit}').decode().strip()
    if commit != revision:
        raise ValueError('Source commit did not resolve exactly')
    paths, omitted = [], []
    for record in git(repo, 'ls-tree', '-rz', '--full-tree', commit).split(b'\0'):
        if not record:
            continue
        metadata, raw_name = record.split(b'\t', 1)
        name = raw_name.decode('utf-8')
        mode, kind, _ = metadata.decode('ascii').split()
        if excluded(name):
            omitted.append(name)
            continue
        if kind != 'blob' or mode not in {'100644', '100755'}:
            raise ValueError('Unpackaged Git submodule or link in source: ' + name)
        paths.append(name)
    if not paths:
        raise ValueError('The commit contains no packageable source')
    source = git(repo, 'archive', '--format=tar', commit, '--', *paths)
    with tarfile.open(fileobj=io.BytesIO(source)) as archive:
        files = {member.name: archive.extractfile(member).read()
                 for member in archive.getmembers() if member.isfile()}
        modes = {member.name: 0o755 if member.mode & 0o111 else 0o644
                 for member in archive.getmembers() if member.isfile()}
    if set(files) != set(paths):
        raise ValueError('Git export attributes omitted committed source files')
    return commit, files, modes, sorted(omitted)


def load_lock(files):
    lock = json.loads(files['Resources/ThirdPartySources.json'])
    updates = json.loads(files['Resources/Updates.json'])
    if lock.get('schemaVersion') != 1 or len(lock.get('dependencies', [])) != 1:
        raise ValueError('Unsupported corresponding-source lock schema')
    sparkle = lock['dependencies'][0]
    commit = sparkle.get('commit', '')
    if (sparkle.get('name') != 'Sparkle' or not re.fullmatch(r'[0-9a-f]{40}', commit) or
            sparkle.get('repository') != 'https://github.com/sparkle-project/Sparkle' or
            sparkle.get('archiveURL') != 'https://codeload.github.com/sparkle-project/Sparkle/tar.gz/' + commit or
            sparkle.get('archiveRoot') != 'Sparkle-' + commit or
            not re.fullmatch(r'[0-9a-f]{64}', sparkle.get('archiveSHA256', '')) or
            sparkle.get('version') != updates['sparkleVersion'] or
            sparkle.get('binaryArchiveSHA256') != updates['sparkleSHA256'] or
            sparkle.get('submodules') != []):
        raise ValueError('Sparkle source lock does not match the pinned binary dependency')
    if not sparkle.get('requiredSourcePaths'):
        raise ValueError('Dependency source-path audit is missing')
    return lock


def fetch_dependency(dependency, cache):
    cache = pathlib.Path(cache)
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / (dependency['archiveSHA256'] + '.tar.gz')
    if not archive.exists():
        descriptor, temporary = tempfile.mkstemp(prefix='source-', suffix='.download', dir=cache)
        os.close(descriptor)
        try:
            subprocess.run(['/usr/bin/curl', '--fail', '--location', '--silent', '--show-error',
                            '--proto', '=https', '--proto-redir', '=https', '--tlsv1.2',
                            '--connect-timeout', '15', '--max-time', '180',
                            '--output', temporary, dependency['archiveURL']], check=True)
            if digest(temporary) != dependency['archiveSHA256']:
                raise ValueError('Downloaded corresponding-source archive failed SHA-256 verification')
            pathlib.Path(temporary).replace(archive)
        finally:
            pathlib.Path(temporary).unlink(missing_ok=True)
    if digest(archive) != dependency['archiveSHA256']:
        raise ValueError('Cached corresponding-source archive failed SHA-256 verification')
    return archive


def dependency_files(dependency, archive_path):
    result, modes = {}, {}
    root = dependency['archiveRoot']
    total = 0
    with tarfile.open(archive_path) as archive:
        for member in archive:
            path = safe_path(member.name)
            if path.parts[0] != root:
                raise ValueError('Unexpected dependency archive root')
            if member.isdir():
                continue
            if not member.isfile() or len(path.parts) < 2:
                raise ValueError('Links and special files are not allowed in dependency source')
            name = '/'.join(path.parts[1:])
            if name in result:
                raise ValueError('Duplicate dependency archive path')
            total += member.size
            if total > MAX_SOURCE_BYTES:
                raise ValueError('Dependency source exceeds the bounded archive size')
            result[name] = archive.extractfile(member).read()
            modes[name] = 0o755 if member.mode & 0o111 else 0o644
    if '.gitmodules' not in result or result['.gitmodules'].strip():
        raise ValueError('Dependency submodules changed; audit and lock every submodule source first')
    for required in dependency['requiredSourcePaths']:
        if str(safe_path(required)) not in result:
            raise ValueError('Missing required dependency source: ' + required)
    return result, modes


def add_file(archive, name, data, mode, timestamp):
    item = tarfile.TarInfo(name)
    item.size, item.mode, item.mtime = len(data), mode, timestamp
    item.uid = item.gid = 0
    item.uname = item.gname = ''
    archive.addfile(item, io.BytesIO(data))


def package(repo, commit, output, cache):
    repo, output = pathlib.Path(repo).resolve(), pathlib.Path(output).resolve()
    if output.exists():
        raise ValueError('Refusing to overwrite an existing source archive')
    commit, files, modes, omitted = committed_tree(repo, commit)
    for required in ['LICENSE', 'SOURCE_BUILD.md', 'build.sh', 'Resources/Release.json']:
        if required not in files:
            raise ValueError('Missing committed source/build material: ' + required)
    lock = load_lock(files)
    version = json.loads(files['Resources/Release.json'])
    if not re.fullmatch(r'\d+\.\d+\.\d+', version['version']):
        raise ValueError('Unexpected source version')
    prefix = 'RetinaLink-' + version['version'] + '-source'
    manifest = {'schemaVersion': 1, 'sourceCommit': commit,
                'sourceTree': git(repo, 'rev-parse', commit + '^{tree}').decode().strip(),
                'version': version['version'], 'build': version['build'],
                'license': 'GPL-3.0-only', 'excludedTrackedPaths': omitted,
                'dependencies': []}
    for dependency in lock['dependencies']:
        path = fetch_dependency(dependency, cache)
        sources, source_modes = dependency_files(dependency, path)
        destination = 'VendorSources/' + dependency['name'] + '-' + dependency['version']
        for name, data in sources.items():
            target = destination + '/' + name
            if target in files:
                raise ValueError('Dependency source collides with committed project source')
            files[target], modes[target] = data, source_modes[name]
        manifest['dependencies'].append({**dependency, 'sourceDirectory': destination})
    if 'SOURCE_MANIFEST.json' in files:
        raise ValueError('Source manifest collides with committed project source')
    files['SOURCE_MANIFEST.json'] = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    modes['SOURCE_MANIFEST.json'] = 0o644
    timestamp = int(git(repo, 'show', '-s', '--format=%ct', commit))
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=output.name + '.', dir=output.parent)
    try:
        with os.fdopen(descriptor, 'wb') as raw:
            with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=timestamp) as compressed:
                with tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as archive:
                    for name in sorted(files):
                        add_file(archive, prefix + '/' + name, files[name], modes[name], timestamp)
        os.replace(temporary, output)
    finally:
        pathlib.Path(temporary).unlink(missing_ok=True)
    return {'archive': str(output), 'sha256': digest(output), **manifest}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--commit', required=True, help='Full source Git commit recorded by the signed release')
    parser.add_argument('--output', required=True, type=pathlib.Path, help='New .tar.gz archive path')
    parser.add_argument('--manifest', type=pathlib.Path, help='Write the archive digest and source manifest as JSON')
    parser.add_argument('--cache-directory', type=pathlib.Path, default=ROOT/'build/source-cache')
    args = parser.parse_args()
    report = package(ROOT, args.commit, args.output, args.cache_directory)
    text = json.dumps(report, indent=2) + '\n'
    if args.manifest:
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        args.manifest.write_text(text)
    print(text, end='')


if __name__ == '__main__':
    main()
