import unittest
from client_conformance import evidence_rows, requirement_ids, test_results


class ReportTests(unittest.TestCase):
    def test_unknown_disposition_is_rejected(self):
        with self.assertRaises(ValueError):
            evidence_rows({'requirements':[{'id':'1','disposition':'typo'}]}, [])

    def test_compile_evidence_requires_all_expected_checks(self):
        manifest = {'requirements':[{'id':'3.3.2.1','disposition':'api_shape',
            'checks':['positive','negative']}]}
        checks = [{'name':'positive','passed':True}]
        self.assertEqual(evidence_rows(manifest, [], checks)[0]['evidence_status'],'missing')
        checks.append({'name':'negative','passed':False})
        self.assertEqual(evidence_rows(manifest, [], checks)[0]['evidence_status'],'not_passing')
        checks[-1]['passed'] = True
        self.assertEqual(evidence_rows(manifest, [], checks)[0]['evidence_status'],'passing')

    def test_explicit_gap_cannot_be_mislabeled_as_passing_evidence(self):
        rows = evidence_rows({'requirements':[{'id':'4.3.1', 'disposition':'gap',
            'review':'approved', 'rationale':'Incomplete stage contract'}]}, [])
        self.assertEqual(rows[0]['evidence_status'], 'evidence_gap')

    def test_inventory_includes_normative_tracking_condition(self):
        text = '#### Requirement 1.1.1\n> **SHOULD** test\n#### Condition 2.7.1\n> **MAY** track\n#### Condition 3.2.2\n> static\n'
        self.assertEqual(requirement_ids(text), {'1.1.1', '2.7.1'})

    def test_missing_failed_and_skipped_tests_never_become_passing_evidence(self):
        manifest = {'requirements': [{'id':'1.1.1','disposition':'evidence','tests':[{'file':'contract.dart','name_pattern':'contract'}]}]}
        for outcome in ('failure','error','skipped','unfinished'):
            tests = [{'file':'/test/contract.dart','name':'contract','result':outcome}]
            self.assertEqual(evidence_rows(manifest, tests)[0]['evidence_status'], 'not_passing')
        self.assertEqual(evidence_rows(manifest, [])[0]['evidence_status'], 'missing')

    def test_each_selector_must_have_executed_tests(self):
        manifest = {'requirements': [{'id':'1','disposition':'evidence','tests':[
            {'file':'contract.dart','name_pattern':'passes'}, {'file':'contract.dart','name_pattern':'missing'}]}]}
        rows = evidence_rows(manifest, [{'file':'/test/contract.dart','name':'passes','result':'success'}])
        self.assertEqual(rows[0]['evidence_status'], 'missing')

    def test_json_report_tracks_skips_and_incomplete_runs(self):
        output = '\n'.join([
            '{"type":"suite","suite":{"id":0,"path":"test/contract.dart"}}',
            '{"type":"testStart","test":{"id":1,"suiteID":0,"name":"case"}}',
            '{"type":"testDone","testID":1,"result":"success","skipped":true,"hidden":false}',
        ])
        tests, completed = test_results(output)
        self.assertFalse(completed)
        self.assertEqual(tests[0]['result'], 'skipped')


if __name__ == '__main__':
    unittest.main()
