"""A Ready Pod must not start seeding before the public API accepts requests."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ForgejoStartupTests(unittest.TestCase):
    def test_route_503_is_waited_out_before_token_check_and_seeding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "scripts"
            scripts.mkdir()
            shutil.copy(ROOT / "cluster/forgejo/scripts/demo.sh", scripts / "demo.sh")
            (scripts / "seed.sh").write_text('#!/bin/sh\necho seed >> "$CALL_LOG"\n')
            (scripts / "seed.sh").chmod(0o755)
            binary = root / "bin"
            binary.mkdir()
            stub = '''#!/usr/bin/env python3
import os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
log = pathlib.Path(os.environ['CALL_LOG'])
def record(value):
    with log.open('a') as stream: stream.write(value + '\\n')
if name == 'curl':
    if args[-1].endswith('/version'):
        count = log.read_text().count('version') if log.exists() else 0
        record('version 503' if count == 0 else 'version 200')
        sys.exit(22 if count == 0 else 0)
    record('token check 401')
    print('401')
elif name == 'oc':
    if args == ['whoami', '--show-server']: print('https://cluster.example.test:6443')
    elif args == ['whoami']: print('admin')
    elif 'route' in args: print('forgejo.example.test')
    elif 'exec' in args:
        record('mint' if 'generate-access-token' in args else 'admin command')
        if 'list' in args: print('ID Username\\n1 demo-admin')
        elif 'generate-access-token' in args: print('fixture')
'''
            for name in ("curl", "oc"):
                path = binary / name
                path.write_text(stub)
                path.chmod(0o755)
            (binary / "sleep").write_text("#!/bin/sh\nexit 0\n")
            (binary / "sleep").chmod(0o755)
            state = root / "state"
            state.mkdir()
            (state / "admin-token").write_text("old fixture")
            log = root / "calls"
            env = dict(os.environ, PATH=f"{binary}:{os.environ['PATH']}",
                       FORGEJO_URL="https://forgejo.example.test",
                       DEMO_CLUSTER_SERVER="https://cluster.example.test:6443",
                       FORGEJO_STATE_DIR=str(state), CALL_LOG=str(log))
            result = subprocess.run(["bash", str(scripts / "demo.sh"), "seed"],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = log.read_text().splitlines()
            self.assertEqual(calls[:2], ["version 503", "version 200"])
            self.assertLess(calls.index("version 200"), calls.index("admin command"))
            self.assertLess(calls.index("token check 401"), calls.index("mint"))
            self.assertLess(calls.index("mint"), calls.index("seed"))
