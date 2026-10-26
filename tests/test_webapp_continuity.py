"""Verify nginx incident identity, duplicate claims and exact-merge routing."""
import copy
import base64
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch
import yaml
ROOT = Path(__file__).resolve().parents[1]
with patch.dict(os.environ, BACKSTAGE_URL='http://backstage.fixture'):
    spec = importlib.util.spec_from_file_location('web_gate', ROOT / 'cluster/automation-orchestrator/feature-gate.py')
    gate = importlib.util.module_from_spec(spec); spec.loader.exec_module(gate)

class WebPRTests(unittest.TestCase):
    def setUp(self):
        self.pr = {'number': 2, 'state': 'open', 'draft': False, 'merged': False, 'html_url': 'https://fixture/pulls/2',
            'head': {'ref': 'feature/issue-1', 'sha': 'a' * 40, 'repo': {'full_name': gate.DEFAULT_REPOSITORY}},
            'base': {'ref': 'main', 'repo': {'full_name': gate.DEFAULT_REPOSITORY}}, 'merge_base': 'b' * 40}
    def read(self, **kwargs):
        def api(path, **unused):
            self.assertIn(gate.DEFAULT_REPOSITORY, path)
            if '/contents/' in path:
                return None if path.endswith('b' * 40) else {'type': 'file', 'encoding': 'base64',
                    'content': base64.b64encode(b'- name: Test incident\n  ansible.builtin.assert:\n    that: true\n').decode()}
            if path.endswith('/status'):
                return {'statuses': [{'context': 'webapp/regression-validation', 'status': 'success',
                    'creator': {'login':'demo-reviewer'},
                    'description': 'webapp-regression-v1 base=' + 'b' * 40 + ' red=passed green=passed durable=passed'}]}
            if '/commits?' in path: return [{'sha': 'a' * 40}]
            return self.pr if '/pulls/' in path else [self.pr]
        with patch.dict(os.environ, BACKSTAGE_TOKEN='fixture'), patch.object(gate, 'backstage', side_effect=api):
            return gate.webapp_pr(1, **kwargs)
    def test_exact_web_head_and_human_merge_are_required(self):
        self.assertEqual(self.read()['head_sha'], 'a' * 40)
        self.pr.update(merged=True, state='closed')
        self.assertTrue(self.read(pr_number=2, head_sha='a' * 40, require_merged=True)['merged'])
    def test_cross_application_drift_or_closed_pr_stops(self):
        for case in ['repository', 'source', 'closed']:
            with self.subTest(case=case):
                self.setUp()
                if case == 'repository': self.pr['head']['repo']['full_name'] = gate.INVOICE_REPOSITORY
                if case == 'source': self.pr['head']['sha'] = 'b' * 40
                if case == 'closed': self.pr['state'] = 'closed'
                with self.assertRaises(ValueError): self.read(pr_number=2, head_sha='a' * 40, require_merged=True)
    def test_missing_unchanged_or_empty_regression_is_rejected(self):
        def record(text):
            return {'type':'file', 'encoding':'base64', 'content':base64.b64encode(text.encode()).decode()}
        for original, candidate in [(None,None), (None,record('')), (record('same'),record('same\n'))]:
            with self.subTest(original=original,candidate=candidate), patch.dict(os.environ,BACKSTAGE_TOKEN='fixture'):
                with patch.object(gate,'backstage',side_effect=[candidate,original]):
                    with self.assertRaises(ValueError):gate.require_webapp_regression('b'*40,'a'*40)
    def test_changed_file_does_not_replace_independent_execution_proof(self):
        self.pr.update(merged=True,state='closed')
        for check in [None, {'status':'pending'}, {'status':'success','description':'wrong base'},
                {'status':'success','description':'webapp-regression-v1 base='+'b'*40+' red=passed green=passed durable=passed',
                 'creator':{'login':'demo-agent'}}]:
            def api(path, **unused):
                if '/contents/' in path:return None if path.endswith('b'*40) else {'type':'file','encoding':'base64','content':'dGVzdA=='}
                if path.endswith('/status'):return {'statuses':[] if check is None else [dict(check,context='webapp/regression-validation')]}
                if '/commits?' in path:return [{'sha':'a'*40}]
                return self.pr
            with self.subTest(check=check), patch.dict(os.environ,BACKSTAGE_TOKEN='fixture'), patch.object(gate,'backstage',side_effect=api):
                with self.assertRaises(ValueError):gate.webapp_pr(1,pr_number=2,head_sha='a'*40,require_merged=True)
    def test_missing_pr_waits_and_ambiguous_prs_fail(self):
        with patch.dict(os.environ, BACKSTAGE_TOKEN='fixture'), patch.object(gate, 'backstage', return_value=[]):
            self.assertFalse(gate.webapp_pr(1)['ready'])
        with patch.dict(os.environ, BACKSTAGE_TOKEN='fixture'), patch.object(gate, 'backstage', return_value=[self.pr, self.pr]):
            with self.assertRaises(ValueError): gate.webapp_pr(1)
    def test_duplicate_web_deliveries_claim_one_author(self):
        state = {'branch': False, 'tasks': 0}
        def api(path, method='GET', *args, **unused):
            if '/issues/' in path: return {'state': 'open'}
            if '/branches/' in path: return {'name': 'feature/issue-1'} if state['branch'] else None
            if method == 'POST': state.update(branch=True, tasks=state['tasks']+1); return {'id': 'fixture'}
            return {'status': 'completed'}
        with patch.dict(os.environ, BACKSTAGE_TOKEN='fixture'), patch.object(gate, 'backstage', side_effect=api), ThreadPoolExecutor(max_workers=2) as workers:
            results = list(workers.map(lambda _: gate.prepare(1), range(2)))
        self.assertEqual(sorted(r['author_required'] for r in results), [False, True])
        self.assertEqual(state['tasks'], 1)

class WebWorkflowTests(unittest.TestCase):
    def test_merge_wait_and_approval_bind_one_published_head(self):
        w = yaml.safe_load((ROOT / 'cluster/automation-orchestrator/workflows/omnigent-remediation.yaml').read_text())
        n = {n['id']: n for n in w['nodes']}; edges = w['edges']
        self.assertEqual(w['triggers'][0]['parameters']['webhook_path'], 'forgejo-issue-remediation')
        self.assertIn({'from': 'owns_incident', 'to': 'authenticate_omnigent', 'from_port': 'true'}, edges)
        self.assertEqual([e['from_port'] for e in edges if e['from'] == 'owns_incident'], ['true'])
        self.assertIn({'from': 'wait_pr', 'to': 'read_candidate', 'from_port': 'complete'}, edges)
        self.assertIn({'from': 'wait_merge', 'to': 'approve_and_deploy', 'from_port': 'complete'}, edges)
        self.assertEqual(n['approve_and_deploy']['parameters']['workflow_job_template_name'], 'webapp_promote')
        self.assertEqual(n['approve_and_deploy']['parameters']['scm_branch'], '${read_candidate.body.head_sha}')
        self.assertEqual(n['read_merge']['parameters']['query_params']['head_sha'], '${read_candidate.body.head_sha}')
        self.assertTrue(n['read_merge']['parameters']['url'].endswith('/webapp/pr'))
        self.assertEqual(n['approve_and_deploy']['settings']['retry_policy']['max_retries'], 0)
        self.assertIn({'from': 'approve_and_deploy', 'to': 'verify_deployment'}, edges)
