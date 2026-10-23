---
name: custom-pipeline-edit
description: Creates or changes a GitHub Actions workflow or reusable workflow of the Watch Face Total View repo. Use whenever you touch `.github/workflows/`, add a build job, secret, variable, environment or OIDC login, or review such a change.
---

# Editing Watch Face Total View workflows

**Owner:** project-owned, edited directly (see `custom-aitooling-maintain`).

The workflow conventions of this project are in `.github/workflows/README.md`: the rules, the runners,
the secrets, variables and environments, the cloud logins and the artifact layouts. That file is the
reference for people too, so this skill does not repeat it. It tells you what to look up for the change
at hand, what to check, and what commonly goes wrong. The repository has no GitHub Actions workflows
and no `.github/workflows/README.md` yet: before the first workflow, ask the user before inventing
conventions, and offer to create that file with it.

## 1. Find where the change goes

Read `.github/workflows/README.md` first, then place the change:

| Change | Where |
|---|---|
| A new app build, or a job for one | A workflow file per app, or a job in the main workflow that only holds `needs`, `if` and `uses:` of a reusable workflow; the steps live with the app. Never add build logic to the main workflow |
| Steps needed by more than one app | A reusable workflow (`on: workflow_call`) or a composite action in `.github/actions/`, with inputs instead of copies |
| A job for one platform or stack | The app's own workflow or the matching reusable workflow, as the README describes it |
| A password, key, certificate or profile | A repository, environment or organisation secret, never YAML |
| A non-secret setting (a host name, a flag) | A repository or environment variable (`vars.NAME`), never a constant repeated in many files |
| A login to a cloud or another service | OpenID Connect (OIDC) with a federated credential, not a stored long-lived key; the job gets `permissions: id-token: write` |
| A version number | The one place the README names for it, never computed per job |
| A release or deployment | A job that targets an `environment:` (with its protection rules and reviewers); never a side effect of a build |

## 2. Checklist for every job

- Runner (`runs-on`) from the rules in the README; never a self-hosted runner that is not listed.
- A `timeout-minutes` on every job that starts a long-running or interactive process, so a hang fails
  the run instead of holding a runner (the default limit is six hours).
- `permissions:` at the workflow or job level, as narrow as possible (usually `contents: read`). The
  default `GITHUB_TOKEN` permissions of the repository may be wider than the job needs.
- Checkout through `actions/checkout`, limited with `sparse-checkout:` to the folders the job needs
  (as the README describes it for several folders), and `fetch-depth` only as deep as the job needs.
  Never a full checkout for an app build.
- Every third-party action pinned to a full commit SHA with the version in a comment
  (`uses: owner/action@<40-character sha> # v4.1.0`), never a moving tag or branch.
- Artifacts with `actions/upload-artifact` under the name the README prescribes, with the target
  directory created (`mkdir -p`) before copying, and uploaded with `if: ${{ !cancelled() }}` where the
  logs or outputs help to diagnose a failed run.
- `concurrency:` with `cancel-in-progress: true` for pull request runs, so a new push replaces the old
  run; never for deployments.
- No secrets in YAML (`PERMISSIONS.md`, section 6).

## 3. Known pitfalls

Check the change against every row that applies before handing it back.

