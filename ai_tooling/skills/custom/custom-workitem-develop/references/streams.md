# Split a work item into streams

This is chapter 16 of [SKILL.md](../SKILL.md). Chapter numbers without a file name are chapters of `SKILL.md`; 16.1 to 16.4 are sections of this file.

## Contents

- 16.1 Plan
- 16.2 Work
- 16.3 Report
- 16.4 Judge

Only when chapter 8 of `SKILL.md` finds two or more parts that change separate apps and can all be built in one round. You, the session model, are the **lead** (not the `custom-role-planner` subagent, which cannot dispatch): you plan the streams and judge the results, and workers write the code. Chapters 14 and 15 of `SKILL.md` then run on the merged result as usual.

## 16.1 Plan

1. Ask every open question before the first stream starts: a worker cannot ask the user.
2. Write one **stream** per part, numbered `s1`, `s2`, ...: its scope, the files it may change, the skills it follows, and its check (the commands, and which result passes). Two streams never change the same file, and no stream needs another stream's result: all streams run in one round. A part that would need another's result is built by the lead after the merge, or the item is not split.
3. Show the streams with the plan (chapter 9 of `SKILL.md`), and give each stream its own row in the Progress comment.

## 16.2 Work

1. **Worktrees.** With the work item branch checked out and a clean working tree, create one worktree per stream. Changes that tools write on their own while they run (generated or normalised files) do not count as changes, but note them before you start. Each worktree goes next to the repository (`custom-worktrees` in the repository's parent folder). From the repository root:
   `git worktree add ../custom-worktrees/{id}-s{n} -b stream/{id}-s{n} HEAD`
   - This writes outside the repository: ask once, listing all the worktrees (`PERMISSIONS.md`, section 5).
   - The folder is outside the agent's working directory. Where the agent restricts access to its working directory (Claude Code: ask the user to run `/add-dir` with the full path of the worktrees folder), grant access before creating the worktrees; otherwise every read and edit of the workers asks for permission.
   - Create them yourself. Claude Code's own subagent worktree isolation (`isolation: worktree`) by default branches from the remote's default branch, not from the work item branch (setting `worktree.baseRef`), and puts the worktree inside the repository, where the IDE's language servers index it and hold its folders open. Other agents' isolation features may behave alike.
   - A worktree holds only tracked files: no installed dependencies, no generated agent files.
   - Never change your own shell's directory into a worktree (use `git -C` and paths instead): a shell left there holds the folder open.
2. **Workers.** Start one subagent per stream, at most 4 at a time: `custom-workitem-stream-worker`. Its brief: the work item id, the stream from 16.1, and the absolute path of its worktree.
   - Agents without subagent definitions brief a fresh subagent with the body of `ai_tooling/agents/custom-workitem-stream-worker.md`.
   - An agent that cannot start subagents works through the streams itself, one after another, each in its own worktree, and writes the same report (16.3) for each before judging it.
3. **Checks.** The worker runs its stream's check in its worktree, with the worktree's own scripts and the commands of the app's `AGENTS.md`. A check that needs installed dependencies cannot run in a worktree: the worker reports it as not run, and you run it in 16.4.

## 16.3 Report

Each worker replies with exactly these four parts:

1. **Changes**: every file changed, with one line on what changed.
2. **Commands run**: each command, with its exit code and the output that matters.
3. **Not tested**: what it did not run or could not check, and why.
4. **Doubts**: anything it is unsure of, and every place where the stream and the code disagreed.

## 16.4 Judge

When all workers have reported:

1. Before merging anything, run `git status` in the main checkout: it must still be clean, apart from the tool-written changes noted in step 1 of 16.2. Other changes there mean a worker wrote outside its worktree: show them to the user, and send back the stream whose files they are (revise); if that is unclear, escalate.

Then for each report:

2. Stage the worktree's changes (`git -C ../custom-worktrees/{id}-s{n} add -A`) and read `git -C ../custom-worktrees/{id}-s{n} diff --cached` against the stream and the report.
3. Mark the stream:
   - **accept**: the diff stays within the stream, its check passed, and the report has all four parts. A stream whose app `AGENTS.md` names a mandatory code check is never accepted without a clean result of it.
   - **revise**: send your findings to the same worker (where the agent can message a running subagent; otherwise a fresh worker with the old report and the findings). After two revisions, escalate.
   - **escalate**: show the user the report and the question to decide.
4. **Merge an accepted stream** into the work item branch, from the repository root:
   `git -C ../custom-worktrees/{id}-s{n} diff --cached --binary --output=../{id}-s{n}.patch`, then `git apply --index ../custom-worktrees/{id}-s{n}.patch`.
   `--output` is resolved inside the worktree, so the patch lands in `custom-worktrees/{id}-s{n}.patch`, the path `git apply` reads; it lets git write the file because Windows PowerShell 5.1 re-encodes a piped diff. If `git apply --index` refuses because a file has local tool-written changes, restore the file first (ask, `PERMISSIONS.md` section 5). Now run the checks the worker reported as not run for lack of dependencies; if they fail, take the stream back out (`git apply --reverse --index` with the same patch) and revise. Then commit the stream, one commit each; the accepted streams can be shown for approval as one list (`PERMISSIONS.md`, section 4).
5. **Clean up**: `git worktree remove --force ../custom-worktrees/{id}-s{n}`, delete its patch file, and `git branch -d stream/{id}-s{n}` (it has no commits of its own). If the removal fails with "Permission denied", git has already unregistered the worktree but a process still holds a folder: ask the user to close it (`PERMISSIONS.md`, section 5), then remove the leftover folder with `cmd /c rd /s /q "{folder}"` (backslashes in the path; in Git Bash write `cmd //c`).
6. Update the stream's row in the Progress comment.

For each stream, note the worker's tokens and elapsed time (where the agent shows them when a subagent finishes) and the number of revisions, and afterwards the number of findings of the chapter 14 review of `SKILL.md`; a comparison with a normal run needs them.
