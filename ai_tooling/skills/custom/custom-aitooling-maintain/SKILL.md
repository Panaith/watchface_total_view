---
name: custom-aitooling-maintain
description: Maintains the AI agent tooling of the Watch Face Total View repository - skills, subagent roles, rules, MCP servers, the setup version and its checks. Use whenever you touch anything under ai_tooling/, PERMISSIONS.md or an AGENTS.md, create or rename a skill or rule, add an MCP server, refresh upstream skills, or fix a broken doc link.
---

# Maintaining the Watch Face Total View agent tooling

**Owner:** project-owned, edited directly.

Everything shared lives in the app `ai_tooling/` (`PERMISSIONS.md` included), plus the entry
points at fixed places: the root `AGENTS.md` and one `AGENTS.md` per app. `ai_tooling/setup.ps1`
publishes this into whatever layout each agent expects. What the app is and how to set it up,
for people: [ai_tooling/documentation/overview.md](../../../documentation/overview.md). Where
each kind of content belongs is **Where things go** in `custom-docs-update`; this skill is the
procedure for changing it.

## 1. How it is organised

Committed (the shared source):

| Path | What |
|------|------|
| `ai_tooling/PERMISSIONS.md` | What an agent may do without asking. The only place such rules are written; the root `AGENTS.md` imports it. |
| `AGENTS.md`, `{app}/AGENTS.md` | Always-on instructions: the root holds only what every session needs (under 60 lines, checked by `verify-agent-setup.ps1`); per app: version constraints, commands, routing. `ai_tooling/AGENTS.md` is the tooling app's own. |
| `ai_tooling/skills/{group}/{name}/SKILL.md` | All skills, upstream and project-owned, in one folder per group: `upstream/{stack}/` (one per installer), `custom/` (every app), `custom-{app}/` (one app). Optional `references/` and `scripts/` next to it. The format is the same for every agent. |
| `ai_tooling/manifest/skills.json` | Every skill and its group; per group the owner, source (`project`, or the upstream repository and ref, plus the installed commit and content hash, written by the group's installer), apps and default; the profiles. Its schema is `skills.schema.json`. The only place skills are listed or counted: the inventory in [the overview](../../../documentation/overview.md#skills) is generated from it. |
| `ai_tooling/manifest/project.json` | The project's name and skill prefixes, read by the engine. |
| `ai_tooling/agents/{name}.md` | Subagent definitions: the four roles and those a project skill dispatches (Claude Code only, section 3). |
| `ai_tooling/instructions/` | Always-on instruction files for one stack, or for every app (`coding-principles.md`), imported by an app `AGENTS.md`. |
| `ai_tooling/mcp-servers.json` | The MCP servers, declared once. Its schema is `mcp-servers.schema.json`. |
| `ai_tooling/manifest/agents.json` | Every agent setup supports and where each one wants things (skills folder and `skillLinks`, rules folder and format, stub, MCP file, `resolvesImports`, ...). Its schema is `agents.schema.json`. Adding an agent means adding an entry. |
| `ai_tooling/manifest/instructions.json` | Where each `ai_tooling/instructions/` file applies (globs, or `allApps`). |
| `ai_tooling/lib/AgentSetup.psm1` | The functions of the setup: detection, the skill manifest and profiles, publishing the skills, one writer per rule format, the MCP translation, `localversion`, the upstream installer, the skill and doc-link checks. |
| `ai_tooling/setup.ps1`, `ai_tooling/scripts/setup-tools.ps1` | The orchestrator, which holds no agent's paths; the tool provisioning (the pinned npm MCP servers, the project's own tools), which also runs on its own. |
| `ai_tooling/verify-agent-setup.ps1`, `ai_tooling/scripts/verify-project.ps1` | The generic checks, and the project's own checks it runs at the end. |
| `ai_tooling/check-doc-links.ps1`, `ai_tooling/scripts/update-generated-docs.ps1` | The doc-link check; the generator of the tables in the overview. |
| `ai_tooling/update-{stack}-skills.ps1`, `ai_tooling/npm-mcp.js` | The upstream skill installers (section 5); the launcher of the pinned npm MCP servers. |
| `ai_tooling/external-skill-config/` | The configuration the upstream Matt Pocock skills read; `setup.ps1` writes it to `docs/agents/`, the path they hard-code. |
| `ai_tooling/tests/` | Tests of the setup: Pester tests of the engine (`setup.Tests.ps1`), the expected output of every agent layout (`expected/`, this project's), the runner `Invoke-Tests.ps1` (section 7). |
| `ai_tooling/documentation/` | `overview.md` for people and the topic documents: why the tooling is built the way it is. |
| `ai_tooling/version` | Version of the setup, a whole number. Raised with every change to what setup publishes (section 6). |
| `ai_tooling/CHANGELOG.md` | One entry per setup version: what changed for developers. Shown when the agent offers the re-run (section 6). |

**Engine and project files.** `lib/AgentSetup.psm1`, `setup.ps1`, `verify-agent-setup.ps1`,
`check-doc-links.ps1`, `npm-mcp.js`, `manifest/agents.json`, the three schemas and the test scripts
(`tests/Invoke-Tests.ps1`, `tests/setup.Tests.ps1`, `tests/SetupOutput.ps1`) are the engine:
they hold nothing of this project and are the same in every project set up from the ai_tooling
blueprint. Everything else is this project's. A fix to the engine is a fix for every project, so
tell the user it belongs in the blueprint too; project-specific code goes into `scripts/`
(`setup-tools.ps1`, `verify-project.ps1`) or a project file, never into the engine.

Everything else an agent reads is generated by `setup.ps1` and gitignored (the list: "Where
things go" in `custom-docs-update`). Never commit it, never edit it by hand; change the source
and re-run `setup.ps1`. Which agent gets what, as import or as copy, is the table in
[the overview](../../../documentation/overview.md#what-each-agent-gets), generated from
`agents.json`; why: [agent-setup.md](../../../documentation/agent-setup.md).

Setup publishes each skill of the developer's profile on its own into every agent's skills
folder, which stays flat (`.claude/skills/{name}/`): a junction, so an edit is live at once (a new
session picks it up), or, for agents that do not follow such a junction (`skillLinks` in
`agents.json`: Antigravity, Cursor), a copy that the next run refreshes. Setup never touches a
folder it did not write, so a developer's own skill there stays. With Antigravity or Cursor set
up, re-run `setup.ps1` after editing a skill (`verify-agent-setup.ps1 -Quick` reports a copy that
is out of date). `.claude/agents/` is one junction to `ai_tooling/agents/` the same way, unless a
developer keeps personal subagents in a real folder there; then `setup.ps1` copies only the
project's files into it and removes the project's (named with a prefix from `project.json`) that
no longer exist in `ai_tooling/agents/`; so personal subagents need another prefix. An agent that
does not follow `@` imports (`resolvesImports: false`) gets `PERMISSIONS.md` and the
`ai_tooling/instructions/` files copied into its rules folder, under its own file names and
frontmatter, scoped by `instructions.json`. An agent that does not read nested `AGENTS.md` files
gets each app's `AGENTS.md` as a rule scoped to that app. Everything is generated at the
repository root, which is why developers open the root in the IDE. `setup.ps1 -Remove {agent}`
takes one agent's layout away again.

Antigravity's MCP config is the workspace file `.agents/mcp_config.json`, one per clone. Its
global file `~/.gemini/config/mcp_config.json` wins on a name clash; setup never writes the
project's servers there, keeps it valid, and verify names a server there that hides a project one
([mcp.md](../../../documentation/mcp.md)).

## 2. Naming convention for project skills

`{prefix}-{app}-{feature}-{action}`, lowercase letters, digits and hyphens only. Leave out any
part that does not apply.

| Part | Values |
|------|--------|
| `{prefix}` | a prefix from `ai_tooling/manifest/project.json`: `custom` |
| `{app}` | a short name of the app (one word, lowercase, no separators) as listed in the root `AGENTS.md`; `pipeline` for pipelines; none for `ai_tooling` and for skills every app uses |
| `{feature}` | what the skill is about, one word: `workitem`, `pr`, `forms`, `docs`, `aitooling` |
| `{action}` | what it does, one verb: `develop`, `review`, `create`, `edit`, `check`, `test`, `lint`, `build`, `update`, `maintain` |

Examples: `custom-workitem-develop` (general, no app), `custom-pipeline-edit`,
`custom-{app}-test` (no feature). Record each app's short name in the root `AGENTS.md` Apps
table when its first skill is created.

The folder name and the `name:` in the frontmatter must be identical. Upstream skills keep their
upstream names and may not start with a project prefix.

## 3. Create or change a project skill

1. **Check that it is a skill.** A skill is a procedure, checklist or set of pitfalls needed for
   one kind of task, loaded when that task comes up. A rule that must hold in every session
   belongs in `AGENTS.md` or `PERMISSIONS.md`; human setup docs belong in
   `{app}/documentation/overview.md`. Extend an existing skill if one covers the task.
2. **Create `ai_tooling/skills/{group}/{name}/SKILL.md`** (see the naming convention): group
   `custom` for every app, `custom-{app}` for one app. A new group needs an entry in
   `groups` in `ai_tooling/manifest/skills.json` (description, owner, `"source": "project"`, apps, default) and
   the profiles that should carry it. Frontmatter: `name`, and a `description` saying what it
   covers and **when to use it** - agents load a skill by matching that description, so name the
   files, commands and situations that should trigger it. Longer material goes into
   `references/*.md`, runnable helpers into `scripts/`. Nothing outside that folder.
3. **Write it agent-neutral.** Name MCP tools (`repo_pull_request_thread_write`) or CLI commands (`gh pr review`), not one agent's
   built-in tools; phrase agent-specific tips as such. Do not restate permission rules: write
   "`PERMISSIONS.md` applies" and list which steps of the skill are writes to the code host (Azure DevOps or GitHub).
4. **Move, do not copy.** If the content comes from a document, remove it there and leave a
   one-line link, so each fact lives in one place.
5. **Save as UTF-8 without a BOM.** A BOM ahead of the opening `---` hides the frontmatter from
   the loader.
6. **Register it:**
   - a routing table, "when you ..., load ...": the app's `AGENTS.md` for a skill of one app, the
     root `AGENTS.md` only for a skill every app's work can need (it stays under 60 lines); a
     command-only skill (`disable-model-invocation: true`, run only when the user types it) gets
     no row, since no agent loads it by itself;
   - its entry in `skills` in `ai_tooling/manifest/skills.json` (`{ "group": "..." }`); verify
     fails while a folder and the manifest disagree;
   - `ai_tooling/verify-agent-setup.ps1` then checks it with every other skill: no BOM, `name` =
     folder, a name unique across groups, of at most 64 characters and without `--`, a
     description of at most 1024 characters, a `compatibility` field of at most 500, a `SKILL.md`
     of at most 500 lines (detail goes into `references/`), a reference file over 100 lines
     starting with a `## Contents` list, the naming convention, and that a skill mentioning
     approvals points to `PERMISSIONS.md`;
   - regenerate the inventory and the expected output: `.\ai_tooling\tests\Invoke-Tests.ps1 -Update`
     (or only the inventory: `.\ai_tooling\scripts\update-generated-docs.ps1`).
7. Raise `ai_tooling/version` by 1 and add its `ai_tooling/CHANGELOG.md` entry (section 6).
8. Run `.\ai_tooling\setup.ps1` (it publishes the new skill) and
   `.\ai_tooling\verify-agent-setup.ps1`. Start a new session and check that the skill is listed.

**Description = triggers.** The description is the one line every session carries for the
skill: what it does in one clause, then "Use when ..." with the phrases, files and situations
that should load it. A description that summarises the steps makes an agent follow the summary
instead of the skill; keep the steps in the body. Aim for under 300 characters. After a new skill
or a changed description, try a few prompts that should load it, and one that should not, in a
fresh session.

**Baseline before an edit.** When a skill changes because an agent did something wrong, record
the failing prompt or transcript excerpt in the work item first, then edit, then run the same
prompt again in a fresh session; the pull request names both runs.

Renaming a skill: rename the folder, the `name:` and its key in `skills.json`, update every
reference (`git grep {old name}`), and tell developers to delete any personal copy in
`~/.claude/skills/{old name}/` - a personal skill with the same name takes precedence over the
project one.

**Subagent definitions.** A subagent definition lives in `ai_tooling/agents/{name}.md`, named
with a project prefix. Only agents with a `subagents` folder in `agents.json` read them (today
Claude Code, `.claude/agents/`). Frontmatter: `name` (= file name), `description` (what it is
dispatched for), an explicit `tools` list and `model`. A `tools` list without MCP tools and
without `Skill` keeps the start context small. `verify-agent-setup.ps1` checks the name, the
description, the tool list and that the published copy is current. A new definition takes effect
in a new session and raises `ai_tooling/version` (section 6).

**Roles.** Every subagent has one of four roles. The role agents `custom-role-*` are used
whenever no skill names a specialised subagent:

| Role | Agent | Model | Tools | Why this model |
|---|---|---|---|---|
| Planner | `custom-role-planner` | opus | read-only by instruction (`Bash` only to read) | judgment and trade-offs; few tokens |
| Researcher | `custom-role-researcher` | sonnet | read, web; by instruction writes only its one findings file | much reading; every statement carries a source, so a verifier can check it |
| Writer | `custom-role-writer` | sonnet | read, write, edit | high volume; the lead session and a verifier judge its output |
| Verifier | `custom-role-verifier` | opus | read-only by instruction, may run checks | at least as strong as the writer, and a fresh context |

The tool lists cannot limit `Bash` or `Write` to reading or to one path; those limits are in each
role's instructions. Every role replies with a status on its first line - `DONE`,
`DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED` - so the session can judge the reply before
reading it.

- **Against agreeing too easily**: the verifier gets the output, the sources and the writer's
  checklist, never the writer's reasoning, and runs in a fresh context. It gives one verdict per
  claim (confirmed / wrong / unverifiable) with evidence. The writer never calls its own work
  correct; the planner names the strongest argument against its recommendation.
- **Dispatch hygiene**: a brief, a diff or a source goes to the subagent as a file path, not
  pasted; a researcher or writer with an output file writes its report there and replies with the
  status and a few lines; a re-check after fixes goes to the same verifier with the fix diff and
  its earlier findings; after five fix rounds the session stops and shows the user what is open;
  no subagent dispatches subagents.
- **Changing a model** needs evidence: the same task run on both models and scored with the same
  review sheet. Record the reason in the table above.
- **Specialised subagents**: when a skill hands repeatable, context-heavy work to a fresh
  subagent, give it its own definition, named like a skill. It keeps the model and tool limits of
  its role unless the skill gives a reason. Keep its body to a few lines that point at the skill
  section to follow; the procedure stays in the skill.
- **Agents without subagent definitions** start a fresh subagent with the body of
  `ai_tooling/agents/{name}.md` as its brief.

**Groups, owners, profiles.** A group's owner reviews changes to its skills. A profile
(`setup.ps1 -Profile core`) is a set of groups; `default` (every skill with default true) and
`all` are built in, and the choice is remembered in `ai_tooling/localprofile`. A new app group goes
into the profiles of the developers who need it. A skill or group with `"default": false` stays
installed but is published only by a profile that names its group, or by `all`. A profile name
starts with a letter: PowerShell reads an unquoted `4x` as a number.

**Deprecating a skill.** Set `"status": "deprecated"` and `"replacedBy"` on its entry; it stays
published, verify warns, and it is removed (folder and entry) after one release.

**App folders.** Skills are not published into app folders (`{app}/.claude/skills/`): only
Claude Code reads them there, and only once a file in the app is read; Copilot and Antigravity do
not ([agent-setup.md](../../../documentation/agent-setup.md)). Profiles do the scoping.

## 4. Change the always-on files

- **`ai_tooling/PERMISSIONS.md`**: the only place for rules about what an agent may do without
  asking. Edit it there, never add such a rule to a skill or another document. The root
  `AGENTS.md` imports it; `setup.ps1` copies it into the rule folders of the agents that do not
  follow imports, so re-run it after a change. Never put a copy at the repository root (verify
  fails).
- **Root `AGENTS.md`**: under 60 lines, loaded in every session of every developer: the
  permissions import, the setup version check, the apps and cross-app skills (one line each), the
  rules for every change and the "never" list. Add a line only if every task needs it; otherwise
  add it to an app's `AGENTS.md`, a skill or a document, and link it.
- **`{app}/AGENTS.md`**: that app's version constraints, commands, never-do rules and routing
  table, in the section order of the template in `custom-docs-update`. Shared agent
  instructions never go into a `CLAUDE.md`, `GEMINI.md` or `.github/copilot-instructions.md`:
  those are generated per developer and gitignored.
- **Import lines** in an `AGENTS.md` are written as `[@path](path)`, for example
  `[@../ai_tooling/instructions/{file}](../ai_tooling/instructions/{file})`: a link for agents that
  read `@…` as text, an import for Claude Code ([agent-setup.md](../../../documentation/agent-setup.md)).
- **`ai_tooling/instructions/`**: an always-on instruction file for one stack. Import it from the
  app's `AGENTS.md` and add its globs and description to `ai_tooling/manifest/instructions.json`
  (otherwise Copilot and Cursor only get it on demand; verify fails on both). `coding-principles.md`
  applies to every app: every app `AGENTS.md` imports it (a new app too; the tooling app as
  `instructions/coding-principles.md`), the root `AGENTS.md` does not even name it (verify checks
  both), and its entry has `allApps`.
- **`ai_tooling/mcp-servers.json`**: the only place to add or change an MCP server
  ([mcp.md](../../../documentation/mcp.md) lists known ones and how to declare them). Use
  `${REPO_ROOT}` for paths; never an absolute path. A server on npm starts through `npm-mcp.js`
  with an exact version, which `scripts/setup-tools.ps1` installs. A server that needs a check of
  its own (a privacy flag, a pinned docs version) gets it in `scripts/verify-project.ps1`. A new
  field needs a matching entry in `mcp-servers.schema.json`.
- **`ai_tooling/manifest/agents.json`**: the only place for an agent's paths and facts. Add or
  change an agent there ([agent-setup.md](../../../documentation/agent-setup.md), "Adding an
  agent"), never in `setup.ps1` or `verify-agent-setup.ps1`; then run
  `tests/Invoke-Tests.ps1 -Update` for the expected output and the delivery table. It is engine: tell the user the
  change belongs in the blueprint too.

Every change in this section raises `ai_tooling/version` by 1, with a changelog entry, except a
change to the root `AGENTS.md` alone (section 6).

## 5. Upstream skills

Each `upstream/{stack}` group comes from one upstream repository (`skills.json`, and the inventory
in the overview). Its installer `ai_tooling/update-{stack}-skills.ps1` calls
`Install-UpstreamSkillGroup` (in `lib/AgentSetup.psm1`): it re-clones upstream, **replaces** the
group folder, puts the project's binding note after each skill's frontmatter and records the
installed commit and a content hash of the folder in `skills.json`. `update-mattpocock-skills.ps1`
is the model for a new installer. Never hand-edit an upstream `SKILL.md`:
`verify-agent-setup.ps1` compares the folder with the recorded hash and names the installer to
run. When upstream adds or drops a skill, the installer prints the entries to add to or remove
from `skills.json`: verify fails until they agree. Durable project guidance for upstream skills
belongs in the `$Binding` / `$ExtraNotes` strings inside the installer, which survive an update.

**Before adding an upstream source**, record in the group's `$comment` in `skills.json`: the owner
and licence, the date of the last commit, the star count (a floor, not a pass), and that every
`SKILL.md` was read for shell commands, network calls and sentences addressed to the agent
(`PERMISSIONS.md`, section 3). A skill that installs tools, sends data off the machine or
contradicts `PERMISSIONS.md` is left out by the installer (`$Skip`) or bound with a note that
overrides it. Running an installer clones from the network: ask first.

| Task | Command |
|------|---------|
| Check the whole setup | `.\ai_tooling\verify-agent-setup.ps1` |
| Republish after a change | `.\ai_tooling\setup.ps1` |
| Refresh one stack from upstream | `.\ai_tooling\update-{stack}-skills.ps1` |

After an update, raise `ai_tooling/version` by 1 with a changelog entry (section 6), re-run
`setup.ps1` and `verify-agent-setup.ps1`, then commit.

## 6. Setup version

`ai_tooling/version` holds one whole number, the version of the agent setup. `setup.ps1` copies it
to `ai_tooling/localversion` (gitignored) at the end of a complete run: every agent layout already
on disk was refreshed, and the script did not stop early. At the start of a session every agent
compares the two, as the root `AGENTS.md` tells it to, and offers to re-run `setup.ps1` when
`version` is higher or `localversion` is missing. That is how the other developers get a change:
nobody has to remember to re-run the script after a pull. When the version is equal or lower, the
agent runs `verify-agent-setup.ps1 -Quick` instead, which finds copies whose source changed
without a raise (an edit, a branch switch) through the hashes in `ai_tooling/localsources.json`.

- **When to raise it**: when what `setup.ps1` publishes can change. That is any change under
  `ai_tooling/` except the tooling documentation (`documentation/`, `CHANGELOG.md`) and the tests
  (`tests/`), and any change
  to an app's `{app}/AGENTS.md`. The root `AGENTS.md` needs no raise: every agent reads it
  directly through its stub. Raise it by 1, once per branch, whatever the size of the change.
- **A changelog entry with every raise**: add `## {version} — {date} — {issue}` at the top of
  `ai_tooling/CHANGELOG.md`, with a bullet or two on what changes for developers and anything they
  must do beyond the re-run. `setup.ps1` prints these entries as "What's new" at the end of the
  run, found by the number at the start of the heading; verify fails without an entry for the
  current number.
- **Higher than the target branch**: before the PR is merged, `ai_tooling/version` must be higher
  than on `master`. If another PR raised it to the same number in the meantime, git
  merges both without a conflict and the second change never reaches anyone. After merging the
  target into your branch, compare (`git show origin/master:ai_tooling/version`) and
  raise it again if needed. `custom-pr-review` checks it; a PR build can enforce it
  (`custom-pipeline-edit`).
- **Only the number**: digits and one line ending, nothing else (no BOM, no spaces, no second
  line). `verify-agent-setup.ps1` checks the format and that `localversion` is current.

## 7. Checks

Run after any change to `setup.ps1`, `ai_tooling/lib/`, `ai_tooling/manifest/`,
`mcp-servers.json` or the files setup publishes:

```powershell
.\ai_tooling\tests\Invoke-Tests.ps1              # Pester tests, expected output, generated tables
.\ai_tooling\tests\Invoke-Tests.ps1 -Update      # after an intended change of the output; review the diff
.\ai_tooling\verify-agent-setup.ps1              # the source and every layout on disk
pwsh -NoProfile -File .\ai_tooling\verify-agent-setup.ps1 -SourceOnly   # the committed source, with the schema check
.\ai_tooling\check-doc-links.ps1                 # links, anchors, VS Code names in the docs
```

| Part | What it checks |
|------|----------------|
| `setup.Tests.ps1` (Pester 5) | The functions in `lib/AgentSetup.psm1` against fixtures of a made-up project (the layouts and what each agent gets, detection, the skill manifest and profiles, publishing per skill, the rule writers, the MCP translation, `localversion` and "What's new", the copied-source hashes, `-Remove`, the upstream installer, the doc-link checks); this project's manifests against their schemas and the skill folders; `setup.ps1`'s parameters |
| `expected/{agent}.txt` | What `setup.ps1 -Agent {agent} -SkipTools` writes, generated into temp folders with `-OutputRoot` / `-HomeRoot` and compared |
| Generated tables | The delivery table and the skill inventory in the overview are what the manifests give |
| `-GitignoreCheck` | CI only: after `setup.ps1 -Agent all -SkipTools` into the checkout, `git status --porcelain` is empty |

- **The expected output is normalized text, not a copy of the generated tree**: the roots become
  `{REPO_ROOT}`, `{OUTPUT_ROOT}`, `{HOME_ROOT}`; JSON one fixed form; a junction its target; where a
  generated file ends with the content of `PERMISSIONS.md`, an `AGENTS.md` or an instruction file,
  the snapshot names the source instead. It changes with every skill added or removed: run
  `Invoke-Tests.ps1 -Update` and commit the changed `expected/` files with the change; their diff
  shows reviewers what every agent receives differently.
- **`envArgs` variables** of `mcp-servers.json` change the generated MCP config; the comparison
  stops while one is set (Process or User scope).
- **Pester** is pinned in `Invoke-Tests.ps1` (`$PesterVersion`) and kept in the gitignored
  `ai_tooling/tests/modules/`: run `Invoke-Tests.ps1 -InstallPester` once (it downloads from the
  PowerShell Gallery: ask first, `PERMISSIONS.md` section 5). The Pester 3.4 that Windows ships is
  never used. The schema tests need PowerShell 7 and are skipped in 5.1.
- **No placeholders**: verify fails while a token in double braces, a SETUP note in an HTML
  comment or a prefix placeholder in a path from the blueprint is left.
- **Schemas**: in PowerShell 7 verify checks `agents.json`, `skills.json` and `mcp-servers.json`
  against their schemas; Windows PowerShell 5.1 skips it.
- **Generated tables**: the delivery table and the skill inventory in the overview must be what
  the manifests give; `scripts/update-generated-docs.ps1` rewrites them.
- **Both PowerShell editions**: run a changed script in Windows PowerShell 5.1 and in PowerShell 7.
- **Doc links**: every relative link and anchor (GitHub's heading slugs) in the repository's own
  Markdown, and every `{app}: {name}` VS Code task or launch configuration named on a line about a
  task or launch; which documents: `Get-DocFiles` in the lib.
- **In a PR build**: run `tests/Invoke-Tests.ps1` (in 5.1 and 7, with `-GitignoreCheck`),
  `verify-agent-setup.ps1 -SourceOnly` and `check-doc-links.ps1`, and check the version raise
  (`custom-pipeline-edit`).

## 8. Work items

Work on the agent tooling is tracked as GitHub issues like any other change, as ordinary
enhancements. Grouping: none (no parent issue, label or milestone).

## 9. Never

- Never commit or hand-edit a generated path from section 1.
- Never put project-specific code into an engine file (section 1).
- Never create a new folder for agent content outside `ai_tooling/`, and never a second skills
  folder.
