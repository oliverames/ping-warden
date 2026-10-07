"""Verified delivery helpers and pinned official Linear scheduled-release client."""
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

CLI_VERSION = 'v0.18.0'
CLI_ORIGIN = 'https://github.com/linear/linear-release/releases/download/' + CLI_VERSION
CLI_DIGESTS = {
    'darwin-arm64': '91060da15543d38b417f496e9a17f9991799e1e0c783126612c37e802766d711',
    'darwin-x64': 'e00384ead55982e1ded0e84ee1d8bd0ab3030d7b3647d9569e46203a9e83a49e',
    'linux-arm64': 'de74648749a540f1ec4f85d057dc3f62a5c442d560b99ce2eb91b7a1b13b1087',
    'linux-x64': '0476bc8b8c23c1ed3150a55fdeb17c91d6cafcdf5f52dab74b4f89539b3c374a',
}
SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def run(args, *, cwd=None, env=None):
    """Never expose child output on failure, which may contain credentials."""
    child_env = dict(os.environ if env is None else env)
    for name in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE',
                 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_NAMESPACE'):
        child_env.pop(name, None)
    result = subprocess.run([str(a) for a in args], cwd=cwd, env=child_env,
                            capture_output=True, text=True, timeout=180)
    if result.returncode:
        raise RuntimeError(f'{Path(args[0]).name} failed (exit {result.returncode}); no child output was logged')
    return result.stdout.strip()


def digest(path):
    checksum = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            checksum.update(chunk)
    return checksum.hexdigest()


def download(url, destination, *, user_agent=None):
    # Use the host's trusted curl certificate store. Never disable TLS checks.
    command = ['curl', '--fail', '--silent', '--show-error', '--location',
               '--max-time', '120', '--output', str(destination)]
    if user_agent:
        command += ['--user-agent', user_agent]
    run([*command, url])


def verify_download(url, expected, *, user_agent=None):
    if not Path(expected).is_file():
        raise ValueError(f'Missing release artifact: {Path(expected).name}')
    with tempfile.TemporaryDirectory(prefix='release-delivery-') as directory:
        received = Path(directory) / 'received'
        download(url, received, user_agent=user_agent)
        if digest(received) != digest(expected):
            raise ValueError(f'Served bytes do not match {Path(expected).name}')


def verify_feed(url, expected, version, asset_url, artifact, *, user_agent=None):
    verify_download(url, expected, user_agent=user_agent)
    items = ET.parse(expected).findall('channel/item')
    matches = []
    for item in items:
        enclosure = item.find('enclosure')
        if enclosure is None:
            continue
        item_version = item.findtext(SPARKLE + 'shortVersionString') or enclosure.get(SPARKLE + 'shortVersionString')
        if item_version == version and enclosure.get('url') == asset_url:
            matches.append(enclosure)
    if len(matches) != 1:
        raise ValueError('Served feed must contain exactly one enclosure for the requested release')
    enclosure = matches[0]
    if not enclosure.get(SPARKLE + 'edSignature') or int(enclosure.get('length', '-1')) != Path(artifact).stat().st_size:
        raise ValueError('Feed signature or enclosure length is missing or incorrect')


def validate_version(version):
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', version):
        raise ValueError('Use an explicit semantic release version without the v prefix')


def github_release(repo, version, assets):
    release = json.loads(run(['gh', 'api', f'repos/oliverames/{repo}/releases/tags/v{version}']))
    if release.get('draft') or not release.get('published_at'):
        raise ValueError('GitHub release is not published')
    if bool(release.get('prerelease')) != ('-' in version):
        raise ValueError('GitHub stable/beta status does not match the release version')
    names = [a['name'] for a in release.get('assets', [])]
    if any(names.count(name) != 1 for name in assets):
        raise ValueError('GitHub release does not contain every expected delivery asset exactly once')
    return release


def source_commit(root, repo, version, source_ref=None):
    # Resolve the immutable release tag remotely, not a moving checkout branch.
    if source_ref:
        if not re.fullmatch(r'[0-9a-f]{40}', source_ref):
            raise ValueError('--source-ref must be the full SHA recorded for the built artifacts')
        sha = source_ref
        if repo != 'apple-core':
            tagged = run(['gh', 'api', f'repos/oliverames/{repo}/commits/v{version}', '--jq', '.sha'])
            if tagged != sha:
                raise ValueError('Explicit source SHA does not match the published release tag')
    else:
        sha = run(['gh', 'api', f'repos/oliverames/{repo}/commits/v{version}', '--jq', '.sha'])
    if not re.fullmatch(r'[0-9a-f]{40}', sha):
        raise ValueError('Could not resolve the delivered source commit')
    run(['git', 'cat-file', '-e', sha + '^{commit}'], cwd=root)
    return sha


