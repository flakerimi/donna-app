# Donna app

The phone app for [Donna](https://github.com/flakerimi/donna), a personal
AI assistant built on the [harness](https://github.com/flakerimi/harness)
engine. It is a Flutter client for the engine's HTTP and SSE API, so it works
against any harness server, not only Donna: enter a server URL and an API
token on the connect screen and the rest follows.

## What is in it

- **Chat** that streams the answer as it is written, shows tool calls as they
  run, and takes photos from the camera or the library as attachments.
- **Sessions**: past conversations, resumable.
- **Tasks**: the background work the assistant is running or has finished.
- **Inbox**: what scheduled work delivered (a morning briefing, a pulse), with
  an unread badge, a push notification on arrival, and a thumbs up or down
  that feeds the assistant's memory.
- **Settings**: server, token, profile.

Push arrives through APNs. The app registers its device token with the server
(`POST /v1/push/register`), and the server's schedules deliver to the app
instead of to a chat bot.

## Layout

- `lib/api/` — `HarnessClient` and the wire models
- `lib/state/` — one `InheritedNotifier` holds app state; no state package
- `lib/screens/` — connect, home shell with bottom navigation, chat, sessions,
  tasks, inbox, settings
- `lib/push/` — the APNs registration, with its native half in
  `ios/Runner/AppDelegate.swift`
- `test/` — the client is tested against a real local HTTP server

Dependencies are kept to a handful: `http`, `flutter_markdown_plus`,
`shared_preferences`, `image_picker`.

## Building

```sh
flutter pub get
flutter run
```

To bake in a default server so the connect screen is pre-filled, copy
`lib/config.example.dart` to `lib/config.dart` and fill it in. `config.dart`
is gitignored and never committed.

```sh
flutter analyze
flutter test
```

Both must stay clean.

## Releasing to TestFlight

`release.sh` bumps the build number, archives and uploads. It takes either an
App Store Connect API key (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`) or an
app-specific password stored in the keychain as `AC_PASSWORD`.
`upload-testflight.sh` uploads an existing archive with the API key alone,
with no Xcode sign-in:

```sh
flutter build ipa --release --no-codesign
ASC_ISSUER_ID=<issuer id> ./upload-testflight.sh
```

Bundle identifier `al.basecode.harnessApp`, display name Donna.
