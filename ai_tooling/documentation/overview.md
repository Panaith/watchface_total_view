# ai_tooling

**Purpose: setting up the tooling of every AI agent we use, whatever the agent, IDE or developer.**

`ai_tooling` holds everything the AI agents in this repository share: the skills, the permission
rules (`PERMISSIONS.md`), the always-on instruction files, the MCP servers and the subagent
definitions. `setup.ps1` publishes them into the folders and files each agent reads. It is
developed and maintained like the other apps, but it is **not built and not deployed**: it runs
on each developer's machine (and, if the project adds it, in the pull request build).

It was set up from the ai_tooling blueprint, which other projects share: the engine
(`lib/AgentSetup.psm1`, `setup.ps1`, `verify-agent-setup.ps1`, `check-doc-links.ps1`,
`npm-mcp.js`, `manifest/agents.json` and the schemas) is the same everywhere; everything else is
this project's.

Every agent file is one of three kinds:

| Kind | Where | Written by |
|---|---|---|
| **Source** | this folder, committed | hand, or an `update-*-skills.ps1` installer for the upstream skills |
| **Entry points** | the root `AGENTS.md` and each app's `AGENTS.md`, committed | hand |
| **Generated output** | the agents' own folders (`.claude/`, `.agents/`, `.github/skills/`, ...), the `CLAUDE.md` and `GEMINI.md` stubs, `docs/agents/`; all gitignored | `setup.ps1` |

A file that is none of these is in the wrong place.

The procedure for changing the tooling (a new skill, a rule, an MCP server, the setup version)
is the skill `custom-aitooling-maintain`. Where new documentation, rules or agent content go
is "Where things go" in the skill `custom-docs-update`.

## Tech Stack

- **Windows only**: the scripts use junctions (`mklink /J`), `cmd` for the `npx` fallback of the
  MCP launcher, `%APPDATA%` and `USERPROFILE`. On macOS or Linux, set up no agent through it.
- **PowerShell**: Windows PowerShell 5.1 and PowerShell 7. `setup.ps1` is a short orchestrator;
  the functions are in `lib/AgentSetup.psm1`, the per-agent facts in `manifest/agents.json`, the
  skills in `manifest/skills.json`, the project's name and skill prefixes in
  `manifest/project.json`.
- **Node.js 20+** for the MCP servers started through `npm-mcp.js` or another node launcher.
- **git** for the upstream skill installers and the doc-link check.
- **Pester 5** for the tests, pinned in `tests/Invoke-Tests.ps1` and kept in `tests/modules/`
  (gitignored).
- The skills are Markdown (`SKILL.md`) in the format every agent reads. The upstream skills come
  from their own repositories through the `update-*-skills.ps1` installers.

### Supported agents

| Agent | Instructions | Skills | Rules | MCP |
|---|---|---|---|---|
| Claude Code (CLI, VS Code, JetBrains, desktop Code tab) | `CLAUDE.md` stubs (root and apps), then `AGENTS.md` and its imports | `.claude/skills/` | through the imports | `.mcp.json` |
| Antigravity | `GEMINI.md` stubs (root and apps) | `.agents/skills/` | `.agents/rules/` | `.agents/mcp_config.json` |
| GitHub Copilot (VS Code) | `AGENTS.md`, `.github/copilot-instructions.md` | `.github/skills/` | `.github/instructions/` | `.vscode/mcp.json` |
| Cursor | `AGENTS.md` (the app ones too) | `.cursor/skills/` | `.cursor/rules/` | `.cursor/mcp.json` |

Not set up: the Claude desktop chat app (it reads no repository files) and Codex. Gemini CLI
picks up the `GEMINI.md` stubs and the skills in `.agents/skills/`, but setup gives it no MCP
servers and it is not tested.

### What each agent gets

Generated from `manifest/agents.json` by `scripts/update-generated-docs.ps1`; verify fails when
it is out of date. Do not edit the table by hand.

