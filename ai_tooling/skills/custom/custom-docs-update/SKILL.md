---
name: custom-docs-update
description: Keeps the Watch Face Total View documentation in sync with a change and says where every kind of document, rule or agent content belongs. Use before committing any change, when finishing a work item, when adding an app, and before you create, move or delete a documentation file or folder.
---

# Keeping the documentation in sync

**Owner:** project-owned, edited directly (see `custom-aitooling-maintain`).

Update the documentation in the **same commit** as the change. Never leave it stale.

## 1. Which document to update

| Change type | Documentation to update |
|-------------|------------------------|
| New dependency added to an app | App `overview.md` → Tech Stack |
| Installation requirement added/removed | App `overview.md` → Installations |
| Dev/debug/build workflow changed | App `overview.md` → How to Develop / Debug / Build |
| VS Code task or launch config added/changed | App `overview.md` → How to Develop / Debug / Build |
| New app added to the repo | Create `{app}/documentation/overview.md` and `{app}/AGENTS.md` (template in section 3); add the app to `documentation/overview.md` and to the Apps table in the root `AGENTS.md`, with its short name for skill names (`custom-aitooling-maintain`, section 2). `ai_tooling/setup.ps1` and `ai_tooling/verify-agent-setup.ps1` find every folder with an `AGENTS.md` by themselves |
| App removed | Remove its entries from `documentation/overview.md` and `AGENTS.md`, delete its `documentation/overview.md` and `AGENTS.md` |
| A document found outside this structure (a README section, a page under `docs/`, notes next to the code, rules in a `CLAUDE.md`) | Take it apart: move each fact to the place section 2 names (a skill, an `AGENTS.md`, an `overview.md`, a topic file), link instead of copying, then remove the old file or reduce it to a pointer and fix the links to it (`PERMISSIONS.md`, section 5: ask before deleting a file this session did not create) |
| Pipeline, variable group, secure file or service connection changed | The CI documentation (`pipelines/PIPELINES.md` for Azure Pipelines, `.github/workflows/README.md` for GitHub Actions, if the project has one); a new pitfall goes into `custom-pipeline-edit` |
| Test, lint or build convention of an app changed | The app's skill (`custom-{app}-test`, ...), not the overview |
| What an agent may do without asking | `ai_tooling/PERMISSIONS.md` only (see `custom-aitooling-maintain`) |
| An always-on rule for all apps, or for one app | Root `AGENTS.md` (only what every session needs; it stays under 60 lines), or `{app}/AGENTS.md` |
| A skill added, renamed or removed | See `custom-aitooling-maintain`, section 3 |
| A file or heading renamed, moved or removed, a VS Code task or launch config renamed | Run `.\ai_tooling\check-doc-links.ps1` and fix every link, anchor or name it reports |
| Anything under `ai_tooling/` or an app's `AGENTS.md` changed (not only `ai_tooling/documentation/` or `CHANGELOG.md`) | Raise `ai_tooling/version` by 1, once per branch, and add its entry to `ai_tooling/CHANGELOG.md` (`custom-aitooling-maintain`, section 6), so every developer's agent offers to re-run `setup.ps1` and says why. The root `AGENTS.md` alone needs no raise |
| `ai_tooling/manifest/skills.json` or `agents.json` changed | Run `.\ai_tooling\scripts\update-generated-docs.ps1` |
| A release is cut | A fresh `custom-role-verifier` pass over the agent-written documentation (overviews, topic documents): contradictions, statements that no longer match the code, pages nothing links to |

## 2. Where things go

Put every new piece of documentation, rule or agent content in the place this table names, and
change existing content where it already lives. It is the only list of places for documentation,
skills and agent rules in this repository. **Do not create new folders or new kinds of files for
it.** If nothing below fits, ask the user before creating anything.

