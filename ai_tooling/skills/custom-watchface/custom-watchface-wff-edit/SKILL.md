---
name: custom-watchface-wff-edit
description: Edits the Watch Face Total View watch face in Watch Face Format v2 - watchface.xml, its strings, drawables, fonts and watch_face_info.xml - with the WFF pitfalls found on real hardware and the face's design spec. Use when changing the layout, a user setting, a complication slot, a widget, colors or ambient mode in watchface/.
---

# Editing the watch face (Watch Face Format v2)

**Owner:** project-owned, edited directly (see `custom-aitooling-maintain`).

`ai_tooling/PERMISSIONS.md` applies. This skill makes no writes to GitHub; commits follow the root `AGENTS.md`.

All paths are relative to `watchface/`, whose `AGENTS.md` applies: its version constraints, never-do rules and
commands are not repeated here.

## 1. Find your way

- What the face shows, where and why - settings, widgets, slot ids, coordinates, colour roles:
  [references/design-spec.md](references/design-spec.md). Read the part you are changing before you edit.
- The files next to `watchface.xml` (strings, drawables, font, `xml/` metadata): the tree in
  [watchface/documentation/overview.md](../../../../watchface/documentation/overview.md#tech-stack). The flavors
  (presets) are defined in `watchface.xml` itself (`<Flavors>`); `watch_face_info.xml` only switches them on.
- Assets of the original design live in `../project in WatchFace Studio/` (read only there; see its `AGENTS.md`).

## 2. Rules that break rendering on a device

These were found through testing on real hardware: violating any of them breaks rendering on Wear OS devices.
Check each one yourself in every change.

1. **`displayName` names a string resource, without `@string/`.** In `<UserConfigurations>` write
   `displayName="config_show_battery_bar"`. A literal (`displayName="Show Battery"`) shows as "1st setting" on the
   watch; `@string/config_show_battery_bar` does not work either.
2. **Never put a `<Transform>` inside `<TimeText>`.** `<Transform target="alpha" ...>` directly in `<TimeText>` is
   invalid and hides the clock. Wrap the `<DigitalClock>` in a `<Group>` and put the `<Transform>` on the `<Group>`.
3. **`ListConfiguration` values are integers in expressions.** `[CONFIGURATION.clockWeight] == 0`; never quote the
   number (`'0'` breaks the conditional rendering).
4. **A weather complication needs both icon kinds.** Providers send a coloured or a monochrome icon; render both:
   ```xml
   <PartImage x="..." y="..." width="..." height="...">
       <Image resource="[COMPLICATION.ICON]" />
   </PartImage>
   <PartImage x="..." y="..." width="..." height="..." tintColor="[CONFIGURATION.themeColor.1]">
       <Image resource="[COMPLICATION.MONOCHROMATIC_IMAGE]" />
   </PartImage>
   ```
5. **Keep ambient mode dark.** Light as few pixels as possible (OLED burn-in, battery): give every non-essential
   element `<Variant mode="AMBIENT" target="alpha" value="0" />` - seconds, AM/PM, battery, logo, background,
   shortcut slots, complications. The dimming overlay stays the last element of the `Scene`.
6. **`TimeText` takes `hh:mm`, never `HH:mm`.** Java-style `format="HH:mm"` makes the clock fail silently. Use
   `format="hh:mm"` (two `h` pad with a leading zero) and choose 12 h / 24 h with `hourFormat`: `"24"`, `"12"` or
   `"SYNC_TO_DEVICE"` (the default).

## 3. Conventions of this face

- Colours come from the theme's colour roles (design spec, "User settings"). Hard-code a colour only where the spec
  does (the red low-battery bar, the ambient overlay).
- A new user setting gets an id in `<UserConfigurations>`, its title and option labels in `strings.xml` (rule 1),
  and, if it changes a preset, a value in both flavors (`<Flavors>` in `watchface.xml`).
- A new complication slot gets the next free `slotId` (the table in the spec), and both flavors declare its default
  provider policy.

## 4. Check the change

From `watchface/`, with the commands in `watchface/AGENTS.md` (Commands):

1. **Lint** (the WFF validator) - no errors.
2. **Build** (`assembleDebug`) - succeeds.
3. Walk through the six rules of section 2 against your diff.
4. When the user wants to see it, install it with `custom-watchface-device-deploy` and check active and ambient mode,
   each setting you touched and each theme colour type (single-tone and dual-tone).

Do not commit before 1 and 2 pass (`watchface/AGENTS.md`).

## 5. Keep the spec in step

In the same commit, update [references/design-spec.md](references/design-spec.md) for every setting, widget,
position, slot, colour role or ambient behaviour you changed. A new pitfall found on a device goes into section 2
of this skill.
