---
name: grill-with-docs
description: A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go.
disable-model-invocation: true
---

> **Watch Face Total View binding** (added at install, not upstream; MIT, see `LICENSE`). Configuration is read from
> `docs/agents/`, which `ai_tooling/setup.ps1` generates from `ai_tooling/external-skill-config/` (edit it there).
> `ai_tooling/PERMISSIONS.md` applies, also to unattended work: ask before every issue-tracker write, commit, push and
> pull request. Branches follow the rule in the root `AGENTS.md`; new files and folders go where `custom-docs-update`
> says. `/setup-matt-pocock-skills`, `/pr` and `/implement-spec` are not installed. A `custom-*` skill wins where it
> covers the task: `custom-pr-review` over `code-review`, `custom-workitem-develop` over `implement`.

Call the Skill tool twice, for "grilling" and "domain-modeling".
