# Changelog

All notable changes to this project will be documented in this file.

## 1.7.1 - 2026-07-23

- Keep daily usage stable when Codex adjusts a rate-limit reset timestamp by a
  few seconds.
- Ignore small downward usage corrections when accumulating today's observed
  consumption, while preserving real rate-limit resets.

## 1.7.0 - 2026-07-15

- Remove rolling one-hour usage (`1H`) from the menu bar and detail menu.
- Rename daily usage from `1D` to `D` and remove the `+` marker from partial
  daily values.

## 1.6.1 - 2026-07-15

- Remove the red and green depletion-risk colors from the `1D` and `1H`
  percentages and restore the standard menu-bar text color.

## 1.6.0 - 2026-07-14

- Color the `1D` and `1H` percentages red when their projected daily or hourly
  pace would exhaust the remaining total limit by its reset, and green when
  projected consumption stays below the remaining limit.
- Keep the normal menu-bar color when the reset time or a measured percentage
  is unavailable.
- Base partial `1D …%+` projections on the known lower-bound usage.

## 1.5.3 - 2026-07-14

- Rename the total-limit abbreviation from `W` to `T` and update the detailed
  menu label from weekly to total.

## 1.5.2 - 2026-07-14

- Show a lower-bound daily value such as `1D 3%+` when the app starts after
  midnight and cannot recover the full day's usage.
- Start partial daily tracking immediately at `1D 0%+`, then switch to the
  exact `1D` value when the full-day total can be determined reliably.

## 1.5.1 - 2026-07-14

- Rename the menu bar abbreviations from `D` and `1h` to `1D` and `1H`.

## 1.5.0 - 2026-07-14

- Show today's weekly-limit consumption as `D` alongside weekly remaining and
  rolling one-hour consumption.
- Keep up to 48 hours of local samples so daily usage can be calculated from
  the Mac's local midnight.
- Avoid showing a daily estimate when the midnight baseline or a weekly reset
  boundary cannot be determined exactly.

## 1.4.1 - 2026-07-14

- Show both the remaining weekly limit (`W`) and rolling one-hour consumption
  (`1h`) in the menu bar.

## 1.4.0 - 2026-07-14

- Replace the weekly `W` percentage in the menu bar with the percentage used
  during the last hour.
- Keep two hours of rate-limit samples locally so the rolling one-hour value
  survives app restarts.
- Show `1h …` while the first hour of history is being collected.

## 1.3.2 - 2026-07-13

- Hide the `5h` placeholder from the menu bar when the App Server does not
  return a 5-hour limit.
- Show only the usage windows currently available from Codex.

## 1.3.1 - 2026-07-13

- Classify 5-hour and weekly limits by their window duration instead of their
  position in the App Server response.
- Show a weekly-only response under `W` when the current plan does not return a
  separate 5-hour window.

## 1.3.0 - 2026-07-13

- Add native English and Japanese localization resources.
- Follow the macOS app language setting automatically.
- Localize the installation flow, menu items, status details, dates, and errors.
- Add automated localization validation for both languages.

## 1.2.0 - 2026-07-12

- Rename the open-source project to Codex Usage App.
- Add a minimal monochrome app icon representing the 5-hour and weekly limits.
- Remove the decorative chart icon from the menu bar and show usage values only.
- Publish the project through the ESTAY GitHub organization.

## 1.1.0 - 2026-07-12

- Add a DMG package containing the app and an Applications shortcut.
- Prompt to move the app to `/Applications` when launched elsewhere.
- Replace an existing installed copy safely and reopen the installed app.
- Add a relocation self-test for release validation.

## 1.0.0 - 2026-07-12

- Display remaining 5-hour and weekly Codex usage in the macOS menu bar.
- Show usage percentage, reset time, plan, and last update time.
- Refresh automatically every two minutes.
- Add launch-at-login support.
- Add a live App Server self-test.
