"""Aggregate prerequisites without modifying infrastructure or reading Secret data."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import select
import shutil
import subprocess
import time
import urllib.error
import urllib.request

from local_tools import check_tools
from manifest import read_rhel_entitlement

ROOT = Path(__file__).resolve().parents[1]
METADATA_ACCEPT = "application/json;as=PartialObjectMetadata;g=meta.k8s.io;v=v1"


def oc(*args):
    return subprocess.run(["oc", *args, "--request-timeout=30s"],
                          text=True, capture_output=True, check=True, timeout=45).stdout.strip()


def get(resource, name=None, namespace=None):
    args = ["-n", namespace] if namespace else []
    args += ["get", resource]
    if name:
        args.append(name)
    return json.loads(oc(*args, "-o", "json"))


def condition(obj, name):
    return next((item["status"] for item in obj.get("status", {}).get("conditions", [])
                 if item["type"] == name), None)


def require(value):
    if not value:
        raise ValueError("Required prerequisite absent or unready")


@contextmanager
def metadata_proxy(namespace, names):
    # Core Secret GETs negotiate metadata only. No application/json fallback.
    allowed = "^/api/v1/namespaces/" + re.escape(namespace) + "/secrets/(" + "|".join(map(re.escape, names)) + ")$"
    process = subprocess.Popen(["oc", "-n", namespace, "proxy", "--port=0",
                                "--address=127.0.0.1", "--accept-paths=" + allowed],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline and process.poll() is None:
            if select.select([process.stdout], [], [], 0.2)[0]:
                match = re.search(r"127\.0\.0\.1:(\d+)", process.stdout.readline())
                if match:
                    yield "http://127.0.0.1:" + match.group(1)
                    return
        raise ValueError("Could not start local metadata proxy")
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def secret_metadata(namespace, names):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with metadata_proxy(namespace, names) as origin:
        for name in names:
            request = urllib.request.Request(f"{origin}/api/v1/namespaces/{namespace}/secrets/{name}",
                                             headers={"Accept": METADATA_ACCEPT})
            with opener.open(request, timeout=15) as response:
                obj = json.load(response)
            require(obj.get("kind") == "PartialObjectMetadata" and "data" not in obj and "stringData" not in obj)
            require(obj.get("metadata", {}).get("name") == name)
            # Metadata annotations can contain last-applied Secret material. Never print them.


class Report:
    def __init__(self):
        self.failures = 0

    def check(self, name, operation, remediation):
        try:
            detail = operation()
        except (RuntimeError, ValueError, OSError, subprocess.SubprocessError):
            self.failures += 1
            print(f"FAIL {name}: {remediation}")
            return False
        print(f"PASS {name}" + (f": {detail}" if detail else ""))
        return True

    def advisory(self, text):
        print("ADVISORY " + text)


def identity():
    server = oc("whoami", "--show-server")
    user = oc("whoami")
    require(server and user and (not os.environ.get("DEMO_CLUSTER_SERVER") or
                                server == os.environ["DEMO_CLUSTER_SERVER"]))
    return f"{server} as {user}"


def model_inputs():
    subprocess.run(["bash", "-c", 'source "$1"', "preflight", str(ROOT / "bootstrap/model-env.sh")],
                   capture_output=True, check=True, timeout=15)


def manifest_inputs():
    # Never return the material to the report's printable detail field.
    read_rhel_entitlement(os.environ.get("AAP_LICENSE_FILE") or ROOT / "aap_manifest.zip")


def ingress():
    domain = get("ingresscontroller", "default", "openshift-ingress-operator").get("status", {}).get("domain")
    require(domain)
    return domain


def storage():
    classes = get("storageclasses")["items"]
    defaults = [obj for obj in classes if any(obj.get("metadata", {}).get("annotations", {}).get(key) == "true"
                for key in ("storageclass.kubernetes.io/is-default-class", "storageclass.beta.kubernetes.io/is-default-class"))]
    require(defaults)
    return ", ".join(obj["metadata"]["name"] for obj in defaults)


def catalogs():
    for name in ("redhat-operators", "certified-operators"):
        obj = get("catalogsource", name, "openshift-marketplace")
        require(obj.get("status", {}).get("connectionState", {}).get("lastObservedState") == "READY")


def registry():
    config = get("config.imageregistry.operator.openshift.io", "cluster")
    require(config.get("spec", {}).get("managementState") == "Managed")
    require(config["spec"].get("storage"))
    operator = get("clusteroperator", "image-registry")
    require(condition(operator, "Available") == "True" and condition(operator, "Degraded") == "False")
    claim = config["spec"]["storage"].get("pvc", {}).get("claim")
    if claim:
        require(get("pvc", claim, "openshift-image-registry").get("status", {}).get("phase") == "Bound")


def keycloak_database():
    require(get("namespace", "keycloak").get("status", {}).get("phase") == "Active")
    deployment = get("deployment", "keycloak-pgsql", "keycloak")
    require(deployment.get("status", {}).get("availableReplicas", 0) >= 1)
    require(get("service", "keycloak-pgsql", "keycloak").get("spec", {}).get("ports"))
    require(get("pvc", "keycloak-pgsql-data", "keycloak").get("status", {}).get("phase") == "Bound")


def nodes():
    items = get("nodes")["items"]
    require(any(condition(obj, "Ready") == "True" for obj in items))
    require(all(condition(obj, pressure) != "True" for obj in items
                for pressure in ("DiskPressure", "MemoryPressure", "PIDPressure")))


def main():
    report = Report()
    failures = check_tools()
    for name, remediation in failures:
        report.check(name, lambda: require(False), remediation)
    if not failures:
        print("PASS local tools and yq/jq compatibility")
    report.check("model inputs", model_inputs,
                 "Fill the selected provider's key, HTTPS API base URL and model in .env; see README Local secrets")
    report.check("manifest structure and RHEL material",
                 manifest_inputs,
                 "Supply a readable AAP subscription ZIP with consumer_export.zip, valid entitlement JSON and RHEL certificate/key")
    configured = report.check("KUBECONFIG", lambda: require(os.environ.get("KUBECONFIG")),
                              "Export KUBECONFIG or set an explicit path/list in .env; inherited nonempty values win")
    if configured and shutil.which("oc") and report.check("cluster identity", identity, "Check the intended kubeconfig, context and oc authentication"):
        report.check("cluster-admin permissions", lambda: require(oc("auth", "can-i", "*", "*", "--all-namespaces") == "yes"),
                     "Use a cluster-admin identity for this disposable workshop bootstrap")
        report.check("ingress domain", ingress, "Wait for the default ingress controller to report its domain")
        report.check("default storage configuration", storage, "Configure a default StorageClass capable of the demo's RWO claims")
        report.check("operator catalogs", catalogs, "Restore READY redhat-operators and certified-operators CatalogSources in openshift-marketplace")
        report.check("internal registry", registry, "Enable the Managed internal image registry with healthy storage and image-registry ClusterOperator")
        report.check("node readiness and pressure", nodes, "Resolve NotReady nodes or active disk/memory/PID pressure before bootstrap")
        report.check("external Keycloak database", keycloak_database,
                     "Supply keycloak namespace, keycloak-pgsql Deployment/Service and Bound keycloak-pgsql-data PVC; see issue #17")
        report.check("external Keycloak Secret references", lambda: secret_metadata("keycloak", ("keycloak-pgsql-user", "keycloak-tls")),
                     "Supply keycloak-pgsql-user and keycloak-tls in keycloak; metadata-only access through oc proxy is required")
    else:
        report.advisory("Cluster checks skipped until KUBECONFIG, oc and identity are available")
    report.advisory("ZIP checks establish local structure/RHEL material; AAP import validates licensing. Expiry, authenticity and CDN access are not checked")
    report.advisory("Storage configuration/Bound claims do not prove new provisioning or RWO support; registry status does not prove pulls")
    report.advisory("Capacity and hardware KVM need functional validation; node metadata alone cannot prove them")
    report.advisory("Keycloak Secret values, database credentials and realm state are external prerequisites, not inspected here (issue #17)")
    report.advisory("KubeVirt, Tekton, AAP, Sandbox and guest-image APIs may be absent before installation; bootstrap/readiness.sh gates their later use")
    print(f"Preflight: {report.failures} required failure(s)")
    return 2 if report.failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
