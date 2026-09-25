"""Build candidate evidence from the pinned spec and a fresh Dart JSON test run.

This reports evidence, not certification. Pending reviews and external-provider
gates remain explicit even when all mapped tests pass.
"""
from collections import Counter
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
from client_api_shape import check_api_shape


def requirement_ids(text):
    # 2.7.1 is normatively MAY but is titled Condition in the pinned source.
    sections = re.split(r'(?m)^#{3,6} ', text)
    found = set()
    for section in sections:
        title, _, body = section.partition('\n')
        match = re.fullmatch(r'(?:Conditional )?Requirement ([\d.]+)\s*', title)
        if match:
            found.add(match[1].rstrip('.'))
        elif title.strip() == 'Condition 2.7.1' and '**MAY**' in body:
            found.add('2.7.1')
    return found


def test_results(output):
    suites, tests, done = {}, {}, False
    for line in output.splitlines():
        event = json.loads(line)
        kind = event.get('type')
        if kind == 'suite':
            suites[event['suite']['id']] = event['suite']['path'].replace('\\', '/')
        elif kind == 'testStart':
            test = event['test']
            tests[test['id']] = {'name': test['name'], 'suite': test['suiteID'], 'result': 'unfinished', 'hidden': False}
        elif kind == 'testDone' and event['testID'] in tests:
            tests[event['testID']].update(result='skipped' if event['skipped'] else event['result'], hidden=event['hidden'])
        elif kind == 'done':
            done = event['success']
    return [dict(test, file=suites.get(test['suite'], '')) for test in tests.values() if not test['hidden'] and not test['name'].startswith('loading ')], done


def evidence_rows(manifest, tests, api_checks=None):
    rows = []
    for requirement in manifest['requirements']:
        row = dict(requirement)
        if row['disposition'] == 'api_shape':
            selected = [check for check in (api_checks or []) if check['name'] in row['checks']]
            row['executed_api_checks'] = selected
            row['evidence_status'] = ('missing' if {check['name'] for check in selected} != set(row['checks']) else
                'passing' if all(check['passed'] for check in selected) else 'not_passing')
        elif row['disposition'] == 'gap':
            row['evidence_status'] = 'evidence_gap'
        elif row['disposition'] in ('not_applicable', 'rationale'):
            row['evidence_status'] = ('rationale_approved' if row.get('review') == 'approved' else 'rationale_pending_review')
        elif row['disposition'] == 'evidence':
            matched = []
            missing = []
            for selector in row['tests']:
                selected = [test for test in tests if test['file'].endswith('/' + selector['file']) and re.search(selector['name_pattern'], test['name'])]
                if not selected:
                    missing.append(selector)
                matched.extend(selected)
            row['executed_tests'] = list({(test['file'], test['name']): test for test in matched}.values())
            row['missing_selectors'] = missing
            row['evidence_status'] = ('missing' if missing or not matched else
                'passing' if all(test['result'] == 'success' for test in matched) else 'not_passing')
        else:
            raise ValueError(f"Unknown requirement disposition: {row['disposition']}")
        rows.append(row)
    return rows


