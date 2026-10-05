import unittest
from server_conformance import evidence_rows, requirement_ids, test_results


class ReportTests(unittest.TestCase):
    def test_only_rationale_and_not_applicable_use_rationale_statuses(self):
        for disposition in ('rationale', 'not_applicable'):
            for review, expected in (('pending', 'rationale_pending_review'),
                                     ('approved', 'rationale_approved')):
                with self.subTest(disposition=disposition, review=review):
                    row = evidence_rows({'requirements': [{'id': '1',
                        'disposition': disposition, 'review': review}]}, [])[0]
                    self.assertEqual(row['evidence_status'], expected)

    def test_deviation_remains_a_gap_even_when_review_is_approved(self):
        for review in ('pending', 'approved'):
            with self.subTest(review=review):
                row = evidence_rows({'requirements': [{'id': '1',
                    'disposition': 'deviation', 'review': review}]}, [])[0]
                self.assertEqual(row['evidence_status'], 'evidence_gap')

    def test_unknown_dispositions_are_rejected_even_when_approved(self):
        for disposition in ('typo', 'gap', 'api_shape'):
            with self.subTest(disposition=disposition):
                with self.assertRaisesRegex(ValueError, 'Unknown requirement disposition'):
                    evidence_rows({'requirements': [{'id': '1',
                        'disposition': disposition, 'review': 'approved'}]}, [])

    def test_successful_evidence_matching_is_unchanged(self):
        manifest = {'requirements': [{'id': '1', 'disposition': 'evidence',
            'tests': [{'file': 'contract.dart', 'name_pattern': '^passes$'}]}]}
        rows = evidence_rows(manifest, [
            {'file': '/test/contract.dart', 'name': 'passes', 'result': 'success'},
            {'file': '/test/other.dart', 'name': 'passes', 'result': 'failure'},
        ])
        self.assertEqual(rows[0]['evidence_status'], 'passing')
        self.assertEqual(len(rows[0]['executed_tests']), 1)

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
