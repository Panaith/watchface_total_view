# watchface

**Purpose: the Watch Face Total View watch face for Wear OS 6+, written in Watch Face Format v2 and built into an installable APK.**

## Tech Stack

- **Watch Face Format (WFF)**: declarative XML that the Wear OS system renders; the APK carries no
  code of its own.
- **Gradle** with the Android Gradle Plugin, through the wrapper.
- Google's WFF validator, checked in as `tools/wff-validator.jar`.
- No other apps or services: the face reads only Wear OS data sources and complication providers.

The exact versions (WFF, SDK levels, AGP, Gradle, daemon JVM), the application id and the publisher
are in [Critical Version Constraints](../AGENTS.md#critical-version-constraints). The design of the
face (canvas, user settings, widgets, complication slots, layout) is described in the
[design spec](../../ai_tooling/skills/custom-watchface/custom-watchface-wff-edit/references/design-spec.md).

```
watchface/
├── .gitignore                     # Gradle caches, build output, local.properties
├── build.gradle.kts
├── gradle.properties              # Gradle / AndroidX properties
├── settings.gradle.kts            # rootProject.name = "watchface_total_view", include ":app"
├── gradle/                        # libs.versions.toml (AGP), daemon JVM, wrapper
├── gradlew, gradlew.bat           # Gradle wrapper
├── tools/wff-validator.jar        # Google's WFF validator
└── app/                           # Gradle module ":app"
    ├── build.gradle.kts           # SDK levels, application id
    └── src/main/
        ├── AndroidManifest.xml    # standalone watch face, WFF version, publisher
        ├── keepRules/rules.keep   # R8 keep rules (template, unused)
        └── res/
            ├── drawable/          # background_1..9.png, icon_*.png, preview.png
            ├── font/corinthia.ttf # script font of the "PanSar" logo
            ├── raw/watchface.xml  # the watch face definition
            ├── values/strings.xml # setting titles and option labels
            └── xml/               # watch_face_info.xml (preview, editable, flavors on, multiple instances), watch_face_shapes.xml (display shape)
```

## Installations

- Java JDK 17 or higher on `PATH` (for Gradle's launcher and the validator); Gradle provisions its
  daemon JVM itself.
- Android SDK with the platforms of the SDK levels in
  [Critical Version Constraints](../AGENTS.md#critical-version-constraints), and Android Debug Bridge
  (`adb`) on `PATH`.
- For the emulator: a Wear OS AVD in the Android SDK emulator (`%LOCALAPPDATA%\Android\Sdk\emulator`).

## How to Develop

1. Edit `app/src/main/res/raw/watchface.xml` and the resources next to it.
2. Validate (How to Test and Lint), build (How to Build), and install on a watch or emulator (How to Debug).

## How to Debug

**On a watch, over Wi-Fi:**

1. On the watch: enable **Developer options**, then **Wireless debugging**.
2. Note the IP address and port it shows (for example `192.168.1.176:37805`).
3. From `watchface/`:
   ```powershell
   adb connect <WATCH_IP>:<PORT>
   adb devices
   ```
4. Install with the **Run** command of [watchface/AGENTS.md](../AGENTS.md#commands).
5. Select the face in the watch's face picker or in the companion app (Galaxy Wearable, Pixel Watch).

**On an emulator:** list the AVDs and start one as section 3 of
[custom-watchface-device-deploy](../../ai_tooling/skills/custom-watchface/custom-watchface-device-deploy/SKILL.md)
describes, then install and select the face as above (steps 4 and 5).

A face that renders nothing, or a setting labelled "1st setting", is almost always one of the
WFF rules found on real hardware broken in `watchface.xml`
([custom-watchface-wff-edit](../../ai_tooling/skills/custom-watchface/custom-watchface-wff-edit/SKILL.md), section 2).

## How to Build

Run the **Build** commands of [watchface/AGENTS.md](../AGENTS.md#commands). The APKs land in
`app/build/outputs/apk/debug/` and `app/build/outputs/apk/release/`. No pipeline builds the app.

## How to Test and Lint

There are no unit or E2E tests. Before every commit, run the **Lint** command of
[watchface/AGENTS.md](../AGENTS.md#commands) (Google's WFF validator), then check the face on a
device or emulator (How to Debug), in active and ambient mode.
