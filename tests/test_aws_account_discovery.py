"""Exercise bootstrap account discovery and the recorded deployment boundary."""
import json
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'bootstrap/bootstrap.sh').read_text().split('action = sys.argv[1]', 1)[1]
SOURCE = 'action = sys.argv[1]' + SOURCE.split("deployment = state['deployment_id']", 1)[0]


class AccountDiscoveryTests(unittest.TestCase):
    def discover(self, recorded=None, local=False):
        with tempfile.TemporaryDirectory() as tmp:
            if recorded and local:
                receipt = Path(tmp) / '.rendered/aws-state/current-cluster/state.json'
                receipt.parent.mkdir(parents=True)
                receipt.write_text(json.dumps(recorded))
            config = {'data': {'aws.json': json.dumps(recorded)}} if recorded and not local else None
            run = Mock(side_effect=[
                SimpleNamespace(stdout=json.dumps({'metadata': {'uid': 'current-cluster'}})),
                SimpleNamespace(stdout=json.dumps(config) if config else ''),
            ])
            session = Mock()
            session.client.return_value.get_caller_identity.return_value = {'Account': '222222222222'}
            namespace = dict(
                sys=SimpleNamespace(argv=['bootstrap', 'preflight']),
                os=SimpleNamespace(environ={
                    'AWS_DEMO_REGION': 'us-east-2', 'AWS_BOOTSTRAP_ACCESS_KEY_ID': 'fixture',
                    'AWS_BOOTSTRAP_SECRET_ACCESS_KEY': 'fixture', 'AWS_DEMO_ACCOUNT_ID': '111111111111',
                    'DEMO_REPO_ROOT': tmp,
                }),
                boto3=SimpleNamespace(Session=Mock(return_value=session)), Config=Mock(),
                subprocess=SimpleNamespace(run=run), json=json, Path=Path, secrets=secrets,
            )
            exec(compile(SOURCE, 'bootstrap AWS discovery', 'exec'), namespace)
            self.assertEqual(run.call_count, 2, 'Discovery must not mutate cluster resources')
            return namespace['state']

    def test_new_cluster_ignores_stale_account_input(self):
        state = self.discover()
        self.assertEqual(state['account_id'], '222222222222')
        self.assertEqual(state['cluster_uid'], 'current-cluster')

    def test_matching_recorded_deployment_can_continue(self):
        recorded = dict(account_id='222222222222', region='us-east-2', cluster_uid='current-cluster')
        for local in (False, True):
            with self.subTest(local=local):
                self.assertEqual(self.discover(recorded, local), recorded)

    def test_existing_deployment_cannot_change_account_region_or_cluster(self):
        for local in (False, True):
            for field, value in [('account_id', '111111111111'), ('region', 'us-west-2'), ('cluster_uid', 'other-cluster')]:
                with self.subTest(local=local, field=field):
                    recorded = dict(account_id='222222222222', region='us-east-2', cluster_uid='current-cluster')
                    recorded[field] = value
                    with self.assertRaisesRegex(AssertionError, 'refusing to rebind'):
                        self.discover(recorded, local)


if __name__ == '__main__':
    unittest.main()
