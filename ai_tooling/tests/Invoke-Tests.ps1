# Tests the agent tooling setup (ai_tooling/setup.ps1). Run from anywhere:
#
#   .\ai_tooling\tests\Invoke-Tests.ps1            Pester tests, schema checks, expected output,
#                                                 generated tables in ai_tooling/documentation/overview.md
#   .\ai_tooling\tests\Invoke-Tests.ps1 -InstallPester
#                                                 first download the pinned Pester into
#                                                 ai_tooling/tests/modules/ (gitignored), then test
#   .\ai_tooling\tests\Invoke-Tests.ps1 -Update    rewrite ai_tooling/tests/expected/ and the generated
#                                                 tables after an intended change of what setup.ps1
#                                                 writes, of a manifest or of a published source; review the diff
#   .\ai_tooling\tests\Invoke-Tests.ps1 -GitignoreCheck
#                                                 CI only: also runs setup.ps1 for every agent
#                                                 INTO THIS CHECKOUT and fails if git status shows
#                                                 anything. On a developer clone it would add every
#                                                 agent layout, so it refuses to run outside a build.
#
# Uses one pinned Pester ($PesterVersion below), saved into ai_tooling/tests/modules/
# like a node_modules folder: not installed for the user, the same version
# locally and in CI, never the Pester 3.4 that Windows ships. The schema check
# needs PowerShell 7 (Test-Json) and is skipped in Windows PowerShell 5.1.
# Exits 1 on any failure.

