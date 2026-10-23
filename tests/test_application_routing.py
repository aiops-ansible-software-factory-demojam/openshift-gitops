"""Exercise the real Developer Hub gate for independent application repositories."""
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
with patch.dict(os.environ, BACKSTAGE_URL='http://backstage.fixture'):
    spec = importlib.util.spec_from_file_location('feature_gate', ROOT / 'cluster/automation-orchestrator/feature-gate.py')
    gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gate)


class ApplicationRoutingTests(unittest.TestCase):
    def test_same_issue_number_creates_a_branch_in_each_application(self):
        branches, tasks, issue_paths = set(), [], []

        def backstage(path, method='GET', body=None, token=None, missing_ok=False):
            if '/issues/' in path:
                issue_paths.append(path)
                return {'state': 'open', 'title': 'Fixture finding', 'body': 'Evidence', 'html_url': 'https://fixture/issue'}
            if '/branches/' in path:
                return {'name': 'feature/issue-2'} if path in branches else None
            if path == '/api/scaffolder/v2/tasks' and method == 'POST':
                values = body['values']
                tasks.append(values)
                branches.add(f'/api/proxy/forgejo/repos/{values["repository"]}/branches/feature%2Fissue-2')
                return {'id': str(len(tasks))}
            if path.startswith('/api/scaffolder/v2/tasks/'):
                return {'status': 'completed'}
            self.fail(f'Unexpected Backstage request: {method} {path}')

        with patch.dict(os.environ, BACKSTAGE_TOKEN='fixture'), patch.object(gate, 'backstage', side_effect=backstage):
            for repository in sorted(gate.REPOSITORIES):
                result = gate.prepare(2, repository)
                self.assertEqual(result['repository'], repository)
                self.assertEqual(result['branch'], 'feature/issue-2')
            gate.prepare(2, 'demo-owner/ansible-collection-demo.pythonapp')
        self.assertEqual(len(tasks), 2, 'An existing branch must not create another scaffolder task')
        self.assertEqual({task['repository'] for task in tasks}, gate.REPOSITORIES)
        self.assertEqual(len(set(issue_paths)), 2)

    def test_untrusted_repository_is_rejected_before_any_backstage_request(self):
        with patch.object(gate, 'backstage') as request:
            with self.assertRaisesRegex(ValueError, 'Unsupported application repository'):
                gate.prepare(2, 'other-owner/ansible-collection-demo.pythonapp')
            request.assert_not_called()

    def test_closed_issues_and_pull_requests_cannot_prepare_contributions(self):
        for issue in ({'state': 'closed'}, {'state': 'open', 'pull_request': {'id': 2}}):
            with self.subTest(issue=issue), patch.dict(os.environ, BACKSTAGE_TOKEN='fixture'), patch.object(gate, 'backstage', return_value=issue):
                with self.assertRaisesRegex(ValueError, 'not an open collection issue'):
                    gate.prepare(2, 'demo-owner/ansible-collection-demo.pythonapp')


if __name__ == '__main__':
    unittest.main()
