# Privacy

Codex Usage App does not operate a backend service and does not include
analytics, advertising, crash-reporting SDKs, or telemetry controlled by this
project.

The app requests rate-limit information from a locally installed Codex App
Server. Usage values are displayed in the menu bar. To calculate the rolling
one-hour consumption, the app keeps up to two hours of timestamped percentage
samples in macOS `UserDefaults`. This history stays on the user's Mac and is
not transmitted to the project's maintainers or any developer-operated
backend.

The Codex App Server communicates with OpenAI using the account already signed
in on the user's Mac. That communication is governed by OpenAI's terms and
privacy policy. This project does not directly read, copy, or store ChatGPT
access tokens.

Opening ChatGPT from the menu launches the official local application. No data
is sent to the maintainers when that action is used.
