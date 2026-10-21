# Calibration — 2026-10-21

Canonical audit and new measurements:

- [Study audit and OpenCode results](https://irregularpedia.org/ai-ml/agent-reliability-study/)
- [Original Outline study](https://outline.irregularchat.com/doc/silent-failures-sandbox-tiers-and-reliability-in-multi-agent-ai-coding-infrastructure-qd3yS20IwA)
- [Versioned research and raw new results](https://git.juntogroups.org/sac/llms-local)

E13's 400 legacy CLI attempts include 313 successes, 52 timeouts and 35 missing
files. The 21.75% combined failure rate is not a 22% hang rate; the timeout rate
is 13%. Its scorer did not enforce every requested format condition and the
parallel runner waited for both candidates. Independence was not disproved;
that does not prove independence or portability across tasks and loads.

The pasted Outline v6.5 notes E28's regime decomposition and contamination of
earlier invocation profiles; powered E29 results were not available in the audited
Git corpus. The claimed line-count hang mechanism remains a hypothesis. The new
OpenCode synthetic test produced no deadlines, with one GLM formatting miss.

E18's one-shot cost/success already included the geometric retry calculation;
dividing again overstated retry cost. Harness, instruction and pricing differences
prevent a pure model-quality comparison. E16's remote path used host SSH rather
than constructing an LXC. LXC namespaces share the host kernel; placement on
another machine changes the blast radius, not that fact. Fan-out adds orchestration,
not intrinsically stronger isolation.

New OpenCode 2.1.0 fixtures retained 81 CLI attempts and 211 assistant model turns:
80 artifacts accepted, no deadlines or session errors. Qwen and GLM behavioral
shell fixtures passed 10/10 each; exact-five-line Qwen passed 10/10, GLM 9/10.
Both refinement arms passed 10/10; a conditional GLM retry passed 1/1. Qwen Python
and owned defensive SQLite repairs passed 10/10 each. N=10 is small: 10/10 Wilson
95% interval is about 72.2–100%. Minimal benchmark prompts differ from daily global
rules. These results do not rank whole products or qualify autonomous Proxmox work.

The installed legacy RESEARCH_LOG.md, where present, remains historical evidence.
Use this correction when its older operational conclusions conflict.
