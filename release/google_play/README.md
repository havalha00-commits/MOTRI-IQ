# MOTRI IQ — Google Play preparation package

The signed technical candidate is built and tested, but production submission remains blocked by the items in [play-console-checklist.md](play-console-checklist.md). The version-code-5 bundle was uploaded to Production on 25 October 2026; no review submission or production rollout was performed.

Start with the checklist, then the signed bundle at `artifacts/motri-iq-1.0.1-5-play.aab`. The APK is for release-mode testing, not the Play upload. `artifacts/release-verification.json` records checksums, source hashes, signing identity and validation evidence. Keep the private upload keystore and its passwords backed up separately; this package contains only its public certificate.

The public deletion request portal is https://motri-iq-account-deletion.me-0eca.chatgpt.site/ and the protected dashboard is `/admin`. Sign in with the configured support account. Request management is live; actual backend account/data deletion and email notifications are not automated.

Current version-code-5 checks: analysis clean; 32 focused Play/locale/home tests passed; signed APK/AAB signatures and 16KB library/ZIP alignment passed; no Google Mobile Ads or UMP classes in either artifact; no advertising-ID permissions in the packaged manifest. Runtime and refreshed screenshot evidence is recorded in artifacts/release-verification.json. Older full-suite evidence is historical validation of version code 4.

Version code 5 has no AdMob SDK or banners. Paid business-ad feeds are suppressed in the Play build. Select Contains ads = No for this new upload. Paid Android business-placement/top-up entry points are blocked by `PLAY_STORE_BUILD=true`, and bundle builds require that flag. Website/iOS paid feature behavior is unaffected. Store descriptions, graphics and 24 authentic phone screenshots (eight full pages each in Arabic, English and Kurdish) are prepared. The full app privacy policy is published; Data safety remains an operator review worksheet.

## Published app privacy policy

https://motri-iq.me-0eca.chatgpt.site/privacy/

Operator: MOTRI IQ. English and Arabic app-wide policy; includes provider, advertising, permission, retention and manual deletion-request disclosures. Publication does not confirm Play readiness: actual deletion execution, record-specific retention and processing periods remain operator/backend work.
