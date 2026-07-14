# Codex Usage App

<p align="center">
  <img src="Resources/AppIcon.svg" width="128" alt="Codex Usage App icon">
</p>

An unofficial, open-source macOS menu bar utility that shows the remaining
weekly Codex limit plus consumption since local midnight and during the last
hour. It also shows the 5-hour limit when Codex returns one.

[日本語 README](README.ja.md)

<p align="center">
  <a href="https://github.com/estay-inc/codex-usage-app/releases/latest/download/Codex-Usage-App.dmg"><strong>Download for macOS (.dmg)</strong></a>
</p>

![macOS](https://img.shields.io/badge/macOS-13%2B-black)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

## What it does

- Shows the remaining weekly limit (`W`), consumption today (`1D`), and rolling
  one-hour consumption (`1H`) in the menu bar.
- Shows the remaining 5-hour limit (`5h`) only when it is available.
- Displays used percentage, reset time, plan, and last update time.
- Refreshes automatically every two minutes.
- Supports launching at login through macOS `SMAppService`.
- Switches the app UI automatically between English and Japanese based on the
  macOS language setting.
- Keeps up to 48 hours of usage history locally; there is no analytics or
  developer-operated backend.

## In the menu bar

<p align="center">
  <img src="docs/images/usage-details.png" width="255" alt="Codex Usage App usage details menu">
</p>

- `W 82%` means 82% of the weekly limit remains.
- `1D 6%` means 6% of the weekly limit was used since local midnight.
- `1H 2%` means 2% of the weekly limit was used during the last hour.
- On the first day after updating, the app shows `1D …` if it cannot determine
  the midnight baseline. It also avoids estimating across a weekly reset during
  the day. It shows `1H …` while collecting its first hour of history.
- The normal title is `W 82%  1D 6%  1H 2%`. When a 5-hour window is available,
  it looks like `5h 70%  W 82%  1D 6%  1H 2%`.
- Click the status item to see used percentages, reset times, your plan, and
  the last update time.

## Requirements

- macOS 13 or later.
- Apple Silicon or Intel Mac.
- One of the following installed and signed in:
  - ChatGPT/Codex desktop app, or
  - Codex CLI.

The app talks to the local [Codex App Server](https://learn.chatgpt.com/docs/app-server)
and calls the documented `account/rateLimits/read` method. It never reads or
stores your ChatGPT tokens itself.

## Install a release

1. Download and open [Codex-Usage-App.dmg](https://github.com/estay-inc/codex-usage-app/releases/latest/download/Codex-Usage-App.dmg).
2. Open the DMG, then open `Codex Usage.app`.
3. Click **Move and Open** when the app asks to move itself to `/Applications`.
4. If macOS blocks an unsigned community build, Control-click the app in Finder
   and choose **Open** once.
5. Optionally enable **Launch at Login** from the menu.

Community release builds are ad-hoc signed, not Apple-notarized.

## Build from source

Xcode is not required; the Swift toolchain included with Xcode Command Line
Tools is sufficient.

```bash
git clone https://github.com/estay-inc/codex-usage-app.git
cd codex-usage-app
./scripts/build.sh
open "build/Codex Usage.app"
```

Create a universal binary and ZIP package:

```bash
ARCHS=universal PACKAGE=1 ./scripts/build.sh
```

Create the DMG used for GitHub Releases:

```bash
ARCHS=universal DMG=1 ./scripts/build.sh
```

Run the live usage test on a Mac already signed in to Codex:

```bash
CODEX_USAGE_LIVE_TEST=1 ./scripts/test.sh
```

If Codex is installed in a custom location, set `CODEX_PATH` to the absolute
path of the executable before launching the app.

## Privacy

See [PRIVACY.md](PRIVACY.md). To calculate daily and one-hour consumption, the
app keeps only the last 48 hours of timestamps and usage percentages in macOS
`UserDefaults`. The app starts the locally installed Codex App Server, which
communicates with OpenAI under the user's existing account and OpenAI terms.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md)
and [SECURITY.md](SECURITY.md).

## License and trademark notice

The source code in this repository is licensed under the [MIT License](LICENSE).

This project is unofficial and is not affiliated with, endorsed by, or
sponsored by OpenAI. Codex, ChatGPT, OpenAI, and related marks are trademarks of
OpenAI. This project does not include OpenAI logos or bundle OpenAI software.
Codex itself is available separately from OpenAI under the
[Apache-2.0 License](https://github.com/openai/codex).
