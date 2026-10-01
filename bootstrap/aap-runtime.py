#!/usr/bin/env python3
"""The small imperative seam: create runtime AAP credentials before Git dispatch."""
import base64
import http.client
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

NAMESPACE = "ansible-automation-platform"


def oc(*args, input_data=None):
    return subprocess.check_output(["oc", *args], input=input_data, text=True).strip()


def secret(namespace, name):
    obj = json.loads(oc("-n", namespace, "get", "secret", name, "-o", "json"))
    return {k: base64.b64decode(v).decode() for k, v in obj.get("data", {}).items()}


def apply_secret(namespace, name, values, **extra):
    obj = {"apiVersion": "v1", "kind": "Secret",
           "metadata": {"name": name, "namespace": namespace}, "stringData": values, **extra}
    oc("-n", namespace, "apply", "-f", "-", input_data=json.dumps(obj))


class Controller:
    def __init__(self):
        self.host = os.environ.get("AAP_HOST") or "https://" + oc(
            "-n", NAMESPACE, "get", "route", "aap", "-o", "jsonpath={.status.ingress[0].host}")
        self.username = os.environ.get("AAP_USERNAME") or "admin"
        self.password = os.environ.get("AAP_PASSWORD") or secret(NAMESPACE, "aap-admin-password")["password"]

    def request(self, path, data=None, method=None, prefix="/api/controller/v2/"):
        auth = base64.b64encode(f"{self.username}:{self.password}".encode()).decode()
        req = urllib.request.Request(self.host + prefix + path,
            data=json.dumps(data).encode() if data is not None else None,
            headers={"Authorization": "Basic " + auth, "Content-Type": "application/json"}, method=method)
        # Polling must tolerate a brief ingress/network interruption. Never
        # retry writes: a timed-out launch might already have created a job.
        attempts = 3 if req.get_method() == "GET" else 1
        for attempt in range(attempts):
            try:
                with urllib.request.urlopen(req, timeout=60) as response:
                    payload = response.read()
                    return json.loads(payload) if payload else {}
            except urllib.error.HTTPError as error:
                if error.code not in (502, 503, 504) or attempt == attempts - 1:
                    # API payloads can contain inputs. Never print them.
                    raise RuntimeError(f"AAP {req.get_method()} {path.split('?')[0]} returned HTTP {error.code}") from None
            except (urllib.error.URLError, TimeoutError, http.client.RemoteDisconnected):
                if attempt == attempts - 1:
                    raise RuntimeError(f"AAP {req.get_method()} {path.split('?')[0]} could not complete after {attempts} attempt(s)") from None
            print(f"AAP GET {path.split('?')[0]} interrupted; retrying")
            time.sleep(5 * (attempt + 1))

    def find(self, endpoint, name, **filters):
        result = self.request(endpoint + "?" + urllib.parse.urlencode({"name": name, **filters}))
        return next(iter(result["results"]), None)

    def upsert(self, endpoint, name, **fields):
        scope = {key: fields[key] for key in ("organization", "inventory") if key in fields}
        existing = self.find(endpoint, name, **scope)
        if existing:
            if endpoint == "credential_types/" and all(existing.get(k) == v for k, v in fields.items()):
                return existing
            if endpoint == "credentials/" and existing["credential_type"] != fields["credential_type"]:
                # One-time migration from the earlier demo credential schema.
                self.request(f"{endpoint}{existing['id']}/", method="DELETE")
            else:
                return self.request(f"{endpoint}{existing['id']}/", fields, "PATCH")
        return self.request(endpoint, {"name": name, **fields}, "POST")

    def wait(self, path, timeout=1800):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            job = self.request(path)
            if job["status"] == "successful":
                print(f"AAP {path} successful")
                return job
            if job["status"] in ("failed", "error", "canceled"):
                raise RuntimeError(f"AAP {path} {job['status']}; inspect the job in AAP")
            time.sleep(5)
        raise RuntimeError(f"Timed out waiting for AAP {path}")


