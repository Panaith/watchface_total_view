# Watch Face Total View (`watchface_total_view`)

## 1. Project Overview & Philosophy

`watchface_total_view` is a comprehensive, feature-rich digital watch face for Wear OS (Wear OS 4 / 5+).
It is built strictly using Google's declarative **Watch Face Format (WFF)** Version 1.

- **Package / Application ID:** `com.pansar.watchface_total_view`
- **Target OS:** Wear OS 4+ (minSdk 36, targetSdk 37, compileSdk 37)
- **IDE / Environment:** Visual Studio Code and Google Antigravity IDE. Do **not** commit Android Studio / JetBrains `.idea/` directory files or cache artifacts.

---

## 2. Declarative Architecture (`android:hasCode="false"`)

This watch face runs entirely on Wear OS system rendering services without custom Kotlin/Java runtime code:
1. `AndroidManifest.xml` explicitly defines `android:hasCode="false"`.
2. All visual layouts, complications, user settings, animations, dynamic color bindings, and ambient modes are defined in XML under `watchface/src/main/res/raw/watchface.xml`.
3. Never attempt to add Kotlin or Java classes, activities, or services for watch face logic. All logic must be expressed using WFF expressions and XML tags.

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
│   ├── libs.versions.toml             # Version catalog (Android Gradle Plugin, etc.)
│   └── wrapper/                       # Gradle wrapper binaries
└── watchface/                         # Core watch face module
    ├── build.gradle.kts               # Module build configuration (minSdk 36, targetSdk 37)
    └── src/main/
        ├── AndroidManifest.xml        # Declares standalone watch face with format version 1
        └── res/
            ├── drawable/              # Preview and static graphic assets
            │   └── preview.png        # Watch face preview thumbnail
            ├── font/
            │   └── corinthia.ttf      # Custom font
            ├── raw/
            │   └── watchface.xml      # Core declarative Watch Face Format definition
            ├── values/
            │   └── strings.xml        # Localization, config titles, and option labels
            └── xml/
                └── watch_face_info.xml # Watch face metadata (preview drawable)
```

---

## 4. Critical Watch Face Format (WFF) Rules & Gotchas

> [!WARNING]
> These rules were verified on Wear OS hardware. Violating any of them will break rendering on Wear OS devices.

1. **`displayName` Must Reference String Resource Names (No `@string/` prefix):**
   - In `<UserConfigurations>`, use `displayName="config_name"`.
   - **Do NOT** use string literals like `displayName="My Config"`.
   - **Do NOT** use `@string/config_name`. Use only the plain resource identifier name.

2. **Never Put `<Transform>` Inside `<TimeText>`:**
   - Placing `<Transform target="alpha" ...>` directly inside `<TimeText>` is invalid syntax in WFF v1 and completely disables/hides the clock.
   - **Correct Solution:** Wrap `<DigitalClock>` or `<TimeText>` inside an enclosing `<Group>` and apply the `<Transform target="alpha" ...>` to that `<Group>`.

3. **ListConfiguration Values in Expressions are Integers:**
   - In WFF expressions, evaluate list options as numbers: `[CONFIGURATION.someSetting] == 0`.
   - **Do NOT** use quotes around numbers (e.g. `'0'` evaluates incorrectly and breaks conditional rendering).

4. **Weather Complication Support:**
   - Weather providers supply both colored and monochrome icons depending on the user's provider.
   - Always define both:
     ```xml
     <PartImage x="..." y="..." width="..." height="...">
         <Image resource="[COMPLICATION.ICON]" />
     </PartImage>
     <PartImage x="..." y="..." width="..." height="..." tintColor="[CONFIGURATION.fontsColor]">
         <Image resource="[COMPLICATION.MONOCHROMATIC_IMAGE]" />
     </PartImage>
     ```

5. **Ambient Mode Optimization:**
   - Ambient mode on Wear OS OLED panels requires minimizing lit pixels to prevent burn-in and save power.
   - Add `<Variant mode="AMBIENT" target="alpha" value="0" />` to non-essential elements (seconds, dynamic battery meters, logo, background patterns, shortcut slots).

---

## 5. Build, Test & Deployment Guide

### A. Building
From the project root:
```powershell
# Build debug APK
.\gradlew.bat assembleDebug

# Build release APK
.\gradlew.bat assembleRelease
```

### B. Wireless Debugging & Deployment on Wear OS Watch
1. On the watch: Enable **Developer options** -> enable **Wireless debugging**.
2. Note the IP address and dynamic port shown (e.g., `192.168.1.176:<PORT>`).
3. Connect via ADB:
   ```powershell
   adb connect 192.168.1.176:<PORT>
   adb devices
   ```
4. Install debug build directly to the watch:
   ```powershell
   .\gradlew.bat installDebug
   ```
5. Apply/Switch to the watch face:
   Select `watchface_total_view` directly on the watch screen picker or in the companion Wear OS mobile app.
