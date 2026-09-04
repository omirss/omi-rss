# Omi RSS App

The Omi RSS reader client — a Flutter app (project `rss_glassmorphism_reader`)
for desktop, web, and mobile.

Local-first: subscriptions and articles live in on-device storage (drift /
SQLite, sql.js on web). The server is optional — set its URL in the app's
settings to sync against a self-hosted Omi RSS instance; on web the default is
the serving origin.

## Features

- Feed management with folders and OPML import/export
- Article reading with read/star state and search
- Local-first storage; optional server sync
- Glassmorphism UI with dark and light themes
- Reading stats when paired with a server

## Requirements

- Flutter 3.22+ / Dart 3.0+
- For desktop builds: platform toolchain (Xcode, Visual Studio, or Linux build
  tools)

## Run

```bash
flutter pub get
flutter run                     # native desktop
flutter run -d chrome           # web
```

Point the app at a server in Settings (server URL), or run it standalone —
feeds are fetched and stored locally either way.

## Test and build

```bash
flutter test                    # widget tests
flutter analyze
flutter build web --release     # web build (used by ../build-web.sh)
flutter build macos --release   # or windows / linux
```

Native/desktop release builds exist but are not yet exercised for release;
the web build is the verified path (it is what the server optionally serves
as a web UI).

## Structure

```
lib/
  core/         models, services, parsers, database (drift)
  ui/           screens and components
app/
  assets/       images, fonts
  web/          web platform scaffolding
```

## Status

v0.2.0 alpha — reader core works on web (analyze clean, tests pass, build
verified); native/desktop builds untested for release. See the repository
PLAN.md for details.

## License

MIT — see the repository LICENSE.
