import json
import unittest
from client_provider_evidence import summarize


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


if __name__ == '__main__':
    unittest.main()
