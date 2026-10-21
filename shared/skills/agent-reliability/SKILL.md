---
name: agent-reliability
description: Design or audit coding-agent reliability experiments, acceptance checks, deadlines, retry policies and cost measurements. Use when evaluating agent infrastructure or interpreting empirical agent results.
---

# Agent reliability

Separate process termination, tool completion, artifact correctness and accepted
behavior. An exit-zero DONE without the requested file is a failure. Preserve raw
attempts privately; publish redacted metadata and reproducible checks.

Before interpreting the homelab study, read
[the dated calibration](references/study-calibration.md). Historical rates are
measurements of specific invocation profiles, task families, models and scorers.
They are not default failure probabilities for today's agents.

Use a deadline sized to the task/model and record deadline exceeded separately
from a diagnosed hang. Quiet or buffered stdout does not prove a hang. Include
stdin handling, effective cwd/PWD, runtime/config fingerprints, model identities,
permission denials, tool errors, and retained partial files in diagnosis.

Use an independent executable oracle when available. Test the oracle with known
correct and incorrect controls before inference. Do not execute generated code
with operator credentials; use an appropriate credential-free validator boundary.
Tool permissions and worktrees are not OS isolation.

Retry only after classifying failure and reconciling partial state. Retry-once
can be cheaper than unconditional refinement when correctness is observable.
Refinement can recover missing tool calls as well as fix content. Neither pattern
is universally best. Never duplicate an external mutation on a quiet stream or
ambiguous timeout. Redundant generation belongs in independent candidate workspaces
with a real acceptance oracle, not two workers editing the same tree.

For two independent alternative attempts with failure probability f, probability
of at least one success is 1-f². For two required independent sequential stages
with success probabilities p and q, success is p*q. Recovery/refinement requires
conditional outcome measurements. Failure independence cannot be established by
a nonsignificant test. Count all failures consistently; timeout is only one class.
If a runner waits for both jobs, do not describe it as first-success cancellation.

Report CLI attempts, model turns and HTTP requests separately. Use Wilson intervals
for binomial rates and state the sampling unit. Do not pool dependent refinement
stages as independent trials. Track total cost per accepted result, wall time,
cache read/write, retry and operator effort. If attempt cost is c and independent
success probability p, c/p already gives geometric retry cost per success.
Gateway-reported cost is not necessarily incremental subscription cash expense.

Treat provider refusals, rate limits, authentication, harness defects, validation
errors and deadlines as distinct outcomes. Preserve provider policy and user
authorization when choosing another supported model; no universal refusal-free
surface is established. Review model findings against original evidence.
