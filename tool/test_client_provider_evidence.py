import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from client_provider_evidence import summarize, verify_package_paths, receipt_passes


class EvidenceTests(unittest.TestCase):
    def output(self, skip=None, count=10, success=True):
        events = [{'type':'suite','suite':{'platform':'vm'}}]
        for number in range(1,count+1):
            events += [
                {'type':'testStart','test':{'id':number,'name':f'contract C{number:02} case'}},
                {'type':'testDone','testID':number,'result':'success','skipped':number==skip},
            ]
        events.append({'type':'done','success':success})
        return '\n'.join(json.dumps(event) for event in events)
    def test_complete_ten_scenario_run(self):
        self.assertTrue(summarize(self.output())['all_scenarios_passed'])
    def test_skips_and_incomplete_or_failed_runs_do_not_qualify(self):
        for output in (self.output(skip=6), self.output(count=9), self.output(success=False)):
            self.assertFalse(summarize(output)['all_scenarios_passed'])

    def test_package_resolution_and_exit_gate(self):
        with TemporaryDirectory(prefix='contract path ') as folder:
            root = Path(folder).resolve()
            config = root/'provider/.dart_tool/package_config.json'
            config.parent.mkdir(parents=True)
            sdk = {'name':'openfeature_dart_client_sdk',
                'rootUri':'../../packages/openfeature_dart_client_sdk'}
            contract = {'name':'openfeature_client_provider_contract',
                'rootUri':(root/'conformance/client_provider_contract').as_uri()}
            cases = [
                ([sdk, contract], True, True),
                ([sdk], True, False),
                ([contract], False, True),
                ([sdk, {**contract, 'rootUri':'../../older-harness'}], True, False),
                ([{**sdk, 'rootUri':'../../older-sdk'}, contract], False, True),
                ([sdk, {**contract, 'rootUri':'https://example.invalid/harness'}], True, False),
            ]
            for packages, sdk_ok, contract_ok in cases:
                with self.subTest(packages=packages):
                    config.write_text(json.dumps({'packages':packages}), encoding='utf-8')
                    paths = verify_package_paths(config, root)
                    self.assertEqual(paths, {'sdk_path_verified':sdk_ok,
                        'contract_path_verified':contract_ok})
                    receipt = {**summarize(self.output()), **paths}
                    self.assertEqual(receipt_passes(receipt, 'vm'), sdk_ok and contract_ok)
                    self.assertFalse(receipt_passes(receipt, 'chrome'))


if __name__ == '__main__':
    unittest.main()