<!-- BEGIN generated: agents.json -->
| Source | Claude Code | Gemini / Antigravity | GitHub Copilot | Cursor |
|---|---|---|---|---|
| Skills | junction per skill in `.claude/skills` | **copy** per skill in `.agents/skills` | junction per skill in `.github/skills` | **copy** per skill in `.cursor/skills` |
| Subagents | junction `.claude/agents` | **not delivered** | **not delivered** | **not delivered** |
| Root `AGENTS.md` | `CLAUDE.md` stub, import | `GEMINI.md` stub; the imports in `AGENTS.md` are **not followed** | native, plus pointer in `.github/copilot-instructions.md` | native |
| App `AGENTS.md` | `CLAUDE.md` stub in app folder, import | **copy** as app-scoped rule in `.agents/rules` | **copy** as app-scoped rule in `.github/instructions` | native |
| `PERMISSIONS.md` | import | **copy** as always-on rule in `.agents/rules` | **copy** as always-on rule in `.github/instructions` | **copy** as always-on rule in `.cursor/rules` |
| `instructions/` | import (from app `AGENTS.md`) | **copy** in `.agents/rules`, as is with a trigger other than glob, else new frontmatter | **copy** in `.github/instructions`, new frontmatter | **copy** in `.cursor/rules`, new frontmatter |
| MCP servers | `.mcp.json`, key `mcpServers` | `.agents/mcp_config.json`, key `mcpServers` | `.vscode/mcp.json`, key `servers` | `.cursor/mcp.json`, key `mcpServers` |
<!-- END generated: agents.json -->

Junctions and imports are live: an edit to a skill, `AGENTS.md` or an imported file reaches the
agent at once. Copies are snapshots until setup runs again. A skill that a branch adds or removes
reaches the published folders only with the next run; every such change raises `version`, so the
version check in the root `AGENTS.md` offers that run. A copy whose source changed without a
version raise (an edit, a pull, a branch switch) is found by `verify-agent-setup.ps1 -Quick`,
which compares it with the hashes `setup.ps1` recorded in `localsources.json`; the session-start
check runs it when the version is equal or lower. Why the delivery differs per agent and how that
was found: [agent-setup.md](agent-setup.md).

