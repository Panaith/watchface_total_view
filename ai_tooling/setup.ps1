# Sets up the AI agent tooling in this repository for whichever agent you use.
#
#   .\ai_tooling\setup.ps1                     refresh the agents set up in this clone; on the first
#                                              run, detect the installed agents and configure them
#   .\ai_tooling\setup.ps1 -Agent claude       configure one explicitly
#   .\ai_tooling\setup.ps1 -Agent claude,gemini
#   .\ai_tooling\setup.ps1 -Agent all
#   .\ai_tooling\setup.ps1 -Profile core       publish only the skills of one profile
#   .\ai_tooling\setup.ps1 -Profile default    back to every default skill
#   .\ai_tooling\setup.ps1 -Remove cursor      take one agent's layout away for good (what setup wrote only)
#   .\ai_tooling\setup.ps1 -Agent all -SkipTools -OutputRoot <dir> -HomeRoot <dir>
#                                              write the output elsewhere (for a test run)
#
# The shared, committed source of truth is this folder, ai_tooling/:
# skills/, agents/ (subagent definitions), instructions/, external-skill-config/,
# mcp-servers.json, PERMISSIONS.md and version. Which agents exist and where
# each one wants things is manifest/agents.json; which skills exist, their
# groups and the profiles is manifest/skills.json; the project's name and skill
# prefixes are manifest/project.json; how it is written is lib/AgentSetup.psm1.
# This script only puts them together. Everything it writes is GENERATED and
# gitignored. How it works: ai_tooling/documentation/overview.md.
#
# At the end of a complete run (every agent layout on disk refreshed) it copies
# version to localversion (gitignored) and prints "What's new": the
# CHANGELOG.md entries above the localversion it found before the run. At the
# start of a session the agent compares the two, as the root AGENTS.md tells
# it to, and offers to re-run this script when version is higher; afterwards
# it shows the user that section. For every agent it refreshed, it records the
# hashes of the sources that agent got as a copy in localsources.json
# (gitignored); verify-agent-setup.ps1 -Quick compares them with the working
# tree, also after a branch switch.
#
# Unless -SkipTools, it then runs ai_tooling/scripts/setup-tools.ps1 for what no
# agent ships (the pinned npm MCP servers, and the project's own tools).
#
# Safe to re-run. Check with .\ai_tooling\verify-agent-setup.ps1.

param(
    # Agent keys from ai_tooling/manifest/agents.json, or 'all'.
    [string[]]$Agent,

    # Skill profiles from ai_tooling/manifest/skills.json, plus 'default' and 'all'.
    # Remembered in ai_tooling/localprofile (gitignored), so a re-run without it
    # publishes the same skills again. Typed as -Profile; $Profile itself is
    # an automatic variable.
    [Alias('Profile')]
    [string[]]$SkillProfile,

    # Agent keys from ai_tooling/manifest/agents.json: remove what setup
    # wrote for them (skills, subagents, rules, stubs, their MCP servers) and
    # leave everything else. A run without -Agent then no longer sets them up.
    # Not with -Agent or -Profile.
    [string[]]$Remove,

    # Skip ai_tooling/scripts/setup-tools.ps1; configure agents only.
    [switch]$SkipTools,

    # Write every output that normally goes into the repository under this
    # folder instead; the sources are still read from the repository. With
    # -HomeRoot, for a test run. Needs -SkipTools.
    [string]$OutputRoot,

    # Read and write the home-folder files under this folder instead (the
    # Antigravity global MCP file setup keeps valid). Needs -SkipTools.
    [string]$HomeRoot
)

$ErrorActionPreference = 'Stop'

if ($Remove -and ($Agent -or $SkillProfile)) {
    throw '-Remove cannot be combined with -Agent or -Profile.'
}

# Tool provisioning writes to ai_tooling/mcp-packages and wherever the
# project's own tools go, which these two roots do not redirect.
if (($OutputRoot -or $HomeRoot) -and -not $SkipTools) {
    throw '-OutputRoot and -HomeRoot need -SkipTools: tool provisioning would still write outside them.'
}

Import-Module (Join-Path $PSScriptRoot 'lib\AgentSetup.psm1') -Force

$RepoRoot = Split-Path -Parent $PSScriptRoot
$AiDir    = $PSScriptRoot
$OutRoot  = Resolve-Root $OutputRoot $RepoRoot
$HomeDir  = Resolve-Root $HomeRoot $env:USERPROFILE
$Layouts  = Get-AgentLayouts $AiDir $OutRoot $HomeDir
$AgentKeys = @($Layouts.Keys)
$Project  = Read-ProjectManifest $AiDir

Write-Host "$($Project.Name) agent tooling setup"
Write-Host ""

if ($Remove) {
    $unknown = @($Remove | Where-Object { $AgentKeys -notcontains $_ })
    if ($unknown) { throw "Unknown agent '$($unknown -join "', '")'. Use $($AgentKeys -join ', ')." }
    # Every skill, so that every skill setup could have published is recognised.
    $SkillManifest = Read-SkillManifest $AiDir
    $Sources = Get-SetupSources $AiDir $OutRoot $HomeDir $SkillManifest (Resolve-SkillProfile $SkillManifest @('all'))
    foreach ($key in @($Remove | Select-Object -Unique)) {
        $layout = $Layouts[$key]
        Write-Host $layout.Name
        $r = Remove-AgentLayout $layout $Sources $OutRoot $HomeDir
        foreach ($path in $r.Removed) { Write-Host "  OK  removed $path" }
        foreach ($path in $r.Edited) { Write-Host "  OK  removed the servers setup wrote from $path" }
        foreach ($k in $r.Kept) { Write-Host "  WARN  kept $($k.Path): $($k.Reason)" }
        if (-not ($r.Removed -or $r.Edited -or $r.Kept)) { Write-Host "  --  nothing to remove" }
        Remove-LocalSourcesEntry $OutRoot $key
        Write-Host ""
    }
    return
}

