---
name: custom-watchface-device-deploy
description: Installs and runs the Watch Face Total View watch face on a Wear OS watch over wireless adb or on a local Wear OS emulator, on Windows. Use when asked to install, deploy, run or try the face, to start or launch an emulator or AVD, or to connect a watch with adb.
---

# Running the watch face on a watch or emulator

**Owner:** project-owned, edited directly (see `custom-aitooling-maintain`).

`ai_tooling/PERMISSIONS.md` applies; treat a running emulator and the `adb` server as the user's processes
(section 5). This skill
makes no writes to GitHub.

Commands run from `watchface/`. Run the **Lint** and **Build** commands of `watchface/AGENTS.md` first: an install of
a face that fails validation tells you nothing.

## 1. Pick the target

Ask the user, as one question, whether to use a **watch** (section 2) or an **emulator** (section 3), unless they
said so already. `adb devices` shows what is connected now; if the target is listed, go to section 4.

## 2. A watch over wireless debugging

Steps 1 to 3 of "How to Debug" in [watchface/documentation/overview.md](../../../../watchface/documentation/overview.md#how-to-debug):
the user enables wireless debugging on the watch and reads you the IP address and port; you run the `adb connect` and
`adb devices` shown there.

## 3. A local Wear OS emulator

Always follow these steps in this order:

1. **List the emulators:**
   ```powershell
   & "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -list-avds
   ```
2. **Ask the user to pick one** of the listed AVDs, as one clickable question, and wait for the answer.
3. **Launch it through WMI (`Win32_Process`)**, so it runs as a process of its own:
   ```powershell
   Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe -avd <SELECTED_AVD_NAME>" }
   ```
   Never start `emulator.exe` with `Start-Process` or as a foreground command of the agent's shell: Windows ends the
   child processes of the agent's temporary PowerShell job when the command returns, and the emulator dies with it.
4. Check that `adb devices` lists the emulator before installing.

## 4. Install and select

Run the **Run** command of `watchface/AGENTS.md` (it installs the debug build). The user then selects the face,
labelled `watchface_total_view` (the `watch_face_name` string), as step 5 of "How to Debug" in the overview says. Ask
them to report what they see; check active and ambient mode.