| Pitfall | Rule |
|---------|------|
| Full repository checkout | Use `sparse-checkout:` limited to the folders the job needs: a full checkout is slow |
| A job needs a second repository | The default `GITHUB_TOKEN` is limited to the repository that runs the workflow. Check the other repository out with a second `actions/checkout` step (`repository:`, `path:`) and a fine-grained token or GitHub App token stored as a secret, with read access only |
| Hardcoded passwords, tokens or webhook URLs in YAML | Never: use a secret. A secret that a job reads must be defined in the repository, environment or organisation settings; an empty value means it is missing, not that it belongs in YAML. Secrets are not passed to workflows triggered from forks, and a reusable workflow gets them only when the caller passes them by name under `secrets:` or uses `secrets: inherit` (declaring them under `on.workflow_call.secrets` alone passes nothing) |
| Untrusted text interpolated into a `run:` script | `${{ github.event.pull_request.title }}` and similar fields are attacker-controlled and are expanded into the script (script injection). Pass them through `env:` and use the shell variable |
| `pull_request_target` or `workflow_run` combined with a checkout of the pull request's code | Runs untrusted code with write permissions and secrets. Use `pull_request` for validation; if `pull_request_target` is unavoidable, never check out or run the head's code in it |
| An action pinned to a tag or branch | A tag can be moved after review. Pin to the commit SHA, keep the version in a comment, and let Dependabot (ecosystem `github-actions`) propose the updates |
| One job doing two platforms | Split into separate jobs per platform (a matrix or separate jobs), so one failure does not hide the other and each gets the right runner |
| Publishing before creating the target directory | Always `mkdir -p` before copying artifacts |
| A tool's cache key file modified by a version step | Copy the file the cache key is computed from (`hashFiles(...)`) to a stable path before any goal that rewrites it |
| A reset command that fails with a locked-file error on the runner (for example `EBUSY`) | Delete the cache folder directly instead of using the tool's own reset |
| Signing profiles or certificates invalid after a capability change | Regenerate and re-upload them after any change of the app's capabilities, and keep signing manual where profiles are managed explicitly |
| Store or platform requirements rising yearly (target SDK, IDE or SDK version) | Look up the current requirement when touching the job and set it through an input or variable, not a stale constant |
| Build tool and runtime versions drifting apart (wrapper, JDK, Node) | Read the version the project pins (wrapper properties, `.nvmrc`, `engines`, the `*-version-file` input of the setup actions) and set the workflow's tool version from it |
| A tool exiting with 0 although it reported errors | Judge by the tool's own error output or log file, not by its exit code, and fail the step explicitly |
| A macOS job that starts an app with `open -W` hangs or leaves the process running | `open -W` can leave the started application running after the step ends. Add a `pkill` step with `if: always()` after it, and give the job a `timeout-minutes` |
| An unauthenticated download in a workflow that hits a rate limit | Anonymous API calls share a per-IP limit with every runner behind it. Authenticate the call (`GITHUB_TOKEN` for the GitHub API), or download once and cache or pre-stage the result; give the step a timeout |
| A shallow checkout lacks the history a step needs (a diff against the base branch, a commit count) | `actions/checkout` fetches one commit by default, and a three-dot or merge-base diff needs the history of both sides. Set `fetch-depth: 0`, or deepen until `git merge-base` succeeds |
| A list from the REST API stops without notice | List endpoints return 30 items per page by default and at most 100: pass `per_page=100` and follow the pages (`gh api --paginate`) |
| `#` followed by a number in a commit message or PR text links an unrelated issue or PR | GitHub links `#{number}` in commits, titles and descriptions and posts a note on the target. A script that writes commit messages writes "Nr. 6". Only `Closes #{n}` in a PR description is intended |
| A path filter that skips a validation that must run | `on.pull_request.paths` applies to changed files only: list every folder whose change must trigger the workflow, including `.github/workflows/` and the reusable workflows it calls |
| A required status check never reports because a path filter skipped the workflow | The check stays "Expected" and blocks the merge. Run the workflow always and skip inside it (a first job that decides), or add a job of the same name that passes when the filter did not match |
| A required status check named after a job that was renamed | Branch protection or a ruleset waits for the old name forever. Change the required check in the repository settings together with the rename |
| Events created with `GITHUB_TOKEN` do not start another workflow | By design (except `workflow_dispatch` and `repository_dispatch`; a `pull_request` event created with it starts a run that waits for approval). Use a GitHub App token where a follow-up run is needed |
| A scheduled or `workflow_dispatch` workflow that is not on the default branch | Scheduled runs use the file on the default branch, and the "Run workflow" button needs the workflow file to exist there (the run then uses the chosen branch's version) |

When a new pitfall is found, add a row here, not to `.github/workflows/README.md`.

## 4. Recommended PR validation for the tooling

If the project has GitHub Actions and validates pull requests, these three jobs protect the agent
tooling. They are recommendations: add them as workflows only with the user's agreement, through the
checklist above, and list them in `.github/workflows/README.md`. Make each a required status check in
the branch protection or ruleset of `master` once it is stable.

| Job | Runs | Catches |
|---|---|---|
| Agent tooling check | `ai_tooling/verify-agent-setup.ps1 -SourceOnly` in PowerShell 7 (`pwsh`) on `windows-latest`, so the manifests are checked against their schemas too | A broken skill or rule source, a placeholder left from the blueprint, an upstream skill edited by hand (stale hash), stale generated tables |
| Version check | Compares `ai_tooling/version` of the PR with the base branch and requires a `ai_tooling/CHANGELOG.md` entry | A change to what the setup publishes without the version raise that tells developers to refresh |
| Doc link check | `ai_tooling/check-doc-links.ps1` | A relative Markdown link that does not resolve |

A sketch (`.github/workflows/ai-tooling.yml`); replace each `<sha>` by the reviewed commit SHA of the
action's release:

```yaml
name: ai-tooling
on:
  pull_request:
    paths:
      - 'ai_tooling/**'
      - '**/AGENTS.md'
      - '.github/workflows/ai-tooling.yml'
permissions:
  contents: read
concurrency:
  group: ai-tooling-${{ github.ref }}
  cancel-in-progress: true
jobs:
  verify:
    runs-on: windows-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@<sha> # vX.Y.Z
      - name: Verify the agent tooling source
        shell: pwsh
        run: ./ai_tooling/verify-agent-setup.ps1 -SourceOnly
  version:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@<sha> # vX.Y.Z
        with:
          fetch-depth: 0
      - name: Version raised and changelog entry present
        shell: pwsh
        env:
          BASE_REF: ${{ github.base_ref }}
        run: |
          git cat-file -e "origin/${env:BASE_REF}:ai_tooling/version" 2>$null
          $base = if ($LASTEXITCODE -eq 0) { [int](git show "origin/${env:BASE_REF}:ai_tooling/version") } else { 0 }
          $global:LASTEXITCODE = 0   # a missing file on the base (first PR) is not a failure
          $head = [int](Get-Content ai_tooling/version -Raw)
          if ($head -le $base) { throw "ai_tooling/version must be raised above $base" }
          if (-not (Select-String -Path ai_tooling/CHANGELOG.md -Pattern "^\s*#+\s*$head\b" -Quiet)) {
            throw "ai_tooling/CHANGELOG.md has no entry for version $head"
          }
  links:
    runs-on: windows-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@<sha> # vX.Y.Z
      - name: Check relative Markdown links
        shell: pwsh
        run: ./ai_tooling/check-doc-links.ps1
```

The version job should fail only when the PR changes what the setup publishes (skills, rules, MCP
servers, `setup.ps1`): adapt the condition to the project's bump rule in `custom-aitooling-maintain`,
and match the changelog heading pattern to the file's real format. Run the PowerShell in both Windows
PowerShell 5.1 (`shell: powershell`) and PowerShell 7 (`shell: pwsh`) where the project's scripts
claim both.

## 5. Testing and documentation

- Workflows cannot run fully locally (`act` covers only part of them). Starting or re-running a
  workflow (`gh workflow run`, `gh run rerun`) is a GitHub write (`PERMISSIONS.md`, section 1): ask
  first, and say which branch and inputs. Pushing the YAML is one too. Reading the result needs no
  approval: `gh run list`, `gh run view {run-id} --log-failed`, `gh pr checks`.
- A new or changed secret, variable, environment, OIDC login, reusable workflow or convention
  updates the matching table in `.github/workflows/README.md` in the same commit
  (`custom-docs-update`). Write only a secret's name and purpose there, never its value.
- Where the project has a wiki or other page that describes the CI, update it in the same change.

## Project facts

- The conventions file: `.github/workflows/README.md`, created with the first workflow. On 2026-10-23 the repository has no workflows: CI would be GitHub Actions.
- Names of the project's runners, secrets, variables, environments, OIDC roles and the main workflow: in `.github/workflows/README.md` only, never here.
- Branch protection or ruleset of `master`: none, so no status check and no review is required (checked 2026-10-23).
