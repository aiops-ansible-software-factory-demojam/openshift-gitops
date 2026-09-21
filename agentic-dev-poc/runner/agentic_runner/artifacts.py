"""Untrusted workspace collection."""

from __future__ import annotations

import hashlib
import io
import os
import stat
import tarfile
from pathlib import Path

from .models import ARTIFACT_BYTES, MAX_FILES, RequestError

SECRET_MARKERS = (b"OPENSHELL_OIDC_CLIENT_SECRET", b"BEGIN PRIVATE KEY", b"Bearer ")
REPORT_BYTES = 1024 * 1024
TRANSFER_BYTES = ARTIFACT_BYTES + (MAX_FILES + 8) * 1024


def extract_bounded_tar(archive: Path, destination: Path) -> None:
    """Validate a received tar completely before materializing regular files."""
    members: list[tarfile.TarInfo] = []
    seen: set[str] = set()
    total = 0
    try:
        with tarfile.open(archive, "r:") as incoming:
            for member in incoming:
                name = member.name.removeprefix("./")
                target = Path(name)
                if (
                    not name
                    or target.is_absolute()
                    or ".." in target.parts
                    or not member.isreg()
                    or name in seen
                ):
                    raise RequestError(
                        422,
                        "artifact_rejected",
                        "Workspace transfer contains an unsafe entry.",
                    )
                seen.add(name)
                members.append(member)
                if len(members) > MAX_FILES:
                    raise RequestError(
                        422, "artifact_rejected", "Workspace has too many files."
                    )
                total += member.size
                if total > ARTIFACT_BYTES:
                    raise RequestError(
                        422, "artifact_rejected", "Workspace exceeds 100 MiB."
                    )
                if name == "out/result.json" and member.size > REPORT_BYTES:
                    raise RequestError(
                        422, "artifact_rejected", "Result report is too large."
                    )
    except (tarfile.TarError, OSError) as exc:
        raise RequestError(
            422, "artifact_rejected", "Workspace transfer is not a valid archive."
        ) from exc

    destination.mkdir(parents=True, exist_ok=False)
    with tarfile.open(archive, "r:") as incoming:
        by_name = {member.name.removeprefix("./"): member for member in incoming}
        for name in sorted(seen):
            member = by_name[name]
            source = incoming.extractfile(member)
            if source is None:
                raise RequestError(
                    422, "artifact_rejected", "Workspace transfer entry is unreadable."
                )
            target = destination.joinpath(*Path(name).parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            remaining = member.size
            with target.open("xb") as output:
                while remaining:
                    chunk = source.read(min(65536, remaining))
                    if not chunk:
                        raise RequestError(
                            422,
                            "artifact_rejected",
                            "Workspace transfer was truncated.",
                        )
                    output.write(chunk)
                    remaining -= len(chunk)


def collect_tree(root: Path, archive: Path) -> list[dict[str, object]]:
    """Copy regular files under root into a tar archive.

    Symlinks, special files, and paths that leave root are rejected.
    """
    if not root.is_dir():
        raise RequestError(
            500, "artifact_missing", "Workspace download is not a directory."
        )
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
                    raise RequestError(
                        422,
                        "artifact_rejected",
                        "Workspace contains a symlink or special directory.",
                    )
                if not _inside(root, child):
                    raise RequestError(
                        422,
                        "artifact_rejected",
                        "Workspace path escapes the download root.",
                    )
                kept.append(name)
            dirnames[:] = kept
            for name in filenames:
                path = current / name
                count += 1
                if count > MAX_FILES:
                    raise RequestError(
                        422, "artifact_rejected", "Workspace has too many files."
                    )
                info = path.lstat()
                if (
                    path.is_symlink()
                    or not path.is_file()
                    or not stat_regular(info.st_mode)
                ):
                    raise RequestError(
                        422,
                        "artifact_rejected",
                        "Workspace contains a symlink or special file.",
                    )
                if not _inside(root, path):
                    raise RequestError(
                        422,
                        "artifact_rejected",
                        "Workspace path escapes the download root.",
                    )
                total += info.st_size
                if total > ARTIFACT_BYTES:
                    raise RequestError(
                        422, "artifact_rejected", "Workspace exceeds 100 MiB."
                    )
                flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
                try:
                    descriptor = os.open(path, flags)
                except OSError as exc:
                    raise RequestError(
                        422,
                        "artifact_rejected",
                        "Workspace file could not be opened safely.",
                    ) from exc
                with os.fdopen(descriptor, "rb") as stream:
                    opened = os.fstat(stream.fileno())
                    if (
                        not stat.S_ISREG(opened.st_mode)
                        or (opened.st_dev, opened.st_ino) != (info.st_dev, info.st_ino)
                        or opened.st_size != info.st_size
                    ):
                        raise RequestError(
                            422,
                            "artifact_rejected",
                            "Workspace file changed during collection.",
                        )
                    data = stream.read(ARTIFACT_BYTES + 1)
                if len(data) != info.st_size:
                    raise RequestError(
                        422,
                        "artifact_rejected",
                        "Workspace file changed during collection.",
                    )
                if any(marker in data for marker in SECRET_MARKERS):
                    raise RequestError(
                        422,
                        "artifact_rejected",
                        "Workspace contains credential material.",
                    )
                digest = hashlib.sha256(data).hexdigest()
                relative = path.relative_to(root).as_posix()
                entry = tarfile.TarInfo(relative)
                entry.size = len(data)
                entry.mode = info.st_mode & 0o777
                tar.addfile(entry, io.BytesIO(data))
                manifest.append(
                    {"path": relative, "size": info.st_size, "sha256": digest}
                )
    if archive.stat().st_size > ARTIFACT_BYTES:
        archive.unlink(missing_ok=True)
        raise RequestError(
            422, "artifact_rejected", "Workspace archive exceeds 100 MiB."
        )
    return manifest


def stat_regular(mode: int) -> bool:
    return stat.S_ISREG(mode)


def _inside(root: Path, path: Path) -> bool:
    try:
        path.resolve().relative_to(root)
    except ValueError:
        return False
    return True
