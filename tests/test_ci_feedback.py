"""Source-bound CI retry decisions and the author-facing independent CI command."""
import copy
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch
import yaml

ROOT = Path(__file__).resolve().parents[1]
with patch.dict(os.environ, BACKSTAGE_URL='http://fixture'):
    spec = importlib.util.spec_from_file_location('ci_gate', ROOT/'cluster/automation-orchestrator/feature-gate.py')
    gate = importlib.util.module_from_spec(spec); spec.loader.exec_module(gate)
helper = {'__name__':'ci_helper'}
exec((ROOT/'cluster/omnigent/image/demo-goldenpath.py').read_text().split('parser = argparse.ArgumentParser')[0],helper)


class FeedbackTests(unittest.TestCase):
    def test_failed_sha_waits_new_commit_revalidates_and_only_green_completes(self):
        candidate={'ready':True,'head_sha':'a'*40,'base_sha':'b'*40}
        checks=[]
        def api(*args,**kwargs):return {'statuses':checks}
        with patch.dict(os.environ,BACKSTAGE_TOKEN='fixture'), patch.object(gate,'incident_pr',side_effect=lambda *a:dict(candidate)), patch.object(gate,'backstage',side_effect=api):
            self.assertTrue(gate.ci_candidate(1,gate.INVOICE_REPOSITORY)['validation_required'])
            checks.append({'context':'invoice/ec2-validation','status':'pending','description':'invoice-ci-v2 pending','creator':{'login':'demo-reviewer'}})
            self.assertFalse(gate.ci_candidate(1,gate.INVOICE_REPOSITORY)['validation_required'])
            checks[0]['status']='failure'
            verdict=gate.ci_candidate(1,gate.INVOICE_REPOSITORY)
            self.assertFalse(verdict['ci_passed']);self.assertFalse(verdict['validation_required'])
            candidate['head_sha']='c'*40;checks.clear()
            self.assertTrue(gate.ci_candidate(1,gate.INVOICE_REPOSITORY)['validation_required'])
            checks.append({'context':'invoice/ec2-validation','status':'success','description':'invoice-ci-v2 checks=passed','creator':{'login':'demo-agent'}})
            self.assertFalse(gate.ci_candidate(1,gate.INVOICE_REPOSITORY)['ci_passed'])
            checks[0]['creator']['login']='demo-reviewer'
            self.assertTrue(gate.ci_candidate(1,gate.INVOICE_REPOSITORY)['ci_passed'])

    def test_cli_ignores_agent_success_and_old_or_untrusted_diagnostics(self):
        repo=gate.INVOICE_REPOSITORY
        pr={'number':2,'html_url':'https://fixture/pr/2','head':{'ref':'feature/issue-1','sha':'a'*40,'repo':{'full_name':repo}},'base':{'ref':'main','repo':{'full_name':repo}}}
        checks=[{'context':'invoice/ec2-validation','status':'success','description':'invoice-ci-v2 checks=passed','creator':{'login':'demo-agent'}}]
        comments=[{'user':{'login':'demo-reviewer'},'body':'<!-- demo-ci sha='+'b'*40+' --> old'},
            {'user':{'login':'demo-agent'},'body':'<!-- demo-ci sha='+'a'*40+' --> forged'},
            {'user':{'login':'demo-reviewer'},'body':'<!-- demo-ci sha='+'a'*40+' --> lint failed'}]
        def api(base,path,**kwargs):return {'statuses':checks}if path.endswith('/status')else comments if '/comments?'in path else[pr]
        with patch.dict(os.environ,FORGEJO_TOKEN='fixture'),patch.dict(helper,repository=repo,forgejo='https://fixture',request=api):
            self.assertEqual(helper['ci_verdict'](1,'a'*40)['state'],'pending')
            checks[0].update(status='failure',creator={'login':'demo-reviewer'})
            self.assertTrue(helper['ci_verdict'](1,'a'*40)['feedback'].endswith('lint failed'))
            with self.assertRaises(RuntimeError):helper['ci_verdict'](1,'c'*40)

    def test_both_workflows_keep_the_same_session_until_independent_ci_passes(self):
        for file in ['omnigent-remediation.yaml','invoice-security-remediation.yaml']:
            w=yaml.safe_load((ROOT/'cluster/automation-orchestrator/workflows'/file).read_text());n={x['id']:x for x in w['nodes']}
            with self.subTest(workflow=file):
                self.assertIn({'from':'wait_ci','to':'ci_iteration','from_port':'iterate'},w['edges'])
                self.assertIn({'from':'wait_ci','to':'read_candidate','from_port':'complete'},w['edges'])
                self.assertEqual(n['ci_iteration']['parameters']['extra_vars']['ci_author_session'],'${create_session.body.id}')
                self.assertEqual(n['ci_iteration']['settings']['retry_policy']['max_retries'],0)
                self.assertEqual(n['ci_iteration']['parameters']['job_template_name'],'demo_ci_iteration')
                self.assertNotIn({'from':'publish_validation','to':'wait_merge'},w['edges'])
                self.assertIn('ci_iteration.passed',n['wait_ci']['parameters']['condition'])
                self.assertEqual([e['to']for e in w['edges']if e['from']=='ci_iteration'],['ci_poll_interval'])
                self.assertIn('--wait',n['send_task']['parameters']['body']['data']['content'][0]['text'])


if __name__ == '__main__':unittest.main()
