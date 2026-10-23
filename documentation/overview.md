# Watch Face Total View Repository — Overview

Watch Face Total View is a digital watch face for Wear OS that shows the
time, date, battery, heart rate, steps, weather, the next calendar event and six app shortcuts at
a glance. It was first designed in Samsung's Watch Face Studio (the app
`project in WatchFace Studio`) and is now maintained as a hand-written Watch Face Format
project built with Gradle (the app `watchface`). The WFS project is the design archive and source of the original assets; the `watchface` app is what is built and
installed.

Repository: [Panaith/watchface_total_view](https://github.com/Panaith/watchface_total_view) on
GitHub, default branch `master`. The project is developed in Visual Studio Code and Google
Antigravity.

## Repository Structure

```
watchface_total_view/
├── AGENTS.md                      # Agent instructions for every session
├── documentation/overview.md      # This file
├── ai_tooling/                    # AI agent tooling: skills, permissions, setup for every agent
├── project in WatchFace Studio/   # Watch Face Studio project (.wfs sources, assets)
└── watchface/                     # Wear OS watch face (Gradle project)
```

`watchface` and `project in WatchFace Studio` each have their own `.gitignore`; the root one
ignores IDE and OS files (`.idea/`, `*.iml`, `.DS_Store`) and everything `ai_tooling/setup.ps1`
generates.

## Pipelines

None: the repository has no CI. Each change is validated and built locally (see the
[watchface overview](../watchface/documentation/overview.md)).

---

## Apps

| App | Description |
|-----|-------------|
| [watchface](../watchface/documentation/overview.md) | The Wear OS watch face: declarative Watch Face Format v2 XML, built into an APK with Gradle |
| [project in WatchFace Studio](../project%20in%20WatchFace%20Studio/documentation/overview.md) | The original Samsung Watch Face Studio project: `.wfs` sources, screenshots, backgrounds, icons, fonts |
| [ai_tooling](../ai_tooling/documentation/overview.md) | AI agent tooling: the skills, permissions, MCP servers and setup for every agent; not deployed |