def prepare_credentials(api):
    manifest = Path(os.environ.get("AAP_LICENSE_FILE") or Path.cwd() / "aap_manifest.zip")
    with zipfile.ZipFile(manifest) as outer, zipfile.ZipFile(io.BytesIO(outer.read("consumer_export.zip"))) as inner:
        entitlement = None
        for name in inner.namelist():
            if not name.startswith("export/entitlements/"):
                continue
            entry = json.loads(inner.read(name))
            pool = entry.get("pool", {})
            products = [pool.get("productName", "")] + [p.get("productName", "") for p in pool.get("providedProducts", [])]
            if not any(p in products for p in ("Red Hat Enterprise Linux for x86_64", "Red Hat Enterprise Linux Server")):
                continue
            for certificate in entry.get("certificates", []):
                if certificate.get("cert") and certificate.get("key"):
                    entitlement = certificate["cert"] + "\n" + certificate["key"]
                    break
            if entitlement:
                break
    if not entitlement:
        raise RuntimeError("The manifest must include a RHEL entitlement certificate and private key")

    token_name = "aap-vm-admin-token"
    token_spec = {"apiVersion": "v1", "kind": "Secret", "type": "kubernetes.io/service-account-token",
        "metadata": {"name": token_name, "namespace": NAMESPACE,
                     "annotations": {"kubernetes.io/service-account.name": "aap-vm-admin"}}}
    oc("-n", NAMESPACE, "apply", "-f", "-", input_data=json.dumps(token_spec))
    for _ in range(60):
        runtime = secret(NAMESPACE, token_name)
        if runtime.get("token"):
            break
        time.sleep(1)
    else:
        raise RuntimeError("Service account token was not populated")

    # Preserve the SSH identity across bootstrap reruns and Forgejo resets.
    exists = oc("-n", NAMESPACE, "get", "secret", "aap-webapp-ssh", "--ignore-not-found", "-o", "name")
    if not exists:
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            key = Path(directory) / "id_ed25519"
            subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "aap-webapp", "-f", str(key)], check=True)
            apply_secret(NAMESPACE, "aap-webapp-ssh", {"private-key": key.read_text(), "public-key": key.with_suffix(".pub").read_text()})
    ssh = secret(NAMESPACE, "aap-webapp-ssh")
    org = api.upsert("organizations/", "demo", description="Disposable automation demo")
    kind = api.upsert("credential_types/", "Demo VM API", kind="cloud",
        inputs={"fields": [
            {"id": "kube_api_host", "label": "Kubernetes API URL", "type": "string"},
            {"id": "kube_api_token", "label": "Service account token", "type": "string", "secret": True},
            {"id": "kube_api_ca", "label": "Kubernetes CA", "type": "string", "multiline": True},
            {"id": "ssh_public_key", "label": "VM SSH public key", "type": "string"}],
            "required": ["kube_api_host", "kube_api_token", "kube_api_ca", "ssh_public_key"]},
        injectors={"file": {"template": "{{ kube_api_ca }}"}, "env": {
            "K8S_AUTH_HOST": "{{ kube_api_host }}", "K8S_AUTH_API_KEY": "{{ kube_api_token }}",
            "K8S_AUTH_SSL_CA_CERT": "{{ tower.filename }}", "K8S_AUTH_VERIFY_SSL": "true",
            "VM_SSH_PUBLIC_KEY": "{{ ssh_public_key }}"}})
    api.upsert("credentials/", "demo-virtualmachine-admin", organization=org["id"], credential_type=kind["id"],
        inputs={"kube_api_host": oc("whoami", "--show-server"), "kube_api_token": runtime["token"],
                "kube_api_ca": runtime["ca.crt"], "ssh_public_key": ssh["public-key"].strip()})
    machine = api.find("credential_types/", "Machine")
    api.upsert("credentials/", "demo-webapp-ssh", organization=org["id"], credential_type=machine["id"],
        inputs={"username": "cloud-user", "ssh_key_data": ssh["private-key"], "become_method": "sudo"})
    rhel = api.upsert("credential_types/", "Demo RHEL entitlement", kind="cloud",
        inputs={"fields": [{"id": "entitlement_pem", "label": "RHEL entitlement PEM", "type": "string", "secret": True, "multiline": True}],
                "required": ["entitlement_pem"]},
        injectors={"file": {"template": "{{ entitlement_pem }}"}, "env": {"RHEL_ENTITLEMENT_FILE": "{{ tower.filename }}"}})
    api.upsert("credentials/", "demo-rhel-entitlement", organization=org["id"], credential_type=rhel["id"],
               inputs={"entitlement_pem": entitlement})
    config = api.upsert("credential_types/", "Demo AAP dispatch", kind="cloud",
        inputs={"fields": [
            {"id": "host", "label": "AAP URL", "type": "string"},
            {"id": "username", "label": "AAP username", "type": "string"},
            {"id": "password", "label": "AAP password", "type": "string", "secret": True}],
            "required": ["host", "username", "password"]},
        injectors={"env": {"AAP_HOST": "{{ host }}", "AAP_USERNAME": "{{ username }}", "AAP_PASSWORD": "{{ password }}"}})
    api.upsert("credentials/", "demo-aap-dispatch", organization=org["id"], credential_type=config["id"],
               inputs={"host": api.host, "username": api.username, "password": api.password})
    galaxy = api.find("credential_types/", "Ansible Galaxy/Automation Hub API Token")
    community = api.upsert("credentials/", "demo-galaxy", organization=org["id"], credential_type=galaxy["id"],
        inputs={"url": "https://galaxy.ansible.com/"})
    api.request(f"organizations/{org['id']}/galaxy_credentials/", {"id": community["id"], "associate": True})
    if not oc("-n", NAMESPACE, "get", "secret", "aap-resource-connection", "--ignore-not-found", "-o", "name"):
        token = api.request("tokens/", {"description": "demojam resource operator", "scope": "write"}, prefix="/api/gateway/v1/")
        apply_secret(NAMESPACE, "aap-resource-connection", {"host": api.host, "token": token["token"]})
    project = api.find("projects/", "demojam-ansible", organization=org["id"])
    if project and project.get("credential"):
        api.request(f"projects/{project['id']}/", {"credential": None}, "PATCH")
    api.request("config/", {"manifest": base64.b64encode(manifest.read_bytes()).decode()})
    print("AAP license and runtime VM, SSH, entitlement, and dispatch credentials are ready")



