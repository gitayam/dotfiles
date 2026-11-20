# Decision lenses

Select the questions relevant to this decision; do not turn every review into a
mandatory checklist. Unknown answers become a targeted discovery step.

| Lens | Questions that can change the recommendation |
| --- | --- |
| Product/customer | Which workflow or outcome is impaired? Who is affected and how often? What evidence shows demand or harm? Is the proposed feature the smallest way to meet the need? |
| Business/portfolio | What objective does this serve? What is displaced by doing it now? Is the constraint adoption, delivery, operations or missing knowledge? What changes if we wait? |
| Architecture | Which contracts, boundaries or quality attributes are involved? Is this repeated integration friction or an isolated defect? What must remain compatible during migration? Can we simplify/remove a dependency? |
| Reliability/operations | What telemetry or incident evidence exists? Is there an agreed SLO? What recurring manual work is generated? Would automation eliminate the cause or create new support work? What proves recovery remains healthy? |
| Security/privacy | What asset, trust boundary, actor and exposure are described? Is a claim supported by source or reproduction? Is a fix merely written, merged, deployed or actually verified? What immediate assessment/containment is appropriate? |
| Data/migration | Who owns schema and semantics? What happens to old data, compatibility, retries and partial failures? Are duplicate or unknown writes reconciled? What evidence makes cutover/rollback acceptable? |
| Delivery/dependencies | What is a verified blocker versus an assumption? Are CI failures causal, baseline or unrelated? Does fixing one prerequisite unlock a cluster? Is work truly parallelizable without conflicting ownership? |
| Organization/process | Is accountability missing? Are teams using different definitions of Done, ownership or acceptance? Would a policy, support process or decision record solve the problem more directly than another service? |

For a solution-shaped issue, restate its underlying need before evaluating the
solution. For example, “add an automatic retry” may express a need for recovery
from transient failure; retries, idempotency, manual reconciliation and removing
the failing dependency have different tradeoffs. This example is not evidence
about a particular repository.

Watch for misleading signals: label counts overlap; many tickets may share one
cause; age does not establish irrelevance; an assignee field does not prove
accountability; an unassigned item may still have an accountable team. An issue
snapshot is not a live atomic view, and source HEAD is not deployed behavior.
