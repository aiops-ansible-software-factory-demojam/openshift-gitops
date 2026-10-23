"""Check editor-compatible polling conditions with the installed AO engine.

Run inside the AO backend with the portable nginx workflow JSON on stdin.
Only schema, graph, expression and loop functions run; no workflow is launched.
"""
import asyncio
import json
import sys

from syntara.workflows.models.workflow_definition import WorkflowDefinition
from syntara.workflows.utils.namespace_resolver import NamespaceResolver
from syntara.workflows.workflow_engine.activities.loop import loop
from syntara.workflows.workflow_engine.graph import WorkflowGraph
from syntara.workflows.workflow_engine.unified_eval import safe_eval_with_namespace


async def main():
    definition = json.load(sys.stdin)
    WorkflowDefinition.model_validate(definition)
    graph = WorkflowGraph.from_dict(definition)
    nodes = {node['id']: node for node in definition['nodes']}
    for loop_id, poll_id, field in [('wait_pr', 'read_pr', 'ready'), ('wait_merge', 'read_merge', 'merged')]:
        node = nodes[loop_id]
        assert node['parameters']['max_iterations'] == 2880
        assert [n.id for n in graph.get_next_activities_by_port(loop_id, 'iterate')] == [poll_id]
        resolver = NamespaceResolver()
        # Do-while must enter its body before the poll has produced output.
        first = await loop({'type': 'do_while', 'current_index': 0, 'condition_result': None}, None, {})
        assert first['control']['next_port'] == 'iterate'
        for index, finished in [(1, False), (2, True)]:
            resolver.set_namespace(poll_id, {'body': {field: finished}})
            pending = safe_eval_with_namespace(node['parameters']['condition'], resolver.get_complete_namespace())
            assert pending is (not finished)
            result = await loop({'type': 'do_while', 'current_index': index, 'condition_result': pending}, None, {})
            assert result['control']['next_port'] == ('complete' if finished else 'iterate')
    assert [n.id for n in graph.get_next_activities_by_port('wait_pr', 'complete')] == ['read_candidate']
    assert [n.id for n in graph.get_next_activities_by_port('wait_merge', 'complete')] == ['approve_and_deploy']
    resolver = NamespaceResolver()
    candidate = {'head_sha': 'a' * 40, 'number': 2}
    resolver.set_namespace('read_candidate', {'body': candidate})
    # Later poll iterations cannot alter the published selection held for human review.
    resolver.set_namespace('read_pr', {'body': {'head_sha': 'b' * 40, 'number': 3}})
    for node_id in ['approve_and_deploy', 'read_merge', 'verify_deployment']:
        parameters = nodes[node_id]['parameters'].get('extra_vars', nodes[node_id]['parameters'].get('query_params'))
        reference = parameters.get('webapp_candidate_sha', parameters.get('head_sha'))
        assert resolver.resolve_value(reference) == candidate['head_sha']
    print('AO schema, graph, do-while entry/repetition/exit and immutable nginx candidate binding passed; no workflow launched.')


asyncio.run(main())
