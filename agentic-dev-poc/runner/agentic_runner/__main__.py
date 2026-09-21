"""Process entrypoint."""

from __future__ import annotations

import hashlib
import os
import ssl
import threading
from pathlib import Path

from .api import ApiServer
from .lifecycle import Engine, EngineConfig, config_hash
from .openshell import CliOpenShell
from .store import Store


def main() -> None:
    data = Path(os.environ.get("RUNNER_DATA", "/data"))
    policy = Path(os.environ.get("SANDBOX_POLICY", "/etc/agentic-poc/sandbox-policy.yaml"))
    policy_bytes = policy.read_bytes()
    policy_digest = hashlib.sha256(policy_bytes).hexdigest()
    image = os.environ["SANDBOX_IMAGE"]
    model = os.environ.get("MODEL_ID", "")
    token = os.environ["RUNNER_TOKEN"]
    cert = os.environ["RUNNER_TLS_CERT"]
    key = os.environ["RUNNER_TLS_KEY"]
    store = Store(data / "runner.sqlite")
    engine = Engine(
        store,
        CliOpenShell(),
        EngineConfig(
            image=image,
            policy_path=policy,
            policy_hash=policy_digest,
            config_hash=config_hash(image, policy_digest, model),
        ),
        data / "artifacts",
    )
    ready = threading.Event()

    def start_run(run_id: str) -> None:
        threading.Thread(target=engine.execute, args=(run_id,), daemon=True).start()

    server = ApiServer(("0.0.0.0", 8443), engine, token, start_run, ready.is_set)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(cert, key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    engine.reconcile_startup()
    ready.set()
    server.serve_forever()


if __name__ == "__main__":
    main()
