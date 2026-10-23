# How the agent setup is built

Maintainer notes for `ai_tooling/setup.ps1` and what it publishes: why it is built this way. What
each agent gets, the skills and the profiles are in [overview.md](overview.md); the procedure for
changing the tooling is the skill `custom-aitooling-maintain`.

## Parts

| Path | What |
|------|------|
| `ai_tooling/manifest/project.json` | The project's own facts for the engine: its name and the skill prefixes (`skillPrefixes`, lowercase; the first is the main one). The engine in `lib/` is the same in every project and reads these two values from here, nowhere else. |
| `ai_tooling/manifest/agents.json` | Every agent setup knows, and where each one wants things: detection signals, skills folder and whether it gets a junction or a copy per skill (`skillLinks`), subagents folder, rules folder and format, instruction stub, pointer file, MCP file, key and HTTP field, and the facts `resolvesImports` and `readsNestedAgentsMd`. Its schema is `agents.schema.json`. |
| `ai_tooling/manifest/skills.json` | Every skill: its group (the folder `ai_tooling/skills/{group}/`), and per group the owner, source (project, or the upstream repository and ref, plus the installed commit, written by the group's next `update-*-skills.ps1` run), apps and default; plus the profiles. Its schema is `skills.schema.json`. |
| `ai_tooling/manifest/instructions.json` | Where each `ai_tooling/instructions/` file applies (globs, or `allApps`), for agents that get it as a scoped rule. |
| `ai_tooling/mcp-servers.json` | Which MCP servers, agent-neutral ([mcp.md](mcp.md)). |
| `ai_tooling/lib/AgentSetup.psm1` | How: reading the manifests, detection, publishing the skills, one writer per rule format, the MCP translation, `localversion`, `localprofile` and the hashes of the copied sources (`localsources.json`), the skill and doc-link checks, the generated tables in [overview.md](overview.md). Every input is a parameter. |
| `ai_tooling/setup.ps1` | The orchestrator: loads the manifests, publishes the skills of the chosen profile and each chosen agent's layout, runs `scripts/setup-tools.ps1`, records `localversion` and prints the `CHANGELOG.md` entries above the previous one ("What's new"). It holds no agent's paths. |
| `ai_tooling/scripts/setup-tools.ps1` | What no agent ships: the npm MCP servers `npm-mcp.js` starts, in the versions pinned in `mcp-servers.json` (`ai_tooling/mcp-packages/`), and the project's own tools (a section per tool, none by default). Runs on its own too. |
| `ai_tooling/verify-agent-setup.ps1` | Checks the source (skills against `skills.json` and their limits, routing tables, subagents, imports, MCP definitions, doc links) and the result, reading the same layouts from `agents.json`. `-SourceOnly` checks only the source, as a CI build does; `-Quick` only whether the copies still match their sources, the skill junctions, the personal MCP servers that win over the project one, and that Antigravity's global MCP file holds a JSON object, as the session-start check does ([Stale copies](#stale-copies)). It ends by running `scripts/verify-project.ps1`. |
| `ai_tooling/scripts/verify-project.ps1` | The project's own checks, run by `verify-agent-setup.ps1` after the generic ones (not with `-Quick`): every fact the setup relies on that the generic checks cannot know, for example an MCP server that must keep a privacy flag ([mcp.md](mcp.md), "Known servers"). |
| `ai_tooling/scripts/update-generated-docs.ps1` | Rewrites the generated tables in [overview.md](overview.md) (what each agent gets, the skill inventory) from `agents.json` and `skills.json`. Run it after changing either manifest; `verify-agent-setup.ps1` fails while the tables are out of date. |
| `ai_tooling/check-doc-links.ps1` | Relative links, anchors and VS Code task and launch names in the repository's own Markdown; run by verify. |

There are no unit tests and no `tests/` or `evals/` folder: the checks are `verify-agent-setup.ps1`
(also `-SourceOnly` and `-Quick`), `check-doc-links.ps1` and the generated-tables check above.
Probes against the agents are run by hand, as described below.

## Publishing the skills

**Published per skill.** Every agent wants its skills one level deep (`.claude/skills/{name}/`),
so the groups exist only in the source. Setup publishes one entry per skill of the profile: a
junction, or a copy with a `.ai-tooling-setup-copy` marker file for agents that do not follow a
junction inside their skills folder (`skillLinks` in `agents.json`). It removes what it published
earlier and the profile no longer has (also a junction left dangling by a branch switch, or one
into the `ai_tooling\skills` of a clone that was moved), and never touches a folder it did not
write: a developer's own skill in `.claude/skills/` stays, one named like a project skill is
reported instead of overwritten, and a skills folder that is the developer's own junction to
somewhere else is left alone with a warning. A copy is refreshed on every run; verify reports one
whose files differ from the source. Copilot prefers `.agents/skills`, so where the Antigravity
layout exists Copilot reads those copies, not its own junctions.

**Limits.** `verify-agent-setup.ps1` fails a skill name used in more than one group (the published
folders are flat), a description over 1024 characters (the Agent Skills specification) and a
project `SKILL.md` over 500 lines (detail goes into `references/`); an upstream `SKILL.md` over 500
lines is a warning, as it is not edited here. A skill or subagent whose name starts with one of the
`skillPrefixes` of `manifest/project.json` is the project's own; upstream skills may not start with
one.

### How skills are found

A throwaway folder with probe skills, one token each: in each agent's skills folder a real folder
and a junction per skill, a junction left dangling, a skill one group folder deeper, and each
agent's skills folder inside an app folder. A second folder had a junction as the whole
`.agents/skills`, and one skill name in `.claude/skills`, `.github/skills` and `.agents/skills`
with a different token each. Each agent listed the tokens in a fresh session, once at the start
and once after reading a file in the app folder.

| Agent | Junction per skill | Whole folder a junction | Other agents' folders | Skills in an app folder | One group deeper |
|-------|--------------------|-------------------------|-----------------------|-------------------------|------------------|
| Claude Code 2.1.289 | yes | yes | no | only once a file in the app is read | no |
| Copilot (VS Code) | yes | yes | reads `.claude/skills` and `.agents/skills` too; a name found twice is listed once, and the `.agents/skills` one wins | no | no |
| Antigravity (Gemini 3.1 Pro) | **no** | yes | no | no | not tested |
| Cursor | not tested (not installed on the test machine) | | | | |

So Antigravity and Cursor get copies (Cursor because its forum reports skills behind links not
being found after a restart), no skills are published into app folders, and the published folders
stay flat. A dangling junction is skipped without an error. Re-run the probe after a major agent
update, and record the result in `agents.json` (`$skillLinks`) and here.

**Pending probe.** Cursor's documentation and the `skills` CLI's agent table both list
`.agents/skills/` as a project skills folder Cursor reads. If a probe on a machine with Cursor
confirms it, the `.cursor/skills` copy (one folder per published skill, refreshed on every setup
run) can go: Cursor would read the `.agents/skills` copy Antigravity gets. Until then the copy
stays.

### Command-only skills

A skill with `disable-model-invocation: true` (for example `custom-decision-council`,
`grill-me`) is meant to run only when the user types it. The field is a Claude Code extension, not
part of the Agent Skills specification (agentskills.io). Whether each agent keeps such a skill out
of the list the agent picks from by itself:

| Agent | Result | Evidence |
|-------|--------|----------|
| Claude Code 2.1.295 | honours | documented; in a session of the desktop app, the seven command-only skills checked were missing from the skill list and `grilling` was listed |
| Copilot (VS Code 1.140.0, Copilot Chat 0.68.0) | honours (code, not a chat run) | the installed code leaves the skill out of the system prompt's skill list; `user-invocable` defaults to true, so it stays a `/` command; documented since VS Code 1.109 |
| Antigravity IDE 2.5.5 | not tested | not in its skills docs; its language server reads the field, but whether it filters on it is unknown |
| Cursor | not tested (not installed) | documented as honoured; a forum report (3.12.17) said it is ignored in `.agents/skills`, and the reporter could not reproduce it in an empty repository |

Gemini CLI reads only `name` and `description` (its skill loader on `main`), so it ignores the
field. Sources and quotes: the `$disableModelInvocation` notes in `agents.json`.

**Probe.** Run it in a fresh chat at the repository root, after `setup.ps1`. Tell the agent to
read no files, run no commands and load no skill, and to answer "listed" or "not listed" for
each name from its own skill list: `custom-decision-council`, `grill-me`, `ask-matt` and
`grilling` (the first three are command-only, `grilling` is not). Then ask two questions that
match no skill (what is wrong with a draft forecast, which architecture option to choose) and see
that no command-only skill is loaded to answer them. Finally type `/custom-decision-council`
and tell the agent not to run the council, only to reply with the skill's first heading. The agent
honours the field when the command-only names are "not listed", `grilling` is "listed", the two
questions load no command-only skill, and the command still loads the skill. Record the result,
with the date and the agent version, here and in `agents.json`.

## Import or copy

What setup copies follows from two facts per agent, decided in one place (`Get-AgentLayout`):

- **`resolvesImports`**: the agent follows `@file` lines in its instruction files. If it does not,
  `PERMISSIONS.md` (always on) and every `ai_tooling/instructions/` file (scoped by
  `instructions.json`) are copied into its rules folder.
- **`readsNestedAgentsMd`**: the agent reads an app folder's `AGENTS.md` by itself. If it does
  not, and no importing stub in the app folder brings it in, each app's `AGENTS.md` is copied as
  a rule scoped to that app.

Import lines in the `AGENTS.md` files are written as `[@path](path)`: a Markdown link for agents
and people that read `@...` as plain text, and an import for Claude Code, which follows the
`@path` in the link text.

### How the facts were found

A throwaway folder with a root `AGENTS.md`, `CLAUDE.md`/`GEMINI.md` stubs, an app folder with its
own `AGENTS.md` and stubs, and one token per import form: a plain `@file` line, a nested import,
`[@file](file)`, `- [file](file) @file`, and `@../shared/file` plus `[@../shared/file](../shared/file)`
from the app. Each agent opened the folder in a fresh session and listed the tokens in its
instructions, once at the start and once after reading a file in the app folder.

| Agent | Result |
|-------|--------|
| Claude Code | Follows every form, nested imports too. The app's imports load once a file in the app folder is read. Started inside the app folder, imports above the working folder are not followed (external imports). |
| Antigravity 2.5.5 | Sees the text of the root `AGENTS.md`, but follows none of its imports in any form, and loads no app `AGENTS.md`, not even after reading a file in the app folder. Whether the root text came through the `GEMINI.md` stub or because Antigravity reads `AGENTS.md` by itself was not told apart. So it gets `PERMISSIONS.md`, the instruction files and each app's `AGENTS.md` as rules (`trigger: always_on`; the app rules and the instruction files without an always-on trigger as `trigger: model_decision`, see [When app rules load](#when-app-rules-load)). |
| Copilot | Not tested; its documentation describes no import syntax. |
| Cursor | Not tested (not installed on the test machine); its documentation describes `AGENTS.md` as plain Markdown. |

Re-run the probe after a major agent update, and record the result in `agents.json`
(`$resolvesImports`) and here.

### When app rules load

The root `AGENTS.md` tells every agent to read an app's `documentation/overview.md` and
`AGENTS.md` before working on that app. That routing is what reliably brings the app rules in,
in every agent. The scoped rule setup writes for an app is a second way in, and whether it fires
depends on the agent.

**Probe.** A throwaway folder without that routing line: a root `AGENTS.md`, an `app/` and an
`app2/` folder each with its own `AGENTS.md` and `CLAUDE.md` stub, and the rules in the form
setup writes them (Antigravity: `always_on` as a control, `glob` for `app/**`, `model_decision`
for `app2/`; Copilot: `applyTo: "**"` as a control, `applyTo` for each folder). Every file held
its own token. In one chat the agent listed the tokens at the start, after reading
`app/code.txt` with its tool, and after appending a line to it; in a new chat it appended a line
to `app2/code.txt` (once with "following any project rules", once without), then listed them
again with the files it read.

| Agent | Read in `app/` | Edit in `app/` | Edit in `app2/` |
|-------|----------------|----------------|-----------------|
| Claude Code (desktop app 3.1623.0; extension 2.1.306 in Antigravity IDE 2.5.5, Opus 5.5) | the folder's `CLAUDE.md` stub, and through it its `AGENTS.md`, loads by itself | already loaded | loads by itself (the agent edited and then read the file; which of the two loaded it was not told apart) |
| Copilot (VS Code 1.142.0, `@github/copilot` 1.0.95; Auto, gpt-6-luna) | nothing loads | the model reads the matching `applyTo` file and `app/AGENTS.md` itself before editing | the same for `app2/` |
| Antigravity 2.24.0 (Gemini 4 Argon Medium) and Antigravity IDE 2.5.5 (Gemini 3.8 Flash High) | `glob` rule: nothing loads | `glob` rule: nothing loads, also with the file open in the editor | `model_decision` rule: the model reads it itself before editing, with and without being told to follow project rules |

So:

- **Claude Code**: the `CLAUDE.md` stub in each app folder.
- **Copilot**: its prompt lists every `*.instructions.md` with its description and `applyTo` and
  tells the model to read the matching ones before creating or changing a file; a file is
  attached by Copilot itself only when a matching file is attached to the chat
  (`chat.includeApplyingInstructions`, from the installed code, not tested). Nothing loads on a
  read.
- **Antigravity**: the app rules and an instruction file whose own frontmatter says
  `trigger: glob` are `trigger: model_decision`, with the globs named in the description
  (`ConvertTo-AntigravityRule`); so is an instruction file without `trigger` (below). An
  instruction file with another trigger (`always_on`) goes as it is. A `model_decision` rule puts
  its path and description into every prompt; the model reads it when it decides the rule applies.

**A rule without `trigger`.** An instruction file may carry only a `description` (the Copilot
format; an upstream skill installer can overwrite such a file, so it cannot carry a `trigger`
itself). The same probe folder had an `always_on` control, a rule with only a description worded
as a question topic, one with only a description naming `app/**`, and a `model_decision` rule for
`app2/`. In one chat the agent listed the tokens at the start, after reading `app/code.txt` and
after appending a line to it; in a second it answered a question matching the first rule's
description; in a third it appended a line to `app2/code.txt`.

| Agent | Rules list (Customizations) | Start, read, edit in `app/` | Matching question | Edit in `app2/` |
|-------|-----------------------------|-----------------------------|-------------------|-----------------|
| Antigravity 2.24.0 (Gemini 4 Argon Medium) and Antigravity IDE 2.5.5 (Gemini 3.8 Flash High) | the two rules without `trigger` are not listed, and not counted in the rules' token budget | only `AGENTS.md` and the `always_on` rule | the model knew nothing of the rule's content | the model read the `model_decision` rule before editing |

So Antigravity ignores a rule without `trigger` entirely, and such an instruction file is written
as `model_decision` too, its description and globs from `manifest/instructions.json`. An empty or
quoted value counts by its name (`trigger: ''` as none, `trigger: "glob"` as `glob`).
`setup.ps1 -Remove` also removes an Antigravity copy that an earlier version wrote as the bare
source text, without the generated marker, as long as that source has not changed since.

Re-run the probe after a major agent update, and record the result here and in `agents.json`
(`$rules`, `$stub`).

## Stale copies

Setup copies only where an agent cannot reference the source, as far as the probes above found:

| Copied | For | Why not live |
|--------|-----|--------------|
| Each skill folder | Antigravity, Cursor | Antigravity lists no junction per skill (probed); Cursor not probed, its forum reports skills behind links not found after a restart |
| `PERMISSIONS.md`, `instructions/` files | Antigravity, Copilot, Cursor | They follow no `@` imports (Antigravity probed; Copilot and Cursor by their documentation) |
| Each app's `AGENTS.md` | Antigravity, Copilot | They do not read nested `AGENTS.md` files (Antigravity probed; Copilot by its default setting) |
| `docs/agents/` from `external-skill-config/` | every agent | The upstream skills hard-code that path |
| MCP config from `mcp-servers.json` | every agent | Each agent spells it differently ([mcp.md](mcp.md)) |
| Subagent definitions | Claude Code, only when `.claude/agents/` is a real folder | A developer's own folder there is never replaced by a junction |

A copy goes stale when its source changes (an edit, a pull, a branch switch) until setup runs
again, and the version check does not see that: after checking out an older branch its `version`
is lower, while the copies still come from the newer one. So at the end of a run `setup.ps1`
records, per agent it refreshed, the SHA-256 of every source that agent got as a copy (a skill
folder as one hash over its files, also one copied because a junction could not be made; an app
folder whose name scopes an instruction rule by its presence only) in
`ai_tooling/localsources.json` (gitignored; `Get-CopiedSources` decides what counts; the
`docs/agents/` sources are refreshed in every agent's record, since every run rewrites that shared
folder). `verify-agent-setup.ps1 -Quick` hashes the same sources in the working tree and reports
per agent each one that changed, is new (a new skill of the profile, instruction file or app) or
is gone. It also checks that every skill junction of the profile is there and not dangling: an
older branch's `setup.ps1` can remove them (seen after the tooling folder was renamed). It takes a
second or two, so the session-start check in the root `AGENTS.md` runs it whenever the version is
equal or lower. On a branch whose tooling is older than the check itself nothing runs it, since
that branch's own `AGENTS.md` and scripts are loaded; the check runs again on the way back.

## Personal skills and MCP servers

`verify-agent-setup.ps1` warns when a personal skill or a non-project MCP server has the name of
a project one ([overview.md](overview.md)). The locations it reads are `personal` in
`manifest/agents.json`. What each agent's documentation says (fetched 2026-10-12), and which one
wins when the names are the same:

| Agent | Personal skills | Personal MCP servers | Which one wins |
|-------|-----------------|----------------------|----------------|
| Claude Code | `~/.claude/skills/` | `~/.claude.json`: the local scope under `projects` > `{project path}` > `mcpServers`; the user scope is also in that file | Skill: the personal one over the project one. MCP: the local scope over `.mcp.json`; the user scope loses to the project one ([skills](https://code.claude.com/docs/en/skills), [MCP](https://code.claude.com/docs/en/mcp)) |
| GitHub Copilot (VS Code) | `~/.copilot/skills/`, `~/.claude/skills/`, `~/.agents/skills/` | `mcp.json` in the VS Code user profile folder, key `servers` (the docs give no literal Windows path; `%APPDATA%\Code\User\mcp.json` is assumed) | Not documented ([skills](https://code.visualstudio.com/docs/copilot/customization/agent-skills), [MCP](https://code.visualstudio.com/docs/copilot/customization/mcp-servers)) |
| Cursor | `~/.cursor/skills/`, `~/.agents/skills/`, `~/.claude/skills/`, `~/.codex/skills/` | `~/.cursor/mcp.json`, key `mcpServers` | Not documented ([skills](https://cursor.com/docs/context/skills), [MCP](https://cursor.com/docs/context/mcp)) |
| Antigravity | `~/.gemini/config/skills/`, `~/.gemini/antigravity/skills/`, `~/.gemini/antigravity-cli/skills/` (Antigravity CLI) | `~/.gemini/config/mcp_config.json`, key `mcpServers`: the global file its docs name. Setup writes the project's servers only to the workspace file `.agents/mcp_config.json`, never to the global file; it only keeps the global file a valid JSON object (`mcp.keepValid`): while it was empty, Antigravity 2.24.0 loaded no MCP server at all. A file with comments, or one that is not valid JSON, it leaves alone | Skills: not documented ([skills](https://antigravity.google/docs/skills)). MCP: the global one over the workspace one; tested 2026-10-20 with Antigravity 2.24.0 and Antigravity IDE 2.5.5: a probe server only in `.agents/mcp_config.json` was listed and started, and a server in both ran the global one ([MCP](https://antigravity.google/docs/mcp)) |

Where the winner is not documented, verify says the agent "may use" the personal one.

## Adding an agent

1. Add its entry to `agents.json`; the order of the entries is the order of the prompt.
2. If it reads rules in a format no writer knows, add `ConvertTo-{Format}Rule`, its branch in
   `ConvertTo-Rule` and `Get-RuleFilter` in `lib/AgentSetup.psm1`, and the format to
   `agents.schema.json`.
3. Run `.\ai_tooling\scripts\update-generated-docs.ps1` (the delivery table in
   [overview.md](overview.md)), review the diff, then `.\ai_tooling\verify-agent-setup.ps1`.
4. Raise `ai_tooling/version` with a changelog entry (`custom-aitooling-maintain`, section 6).

## Why these models

The model of each role in `custom-aitooling-maintain`, section 3, and the reasoning behind it.

- **Planner** (`custom-role-planner`): opus. It does judgment and trade-offs, with few tokens.
- **Researcher** (`custom-role-researcher`): sonnet. It does much reading, and every statement carries a source, so a verifier can check it.
- **Writer** (`custom-role-writer`): sonnet, for high volume. In a pilot on documentation pages sonnet produced every statement correctly (81 of 81). For files of claims about code, sonnet beat haiku on 3 of 3 samples in a blind opus scoring: 4 wrong claims of 61 against 7 of 45, and haiku needed 2-5 times the turns, so it was not cheaper overall. The stream workers of `custom-workitem-develop` (`custom-workitem-stream-worker`) run on sonnet, since the lead session judges every report.
- **Verifier** (`custom-role-verifier`): opus. It is at least as strong as the writer; against a sonnet writer it is also a different model, so their errors are less correlated; against an opus session the fresh context is what it buys.
