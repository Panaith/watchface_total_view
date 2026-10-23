# project in WatchFace Studio — AI Agent Instructions

This file contains rules specific to the **project in WatchFace Studio** application: the original Samsung Watch Face
Studio (WFS) project of the watch face, kept as the design archive and the source of its original assets.
The root [AGENTS.md](../AGENTS.md) and [PERMISSIONS.md](../ai_tooling/PERMISSIONS.md) apply here too.

**If your workspace is this folder and not the repository root** (the IDE was opened on `project in WatchFace Studio` alone):

1. Read `../AGENTS.md` and `../ai_tooling/PERMISSIONS.md` now, unless they are already in your context, and follow them.
2. Tell the user once, at the start: *opening the repository root in the IDE is recommended. The project's skills,
   MCP servers and agent rules are published only there, so some of them may be missing in this window.*

## Critical Version Constraints

| Constraint | Why |
|-----------|-----|
| `src/*.wfs` are Watch Face Studio project files: **zip archives** written by the WFS GUI | They are opened, edited, built and run only in Watch Face Studio; no command line builds them |
| The current `.wfs` file is named in [How to Develop](documentation/overview.md#how-to-develop) | Open the current one; the others are the design history |

## Things AI Agents Must Never Do

- Never unzip, rewrite or hand-edit a `.wfs` file, and never delete an older version: they are the design history.
  Changes to the face that is built today go into the `watchface` app.
- Never copy files between this folder and `watchface/` unasked: the apps share no files (root `AGENTS.md`, Isolation).
- Never commit `build/` (ignored by this folder's `.gitignore`).

## Skills

| When you ... | Load |
|---|---|
| work in this folder | nothing beyond the root `AGENTS.md`: there is no code or command to run here |
| take a design or asset from here into the built face | [`custom-watchface-wff-edit`](../ai_tooling/skills/custom-watchface/custom-watchface-wff-edit/SKILL.md), working in `watchface/` |

## Commands

Run from `project in WatchFace Studio/`:

- **Prepare**: none
- **Run**: none (Watch Face Studio: **Run on Device**)
- **Unit tests**: none
- **E2E tests**: none
- **Lint**: none
- **Build**: none (Watch Face Studio builds the project)

## Adding or Updating Dependencies

- None: fonts, icons and backgrounds are files in this folder.
- **Notes**: none

## Agent Instruction Imports

The coding principles apply to every change in this app.

[@../ai_tooling/instructions/coding-principles.md](../ai_tooling/instructions/coding-principles.md)
