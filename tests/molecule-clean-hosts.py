"""Exercise repository lifecycle sequences using real Molecule and local fixtures.

Run in the pinned development-tools image with --config for every guest scenario.
The fixture has no cloud credentials and creates no VM: a file represents a guest
whose stale state must be removed before each separate provisioning command.
"""
import argparse
import copy
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import yaml


class CleanHostsTests(unittest.TestCase):
    configs = []

    def fixture(self, directory, scenario):
        root = Path(directory)
        guest = root / 'guest'
        denied = root / 'deny-cleanup'
        config_dir = root / 'molecule/default'
        config_dir.mkdir(parents=True)
        scenario = copy.deepcopy(scenario)
        scenario['name'] = 'default'
        definition = {
            'prerun': False,
            'dependency': {'name': 'galaxy', 'enabled': False},
            'ansible': {
                'executor': {'args': {'ansible_playbook': ['--inventory=localhost,']}},
                'playbooks': {name: name + '.yml' for name in
                              ['create', 'destroy', 'prepare', 'converge', 'verify']},
            },
            'scenario': scenario,
            'verifier': {'name': 'ansible'},
        }
        (config_dir / 'molecule.yml').write_text(yaml.safe_dump(definition, sort_keys=False))

        def play(name, tasks):
            value = [{'name': name, 'hosts': 'all', 'connection': 'local',
                      'gather_facts': False,
                      'vars': {'ansible_remote_tmp': str(root / 'remote-tmp'),
                               'ansible_python_interpreter': sys.executable},
                      'tasks': tasks}]
            (config_dir / (name + '.yml')).write_text(yaml.safe_dump(value, sort_keys=False))

        play('destroy', [
            {'name': 'Inspect the cleanup failure fixture',
             'ansible.builtin.stat': {'path': str(denied)}, 'register': 'denied'},
            {'name': 'Require successful cleanup before continuing',
             'ansible.builtin.assert': {'that': 'not denied.stat.exists',
                                      'fail_msg': 'Fixture cleanup refused'}},
            {'name': 'Remove the owned guest fixture',
             'ansible.builtin.file': {'path': str(guest), 'state': 'absent'}},
        ])
        play('create', [
            {'name': 'Inspect the previous guest fixture',
             'ansible.builtin.stat': {'path': str(guest)}, 'register': 'previous'},
            {'name': 'Require a genuinely new guest',
             'ansible.builtin.assert': {'that': 'not previous.stat.exists'}},
            {'name': 'Create the clean guest fixture',
             'ansible.builtin.copy': {'dest': str(guest), 'content': 'baseline', 'mode': '0600'}},
        ])
        play('prepare', [
            {'name': 'Read the prepared guest fixture',
             'ansible.builtin.slurp': {'src': str(guest)}, 'register': 'guest'},
            {'name': 'Require a clean baseline before deployment',
             'ansible.builtin.assert': {'that': "guest.content | b64decode == 'baseline'"}},
        ])
        play('converge', [
            {'name': 'Read the deployed guest fixture',
             'ansible.builtin.slurp': {'src': str(guest)}, 'register': 'guest'},
            {'name': 'Reject state left by another code revision',
             'ansible.builtin.assert': {
                 'that': "guest.content | b64decode in ['baseline', 'configured']"}},
            {'name': 'Configure the guest idempotently',
             'ansible.builtin.copy': {'dest': str(guest), 'content': 'configured', 'mode': '0600'}},
        ])
        play('verify', [
            {'name': 'Read the verified guest fixture',
             'ansible.builtin.slurp': {'src': str(guest)}, 'register': 'guest'},
            {'name': 'Require the configured guest',
             'ansible.builtin.assert': {'that': "guest.content | b64decode == 'configured'"}},
        ])
        return root, guest, denied

    def run_molecule(self, root, command, passes=True):
        env = dict(os.environ)
        env.update({
            'MOLECULE_GLOB': 'molecule/*/molecule.yml',
            'MOLECULE_EPHEMERAL_DIRECTORY': str(root / 'state'),
            'ANSIBLE_HOME': str(root / 'ansible'),
            'ANSIBLE_LOCAL_TEMP': str(root / 'ansible/tmp'),
            'XDG_CACHE_HOME': str(root / 'cache'),
            'ANSIBLE_NOCOLOR': '1',
            'ANSIBLE_FORCE_COLOR': 'false',
        })
        result = subprocess.run(['molecule', command, '-s', 'default'], cwd=root,
                                env=env, text=True, capture_output=True, timeout=180)
        self.assertEqual(result.returncode == 0, passes,
                         command + '\n' + (result.stdout + result.stderr)[-14000:])
        return result.stdout + result.stderr

    def test_fresh_provisioning_cleanup_failure_and_full_lifecycle(self):
        self.assertIsNotNone(shutil.which('molecule'), 'Use the pinned Molecule development image')
        for config in self.configs:
            with self.subTest(config=str(config)), tempfile.TemporaryDirectory() as tmp:
                scenario = yaml.safe_load(config.read_text())['scenario']
                root, guest, denied = self.fixture(tmp, scenario)
                print('Testing clean lifecycle:', config.name, str(config), flush=True)
                self.run_molecule(root, 'converge')
                self.assertEqual(guest.read_text(), 'configured')
                guest.write_text('stale-from-earlier-code')
                self.run_molecule(root, 'converge')
                self.assertEqual(guest.read_text(), 'configured')
                guest.write_text('stale-from-earlier-code')
                self.run_molecule(root, 'create')
                self.assertEqual(guest.read_text(), 'baseline')
                guest.write_text('stale-from-earlier-code')
                denied.touch()
                output = self.run_molecule(root, 'converge', passes=False)
                self.assertIn('Fixture cleanup refused', output)
                self.assertEqual(guest.read_text(), 'stale-from-earlier-code')
                denied.unlink()
                self.run_molecule(root, 'test')
                self.assertFalse(guest.exists(), 'Full test must finish destruction')
                self.run_molecule(root, 'check')
                self.assertFalse(guest.exists(), 'Check must finish destruction')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', action='append', type=Path, required=True)
    args = parser.parse_args()
    CleanHostsTests.configs = args.config
    unittest.main(argv=[sys.argv[0]], verbosity=2)
