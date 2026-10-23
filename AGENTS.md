# Total View (`watchface_total_view`) — Monorepo

This repository hosts several independent apps, each in its own top-level folder with its own build, tooling, and `AGENTS.md`.

- **Repository:** [https://github.com/Panaith/watchface_total_view](https://github.com/Panaith/watchface_total_view)
- **Publisher:** `PanSar`
- **IDE / Environment:** Visual Studio Code and Google Antigravity IDE. Do **not** generate or commit Android Studio / JetBrains `.idea/` directory files or cache artifacts.

## Apps

| Folder | Description | Guide |
|---|---|---|
| [`watchface/`](watchface/) | Wear OS digital watch face built with Watch Face Format (WFF) v2 | [`watchface/AGENTS.md`](watchface/AGENTS.md) |

Before working on an app, read its `AGENTS.md`. Run that app's build and validation commands from inside its folder.

## Repository Structure

```
watchface_total_view/
├── .gitignore      # Repo-wide ignores (.idea, *.iml, .DS_Store, GEMINI.md); each app has its own .gitignore
├── AGENTS.md       # This file: monorepo overview
├── GEMINI.md       # Antigravity context loader (imports @AGENTS.md)
└── watchface/      # Wear OS watch face (Gradle project)
```

## Git & Contribution Guidelines

- **Primary Branch:** `master`
- **Origin Remote:** `https://github.com/Panaith/watchface_total_view.git`
- Keep commits focused, clean, and atomic (Conventional Commits style, scoped by app or area, e.g. `feat(wff): ...`, `docs: ...`).
