"""Validate workflow and failed-node fallback using the shipped AO engine."""

import json
import sys
from pathlib import Path

from syntara.workflows.models.workflow_definition import WorkflowDefinition
from syntara.workflows.utils.namespace_resolver import NamespaceResolver
from syntara.workflows.workflow_engine.models.workflow_definition import AgenticOutput


definition = json.loads(Path(sys.argv[1]).read_text())
WorkflowDefinition.model_validate(definition)
resolver = NamespaceResolver()
resolver.set_namespace("trigger", {"alert_payload": {"status": "firing"}})
resolver.set_namespace("auditlogs", {"artifacts": {"affected_host_log_output": "nginx AVC denial"}})
node = next(node for node in definition["nodes"] if node["id"] == "airca")
if any(node["id"] == "mcpdiag" for node in definition["nodes"]):
    failed = AgenticOutput().dump()
    failed.update(status="failed", error="Diagnostic connection unavailable")
    resolver.set_namespace("mcpdiag", failed)
    prompt = resolver.resolve_value(node["parameters"]["prompt"])
    assert "nginx AVC denial" in prompt and "failed" in prompt
else:
    prompt = resolver.resolve_value(node["parameters"]["prompt"])
    assert "audit-only mode" in prompt
assert "${" not in prompt
print("AO workflow schema and downstream fallback expression resolution passed")
