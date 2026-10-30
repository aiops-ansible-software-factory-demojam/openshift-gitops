# Architecture and workflow diagrams

Checked-in **SVG**, **JPEG**, **PNG**, and **PDF** previews only. No separate
editable diagram source is kept in this folder; edit the SVG directly or replace
the raster exports after changes. Nothing here embeds credentials, runtime
hostnames, or remote assets.

| File | Purpose |
| --- | --- |
| [demo-architecture.svg](demo-architecture.svg) | Architecture — OpenShift management plane, inference and artifact inputs, virtualized RHEL production and test guests. |
| [demo-architecture.jpg](demo-architecture.jpg) | Same architecture as JPEG for slides. |
| [demo-workflow-overview.svg](demo-workflow-overview.svg) | Workflow overview — preparation and dual incident paths. |
| [demo-workflow-overview.png](demo-workflow-overview.png) | Same overview as PNG. |
| [demo-workflow.pdf](demo-workflow.pdf) | Full multi-page workflow walkthrough (prepare, nginx, Python, CVE alternatives). |

## Architecture preview

![Demo architecture](demo-architecture.svg)

[Open the SVG](demo-architecture.svg) or [JPEG](demo-architecture.jpg).

The layout takes inspiration from the
[AAP infrastructure reference](https://ansible-tmm.github.io/solution-guides/assets/images/aap-hadr-full-architecture.png):
nested boundaries, compact component groups and separate external services.
Blue outlines group the OpenShift management plane; orange outlines group virtualized
application and test hosts. These are logical service groups, not availability
zones or an HA/DR deployment. Purple marks execution and authoring, green marks
applications and data, and teal marks monitoring and runtime configuration.

Regenerate the JPEG from the SVG when architecture labels change (for example with
`resvg`/`jimp` or your usual SVG raster tool at 2200px width).

## Reading the diagrams

In the workflow diagrams, blue denotes automated work; amber denotes human-controlled gates/actions; green
marks verification/recovery; purple marks inference, artifacts or policy review;
gray marks supporting services and boundaries. Red notes identify failure handling.
Architecture arrows are schematic interactions, not an exhaustive network-policy
or secret-mount specification. Dashed architecture arrows identify configuration, inference and artifact inputs,
as well as the internal HTTP probe check. Solid arrows show runtime actions.

For a timed presentation, use the [three-presenter script](../demo-script.md).
Use the workflow PDF or overview SVG/PNG for walkthrough pages: preparation, nginx, Python, and CVE alternatives.
Application provisioning does not trigger an incident. Agent completion, PR closure,
a signature, or an OIDC login response alone does not prove production recovery.

## Source and evidence boundary

The diagrams reflect the [current-state record](../stable-demo-rehearsal.md),
[operator runbook](../invoice-lightwell-demo.md),
[AO definitions](../../cluster/automation-orchestrator/workflows/README.md), and
trusted AAP content in `demojam-ansible`. The 2026-10-28 clean run used a virtualized guest backend,
separate RHEL 9 production hosts, fresh RHEL 9/10 tests and LiteLLM/MaaS
`claude-haiku-4-5` for both consumers. The patch route and nginx recovered together.
Alternative mitigation routes have isolated fixture coverage; CNV was not used
in that dual-app run. That earlier rehearsal took 66.8 minutes. The latest
[scripted walkthrough](../demo-script.md) covers a 35-minute parallel incident run
and 79.5 minutes including reset, preparation and connectivity retries; both
measurements include operator actions.

nginx recovery is operator-launched through the existing AAP wrapper. Python
uses a reusable native `invoice_promote` approval graph. A failed independent
Python check stops orchestration; an automatic agent CI-repair loop and a native
nginx promotion workflow remain deferred. Containment stops service and leaves
the dependency vulnerable; it does not close the incident.

Keep diagram copy aligned with checked-in behavior and validate relative documentation links before publication.
