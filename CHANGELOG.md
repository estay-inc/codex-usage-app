# Changelog

All notable changes to this project will be documented in this file.

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
