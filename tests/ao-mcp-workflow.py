"""Validate workflow and failed-node fallback using the shipped AO engine."""

import asyncio
import json
import sys
from pathlib import Path

from syntara.workflows.models.workflow_definition import WorkflowDefinition
from syntara.workflows.utils.namespace_resolver import NamespaceResolver
from syntara.workflows.workflow_engine.activities.script_activity import _execute_script_common
from syntara.workflows.workflow_engine.models.workflow_definition import AgenticOutput, ScriptExecutorParameters, ScriptOutput


definition = json.loads(Path(sys.argv[1]).read_text())
WorkflowDefinition.model_validate(definition)
nodes = {node["id"]: node for node in definition["nodes"]}


async def script_output(resolver, node):
    parameters = ScriptExecutorParameters.model_validate(resolver.resolve_dict(node["parameters"]))
    output = await _execute_script_common(
        [sys.executable, "-c", parameters.code], environment=parameters.environment,
        timeout_seconds=10, max_output_bytes=8192,
    )
    assert output["return_code"] == 0 and not output["stderr"]
    return output


async def check(diagnostics=None, fixture=None):
    resolver = NamespaceResolver()
    trigger = {"alert_payload": {"status": "firing", "padding": "x" * 12000}}
    audit = {"artifacts": {"affected_host_log_output": "padding " * 2200 + " nginx AVC denial" * 20}}
    if fixture:
        outputs = {activity["activity_name"]: activity["output_data"] for activity in fixture["resources"]}
        trigger, audit = outputs["alertmanagereda"], outputs["auditlogs"]
        diagnostics = outputs["mcpdiag"]
    resolver.set_namespace("trigger", trigger)
    resolver.set_namespace("auditlogs", audit)
    evidence = await script_output(resolver, nodes["evidence"])
    assert len(evidence["stdout"]) <= 5001
    resolver.set_namespace("evidence", evidence)
    if "mcpdiag" in nodes:
        resolver.set_namespace("mcpdiag", diagnostics)
        diagnostic_prompt = resolver.resolve_value(nodes["mcpdiag"]["parameters"]["prompt"])
        assert len(diagnostic_prompt) < 10000
        try:
            summary = await script_output(resolver, nodes["mcpsummary"])
            assert len(summary["stdout"]) <= 2401
        except KeyError:
            assert nodes["mcpsummary"]["settings"]["continue_on_failure"]
            summary = ScriptOutput().dump()
            summary.update(status="failed")
        resolver.set_namespace("mcpsummary", summary)
    prompt = resolver.resolve_value(nodes["airca"]["parameters"]["prompt"])
    assert len(prompt) < 10000, len(prompt)
    assert "TRACE_NOT_FOR_PROMPT" not in prompt and "agent_trace" not in prompt
    assert "${" not in prompt
    return prompt


async def main():
    if "mcpdiag" in nodes:
        failed = AgenticOutput().dump()
        failed.update(status="failed", error="Diagnostic connection unavailable")
        prompt = await check(failed)
        assert "MCP diagnostics: None" in prompt
        success = {"status": "completed", "result": {"content": {"status": "observed",
            "observations": ["get_service_status: nginx running"], "limitations": []},
            "agent_trace": {"steps": [{"content": "TRACE_NOT_FOR_PROMPT" * 5000}]}}}
        prompt = await check(success)
        assert "get_service_status: nginx running" in prompt
        if len(sys.argv) > 2:
            await check(fixture=json.loads(Path(sys.argv[2]).read_text()))
    else:
        assert "audit-only mode" in await check()
    print("AO schema, shipped script execution, bounded prompts and failed-node fallback passed")


asyncio.run(main())
