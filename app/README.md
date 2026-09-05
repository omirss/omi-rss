# Omi RSS App

> **Frozen — future mobile client.** As of v0.3.0 the Flutter client is not
> part of the shipped product: the Neutron web app (`../web/`) replaced both
> the Express server and the Flutter web UI. This code is kept intact as the
> starting point for a future iOS/Android client against the same API; it is
> not under active development. The notes below describe it as it shipped in
> v0.2.

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
flutter build web --release     # web build (served by the frozen v0.2 stack; not part of v0.3)
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

Frozen at v0.2 (`flutter analyze` on Flutter 3.47.2: 0 errors, ~31 warnings,
~323 infos; tests pass, web build verified against the v0.2 server); native/
desktop builds untested for release. The shipped product is the Neutron web
app (`../web/`), v0.3.0. See the repository PLAN.md for details.

## License

MIT — see the repository LICENSE.
