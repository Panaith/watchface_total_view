# Watch Face Total View (`watchface_total_view`)

## 1. Project Overview

`watchface_total_view` is a comprehensive, feature-rich digital watch face for Wear OS.
It is built strictly using Google's declarative **Watch Face Format (WFF)** Version 2.

- **Package / Application ID:** `com.pansar.watchface_total_view`
- **Repository:** [https://github.com/Panaith/watchface_total_view](https://github.com/Panaith/watchface_total_view)
- **Target OS:** Wear OS 6+ (minSdk 36, targetSdk 37, compileSdk 37)
- **Format Version:** Watch Face Format Version 2 (`com.google.wear.watchface.format.version=2`)
- **Publisher:** `PanSar`
- **IDE / Environment:** Visual Studio Code and Google Antigravity IDE. Do **not** generate or commit Android Studio / JetBrains `.idea/` directory files or cache artifacts.

---

## 2. Declarative Architecture (`android:hasCode="false"`)

This watch face runs entirely on Wear OS system rendering services without any custom Kotlin/Java runtime code:
1. `AndroidManifest.xml` explicitly defines `android:hasCode="false"`.
2. All visual layouts, complications, user settings, dynamic color bindings, and ambient modes are defined in XML under `app/src/main/res/raw/watchface.xml`.
3. Never add Kotlin or Java classes, activities, or services for watch face logic. All logic must be expressed using declarative WFF XML tags and expressions.

---

## 3. Project Directory Structure

This project lives in the `watchface/` folder of the monorepo (see the root `AGENTS.md`). All paths and commands below are relative to `watchface/`.

```
watchface_total_view/                  # Monorepo root (AGENTS.md, GEMINI.md, .gitignore)
└── watchface/                         # Watch face Gradle project (this file lives here)
    ├── .gitignore                     # Ignores Gradle caches, build output, local.properties
    ├── AGENTS.md                      # AI agent guide and technical documentation (this file)
    ├── build.gradle.kts               # Root build script
    ├── settings.gradle.kts            # Project settings (rootProject.name = "watchface_total_view", include ":app")
    ├── gradle.properties              # Gradle / AndroidX properties
    ├── gradle/
    │   ├── gradle-daemon-jvm.properties   # Gradle daemon JVM toolchain
    │   ├── libs.versions.toml         # Version catalog (AGP 9.4.1)
    │   └── wrapper/                   # Gradle wrapper binaries
    ├── gradlew, gradlew.bat           # Gradle wrapper CLI scripts
    ├── tools/
    │   └── wff-validator.jar          # Official Google WFF validator
    └── app/                           # Core watch face module (Gradle project ":app")
        ├── build.gradle.kts           # Module build configuration (minSdk 36, targetSdk 37)
        └── src/main/
            ├── AndroidManifest.xml    # Standalone watch face, WFF version 2, publisher PanSar
            ├── keepRules/rules.keep   # R8 keep rules (template, unused)
            └── res/
                ├── drawable/          # background_*.png textures, icon_*.png widget icons, preview.png
                ├── font/corinthia.ttf # Custom script font for "PanSar" branding
                ├── raw/watchface.xml  # Core declarative Watch Face Format definition
                ├── values/strings.xml # Config titles and option labels
                └── xml/
                    ├── watch_face_info.xml   # Metadata (preview, editable, flavors, multiple instances)
                    └── watch_face_shapes.xml # Circular 450x450 display shape binding
```

---

## 4. Core Implementation

Canvas: **450 x 450** circular display (`clipShape="CIRCLE"`, `CLOCK_TYPE=DIGITAL`).

### A. User Customization Schema (`<UserConfigurations>`)

| Configuration ID | Type | Options / Values | Default | Description |
|---|---|---|---|---|
| `themeColor` | Color | 11 options (`0`–`10`), see below | `0` (White) | Three-color theme palette |
| `bgImage` | List | `0`–`8` → `background_1` … `background_9` | `0` | Background texture image |
| `clockFormat` | List | `0` (24 Hour), `1` (12 Hour) | `0` | Time format |
| `clockWeight` | List | `0` (Normal), `1` (Bold), `2` (Light) | `0` | Font weight for clock, seconds, AM/PM |
| `showSeconds` | Boolean | `TRUE` / `FALSE` | `TRUE` | Toggle seconds display |
| `showBattery` | Boolean | `TRUE` / `FALSE` | `TRUE` | Toggle battery progress bar |

**`themeColor` color roles** (every option defines 3 colors):
- `[CONFIGURATION.themeColor.0]` — Background tint (always black).
- `[CONFIGURATION.themeColor.1]` — Accent: icons, monochrome images, progress bars, secondary labels.
- `[CONFIGURATION.themeColor.2]` — Primary text: clock, date, values.
- Options `0`–`5` are single-tone (White, Cyan, Orange, Green, Blue, Dark Red); options `6`–`10` are dual-tone (colored accent + white primary text).

**Flavors (presets):** `1` = Default (`themeColor=0`, `bgImage=0`), `2` = Variant (`themeColor=7`, `bgImage=7`). Each flavor also re-declares the default provider policy of every complication slot.

### B. Core Components
- **Background:** solid `PartDraw` tinted with `themeColor.0` + `bgImage` texture `ListConfiguration`. Both hidden in ambient.
- **Battery widget:** launches `BATTERY_STATUS`; `[BATTERY_PERCENT]%` text + horizontal progress bar toggled by `showBattery`. The bar is red (`#ff0101`) at 0–9% and `themeColor.1` at 10–100%.
- **Date:** `PartText` with `%s, %s %s %s` template (`DAY_OF_WEEK_S`, `DAY`, `MONTH_S`, `YEAR`), Gregorian calendar, launches `CALENDAR`.
- **Digital clock:** `Group` launching `ALARM`. 2 formats × 3 weights = 6 `DigitalClock` variants toggled by alpha `Transform`s.
- **Seconds:** `TimeText format="ss"` in 3 weights, toggled by `showSeconds`, hidden in ambient.
- **AM/PM:** shown only when `clockFormat == 1`, via `[AMPM_STATE]` (`0` = AM, `1` = PM), 3 weights, hidden in ambient.
- **Weather complication:** `SHORT_TEXT` with dual icon support (`ICON` / `MONOCHROMATIC_IMAGE`), plus image types. Default `EMPTY`.
- **Next Event complication:** `LONG_TEXT` (title + text) default provider `NEXT_EVENT`.
- **Logo:** "PanSar" in `corinthia` font, launches Contacts (`com.google.android.contacts`), hidden in ambient.
- **Ambient dimming overlay:** full-screen `#85000000` rectangle, visible only in ambient (last element in the `Scene`).

---

## 5. Watch Face Layout Specification

### A. Outer Ring Widgets (clockwise, `widget 1` to `widget 12`)
All ring widgets are hidden in ambient mode.

| Widget | Position | Content | Tap Action |
|---|---|---|---|
| `widget 1` (12 o'clock) | `x=193, y=7` (65x65) | Battery: `35 x 10` bar (toggled by `showBattery`) + `[BATTERY_PERCENT]%` | `BATTERY_STATUS` |
| `widget 2` (~1 o'clock) | `x=298, y=41` (65x65) | `icon_heart` + `round([HEART_RATE])` | `HEALTH_HEART_RATE` |
| `widget 3` (~2 o'clock) | `x=381, y=111` (40x40) | `icon_fitness` + Slot 1 (`slotId="4"`) | Complication |
| `widget 4` (~3 o'clock) | `x=403, y=205` (40x40) | `icon_timer` + Slot 2 (`slotId="5"`) | Complication |
| `widget 5` (~4 o'clock) | `x=378, y=305` (40x40) | `icon_camera` (fixed launcher) | Camera (`com.google.android.GoogleCamera`) |
| `widget 6` (~5 o'clock) | `x=315, y=374` (40x40) | `icon_mic` + Slot 3 (`slotId="6"`) | Complication |
| `widget 7` (6 o'clock) | `x=188, y=399` (76x46) | "PanSar" logo, `corinthia` size 32 | Contacts |
| `widget 8` (~7 o'clock) | `x=102, y=375` (40x40) | `icon_home` + Slot 4 (`slotId="7"`) | Complication |
| `widget 9` (~8 o'clock) | `x=33, y=305` (40x40) | `icon_nest` + Slot 5 (`slotId="8"`) | Complication |
| `widget 10` (~9 o'clock) | `x=7, y=205` (40x40) | `icon_inventory` + Slot 6 (`slotId="9"`) | Complication |
| `widget 11` (~10 o'clock) | `x=19, y=111` (65x65) | Weather complication (`slotId="2"`) | Complication |
| `widget 12` (~11 o'clock) | `x=80, y=42` (65x66) | `icon_steps` + `[STEP_COUNT]` | `health://steps` |

- **Shortcut slots (`slotId` 4–9):** invisible (`alpha="0"`) 40x40 tap targets placed over fixed icons tinted with `themeColor.1`. Default provider `APP_SHORTCUT` (`SMALL_IMAGE`). Supported: `SHORT_TEXT`, `SMALL_IMAGE`, `MONOCHROMATIC_IMAGE`, `RANGED_VALUE`.
- **Weather slot (`slotId` 2):** Supported: `SHORT_TEXT`, `SMALL_IMAGE`, `MONOCHROMATIC_IMAGE`, `EMPTY`.
- Widget value text: size 22, `NORMAL`, `themeColor.2`.

### B. Center Rows (top to bottom)
- **Row 1 – Date (`x=0, y=122, w=450, h=35`):** size 24, `NORMAL`, `themeColor.2`. Stays visible in ambient (dimmed by overlay).
- **Row 2 – Clock (`x=45, y=165, w=325, h=115`):** size 115, `themeColor.2`.
  - **Seconds (`x=375, y=172`):** size 24, `themeColor.1`.
  - **AM/PM (`x=375, y=238`):** size 20, `themeColor.1`, at the bottom of the seconds column.
- **Row 3 – Next Event (`x=75, y=285, w=300, h=48`, `slotId="3"`):** customizable (`isCustomizable="TRUE"`), default `NEXT_EVENT` (`LONG_TEXT`), fallback text "Next event" when empty. Supported: `LONG_TEXT`, `SHORT_TEXT`, `SMALL_IMAGE`, `MONOCHROMATIC_IMAGE`, `EMPTY`.

### C. Complication Slot IDs
| Slot ID | Purpose |
|---|---|
| `2` | Weather |
| `3` | Next Event |
| `4`–`9` | Ring shortcuts (Slot 1 … Slot 6) |

---

## 6. Critical Watch Face Format (WFF) Rules & Gotchas

> [!WARNING]
> These rules were discovered through real hardware testing. Violating any of them will break rendering on Wear OS devices.

1. **`displayName` Must Reference String Resource Names (No `@string/` prefix):**
   - In `<UserConfigurations>`, use `displayName="config_show_battery_bar"`.
   - **Do NOT** use string literals like `displayName="Show Battery"` (Wear OS will display "1st setting" instead).
   - **Do NOT** use `@string/config_show_battery_bar`. Use only the resource identifier name.

2. **Never Put `<Transform>` Inside `<TimeText>`:**
   - Placing `<Transform target="alpha" ...>` directly inside `<TimeText>` is invalid and hides the clock.
   - **Correct Solution:** Wrap `<DigitalClock>` inside an enclosing `<Group>` and apply the `<Transform target="alpha" ...>` to that `<Group>`.

3. **ListConfiguration Values in Expressions are Integers:**
   - Evaluate list options as numbers: `[CONFIGURATION.clockWeight] == 0`.
   - **Do NOT** use quotes around numbers (e.g. `'0'` breaks conditional rendering).

4. **Weather Complication Support:**
   - Weather providers supply either colored or monochrome icons. Always handle both:
     ```xml
     <PartImage x="..." y="..." width="..." height="...">
         <Image resource="[COMPLICATION.ICON]" />
     </PartImage>
     <PartImage x="..." y="..." width="..." height="..." tintColor="[CONFIGURATION.themeColor.1]">
         <Image resource="[COMPLICATION.MONOCHROMATIC_IMAGE]" />
     </PartImage>
     ```

5. **Ambient Mode Optimization:**
   - Minimize lit pixels in ambient mode to prevent OLED burn-in and save power.
   - Add `<Variant mode="AMBIENT" target="alpha" value="0" />` to non-essential elements (seconds, AM/PM, battery, logo, background, shortcut slots, complications).

6. **TimeText Formatting & 12h / 24h Notation (`hourFormat`):**
   - `<TimeText>` does **not** support Java-style `HH:mm`. Using `format="HH:mm"` makes the clock fail silently.
   - Always use `format="hh:mm"` (two `h` characters enforce leading zero padding).
   - Control 12h / 24h with the `hourFormat` attribute: `"24"`, `"12"`, or `"SYNC_TO_DEVICE"` (default).

---

## 7. Build, Validation & Deployment Guide

Run all commands below from the `watchface/` folder (`cd watchface`).

### A. Prerequisites
- Java JDK 17 or higher
- Android SDK with Platform 36 & 37 installed
- Android Debug Bridge (`adb`) in system `PATH`

### B. Validation
Validate WFF syntax with Google's official validator:
```powershell
java -jar "tools\wff-validator.jar" 2 "app/src/main/res/raw/watchface.xml"
```

### C. Building
```powershell
# Build debug APK
.\gradlew.bat assembleDebug

# Build release APK
.\gradlew.bat assembleRelease
```

### D. Wireless Debugging & Deployment on Wear OS Watch
1. On the watch: enable **Developer options** → **Wireless debugging**.
2. Note the IP address and dynamic port shown (e.g., `192.168.1.176:37805`).
3. Connect and install:
   ```powershell
   adb connect <WATCH_IP>:<PORT>
   adb devices
   .\gradlew.bat installDebug
   ```
4. Select the watch face on the watch picker or in the companion app (Galaxy Wearable / Pixel Watch app).

### E. Launching Local Wear OS Emulators (Windows / Antigravity)
When launching a local emulator, always follow this exact workflow:
1. **Find and list all available local emulators first:**
   ```powershell
   & "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -list-avds
   ```
2. **Ask the user to select an emulator:** Present the discovered AVDs to the user (using the `ask_question` tool or a direct prompt) and wait for their selection before launching.
3. **Launch the selected emulator via WMI (`Win32_Process`):**
   - **Important:** Do **not** launch `emulator.exe` with `Start-Process` or a standard foreground command in `run_command`, because Windows terminates child processes attached to the temporary PowerShell job object when the command exits.
   - Always spawn `emulator.exe` via WMI (`Win32_Process`) so it runs as an independent desktop process:
     ```powershell
     Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe -avd <SELECTED_AVD_NAME>" }
     ```

---

## 8. Git & Contribution Guidelines

- **Primary Branch:** `master`
- **Origin Remote:** `https://github.com/Panaith/watchface_total_view.git`
- Validate `watchface.xml` and verify `.\gradlew.bat assembleDebug` succeeds before committing.
- Keep commits focused, clean, and atomic (Conventional Commits style, e.g. `refactor(wff): ...`, `docs: ...`).
