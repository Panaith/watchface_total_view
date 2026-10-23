# Checks the repository's own Markdown: every relative link and anchor
# resolves, and every VS Code task or launch configuration the docs name exists
# in .vscode/tasks.json or launch.json.
#
#   .\ai_tooling\check-doc-links.ps1
#
# Which files: the root Markdown, docs/, documentation/, pipelines/, each app's
# AGENTS.md and documentation/, every file of ai_tooling/ outside skills/
# (PERMISSIONS.md, CHANGELOG.md, documentation/, agents/, external-skill-config/)
# and the project skills (Get-DocFiles in lib/AgentSetup.psm1). Upstream skills
# and vendored files are left out. Only Markdown files git tracks are checked
# (git ls-files): add a new document to git before checking. verify-agent-setup.ps1
# runs the same check; a PR build can run this script for every pull request,
# also one that changes only Markdown.
#
# Exit code 0 when everything resolves, 1 otherwise.

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'lib\AgentSetup.psm1') -Force

$tracked = Get-TrackedFiles $RepoRoot
$docs = @(Get-DocFiles $RepoRoot $tracked)
$problems = @(Test-DocLinks $RepoRoot)

foreach ($p in $problems) { Write-Host "  FAIL  $($p.File):$($p.Line)  $($p.Problem)" -ForegroundColor Red }
if ($problems) {
    Write-Host "$($problems.Count) broken link(s) in $($docs.Count) documents." -ForegroundColor Red
    exit 1
}
Write-Host "All links, anchors and VS Code names in $($docs.Count) documents resolve." -ForegroundColor Green
exit 0
