---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
---

> **Watch Face Total View binding** (added at install, not upstream; MIT, see `LICENSE`). Configuration is read from
> `docs/agents/`, which `ai_tooling/setup.ps1` generates from `ai_tooling/external-skill-config/` (edit it there).
> `ai_tooling/PERMISSIONS.md` applies, also to unattended work: ask before every issue-tracker write, commit, push and
> pull request. Branches follow the rule in the root `AGENTS.md`; new files and folders go where `custom-docs-update`
> says. `/setup-matt-pocock-skills`, `/pr` and `/implement-spec` are not installed. A `custom-*` skill wins where it
> covers the task: `custom-pr-review` over `code-review`, `custom-workitem-develop` over `implement`.

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the questions you can ask _now_ without guessing at answers you haven't heard yet. Ask the whole frontier in one round: number each question and give your recommended answer. Then wait for the user's answers before the next round.

Format a round like so:

```
❓ **Q1** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>

---

❓ **Q2** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>
```

Each round the user answers reshapes the tree: settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a _later_ round, not this one.

Finding _facts_ is your job, never the user's. When a frontier question needs a fact from the environment (filesystem, tools, etc.), dispatch a sub-agent to find it; don't ask the user for anything you could look up yourself. Don't block on it: a running exploration is an unsettled prerequisite, so only the questions downstream of it wait for the sub-agent to report; ask the rest of the frontier now. The _decisions_ are the user's: put each to them and wait.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding.
