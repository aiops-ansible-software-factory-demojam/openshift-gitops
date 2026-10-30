"""Reject failed committed-source checks before a candidate can be published."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'cluster/omnigent/image/demo-goldenpath.py'
SCOPE = {'__file__': str(SOURCE), '__name__': 'candidate_publication_fixture'}
exec(compile(SOURCE.read_text().split('parser = argparse.ArgumentParser')[0], str(SOURCE), 'exec'), SCOPE)


class CandidatePublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'checkout'
        self.root.mkdir()
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.test')
        (self.root / 'galaxy.yml').write_text('namespace: fixture\nname: example\nversion: 1.0.0\n')
        (self.root / 'tests').mkdir()
        (self.root / 'tests/test_fixture.py').write_text('import unittest\n')
        self.commit()
        self.git('update-ref', 'refs/remotes/origin/main', self.git('rev-parse', 'HEAD'))

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, text=True).strip()

    def commit(self):
        self.git('add', '--all')
        self.git('commit', '-qm', 'fixture')

    def task(self, condition):
        target = self.root / 'roles/example/tasks/main.yml'
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text('---\n- name: Inspect expected command outcome\n'
                          '  ansible.builtin.command:\n    argv: [example]\n'
                          '  changed_when: false\n' + condition)
        self.commit()

    def test_failed_checks_stop_before_push_or_api(self):
        self.git('checkout', '-qb', 'feature/issue-1')
        self.task('  failed_when: result.rc not in [0, 1]\n')
        self.git('remote', 'add', 'origin', 'https://forgejo.fixture/demo-owner/ansible-collection-demo.webapp.git')
        body = Path(self.temp.name) / 'body.txt'
        body.write_text('Closes #1\n')
        original_git = SCOPE['git']
        def local_git(cwd, *args, **kwargs):
            self.assertNotEqual(args[0], 'push', 'Failed checks must prevent publishing')
            return original_git(cwd, *args, **kwargs)
        def reject(_):
            raise RuntimeError('Committed production lint failed')
        with patch.dict(SCOPE, {'forgejo': 'https://forgejo.fixture',
                               'repository': 'demo-owner/ansible-collection-demo.webapp',
                               'git': local_git, 'check_committed_quality': reject,
                               'request': lambda *a, **k: self.fail('Failed checks must prevent API writes')}), \
                patch.dict(os.environ, {'FORGEJO_TOKEN': 'fixture-token'}), \
                patch.object(Path, 'cwd', return_value=self.root):
            with self.assertRaisesRegex(RuntimeError, 'production lint failed'):
                SCOPE['open_pr'](1, body)

    def test_unconditional_command_failure_suppression_is_rejected(self):
        for condition in ('false', '"false"'):
            with self.subTest(condition=condition):
                self.task(f'  failed_when: {condition}\n')
                with self.assertRaisesRegex(RuntimeError, 'unconditional'):
                    SCOPE['check_committed_quality'](self.root)

    def test_restorecon_cannot_accept_error_exit_codes(self):
        self.task('  failed_when: result.rc not in [0, 255]\n')
        target = self.root / 'roles/example/tasks/main.yml'
        target.write_text(target.read_text().replace('argv: [example]', 'argv: [/usr/sbin/restorecon, -Rv, /web]'))
        self.commit()
        with self.assertRaisesRegex(RuntimeError, 'restorecon'):
            SCOPE['check_committed_quality'](self.root)

    def test_checks_export_head_and_keep_installation_separate(self):
        self.task('  failed_when: result.rc not in [0, 1]\n')
        committed = (self.root / 'galaxy.yml').read_text()
        (self.root / 'galaxy.yml').write_text('Uncommitted replacement\n')
        before = self.git('status', '--porcelain')
        calls = []
        def runner(cwd, environment, *command):
            calls.append(command)
            self.assertNotEqual(cwd, self.root)
            self.assertEqual((cwd / 'galaxy.yml').read_text(), committed)
            installed = Path(environment['ANSIBLE_COLLECTIONS_PATH'].split(':')[0])
            self.assertNotEqual(installed, cwd)
            self.assertNotIn(cwd, installed.parents)
            if 'build' in command:
                output = Path(command[command.index('--output-path') + 1])
                (output / 'fixture-example-1.0.0.tar.gz').touch()
            if command[0] == 'ansible-lint':
                raise subprocess.CalledProcessError(2, command)
        with patch.dict(SCOPE, {'run_collection_check': runner}):
            with self.assertRaises(subprocess.CalledProcessError):
                SCOPE['check_committed_quality'](self.root)
        self.assertEqual(self.git('status', '--porcelain'), before)
        self.assertTrue(any(c[0] == 'ansible-lint' for c in calls))
        self.assertFalse(any('unittest' in c for c in calls))

    def test_valid_checks_include_units_without_mutating_checkout(self):
        self.task('  failed_when: result.rc not in [0, 1]\n'
                  '  vars:\n    opaque: !unsafe "{{ fixture_expression }}"\n')
        head = self.git('rev-parse', 'HEAD')
        calls = []
        def runner(cwd, environment, *command):
            calls.append(command)
            if 'build' in command:
                output = Path(command[command.index('--output-path') + 1])
                (output / 'fixture-example-1.0.0.tar.gz').touch()
        with patch.dict(SCOPE, {'run_collection_check': runner}):
            self.assertEqual(SCOPE['check_committed_quality'](self.root), head)
        self.assertTrue(any('unittest' in c for c in calls))
        self.assertEqual(self.git('rev-parse', 'HEAD'), head)
        self.assertEqual(self.git('status', '--porcelain'), '')


if __name__ == '__main__':
    unittest.main()
