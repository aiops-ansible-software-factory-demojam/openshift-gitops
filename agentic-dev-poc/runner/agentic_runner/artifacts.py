"""Untrusted workspace collection."""

from __future__ import annotations

import hashlib
import os
import stat
import tarfile
from pathlib import Path

from .models import ARTIFACT_BYTES, MAX_FILES, RequestError

SECRET_MARKERS = (b"OPENSHELL_OIDC_CLIENT_SECRET", b"BEGIN PRIVATE KEY", b"Bearer ")


def collect_tree(root: Path, archive: Path) -> list[dict[str, object]]:
    """Copy regular files under root into a tar archive.

    Symlinks, special files, and paths that leave root are rejected.
    """
    if not root.is_dir():
        raise RequestError(500, "artifact_missing", "Workspace download is not a directory.")
    root = root.resolve()
    manifest: list[dict[str, object]] = []
    total = 0
    count = 0
    archive.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive, "w:gz") as tar:
        for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
            current = Path(dirpath)
            kept: list[str] = []
            for name in dirnames:
                child = current / name
                if child.is_symlink() or not child.is_dir():
                    raise RequestError(422, "artifact_rejected", "Workspace contains a symlink or special directory.")
                if not _inside(root, child):
                    raise RequestError(422, "artifact_rejected", "Workspace path escapes the download root.")
                kept.append(name)
            dirnames[:] = kept
            for name in filenames:
                path = current / name
                count += 1
                if count > MAX_FILES:
                    raise RequestError(422, "artifact_rejected", "Workspace has too many files.")
                info = path.lstat()
                if path.is_symlink() or not path.is_file() or not stat_regular(info.st_mode):
                    raise RequestError(422, "artifact_rejected", "Workspace contains a symlink or special file.")
                if not _inside(root, path):
                    raise RequestError(422, "artifact_rejected", "Workspace path escapes the download root.")
                total += info.st_size
                if total > ARTIFACT_BYTES:
                    raise RequestError(422, "artifact_rejected", "Workspace exceeds 100 MiB.")
                data = path.read_bytes()
                if any(marker in data for marker in SECRET_MARKERS):
                    raise RequestError(422, "artifact_rejected", "Workspace contains credential material.")
                digest = hashlib.sha256(data).hexdigest()
                relative = path.relative_to(root).as_posix()
                tar.add(path, arcname=relative, recursive=False)
                manifest.append({"path": relative, "size": info.st_size, "sha256": digest})
    if archive.stat().st_size > ARTIFACT_BYTES:
        archive.unlink(missing_ok=True)
        raise RequestError(422, "artifact_rejected", "Workspace archive exceeds 100 MiB.")
    return manifest


def stat_regular(mode: int) -> bool:
    return stat.S_ISREG(mode)


def _inside(root: Path, path: Path) -> bool:
    try:
        path.resolve().relative_to(root)
    except ValueError:
        return False
    return True
