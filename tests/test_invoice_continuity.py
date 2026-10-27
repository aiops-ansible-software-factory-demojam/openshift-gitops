"""Exercise incident PR binding, duplicate delivery and orchestration boundaries."""
import copy
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import os
import json
import subprocess
from pathlib import Path
import unittest
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[1]
with patch.dict(os.environ, BACKSTAGE_URL='http://backstage.fixture'):
    spec = importlib.util.spec_from_file_location('invoice_gate', ROOT / 'cluster/automation-orchestrator/feature-gate.py')
    gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gate)


class InvoicePRTests(unittest.TestCase):
    def setUp(self):
        self.pr = {'number': 2, 'state': 'open', 'draft': False, 'merged': False, 'html_url': 'https://forgejo.fixture/pulls/2',
                   'head': {'ref': 'feature/issue-1', 'sha': 'a' * 40, 'repo': {'full_name': gate.INVOICE_REPOSITORY}},
                   'base': {'ref': 'main', 'repo': {'full_name': gate.INVOICE_REPOSITORY}}}
        self.env = patch.dict(os.environ, BACKSTAGE_TOKEN='fixture')
        self.env.start()
        self.addCleanup(self.env.stop)

    def read(self, **kwargs):
        def api(path, **unused):
            if '/commits?' in path:
                return [{'sha': 'a' * 40}]
            if '/pulls?' in path:
                return [self.pr]
            return self.pr
        with patch.object(gate, 'backstage', side_effect=api):
            return gate.invoice_pr(1, **kwargs)

    def test_no_pr_is_a_wait_state(self):
        with patch.object(gate, 'backstage', return_value=[]):
            self.assertFalse(gate.invoice_pr(1)['ready'])

    def test_exact_branch_selects_candidate_without_trusting_model_text(self):
        result = self.read()
        self.assertEqual(result['head_sha'], 'a' * 40)
        self.assertEqual(result['number'], 2)

    def test_draft_is_not_ready(self):
        self.pr['draft'] = True
        self.assertFalse(self.read()['ready'])

    def test_changed_head_stops_review_wait(self):
        with self.assertRaisesRegex(ValueError, 'head changed'):
            self.read(pr_number=2, head_sha='b' * 40, require_merged=True)

    def test_closed_without_merge_stops(self):
        self.pr['state'] = 'closed'
        with self.assertRaisesRegex(ValueError, 'closed without'):
            self.read()

    def test_cross_repository_pr_is_rejected(self):
        self.pr['head']['repo']['full_name'] = 'untrusted/fork'
        with self.assertRaisesRegex(ValueError, 'expected incident'):
            self.read(pr_number=2)

    def test_multiple_matching_prs_fail_closed(self):
        with patch.object(gate, 'backstage', return_value=[self.pr, copy.deepcopy(self.pr)]):
            with self.assertRaisesRegex(ValueError, 'Multiple'):
                gate.invoice_pr(1)

    def test_human_merge_must_contain_the_tested_commit(self):
        self.pr.update(merged=True, state='closed')
        self.assertTrue(self.read(pr_number=2, head_sha='a' * 40, require_merged=True)['merged'])
        with patch.object(gate, 'backstage', side_effect=[self.pr, []]):
            with self.assertRaisesRegex(ValueError, 'not contained'):
                gate.invoice_pr(1, 2, 'a' * 40, True)

    def test_merged_pr_cannot_start_another_deployment(self):
        self.pr.update(merged=True, state='closed')
        with self.assertRaisesRegex(ValueError, 'already merged'):
            self.read()

    def test_existing_invoice_branch_does_not_start_another_author(self):
        with patch.object(gate, 'backstage', side_effect=[{'state':'open'}, {'name':'feature/issue-1'}, {'name':'feature/issue-1'}]):
            self.assertFalse(gate.prepare(1, gate.INVOICE_REPOSITORY)['author_required'])

    def test_concurrent_opening_deliveries_claim_only_one_author(self):
        state = {'branch':False, 'tasks':0}
        def api(path, method='GET', *args, **unused):
            if '/issues/' in path:return {'state':'open'}
            if '/branches/' in path:return {'name':'feature/issue-1'} if state['branch'] else None
            if method=='POST':
                state['tasks']+=1
                state['branch']=True
                return {'id':'fixture'}
            return {'status':'completed'}
        with patch.object(gate,'backstage',side_effect=api), ThreadPoolExecutor(max_workers=2) as workers:
            results=list(workers.map(lambda _:gate.prepare(1,gate.INVOICE_REPOSITORY),range(2)))
        self.assertEqual(sorted(r['author_required'] for r in results),[False,True])
        self.assertEqual(state['tasks'],1)


class WorkflowBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.workflow = yaml.safe_load((ROOT / 'cluster/automation-orchestrator/workflows/invoice-security-remediation.yaml').read_text())
        self.nodes = {n['id']: n for n in self.workflow['nodes']}
        self.edges = self.workflow['edges']

    def test_runtime_binding_authenticates_jobs_and_workflow_without_touching_http_credentials(self):
        result=subprocess.run(['bash','-c','source bootstrap/bootstrap.sh; demo_ao_bind_aap fixture-credential fixture-integration'],
            cwd=ROOT,input=json.dumps(self.workflow),text=True,capture_output=True,check=True)
        bound=json.loads(result.stdout)
        for node in bound['nodes']:
            if node['type'] in ['aap_job_template','aap_workflow_job_template']:
                self.assertEqual(node['parameters']['credential_id'],'fixture-credential')
                self.assertEqual(node['parameters']['integration_id'],'fixture-integration')
            else:
                self.assertNotIn('credential_id',node['parameters'])

    def test_existing_eda_trigger_is_preserved(self):
        trigger = self.workflow['triggers'][0]
        self.assertEqual(trigger['type'], 'eda_trigger')
        self.assertEqual(trigger['parameters']['webhook_path'], 'invoice-security-remediation')
        self.assertEqual(len(self.workflow['triggers']), 1)

    def test_approval_remains_in_native_aap_workflow(self):
        self.assertEqual(self.nodes['approve_and_deploy']['type'], 'aap_workflow_job_template')
        chain = ['publish_validation','wait_merge','configure_release','approve_and_deploy','verify_deployment','verify_release','close_incident']
        for first, second in zip(chain, chain[1:]):
            self.assertTrue(any(e['from']==first and e['to']==second for e in self.edges))
        self.assertEqual(self.nodes['approve_and_deploy']['settings']['retry_policy']['max_retries'], 0)
        self.assertFalse(any(n['type']=='script' for n in self.nodes.values()))

    def test_source_identity_and_failed_validation_cannot_be_skipped(self):
        self.assertTrue(self.nodes['validate_invoice']['settings']['continue_on_failure'])
        self.assertEqual(self.nodes['publish_validation']['parameters']['job_template_name'], 'invoice_validation_status')
        self.assertEqual(self.nodes['verify_release']['parameters']['extra_vars']['invoice_expected_source_revision'], '${read_candidate.body.head_sha}')
        duplicate_edges = [e for e in self.edges if e['from']=='owns_incident']
        self.assertEqual([e['from_port'] for e in duplicate_edges], ['true'])


if __name__ == '__main__':
    unittest.main()
