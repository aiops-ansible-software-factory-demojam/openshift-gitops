"""Exercise Keycloak retries without replaying uncertain administrative writes."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class IdentityTransportTests(unittest.TestCase):
    def request(self, method, first, status=28, always=False):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'token-deadline').write_text('999999')
            (root / 'curl.conf').touch()
            script = r'''
set -euo pipefail
source "$SOURCE"
identity_scratch=$SCRATCH
identity_base=https://fixture.invalid
demo_die() { echo "$*" >&2; exit 1; }
sleep() { :; }
curl() {
  local count=0
  [[ ! -f $SCRATCH/count ]] || count=$(cat "$SCRATCH/count")
  count=$((count + 1)); echo "$count" > "$SCRATCH/count"
  if (( count == 1 )) || [[ $ALWAYS == 1 ]]; then
    printf '%s' "$FIRST"
    return "$STATUS"
  fi
  printf '{"ok":true}' > "$SCRATCH/response.json"
  printf '200 0.025'
}
demo_identity_request "$METHOD" /realms/demo '{"enabled":true}'
'''
            result = subprocess.run(['bash', '-c', script], env={**os.environ,
                'SOURCE': str(ROOT / 'bootstrap/identity.sh'), 'SCRATCH': tmp,
                'FIRST': first, 'STATUS': str(status), 'ALWAYS': str(int(always)),
                'METHOD': method}, capture_output=True, text=True)
            return result, int((root / 'count').read_text())

    def test_get_retries_interrupted_response(self):
        result, count = self.request('GET', '000 0.125')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(count, 2)
        self.assertEqual(result.stdout, '{"ok":true}')

    def test_write_retries_only_before_tcp_connection(self):
        for status in (7, 28):
            with self.subTest(status=status):
                result, count = self.request('POST', '000 0.000000', status)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(count, 2)

    def test_uncertain_write_is_not_replayed(self):
        for method in ('POST', 'PUT', 'DELETE'):
            with self.subTest(method=method):
                result, count = self.request(method, '000 0.125')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(count, 1)
                self.assertIn(method + ' /realms/demo transport failed', result.stderr)
                self.assertNotIn('enabled', result.stderr)

    def test_retries_are_bounded(self):
        result, count = self.request('GET', '000 0.000000', always=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(count, 3)

    def test_http_error_is_not_replayed(self):
        result, count = self.request('POST', '403 0.125', status=0)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(count, 1)
        self.assertIn('HTTP 403', result.stderr)


if __name__ == '__main__':
    unittest.main()
