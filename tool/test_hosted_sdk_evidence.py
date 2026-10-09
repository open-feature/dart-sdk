import hashlib
import io
import json
import tarfile
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from hosted_sdk_evidence import verify_hosted_sdk


class HostedSdkEvidenceTests(unittest.TestCase):
    def test_verified_archive_and_tampering_are_distinguished(self):
        with TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            sdk = root/'cache/openfeature_dart_client_sdk-0.0.1'
            sdk.mkdir(parents=True)
            content = {'pubspec.yaml': b'name: openfeature_dart_client_sdk\nversion: 0.0.1\n', 'lib/sdk.dart': b'const identity = 1;\n'}
            stream = io.BytesIO()
            with tarfile.open(fileobj=stream, mode='w:gz') as tar:
                for name, raw in content.items():
                    info = tarfile.TarInfo(name); info.size = len(raw)
                    tar.addfile(info, io.BytesIO(raw))
                    target = sdk/name; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(raw)
            archive = stream.getvalue()
            metadata = {'version':'0.0.1','archive_url':'https://pub.dev/api/archives/openfeature_dart_client_sdk-0.0.1.tar.gz', 'archive_sha256':hashlib.sha256(archive).hexdigest()}
            def fetch(url):
                return archive if url.endswith('.tar.gz') else json.dumps(metadata).encode()
            config = root/'package_config.json'
            config.write_text(json.dumps({'packages':[{'name':'openfeature_dart_client_sdk','rootUri':sdk.as_uri()}]}))
            actual, receipt = verify_hosted_sdk(config, '0.0.1', fetch)
            self.assertEqual(actual, sdk)
            self.assertTrue(receipt['all_archive_files_match'])
            (sdk/'lib/sdk.dart').write_text('tampered')
            with self.assertRaisesRegex(ValueError, 'differs'):
                verify_hosted_sdk(config, '0.0.1', fetch)
            (sdk/'lib/sdk.dart').write_bytes(content['lib/sdk.dart'])
            (sdk/'lib/extra.dart').write_text('unexpected runtime source')
            with self.assertRaisesRegex(ValueError, 'Extra or missing'):
                verify_hosted_sdk(config, '0.0.1', fetch)
            (sdk/'lib/extra.dart').unlink()
            metadata['archive_sha256'] = '0'*64
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                verify_hosted_sdk(config, '0.0.1', fetch)
            metadata['archive_url'] = 'https://example.invalid/archive.tar.gz'
            with self.assertRaisesRegex(ValueError, 'archive URL'):
                verify_hosted_sdk(config, '0.0.1', fetch)


if __name__ == '__main__':
    unittest.main()
