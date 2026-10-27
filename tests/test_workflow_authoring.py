"""Keep generated workflows editable and publishable in the AO builder."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / 'cluster/automation-orchestrator/workflows'


class WorkflowAuthoringTests(unittest.TestCase):
    def test_invoice_pins_a_candidate_after_polling_before_validation(self):
        workflow = yaml.safe_load((WORKFLOWS / 'invoice-security-remediation.yaml').read_text())
        nodes = {node['id']: node for node in workflow['nodes']}
        self.assertIn({'from': 'wait_ci', 'to': 'read_candidate'}, workflow['edges'])
        self.assertEqual(nodes['wait_ci']['parameters']['job_template_name'], 'demo_ci_watch')
        for node in nodes.values():
            if node['type'] != 'loop':
                # Poll body outputs are not upstream in the editor's outer graph.
                self.assertNotRegex(json.dumps(node), r'\$\{(?:read_pr|read_merge)\.')
        for node_id in ['wait_merge',
                        'configure_release', 'verify_release', 'verify_deployment']:
            self.assertIn('${read_candidate.body.head_sha}', json.dumps(nodes[node_id]['parameters']))

    def test_trigger_references_are_declared_for_editor_validation(self):
        for path in WORKFLOWS.glob('*.yaml'):
            definition = yaml.safe_load(path.read_text())
            referenced = set(re.findall(r'\$\{trigger\.([A-Za-z_][A-Za-z_0-9]*)', json.dumps(definition['nodes'])))
            for trigger in definition['triggers']:
                with self.subTest(workflow=definition['name'], trigger=trigger['id']):
                    schema = trigger['parameters'].get('input_schema', {})
                    fields = set(schema.get('properties', {}))
                    self.assertLessEqual(referenced, fields)
                    self.assertLessEqual(set(schema.get('required', [])), fields)

    def test_session_layout_preserves_runtime_users_credentials_and_chain(self):
        layouts = json.loads((WORKFLOWS / 'session-sharing-layouts.json').read_text())
        with tempfile.TemporaryDirectory() as scratch:
            users = Path(scratch) / 'users.json'
            users.write_text(json.dumps({'users': [
                {'username': 'first', 'email': 'first@example.test'},
                {'username': 'disabled', 'email': 'disabled@example.test', 'enabled': False},
                {'username': 'second', 'email': 'second@example.test'},
            ]}))
            for filename in ['omnigent-remediation.yaml', 'invoice-security-remediation.yaml']:
                with self.subTest(workflow=filename):
                    result = subprocess.run([
                        'bash', '-c', 'source bootstrap/bootstrap.sh; demo_ao_workflow_definition "$1" fixture-credential fixture-agent',
                        'workflow-test', str(WORKFLOWS / filename),
                    ], cwd=ROOT, env={**os.environ, 'DEMO_USERS_FILE': str(users)},
                        text=True, capture_output=True, check=True)
                    workflow = json.loads(result.stdout)
                    nodes = {node['id']: node for node in workflow['nodes']}
                    self.assertEqual(nodes['share_session_0']['position'], layouts[workflow['name']]['share_session_0'])
                    self.assertEqual(nodes['share_session_0']['parameters']['body']['user_id'], 'first@example.test')
                    self.assertEqual(nodes['share_session_1']['parameters']['body']['user_id'], 'second@example.test')
                    self.assertNotIn('share_session_2', nodes)
                    self.assertEqual(nodes['authenticate_omnigent']['parameters']['credential_id'], 'fixture-credential')
                    self.assertEqual(nodes['create_session']['parameters']['body']['agent_id'], 'fixture-agent')
                    chain = ['create_session', 'share_session_0', 'share_session_1', 'send_task']
                    for first, second in zip(chain, chain[1:]):
                        self.assertIn({'from': first, 'to': second}, workflow['edges'])


if __name__ == '__main__':
    unittest.main()
