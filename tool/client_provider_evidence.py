"""Run the shared client contract and record exact provider/SDK identities."""
from pathlib import Path
import argparse
import json
import re
import shutil
import subprocess
from urllib.parse import urljoin, urlparse, unquote

CONTRACT_VERSION = '2'
SCENARIOS = {f'C{i:02}' for i in range(1, 14)}


def verify_package_paths(config_path, root):
    """Verify the SDK and harness actually loaded by the provider's tests."""
    config = json.loads(config_path.read_text(encoding='utf-8'))

    def resolves_to(name, expected):
        package = next((p for p in config['packages'] if p['name'] == name), None)
        if package is None:
            return False
        uri = urlparse(urljoin(config_path.as_uri(), package['rootUri']))
        if uri.scheme != 'file' or uri.netloc not in ('', 'localhost'):
            return False
        path_text = unquote(uri.path)
        if re.match(r'^/[A-Za-z]:/', path_text):
            path_text = path_text[1:]
        return Path(path_text).resolve() == expected.resolve()

    return {
        'sdk_path_verified': resolves_to('openfeature_dart_client_sdk',
            root/'packages/openfeature_dart_client_sdk'),
        'contract_path_verified': resolves_to('openfeature_client_provider_contract',
            root/'conformance/client_provider_contract'),
    }


def receipt_passes(receipt, platform):
    return (receipt['all_scenarios_passed'] and receipt['sdk_path_verified']
        and receipt['contract_path_verified'] and receipt['platforms'] == [platform])


def summarize(output):
    tests, platforms, successful = {}, set(), False
    for line in output.splitlines():
        event = json.loads(line)
        if event['type'] == 'suite':
            platforms.add(event['suite']['platform'])
        elif event['type'] == 'testStart':
            match = re.search(r'\b(C\d{2})\b', event['test']['name'])
            if match:
                tests[event['test']['id']] = {'scenario':match[1], 'name':event['test']['name'], 'result':'unfinished'}
        elif event['type'] == 'testDone' and event['testID'] in tests:
            tests[event['testID']]['result'] = 'skipped' if event['skipped'] else event['result']
        elif event['type'] == 'done':
            successful = event['success']
    scenarios = list(tests.values())
    passed = (successful and len(scenarios) == len(SCENARIOS) and {t['scenario'] for t in scenarios} == SCENARIOS and all(t['result'] == 'success' for t in scenarios))
    return {'scenarios':scenarios, 'platforms':sorted(platforms), 'all_scenarios_passed':passed}


def identity(path):
    def git(*args):
        return subprocess.check_output(['git','-C',str(path),*args], encoding='utf-8').strip()
    return {'commit':git('rev-parse','HEAD'), 'tree':git('rev-parse','HEAD^{tree}'),
        'dirty':bool(git('status','--porcelain','--untracked-files=normal'))}


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--classification', required=True, choices=['reference','external'])
    parser.add_argument('--canonical-repository', required=True)
    parser.add_argument('--provider-repo', required=True)
    parser.add_argument('--working-directory', required=True)
    parser.add_argument('--test-target', required=True)
    parser.add_argument('--platform', required=True, choices=['vm','chrome'])
    parser.add_argument('--output', required=True)
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    out = Path(options.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    dart = shutil.which('dart')
    command = [dart,'test','--reporter=json','--platform',options.platform, options.test_target]
    result = subprocess.run(command, cwd=options.working_directory, encoding='utf-8', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (out/'tests.jsonl').write_text(result.stdout, encoding='utf-8')
    (out/'stderr.log').write_text(result.stderr, encoding='utf-8')
    summary = summarize(result.stdout)
    receipt = {'contract_version':CONTRACT_VERSION, 'contract_checkout':identity(root),
        'sdk_checkout':identity(root), 'provider_checkout':identity(options.provider_repo),
        'classification':options.classification, 'canonical_repository':options.canonical_repository,
        'dart':subprocess.check_output([dart,'--version'],encoding='utf-8').strip(),
        'command':command[1:], 'process_exit_code':result.returncode, **summary,
        'native_mobile_runtime_tested':False, 'independent_provider_gate_satisfied':False,
        'remaining_review':'Verify canonical provider provenance, independent ownership, vendor transport/token scenarios, declared platform evidence and maintainer acceptance. SDK and harness package paths are checked below. A reference receipt never counts as an independent provider.'}
    deps = subprocess.run([dart,'pub','deps','--json'], cwd=options.working_directory, encoding='utf-8',stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if deps.returncode:
        raise RuntimeError(deps.stderr)
    (out/'dependencies.json').write_text(deps.stdout, encoding='utf-8')
    # Verify actual resolution, not just the SDK path claimed by a caller.
    working = Path(options.working_directory).resolve()
    configs = [parent/'.dart_tool/package_config.json' for parent in [working, *working.parents]]
    config_path = next((path for path in configs if path.exists()), None)
    if config_path is None:
        raise RuntimeError('Cannot verify package resolution')
    receipt.update(verify_package_paths(config_path, root))
    receipt['all_scenarios_passed'] = receipt['all_scenarios_passed'] and result.returncode == 0
    (out/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({key:receipt[key] for key in ('classification','all_scenarios_passed','platforms','sdk_path_verified','contract_path_verified','independent_provider_gate_satisfied')}))
    return 0 if receipt_passes(receipt, options.platform) else 1


if __name__ == '__main__':
    raise SystemExit(run())
