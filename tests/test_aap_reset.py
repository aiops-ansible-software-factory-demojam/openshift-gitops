"""Reset must validate all targets before launching a destructive AAP job."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("runtime", Path(__file__).resolve().parents[1] / "bootstrap/aap-runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class Controller:
    def __init__(self, wrong_project=False):
        self.wrong_project = wrong_project
        self.waited = []

    def find(self, endpoint, name, **filters):
        if endpoint == "organizations/":
            return {"id": 1}
        playbooks = {
            "webapp_vm": "webapp-launch.yml",
            "openshift_virtualization_machine": "virtualmachine-manage.yml",
        }
        return {"id": 1 if name == "webapp_vm" else 2,
                "project": 1 if name == "webapp_vm" else 2, "inventory": 1,
                "playbook": "playbooks/openshift_virtualization/" + playbooks[name]}

    def request(self, path):
        if path.startswith("projects/"):
            return {"name": "other" if self.wrong_project and path == "projects/2/" else "demojam-ansible"}
        if path.startswith("inventories/"):
            return {"name": "demo-inventory"}
        return {"results": [{"id": 99, "status": "running"}]}

    def wait(self, path):
        self.waited.append(path)


class ResetTests(unittest.TestCase):
    def test_dispatch_does_not_reattach_existing_credential(self):
        api = Mock()
        api.request.return_value = {"results": [{"id": 6}]}
        runtime.associate_credential(api, "job_templates/8/credentials/", 6)
        api.request.assert_called_once_with("job_templates/8/credentials/?page_size=200")

    def test_dispatch_attaches_missing_credential(self):
        api = Mock()
        api.request.return_value = {"results": []}
        runtime.associate_credential(api, "job_templates/8/credentials/", 6)
        self.assertEqual(api.request.call_args.args,
                         ("job_templates/8/credentials/", {"id": 6, "associate": True}))

    def test_wrong_second_project_prevents_both_deletions(self):
        with patch.object(runtime, "launch") as launch:
            with self.assertRaisesRegex(RuntimeError, "unexpected project/inventory"):
                runtime.reset_vms(Controller(wrong_project=True))
            launch.assert_not_called()

    def test_waits_and_deletes_only_seeded_vm_targets(self):
        api = Controller()
        with patch.object(runtime, "launch") as launch:
            runtime.reset_vms(api)
            self.assertEqual(api.waited, ["jobs/99/", "jobs/99/"])
            self.assertEqual(launch.call_args_list[0].args[1:],
                ("webapp_vm", {"host": "demo_cluster", "vm_state": "absent"}))
            self.assertEqual(launch.call_args_list[1].args[1:],
                ("openshift_virtualization_machine", {"host": "demo_cluster", "vm_state": "absent", "vm_name": "automation-demo"}))


if __name__ == "__main__":
    unittest.main()
