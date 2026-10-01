"""Shared local tool checks; no cluster queries or builds."""
import shutil
import subprocess

TOOLS = ("bash", "make", "oc", "kustomize", "helm", "yq", "jq", "openssl",
         "curl", "git", "python3", "ssh-keygen")


def check_tools():
    """Return named failures for callers to include in their own report."""
    failures = [(f"tool {tool}", f"Install {tool} and put it on PATH")
                for tool in TOOLS if not shutil.which(tool)]
    if shutil.which("yq") and shutil.which("jq"):
        try:
            rendered = subprocess.run(["yq", "."], input="preflight:\n  compatible: true\n",
                                      text=True, capture_output=True, check=True, timeout=15)
            subprocess.run(["jq", "-e", ".preflight.compatible == true"],
                           input=rendered.stdout, text=True, capture_output=True,
                           check=True, timeout=15)
        except (OSError, subprocess.SubprocessError):
            failures.append(("yq/jq compatibility", "Install jq-wrapper yq: yq '.' must emit JSON consumable by jq"))
    return failures
