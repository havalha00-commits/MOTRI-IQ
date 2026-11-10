# MOTRI IQ client web preview

First Codemagic build passed on 2026-10-23 (commit f1ea83a, 3m14s). The published page was opened in Chrome and live listings were visually verified.

Build: https://codemagic.io/app/6adb4d088693820398aa5ece/build/6adb4d9c4a72334e32e46031

Build verified locally with Flutter 3.47.7 stable:

```sh
flutter pub get
flutter build web --release
```

Use Codemagic **Flutter workflow editor**, not YAML, for Codemagic Static Pages.

1. Add the private GitHub source repository as a Flutter application.
2. Select only Web, Flutter 3.47.7 stable and Release mode.
3. Under Distribution → Codemagic Static Pages, select an available one-level preview subdomain and enable publishing. Keep publishing on failed tests disabled.
4. Start the build from main and verify the resulting HTTPS URL before sharing it with the client.

The web application currently uses the same Supabase endpoint and browser-safe publishable key as the mobile app. Real account actions use that backend. Never put a service-role key or signing credentials in a web build. Custom backend values can be supplied with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY Dart defines.

Codemagic Static Pages is a testing/preview service. Client preview access does not establish production backend, store or operational readiness. Email/OAuth recovery redirects must allow the exact preview URL when those flows are enabled.

Source upload excludes local signing keys, generated output, browser profiles and historical backup copies. The original working checkout and its Git history remain intact.

Reference: https://docs.codemagic.io/flutter-distributing/publishing-to-codemagic-static-pages/