if ($Agent) {
    $unknown = @($Agent | Where-Object { ($_ -ne 'all') -and ($AgentKeys -notcontains $_) })
    if ($unknown) { throw "Unknown agent '$($unknown -join "', '")'. Use $($AgentKeys -join ', ') or all." }
    if ($Agent -contains 'all') { $Agent = $AgentKeys }
} else {
    # What is set up in this clone is refreshed; what is only detected is
    # offered, not set up (a layout taken away with -Remove stays away).
    $Agent = Get-AgentsOnDisk $Layouts
    if ($Agent) {
        Write-Host "Configuring: $($Agent -join ', ')  (set up in this clone; add another with -Agent)"
        foreach ($key in @(Find-InstalledAgents $Layouts $HomeDir | Where-Object { $Agent -notcontains $_ })) {
            Write-Host "  Also found: $($Layouts[$key].Name) - not set up here; add it with -Agent $key"
        }
    } else {
        $Agent = Find-InstalledAgents $Layouts $HomeDir
        if ($Agent) {
            Write-Host "Configuring: $($Agent -join ', ')  (detected; override with -Agent)"
        } else {
            $Agent = Select-AgentsInteractively $Layouts
            if ($Agent) { Write-Host "Configuring: $($Agent -join ', ')" }
        }
    }
    if (-not $Agent) {
        Write-Warning "Nothing configured. Re-run with -Agent $($AgentKeys -join '|')|all."
        return
    }
}
Write-Host ""

$SkillManifest = Read-SkillManifest $AiDir
if (-not $SkillProfile) {
    $SkillProfile = Read-LocalProfile $OutRoot
    # A profile renamed or removed since the last run is dropped; with none
    # left, 'default': publish more, not nothing.
    $known = @('default', 'all') + @($SkillManifest.Profiles.Keys)
    $gone = @($SkillProfile | Where-Object { $known -notcontains $_ })
    if ($gone) {
        $SkillProfile = @($SkillProfile | Where-Object { $known -contains $_ })
        if (-not $SkillProfile) { $SkillProfile = @('default') }
        Write-Warning "The profile '$($gone -join "', '")' in ai_tooling/localprofile no longer exists - publishing '$($SkillProfile -join ',')'. Choose with -Profile $($known -join '|')."
    }
}
$SkillProfile = @($SkillProfile | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$SkillNames = Resolve-SkillProfile $SkillManifest $SkillProfile
Write-Host "Skills: profile $($SkillProfile -join ', ') ($($SkillNames.Count) of $($SkillManifest.Skills.Count))"
Write-Host ""

# The version of the last complete run, for "What's new" at the end.
$PreviousVersion = Read-LocalVersion $OutRoot

$Sources = Get-SetupSources $AiDir $OutRoot $HomeDir $SkillManifest $SkillNames
foreach ($key in $Agent) { Publish-AgentLayout $Layouts[$key] $Sources }
Write-LocalProfile $OutRoot $SkillProfile

# Read by the upstream Matt Pocock skills, whatever the agent.
Write-Host "External skill configuration"
$n = Publish-ExternalSkillConfig $Sources.ExternalSkillConfig $OutRoot
if ($n) { Write-Host "  OK  external-skill-config -> docs\agents ($n files)" }
else { Write-Host "  --  none (ai_tooling/external-skill-config/ is empty)" }
Write-Host ""

# What each agent got as a copy, so verify-agent-setup.ps1 -Quick can tell
# when a source changed (an edit, a pull, a branch switch) since this run.
Write-LocalSources $OutRoot $Agent $Layouts $Sources
Write-Host "Copied sources recorded in ai_tooling/$LocalSourcesName ($($Agent -join ', '))"
Write-Host ""

if ($SkipTools) {
    Write-Host "Skipping tool provisioning (-SkipTools)."
    $RecordedVersion = Write-LocalVersion $AiDir $OutRoot $Agent $Layouts
    Write-WhatsNew $AiDir $PreviousVersion $RecordedVersion
    return
}

# A tool install that stops with an error stops here too, before the version is
# recorded, so the prompt comes back.
& (Join-Path $AiDir 'scripts\setup-tools.ps1')
$RecordedVersion = Write-LocalVersion $AiDir $OutRoot $Agent $Layouts

Write-Host ""
Write-Host "Done. Next:"
Write-Host "  - Claude Code: start a session, approve the project MCP servers, run /mcp"
Write-Host "  - others: restart the IDE"
Write-Host "  - an MCP server that needs a sign-in asks for it on its first use (ai_tooling/documentation/mcp.md)"
Write-Host "  Then run .\ai_tooling\verify-agent-setup.ps1"

# Last, so the developer and the agent find it at the end of the output.
Write-WhatsNew $AiDir $PreviousVersion $RecordedVersion
