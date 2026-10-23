# Provisions the tools no agent ships, for this clone and this developer:
#
#   - copies of the npm MCP servers in the versions mcp-servers.json pins for
#     ai_tooling/npm-mcp.js (ai_tooling/mcp-packages, gitignored)
#   - the project's own tools, below (none yet)
#
#   .\ai_tooling\scripts\setup-tools.ps1
#
# ai_tooling/setup.ps1 runs it after configuring the agents (unless -SkipTools).
# It also runs on its own. Safe to re-run.
#
# This file belongs to the project: add a section per tool the project's skills
# or MCP servers need (a CLI binary, a pinned launcher package), with what it
# installs and where in the header above. Anything written into the repository
# is gitignored; anything outside it (the home folder, environment variables)
# is offered, not done: ask on the console first ([Console]::IsInputRedirected
# false), and give an agent that runs this script a switch to pass once the
# developer approved it (PERMISSIONS.md, section 5).

$ErrorActionPreference = 'Stop'

$AiDir    = Split-Path -Parent $PSScriptRoot
$RepoRoot = Split-Path -Parent $AiDir
Import-Module (Join-Path $AiDir 'lib\AgentSetup.psm1') -Force

# The npm packages mcp-servers.json starts through npm-mcp.js, in the versions
# pinned there. npm-mcp.js starts these copies with node instead of npx.
Write-Host "npm MCP servers"
$mcpSpecs = @(Get-McpNpmPackages $AiDir)
if (-not $mcpSpecs) {
    Write-Host "  --  none in mcp-servers.json"
} else {
    $missing = @(Install-McpNpmPackages $AiDir)
    if ($missing) { Write-Warning "  npm install failed for $($missing -join ', ') - those servers fall back to npx, which can exceed the 30 s connect limit of Claude Code" }
    else { Write-Host "  OK  $($mcpSpecs -join ', ') pinned in ai_tooling/mcp-packages" }
}

# ---- the project's own tools ------------------------------------------------