def wait_for_resources(api, require_template=True):
    """Operator conditions can precede actual Controller object creation."""
    deadline = time.monotonic() + 900
    while time.monotonic() < deadline:
        org = api.find("organizations/", "demo")
        if org:
            inventory = api.find("inventories/", "demo-inventory", organization=org["id"])
            project = api.find("projects/", "demojam-ansible", organization=org["id"])
            if inventory and project and project["status"] == "successful":
                if not require_template:
                    print("Resource Operator inventory and synced project exist in AAP")
                    return
                template = api.find("job_templates/", "aap_configure_all", organization=org["id"])
                if (template and template["inventory"] == inventory["id"]
                        and template["project"] == project["id"]
                        and template["playbook"] == "playbooks/aap/configure-aap.yml"):
                    print("Resource Operator dispatch template exists in AAP")
                    return
        time.sleep(5)
    raise RuntimeError("Resource Operator objects did not become ready in AAP; inspect the CRs and project update")


def launch(api, name, extra, *, reset=False):
    org = api.find("organizations/", "demo")
    if not org:
        raise RuntimeError("Bootstrap the demo organization before launching automation")
    template = api.find("job_templates/", name, organization=org["id"])
    if not template:
        raise RuntimeError(f"Job template {name} was not found")
    # Only the demo's three purposeful templates are exposed by this helper.
    if name not in ("webapp_vm", "webapp_nginx", "aap_configure_all") and not (reset and name == "openshift_virtualization_machine"):
        raise RuntimeError("Only demo webapp and dispatch templates may be launched")
    if name == "webapp_vm" and extra.get("vm_state") == "absent":
        print("Deleting only webapp in webapp-vms")
    result = api.request(f"job_templates/{template['id']}/launch/", {"extra_vars": extra})
    print(f"Launched {name}: job {result['job']}")
    api.wait(f"jobs/{result['job']}/")



