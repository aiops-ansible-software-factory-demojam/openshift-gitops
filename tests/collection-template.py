#!/usr/bin/env python3
"""Exercise Forgejo template expansion and build the generated collection."""

from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile


root = Path(__file__).resolve().parents[1]
source = root / "cluster/forgejo-demo/fixtures/collection-template"
forgejo_url = "https://forgejo.apps.example.test"
values = {
    "${REPO_NAME}": "sample_collection",
    "${REPO_OWNER}": "demo-agent",
    "${REPO_DESCRIPTION}": "Example collection",
}

with tempfile.TemporaryDirectory() as temporary:
    target = Path(temporary) / "sample_collection"
    shutil.copytree(source, target, symlinks=True)
    for file in target.rglob("*"):
        if file.is_file() and not file.is_symlink():
            file.write_text(file.read_text().replace("__FORGEJO_URL__", forgejo_url))

    for relative_path in (target / ".gitea/template").read_text().splitlines():
        file = target / relative_path
        content = file.read_text()
        for placeholder, replacement in values.items():
            content = content.replace(placeholder, replacement)
        assert "${" not in content, f"Unexpanded placeholder in {relative_path}"
        file.write_text(content)

    subprocess.run(
        ["ansible-galaxy", "collection", "build", str(target), "--output-path", temporary],
        check=True,
    )
    subprocess.run(["ansible-lint", "--offline", "--profile=basic", str(target)], check=True)
    archive = Path(temporary) / "demo-sample_collection-0.1.0.tar.gz"
    with tarfile.open(archive) as package:
        files = set(package.getnames())
    assert "roles/example/tasks/main.yml" in files
    assert "extensions/molecule/default/molecule.yml" in files
    assert "catalog-info.yaml" not in files
    assert "devfile.yaml" not in files

print("Collection golden path expanded and built successfully")
