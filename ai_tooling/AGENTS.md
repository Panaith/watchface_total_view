# ai_tooling — AI Agent Instructions

This file contains rules specific to **ai_tooling**, the agent tooling every agent in this
repository is set up from (not built or deployed; [documentation/overview.md](documentation/overview.md)).
The root [AGENTS.md](../AGENTS.md) and [PERMISSIONS.md](PERMISSIONS.md) apply here too.

**If your workspace is this folder and not the repository root** (the IDE was opened on `ai_tooling` alone):

1. Read `../AGENTS.md` and `PERMISSIONS.md` now, unless they are already in your context, and follow them.
2. Tell the user once, at the start: *opening the repository root in the IDE is recommended. The project's skills,
   MCP servers and agent rules are published only there, so some of them may be missing in this window.*

## Critical Version Constraints

| Constraint | Why |
|-----------|-----|
| Every script runs in **Windows PowerShell 5.1** and in **PowerShell 7** | Developers run `setup.ps1` in either. No `??`, ternary or `-Parallel` |
| `version` holds one whole number, and every change to what `setup.ps1` publishes raises it by 1 with a `CHANGELOG.md` entry | The session-start check in the root `AGENTS.md` compares it with `localversion` |
| An npm MCP server is pinned to an exact version in `mcp-servers.json` (the argument after `npm-mcp.js`) | A server update changes the tools every agent sees; raise it deliberately |
| Pester `5.9.1`, pinned in `tests/Invoke-Tests.ps1` | The same version locally and in CI, never the Pester 3.4 Windows ships |
| `lib/AgentSetup.psm1`, `setup.ps1`, `verify-agent-setup.ps1`, `check-doc-links.ps1`, `npm-mcp.js`, `manifest/agents.json`, the schemas and the test scripts in `tests/` are the **engine**, the same in every project set up from the ai_tooling blueprint | A fix there is a fix for every project: make it in the blueprint too. Project code goes into `scripts/` and the project files |

## Things AI Agents Must Never Do

| Never | Why | Check |
|---|---|---|
| Edit or commit generated output (the agents' folders, the `CLAUDE.md` and `GEMINI.md` stubs, `docs/agents/`, `localversion`, `localprofile`, `localsources.json`, `mcp-packages/`) | It is overwritten by the next `setup.ps1` run; change the source here | `verify-agent-setup.ps1` (every generated path is gitignored) |
| Hand-edit an upstream `SKILL.md` under `skills/upstream/` | An installer run replaces it; project guidance goes into the installer's `$Binding` or `$ExtraNotes` text | `verify-agent-setup.ps1`: the group's folder hash against `skills.json` |
| Put an agent's paths into `setup.ps1` or `verify-agent-setup.ps1`, or an absolute path into `mcp-servers.json` | They go into `manifest/agents.json`; paths use `${REPO_ROOT}` | `verify-agent-setup.ps1` (absolute paths); the agent paths: none |
| Create a new folder or kind of file for agent content without asking | "Where things go" in `custom-docs-update` | `verify-agent-setup.ps1` (a skill folder without its entry); other kinds: none |

## Skills

| When you ... | Load |
|---|---|
| change anything in this folder, an `AGENTS.md` or `PERMISSIONS.md`, or create a skill or rule | `custom-aitooling-maintain` |
| create, move or delete a document, or finish a change | `custom-docs-update` |
| change a pipeline that runs the tooling checks | `custom-pipeline-edit` |

## Commands

From the repository root:

- **Prepare**: `.\ai_tooling\setup.ps1` (`-Agent`, `-Profile`, `-SkipTools`, `-Remove`; see the overview)
- **Run**: `.\ai_tooling\verify-agent-setup.ps1` checks the source and every layout on disk; `-Quick` only the
  copies against their sources, the skill junctions, personal MCP servers that hide a project one and Antigravity's
  global MCP file (the session-start check)
- **Unit tests**: `.\ai_tooling\tests\Invoke-Tests.ps1` (once before: `-InstallPester`, which downloads Pester: ask first;
  after an intended change of the output: `-Update`, then review the diff); run it in PowerShell 5.1 and 7
- **E2E tests**: none
- **Lint**: `.\ai_tooling\check-doc-links.ps1` and `.\ai_tooling\verify-agent-setup.ps1 -SourceOnly` (in PowerShell 7
  it also checks the manifests against their schemas)
- **Build**: none; after a manifest change, `.\ai_tooling\tests\Invoke-Tests.ps1 -Update` (expected output and generated tables)

## Adding or Updating Dependencies

Load `custom-aitooling-maintain`: an MCP server, an agent or an instruction file is in section 4, an
upstream skill set in section 5. Both raise `version` (section 6).

## Agent Instruction Imports

The coding principles apply to every change in this app.

[@instructions/coding-principles.md](instructions/coding-principles.md)
