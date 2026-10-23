"""Run the real upgrade cleanup against isolated AO response fixtures."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT = Path(__file__).resolve().parents[1]

class DispatchRetirementTests(unittest.TestCase):
    def retire(self, workflows, history=None, next_page=None, passes=True):
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp)/'fixture.json'; calls = Path(tmp)/'calls'
            fixture.write_text(json.dumps({'workflows': {'resources': workflows, 'next': next_page},
                'history': {'resources': history or []}}))
            env = dict(os.environ, RETIRE_FIXTURE=str(fixture), RETIRE_CALLS=str(calls), RETIRE_RESPONSE=str(Path(tmp)/'response'))
            command = r'''
set -euo pipefail
source bootstrap/bootstrap.sh
base_url=http://ao.fixture/api/v1
auth_header='Authorization: fixture'
ao_response=$RETIRE_RESPONSE
ao_curl() {
  printf '%s %s\n' "$1" "$2" >> "$RETIRE_CALLS"
  case "$1 $2" in
    'GET http://ao.fixture/api/v1/workflows?limit=100') jq .workflows "$RETIRE_FIXTURE" > "$ao_response"; echo 200 ;;
    GET*) jq .history "$RETIRE_FIXTURE" > "$ao_response"; echo 200 ;;
    PATCH*) echo '{"is_enabled":false}' > "$ao_response"; echo 200 ;;
    DELETE*) echo 204 ;;
    *) exit 10 ;;
  esac
}
ao_require_json() { [[ $2 == 200 ]] && jq -e 'type == "object"' "$ao_response" >/dev/null; }
ao_fail_response() { echo "$1" >&2; exit 1; }
demo_ao_retire_dispatch
'''
            result = subprocess.run(['bash','-c',command], cwd=ROOT, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode==0,passes,result.stdout+result.stderr)
            return calls.read_text().splitlines()
    def workflow(self, **changes):
        return dict({'id':'retired','name':'omnigent-dispatch','is_builtin':False,'is_enabled':True},**changes)
    def test_unused_copy_is_disabled_then_deleted_and_other_workflows_are_untouched(self):
        calls=self.retire([self.workflow(), {'id':'keep','name':'omnigent-remediation','is_builtin':False}])
        writes=[c for c in calls if c.startswith(('PATCH','DELETE'))]
        self.assertEqual(writes,['PATCH http://ao.fixture/api/v1/workflows/retired','DELETE http://ao.fixture/api/v1/workflows/retired'])
        self.assertLess(calls.index(writes[0]),next(i for i,c in enumerate(calls) if '/executions?' in c))
    def test_any_execution_history_is_retained(self):
        calls=self.retire([self.workflow()],history=[{'status':'completed'}])
        self.assertTrue(any(c.startswith('PATCH') for c in calls))
        self.assertFalse(any(c.startswith('DELETE') for c in calls))
    def test_absent_or_builtin_dispatch_is_not_modified(self):
        for workflows in [[],[self.workflow(is_builtin=True)]]:
            self.assertEqual(len(self.retire(workflows)),1)
    def test_already_retired_history_does_not_create_another_update(self):
        calls=self.retire([self.workflow(is_enabled=False)],history=[{'status':'running'}])
        self.assertFalse(any(c.startswith(('PATCH','DELETE')) for c in calls))
    def test_ambiguous_or_truncated_listing_does_not_modify_any_workflow(self):
        for workflows,next_page in [([self.workflow(),self.workflow()],None),([self.workflow()],'cursor')]:
            calls=self.retire(workflows,next_page=next_page,passes=False)
            self.assertFalse(any(c.startswith(('PATCH','DELETE')) for c in calls))
