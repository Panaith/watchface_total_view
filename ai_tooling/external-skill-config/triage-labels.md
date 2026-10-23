# Triage Labels

> **External skill configuration.** This file is read by the upstream Matt Pocock skills, installed
> into `ai_tooling/skills/upstream/mattpocock/` by `ai_tooling/update-mattpocock-skills.ps1`.
> The project's own skills do not use it. Its source is `ai_tooling/external-skill-config/`;
> `ai_tooling/setup.ps1` writes the copy in `docs/agents/` that the skills read, so edit the
> source. Do not add files to either folder; see "Where things go" in the `custom-docs-update` skill.

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

In GitHub Issues, these are **labels** on the issue. See `docs/agents/issue-tracker.md` for how to add and remove them
(`gh issue edit {n} --add-label ...`). A label that does not exist yet must be created first (`gh label create`), which is a GitHub write.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, an agent can work on it |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

`ready-for-agent` says the issue is specified well enough for an agent to do the work. It does **not** let the
agent act without asking: every GitHub write, commit, push and PR still needs the user's approval
(`PERMISSIONS.md`), also when the agent works unattended.

Edit the right-hand column to match whatever vocabulary you actually use (GitHub's default `wontfix` label exists in new repositories).
