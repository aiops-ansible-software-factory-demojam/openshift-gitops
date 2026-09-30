#!/usr/bin/env python3
"""Keep one unique VM hostname throughout a Molecule run, including destroy."""

import fcntl
import json
import os
from pathlib import Path
import secrets
import sys


def inventory():
    ephemeral = os.environ.get("MOLECULE_EPHEMERAL_DIRECTORY")
    if not ephemeral:
        raise RuntimeError("Run molecule from the collection root to set its ephemeral directory")
    state = Path(ephemeral)
    state.mkdir(parents=True, exist_ok=True)
    run_file = state / "run-id"
    descriptor = os.open(run_file, os.O_RDWR | os.O_CREAT, 0o600)
    with os.fdopen(descriptor, "r+") as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        run_id = stream.read().strip()
        if not run_id:
            run_id = secrets.token_hex(8)
            stream.write(run_id)
    if len(run_id) != 16 or any(character not in "0123456789abcdef" for character in run_id):
        raise RuntimeError("Invalid Molecule run-id; restore it before destroying existing VMs")
    host = f"molecule-{run_id}"
    return {
        "molecule": {"hosts": [host]},
        "_meta": {"hostvars": {host: {"mp": {"kubevirt": {}}}}},
    }


if __name__ == "__main__":
    try:
        result = inventory()
        if len(sys.argv) == 3 and sys.argv[1] == "--host":
            result = result["_meta"]["hostvars"].get(sys.argv[2], {})
        elif sys.argv[1:] != ["--list"]:
            raise RuntimeError("Expected --list or --host HOST")
        print(json.dumps(result))
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
