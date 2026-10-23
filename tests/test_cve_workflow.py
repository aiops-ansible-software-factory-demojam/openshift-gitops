"""Check graph reachability: only an approved fix can create an authoring issue."""
from pathlib import Path
import unittest
import yaml
ROOT = Path(__file__).resolve().parents[1]

class CVEWorkflowTests(unittest.TestCase):
    def test_all_response_paths_are_explicit_and_preserve_trigger_and_agent(self):
        w = yaml.safe_load((ROOT / 'cluster/automation-orchestrator/workflows/invoice-security-detect.yaml').read_text())
        nodes = {n['id']: n for n in w['nodes']}
        self.assertEqual(w['triggers'][0]['type'], 'manual_trigger')
        edges = {(e['from'], e.get('from_port'), e['to']) for e in w['edges']}
        self.assertIn(('has_fix', 'true', 'create_issue'), edges)
        self.assertIn(('has_fix', 'false', 'needs_containment'), edges)
        self.assertIn(('needs_containment', 'true', 'record_response'), edges)
        self.assertIn(('record_response', None, 'contain_application'), edges)
        self.assertIn(('manual_review', 'true', 'escalate_review'), edges)
        self.assertIn(('manual_review', 'false', 'defer_review'), edges)
        self.assertEqual(nodes['contain_application']['parameters']['workflow_job_template_name'], 'invoice_contain')
        self.assertEqual(nodes['route_cve']['parameters']['extra_vars']['invoice_assessment_job_id'], '${check_invoice.job_id}')
        remediation = yaml.safe_load((ROOT / 'cluster/automation-orchestrator/workflows/invoice-security-remediation.yaml').read_text())
        self.assertEqual(remediation['triggers'][0]['parameters']['webhook_path'], 'invoice-security-remediation')
        self.assertTrue(any(n['id'] == 'create_session' for n in remediation['nodes']))
