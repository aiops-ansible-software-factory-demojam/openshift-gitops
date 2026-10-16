"""Verify direct MCP RCA, prompt limits and exclusive fallback in the shipped AO engine."""

import asyncio
import json
import sys
from pathlib import Path
from uuid import uuid4

from syntara.agent_orchestrator.models.request import InvocationCreateRequest
from syntara.workflows.models.workflow_definition import WorkflowDefinition
from syntara.workflows.utils.namespace_resolver import NamespaceResolver
from syntara.workflows.workflow_engine.activities.condition import condition
from syntara.workflows.workflow_engine.graph import WorkflowGraph
from syntara.workflows.workflow_engine.models.workflow_definition import AgenticOutput


definition = json.loads(sys.stdin.read() if sys.argv[1] == "-" else Path(sys.argv[1]).read_text())
WorkflowDefinition.model_validate(definition)
graph = WorkflowGraph.from_dict(definition)
nodes = {node["id"]: node for node in definition["nodes"]}
assert all(node["type"] != "script" for node in definition["nodes"])


def resolver_for(primary=None):
    resolver = NamespaceResolver()
    # Unbounded source fields and invocation traces must never enter prompts.
    resolver.set_namespace("trigger", {"alert_payload": {"padding": "RAW_ALERT" * 20000}})
    facts = json.dumps({"status": "observed", "events": [], "padding": "x" * 2900})
    assert len(facts) <= 3000
    resolver.set_namespace("auditlogs", {"artifacts": {
        "affected_host_facts": facts,
        "affected_host_log_output": "RAW_AUDIT" * 20000,
    }})
    if primary is not None:
        resolver.set_namespace("airca", primary)
    return resolver


def check_prompt(resolver, node_id):
    prompt = resolver.resolve_value(nodes[node_id]["parameters"]["prompt"])
    InvocationCreateRequest(prompt=prompt, session_id="validation-only", project_id=uuid4())
    assert len(prompt) < 10000
    assert not any(marker in prompt for marker in ("RAW_ALERT", "RAW_AUDIT", "TRACE_NOT_FOR_PROMPT", "${"))
    return prompt


async def main():
    resolver = resolver_for()
    check_prompt(resolver, "airca")
    if "rca_success" not in nodes:
        assert nodes["airca"]["parameters"]["tool_selection_strategy"] == "NONE"
        assert "MCP disabled" in check_prompt(resolver, "airca")
        assert [n.id for n in graph.get_next_activities_by_port("airca")] == ["createissue"]
        print("AO audit-only schema and bounded prompt passed without script nodes")
        return

    prompt = nodes["airca"]["parameters"]["prompt"]
    assert "log_path=/var/log/audit/audit.log" in prompt and "last_lines=20" in prompt
    assert "get_selinux_denials" not in prompt
    assert nodes["airca"]["parameters"]["tool_selection_strategy"] == "SELECTED"
    assert nodes["airca"]["settings"]["continue_on_failure"]
    assert nodes["airca_fallback"]["parameters"]["tool_selection_strategy"] == "NONE"
    schema = nodes["airca"]["parameters"]["response_schema"]
    assert schema["properties"]["rca"] == nodes["airca_fallback"]["parameters"]["response_schema"]
    assert not any(e["from"]==definition["triggers"][0]["id"] and e["to"]=="auditlogs" for e in definition["edges"])
    assert "${auditlogs" not in nodes["airca"]["parameters"]["prompt"]
    rca = {"rootCause": "Observed audit denial", "escalateTo": "Server Engineer", "remediationSteps": []}
    for status, audit_available in (("completed", True), ("completed", False), ("failed", False), ("cancelled", False)):
        primary = AgenticOutput().dump()
        primary.update(status=status)
        if status == "completed":
            primary["result"] = {"content": {"auditEvidenceAvailable":audit_available, "rca":rca}, "agent_trace": "TRACE_NOT_FOR_PROMPT" * 10000}
        resolver = resolver_for(primary)
        check_prompt(resolver, "airca")
        check_prompt(resolver, "airca_fallback")
        result = await condition({
            "condition": nodes["rca_success"]["parameters"]["condition"],
            "namespace": resolver.get_complete_namespace(),
        }, None)
        port = result["control"]["next_port"]
        successors = graph.get_next_activities_by_port("rca_success", port)
        assert len(successors) == 1
        if status == "completed" and audit_available:
            assert successors[0].id == "createissue"
            issue = resolver.resolve_dict(nodes["createissue"]["parameters"]["extra_vars"])
        else:
            assert successors[0].id == "auditlogs"
            assert [n.id for n in graph.get_next_activities_by_port("auditlogs")] == ["airca_fallback"]
            assert "unavailable" in check_prompt(resolver, "airca_fallback")
            resolver.set_namespace("airca_fallback", {"status": "completed", "result": {"content": rca}})
            issue_nodes = graph.get_next_activities_by_port("airca_fallback")
            assert [node.id for node in issue_nodes] == ["createissue_fallback"]
            issue = resolver.resolve_dict(nodes["createissue_fallback"]["parameters"]["extra_vars"])
        assert issue["affected_host_log_output"] == rca
    print("AO schema, invocation limit, direct MCP RCA and exclusive failure routing passed without scripts")


asyncio.run(main())
