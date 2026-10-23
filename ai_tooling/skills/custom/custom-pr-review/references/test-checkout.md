# Test checkout for a PR review

This is chapter 8 of [SKILL.md](../SKILL.md). Chapter numbers without a file name (chapters 1, 13, 14) are chapters of `SKILL.md`; 8.1 to 8.7 are sections of this file.

## Contents

- 8.1 Copy the repo
- 8.2 Reset the copy and build the merge
- 8.3 Dependencies
- 8.4 Agent setup in the copy
- 8.5 Ports and configuration
- 8.6 Data
- 8.7 Hand over
- Refresh the test checkout
- Committing to the PR

The test checkout is a full, independent copy of the user's repo, switched to the **merge result** (the code as it will be once the PR is merged into its target). It has its own data and its own ports, so it runs side by side with the user's own setup: a second IDE window, a second application, a second dev server, and nothing shared. The user's repo, branch and working tree are never touched.

```
<parent>\<repository folder>          the user's clone
<parent>\custom_PR_branches\PR_{id}\
├─ <repository folder>\                 the copy, on the merge result
└─ data\                                the data for this test, and its settings
```

`<parent>` is the folder that holds the user's clone, `<repository folder>`. The folder name `custom_PR_branches` is a convention of this skill: the user may pick another name next to the repository. Below, `<repo>` is the user's repo, `<PR folder>` is `<parent>\custom_PR_branches\PR_{id}`, and `<copy>` is the repo folder inside it.

