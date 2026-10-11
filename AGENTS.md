# Watch Face Total View (`watchface_total_view`)

## 1. Project Overview & Philosophy

`watchface_total_view` is a comprehensive, feature-rich digital watch face for Wear OS (Wear OS 4 / 5+).
It is built strictly using Google's declarative **Watch Face Format (WFF)** Version 2.

- **Package / Application ID:** `com.pansar.watchface_total_view`
- **Target OS:** Wear OS 4+ (minSdk 36, targetSdk 37, compileSdk 37)
- **Format Version:** Watch Face Format Version 2 (`com.google.wear.watchface.format.version=2`)
- **IDE / Environment:** Visual Studio Code and Google Antigravity IDE. Do **not** commit Android Studio / JetBrains `.idea/` directory files or cache artifacts.

---

## 2. Declarative Architecture (`android:hasCode="false"`)

This watch face runs entirely on Wear OS system rendering services without custom Kotlin/Java runtime code:
1. `AndroidManifest.xml` explicitly defines `android:hasCode="false"`.
2. All visual layouts, complications, user settings, animations, dynamic color bindings, and ambient modes are defined in XML under `watchface/src/main/res/raw/watchface.xml`.
3. Never attempt to add Kotlin or Java classes, activities, or services for watch face logic. All logic must be expressed using declarative WFF XML tags and expressions.

---

## 3. Repository Directory Structure

```
watchface_total_view/
├── .gitignore                         # Configured to ignore Gradle caches, local.properties, GEMINI.md, .idea
├── AGENTS.md                          # AI agent guide and technical documentation (this file)
├── GEMINI.md                          # Antigravity context loader (imports @AGENTS.md)
├── build.gradle.kts                   # Root build script
├── settings.gradle.kts                # Root project settings
├── gradle/
│   ├── libs.versions.toml             # AGP 9.4.1 version catalog
│   └── wrapper/                       # Gradle wrapper binaries
├── project in WatchFace Studio/       # Reference assets, fonts, icons, and WFS project source
│   ├── src/                           # Original .wfs project files
│   ├── icons/                         # Source icon png assets
│   ├── background_images/             # Source background textures
│   └── wff-validator.jar              # Official Google WFF validator tool
└── watchface/                         # Core watch face module
    ├── build.gradle.kts               # Module build configuration (minSdk 36, targetSdk 37)
    └── src/main/
        ├── AndroidManifest.xml        # Declares standalone watch face with WFF version 2
        └── res/
            ├── drawable/              # Watch face graphic assets (icons, background, preview)
            ├── font/                  # Custom fonts (corinthia.ttf)
            ├── raw/
            │   └── watchface.xml      # Core declarative Watch Face Format definition
            ├── values/
            │   └── strings.xml        # Localization, config titles, and option labels
            └── xml/
                ├── watch_face_info.xml   # Metadata (preview drawable, editable, flavors)
                └── watch_face_shapes.xml # Circular display shape binding
```

---

## 4. Watch Face Layout & Feature Specification

Canvas dimensions: **450 x 450** circular display.

### A. Top Row Metrics
- **Steps Widget (`x=80, y=42`):** Footprint icon + `[STEP_COUNT]` text. Launches Steps tracking on tap.
- **Battery Widget (`x=193, y=7`):** Circular progress meter + lightning bolt icon + `[BATTERY_PERCENT]%` text. Launches `BATTERY_STATUS` on tap.
- **Heart Rate Widget (`x=298, y=41`):** Heart icon + `[HEART_RATE]` BPM text. Launches Heart Rate on tap.

### B. Mid-Upper Row (Weather, Date & Complication)
- **Weather Widget (`x=19, y=111`):** Weather condition icon + temperature readout (`°`).
- **Date (`x=96, y=122`):** Formatted date display (`EEE, d MMM yyyy`). Launches Calendar on tap.
- **Slot 1 Complication (`x=381, y=111`):** Top-right complication slot.

### C. Main Center (Digital Clock & Seconds)
- **Hours & Minutes (`x=75, y=175`):** Large, crisp digital time display (`HH:mm`). Launches `ALARM` on tap.
- **Seconds (`x=375, y=175`):** Superscript seconds counter. Automatically hidden in Ambient mode.

### D. Outer Edge Shortcut Slots (Circular Flank Perimeter)
- **Slot 2 (`x=7, y=205`):** 9 o'clock flank.
- **Slot 3 (`x=403, y=205`):** 3 o'clock flank.
- **Slot 4 (`x=33, y=305`):** 8 o'clock flank.
- **Slot 5 (`x=378, y=305`):** 4 o'clock flank.
- **Slot 6 (`x=102, y=375`):** 7 o'clock flank.
- **Slot 7 (`x=315, y=374`):** 5 o'clock flank.

### E. Lower Center & Branding
- **Next Event (`TodayDetail`, `x=84, y=310`):** Long text complication for agenda / reminders.
- **Logo Branding (`x=188, y=399`):** "PanSar" script branding using `corinthia.ttf`. Hidden in Ambient mode.

---

## 5. User Customization Schema (`<UserConfigurations>`)

- **Theme Color (`themeColor`):** 11 curated color palettes (White, Cyan, Orange, Green, Purple, Red, and dual-tone variants).
- **Background Texture (`0cb11f46...`):** 10 selectable background artistic mosaic styles.
- **Slot 1–7 Icon Selections:** Selectable shortcut icons (Fitness, Timer, Home, Inventory, Camera, Assistant, Mic, etc.).
- **Flavors:** Pre-configured watch face styling presets.

---

## 6. Build, Validation & Deployment Guide

### A. Validation
Validate WFF syntax and schema with Google's official validator:
```powershell
java -jar "project in WatchFace Studio/wff-validator.jar" 2 "watchface/src/main/res/raw/watchface.xml"
```

### B. Building
```powershell
# Build debug APK
.\gradlew.bat assembleDebug

# Build release APK
.\gradlew.bat assembleRelease
```

### C. Wireless Debugging & Deployment on Wear OS Watch
```powershell
adb connect <WATCH_IP>:<PORT>
.\gradlew.bat installDebug
```