| Content | Goes in | How to change it |
|---|---|---|
| What an agent may do without asking (approvals, sensitive data, commands, commits, deletions, secrets) | `ai_tooling/PERMISSIONS.md`, and nowhere else | `custom-aitooling-maintain`, section 4 |
| An always-on rule for the whole repo (only what every session needs) | the root `AGENTS.md` | `custom-aitooling-maintain`, section 4 |
| An always-on rule for one app: version constraints, commands, never-do | `{app}/AGENTS.md` | `custom-aitooling-maintain`, section 4 |
| A procedure, checklist, standard or set of pitfalls for one kind of task | the existing project skill for it, or a new one: `ai_tooling/skills/{group}/{name}/SKILL.md` (+ `references/`, `scripts/`) with its entry in `ai_tooling/manifest/skills.json`, named `custom-{app}-{feature}-{action}`, plus a row in a routing table | `custom-aitooling-maintain`, sections 2 and 3 |
| A subagent definition: a role, or a subagent a project skill dispatches | `ai_tooling/agents/{name}.md`: roles `custom-role-{role}`, otherwise named like a skill | `custom-aitooling-maintain`, section 3 |
| An always-on instruction file for one stack | `ai_tooling/instructions/`, imported by the app's `AGENTS.md` | `custom-aitooling-maintain`, section 4 |
| An MCP server | `ai_tooling/mcp-servers.json` | `custom-aitooling-maintain`, section 4 |
| A supported agent and where it wants things | `ai_tooling/manifest/agents.json` | `custom-aitooling-maintain`, section 4 |
| Which skills exist: group, owner, source, apps, default, and the profiles | `ai_tooling/manifest/skills.json` (all skills, upstream and project, stay in this repository) | `custom-aitooling-maintain`, section 3 |
| A tool the skills or MCP servers need, provisioned per developer | `ai_tooling/scripts/setup-tools.ps1` | `custom-aitooling-maintain`, section 1 |
| A check of the agent setup that only this project needs | `ai_tooling/scripts/verify-project.ps1` | `custom-aitooling-maintain`, section 1 |
| How the agent tooling works, for people and maintainers | `ai_tooling/documentation/overview.md` and the topic documents linked from it | this skill |
| What a setup version changed for developers | `ai_tooling/CHANGELOG.md`, one entry per `ai_tooling/version` | `custom-aitooling-maintain`, section 6 |
| Configuration read by external (non-project) skills | `ai_tooling/external-skill-config/`: the existing files only; `setup.ps1` writes the copies in `docs/agents/` | edit in place; add nothing there |
| Tech stack, installation, develop / debug / build for people | `{app}/documentation/overview.md`; repo level: `documentation/overview.md` | this skill, section 3 |
| A deeper topic or design record for one app | `{app}/documentation/{topic}.md`, linked from its `overview.md` | this skill |
| Pipeline conventions and reference tables | the CI documentation: `pipelines/PIPELINES.md` (Azure Pipelines) or `.github/workflows/README.md` (GitHub Actions) (pitfalls: `custom-pipeline-edit`) | this skill |
| First steps for a new developer | `README.md` | edit in place |
| Personal preferences and personal skills | your own agent's user folder (e.g. `~/.claude/`), never the repo | — |

Generated, gitignored and never edited by hand: `CLAUDE.md` and `GEMINI.md` (at the root and in
every app folder), `.claude/`, `.agents/`, `.cursor/`, `.github/skills/`, `.github/instructions/`,
`.github/copilot-instructions.md`, `.vscode/mcp.json`, `.mcp.json`, `docs/agents/`,
`ai_tooling/mcp-packages/`, `ai_tooling/localversion`, `ai_tooling/localprofile`,
`ai_tooling/localsources.json`, `ai_tooling/tests/modules/`, and whatever `ai_tooling/scripts/setup-tools.ps1` provisions.

- Never create a new documentation folder (`docs/...`: only the generated `docs/agents/` lives
  there; `notes/...`; a second `documentation/` level). If no row of the table fits, ask the user.
- Extend an existing document before creating a new one. A new topic file for one app goes into
  `{app}/documentation/` and is linked from that app's `overview.md`.

## 3. The two files every app has

Every app has both files, with these sections **in this order**. Keep a section even when it has
nothing to say ("none", "Nothing beyond the root `AGENTS.md` and `PERMISSIONS.md`"), so agents
and people find the same thing in the same place in every app.

**`{app}/AGENTS.md`** (for agents):

1. Title `# {app} — AI Agent Instructions`, one line saying what the file is, the line that the
   root `AGENTS.md` and `PERMISSIONS.md` apply, and the app-folder fallback block (copy it from
   any existing app).
2. `## Critical Version Constraints`: a table *Constraint | Why*. Take the versions from the app's
   own files (`package.json`, `pubspec.yaml`, `pom.xml`, `*.csproj`, the pipeline), not from
   memory.
3. `## Things AI Agents Must Never Do`
4. `## Skills`: a *When you ... | Load* table, or which upstream skills do or do not apply.
5. `## Commands`: *Prepare* (the VS Code task, if there is one), *Run*, *Unit tests*, *E2E tests*
   (if any), *Lint*, *Build*. Say "none" where there is none.
6. `## Adding or Updating Dependencies`
7. `## Agent Instruction Imports`: the `ai_tooling/instructions/` files the app imports; every app
   imports `coding-principles.md` (verify checks it).

**`{app}/documentation/overview.md`** (for people):
`## Tech Stack` · `## Installations` · `## How to Develop` · `## How to Debug` ·
`## How to Build` · `## How to Test and Lint`.

- Name VS Code tasks and launch configs **exactly** as in `.vscode/tasks.json` and
  `.vscode/launch.json`, and describe what they really do. Point to the visible `{app}: Prepare`
  task, not to the hidden steps behind it.
- An app's `README.md` is a three-line pointer to these two files, not a copy.

## 4. Writing it

- English, Markdown, relative links (they must work in the repository and wherever it is
  published, for example an Azure DevOps code wiki or GitHub Pages).
- Write each fact once and link to it from elsewhere. Do not copy a section into a second file.
- Human documentation (`overview.md`, the CI documentation) says what to do; the reasons and the
  pitfalls an agent needs while working go into the matching skill.
