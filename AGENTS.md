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

### A. Outer Ring Widgets (Clockwise Dial, `widget 1` to `widget 12`)
- **`widget 1` (12 o'clock, `x=193, y=7`): Battery Widget.** Circular progress meter + lightning bolt icon + `[BATTERY_PERCENT]%` text. Launches `BATTERY_STATUS` on tap.
- **`widget 2` (~1 o'clock, `x=298, y=41`): Heart Rate Widget.** Heart icon + `[HEART_RATE]` BPM text. Launches Heart Rate on tap.
- **`widget 3` (~2 o'clock, `x=381, y=111`): Slot 1 Complication.** Fixed fitness/balance icon (`icon_fitness`) + Slot 1 Complication (`slotId="14"`).
- **`widget 4` (~3 o'clock, `x=403, y=205`): Slot 3 Complication.** Fixed timer icon (`icon_timer`) + Slot 3 Complication (`slotId="12"`).
- **`widget 5` (~4 o'clock, `x=378, y=305`): Slot 5 Complication.** Fixed camera icon (`icon_camera`) + Slot 5 Complication (`slotId="10"`).
- **`widget 6` (~5 o'clock, `x=315, y=374`): Slot 7 Complication.** Fixed microphone icon (`icon_mic`) + Slot 7 Complication (`slotId="8"`). Launches `SETTINGS` on tap.
- **`widget 7` (6 o'clock, `x=188, y=399`): Logo Branding.** "PanSar" script branding using `corinthia.ttf`. Hidden in Ambient mode.
- **`widget 8` (~7 o'clock, `x=102, y=375`): Slot 6 Complication.** Fixed home icon (`icon_home`) + Slot 6 Complication (`slotId="9"`).
- **`widget 9` (~8 o'clock, `x=33, y=305`): Slot 4 Complication.** Fixed nest device icon (`icon_nest`) + Slot 4 Complication (`slotId="11"`).
- **`widget 10` (~9 o'clock, `x=7, y=205`): Slot 2 Complication.** Fixed clipboard/inventory icon (`icon_inventory`) + Slot 2 Complication (`slotId="13"`).
- **`widget 11` (~10 o'clock, `x=19, y=111`): Weather Widget.** Weather condition icon + temperature readout (`°`). Launches weather on tap.
- **`widget 12` (~11 o'clock, `x=80, y=42`): Steps Count Widget.** Footprint/shoe icon (`icon_steps`) + `[STEP_COUNT]` text. Launches Steps tracking on tap.

### B. Center Rows (Top to Bottom)
- **Center Row 1 (Date Widget, `x=96, y=122`):** Formatted date display (`EEE, d MMM yyyy`). Launches Calendar on tap.
- **Center Row 2 (Clock Widget, `x=75, y=175`):** Large digital clock (`HH:mm`) launching `ALARM` on tap, plus superscript seconds (`x=375, y=175`, hidden in Ambient mode).
- **Center Row 3 ("Next event" Widget, `x=75, y=285`):** `TodayDetail` long text complication (`slotId="15"`) for calendar agenda / reminders.

---

## 5. User Customization Schema (`<UserConfigurations>`)

- **Step 0: Flavors / Presets:** Pre-configured watch face styling presets (Default & Variant styling).
- **Step 1: Theme Color (`themeColor`):** 11 curated color palettes (White, Cyan, Orange, Green, Purple, Red, and dual-tone variants).
- **Step 2: Background Texture (`0cb11f46...`):** 10 selectable background artistic mosaic styles (`background_1` to `background_10`).
- **Step 3: Clock Format (`clockFormat`):** Selectable between 24-Hour (`opt_24_hour`) and 12-Hour (`opt_12_hour`) display.
- **Step 4: Clock Font Weight (`clockWeight`):** Selectable between Normal (`opt_normal`), Bold (`opt_bold`), and Light (`opt_light`).
- **Step 5: Show Seconds (`showSeconds`):** Boolean toggle to show or hide the superscript seconds counter.
- **Fixed Complication Icons:** `widget 3`, `widget 4`, `widget 5`, `widget 6`, `widget 8`, `widget 9`, `widget 10` use fixed icons tinted by `themeColor`.
- **Interactive Complications:** Configurable via standard Wear OS Complications screen (`slotId="8"` through `slotId="15"`).

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
