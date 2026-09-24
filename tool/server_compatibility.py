"""Run one unchanged legacy consumer against published 0.0.25 and this checkout."""
from pathlib import Path
import argparse
import json
import shutil
import subprocess
import tempfile


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='build/server-conformance')
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = Path(options.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    dart = shutil.which('dart')
    fixture = (root/'test/fixtures/server_legacy_consumer.dart.txt').read_text(encoding='utf-8')
    records = []
    for name in ('published-0.0.25', 'candidate'):
        with tempfile.TemporaryDirectory(prefix='openfeature-legacy-') as directory:
            cwd = Path(directory)
            dependency = "  openfeature_dart_server_sdk: 0.0.25\n" if name.startswith('published') else (
                "  openfeature_dart_server_sdk:\n    path: " + (root/'packages/openfeature_dart_server_sdk').as_posix() + '\n')
            (cwd/'pubspec.yaml').write_text('name: legacy_consumer_fixture\npublish_to: none\nenvironment:\n  sdk: ^3.12.2\ndependencies:\n'+dependency)
            (cwd/'consumer.dart').write_text(fixture)
            commands = [['pub','get'], ['analyze','--fatal-infos'], ['run','consumer.dart']]
            for args in commands:
                result = subprocess.run([dart, *args], cwd=cwd, encoding='utf-8', stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                log = f"compat-{name}-{'-'.join(args[:2])}.log"
                (out/log).write_text(result.stdout, encoding='utf-8')
                records.append({'fixture': name, 'command':args, 'exit_code':result.returncode, 'log':log})
                if result.returncode:
                    (out/'compatibility.json').write_text(json.dumps(records, indent=2))
                    print(result.stdout)
                    return result.returncode
            deps = json.loads(subprocess.check_output([dart,'pub','deps','--json'], cwd=cwd, encoding='utf-8'))
            forbidden = [p['name'] for p in deps['packages'] if p['name'] in ('flutter','flutter_test','sky_engine')]
            if forbidden:
                raise RuntimeError(f'Unexpected Flutter dependencies: {forbidden}')
            (out/f'compat-{name}-dependencies.json').write_text(json.dumps(deps, indent=2))
    (out/'compatibility.json').write_text(json.dumps(records, indent=2))
    print('Published 0.0.25 and candidate: identical fixture analysis/runtime pass; no Flutter dependencies.')
    return 0


if __name__ == '__main__':
    raise SystemExit(run())
