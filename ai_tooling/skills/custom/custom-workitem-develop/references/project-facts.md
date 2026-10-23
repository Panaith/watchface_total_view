# Project facts

Facts of the GitHub issue process of Watch Face Total View (repository `Panaith/watchface_total_view`) that `SKILL.md` refers to by name. Checked against the repository on 2026-10-23: plain GitHub Issues with GitHub's default labels plus `accessibility`, no issue forms, no pull request template, no GitHub Projects board, no branch protection or rulesets on `master`, no CI.

## Contents

- Work item types and states
- Developer Notes
- Release Notes
- Work started state
- Review state
- Pull request title and description
- Required fields
- Agent tooling parent
- Reviewers
- Review threads
- Work item fields

## Work item types and states

Types: a bug (label `bug`) and an enhancement (label `enhancement`); an issue without either label is asked about before planning. States: only open and closed (`stateReason` completed or not planned); the repository has no Projects board. The repository has no issue forms: read the free-text issue body (acceptance criteria and, for a bug, the steps to reproduce are wherever the author wrote them), the labels and the comments.

## Developer Notes

Place written in chapter 10: an issue comment whose first line is the heading `Developer Notes`, updated in place (`gh api --method PATCH repos/Panaith/watchface_total_view/issues/comments/{comment id}`) instead of a new comment each time.

## Release Notes

The project keeps no release notes per issue; skip step 2 of chapter 15.

## Work started state

What is done before the first change (chapter 13): assign yourself (`gh issue edit {n} --repo Panaith/watchface_total_view --add-assignee @me`). No board and no label. Skip it if it is already so.

## Review state

What is done when the PR is created (chapter 15): nothing on the issue itself (it stays open; the PR with `Closes #{n}` closes it on merge, since `master` is the repository's default branch). No board.

## Pull request title and description

Title: a Conventional Commits line in the imperative, scoped by app or area, as the root `AGENTS.md` writes commits (`feat(wff): add a step goal ring`, `fix(wff): ...`, `docs: ...`, `feat(aitooling): ...`); the issue number is not in the title. Squash merging makes it the commit on `master`. Description sections: Problem (one sentence on why), Cause (bugs), Fix, Testing (the validator and `assembleDebug` runs for a watchface change, and what was checked on a device); the last line `Closes #{id}` (the only `#` with a number: `SKILL.md`, chapter 15). The repository has no `.github/pull_request_template.md`.

## Required fields

None: no issue form, workflow or ruleset requires a label, assignee, milestone or field.

- Creating a follow-up bug issue (found during the work): give it the label `bug`, and ask the user for anything else they want on it.
- Moving to the review state: nothing must be set.

## Agent tooling parent

None: agent tooling issues are ordinary enhancements, without a parent issue, label or milestone.

## Reviewers

Candidates for chapter 15, by GitHub login. The owner of the tooling is `Panagiotis Sarridis`. `master` has no branch protection, ruleset or `CODEOWNERS` file, so no review is required by the repository; ask the user whether to request one.

Merge method: **squash**, by the project's convention (the repository also allows merge commits and rebase; do not use them). The repository's squash setting takes the commit title (one commit) or the PR title (several commits) as the title, and the list of commit messages as the body.

| Person | GitHub login | Checked |
|---|---|---|
| Panagiotis Sarridis | `Panaith` | 2026-10-23 (`gh api users/Panaith`) |

## Review threads

Who resolves a review thread on a PR: the author resolves it once the fix is pushed, and the reviewer reopens it if the fix is not right. No ruleset requires all conversations to be resolved before the merge.

## Work item fields

What the parts of an issue change in this workflow (chapter 4).

| Field | What it changes |
|---|---|
| Developer Notes comment, the Progress comment, linked branches and PRs | Resumed or reopened work: what is already done (ch. 5, 12); the Developer Notes are merged, not overwritten (ch. 10), and the existing Progress comment is updated (ch. 11) |
| Assignees, author | Whom to ask when something is unclear |
| Labels `bug`, `enhancement` | The kind of work and the branch name (`bug/{id}`, `feature/{id}`) |
| Label `documentation` | A change to documentation only: no validator or build run needed unless a command or path in it changed |
| State, state reason | A closed or reopened issue: say so before planning |

Skip: the labels `duplicate`, `invalid`, `wontfix` (say so and stop), `good first issue`, `help wanted`, `question`, `accessibility` (read as context only), and bot comments.
