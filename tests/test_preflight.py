"""Read-only prerequisites and kubeconfig precedence, with no real credentials."""
from contextlib import contextmanager, redirect_stdout
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bootstrap"))
from manifest import ManifestError, read_rhel_entitlement
import preflight
import local_tools


def make_manifest(path, entries=None, consumer=None):
    if consumer is None:
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as inner:
            inner.writestr("export/entitlements/", "")
            for index, entry in enumerate(entries or []):
                inner.writestr(f"export/entitlements/{index}.json", json.dumps(entry))
        consumer = data.getvalue()
    with zipfile.ZipFile(path, "w") as outer:
        outer.writestr("consumer_export.zip", consumer)


def rhel_entry():
    return {"pool": {"productName": "Red Hat Enterprise Linux for x86_64"},
            "certificates": [{"cert": "fixture certificate", "key": "fixture key"}]}


class ManifestTests(unittest.TestCase):
    def test_selects_primary_and_provided_rhel_products(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.zip"
            for provided in (False, True):
                entry = rhel_entry()
                if provided:
                    entry["pool"] = {"productName": "other", "providedProducts": [
                        {"productName": "Red Hat Enterprise Linux Server"}]}
                make_manifest(path, [entry])
                self.assertEqual(read_rhel_entitlement(path), "fixture certificate\nfixture key")

    def test_rejects_both_bad_zip_layers_and_missing_consumer(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.zip"
            path.write_text("invalid")
            with self.assertRaises(ManifestError):
                read_rhel_entitlement(path)
            with zipfile.ZipFile(path, "w") as outer:
                outer.writestr("other", "invalid")
            with self.assertRaises(ManifestError):
                read_rhel_entitlement(path)
            make_manifest(path, consumer=b"invalid")
            with self.assertRaises(ManifestError):
                read_rhel_entitlement(path)

    def test_rejects_malformed_json_without_exposing_values(self):
        with tempfile.TemporaryDirectory() as directory:
            data = io.BytesIO()
            with zipfile.ZipFile(data, "w") as inner:
                inner.writestr("export/entitlements/bad.json", "sensitive-fixture-value")
            path = Path(directory) / "manifest.zip"
            make_manifest(path, consumer=data.getvalue())
            with self.assertRaises(ManifestError) as error:
                read_rhel_entitlement(path)
            self.assertNotIn("sensitive-fixture-value", str(error.exception))

    def test_requires_rhel_and_nonempty_string_certificates_and_keys(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "manifest.zip"
            for field, value in (("cert", ""), ("key", " "), ("key", None), ("cert", True)):
                entry = rhel_entry()
                entry["certificates"][0][field] = value
                make_manifest(path, [entry])
                with self.assertRaises(ManifestError):
                    read_rhel_entitlement(path)
            entry = rhel_entry()
            entry["pool"]["productName"] = "other product"
            make_manifest(path, [entry])
            with self.assertRaises(ManifestError):
                read_rhel_entitlement(path)
            make_manifest(path, [None])
            with self.assertRaises(ManifestError):
                read_rhel_entitlement(path)


class KubeconfigTests(unittest.TestCase):
    def test_inherited_file_missing_lists_and_spaces(self):
        with tempfile.TemporaryDirectory() as directory:
            env_file = Path(directory) / "inputs.env"
            for inherited, explicit, expected in (
                ("/inherited", "/file", "/inherited"),
                ("", "/file", "/file"),
                (None, "/file", "/file"),
                (None, None, ""),
                ("", None, ""),
                ("/config one:/config two", "/file", "/config one:/config two"),
                (None, "/file one:/file two", "/file one:/file two"),
            ):
                with self.subTest(inherited=inherited, explicit=explicit):
                    env_file.write_text("" if explicit is None else f"KUBECONFIG='{explicit}'\n")
                    env = {"PATH": os.environ["PATH"], "HOME": directory, "ENV_FILE": str(env_file)}
                    if inherited is not None:
                        env["KUBECONFIG"] = inherited
                    result = subprocess.run(["bash", "-c", 'source "$1"; printf "%s" "$KUBECONFIG"',
                                             "test", str(ROOT / "bootstrap/env.sh")], env=env,
                                            capture_output=True, text=True, check=True)
                    self.assertEqual(result.stdout, expected)
            self.assertFalse((Path(directory) / ".kube").exists())


class PreflightTests(unittest.TestCase):
    def test_success_with_installed_later_apis_absent_and_only_read_calls(self):
        calls, requests = [], []
        healthy = {"status": {"conditions": [{"type": "Available", "status": "True"},
                                              {"type": "Degraded", "status": "False"}]}}
        resources = {
            "ingresscontroller": {"status": {"domain": "apps.example.test"}},
            "storageclasses": {"items": [{"metadata": {"name": "fixture", "annotations": {
                "storageclass.kubernetes.io/is-default-class": "true"}}}]},
            "catalogsource": {"status": {"connectionState": {"lastObservedState": "READY"}}},
            "config.imageregistry.operator.openshift.io": {"spec": {"managementState": "Managed", "storage": {"pvc": {"claim": "registry"}}}},
            "clusteroperator": healthy,
            "namespace": {"status": {"phase": "Active"}},
            "deployment": {"status": {"availableReplicas": 1}},
            "service": {"spec": {"ports": [{"port": 5432}]}},
            "pvc": {"status": {"phase": "Bound"}},
            "nodes": {"items": [{"status": {"conditions": [{"type": "Ready", "status": "True"}]}}]},
        }
        def oc(*args):
            calls.append(args)
            if args[:2] == ("whoami", "--show-server"):
                return "https://cluster.example.test:6443"
            if args == ("whoami",):
                return "admin"
            if args[0] == "auth":
                return "yes"
            self.assertIn("get", args)
            return json.dumps(resources[args[args.index("get") + 1]])
        @contextmanager
        def proxy(namespace, names):
            yield "http://127.0.0.1:12345"
        class Opener:
            def open(self, request, timeout):
                requests.append(request)
                return io.BytesIO(json.dumps({"kind": "PartialObjectMetadata", "metadata": {
                    "name": request.full_url.rsplit("/", 1)[1],
                    "annotations": {"fixture": "sensitive-metadata-fixture"}}}).encode())
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "manifest.zip"
            make_manifest(manifest, [rhel_entry()])
            output = io.StringIO()
            inputs = {"KUBECONFIG": "/fixture one:/fixture two", "AAP_LICENSE_FILE": str(manifest),
                      "MODEL_PROVIDER": "opencode-go", "OPENCODE_GO_API_KEY": "sensitive-model-fixture",
                      "DEMO_CLUSTER_SERVER": ""}
            with patch.dict(os.environ, inputs), patch.object(preflight, "oc", oc), \
                 patch.object(preflight, "metadata_proxy", proxy), \
                 patch.object(preflight.urllib.request, "build_opener", return_value=Opener()), \
                 patch.object(subprocess, "run", wraps=subprocess.run) as run, redirect_stdout(output):
                self.assertEqual(preflight.main(), 0)
            self.assertEqual(calls[:2], [("whoami", "--show-server"), ("whoami",)])
            self.assertTrue(all("secret" not in call and "--kubeconfig" not in call for call in calls))
            self.assertEqual(len(requests), 2)
            self.assertTrue(all(request.get_header("Accept") == preflight.METADATA_ACCEPT for request in requests))
            self.assertTrue(all(call.args[0][0] in ("bash", "yq", "jq") for call in run.call_args_list))
            for value in ("fixture certificate", "fixture key", "sensitive-model-fixture", "sensitive-metadata-fixture"):
                self.assertNotIn(value, output.getvalue())
            self.assertIn("may be absent before installation", output.getvalue())

    def test_aggregates_local_failures_and_skips_cluster_without_config(self):
        output = io.StringIO()
        with patch.dict(os.environ, {"KUBECONFIG": ""}), \
             patch.object(preflight, "check_tools", return_value=[("tool git", "Install git")]), \
             patch.object(preflight, "model_inputs", side_effect=ValueError()), \
             patch.object(preflight, "manifest_inputs", side_effect=ManifestError("invalid")), \
             patch.object(preflight, "oc") as oc, redirect_stdout(output):
            self.assertEqual(preflight.main(), 2)
        oc.assert_not_called()
        self.assertIn("4 required failure(s)", output.getvalue())

    def test_requires_json_yq_output(self):
        with patch.object(local_tools.shutil, "which", return_value="fixture"), \
             patch.object(local_tools.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "jq")):
            self.assertEqual(local_tools.check_tools()[0][0], "yq/jq compatibility")

    def test_metadata_get_has_no_full_json_fallback(self):
        requests = []
        @contextmanager
        def proxy(namespace, names):
            yield "http://127.0.0.1:12345"
        class Opener:
            def open(self, request, timeout):
                requests.append(request)
                return io.BytesIO(json.dumps({"kind": "PartialObjectMetadata",
                                              "metadata": {"name": request.full_url.rsplit("/", 1)[1]}}).encode())
        with patch.object(preflight, "metadata_proxy", proxy), \
             patch.object(preflight.urllib.request, "build_opener", return_value=Opener()):
            preflight.secret_metadata("keycloak", ("keycloak-tls", "keycloak-pgsql-user"))
        self.assertEqual(len(requests), 2)
        self.assertTrue(all(request.get_header("Accept") == preflight.METADATA_ACCEPT for request in requests))

    def test_bootstrap_stops_before_mutation_on_invalid_local_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / "bin"
            binary.mkdir()
            log = Path(directory) / "calls"
            stub = binary / "oc"
            stub.write_text('#!/bin/sh\necho called >> "$CALL_LOG"\nexit 1\n')
            stub.chmod(0o755)
            env_file = Path(directory) / "inputs.env"
            env_file.write_text("MODEL_PROVIDER=invalid\nKUBECONFIG=''\nAAP_LICENSE_FILE=/missing-fixture\n")
            env = {"PATH": f"{binary}:{os.environ['PATH']}", "HOME": directory,
                   "ENV_FILE": str(env_file), "CALL_LOG": str(log)}
            result = subprocess.run(["bash", str(ROOT / "bootstrap/bootstrap.sh")],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn("FAIL model inputs", result.stdout)
            self.assertIn("FAIL manifest", result.stdout)
            self.assertFalse(log.exists(), "bootstrap reached oc before passing preflight")

    def test_unready_aap_or_image_prevents_webapp_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "bootstrap").mkdir()
            shutil.copy(ROOT / "scripts/webapp-demo.sh", root / "scripts/webapp-demo.sh")
            (root / "bootstrap/env.sh").write_text('demo_repo_root="$TEST_ROOT"\ndemo_verify_cluster() { :; }\ndemo_wait_for_api() { :; }\n')
            (root / "bootstrap/readiness.sh").write_text('echo "$1" >> "$CALL_LOG"\nexit 7\n')
            binary = root / "bin"
            binary.mkdir()
            python = binary / "python3"
            python.write_text('#!/bin/sh\necho launched >> "$CALL_LOG"\nexit 99\n')
            python.chmod(0o755)
            log = root / "calls"
            env = {"PATH": f"{binary}:{os.environ['PATH']}", "TEST_ROOT": str(root), "CALL_LOG": str(log)}
            result = subprocess.run(["bash", str(root / "scripts/webapp-demo.sh"), "create"],
                                    env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 7)
            self.assertEqual(log.read_text().splitlines(), ["aap"])