param(
    [switch]$Update,
    [switch]$GitignoreCheck,
    # Download the pinned Pester from the PowerShell Gallery into
    # ai_tooling/tests/modules/ if it is not there yet.
    [switch]$InstallPester,
    # Where to write the Pester results (NUnit XML), for CI.
    [string]$TestResultPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SetupOutput.ps1')
$RepoRoot    = $SnapshotRepoRoot
$AiDir       = $SnapshotAiDir
$Tooling     = $ToolingDirName
$ExpectedDir = Join-Path $PSScriptRoot 'expected'
$failed      = @()
# The one place the Pester version is pinned. Raising it: change it here, run
# -InstallPester, and run the tests in 5.1 and 7.
$PesterVersion = '5.9.1'
$ModulesDir    = Join-Path $PSScriptRoot 'modules'
$PesterManifest = Join-Path $ModulesDir "Pester\$PesterVersion\Pester.psd1"

Write-Host "Agent tooling tests (PowerShell $($PSVersionTable.PSVersion), $($PSVersionTable.PSEdition))"

# --- 1. Pester tests, including the schema checks of the manifests ----------
Write-Host ""
Write-Host "Pester tests"
if ($InstallPester -and -not (Test-Path $PesterManifest)) {
    Write-Host "  downloading Pester $PesterVersion from the PowerShell Gallery into $Tooling/tests/modules ..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Force -Path $ModulesDir | Out-Null
    Save-Module -Name Pester -RequiredVersion $PesterVersion -Repository PSGallery -Path $ModulesDir
}
if (-not (Test-Path $PesterManifest)) {
    Write-Host "  FAIL  Pester $PesterVersion is not in $Tooling/tests/modules. Run .\$Tooling\tests\Invoke-Tests.ps1 -InstallPester once." -ForegroundColor Red
    $failed += 'Pester not installed'
} else {
    # Another Pester already loaded (the 3.4 Windows ships) would shadow it.
    Get-Module Pester | Remove-Module -Force
    Import-Module $PesterManifest -Force
    $config = New-PesterConfiguration
    $config.Run.Path = Join-Path $PSScriptRoot 'setup.Tests.ps1'
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Normal'
    if ($TestResultPath) {
        $config.TestResult.Enabled = $true
        $config.TestResult.OutputFormat = 'NUnitXml'
        $config.TestResult.OutputPath = $TestResultPath
    }
    $result = Invoke-Pester -Configuration $config
    if ($result.FailedCount -gt 0 -or $result.Result -ne 'Passed') { $failed += "Pester: $($result.FailedCount) failed" }
    if (-not (Get-Command Test-Json -ErrorAction SilentlyContinue)) {
        Write-Host "  NOTE  schema checks skipped: Test-Json needs PowerShell 7 (pwsh -File .\$Tooling\tests\Invoke-Tests.ps1)"
    } elseif ($result.SkippedCount -gt 0) {
        # Only the schema tests and the profile tests of a manifest without
        # profiles may skip. A skip beyond those means a -Skip condition is
        # broken (it is evaluated during discovery) and a check silently stopped.
        $allowed = if (@((Read-SkillManifest $AiDir).Profiles.Keys).Count) { 0 } else { 2 }
        if ($result.SkippedCount -gt $allowed) {
            Write-Host "  FAIL  $($result.SkippedCount) test(s) skipped although Test-Json is available" -ForegroundColor Red
            $failed += "Pester: $($result.SkippedCount) skipped"
        }
    }
}

# --- 2. Expected output of every agent layout --------------------------------
Write-Host ""
Write-Host "Expected output ($Tooling/tests/expected/)"
$conflicts = Get-SnapshotEnvConflicts
if ($conflicts) {
    Write-Host "  FAIL  $($conflicts -join ', ') set (Process or User scope): it changes the generated MCP config." -ForegroundColor Red
    Write-Host "        Unset it for this run, or let CI compare."
    $failed += 'expected output: environment'
} else {
    New-Item -ItemType Directory -Force -Path $ExpectedDir | Out-Null
    foreach ($agent in $SnapshotAgents) {
        $file = Join-Path $ExpectedDir "$agent.txt"
        $actual = Get-SetupSnapshot $agent
        if ($Update) {
            [System.IO.File]::WriteAllText($file, $actual, (New-Object System.Text.UTF8Encoding $false))
            Write-Host "  OK    $agent written"
            continue
        }
        $expected = if (Test-Path $file) { [System.IO.File]::ReadAllText($file).Replace("`r`n", "`n") } else { '' }
        if ($actual -ceq $expected) {
            Write-Host "  OK    $agent"
        } else {
            Write-Host "  FAIL  $agent differs from expected/$agent.txt" -ForegroundColor Red
            $diff = Compare-Object ($expected -split "`n") ($actual -split "`n") | Select-Object -First 30
            foreach ($d in $diff) { Write-Host "        $(if ($d.SideIndicator -eq '<=') { 'expected' } else { 'actual  ' }): $($d.InputObject)" }
            Write-Host "        Intended? Run .\$Tooling\tests\Invoke-Tests.ps1 -Update and commit the new expected output."
            $failed += "expected output: $agent"
        }
    }
}

# --- 3. Tables in documentation/overview.md, generated from the manifests ----
Write-Host ""
Write-Host "Generated tables ($Tooling/documentation/overview.md)"
$readme = Join-Path $AiDir 'documentation\overview.md'
$current = [System.IO.File]::ReadAllText($readme).Replace("`r`n", "`n")
# Any roots do: the delivery table shows paths relative to them.
$sections = [ordered]@{
    'agents.json' = Format-DeliveryTable (Get-AgentLayouts $AiDir 'C:\out' 'C:\home') 'C:\out' 'C:\home'
    'skills.json' = Format-SkillInventory (Read-SkillManifest $AiDir)
}
$wanted = $current
foreach ($name in $sections.Keys) { $wanted = Set-GeneratedSection $wanted $name $sections[$name] }
if ($wanted -ceq $current) {
    Write-Host "  OK    current"
} elseif ($Update) {
    [System.IO.File]::WriteAllText($readme, $wanted, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "  OK    written"
} else {
    Write-Host "  FAIL  the tables differ from what $Tooling/manifest/agents.json and skills.json give" -ForegroundColor Red
    Write-Host "        Run .\$Tooling\tests\Invoke-Tests.ps1 -Update (or scripts\update-generated-docs.ps1) and commit documentation/overview.md."
    $failed += 'generated tables'
}

# --- 4. Generated output is gitignored (CI only) ------------------------------
if ($GitignoreCheck) {
    Write-Host ""
    Write-Host "Generated output is gitignored"
    # TF_BUILD: Azure Pipelines; GITHUB_ACTIONS: GitHub Actions; CI: most others.
    if (-not ($env:TF_BUILD -or $env:GITHUB_ACTIONS -or $env:CI)) { throw '-GitignoreCheck writes every agent layout into this clone; it runs only in CI (TF_BUILD, GITHUB_ACTIONS or CI set).' }
    $before = @(git -C $RepoRoot status --porcelain)
    if ($before) { throw "the checkout is not clean before the check:`n$($before -join "`n")" }

    $homeRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ai-tooling-home-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    try {
        $log = Invoke-SetupChild @('-Agent', 'all', '-SkipTools', '-OutputRoot', $RepoRoot, '-HomeRoot', $homeRoot)
        if ($LASTEXITCODE -ne 0) { throw "setup.ps1 failed:`n$($log -join "`n")" }

        $status = @(git -C $RepoRoot status --porcelain)
        if ($status) {
            Write-Host "  FAIL  setup.ps1 wrote files that are not gitignored:" -ForegroundColor Red
            $status | ForEach-Object { Write-Host "        $_" }
            $failed += 'gitignore'
        } else {
            Write-Host "  OK    git status is clean after setup.ps1 -Agent all"
        }

        # The home root holds what no git status can see; compare it with the
        # {HOME_ROOT} entries of the expected output.
        $actualHome = @(Get-OutputEntries $null $homeRoot | ForEach-Object { "=== $($_.Path)`n$($_.Body)" }) -join "`n"
        $expectedHome = @(foreach ($agent in $SnapshotAgents) {
            $text = [System.IO.File]::ReadAllText((Join-Path $ExpectedDir "$agent.txt")).Replace("`r`n", "`n")
            foreach ($block in ($text -split "`n(?==== )")) { if ($block -like '=== {HOME_ROOT}/*') { $block.TrimEnd("`n") } }
        }) -join "`n"
        if ($actualHome -ceq $expectedHome) {
            Write-Host "  OK    home-root output matches the expected output"
        } else {
            Write-Host "  FAIL  home-root output differs from the expected output" -ForegroundColor Red
            Compare-Object ($expectedHome -split "`n") ($actualHome -split "`n") | Select-Object -First 30 |
                ForEach-Object { Write-Host "        $(if ($_.SideIndicator -eq '<=') { 'expected' } else { 'actual  ' }): $($_.InputObject)" }
            $failed += 'home-root output'
        }
    } finally {
        Remove-FolderSafely $homeRoot
    }
}

Write-Host ""
if ($failed) {
    Write-Host "FAILED: $($failed -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "All agent tooling tests passed."
