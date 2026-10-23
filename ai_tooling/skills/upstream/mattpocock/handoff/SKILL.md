---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

> **Watch Face Total View binding** (added at install, not upstream; MIT, see `LICENSE`). Configuration is read from
> `docs/agents/`, which `ai_tooling/setup.ps1` generates from `ai_tooling/external-skill-config/` (edit it there).
> `ai_tooling/PERMISSIONS.md` applies, also to unattended work: ask before every issue-tracker write, commit, push and
> pull request. Branches follow the rule in the root `AGENTS.md`; new files and folders go where `custom-docs-update`
> says. `/setup-matt-pocock-skills`, `/pr` and `/implement-spec` are not installed. A `custom-*` skill wins where it
> covers the task: `custom-pr-review` over `code-review`, `custom-workitem-develop` over `implement`.

> **What a handoff carries in this repository**, besides the summary: the work item and branch;
> what was tried and why it failed, so the next session does not try it again; the current best
> theory; the exact check commands run and their outcomes; the approvals still pending, so the
> new session asks for them again. An approval given in the old session covers nothing in the
> new one (`PERMISSIONS.md`: a yes covers that one action only).

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS - not the current workspace.

Include a "suggested skills" section in the document, naming which skills the next agent should call the Skill tool for.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
