# Rewrites the generated tables in ai_tooling/documentation/overview.md from the
# manifests: "What each agent gets" (manifest/agents.json) and the skill
# inventory (manifest/skills.json), between their
# <!-- BEGIN generated: ... --> and <!-- END generated: ... --> markers.
#
#   .\ai_tooling\scripts\update-generated-docs.ps1
#
# Run it after changing either manifest and commit the result with the change;
# verify-agent-setup.ps1 fails while the tables are out of date.

$ErrorActionPreference = 'Stop'

$AiDir = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $AiDir 'lib\AgentSetup.psm1') -Force

$overview = Join-Path $AiDir 'documentation\overview.md'
$text = [System.IO.File]::ReadAllText($overview).Replace("`r`n", "`n")
# Any roots do: the delivery table shows paths relative to them.
$wanted = Set-GeneratedSection $text 'agents.json' (Format-DeliveryTable (Get-AgentLayouts $AiDir 'C:\out' 'C:\home') 'C:\out' 'C:\home')
$wanted = Set-GeneratedSection $wanted 'skills.json' (Format-SkillInventory (Read-SkillManifest $AiDir))
if ($wanted -ceq $text) {
    Write-Host "documentation/overview.md: tables already current"
} else {
    [System.IO.File]::WriteAllText($overview, $wanted, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "documentation/overview.md: tables rewritten - review and commit the diff"
}
