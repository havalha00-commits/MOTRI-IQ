# MOTRI IQ — iOS publisher handoff

Source snapshot: commit f17c035ce14b713fe1076cf03f45e41929bbde10.
App: MOTRI IQ. Bundle identifier: com.motriiq.app. Version: 1.0.1+5. Minimum iOS: 15.0.
This is clean source, not a signed IPA or a claim of App Store readiness.

## Build on your Mac

1. Install Flutter 3.47.7 and current compatible Xcode from Apple. Run `flutter doctor -v` and complete Xcode setup.
2. Unzip into a simple path, e.g. `~/Projects/motri-iq`.
3. Run:

```sh
flutter pub get
flutter analyze
flutter test test/locale_wiring_test.dart test/play_release_test.dart
flutter build ios --simulator --debug
```

The iOS project uses Flutter Swift Package Manager integration. No Podfile is expected. Flutter regenerates `ios/Flutter/ephemeral` and Generated.xcconfig; do not add machine-specific files to source control.

4. Open `ios/Runner.xcworkspace` in Xcode. Select Runner > Signing & Capabilities, choose YOUR Apple Developer team and enable automatic signing. Register com.motriiq.app in that team or coordinate a bundle ID change with the owner. No team, provisioning profiles or signing certificates are included.
5. Test on a physical iPhone, including sign-in, permissions, photos, location, chat, listings, account deletion and external contact links. Test iPad layout if distributing to iPad.
6. Create the app in App Store Connect with the same bundle ID. Choose an unused build number if 5 is already used.
7. Build/archive:

```sh
flutter build ipa --release --build-name=1.0.1 --build-number=5
```

Use Xcode Organizer to validate/distribute to App Store Connect, or upload the signed IPA using Apple's Transporter. App Store Connect access and an active paid Apple Developer membership are required.

## Configuration and credentials

The source includes the existing public Supabase URL/publishable client key defaults. These are client configuration, not server credentials. For another environment, copy config/production.example.json to config/production.json and pass `--dart-define-from-file=config/production.json` to build commands. Never put a service-role key in the app.

No Android private keys, Apple certificates, provisioning profiles, access tokens, reviewer password or production secret config is included. Obtain a dedicated reviewer account from the owner privately. The nonsecret access instructions are in release/google_play/reviewer-access.md.

## Required before Apple review

- Paid business placements/wallet top-ups are restricted only for Android Play builds. iOS still exposes those flows. Resolve Apple's in-app purchase requirements or disable those features for the first iOS release before submission. Do not assume PLAY_STORE_BUILD disables them on iOS.
- Implement/test actual backend account and associated-data deletion. The current portal records manual requests; it does not perform backend deletion. Review Apple's in-app deletion requirements.
- Complete user-generated-content safeguards: terms acceptance, effective reporting, user blocking and moderation.
- Review privacy disclosures for precise coordinates sent to public Nominatim reverse geocoding; verify retention, processor/service relationships and backend practices.
- Audit merged privacy manifests and required-reason API declarations of all SDKs. Complete App Privacy from actual collection/sharing; do not copy Google Play answers blindly.
- Google Mobile Ads SDK was removed. Info.plist retains an unused sample GADApplicationIdentifier; review/remove obsolete metadata before final release.
- Supply App Store-specific iPhone/iPad screenshot dimensions. Google Play images included here are reference material, not automatically valid Apple screenshots.
- Complete age rating, export compliance/encryption answers, rights/contact information and review notes accurately. Review Sign in with Apple applicability if adding social login.

## Public links

Support: in-app Support Center
Website: https://motri-iq.me-0eca.chatgpt.site/
Privacy: https://motri-iq.me-0eca.chatgpt.site/privacy/
Deletion request: https://motri-iq-account-deletion.me-0eca.chatgpt.site/

## Verification already performed

Clean source snapshot: flutter analyze passed; focused locale/Play tests: 15 passed, 3 skipped. Earlier native iOS UI checks are documented in the project; a current signed iOS distribution build and App Store validation were not performed for this handoff.