If `<PR folder>` already exists from an earlier run, do not copy again: [refresh it](#refresh-the-test-checkout).

## 8.1 Copy the repo

Copy with robocopy (PowerShell), in the background:

```
robocopy "<repo>" "<copy>" /E /XJ /MT:32 /R:1 /W:1 /NFL /NDL /NP /XD "<repo>\{cache folder}" "<repo>\{build output folder}" /LOG:"<scratch dir>\robocopy_PR_{id}.log"
```

- Exclude only regenerable caches and build outputs, by full path (the app's `AGENTS.md` and overview name them). Keep the installed dependencies so the copy is ready to run.
- Exclude folders by full path only. A bare name such as `/XD dist` would also drop folders of that name inside installed dependency packages.
- Tell the user the size and the expected time before starting; measure the first copy and note it for the next.
- Exit codes 0-7 mean success (1 = files copied). 8 or higher means some files failed: read the log and report them.
- `/XJ` skips junctions, among them the agent junctions that the setup publishes into the repo (they point into the user's repo). They are recreated in 8.4; skill copies that are real folders are copied and refreshed there.
- Do not copy with Explorer or `Copy-Item`: they follow the junctions.

## 8.2 Reset the copy and build the merge

The copy starts as the user's repo: their branch, their uncommitted changes, their stashes. Target every command at the copy with `git -C "<copy>"`, and first check that `git -C "<copy>" rev-parse --show-toplevel` is the copy. Stop if it is not.

```
git -C "<copy>" config core.longpaths true
git -C "<copy>" reset --hard
git -C "<copy>" clean -fd
git -C "<copy>" fetch origin {target} +refs/pull/{id}/head:refs/remotes/origin/pr/{id}
git -C "<copy>" switch --detach origin/{target}
git -C "<copy>" merge --no-ff --no-edit -m "Local test merge: PR {id} into {target}" origin/pr/{id}
```

- `clean -fd`, never `-fdx`: `-x` would delete installed dependencies and the other ignored files that make the copy ready to run.
- `refs/pull/{id}/head` is GitHub's ref for the PR's source commit (seen to work for a PR from a fork). If the fetch fails, use the `gh` route below. Fetch with full history: no `--depth`, because the merge needs the merge base; a shallow copy needs `git -C "<copy>" fetch --deepen=100` until `git -C "<copy>" merge-base origin/{target} origin/pr/{id}` succeeds. Alternatively, run `gh pr checkout {id} --repo Panaith/watchface_total_view --detach` inside the copy (it fetches from the fork where there is one), note the commit with `git -C "<copy>" rev-parse HEAD`, then `switch --detach origin/{target}` and merge that commit instead of `origin/pr/{id}`.
- Merge locally rather than use GitHub's `refs/pull/{id}/merge`: that ref may be stale or missing (for example when the PR is not mergeable), and a local merge against the current `origin/{target}` is always the real result.
- Check with `git -C "<copy>" log -1 --format="%h %p %s"`: a merge commit with two parents.
- On a conflict, run `git -C "<copy>" merge --abort` and report the conflicting files. That is a finding: the author has to resolve it. Offer to test `origin/pr/{id}` alone instead, saying clearly that it is not the merge result.
- The local merge commit is never pushed.

## 8.3 Dependencies

The copied dependencies match the user's repo, not necessarily the PR. Compare the dependency manifest and lock files:

```
git -C "<copy>" diff --name-only {user's repo HEAD} HEAD -- {the apps' manifest and lock files}
```

If nothing is listed, nothing needs installing. Otherwise offer to run, in the copy, the install command from each affected app's `documentation/overview.md` or `AGENTS.md`.

## 8.4 Agent setup in the copy

The copy's setup script (in `ai_tooling/`) is the version from the PR under review: code from outside the user's own branch (`PERMISSIONS.md`, section 3). Before running it, list what the merge changes in the tooling folder (`git -C "<copy>" diff --stat origin/{target} HEAD -- ai_tooling`). If anything is listed, show that diff and ask; if nothing is listed, say so and ask. Only then run `& "<copy>\ai_tooling\setup.ps1" -Agent claude -SkipTools` (plus `copilot` or `cursor` if the user uses them; the options are in `ai_tooling/documentation/overview.md`, "Installations"). It republishes the skills and `.mcp.json` for the copy's own path. Always pass `-Agent`: with no console to ask on, the script skips its interactive question.

## 8.5 Ports and configuration

Both setups may run at the same time, so the copy needs its own ports and its own configuration. Find what the app listens on and which files hold it: the app's `documentation/overview.md` and `AGENTS.md` ("Commands": Run), its settings files and launch configurations. List them for the user in a table (server, the user's port, the copy's port, where it is configured).

- Move every port of the copy up by 100. If those ports are already taken (another PR copy is running; check with `Get-NetTCPConnection -State Listen`), use +200, and so on. A dev server that fails when its default port is taken needs an explicit port argument (+1 per copy is enough).
- Settings that live next to the user's data (outside the repo) are work data: ask before reading them (`PERMISSIONS.md`, section 2). Copy them to `<PR folder>\data\` and change the ports there, not in the user's folder.
- Where the app points at its own backend or at a login redirect (an OAuth app registered on GitHub or elsewhere has a fixed callback address), point the copy's configuration at the copy's ports. If a redirect address must be registered for the new port, tell the user that login on the copy may be rejected until it is.
- Edits to tracked configuration files in the copy are hidden from git so they can never be committed:

  ```
  git -C "<copy>" update-index --skip-worktree {edited tracked files}
  ```

If the PR does not need an app running (for example a documentation-only or library-only PR), ask what the user wants to run, and skip what does not apply.

## 8.6 Data

If the app needs a database or data file to run, remind the user, with the full path:

> Put the data for this test in `<PR folder>\data\`. Do not overwrite the settings that are already there. Use a fresh download, or copy it with the application closed: copying a data file that an application has open can give a broken copy. Tell me when it is there.

Then point the copy's configuration at it (the app's overview names the setting and the file; keep that file out of git, or hide the edit as in 8.5). Without this step, the copy opens the user's own data: the copied preferences still point at it.

If the app needs no data, skip this section.

## 8.7 Hand over

Tell the user:

- open `<copy>` in a new IDE window;
- start the application and the dev server with the commands from the app's `AGENTS.md`, with the copy's ports;
- the copy's ports, from the table in 8.5.

Offer to verify once everything runs: map the listening ports (`Get-NetTCPConnection -State Listen`) to their processes. The copy must be on the shifted ports only, and the user's own setup on the usual ones.

## Refresh the test checkout

On a re-review (chapter 13 of `SKILL.md`), or after a push to the PR, update the existing copy instead of copying again:

1. Ask the user to close the copy's application (it holds the project files) and to stop its dev server.
2. Check that nothing would be lost, as in chapter 14 step 2 of `SKILL.md`.
3. Put back the hidden edits of 8.5:
   ```
   git -C "<copy>" update-index --no-skip-worktree {edited tracked files}
   git -C "<copy>" checkout -- {edited tracked files}
   ```
4. Repeat 8.2 from `fetch` onwards, then 8.3, then re-apply the configuration edits of 8.5. The data folder and the data settings stay as they are.

## Committing to the PR

Only when the user asks. It is the author's branch, and a review comment with a suggestion block is usually the better route. A PR from a fork can be pushed to only if the author allowed edits from maintainers (`maintainerCanModify` in `gh pr view --json`). In the copy, `gh pr checkout` sets up the local branch and its upstream, fork or not:

```
git -C "<copy>" stash
gh pr checkout {id} --repo Panaith/watchface_total_view
git -C "<copy>" stash pop
git -C "<copy>" commit -am "{message}"
git -C "<copy>" push
```

(run `gh pr checkout` inside `<copy>`). Alternatively, for a PR from the same repository: `git -C "<copy>" switch {source}`.

- `stash` / `stash pop` are only needed if there are edits already. `gh pr checkout` creates a local branch that tracks the PR's source branch.
- Never commit on the local merge commit: pushing that would merge the target into the author's branch.
- `stash pop` can conflict when the target changed the same file.
- The skip-worktree files are never included. If the checkout complains about them, put them back first (refresh step 3) and redo the configuration edits of 8.5 afterwards.
- A commit message never contains `#` followed by a number: GitHub links it to an issue or PR.
- Committing and pushing need approval (`PERMISSIONS.md`, sections 1 and 4); the push is a GitHub change. It starts new checks, may dismiss existing approvals, and the author has to pull before continuing.
- Afterwards, refresh the test checkout to test the merge result again.