**The Antigravity MCP config is per clone.** Setup writes the MCP servers to
`.agents/mcp_config.json`, the workspace file Antigravity reads in the opened folder (gitignored).
Antigravity's global file `~/.gemini/config/mcp_config.json` wins over it on a name clash, so
`verify-agent-setup.ps1`, `-Quick` too, names any server there that has a project server's name.
Setup keeps that global file a JSON object, at least `{ "mcpServers": {} }`: while it was empty,
Antigravity loaded no MCP server at all ([mcp.md](mcp.md#antigravity-users)).

The upstream Matt Pocock skills read their configuration from `docs/agents/`, a path they
hard-code. Its source is `external-skill-config/`; `setup.ps1` writes the copies there for every
agent.

### Skills

Every skill lives in `skills/{group}/{name}/` and has an entry in `manifest/skills.json`; nothing
else lists or counts them. Generated from `skills.json` by `scripts/update-generated-docs.ps1`;
verify fails when it is out of date. Do not edit the tables by hand.

<!-- BEGIN generated: skills.json -->
33 skills in 3 groups.

| Group (`ai_tooling/skills/{group}/`) | Skills | Owner | Source | Apps | Default |
|---|---|---|---|---|---|
| `upstream/mattpocock` | 24: `ask-matt`, `codebase-design`, `code-review`, `diagnosing-bugs`, `domain-modeling`, `grilling`, `grill-me`, `grill-with-docs`, `handoff`, `implement`, `improve-codebase-architecture`, `prototype`, `research`, `retro`, `tdd`, `teach`, `to-questionnaire`, `to-spec`, `to-tickets`, `triage`, `wait-what`, `wayfinder`, `wizard`, `writing-for-agents` | Panagiotis Sarridis | [mattpocock/skills](https://github.com/mattpocock/skills) @ `24fe0ef7`, `update-mattpocock-skills.ps1` | all | yes |
| `custom` | 7: `custom-aitooling-maintain`, `custom-decision-council`, `custom-docs-update`, `custom-pipeline-edit`, `custom-pr-respond`, `custom-pr-review`, `custom-workitem-develop` | Panagiotis Sarridis | project | all | yes |
| `custom-watchface` | 2: `custom-watchface-device-deploy`, `custom-watchface-wff-edit` | Panagiotis Sarridis | project | `watchface` | yes |

| Profile (`setup.ps1 -Profile`) | Groups | Skills |
|---|---|---|
| `default` | every skill with default yes | 33 |
| `all` | every group | 33 |
| `core`: Project workflow and engineering practice only | `custom`, `upstream/mattpocock` | 31 |
| `watchface`: Work on the watchface app: project workflow, engineering practice and the watchface skills | `custom`, `upstream/mattpocock`, `custom-watchface` | 33 |
<!-- END generated: skills.json -->

**Profiles.** `setup.ps1 -Profile core` publishes only that profile's groups; `default` (every
skill with default yes) and `all` are built in, and several add up. The choice is saved in
`localprofile` (gitignored), so the re-run the version check offers keeps it; `-Profile default`
goes back. Every session loads the name and description of every published skill, so a smaller
profile costs less context and leaves fewer similar descriptions to choose between.

### Upstream skills

An `upstream/{stack}` group is installed and refreshed by `update-{stack}-skills.ps1`, which calls
`Install-UpstreamSkillGroup` in `lib/AgentSetup.psm1` with the upstream repository, the folders
that hold the skills, the skills to skip and the project's binding note.
`update-mattpocock-skills.ps1` is the model. Sources used by other projects of ours:

| Stack | Repository | Skills under | Notes |
|---|---|---|---|
| Engineering practice | `https://github.com/mattpocock/skills` (MIT) | `skills/engineering`, `skills/productivity` | pin a tag (`-Ref`); skip `setup-matt-pocock-skills`, `pr`, `implement-spec`; reads `docs/agents/` |
| 4D | `https://github.com/miyako/skills` | `4d-skills` | skip the `technote-*` skills; paths in them are relative to the 4D project folder |
| DevExtreme | `https://github.com/DevExpress/agent-skills` | `plugins/dx-devextreme/skills` | pin the docs MCP server to the app's DevExtreme version |
| Angular | `https://github.com/angular/skills` | the repository root (`.`) | pairs with the `angular` MCP server |
| Nx | `https://github.com/nrwl/nx-ai-agents-config` | `skills` | skip the `nx-cloud-*` skills unless the project uses Nx Cloud |
| Flutter and Dart | `https://github.com/flutter/agent-plugins` | `skills` | Dart 3 only; pairs with the `flutter-dart` MCP server |

Check a source before adding it (`custom-aitooling-maintain`, section 5): licence, owner,
activity, and every `SKILL.md` read for commands, network calls and sentences addressed to the
agent.

## Installations

Once after cloning, from the repository root:

```powershell
.\ai_tooling\setup.ps1
```

On the first run (no agent set up yet) it detects the installed agents (or asks, or takes
`-Agent claude,gemini,copilot,cursor|all`) and publishes for each. Where there is no console to
ask on (CI, a git hook, an agent running it for you), it skips the question, so pass `-Agent`
explicitly there. The re-run the session-start version check offers runs without `-Agent` and
refreshes the agents set up in this clone; an agent installed later is listed as `Also found: ...
add it with -Agent {key}`. Unless `-SkipTools`, it also provisions what no agent ships
(`scripts/setup-tools.ps1`): the npm MCP servers in the versions pinned in `mcp-servers.json`
(`mcp-packages/`), and the project's own tools.

Then start a new agent session (Claude Code: approve the project MCP servers, run `/mcp`) or
restart the IDE, and sign in to the MCP servers that need it on their first use
([mcp.md](mcp.md)). Open the **repository root** in the IDE, not an app folder: everything is
published at the root.

**Take an agent away.** `.\ai_tooling\setup.ps1 -Remove {agent}` (`claude`, `gemini`, `copilot`,
`cursor`; several at once; not with `-Agent` or `-Profile`) removes what setup wrote for that
agent and nothing else: the skills it published, the subagent junction or files, its rule files,
the pointer file, the stubs that still hold only `@AGENTS.md`, and the MCP servers it wrote (a
file with nothing else left is deleted; the rest of a file stays), then the folders that became
empty. It prints each removed path and each kept one with the reason, for example a file changed
by hand, or a folder in use: close the IDE and run `-Remove` again. A layout removed this way
stays removed, since the re-run does not set up agents again.

## How to Develop

- Change the source in this folder, never the generated output. The procedure, the naming
  convention for skills and the checklist are in `custom-aitooling-maintain`.
- **Setup version.** `version` holds a whole number. A change to what `setup.ps1` publishes
  (anything here except `documentation/`, `CHANGELOG.md` and `tests/`, plus any app's `AGENTS.md`) raises
  it by 1, once per branch, with an entry in `CHANGELOG.md`. Each complete setup run copies it to
  `localversion` (gitignored); at the start of a session every agent compares the two, as the
  root `AGENTS.md` tells it to, and offers the re-run. The run ends with "What's new": the
  `CHANGELOG.md` entries above the `localversion` it found before.
- After editing a skill, `PERMISSIONS.md`, an instruction file or an app's `AGENTS.md` with
  Antigravity, Copilot or Cursor set up, re-run `setup.ps1`: they read copies.
- **Upstream skills** are refreshed with `.\ai_tooling\update-{stack}-skills.ps1`, which replaces
  the group's folder and records the upstream commit and a content hash of the folder in
  `manifest/skills.json`. Never hand-edit an upstream `SKILL.md`; project guidance for it goes into
  the installer's `$Binding` or `$ExtraNotes` text.
- **Project code** for the setup goes into `scripts/setup-tools.ps1` (tools) and
  `scripts/verify-project.ps1` (checks), never into an engine file.

## How to Debug

```powershell
.\ai_tooling\verify-agent-setup.ps1              # the source and every layout on disk
.\ai_tooling\verify-agent-setup.ps1 -SourceOnly  # the committed source only, as a PR build
.\ai_tooling\verify-agent-setup.ps1 -Quick       # copies against their sources, skill junctions, personal MCP servers that hide a project one
```

The full run also warns when a personal skill or a non-project MCP server on your machine has the
name of a project one, for the agents set up in this clone, and says which agent may use it
instead: rename or remove it. It reads only the names in the personal folders and config files
(the locations per agent are `personal` in `manifest/agents.json`).

Each failed check names what to do, usually "re-run `setup.ps1`". Setup never touches a folder it
did not write: a developer's own skill or subagent stays, and a file in the way is reported.

## How to Build

Not built and not deployed. Each developer runs `setup.ps1` (above). After a change to
`manifest/agents.json`, `manifest/skills.json` or anything setup publishes, run
`.\ai_tooling\tests\Invoke-Tests.ps1 -Update` (expected output and generated tables).

## How to Test and Lint

```powershell
.\ai_tooling\tests\Invoke-Tests.ps1 -InstallPester                     # once: downloads the pinned Pester
.\ai_tooling\tests\Invoke-Tests.ps1                                    # Pester, expected output, generated tables
.\ai_tooling\tests\Invoke-Tests.ps1 -Update                            # after an intended change of the output
pwsh -NoProfile -File .\ai_tooling\verify-agent-setup.ps1 -SourceOnly  # also checks the manifests against their schemas
.\ai_tooling\check-doc-links.ps1                                       # links, anchors, VS Code names in the docs
```

- **Pester tests** (`tests/setup.Tests.ps1`) test the functions in `lib/AgentSetup.psm1` against
  fixtures of a made-up project, and this project's manifests against their schemas (the schema
  tests need PowerShell 7).
- **Expected output** (`tests/expected/{agent}.txt`) is what `setup.ps1 -Agent {agent}` writes,
  normalized; it is this project's, and changes with every skill added or removed. Review its diff
  with every change.

Run a changed script in Windows PowerShell 5.1 and in PowerShell 7. A pull request build can run
the tests (`-GitignoreCheck` too) and both checks, and check the version raise
(`custom-pipeline-edit`).

## Topic documents

| Document | About |
|---|---|
| [agent-setup.md](agent-setup.md) | How the setup is built: its parts, publishing the skills, import or copy, adding an agent, and the probes behind those decisions |
| [mcp.md](mcp.md) | The MCP servers, the first sign-in, connect timeouts, known servers and how to declare them |
| [workflow-skills.md](workflow-skills.md) | The workflow skills (work items, PR review and response, pipelines, decisions) and why the subagent roles exist |
| [../CHANGELOG.md](../CHANGELOG.md) | What each setup version changed for developers |
