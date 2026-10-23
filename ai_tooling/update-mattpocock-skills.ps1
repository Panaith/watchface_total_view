# Refreshes Matt Pocock's engineering and productivity skills (mattpocock/skills, MIT)
# into ai_tooling/skills/upstream/mattpocock/, the group upstream/mattpocock in
# ai_tooling/manifest/skills.json.
#
#   .\ai_tooling\update-mattpocock-skills.ps1             the pinned tag
#   .\ai_tooling\update-mattpocock-skills.ps1 -Ref v1.4.0 another tag: bump it deliberately, review the diff
#
# It does NOT configure any agent: ai_tooling/setup.ps1 publishes the skills. The
# skills read their per-repo configuration from docs/agents/ (issue tracker,
# triage labels, domain docs), which setup.ps1 generates from
# ai_tooling/external-skill-config/ (edit it there).
#
# Installs every skill under skills/engineering/ and skills/productivity/ except
# the ones in $Skip, and replaces the group folder wholesale, so never hand-edit
# a SKILL.md: durable project guidance belongs in $Binding and $ExtraNotes.
# Cloning from GitHub is a command with network access: an agent asks first
# (PERMISSIONS.md, section 3).
#
# This file is the model for every other update-{stack}-skills.ps1: the same
# call to Install-UpstreamSkillGroup with that stack's repository, paths, skips
# and notes (ai_tooling/documentation/overview.md, "Upstream skills").
#
# Run ai_tooling/setup.ps1 afterwards to republish, then commit the result.

param(
    # Upstream tag. Bump it deliberately and review the diff of ai_tooling/skills/upstream/mattpocock/.
    [string]$Ref = 'v1.3.1'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\AgentSetup.psm1') -Force

# setup-matt-pocock-skills writes docs/agents/ and a block into CLAUDE.md; here
# setup.ps1 generates docs/agents/ from external-skill-config/, and CLAUDE.md is
# a generated stub. pr (writes the PR body) and implement-spec (implements a
# whole spec) overlap with custom-workitem-develop, which creates the PR and its text.
$Skip = @('setup-matt-pocock-skills', 'pr', 'implement-spec')

# The note is loaded with every skill of the group, so it stays short.
$Binding = @'
> **Watch Face Total View binding** (added at install, not upstream; MIT, see `LICENSE`). Configuration is read from
> `docs/agents/`, which `ai_tooling/setup.ps1` generates from `ai_tooling/external-skill-config/` (edit it there).
> `ai_tooling/PERMISSIONS.md` applies, also to unattended work: ask before every issue-tracker write, commit, push and
> pull request. Branches follow the rule in the root `AGENTS.md`; new files and folders go where `custom-docs-update`
> says. `/setup-matt-pocock-skills`, `/pr` and `/implement-spec` are not installed. A `custom-*` skill wins where it
> covers the task: `custom-pr-review` over `code-review`, `custom-workitem-develop` over `implement`.

'@

# Skill-specific additions to $Binding, for upstream text that names files or
# actions this repository handles differently.
$ExtraNotes = @{
    'retro' = @'
> **Where `retro`'s suggestions go here**: steering instructions into the root or an app `AGENTS.md`, never `CLAUDE.md`
> (a generated, gitignored stub); review rules into `ai_tooling/instructions/coding-principles.md` or the app's
> project skill (`CODING_STANDARDS.md` does not exist); new setup checks follow `custom-aitooling-maintain`; an app's
> `AGENTS.md` names its lint and test commands. Session logs other than the current one can hold work data: ask before
> reading them (`PERMISSIONS.md`, section 2).

'@
    'diagnosing-bugs' = @'
> **Never propose instrumentation or any other change on a production server** (`PERMISSIONS.md`, section 7).

'@
    'wizard' = @'
> **No secrets into repository files**: the generated script must not write captured values to `.env` or any file in the
> repository (`PERMISSIONS.md`, section 6).

'@
    'handoff' = @'

> **What a handoff carries in this repository**, besides the summary: the work item and branch;
> what was tried and why it failed, so the next session does not try it again; the current best
> theory; the exact check commands run and their outcomes; the approvals still pending, so the
> new session asks for them again. An approval given in the old session covers nothing in the
> new one (`PERMISSIONS.md`: a yes covers that one action only).

'@
}

Install-UpstreamSkillGroup -AiDir $PSScriptRoot -Group 'upstream/mattpocock' -Repo 'https://github.com/mattpocock/skills.git' -Ref $Ref `
    -Paths @('skills/engineering', 'skills/productivity') -Skip $Skip -Binding $Binding -ExtraNotes $ExtraNotes -CopyLicense | Out-Null

Write-Host ""
Write-Host "Done. Run .\ai_tooling\setup.ps1 to publish the skills to your agent."