def retry(action, attempts=6, delay=10):
    for attempt in range(attempts):
        try:
            return action()
        except (RuntimeError, ValueError, OSError, ET.ParseError):
            if attempt + 1 == attempts:
                raise
            print(f'Waiting for delivery verification ({attempt + 1}/{attempts})...', flush=True)
            time.sleep(delay)


def install_cli():
    machine = {'aarch64': 'arm64', 'arm64': 'arm64', 'x86_64': 'x64'}.get(platform.machine())
    key = platform.system().lower() + '-' + str(machine)
    if key not in CLI_DIGESTS:
        raise ValueError('Unsupported host for the pinned Linear CLI')
    name = 'linear-release-' + key
    path = Path.home() / 'Library/Caches/ames-release/linear-release' / CLI_VERSION / name
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if digest(path) != CLI_DIGESTS[key]:
            raise ValueError('Cached Linear CLI checksum mismatch; remove the invalid cached file before retrying')
    else:
        with tempfile.TemporaryDirectory(dir=path.parent, prefix='download-') as directory:
            staged = Path(directory) / name
            download(CLI_ORIGIN + '/' + name, staged)
            if digest(staged) != CLI_DIGESTS[key]:
                raise ValueError('Downloaded Linear CLI checksum mismatch')
            staged.chmod(0o700)
            staged.replace(path)
    return path


def report(root, repo, title, version, sha, link, *, dry_run=False, base_ref=None, check_access=False, notes=None):
    """Only call after every required consumer delivery check has succeeded."""
    if check_access and not dry_run:
        raise ValueError('Access checks require --dry-run')
    if dry_run and not check_access:
        print(f'Dry run: verified {title} {version}; would sync and complete the scheduled Linear release at {sha}')
        return
    if run(['git', 'rev-parse', '--is-shallow-repository'], cwd=root) != 'false':
        raise ValueError('Release reporting requires full local Git history; unshallow the source checkout first')
    cli = install_cli()
    key = os.environ.get('LINEAR_ACCESS_KEY') or run([
        'op', 'read', f'op://Development/Linear Release - {repo}/credential'])
    if not key.strip():
        raise ValueError('Linear pipeline credential is empty')
    env = os.environ.copy()
    env['LINEAR_ACCESS_KEY'] = key.strip()
    env['LINEAR_VCS_PROVIDER'] = 'github'
    # Avoid accidental alternate endpoints and CI commit overrides from the parent shell.
    for name in list(env):
        if name.startswith('LINEAR_') and name not in ('LINEAR_ACCESS_KEY', 'LINEAR_VCS_PROVIDER'):
            del env[name]
    with tempfile.TemporaryDirectory(prefix='linear-release-source-') as directory:
        checkout = Path(directory) / 'source'
        # No checkout, hooks, or source edits. The CLI only needs commit metadata.
        run(['git', 'clone', '--quiet', '--shared', '--no-checkout', str(root), str(checkout)])
        run(['git', 'update-ref', '--no-deref', 'HEAD', sha], cwd=checkout)
        run(['git', 'remote', 'set-url', 'origin', f'https://github.com/oliverames/{repo}.git'], cwd=checkout)
        common = [f'--release-version={version}', '--json', '--timeout=120']
        if notes:
            note_path = Path(directory) / 'Release Notes.md'
            note_path.write_text(notes)
            common.append('--release-notes-file=' + str(note_path))
        sync = [str(cli), 'sync', *common, f'--name={title} {version}', f'--link={link}', '--no-branch-ref-detection']
        if base_ref:
            sync.append('--base-ref=' + base_ref)
        if check_access:
            run([*sync, '--dry-run'], cwd=checkout, env=env)
            print(f'Linear pipeline read access verified for {title}; no release was written')
            return
        result = json.loads(run(sync, cwd=checkout, env=env))
        if not result.get('release') and not base_ref:
            # A no-commit first sync does not create a release. Explicit empty
            # baseline creates the delivered version without backfilling history.
            result = json.loads(run([*sync, '--base-ref=' + sha], cwd=checkout, env=env))
        release = result.get('release') or {}
        if release.get('version') != version or not release.get('id'):
            raise ValueError('Linear sync did not return the requested release; completion was not attempted')
        completed = json.loads(run([str(cli), 'complete', *common], cwd=checkout, env=env)).get('release') or {}
        if completed.get('version') != version or completed.get('id') != release['id']:
            raise ValueError('Linear completion was not confirmed for the requested release; retry reporting only')
    print(f'Linear confirmed completed release: {title} {version}')
