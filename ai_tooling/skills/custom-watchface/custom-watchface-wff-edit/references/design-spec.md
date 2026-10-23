# Watch Face Total View — design spec

The face as it is defined in `watchface/app/src/main/res/raw/watchface.xml`. Keep this file in step
with every change there (`custom-watchface-wff-edit`, step 5).

## Contents

- [Canvas](#canvas)
- [User settings](#user-settings)
- [Components](#components)
- [Outer ring widgets](#outer-ring-widgets)
- [Center rows](#center-rows)
- [Complication slot ids](#complication-slot-ids)

## Canvas

**450 × 450** circular display (`clipShape="CIRCLE"`, `CLOCK_TYPE=DIGITAL`).

## User settings

`<UserConfigurations>`:

| Configuration id | Type | Options / values | Default | Description |
|---|---|---|---|---|
| `themeColor` | Color | 11 options (`0`–`10`), see below | `0` (White) | Three-color theme palette |
| `bgImage` | List | `0`–`8` → `background_1` … `background_9` | `0` | Background texture image |
| `clockFormat` | List | `0` (24 Hour), `1` (12 Hour) | `0` | Time format |
| `clockWeight` | List | `0` (Normal), `1` (Bold), `2` (Light) | `0` | Font weight for clock, seconds, AM/PM |
| `showSeconds` | Boolean | `TRUE` / `FALSE` | `TRUE` | Toggle seconds display |
| `showBattery` | Boolean | `TRUE` / `FALSE` | `TRUE` | Toggle battery progress bar |

**`themeColor` color roles** (every option defines 3 colors):

- `[CONFIGURATION.themeColor.0]` — background tint (always black).
- `[CONFIGURATION.themeColor.1]` — accent: icons, monochrome images, progress bars, secondary labels.
- `[CONFIGURATION.themeColor.2]` — primary text: clock, date, values.
- Options `0`–`5` are single-tone (White, Cyan, Orange, Green, Blue, Dark Red); options `6`–`10` are dual-tone
  (colored accent + white primary text).

**Flavors (presets):** `1` = Default (`themeColor=0`, `bgImage=0`), `2` = Variant (`themeColor=7`, `bgImage=7`). Each
flavor also re-declares the default provider policy of every complication slot.

## Components

- **Background:** solid `PartDraw` tinted with `themeColor.0` + `bgImage` texture `ListConfiguration`. Both hidden in ambient.
- **Battery widget:** launches `BATTERY_STATUS`; `[BATTERY_PERCENT]%` text + horizontal progress bar toggled by
  `showBattery`. The bar is red (`#ff0101`) at 0–9% and `themeColor.1` at 10–100%.
- **Date:** `PartText` with `%s, %s %s %s` template (`DAY_OF_WEEK_S`, `DAY`, `MONTH_S`, `YEAR`), Gregorian calendar,
  launches `CALENDAR`.
- **Digital clock:** `Group` launching `ALARM`. 2 formats × 3 weights = 6 `DigitalClock` variants toggled by alpha `Transform`s.
- **Seconds:** `TimeText format="ss"` in 3 weights, toggled by `showSeconds`, hidden in ambient.
- **AM/PM:** shown only when `clockFormat == 1`, via `[AMPM_STATE]` (`0` = AM, `1` = PM), 3 weights, hidden in ambient.
- **Weather complication:** `SHORT_TEXT` with dual icon support (`ICON` / `MONOCHROMATIC_IMAGE`), plus image types. Default `EMPTY`.
- **Next Event complication:** `LONG_TEXT` (title + text), default provider `NEXT_EVENT`.
- **Logo:** "PanSar" in the `corinthia` font, launches Contacts (`com.google.android.contacts`), hidden in ambient.
- **Ambient dimming overlay:** full-screen `#85000000` rectangle, visible only in ambient (last element in the `Scene`).

## Outer ring widgets

Clockwise, `widget 1` to `widget 12`. All ring widgets are hidden in ambient mode.

| Widget | Position | Content | Tap action |
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

- **Shortcut slots (`slotId` 4–9):** invisible (`alpha="0"`) 40x40 tap targets placed over fixed icons tinted with
  `themeColor.1`. Default provider `APP_SHORTCUT` (`SMALL_IMAGE`). Supported: `SHORT_TEXT`, `SMALL_IMAGE`,
  `MONOCHROMATIC_IMAGE`, `RANGED_VALUE`.
- **Weather slot (`slotId` 2):** supported: `SHORT_TEXT`, `SMALL_IMAGE`, `MONOCHROMATIC_IMAGE`, `EMPTY`.
- Widget value text: size 22, `NORMAL`, `themeColor.2`.

## Center rows

Top to bottom:

- **Row 1 – Date (`x=0, y=122, w=450, h=35`):** size 24, `NORMAL`, `themeColor.2`. Stays visible in ambient (dimmed by the overlay).
- **Row 2 – Clock (`x=45, y=165, w=325, h=115`):** size 115, `themeColor.2`.
  - **Seconds (`x=375, y=172`):** size 24, `themeColor.1`.
  - **AM/PM (`x=375, y=238`):** size 20, `themeColor.1`, at the bottom of the seconds column.
- **Row 3 – Next Event (`x=75, y=285, w=300, h=48`, `slotId="3"`):** customizable (`isCustomizable="TRUE"`), default
  `NEXT_EVENT` (`LONG_TEXT`), fallback text "Next event" when empty. Supported: `LONG_TEXT`, `SHORT_TEXT`,
  `SMALL_IMAGE`, `MONOCHROMATIC_IMAGE`, `EMPTY`.

## Complication slot ids

| Slot id | Purpose |
|---|---|
| `2` | Weather |
| `3` | Next Event |
| `4`–`9` | Ring shortcuts (Slot 1 … Slot 6) |
