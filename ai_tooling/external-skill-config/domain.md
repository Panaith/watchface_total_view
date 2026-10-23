# Domain Docs

> **External skill configuration.** This file is read by the upstream Matt Pocock skills, installed
> into `ai_tooling/skills/upstream/mattpocock/` by `ai_tooling/update-mattpocock-skills.ps1`.
> The project's own skills do not use it. Its source is `ai_tooling/external-skill-config/`;
> `ai_tooling/setup.ps1` writes the copy in `docs/agents/` that the skills read, so edit the
> source. Do not add files to either folder; see "Where things go" in the `custom-docs-update` skill.

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

This is a **multi-context** repo: each app listed in the Apps table of the root `AGENTS.md` (every top-level folder with its own `AGENTS.md`) is its own context.

## Before exploring, read these

- **`GLOSSARY-MAP.md`** at the repo root: it points at one `GLOSSARY.md` per app. Read each one relevant to the topic.
- **`{app}/GLOSSARY.md`**: the glossary for that app's domain.
- **`docs/adr/`**: repo-wide decisions (pipelines, monorepo conventions, cross-app deployment coupling).
- **`{app}/docs/adr/`**: decisions scoped to one app. Read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

Domain docs complement, not replace, the existing technical docs: `documentation/overview.md` and
`{app}/documentation/overview.md` cover tech stack, installations, and how to develop, debug and build.

## File structure

```
/
├── GLOSSARY-MAP.md
├── docs/adr/                          ← repo-wide decisions
├── {app}/
│   ├── GLOSSARY.md
│   └── docs/adr/                      ← app-specific decisions
├── {other app}/
│   ├── GLOSSARY.md
│   └── docs/adr/
└── … (one per app)
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in the relevant `GLOSSARY.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because…_