def reset_vms(api):
    """Remove only the two seeded demo VMs through their managed AAP templates."""
    org = api.find("organizations/", "demo")
    if not org:
        raise RuntimeError("Bootstrap AAP before resetting the demo")
    targets = (
        ("webapp_vm", "playbooks/openshift_virtualization/webapp-launch.yml", {}),
        ("openshift_virtualization_machine", "playbooks/openshift_virtualization/virtualmachine-manage.yml",
         {"vm_name": "automation-demo"}),
    )
    # Validate both templates before launching either destructive operation.
    for name, playbook, _ in targets:
        template = api.find("job_templates/", name, organization=org["id"])
        if not template or template["playbook"] != playbook:
            raise RuntimeError(f"Reset requires the seeded {name} template")
        project = api.request(f"projects/{template['project']}/")
        inventory = api.request(f"inventories/{template['inventory']}/")
        if project["name"] != "demojam-ansible" or inventory["name"] != "demo-inventory":
            raise RuntimeError(f"Reset refused unexpected project/inventory for {name}")
        active = api.request(f"jobs/?job_template={template['id']}&page_size=200")
        for job in active["results"]:
            if job["status"] in ("new", "pending", "waiting", "running"):
                api.wait(f"jobs/{job['id']}/")
    for name, _, extra in targets:
        launch(api, name, {"host": "demo_cluster", "vm_state": "absent", **extra}, reset=True)


def associate_credential(api, path, credential_id):
    attached = api.request(path + "?page_size=200")["results"]
    if not any(item["id"] == credential_id for item in attached):
        api.request(path, {"id": credential_id, "associate": True})


def dispatch(api):
    """Prepare the operator-created template for its first Controller launch."""
    wait_for_resources(api)
    org = api.find("organizations/", "demo")
    template = api.find("job_templates/", "aap_configure_all", organization=org["id"])
    credential = api.find("credentials/", "demo-aap-dispatch", organization=org["id"])
    if not credential:
        raise RuntimeError("Seed the demo-aap-dispatch credential before dispatch")
    image = os.environ.get("AAP_EE_IMAGE")
    if not image:
        raise RuntimeError("Load bootstrap/env.sh to select the supported AAP EE")
    ee = api.upsert("execution_environments/", "demo-aap-ee", organization=org["id"], image=image, pull="always")
    api.request(f"job_templates/{template['id']}/", {
        "execution_environment": ee["id"],
        # Retain an operator-selected image for subsequent aap_configure_all runs.
        "extra_vars": json.dumps({"aap_ee_image": image})}, "PATCH")
    associate_credential(api, f"job_templates/{template['id']}/credentials/", credential["id"])
    # The inventory CR has no hosts. Import the aap group before the first play.
    source = api.upsert("inventory_sources/", "demo-inventory-scm", inventory=template["inventory"],
        source="scm", source_project=template["project"], source_path="inventory.yml",
        execution_environment=ee["id"], overwrite=True, overwrite_vars=True,
        update_on_launch=True, update_cache_timeout=0, timeout=900)
    update = api.request(f"inventory_sources/{source['id']}/update/", {})
    api.wait(f"inventory_updates/{update['id']}/")
    group = api.find("groups/", "aap", inventory=template["inventory"])
    if not group or not api.request(f"groups/{group['id']}/hosts/?name=aap_demo")["count"]:
        raise RuntimeError("The bootstrap inventory sync did not import aap_demo into the aap group")
    launch(api, "aap_configure_all", {})


def main():
    sys.stdout.reconfigure(line_buffering=True)
    api = Controller()
    action = sys.argv[1]
    if action == "credentials":
        prepare_credentials(api)
    elif action == "wait-project":
        wait_for_resources(api, require_template=False)
    elif action == "dispatch":
        dispatch(api)
    elif action == "reset-vms":
        reset_vms(api)
    elif action == "launch":
        launch(api, sys.argv[2], json.loads(sys.argv[3]) if len(sys.argv) > 3 else {})
    else:
        raise RuntimeError("Use credentials, wait-project, dispatch, reset-vms, or launch TEMPLATE [JSON_EXTRA_VARS]")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, urllib.error.URLError, subprocess.CalledProcessError, OSError, zipfile.BadZipFile) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