def run(args=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default='build/client-conformance')
    parser.add_argument('--spec-dir', help='Offline directory containing the six pinned source files')
    parser.add_argument('--platform', choices=['vm','chrome'], default='vm')
    parser.add_argument('--require-release-ready', action='store_true')
    options = parser.parse_args(args)
    root = Path(__file__).resolve().parents[1]
    out = Path(options.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((root/'doc/conformance/client-v0.9.0.json').read_text(encoding='utf-8'))
    ids = [row['id'] for row in manifest['requirements']]
    if len(ids) != len(set(ids)):
        raise ValueError('Duplicate requirement IDs')
    spec_ids = set()
    for name, digest in manifest['source_sha256'].items():
        if options.spec_dir:
            raw = (Path(options.spec_dir)/f'{name}.md').read_bytes()
        else:
            url = f"https://raw.githubusercontent.com/open-feature/spec/{manifest['spec_commit']}/specification/sections/{name}.md"
            with urllib.request.urlopen(url, timeout=30) as response:
                raw = response.read()
        if hashlib.sha256(raw).hexdigest() != digest:
            raise ValueError(f'Pinned specification checksum mismatch: {name}')
        spec_ids.update(requirement_ids(raw.decode('utf-8')))
    if spec_ids != set(ids):
        raise ValueError(f'Incomplete specification inventory: {spec_ids.symmetric_difference(ids)}')
    sha = subprocess.check_output(['git','rev-parse','HEAD'], cwd=root, encoding='utf-8').strip()
    tree = subprocess.check_output(['git','rev-parse','HEAD^{tree}'], cwd=root, encoding='utf-8').strip()
    dirty = bool(subprocess.check_output(['git','status','--porcelain','--untracked-files=normal'], cwd=root, encoding='utf-8').strip())
    dart = shutil.which('dart')
    if dart is None:
        raise RuntimeError('Dart executable unavailable')
    version = subprocess.check_output([dart,'--version'], encoding='utf-8').strip()
    result = subprocess.run([dart,'test','--reporter=json','--platform',options.platform], cwd=root/'packages/openfeature_dart_client_sdk', encoding='utf-8', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (out/'tests.jsonl').write_text(result.stdout, encoding='utf-8')
    (out/'tests.stderr.log').write_text(result.stderr, encoding='utf-8')
    tests, completed = test_results(result.stdout)
    api_checks = check_api_shape(root/'packages/openfeature_dart_client_sdk')
    (out/'api-shape.json').write_text(json.dumps(api_checks, indent=2)+'\n', encoding='utf-8')
    rows = evidence_rows(manifest, tests, api_checks)
    broken = [row['id'] for row in rows if row['evidence_status'] in ('missing','not_passing')]
    unreviewed = [row['id'] for row in rows if row.get('review') != 'approved']
    gaps = [row['id'] for row in rows if row['disposition'] == 'gap']
    api_shape_passed = all(check['passed'] for check in api_checks)
    ready = not (gaps or broken or unreviewed or dirty or manifest['release_gates'] or result.returncode or not completed or not api_shape_passed)
    report = {'schema': 1, 'platform': options.platform, 'evidence_gaps': gaps, 'sdk_commit': sha, 'sdk_tree': tree, 'dirty_worktree': dirty,
        'pr_head': os.environ.get('PR_HEAD_SHA'), 'ci_run': os.environ.get('GITHUB_RUN_ID'),
        'dart': version, 'spec_version': manifest['spec_version'], 'spec_commit': manifest['spec_commit'],
        'spec_source_sha256': manifest['source_sha256'], 'claim': manifest['claim'],
        'tests_completed_successfully': completed and result.returncode == 0,
        'api_shape_checks': api_checks, 'api_shape_passed': api_shape_passed,
        'executed_test_count': len(tests), 'broken_evidence': broken,
        'unreviewed_requirements': unreviewed, 'release_gates': manifest['release_gates'],
        'release_ready': ready, 'disposition_counts': dict(sorted(Counter(row['disposition'] for row in rows).items())), 'requirements': rows}
    (out/'report.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    lines = ['# Client static-context v0.9 candidate evidence', '', manifest['claim'], '',
        f"SDK `{sha}`; tree `{tree}`; dirty worktree: `{dirty}`.",
        f"Specification `{manifest['spec_version']}` at `{manifest['spec_commit']}`; six checksums verified.",
        f"Dart: {version}. Tests: {len(tests)}; completed successfully: {report['tests_completed_successfully']}.",
        f"Platform: {options.platform}. Explicit evidence gaps: {len(gaps)}.",
        f"Release ready: **{ready}**. Unreviewed mappings/rationales: {len(unreviewed)}.", '',
        '| Requirement | Level | Evidence | Review |', '| --- | --- | --- | --- |']
    lines[lines.index('| Requirement | Level | Evidence | Review |'):lines.index('| Requirement | Level | Evidence | Review |')] = [
        '| Disposition | Count |', '| --- | --- |',
        *[f"| {key} | {count} |" for key, count in report['disposition_counts'].items()], '',
    ]
    lines.extend(f"| {row['id']} | {row['level']} | {row['evidence_status']} | {row['review']} |" for row in rows)
    lines.extend(['', '## Remaining release gates', ''] + [f'- {gate}' for gate in manifest['release_gates']])
    lines.extend(['', 'Passing evidence means the selected tests ran successfully; semantic completeness is a separate maintainer review. Exact test names/results, source paths, compatibility boundaries and rationale are in report.json.', ''])
    (out/'report.md').write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps({key: report[key] for key in ('sdk_commit','dirty_worktree','executed_test_count','tests_completed_successfully','broken_evidence','evidence_gaps','release_ready')}))
    return 1 if result.returncode or not completed or broken or not api_shape_passed or (options.require_release_ready and not ready) else 0


if __name__ == '__main__':
    sys.exit(run())
