# Company model and effort qualification

Use with [company Hermes setup](company-hermes.md). Qualify the deployed model
and native adapter on the work Mac. Model discovery, process completion and an
accepted artifact are different checks. Company source stays with approved
local/organization inference or real Enterprise Claude Code.

## Durable assignments

The private `.workstation/config.json` accepts optional `role_models` and
`auxiliary_models` maps. Route keys are `local` and `1` (z1); omitted entries
retain the workspace default. This is a **candidate**, requiring acceptance on
the target before adoption:

```json
{
  "role_models": {
    "zf-planner": "1",
    "zf-developer": "local",
    "zf-reviewer": "1"
  },
  "auxiliary_models": {
    "title_generation": "local",
    "memory_query_rewrite": "local",
    "profile_describer": "local",
    "review": "1",
    "background_review": "1",
    "kanban_decomposer": "1",
    "goal_judge": "1"
  }
}
```

Both installers preserve explicit assignments on refresh. Each auxiliary gets
the other eligible approved route as fallback. Vision stays local without a
fallback until another deployed vision route is qualified. Specialist main and
delegation follow the role selection. Short-context z2 is rejected here; it
remains available for bounded direct/Claude tasks. Per-card pins and running
session snapshots are separate: inspect them before changing configuration.

Dry-run `setup_work_hermes.py --from-config <private-config>`, then
`setup_work_desktop.py --from-config <private-config>` on the company-only
device. Inspect changes before adding `--apply`. Preserve explicit turn/budget
overrides, active jobs and dirty work; do not restart an active gateway. These
installers neither benchmark models nor accept recommendations automatically.

## Effort

Effort names are specific to a model and adapter. Start a bounded Enterprise
task at its account/model default; compare lower effort for supervised
classification/formatting and higher effort for difficult diagnosis or review.
Reduce scope and supply relevant evidence before raising budgets. Avoid a
global maximum-effort setting.

- Enterprise Claude Code accepts session-scoped `--effort`. Verify the installed
  CLI and resolved model; organization limits apply. The managed wrapper scrubs
  inherited `CLAUDE_CODE_*` variables, including effort, so pass the flag
  explicitly. Do not restore personal routing environment.
- Gemma's thinking control belongs to its chat template. A Claude effort flag
  does not establish that llama.cpp applied it.
- GPT-OSS supports low/medium/high reasoning; its deployed server must translate
  the request into its Harmony template. Advertised context does not enlarge
  the organization's served window.
- Inspect z1's actual server/template before assigning an effort control.
  HTTP 200 may mean an unknown option was ignored. Do not invent a Hermes YAML
  effort key or claim requested effort was effective without evidence.

Primary sources: [Claude Code model/effort configuration](https://code.claude.com/docs/en/model-config),
[Gemma thinking](https://ai.google.dev/gemma/docs/capabilities/thinking),
[GPT-OSS model card](https://huggingface.co/openai/gpt-oss-120b),
[GLM-5.3-Flash release](https://z.ai/blog/glm-5.3-flash).

## Synthetic probes

`scripts/probe_work_models.py` sends synthetic evidence serially to loopback
routes from the private config. It never executes returned tool calls or code.
Its JSON, unknown-preservation, decision, planted-defect and tool-argument
oracles run correct/incorrect controls first. Receipts include requested/served
model, context, fixture/harness hashes, wall time, numeric usage, outcomes and
requested controls. Reasoning bodies are excluded. This small direct-API smoke
test is not a general model ranking, native-agent qualification or calibration
of business judgment. It does not measure first-token latency or incremental
subscription expense.

```sh
python3 -B scripts/probe_work_models.py \
  --from-config ~/zenithflow/.workstation/config.json \
  --output ~/zenithflow/.workstation/acceptance/models/baseline.jsonl
```

The default is a dry run. Add `--run` to send inference. Existing output files
are never overwritten. Each result flushes immediately; no retries occur. The
full default sends 24 requests with a 120-second deadline each. Start with one
route and `--repeats 1` when the machine has active work. Options
`--reasoning-effort low|medium|high` and `--thinking on|off` record requested
controls, not proof they were honored. Size `--max-tokens` for reasoning;
output-limit results are separate from incorrect answers. Retain provider
errors/timeouts and compare the same cases under comparable conditions.

Then run bounded native tasks with independent acceptance in Hermes, real
Claude Code and each relevant integration. Record adapter/server revisions,
actual model, permissions, retries, context overhead and operator corrections.
Reconcile existing job IDs before retrying.

## Integrations

| Component | Verify before changing assignments |
| --- | --- |
| Hermes | Effective main/auxiliary/delegation routes, card pins, isolated failover, Triage dispatch and independently checked output |
| Paperclip | Company context, adapter environment, actual session model/effort, artifacts and heartbeat/duplicate behavior; billing labels are insufficient |
| Orca | Installed adapter, forwarded model/options and lane artifacts; company Claude dispatch is read-only with no Paperclip/edit bridge |
| AnyJev | Actual backend, named distribution, descriptive levels and scoring; uncertainty stays advisory and logprob scores are not calibrated success probabilities |

AnyJev advises route/role selection and does not replace acceptance. Avoid an
extra model call when hard context/modality/policy constraints already decide
the route. Keep Paperclip heartbeats off unless a separate bounded recurring
workflow is authorized. Never assign Hermes a Paperclip task that calls itself.
