# The project's own checks, run by ai_tooling/verify-agent-setup.ps1 after its
# generic ones (not with -Quick). Dot-sourced, so it can use:
#
#   Check '{label}' {condition} '{what to do when it fails}'   a failure counts
#   Write-Host "  WARN  ..."                                  information only
#   $RepoRoot, $AiDir, $Servers (mcp-servers.json servers), $SkillManifest,
#   $SourceOnly (true in a CI run: only the committed source, no network,
#   no tools, no published layouts)
#
# This file belongs to the project. Add a check for every fact the setup relies
# on that the generic checks cannot know, each with the reason in a comment:
# a skill or instruction file an app's AGENTS.md must import, an MCP server
# that must stay declared or keep a privacy flag, a docs URL pinned to the
# version an app depends on, a tool scripts/setup-tools.ps1 provisions.
# Examples: "the web app's AGENTS.md imports the DevExtreme instructions",
# "chrome-devtools passes --no-usage-statistics", "the DevExtreme docs URL is
# pinned to the major.minor in the web app's package.json".

Write-Host "Project checks (ai_tooling/scripts/verify-project.ps1)"

# The workflow skills (custom-workitem-develop, custom-pr-review, custom-pr-respond)
# work through the GitHub CLI; its sign-in is per developer, so only warn.
if (-not $SourceOnly) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Write-Host "  WARN  gh is not on PATH - the workflow skills need the GitHub CLI" }
    else { gh auth status *> $null; if ($LASTEXITCODE -ne 0) { Write-Host "  WARN  gh is not signed in - run 'gh auth login'" } }
}
