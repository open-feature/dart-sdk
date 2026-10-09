"""Verify the resolved client SDK against the official immutable pub archive."""
import hashlib
import io
import json
import re
import tarfile
from pathlib import Path
from urllib.parse import urljoin, urlparse, unquote
from urllib.request import urlopen


def resolved_package(config_path, name):
    packages = json.loads(config_path.read_text(encoding='utf-8'))['packages']
    package = next((p for p in packages if p['name'] == name), None)
    if package is None:
        raise ValueError('Required resolved package is absent')
    uri = urlparse(urljoin(config_path.as_uri(), package['rootUri']))
    if uri.scheme != 'file' or uri.netloc not in ('', 'localhost'):
        raise ValueError('Resolved package must be a local file URI')
    text = unquote(uri.path)
    if re.match(r'^/[A-Za-z]:/', text):
        text = text[1:]
    return Path(text).resolve()


def fetch_bytes(url):
    with urlopen(url, timeout=30) as response:
        return response.read()


def verify_hosted_sdk(config_path, version, fetch=fetch_bytes):
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', version):
        raise ValueError('Invalid exact SDK version')
    name = 'openfeature_dart_client_sdk'
    metadata_url = f'https://pub.dev/api/packages/{name}/versions/{version}'
    metadata = json.loads(fetch(metadata_url))
    if metadata.get('version') != version:
        raise ValueError('Registry version mismatch')
    archive_url = metadata['archive_url']
    if archive_url != f'https://pub.dev/api/archives/{name}-{version}.tar.gz':
        raise ValueError('Unexpected registry archive URL')
    archive = fetch(archive_url)
    digest = hashlib.sha256(archive).hexdigest()
    if digest != metadata['archive_sha256']:
        raise ValueError('Registry archive hash mismatch')
    root = resolved_package(config_path, name)
    files = {}
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as tar:
        for member in tar.getmembers():
            if member.isdir():
                continue
            path = Path(member.name)
            target = (root / path).resolve()
            if not member.isfile() or not target.is_relative_to(root):
                raise ValueError('Unsafe archive member')
            relative = path.as_posix()
            if relative in files:
                raise ValueError('Duplicate archive member')
            raw = tar.extractfile(member).read()
            if not target.is_file() or target.read_bytes() != raw:
                raise ValueError(f'Resolved SDK differs from registry archive: {relative}')
            files[relative] = hashlib.sha256(raw).hexdigest()
    if 'pubspec.yaml' not in files or not any(name.startswith('lib/') for name in files):
        raise ValueError('Incomplete registry archive')
    expected_lib = {p for p in files if p.startswith('lib/')}
    actual_lib = {p.relative_to(root).as_posix() for p in (root/'lib').rglob('*') if p.is_file()}
    if expected_lib != actual_lib:
        raise ValueError('Extra or missing runtime files in resolved SDK')
    return root, {'kind':'registry-archive-equivalent', 'version':version,
        'metadata_url':metadata_url, 'archive_url':archive_url,
        'archive_sha256':digest, 'resolved_root':str(root), 'files_sha256':files,
        'all_archive_files_match':True}
