# MOTRI IQ — Play Console preparation (25 October 2026)

## Application

New app, never uploaded (publisher confirmed). Package com.motriiq.app; version 1.0.1 (5); minimum API24; target API36. Keep the upload key; enable Play App Signing. New upload key is valid for first registration. No existing upload-key reset is needed for this new app. Never upload key.properties or the private keystore with store materials.

Use the Play-specific build command:

```sh
flutter build appbundle --release --dart-define=PLAY_STORE_BUILD=true
```

Do not use the generic release command: the Play define disables digital business-placement/top-up routes before their state initializes. Paid-feature restrictions are Android Play-specific; the advertising SDK is removed from the current release source on all platforms. Upload only the final candidate identified by the SHA256 in artifacts/release-verification.json. Version code 5 was accepted by Play Console and saved under Production on 25 October 2026; review submission remains pending.

## Materials prepared

- Signed Android App Bundle and release APK, public signing certificate, R8 mapping and native symbols when present: artifacts/.
- English/Arabic title, short/full description and release notes: listing/.
- Store icon512×512 and feature graphic1024×500, editable vector: graphics/.
- Phone screenshots and their provenance: screenshots/ (verify selected screenshots before submission).
- Data safety worksheet, privacy-policy draft and deletion operations: policies/.
- Public account-deletion request URL: https://motri-iq-account-deletion.me-0eca.chatgpt.site/
- Administrator request queue: the same origin at /admin. Sign in with the configured support account. No automatic email alerts or app-backend deletion are configured.
- Support: in-app Support Center; configure any required contact details privately in Play Console.

## Required before review — still open

1. **UGC controls:** source review found car reporting/admin moderation, but no effective user-blocking flow for public listings/direct messages and no explicit terms acceptance before UGC creation. Google’s UGC policy requires those controls. Design/implement/test reporting and user blocking across cars/Market/jobs/reviews/messages, plus terms acceptance. Do not submit the current candidate as fully policy-compliant.
2. **Deletion operations:** public and in-app request paths exist, but the operator must verify ownership and actually delete linked account/database/storage data. Adopt/test the runbook and set precise processing and retention periods; request recording/status changes alone do not satisfy deletion handling.
3. **Full mobile privacy URL:** https://motri-iq.me-0eca.chatgpt.site/privacy/ is published for MOTRI IQ in English and Arabic. Actual record-specific retention, verified backend deletion and processing times still require operator confirmation and implementation. /privacy on the separate deletion site covers only that portal. Review the in-app policy so it matches actual practices. Data safety answers remain a worksheet until certified.
4. **Backend release hardening:** review/apply the wallet/receipt hardening migration only after a backup and coordinated rollout; verify Auth/RLS/Storage, real signup/recovery, moderation, owned-row access and delivery with staging accounts. No remote app-backend migration was run here.
5. **Advertising disabled for version code 5:** Google Mobile Ads/UMP removed; no advertising-ID permissions or paid business-ad feed. Set Contains ads = No for the new build after artifact verification. Re-enabling ads in a future release requires SDK/privacy/console review.
6. **Reviewer access:** provide a dedicated review user and clear instructions for every restricted feature. Avoid OTP-only or production admin credentials. A dedicated reviewer account was created and its login tested; see reviewer-access.md.
7. **Console owner tasks:** developer identity/contact/device verification, app setup, countries, pricing, content rating/IARC, target age/audience, ads, app access, AD_ID, any financial features/government affiliation questions, policy URLs and final declarations. The traffic-fines links open official/external sites; the app is not a government service.
8. **Testing and rollout:** upload to Internal testing first; inspect App Bundle Explorer and pre-launch reports, test current Android/16KB device behavior and signed Play delivery. Affected personal accounts created after 13 November 2023 need at least12 continuously opted-in testers for14 days before applying for production access. Complete that process if applicable, then prepare a staged production rollout.

## Official references checked

- API36 requirement: https://support.google.com/googleplay/android-developer/answer/11926878
- App signing: https://developer.android.com/studio/publish/app-signing
- 16KB support: https://developer.android.com/guide/practices/page-sizes
- UGC: https://support.google.com/googleplay/android-developer/answer/9876937
- Payments: https://support.google.com/googleplay/android-developer/answer/9858738
- Account deletion: https://support.google.com/googleplay/android-developer/answer/13327111
- Preview assets: https://support.google.com/googleplay/android-developer/answer/9866151
- Testing requirement: https://support.google.com/googleplay/android-developer/answer/14151465

This is a preparation package with explicit release blockers, not confirmation of Play acceptance or production readiness.
