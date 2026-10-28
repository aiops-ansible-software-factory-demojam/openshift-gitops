"""Check real committed trees before the PR helper can push or publish them."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'cluster/omnigent/image/demo-goldenpath.py'
SCOPE = {'__file__': str(SOURCE), '__name__': 'portable_source_fixture'}
exec(compile(SOURCE.read_text().split('parser = argparse.ArgumentParser')[0], str(SOURCE), 'exec'), SCOPE)


class PortableSourceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / 'checkout'
        self.root.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.test')
        self.git('config', 'core.hooksPath', '/dev/null')
        (self.root / 'README.md').write_text('Reviewed source\n')
        (self.root / '.gitignore').write_text('/collections/\n')
        self.commit()
        self.git('update-ref', 'refs/remotes/origin/main', self.git('rev-parse', 'HEAD'))

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, text=True).strip()

    def commit(self):
        self.git('add', '--all')
        self.git('commit', '-qm', 'fixture source')

    def check(self):
        head = self.git('rev-parse', 'HEAD')
        SCOPE['check_portable_source'](self.root)
        self.assertEqual(self.git('rev-parse', 'HEAD'), head)

    def test_source_and_internal_relative_link_are_allowed(self):
        (self.root / 'manual.md').symlink_to('README.md')
        self.commit()
        self.check()

    def test_ignored_generated_workspace_does_not_enter_source(self):
        generated = self.root / 'collections/ansible_collections/demo/example'
        generated.mkdir(parents=True)
        (generated / 'README.md').symlink_to(self.root / 'README.md')
        self.assertEqual(self.git('status', '--porcelain'), '')
        self.check()

    def test_absolute_and_relative_escape_links_are_rejected(self):
        for target in ['/outside/checkout', '../outside-checkout']:
            with self.subTest(target=target):
                link = self.root / 'nonportable'
                if link.is_symlink():
                    link.unlink()
                link.symlink_to(target)
                self.commit()
                with self.assertRaisesRegex(RuntimeError, 'nonportable symlink'):
                    self.check()

    def test_committed_cache_is_rejected_before_push_or_api_requests(self):
        generated = self.root / 'collections/install-state.json'
        generated.parent.mkdir()
        generated.write_text('{}')
        self.git('add', '-f', 'collections/install-state.json')
        self.git('commit', '-qm', 'accidental generated cache')
        self.git('checkout', '-qb', 'feature/issue-1')
        self.git('remote', 'add', 'origin', 'https://forgejo.fixture/demo-owner/ansible-collection-demo.webapp.git')
        body = Path(self.directory.name) / 'body.txt'
        body.write_text('Reviewed fix. Closes #1\n')
        original_git = SCOPE['git']
        def local_only_git(cwd, *args, **kwargs):
            self.assertNotEqual(args[0], 'push', 'Invalid source must never be pushed')
            return original_git(cwd, *args, **kwargs)
        with patch.dict(SCOPE, {'forgejo': 'https://forgejo.fixture',
                               'repository': 'demo-owner/ansible-collection-demo.webapp', 'git': local_only_git}), \
                patch.dict(os.environ, {'FORGEJO_TOKEN': 'fixture-token'}), \
                patch.object(Path, 'cwd', return_value=self.root), \
                patch.dict(SCOPE, {'request': lambda *a, **kw: self.fail('Invalid source must never reach the API')}):
            with self.assertRaisesRegex(RuntimeError, 'generated collection cache'):
                SCOPE['open_pr'](1, body)


if __name__ == '__main__':
    unittest.main()
