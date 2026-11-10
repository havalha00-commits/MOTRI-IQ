# MOTRI IQ

## Google Play preparation — 2026-10-24

Current signed Play candidate, store text/graphics/screenshots and policy worksheets are in [release/google_play](release/google_play/play-console-checklist.md). **1550 tests passed (8 scoped skips), Play-specific checks16 passed, analysis clean.** A release-only WorkDatabase startup crash was reproduced and fixed with targeted R8 rules; the rebuilt signed app passed Android15 cold-start review. API36, signing, permissions and native16KB alignment checks passed. This is a technical candidate, **not yet ready for production submission**: UGC user blocking/terms acceptance, real backend account/data deletion and retention, final mobile privacy policy/Data safety and deployed/Console checks remain open.

The [public deletion-request website](https://motri-iq-account-deletion.me-0eca.chatgpt.site/) and protected `/admin` request queue are deployed. Settings links to the portal. It receives/manages requests; it does not itself delete Supabase users or send email notifications. Operations are documented in `sites/motri-account-deletion/OPERATIONS.md`.

Play AAB builds now require `--dart-define=PLAY_STORE_BUILD=true`, which disables paid business-placement/top-up entry points before loading payment state. Keep that flag for Play builds. Other platform behavior is preserved. The new-app status and support email were confirmed by the publisher; no bundle has been uploaded to Play Console.


## Current verification — 2026-10-23

The final current Device Hub desktop-window review passed on retry on iPhone 17 Pro (iOS 26.5). The UI polish objective is complete within the [recorded scope and production limits](tool/ui_current_handoff.md); Android/iOS native app checks passed.

The UI audit remains active. All 38 active screens and applicable page states have direct assertion references. The latest full run passed 1546 tests with 6 native-only decoded-gallery skips; analysis is clean. Current evidence and exact native/capture scope live in [the completion audit](tool/ui_completion_audit.json) and [screen-state matrix](tool/ui_screen_state_matrix.json).

Normal debug builds have been verified on Android API31 and iOS26.5. The existing Android release bundle and unsigned iOS device output are dated 2026-10-21 and predate the current UI source; they are historical artifacts and require a current-source rebuild/validation before distribution. Earlier progress sections below are historical snapshots, not current release-readiness claims.

Production remains unverified for deployed auth/RLS/Storage/RPCs, wallet hardening rollout, real notification/email/SMS delivery and external-app handoffs. Apple distribution signing/provisioning, store build-number history, any required Play upload-key reset, policy URLs and store declarations remain release-owner steps. No remote migration, store submission or live publication was performed.

Flutter marketplace for cars, market listings, jobs, seller contact, and account management. Arabic, Sorani Kurdish, and English are supported. Android and iOS are the verified mobile targets.

## Run locally

Verified with Flutter 3.47.7 / Dart 3.13.5, Java 21, and Xcode 27.1.

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
```

The existing `icon_api31` emulator was launched successfully as `emulator-5554`. The other running emulator (`emulator-5558`) has insufficient storage for this app. Device IDs can change between sessions.

```sh
flutter emulators --launch icon_api31
flutter run -d emulator-5554
```

For the iPhone simulator, select its ID from `flutter devices`. Never select a physical phone unintentionally.

## Verify

```sh
flutter analyze
flutter test
flutter test test/locale_wiring_test.dart
```

Flutter 3.47.7 tooling crashes on this machine when analyzing the current path containing Arabic text and when parsing native assets under a path containing parentheses. The repository supplies an isolated ASCII-path workaround:

```sh
./tool/verify.sh
```

It copies source and tests to a fresh directory under `/tmp`, runs analysis and all tests, and prints the validation directory. It does not move or delete project files. CI runs checks and an Android debug build from a normal checkout.

## Backend configuration

Copy the example file to `config/production.json` and fill in the backend's public HTTPS URL and Supabase client settings. Do not put database credentials, service-role keys, or other server secrets in this client-side file.

```sh
cp config/production.example.json config/production.json
# Set BACKEND_URL to the real, public HTTPS backend URL. Do not use localhost or 10.0.2.2.
# Replace the Supabase example values with the project's URL and publishable key.
flutter run --dart-define-from-file=config/production.json -d <device-id>
flutter build appbundle --release --dart-define=PLAY_STORE_BUILD=true --dart-define-from-file=config/production.json
```

The Play release build fails closed if `BACKEND_URL` is missing, not HTTPS, or points to a local/example host. The repository does not specify a production backend URL; obtain it from the service owner before building. Client configuration is compiled into the app. Use only a Supabase publishable/anon key here; never a service-role key. Backend authorization must be enforced by the backend.

## Android release

```sh
flutter build appbundle --release --dart-define=PLAY_STORE_BUILD=true
```

Output: `build/app/outputs/bundle/release/app-release.aab`.

A signed ARM64 APK for direct device installation can also be built with:

```sh
flutter build apk --release --target-platform android-arm64
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

A new upload key was created at your request on 2026-10-21:

- Private keystore: `android/.local-signing/motriiq-upload-20261021.jks`
- Alias and generated passwords: `android/key.properties`
- Public certificate for Play Console: `android/.local-signing/upload_certificate.pem`
- Previous local signing configuration: `android/.local-signing/previous-key.properties`

These files are ignored by Git. Back up the keystore and passwords securely before publishing. If the app is already published, complete any required upload-key reset in Play Console before submitting this bundle. The new key does not automatically replace the store's registered upload key.

On another machine, copy `android/key.properties.example` to `android/key.properties` and supply the upload key. Debug builds work without signing material; release tasks refuse to proceed without it. Keep the existing application ID `com.motriiq.app`. Set a build number higher than the last uploaded build before store submission; this audit retains `1.0.1+4` because store history is unknown.

## iOS release

The bundle ID is `com.motriiq.app`. Simulator and unsigned device release builds were verified:

```sh
flutter build ios --simulator
flutter build ios --release --no-codesign
```

To distribute, configure your Apple Developer team, registered App ID, provisioning profile and distribution certificate in Xcode, then build/export a signed archive (`flutter build ipa`). An unsigned `Runner.app` cannot be submitted to App Store Connect.

## Ads

Android debug/profile builds use Google's test banner ID. Release builds retain the existing Android production ID. Banner loading requests UMP consent first, checks `canRequestAds`, and initializes after the app has started. Ad privacy choices are accessible from Settings.

Configure the appropriate privacy message in the AdMob console and verify consent-required, declined, and returning-user scenarios before monetization. iOS monetization remains disabled until a real iOS AdMob app ID and iOS banner ID are configured together; Info.plist contains Google's sample app ID so the linked SDK can start safely in the simulator. Do not reuse Android IDs on iOS. See [Google's Flutter setup](https://developers.google.com/admob/flutter/quick-start) and [consent guidance](https://developers.google.com/admob/flutter/privacy).

## Required backend release step

Review and apply `supabase/migrations/20261021_wallet_insert_hardening.sql` to the intended database after a backup. It has **not** been applied remotely by this audit.

It closes two issues in the supplied migrations:

1. A user could insert a confirmed wallet top-up by supplying a matching confirmation timestamp. New requests must have pending status and no administrative fields.
2. Wallet receipt storage was public. The bucket becomes private, with owner/admin read access. The updated client stores object paths and creates 60-second signed links for admin review; legacy public receipt URLs are parsed into object paths.

Coordinate rollout with existing clients: old receipt links stop opening publicly once the bucket is private. Owners and admins must be authenticated. Confirm that no other broad storage policy grants access to this bucket.

Before publishing, validate in staging with distinct normal-user/admin accounts: pending top-up succeeds, forged confirmation fails, other users cannot read receipts, anonymous receipt URLs fail, admin review and approval work, and existing balances remain correct. Never blindly run all historical SQL files: this repository includes destructive cleanup and demo-seeding scripts, and its historical migration filenames are not a clean baseline.

Also verify the deployed `login-with-username` function, signup/email delivery, password recovery, listing creation/edit/deletion, moderation, storage limits and RLS using real staging accounts. This audit did not mutate live accounts, listings, wallet balances or database policies.

Before store submission, review the implemented privacy/terms text for actual operations, supply public store policy URLs and support details, confirm account-deletion handling, and complete store privacy/data declarations. Builds and automated tests alone do not verify those operational requirements.

## UI polish and device review (2026-10-21)

- Fixed disclosure arrows that were mirrored twice in RTL and removed forced RTL from English screens. Multiline row icons now align consistently; forward and back actions follow the locale.
- Made empty home feeds compact, replaced indefinite loading text on failures, and fixed pull-to-refresh so all feeds reload and the indicator waits for completion.
- Exposed language, settings and help to signed-out users. Fixed the white-on-white sell-car action, password toggle labels, and keyboard direction for names and identifiers.
- Persisted local notification preferences. These preferences do not provision a push service or email delivery infrastructure.
- Unified Iraqi OTP number validation/formatting, including Arabic/Persian digits; removed the extra local zero from international numbers.
- Normalized business WhatsApp/call numbers, removed analytics delays before contact actions, and handled unavailable external apps. Added iPad share anchors and bounded location/reverse-geocoding requests.
- Cached immutable translation tables instead of rebuilding them for every label.

Xcode on this machine provides **Device Hub** at `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`. Use it to display the booted iPhone simulator; the old `Simulator.app` location is absent.

When switching from debug/integration testing to a release build, use the normal build commands above with dependency/plugin preparation enabled. On Flutter 3.47.7, using `--no-pub` immediately after a debug test can leave a test-only plugin in generated registration and cause release compilation to fail. Do not hand-edit the generated registrant.

The on-device regression journey is in `integration_test/app_smoke_test.dart`:

```sh
flutter test integration_test/app_smoke_test.dart -d <android-or-ios-device-id>
```

It exercises the six-tab guest shell, a live public car listing, settings/about/support/back navigation, repeated language selection, focused filter apply/cancel/reset, dark mode, and refresh. It does not send SMS, place calls, share messages, upload listings, or modify wallet data. Use an ASCII-only full checkout path without parentheses if Flutter tooling fails under the current path. Signed-in seller/admin flows still require suitable staging accounts.

## Audit result (2026-10-21)

- Fixed missing-photo detail crashes, failed image-preload reporting, unhandled signed-out admin lookups, and admin access refresh after login/logout.
- Restored the missing home Market section and navigation target, updated Flutter radio APIs, and corrected the English wallet currency label.
- Added consent-gated test-safe Android ads, external-link query declarations, iOS SDK initialization metadata, protected signing setup, and CI checks.
- Static analysis: no issues.
- Automated tests: 513 passed, including locale wiring and phone-size layout probes.
- Android: installed and launched on API 31 emulator with live public listings; signed AAB built.
- iOS: installed and launched on iPhone 17 Pro simulator; unsigned release build succeeded.
- Remaining external steps: backend migration/staging checks, secure key backup and possible Play upload-key reset, Apple distribution signing, store metadata/versioning, and iOS ads configuration if desired.

## Locale and filter follow-up (2026-10-21)

Fixed a controller lifetime crash when applying a filter while typing. The filter sheet now owns its controllers until its closing animation finishes. Numeric filters accept Arabic/Persian digits and validate ranges before applying; cancel discards drafts, and reset clears selections. The footer remains accessible above the keyboard, with full-width translated actions.

Business category filters now use stable identifiers and canonical storage values. Switching Arabic/Kurdish/English preserves the selection, and queries include legacy translated category values. Dropdowns tolerate duplicate and previously stored values, and stale category requests cannot overwrite newer results. The language chooser uses a single radio group and applies the locale after returning its selection.

Nine focused regression tests cover these failures and small-screen keyboard layout, alongside the full suite. Device tests exercise the actual language chooser and focused filter apply, cancel, reopen and reset in every language on Android and iOS.

Home empty-state follow-up: optional recommendation sections collapse with their headings and spacing when no items exist. The empty Market feed is hidden on Home, including its heading and arrow. Selecting the Market tab reveals a compact marketplace-specific empty state; returning Home hides it again. Empty highlights no longer reserve extra space, and failed highlight loads no longer retain a loading skeleton. Regression coverage includes an empty backend response and Market navigation on a short home page.

## Visual polish (2026-10-21)

Navigation and common actions now use [Material Symbols Rounded](https://pub.dev/packages/material_symbols_icons), centralized in `lib/design/app_icons.dart`. Selected destinations use filled versions of the same symbol, with a subtle pill and dark-mode contrast; Add uses a compact burgundy tile. Flutter's directional back/disclosure icons remain in place for RTL mirroring. Shared buttons have comfortable minimum heights, field focus/error colors are consistent, and account rows use aligned icon backgrounds. Profile-row ink feedback now paints on its own Material surface. The font is bundled locally; release builds tree-shake unused symbols.

## Whole-app UI polish goal: discovery pass

The active screen/state tracker is `tool/ui_polish_plan.json`. Home discovery now uses a bounded five-dot carousel position display with a numeric count for long feeds, a larger photo area and reduced-motion-aware autoplay. Compact car cards separate model, year/mileage and location; matching city/province values are shown once, empty reputation space is removed, and the sold badge has readable foreground contrast. Mileage units and discount labels are localized.

`test/discovery_polish_test.dart` covers narrow cards with long model names, discounts, large text, Arabic/Kurdish/English and both themes, plus long-carousel semantics and reduced motion. `integration_test/discovery_layout_test.dart` uses a controlled UTF-8 fixture backend to verify populated native layouts independently of service availability. It does not verify production backend behavior. Live API verification remains open while the public service hostname fails DNS resolution from this environment.

Discovery pass verification: 417 unit/widget tests passed and analysis was clean. Controlled native discovery-layout tests passed on Android and iOS in all three locales and both themes. Live service journeys remain unverified during the DNS failure; these fixture results do not replace backend/staging checks.

## Whole-app UI polish goal: shared states and typography

Added shared empty/error/loading views with consistent typography, icon backgrounds, borders and spacing. Full-screen panels scroll on short displays and with large text. Ten seller, message, notification and admin list pages now have localized read-only retry states; followed-seller and wallet-review reads no longer turn failed requests into misleading empty results. Favorites, section browsing, business listings, search and history also use the shared state presentation. Section headers constrain long brand names. Corrected copied page titles in alerts, seller profiles and report review; the report-review header keeps secondary destinations in a menu.

Verification: 430 unit/widget tests passed, including locale wiring; analysis was clean. `integration_test/screen_states_test.dart` runs 13 state/recovery scenarios on Android and iOS with isolated HTTP/auth fixtures. A mock sign-in is local to the fixture client and no production operations are sent. These checks cover error-to-empty recovery and the shared short-screen large-text panel, not all populated seller/admin workflows. Use `--dart-define=UI_REVIEW_HOLD=true` to pause at the report-error visual checkpoint. Native review artifacts are in `tool/ui_review_artifacts/`.

The existing local font selection remains in place. An optional bundled Arabic font evaluation was deferred because the official font download also failed DNS resolution; no incomplete asset or runtime font download was introduced. Full per-screen state/visual review, form/detail polish and real staging/live checks remain tracked in `tool/ui_polish_plan.json`.

## Whole-app UI polish goal: seller and listing forms

Add-car, showroom and business-ad forms now use section headings, responsive field pairs, locale-aware text direction, suitable keyboard actions and content-sized controls. Car validation accepts Arabic/Persian digits, checks year and price before uploads, and shares parsing with price guidance. Signed-out showroom access shows a login state instead of an endless spinner. Business package selection uses one radio group, localized duration/placement labels and a recoverable load-error panel that retains the draft. The image picker respects the five-photo limit, and all five images have accessible remove actions. Dark-theme field focus, text actions and selection have clearer contrast.

Verification: **455 unit/widget tests passed**, including locale wiring; static analysis found no issues. `integration_test/form_layout_test.dart` runs **25 checks on each of Android and iOS**, using isolated HTTP/auth fixtures. The matrix includes Arabic/Kurdish/English, both themes, large text, validation, signed-out access and package-load retry. Native dark-form screenshots were inspected and saved in `tool/ui_review_artifacts/vehicle_form_dark_android.png` and `vehicle_form_dark_ios.png`. No production submissions, uploads, payments or account changes were performed. Native media selection, populated edit flows and actual staging permissions still need verification.

Admin business-ad and wallet review callbacks also no longer return futures from `setState`; populated pull-to-refresh now waits for its read to finish. Richer populated-state interaction tests remain on the tracker. Full-app polish is still active; details/gallery, account/authentication, support/payment and remaining populated seller/admin screens are not yet complete.

## Whole-app UI polish goal: details and galleries

Car details and upload previews share a safe-area full-screen viewer with an owned/disposed page controller, a live photo counter and pinch zoom. Native Android testing exposed competing zoom/page gestures; zoom now wraps the pager, which pauses paging while zoomed so panning does not change the photo. Seller contact actions stack for narrow or enlarged-text layouts. Sold status wraps in Arabic/Kurdish, specification values can wrap, and listing-date, comparable-sample and mileage labels are localized. Offer dialogs scroll above the keyboard, normalize localized numbers and wait for their overlay to disappear before releasing text controllers.

Business details give long names the full content width, keep Share available after recording a view, use bounded carousel indicators, and open photos in the same viewer. Empty photo headers collapse entirely; native screenshot review caught an iOS placeholder/toolbar collision that ordinary overflow tests missed. Empty contact slots no longer reserve gaps, and duplicate/blank location values are removed.

Verification: **481 unit/widget tests passed**, including locale wiring; analysis was clean. `integration_test/detail_layout_test.dart` passed **25 checks on Android and 25 on iOS**. After the final screenshot-led no-photo header adjustment, all **six business layout cases on each platform** passed again. Native checks cover active/sold car details, business details, both themes, all three languages and shared gallery swipe/pinch/pan/rebuild/close behavior. Final dark business screenshots at 1.6 text scale were inspected in `tool/ui_review_artifacts/business_details_dark_android.png` and `business_details_dark_ios.png`.

Fixtures intercept database reads and analytics locally; they do not verify production telemetry, external contact apps, uploaded media, seller reputation, market estimates or authenticated staging permissions. The public backend hostname still fails DNS resolution here. Seller profiles/reviews and remaining account/support/payment/admin screen states remain on the active tracker; the entire-app goal is not complete.

## Whole-app UI polish goal: seller profiles, reviews and populated saved cards

Seller profiles now have inset sections, a wrapping name/verification/tier header, readable statistics and localized counts and received-offer labels. Contact actions use the shared Iraqi phone parser; invalid numbers stay hidden, and guests receive sign-in feedback for reviews. Rating inputs live with their dialog route, wrap safely above the keyboard and retain the selected rating/comment after a failed save. Retrying a review invalidates cached seller reputation after success. Pending offer updates disable duplicate actions and retain localized failure feedback. Profile refresh and saved-list loads return explicit failed result states so refresh callbacks present recovery without propagating read failures.

Richer reputation fixtures exposed a regular listing-card overflow. Regular cards now stack photo/metadata on narrow displays or with enlarged text, wrap key facts and put actions in a separate row; wider layouts retain a side-by-side photo. Favorites uses grid cards with adaptive columns/heights, supports refreshing short grids, and no longer presents failed listing reads as an empty saved list.

Gallery checks also caught horizontal pinch competing with paging. A one-finger page recognizer now yields when a second finger lands; zoomed panning keeps the current photo. Previous/next controls and localized reset-zoom actions support explicit navigation as well as swiping.

Verification: **513 unit/widget tests passed** and analysis was clean. `integration_test/seller_profile_layout_test.dart` passed **38 checks on Android and 38 on iOS**, including public/owner profiles in all three languages and both themes, populated Favorites, review/offer failure recovery, guest access, keyboard cancellation, short-grid refresh, horizontal/vertical pinch, panning and explicit gallery navigation. Final 1.6-scale dark profile screenshots were inspected in `tool/ui_review_artifacts/seller_profile_dark_android.png` and `seller_profile_dark_ios.png`. Review and offer writes in this suite are intercepted local fixtures; staging authorization, actual external contact apps, accepted-offer chat navigation and payment behavior remain unverified.

Network-check correction: a request with outside-sandbox network access reached the backend hostname successfully (HTTP 404 at the root endpoint). Earlier sandbox DNS failures are not proof of a service outage. Real guest journeys subsequently passed on Android and iOS with public listings in Arabic/Kurdish/English, including listing navigation, filter apply/cancel/reset, theme switching, settings/support and refresh. These guest checks do not verify authenticated seller/admin/payment workflows. The full-app polish goal remains active in `tool/ui_polish_plan.json`.

## Whole-app UI polish goal: account and authentication

Login/signup now uses grouped fields, wrapping actions, local validation and persistent localized feedback. Form drafts survive language changes, and existing validation messages update to the selected language. Account headers wrap long names and show email for email-only members; quick actions adapt to narrow displays and enlarged text. Account/profile navigation shares consistent icon backgrounds, directional disclosure arrows and separate destructive-action styling. UserProfile handles failed reads with retry, clears stale identity on auth changes and opens the actual Favorites screen. Support FAQ strings are resolved on every locale update.

OTP verification owns its controller and request state, keeps failed attempts editable, normalizes Arabic/Persian digits and scrolls its title/content above the keyboard. Authentication errors use localized SDK error codes rather than exposing backend diagnostics. Duplicate requests are guarded, signup handles both confirmation-required and immediate-session responses, and passwords clear after success/sign-out. Native avatar selection/upload and real authenticated staging permissions remain unverified.

A read-only production auth-settings check found email enabled, phone disabled, signup enabled and email autoconfirm enabled. The app now reads those public capabilities with failure/retry feedback and displays SMS controls only when phone auth is enabled. Enabling phone login requires server/provider configuration; no settings were changed, SMS sent or production accounts created. Enabled-phone, disabled-phone and retry behavior are covered using isolated fixtures.

Current automated verification: **561 tests passed**, including locale wiring; static analysis found no issues. Final native account checks passed **48 cases on Android and 48 on iOS**. Login, signed-in, OTP and unavailable-phone screenshots were inspected; visual artifacts are recorded in `tool/ui_polish_plan.json`. The whole-app goal remains active; populated chat/offer/admin workflows, remaining support/legal/payment states, native media selection and staging authorization still require review. Earlier release artifacts predate this account pass and must be rebuilt after the remaining polish work.

The final account pass also passed real-service guest journeys on Android and iOS in all three languages. Normal debug builds were then restored and launched on the Android emulator and iOS Device Hub. These checks verify public navigation/listings/filter/settings behavior, not production authenticated permissions.

## Whole-app UI polish goal: offer chat

Offer chat now uses burgundy theme surfaces with matching foregrounds and selectable message text. The composer accounts for keyboard insets, Send has a localized tooltip, and refresh/polling retain existing messages while loading. The query fetches the newest 200 messages and opens at the newest message; older history beyond this limit still needs pagination. Failed sends retain their draft with localized feedback; successful sends preserve a newer draft typed during the request. Closing a pending chat no longer risks touching its disposed controller. Load failure has a localized retry action.

Verification: **573 unit/widget tests passed**, including locale wiring. The chat suite passed **12 checks on Android and 12 on iOS**, covering all three languages, light/dark, enlarged text, error recovery, keyboard position, pending requests, draft preservation and polling. Both populated dark screenshots were inspected in `tool/ui_review_artifacts/offer_chat_dark_android.png` and `offer_chat_dark_ios.png`. All messages in these tests were intercepted by local fixtures; no real-user messages were sent. Authenticated staging permissions, notification/accepted-offer navigation, long-history pagination and other populated offer/activity/admin screens remain on the active goal.

Final chat-pass static analysis found no issues. Normal Android and iOS simulator builds succeeded and were installed/launched after the native checks.

## Whole-app UI polish goal: sent offers and activity notifications

Sent offers now localize amounts and all visible statuses, use theme-based burgundy emphasis and wrapping titles, and retain the accepted-offer chat action. Activity rows use matching icon backgrounds, wrapping content, explicit unread text, directional disclosure arrows and per-item opening feedback. Duplicate opens are guarded. Failed opens preserve the unread state and show localized feedback; missing conversations no longer silently do nothing. Both lists support refreshing short content, await the read and return explicit failure results. Native checks caught and verified the fix for an unhandled failed-refresh future.

Verification: **590 unit/widget tests passed**, including locale wiring; analysis found no issues. `integration_test/activity_layout_test.dart` passed **17 scenarios on Android and 17 on iOS**, including all three languages/themes with enlarged text, accepted-offer and notification chat navigation, duplicate-open prevention, mark-read failure/retry, unavailable conversation feedback and refresh failure/recovery. Four populated dark screenshots were inspected in `tool/ui_review_artifacts/activity_dark_{android,ios}.png` and `sent_offers_dark_{android,ios}.png`. Read-state patches and all other requests are intercepted local fixtures; no real-user messages or production activity changes were made. Real staging authorization, new-offer-to-profile navigation, pagination and remaining admin/support/payment screens still require review.

Normal Android and iOS simulator builds succeeded after the activity pass, and both were installed and launched after the integration tests.

## Whole-app UI polish goal: admin ad management

The admin ad manager now distinguishes a failed permission check from a confirmed non-admin session, with retry for failures. Each cars/market/jobs section reports its own load failure instead of presenting it as an empty list. Long listing titles wrap, headings and row metadata use the shared typography, and short lists support refresh. Delete actions are guarded before confirmation, show per-row progress, disable duplicate requests and preserve the row after failure. The confirmation dialog scrolls on short or enlarged-text layouts. Closing a pending operation safely ignores its eventual UI update.

Automated verification: **602 tests passed**, including locale wiring; static analysis found no issues. Admin checks intercept all service calls, including the delete RPC, in a local fixture client. They do not delete production ads or prove actual server admin authorization. Native results/screenshots and remaining state coverage are tracked in `tool/ui_polish_plan.json`; larger result pagination, actual backend deployment and remaining seller/admin/support/payment screen review are still open.

Admin-manager native verification: **12 checks passed on Android and 12 on iOS**. Both populated dark screenshots at enlarged text were inspected: `tool/ui_review_artifacts/admin_ads_manager_dark_android.png` and `admin_ads_manager_dark_ios.png`.

Normal Android and iOS simulator builds succeeded after the admin-manager pass and were installed/launched after native checks. The full-app polish goal remains active.

## Whole-app UI polish goal: personal reviews and conversations

Personal review cards now wrap long seller names, place ratings on a separate line and support refreshing short content. Missing showroom names resolve their localized fallback during rendering, so language changes no longer preserve a cached fallback from the previous locale. Conversation rows use matching icon surfaces, directional arrows, a bounded message preview and a separate localized offer amount; returning from chat refreshes the preview. Both pages return explicit read failures and await refresh completion.

The old conversation query selected a globally limited set of messages, allowing a busy conversation to crowd out previews for other offers. The replacement uses the existing offer/message foreign key to request one newest embedded message per offer. Local tests assert the per-relation ordering/limit and exercise multiple conversations; actual authenticated server responses and RLS still require staging verification.

Automated verification: **620 tests passed**, including locale wiring; analysis found no issues. Native checks and artifacts are tracked in `tool/ui_polish_plan.json`. Four enlarged-text populated screenshots were inspected in `tool/ui_review_artifacts/my_reviews_dark_{android,ios}.png` and `my_messages_dark_{android,ios}.png`. All service calls are local fixtures; no real-user messages, reviews or account changes were made. Long-result pagination and remaining screen/state coverage are still on the active whole-app goal.

Seller activity native verification: **18 checks passed on Android and 18 on iOS**, covering populated layouts, query contract, chat navigation/return, refresh failure/retry, missing-name locale updates and first-message guidance.

Normal Android and iOS simulator builds succeeded and were installed/launched after seller activity native checks. The whole-app polish goal remains active.

## Whole-app UI polish goal: support, about and legal reading

Support/About links now use consistent icon backgrounds and directional arrows. Support has a clearer opening heading and readable dark-theme help icons. Its contact sheet scrolls and uses adaptive, wrapping actions. Problem reporting uses one radio group with stable category identifiers, includes the selected issue type in shared text, fixes literal newline escapes, guards duplicate report actions and shows localized share-failure feedback. The contact test now scrolls to its actual target rather than relying on a fixed drag distance.

Privacy and terms share a selectable reading layout with bounded width, consistent section cards and typography, and a localized update label/date. All ten privacy sections and eleven terms sections retain their existing text. Tests also scroll to the update footer. This is a presentation pass; policy substance was not rewritten.

Verification evidence and the final native rerun are recorded in `tool/ui_polish_plan.json`. Eight enlarged-text dark screenshots were inspected in `tool/ui_review_artifacts/{support,about,privacy,terms}_polish_dark_{android,ios}.png`. Sharing is intercepted by the test platform channel; no reports were sent to another person. Actual external phone/WhatsApp apps and share-sheet completion remain unverified. The whole-app goal remains active, including the remaining wallet/payment, settings and populated admin/seller states.

Final support/legal verification: **652 tests passed**, analysis was clean, and **32 native scenarios passed on Android and 32 on iOS** after the final contrast/heading changes. Static privacy/terms reading-screen UI coverage is complete in the tracker; remaining whole-app screen/state work is still active.

Normal Android and iOS simulator builds succeeded and were installed/launched after support/legal checks.

## Whole-app UI polish goal: wallet top-up and manual payment

Wallet top-up now scrolls at narrow widths and enlarged text sizes, with content-sized semantic amount choices and explicit IQD labels. Payment headings wrap; loading, failed settings reads and a missing configured account are distinct, with retry for failed reads. Guests see a sign-in state before payment instructions. Receipt selection catches failures and safely handles route disposal, while picker and submission guards prevent duplicate actions. Cached preview bytes avoid repeated receipt reads during selection. A failed insert retains the selected amount/receipt; failed uploads do not create transactions. Backend failures show localized feedback rather than raw diagnostics.

Manual payment now uses selectable wrapping summary fields, a scrollable layout, localized instructions and a link to the existing support center. Removed the placeholder phone number and unverified 24-hour activation promise. USD and IQD values appear on separate explicitly directed lines, avoiding a mixed-script display issue found in native screenshot review. The final action says “Back to listings” and does not claim to confirm a payment.

Automated verification: **672 tests passed**, including locale wiring; static analysis was clean. Final native runs and screenshot evidence are tracked in `tool/ui_polish_plan.json`. Storage uploads and transaction inserts are intercepted local fixtures, and the picker supplies an in-memory image. Screenshot account details are fixture values. No production receipts, balances, transactions or payment settings were changed. Actual native media selection, real storage/RLS permissions, admin confirmation/ledger accounting and payment settlement require staging checks; the prepared wallet-hardening migration remains unapplied. The whole-app goal remains active.

Final wallet/payment verification: **20 native checks passed on Android and 20 on iOS** after the explicit-currency display fix. Four final enlarged-text dark screenshots were inspected in `tool/ui_review_artifacts/wallet_topup_dark_{android,ios}.png` and `manual_payment_dark_{android,ios}.png`. Full suite: **672 passed**; final static analysis: no issues. These results cover local fixtures, not real payment settlement.

Normal Android and iOS simulator builds succeeded and were installed/launched after the final wallet/payment checks. Shared currency formatting on other surfaces remains queued for audit; whole-app polish is still active.

## Whole-app UI polish goal: shared currency display

Shared full/compact price formatting and wallet balances now use explicit USD/IQD codes inside an isolated left-to-right numeric run, preserving order within translated right-to-left prose. Existing conversion values and whole-number rounding are unchanged. Display parsing accepts Arabic/Persian digits and separators; non-numeric price labels retain their original text without acquiring an invented currency, and non-finite values use the localized unknown-price label. The market estimate card no longer repeats the IQD label or a second USD amount.

Verification: **684 tests passed**, including locale wiring; analysis found no issues. The currency suite passed **12 checks on each native platform**, covering conversion values, localized digits, fallback labels, measured text order and shared price surfaces in all three languages/themes at enlarged text size. Both dark review samples were inspected in `tool/ui_review_artifacts/shared_currency_dark_android.png` and `shared_currency_dark_ios.png` after rerunning the visual checkpoint. The review harness includes an actual listing card plus package/wallet price samples; it does not prove every populated financial/admin screen or server accounting behavior. No live financial operations were performed.

The final currency pass also passed real-service guest journeys on Android and iOS in all three languages. Normal debug builds were preserved, reinstalled and launched after those tests. These checks cover public behavior; authenticated financial/admin permissions remain unverified. The whole-app goal is still active.

## Whole-app UI polish goal: wallet administration

Wallet administration now distinguishes a confirmed non-admin session from a failed access check and uses explicit read results for retry/refresh. Pending requests load independently of optional profile names; failed/missing name lookups keep the request visible with its account identifier. The prior embedded inner profile query relied on a relationship not declared by the wallet migration. Requester names, account IDs, amounts and actions wrap, and receipt access is a labelled, guarded button.

Approval/rejection now opens a scrollable confirmation containing the requester and amount. Duplicate actions are guarded before confirmation and throughout the request. Success requires both `ok: true` and the expected returned status; false, malformed or mismatched responses no longer claim success. Already-reviewed requests refresh with a separate notice. Failed decisions retain their rows with localized feedback, and receipt signing/open failures restore controls without exposing server diagnostics. Removed the unused, unmounted wallet balance card and its zero-on-error helper after confirming there were no live call sites; no replacement balance feature was introduced.

Automated verification: **701 tests passed**, including locale wiring; static analysis found no issues. Native verification and visual artifacts are recorded in `tool/ui_polish_plan.json`. All admin decisions and receipt-signing calls in these tests are intercepted local fixtures; no production wallet request or balance was changed. Actual admin/RLS permissions, receipt access, concurrent server decisions and accounting require staging checks. No backend migration was applied, and the whole-app polish goal remains active.

Wallet-review native verification: **17 scenarios passed on Android and 17 on iOS**. After screenshot-led fallback/KCard label refinements, the focused final visual case passed again on each platform. Both final enlarged-text dark screenshots were inspected in `tool/ui_review_artifacts/wallet_admin_dark_android.png` and `wallet_admin_dark_ios.png`. Full suite remains **701 passed**, with clean analysis.

Normal Android and iOS simulator builds succeeded and were installed/launched after final wallet-review checks. The full-app polish goal remains active.


## Whole-app UI polish goal: settings, search history and fines

Settings now uses wrapping switch rows and consistent icon wells, reports preference load/save failures, and offers a retry. Notification choices are local preferences; the screen explains that these do not change delivery or operating-system settings. No notification-provider integration was added.

Saved searches now return their exact query to the mounted Search tab before searching. History preserves newest-first storage order and removes duplicate/empty entries. Failed reads show retry; failed clearing retains the saved entries with localized feedback. Traffic fines cards scroll on small screens, use theme-aware contrast and include corrected Kurdish subtitles. Configured portal URLs remain unchanged.

Verification: **726 tests passed**, including locale wiring, and static analysis found no issues. The settings/history/fines suite passed **25 native cases on Android and 25 on iOS**; the final fines-copy checks passed **7 cases on each platform**. All six enlarged-text dark screenshots were inspected in `tool/ui_review_artifacts/{settings,history,fines}_dark_{android,ios}.png`. Tests intercept authentication, preference failures and external link launching; they do not verify notification delivery or external fines-browser handoff. The full-app polish goal remains active, with per-screen evidence in `tool/ui_polish_plan.json`.

Normal Android and iOS simulator debug builds succeeded. Real-service guest journeys passed on both platforms in Arabic, Kurdish and English, and the preserved normal apps were reinstalled and launched after testing. No authenticated production data was changed.


## Whole-app UI polish goal: Following

Following now uses theme-aware seller cards with wrapping names, localized follow dates and directional disclosure arrows. Names load in one optional batch; missing or denied profile data retains every followed seller with a translated fallback. Tapping a valid seller opens the existing profile, guards duplicate navigation and refreshes on return. Failed follow reads show retry; both populated and empty lists support pull-to-refresh. Invalid dates are omitted rather than displaying raw timestamps.

Verification: **735 tests passed**, including locale wiring; analysis found no issues. Focused tests cover all three locales and both themes at enlarged text size, profile lookup failure, seller navigation, read retry and refreshing the empty state. Both dark native screenshots were inspected in `tool/ui_review_artifacts/follows_dark_android.png` and `follows_dark_ios.png`. All authenticated reads are intercepted fixtures; real profile visibility and follow permissions still need staging checks. No production follow records changed. Native results and normal-build evidence are tracked in `tool/ui_polish_plan.json`; the whole-app goal remains active.

Following native verification: **9 cases passed on Android and 9 on iOS**. The first Android visual-hold run lost its Activity after the valid screenshot and was interrupted after confirming launcher state; the complete functional suite then passed without the hold.

Normal Android and iOS simulator builds succeeded and were installed/launched after the Following native checks.


## Whole-app UI polish goal: vehicle alerts

Vehicle alerts now use the shared activity cards with wrapping location text, shared currency display, explicit unread labels, busy feedback and RTL/LTR disclosure arrows. Both empty and populated states refresh; read failures offer retry. Listing opening uses the existing public listing view and guards duplicate taps. A listing-fetch failure retains unread status. Read-status changes are scoped to the alert and signed-in user, and require a returned row; denied/no-op updates do not block a valid listing from opening and show localized feedback on return. Unavailable listings and failures use translated messages without server diagnostics.

The focused suite covers layout in all three locales/themes with enlarged text, failed loading/retry, empty refresh, unavailable listings, scoped read updates, listing-fetch failure, failed/no-op read updates with successful listing navigation, duplicate taps and disposal during a pending update. All authenticated operations use intercepted fixtures; no production alert was marked read. Actual alert/RLS permissions and listing visibility still require staging verification. Per-screen evidence and final checks are recorded in `tool/ui_polish_plan.json`. The full-app polish goal remains active.

Alerts verification: **747 full-suite tests passed**, including locale wiring; static analysis found no issues. **12 native cases passed on Android and 12 on iOS**. Both enlarged-text dark screenshots were inspected in `tool/ui_review_artifacts/alerts_dark_android.png` and `alerts_dark_ios.png`.

Normal Android and iOS simulator builds succeeded and were installed/launched after the Alerts native checks.


## Whole-app UI polish goal: business-ad moderation

Business moderation now uses a full-width status filter and wrapping theme-aware cards/actions. Status and payment labels resolve at render time, fixing labels remaining in the first language used. Access failure is distinct from a confirmed non-admin session. Filter loads capture the selected value before awaiting access checks. Empty results refresh, and failed reads offer retry.

Status/payment changes require a scrollable confirmation, guard duplicate decisions from before the dialog opens, and require a matching returned row before showing success. Updates match the original status/payment state so a stale decision cannot overwrite a changed state silently. Failed/no-op decisions preserve the row with translated feedback and no server diagnostics. Approval preserves the existing payment-confirmation behavior, now stated explicitly before confirmation. It calculates start/expiry from one UTC instant and a positive package duration; unavailable referenced packages prevent the update. Ads without a package receive a 30-day fallback period. Activation and pause controls no longer offer redundant current-state actions.

Verification: **765 full-suite tests passed**, including locale wiring; static analysis found no issues. Focused coverage includes three languages/both themes at enlarged text size, live language changes, access/read retries, all-status filtering, cancellation, successful approval/rejection/payment/activation/pause, failed/no-op updates, package failure, duplicate guards and disposal. Both native dark screenshots were inspected in `tool/ui_review_artifacts/business_admin_dark_android.png` and `business_admin_dark_ios.png`. All moderation and payment operations are intercepted local fixtures; no production ad or payment status changed. Real admin/RLS access and concurrent server behavior require staging checks. Final native/build evidence is tracked in `tool/ui_polish_plan.json`; the whole-app goal remains active.

Business moderation native verification: **18 cases passed on Android and 18 on iOS**, including successful decisions, access/read failures, failed/no-op updates and all three locale/theme layouts.

Normal Android and iOS simulator builds succeeded and were installed/launched after the business-moderation native checks.


## Whole-app UI polish goal: reports dashboard

Reports now use wrapping theme-aware cards with selectable listing IDs/reasons, translated labels/status/actions and localized dates with clock time. Access failure is distinct from confirmed non-admin access. Failed reads offer retry, and both populated and empty lists refresh with an awaited result. Reported listing access retains the admin table so moderation can inspect listings that are not public. Unavailable listings and other failures use translated feedback without server diagnostics.

Resolving/reopening requires a scrollable confirmation and guards duplicate actions from before the dialog opens. Updates match the original report status and require the expected returned ID/status before success. Reopening clears prior review fields. Seller verification identifies the seller account in its confirmation, guards the same seller across report rows, requires a returned verification, and treats duplicate verification separately from failure. Pending operations are safe when the page is disposed.

All moderation operations are intercepted local fixtures; no production report or seller badge was changed. Actual admin/RLS permissions and concurrent server behavior still need staging verification. Native cases cover three locales/both themes at enlarged text size, access/read retry, empty refresh, resolve/reopen, failed/no-op updates, verification cancellation/success/duplicate/failure/no-op, listing success/missing/failure, duplicate guards and disposal. Final results and screenshot evidence are recorded in `tool/ui_polish_plan.json`; the whole-app goal remains active.

Reports verification: **786 full-suite tests passed**, including locale wiring, and analysis found no issues. **21 native scenarios passed on Android and 21 on iOS**. After preserving local clock time, the final six locale/theme layout cases passed again on each platform. Both final enlarged-text dark screenshots were inspected in `tool/ui_review_artifacts/reports_dark_android.png` and `reports_dark_ios.png`.

Normal Android and iOS simulator builds succeeded and were installed/launched after the reports-dashboard native checks.


## Whole-app UI polish goal: car requests

Car requests now uses wrapping request and nested-offer cards with shared USD/IQD prices, translated year labels and isolated year ranges for RTL. Open/mine choices wrap below the toolbar; publishing remains a full-width action below the list. Failed reads offer retry without diagnostics, and empty/populated lists refresh with an awaited result. Guest publishing/offering shows login guidance.

Request and offer forms now own their controllers through the route lifecycle, preserve drafts on failure and live locale changes, use locale direction for text, and normalize Arabic/Persian numbers. Prices must be finite and positive. Optional years must be integers within the existing database range 1950–2100 and ordered correctly. Pending submissions disable controls and block dismissal; successful writes require a nonempty returned ID. Duplicate offers use localized feedback.

Closing a request or accepting/rejecting an offer requires confirmation. Updates are scoped to the owner, record/request and original status; success requires the expected returned ID/status. Duplicate decisions are guarded and failed/no-op decisions retain the record with translated feedback. Client guards do not establish server atomicity between simultaneous request closure and offer decisions: actual nested-offer visibility, RLS and concurrent behavior require staging verification.

Verification: **819 full-suite tests passed**, including locale wiring; analysis found no issues. Coverage includes all locales/themes with enlarged text, both forms, localized digits, non-finite prices, invalid/reversed years, live locale/draft preservation, failed/no-op write retry, duplicate offers, pending submit/disposal, confirmation cancellation, acknowledged owner decisions, read retry/mine filtering and guest guidance. All backend operations use intercepted local fixtures; no production request or offer was created or changed. Final native/build evidence is tracked in `tool/ui_polish_plan.json`; the full-app polish goal remains active.

Car requests native verification: **33 scenarios passed on Android and 33 on iOS**. Screenshot-led refinement moved labels above inputs to prevent truncation at enlarged text size. Final form layouts passed **12 cases on Android** and **12 on iOS**, with an additional duplicate-offer check on iOS. All six final card/form screenshots were inspected in `tool/ui_review_artifacts/requests_{cards,request,offer}_dark_{android,ios}.png`. Returning from an offer dialog also refreshes the list so a concurrently existing duplicate offer disables the action. Full suite remains **819 passed**, with clean analysis.

The final stronger duplicate-offer refresh assertion passed separately on both Android and iOS after the form review.

Normal Android and iOS simulator builds succeeded and were installed/launched after the final car-requests checks.


## Whole-app UI polish goal: vehicle comparison

Comparison now uses responsive spec cards instead of compressing the label and two cars into narrow columns. Values stack on phone/enlarged-text layouts and sit side by side on wider normal-text layouts. Car names wrap fully and remain attached to each value. Prices use the shared USD/IQD formatter; mileage includes units and supports the legacy field; absent values use translated labels. Selected cars have individual removal and view-listing actions, and the single-car state explains how to finish the comparison. Clear-all remains available. Empty/whitespace IDs are ignored and the existing two-car limit is preserved.

Comparison uses the existing local selection snapshot, so there is no new network loading/error state. Image fixtures contain empty image arrays; real loaded media and refreshed listing availability remain part of the shared-media/live-detail review. Listing-detail requests in this pass are intercepted. The wide 1024px layout is checked in the host widget suite; phone native runs skip that synthetic viewport.

Focused checks passed **37 tests including locale wiring**, covering three locales/both themes, empty/one/two selections, enlarged text, explicit missing data, currency and legacy mileage, single/all removal, wide alignment, live locale changes, selection limits and opening the correct listing while retaining selection on return. Final suite/native/build evidence is tracked in `tool/ui_polish_plan.json`; the whole-app polish goal remains active.

Comparison verification: **844 full-suite tests passed**, including locale wiring; analysis found no issues. **24 native checks passed on each platform** (the synthetic wide-layout case is host-only). A focused final visual case passed again on each platform after currency-code spacing refinement. All four final enlarged-text dark header/spec screenshots were inspected in `tool/ui_review_artifacts/comparison_{headers,specs}_dark_{android,ios}.png`.

Normal Android and iOS simulator builds succeeded and were installed/launched after the final comparison checks.


## Whole-app UI polish goal: shared currencies and share text

Shared USD/IQD displays now keep each currency code attached to its amount at line breaks, including balances, packages, listing cards, comparison and the payment summary. The comparison-only spacing workaround was removed. Non-finite conversion results use the translated unknown-price fallback instead of throwing during rounding. The existing conversion rate and whole-number rounding are unchanged.

Car share text now uses the car form's declared USD units at every price magnitude, accepts Arabic/Persian digits and retains non-numeric price labels without inventing a currency. The legacy threshold guessed that amounts above 100000 were already IQD and stripped localized digits. The business-ad share preview now omits `ad.price`: creation assigns the selected advertising package fee to that field, so it is not a public goods/service offer price. Names, locations and app branding remain in the text.

Both share actions guard duplicate taps, await the platform result, restore controls safely after route disposal and use localized failure feedback. Business share engagement is recorded after successful platform handoff (including platforms that cannot report the chosen action), and not after a thrown error or a reported dismissal. This does not prove message delivery.

All share calls and backend traffic are intercepted in this pass: no native share sheet opened, no recipient selected and no real message sent. A test-only preview harness renders the actual message builders for visual review; no preview step was added to product flows. Actual OS/recipient-app handoff remains unverified. The existing share text still has no independently verified listing deep link. Focused verification passed **94 tests**, including locale wiring, currencies, payment/comparison layouts, share contents, retries, pending duplicate guards, disposal and handoff/dismissal analytics. Final suite/native/build evidence is recorded in `tool/ui_polish_plan.json`; the whole-app goal remains active.

Share/currency verification: **869 full-suite tests passed**, including locale wiring; analysis found no issues. **23 intercepted share checks passed on Android and 23 on iOS**. Both enlarged-text dark text previews were inspected in `tool/ui_review_artifacts/share_price_preview_dark_android.png` and `share_price_preview_dark_ios.png`. Shared-currency native results and normal builds are tracked alongside these checks.

Shared-currency verification passed **14 native cases on Android and 14 on iOS**. Both actual shared-price-surface screenshots were inspected in `tool/ui_review_artifacts/shared_currency_wrapping_dark_android.png` and `shared_currency_wrapping_dark_ios.png`, including a listing card, package amount and wallet-label sample.

Normal Android and iOS simulator builds succeeded. Real-service guest journeys passed on both platforms in Arabic, Kurdish and English; the preserved normal apps were reinstalled and launched after those checks. Authenticated staging and actual OS share handoff remain outside this verification.

### Visible Home polish — 22 October 2026

The opening Home screen now has a compact brand/compare header, a burgundy discovery panel with the existing search-tab entry, and rounded quick destinations for cars, the market and business listings. Large text stacks the destinations; section actions wrap within their available width. The decorative IQ image placeholder fits its bounds without applying accessibility text scaling to a logo. Arabic, Kurdish and English, both themes and 320px enlarged-text layouts are covered. Real rebuilt Home screens were inspected on Android and iOS; see `tool/ui_review_artifacts/home_after_visible_polish_android.png` and `home_after_visible_polish_ios.png`, with the previous Android Home captured alongside.

Business listings now distinguish read failures from empty results, retain loaded rows on refresh/pagination errors, support explicit retry and use stable date/ID ordering with deduplicated rows. A full-width localized category dropdown replaces the constrained chip strip. Cards wrap business names and locations, omit empty photo headers, and label public ads neutrally as business ads. Home business banners now open their detail pages, and contact actions have larger targets. Tests exercise initial retry, pagination retry at the same cursor, and category persistence across a locale change. In-flight stale category/refresh races and populated native feed inspection remain pending.

Validation: 884 unit/widget tests passed; `flutter analyze` is clean. Normal Android debug and iOS simulator builds passed and were installed for visual review. The full-app polish goal remains active; these changes do not establish production readiness or authenticated backend permission coverage.

Live guest checks also passed in ar/ku/en on both Android and iOS, including locale changes and filters (`/tmp/motriiq-home-visible-live-android.txt`, `/tmp/motriiq-home-visible-live-ios.txt`). Normal apps were restored and launched after testing.

### Search discovery and recovery — 22 October 2026

Search now has a burgundy-themed introductory panel. Text filters follow the selected language direction; numeric inputs remain LTR and accept Arabic/Kurdish digits and grouped amounts. Invalid non-finite/negative numbers, fractional years and reversed ranges are rejected before querying.

Every replacement search invalidates older manual, debounced and paginated responses, including clearing/resetting criteria. Stale failures cannot overwrite newer successful results. Initial read failures use a visible retry panel instead of claiming there are no matches. Pagination failures retain loaded results and wait for explicit retry. A raw row cursor, stable ID tie-breaker and deduplicated displayed IDs prevent pagination overlap from corrupting the cursor.

Validation: 895 unit/widget tests passed; analysis is clean. Eleven controlled Search cases passed on Android and iOS. Native fixture error/header screenshots were inspected; their original harness omitted SafeArea, so the harness was corrected and its 11 host checks passed again. Real-shell screenshots (`tool/ui_review_artifacts/search_live_android.png`, `search_live_ios.png`) were also inspected and show the correct system-bar spacing. Normal Android debug and iOS simulator builds passed. These read-only checks do not verify production saved-search writes. Freezing submitted criteria while a user edits quick filters, saved-alert persistence and the remaining screen-inventory audit are tracked follow-ups.

Design review correction: the user rejected the recent styling as insufficiently reference-led. Functional/native results above remain valid but do not imply visual acceptance. Actual AutoScout24 app screenshots and the Cars.com delivery-partner screen flow have now been inspected; the revised discovery design direction and source URLs are recorded in `tool/ui_polish_plan.json`. Home, Search/results and listing cards require a coherent follow-up redesign before broad rollout.

### Reference-led discovery revision — 22 October 2026

This revision supersedes the oversized Home/Search panels described above. Actual AutoScout24 app screenshots and the Cars.com delivery-partner flow were visually studied before rebuilding this set. Home now uses a compact brand/search area, short category actions and a single photo-led latest feed. The duplicate carousel/mosaic above that feed was removed. Search has one consolidated criteria sheet, including city and body type, with a compact search/sort/results layout. Submitting dismisses the keyboard and suggestions; active criteria summaries open the editor without a misleading remove affordance.

Regular vehicle cards share edge-to-edge photography, title, prominent USD asking price, smaller IQD conversion, specifications and location. Noto Sans Arabic is bundled as `MotriSans` at weights 400–800 for consistent multilingual typography, with its SIL OFL license included in app assets. Static weights were generated from the official Google Fonts variable source using FontTools; no font download is required at runtime. Source URL and SHA-256 are recorded in the design tracker.

Saved alerts now map supported consolidated criteria to the existing backend schema, validate localized numeric ranges, guard duplicate saves, require an acknowledged ID and handle route disposal and generic localized failure. Model/fuel/transmission/mileage filters cannot be represented by the installed schema and receive explicit guidance rather than being silently discarded. Saved-alert write tests use isolated fake auth/HTTP; no production alerts were created.

The final full suite passed **900 tests**, including locale wiring; analysis was clean. Native populated Home/Search cases passed for all three languages and both themes on Android and iOS, requiring a decoded public vehicle photo rather than a placeholder. Screenshot review led to heading-width, currency-hierarchy and submitted-keyboard fixes. Final dark icon contrast and live guest checks are recorded in `tool/ui_polish_plan.json`. Global typography review across remaining seller/admin screens and the complete per-screen evidence audit remain active.

Final discovery verification: six populated locale/theme cases passed per platform (`/tmp/motriiq-reference-final-visual-{android,ios}.txt`), with all eight final Home/Search images inspected. Real guest journeys then passed ar/ku/en on both platforms (`/tmp/motriiq-reference-live-{android,ios}.txt`). Normal apps were restored after testing. Final icon-role changes also passed 24 focused checks including a minimum 3:1 submit-icon contrast check in both themes.

### Compact grids and inventory audit — 22 October 2026

Compact vehicle and Market summaries now share a photo/title/price/metadata structure. Vehicle asking prices have a strong USD line and a smaller IQD equivalent when the compact space permits; previous higher asking prices retain their strike-through treatment in roomier summaries and full cards. Responsive grids use one to three columns according to width and text size, with enough height for readable metadata. Horizontal recommendations and Favorites use the same sizing system. Vehicle thumbnails retain a 4:3 frame where constraints permit. Favorite and compare controls have directional placement and at least 44px targets; pending Favorite taps no longer fall through and open the detail route.

Section pagination now marks requests busy, uses a raw cursor with stable date/ID ordering, deduplicates displayed IDs, rejects obsolete responses after refresh/brand changes and offers a full-width retry without discarding prior rows. Favorite writes are guarded, scoped and acknowledged before changing state; failures use localized generic feedback. Market summaries no longer hardcode the Arabic word for dollars, and nonnumeric price labels are preserved.

Validation: **920 full-suite tests passed**, including locale wiring; analysis is clean. **20 native action/layout checks passed per platform**, followed by **12 loaded-photo visual cases per platform** across all locales, both themes and ordinary/enlarged text. All eight grid screenshots in `tool/ui_review_artifacts/reference_grid_*.png` were inspected. Real guest journeys passed ar/ku/en on Android and iOS, and normal builds were restored after testing. All Favorite write tests use isolated auth/HTTP fixtures, not production accounts.

`tool/ui_completion_audit.json` records source-backed completion gaps rather than equating test counts with full-app completion. The inventory now includes **39 named screen/startup surfaces and eight named overlays**: the original list omitted `MarketItemDetailsPage` in `lib/market_images.dart` and the startup surface. That detail route, its editing/picker flows, mandatory Home/selected Market read recovery, duplicate Favorite representations, and current-font review across remaining pages remain active work. Existing test references in the audit are navigation aids until their actual assertions have been reconciled.

Visual refinement after the compact pass: the embedded Cars tab now relies on the shell’s Add action, while standalone routes retain their contextual action. Favorite/compare surfaces are 32px inside at least 44px tap targets, and card/rail vertical allowance is reduced. The updated full suite passes **921 tests**; analysis is clean. The 12 loaded-photo native cases passed again on each platform, with all eight Arabic/Kurdish ordinary/enlarged checkpoints inspected. This does not close the remaining full-app audit.

### Market details and photo editing — 22 October 2026

Market details now uses the same photo-first layout, bundled typography and rounded symbols as discovery. Titles, descriptions and metadata follow their content direction; surrounding navigation follows the selected locale. Prices use localized USD formatting for numeric product prices, preserve nonnumeric labels, and keep job salaries in their declared form without inventing a currency. Long metadata wraps; phone numbers are selectable LTR text. Dark surfaces and photo counters/arrows now have readable contrast.

Market/job photo pickers share theme-aware controls, 44px remove targets, local byte previews, cover selection/reordering and pending-picker/disposal guards. The editor supports both tables, freezes edits while saving, checks ownership/session, requires a scoped acknowledged row and preserves the draft on localized failure. A successful save refreshes images in the detail route instead of closing it. Admin deletion requires an acknowledged deletion count of one, guards repeat actions and presents localized feedback without database diagnostics. All mutation checks use isolated fixtures.

The full host suite passes **944 tests**, including locale wiring; analysis is clean. Twenty-two native checks plus the owner cover-refresh regression passed per platform; all ten detail/editor checkpoint screenshots were inspected. Normal builds were restored and launched after testing. Exact logs are recorded in `tool/ui_polish_plan.json`. Public photo decoding is checked in native fixtures. OS media selection, actual Storage uploads/RLS and production admin permissions remain unverified; the separate Market/job creation form remains active audit work.

### Market/job creation form — 22 October 2026

`GenericAdEditorDialog` replaces the anonymous creation form. Fields use the shared typography, surfaces and spacing, with labels above inputs and fixed visible feedback/actions. The route owns its controllers, preserves selected shift keys across locale changes, validates localized finite nonnegative amounts and freezes edits/photo controls while submitting. Product price remains optional; salary, location and shift are required for jobs. Stored shift labels stay compatible with existing Arabic rows and render in the selected language.

Submission snapshots inputs, checks the original session/owner, requires a matching acknowledged ID and preserves draft values and resolved image URLs on failure. A secure per-draft UUID is reused on retries, preventing a second row after an uncertain acknowledgement; uncertain results direct the user to inspect their listings before retrying. Success means the listing was submitted, without promising public visibility. No production listing or storage upload was created by tests.

The full suite passed **973 tests**; final locale wiring checks and analysis passed after the success-copy adjustment. Native form/action logs and screenshot review are recorded in `tool/ui_polish_plan.json`. The inventory is now 39 named screen/startup surfaces plus nine named overlays. Real OS media selection, staging Storage/RLS and publication behavior remain unverified.

### Home recovery and synchronized favorites — 22 October 2026

Required Home car reads and the explicitly selected Market feed now distinguish network failure from real empty data and show a localized retry action. Optional empty sections continue to collapse. Early error observation prevents a delayed/unselected failed future from escaping before its builder attaches. Home disclosures mirror with RTL. Native review also found the fixed-size MIQ artwork clipping at enlarged text; its decorative text now keeps its artwork scale, while screen text remains scalable. Its motion stops when reduced motion is enabled.

Favorite state now notifies all mounted copies after confirmed writes. Duplicate cards share the pending guard; cache reads and write tokens are scoped to account/generation, stale bulk/reset/account responses are ignored, and confirmed changes survive an older bulk response. Per-car fallback reads coalesce, and a card rebound to another ID does not inherit an older save result. Listener removal and async disposal are covered. No production favorites were changed.

The final full suite passes **987 tests**, including locale wiring; analysis is clean. Eight Home recovery cases passed on each native platform and all eight final Arabic/light and Kurdish/dark enlarged-text captures were inspected. Updated native card/action verification and normal-build restoration are tracked in `tool/ui_polish_plan.json`. Ads are deliberately unavailable in recovery fixtures; these are not consent, ad delivery, or production RLS tests. Remaining work includes current-theme acceptance across the rest of the screen inventory, Business feed timing evidence and native media/staging verification.

### Business discovery and current-theme review — 22 October 2026

Business detail now separates a readable pinned toolbar from the shared photo gallery, bounds content width, hides invalid/empty media and uses consistent metadata/contact controls. Content follows its own script; numeric-only opening-hour ranges stay LTR in Arabic/Kurdish. Map/social taps now record one click, and social links no longer count as map events. Category/refresh timing checks reject stale responses. All analytics and contact actions in these checks are isolated fixtures.

Current-theme native review covered Account/Profile (48 cases), creation forms (26), support/legal (32), and settings/history/fines (25) on each platform. All 28 captures were reviewed; the review found oversized Account quick actions and an incorrect WhatsApp field icon. Account actions now become compact horizontal rows in the enlarged-text single-column layout, with natural height, shared icons and mirrored chevrons. Separate revision reports preserve the source baseline and native capture evidence.

The full host suite passes **998 tests**, including locale wiring, and analysis is clean. See `tool/ui_review_artifacts/current_theme_{android,ios}.json` and `account_hours_revision_{android,ios}.json`. This is not whole-app completion: populated MyAds edit/delete, vehicle offer/submission recovery, remaining modal-state reconciliation, the Business creation WhatsApp icon and real media/Storage/RLS/store checks remain tracked in `tool/ui_completion_audit.json`.

### Owned vehicle editing and deletion — 22 October 2026

“My ads” now uses bounded cards with wrapping vehicle titles, readable year/USD metadata and explicit edit/delete actions below the content. The offers action uses a compact accessible toolbar icon, and the list supports pull-to-refresh. `OwnedVehicleDialog` owns its controllers until route disposal, uses scalable stacked fields, accepts localized finite numbers, validates years/prices and preserves existing selector values that are absent from current option lists.

Saves and deletes check the listing owner/current session, scope the mutation by listing and user ID, reject empty or mismatched acknowledgements, disable actions/back navigation while pending and handle disposal. Save failures retain the draft; delete uncertainty directs the user to refresh before retrying. No private server diagnostics appear. Dedicated fixtures do not modify production listings.

The full host suite passed **1016 tests** and analysis is clean. Native evidence and any follow-up results are recorded in `tool/ui_review_artifacts/owned_vehicle_{android,ios}.json` and `tool/ui_polish_plan.json`. Completion of the entire app remains open, including vehicle offer/AddCar recovery, Business submission partial-write recovery and actual staging media/RLS/store verification.

Owned-vehicle native result: 17 cases passed in each full run; one numeric-validation fixture initially kept the previous year after focus dismissal. Explicitly focusing the field before entering the correction fixed that fixture, and the targeted case then passed on both platforms. Production code was unchanged for this follow-up. All 12 populated/editor/failure captures were inspected.

### Vehicle offer form and recovery — 22 October 2026

`VehicleOfferDialog` replaces the form that previously closed before inserting the offer. The route now owns amount/message controllers, retains the draft on server or acknowledgement failure, uses wrapping labels and directional inputs, and separates feedback from an adaptive button row. Localized positive finite amounts and asking-price values are normalized consistently. Pending actions/back navigation are guarded; late responses after disposal do not update the route, and session/self-offer checks run before a write.

Each draft has one secure UUID reused on retry. Success requires exactly one matching acknowledged offer ID and the same signed-in buyer. Uncertain responses direct the user to inspect existing offers before retrying; reusing the primary key prevents a second row if the first response was lost. Database diagnostics remain internal. The repository schema permits explicit UUID IDs and buyer reads/inserts; its deployment and actual RLS/notification triggers require staging verification. No production offer or message was sent.

The final full host suite passes **1030 tests**, including locale wiring; analysis is clean. Native offer reports, screenshots and final build restoration are tracked in `tool/ui_polish_plan.json` and `tool/ui_review_artifacts/vehicle_offer_{android,ios}.json`. AddCar upload/submission recovery, Business ad/order partial failure and remaining all-screen state reconciliation are still open.

Final vehicle-offer native verification: **14 cases passed per platform** after the adaptive footer refinement. All eight final Arabic/light, Kurdish/dark, English recovery and normal-text captures were individually inspected. Native fixtures intercepted every offer write.

### Add Car media, validation and submission recovery — 22 October 2026

Add Car now reads and decodes a complete photo selection before adding it, keeps the photo/byte lists synchronized, guards duplicate pickers and disposal, and enforces the 15-photo cap. Photo removal has a 44px tap target with a smaller visible circle; photo counters and add/location controls use readable theme colors. The form is bounded to 760px and shows localized upload progress, persistent failure feedback and the publish action together.

Publishing snapshots the draft and photos, scopes it to the starting account, caches completed uploads and plate metadata, and reuses stable listing/photo UUIDs on retries. Partial uploads retry only incomplete photos at their original paths. A matching insert ID is required before clearing the form; uncertain database responses preserve the draft and direct users to inspect existing listings. Success resets both the fields and submission identity. No server diagnostics are exposed.

The new failure/validation checks exposed a lazy-form bug: fields scrolled out of view may have no mounted validator. Complete draft validation now runs before uploads, and attempted fields validate when remounted. Optional blank year/price remain supported; nonblank values must be valid, finite and within the supported year range. Reset ordering was also corrected so successful submission cannot restore stale values.

The final full suite passes **1050 tests**, including 20 dedicated Add Car cases and locale wiring; analysis is clean. Eighteen initial native recovery/media cases passed per platform; final visibility, contrast, normal-text lifecycle and invalid-field checks are tracked separately in `tool/ui_review_artifacts/add_car_submission_revision_{android,ios}.json`. Public seed-photo bytes are fetched read-only for native previews; every upload, insert and auth call is isolated. Real OS picker handoff, deployed Storage/RLS/approval and release publication remain unverified.

Final Add Car native follow-up: **four cases passed per platform** after the feedback/contrast and complete-draft validation fixes. All ten final captures were inspected, including normal text with the native keyboard, and two consecutive acknowledged listings used fresh IDs. The earlier 18-case native recovery/media run remains separate evidence.

### Business submission recovery and immediate startup — 22 October 2026

Business creation now previews decoded photo bytes, enforces complete readable selections and the five-photo cap, keeps media controls at accessible tap sizes, and uses the shared chat icon for WhatsApp. The bounded form keeps its finite fields mounted so validation and submission feedback remain available. Package names, durations and currency amounts have separate direction-aware text, and long features wrap rather than being clipped. Locked package content remains readable.

`BusinessSubmission` freezes a reviewed request, retains secure stable ad/order/photo IDs and completed uploads, and requires matching scoped acknowledgements before navigating to payment. An order failure resumes the original ad; a lost acknowledgement is reconciled by a scoped read before retrying. Pending actions, picker failures, session changes and route disposal are guarded. The confirmation shows the selected package and actual price before any upload. These fixtures intercept all auth/upload/ad/order writes; deployed Storage/RLS/approval/payment behavior still requires staging verification.

Optional blank vehicle year/price can now be preserved or cleared during editing, consistent with creation. The redundant 2.5-second Flutter splash and overlapping animated text were removed: the initialized app opens Home directly. Android and iOS native launch backgrounds follow OS appearance.

The current full host suite passes **1089 tests**, including locale wiring, 13 Business service cases, 18 Business screen cases and six startup cases; analysis is clean. Final device evidence and any limitations are recorded in `tool/ui_review_artifacts/business_submission_final_{android,ios}.json` and `tool/ui_polish_plan.json`. The whole-app goal remains active while current-theme evidence on remaining seller/admin surfaces, native picker selection and final production artifacts are reconciled.

Final native result for this pass: **18 Business + 6 startup cases passed per platform**, followed by one confirmation-copy check per platform. All captures were inspected. Confirmation now accurately says that submission continues to payment instructions. Normal Android and iOS apps were rebuilt, installed and returned to Home.

Real AddCar native picker verification also passed on both platforms: select a local image, show the decoded preview, remove it and cancel a new selection without losing the unsent form. No Publish/Send/payment action was invoked. See `tool/ui_review_artifacts/native_picker_local_review.json`; the reusable iOS simulator UI runner is in `tool/native_picker_review/` (generate its temporary Xcode project with `ruby tool/native_picker_review/create_project.rb /tmp/motriiq-native-picker-review`). This does not prove real Storage/RLS or every other picker entry point. Remaining current-font screen targets are explicitly listed in `tool/ui_completion_audit.json`.


### Carivo / Drivo reference direction and typography review — 22 October 2026

The user-supplied Carivo and Drivo public previews were visually reviewed. Carivo guides the marketplace search, photo and price hierarchy; Drivo guides grouped service sections and consistent component treatment. MOTRI IQ retains burgundy and its Arabic/Kurdish-capable bundled font. The reference decisions and original URLs are in `tool/ui_polish_plan.json:user_reference_direction`. No paid kit source assets were downloaded.

Home now uses a focused dark burgundy search panel and a clear search entry point. Shared compact cards have quieter outlines. Vehicle details separate the primary USD asking price from the secondary IQD conversion and use a readable dark-theme price color. Seller descriptions, reviews, notifications and chat follow their content direction. Disclosure and gallery arrows rely on Flutter mirroring once. The Kurdish reports toolbar title stays within one line.

Sale and report dialogs now retain localized failure feedback and guard pending requests, account changes and acknowledgements. A confirmed sale updates the detail and My Ads status. Report writes use INSERT-only acknowledgement to match the repository reporter RLS policy. The My Ads refresh no longer returns a Future from a setState callback. Backend mutations in these checks are mocked.

The full host suite passes **1123 tests**, including locale wiring. Current-theme device matrices passed 144 initial cases and 72 direction/decision/gallery revision cases per platform. All 88 initial and 44 revision captures were inspected; affected initial captures document bugs and are superseded by revision evidence. New Home/price/chat and safe-area/toolbar follow-ups are tracked separately. See `tool/ui_review_artifacts/typography_visual_acceptance.json` and `tool/ui_completion_audit.json` for exact scope. The full redesign, remaining modal-state reconciliation, staging uploads/RLS and final release artifacts remain incomplete.

This visual revision also passed 30 Home/price/chat device cases plus 12 safe-area/toolbar/centered-price follow-up cases per platform. All 16 follow-up and four chat captures were inspected. Both normal debug apps were rebuilt, installed and launched after the tests. Analysis is clean.


### Vehicle detail specification tiles — 22 October 2026

Vehicle details now use quiet icon/label/value tiles, adaptive one/two/three-column rows and equal row heights for wrapped values. The title is lighter, user text follows its content direction, Mileage has its correct label, and specification/estimate/seller icons use theme-aware accents. The specification group no longer stacks borders and shadows around every chip.

The full suite passed 1123 cases before the final copy and equal-row refinements. Those refinements pass 31 regular-phone/locale checks, 12 enlarged tablet-width checks and 19 enlarged detail checks; analysis is clean. Fourteen initial device cases plus two equal-row follow-up cases passed per platform. Sixteen accepted title/specification captures were reviewed, with revision boundaries documented in `tool/ui_review_artifacts/typography_visual_acceptance.json`. This is a visual pass, not completion of remaining filter/showroom/media recovery or production verification.


### Fonts and Home carousel — 22 October 2026

Arabic now uses bundled Cairo and English uses Inter, including button and navigation labels. Kurdish retains Noto Sans Arabic for complete Sorani glyph coverage. Font sources, hashes and OFL licenses are recorded locally. Home now shows up to five photo listings in a swipeable carousel with previous/next controls, position indicators, a simple USD price badge and reduced-motion/accessibility safeguards. Empty carousel sections are hidden.

Numeric filters now retain invalid input and explain invalid/oversized or reversed bounds. Saved alerts map only criteria represented by the current backend trigger and explain unsupported combinations instead of silently changing their meaning. Backend mutations in tests are mocked.

Final full suite: **1149 passed**, including locale wiring; analysis clean. Nine native cases passed per platform, with sixteen fixture captures reviewed. Final normal debug apps were built, installed and opened on Android emulator and iOS Device Hub; both Home screenshots were reviewed after the final font and badge corrections. Remaining screens still need final Cairo/Inter visual acceptance; showroom/media recovery, staging verification and production readiness remain open.


### Showroom recovery — 22 October 2026

Showroom setup now has localized load retry and retained save-error feedback. Failed loading blocks editing until retry succeeds. The page captures its account owner, hides another account’s draft and guards pending requests, disposal and account changes. Names match the database’s 2–80 character constraint; successful saving requires a matching seller acknowledgement. Long titles stay within the toolbar with the real back button.

The full suite passed 1161 tests before the final title refinement; all 50 affected showroom/form/locale checks passed afterward and analysis is clean. Six enlarged locale/theme cases passed per platform on the final pushed route. Four final captures were visually reviewed, and both normal debug apps were rebuilt, installed and launched. Writes and auth are mocked in these checks; deployed showroom RLS is still a staging verification item. Media retry recovery and the remaining whole-app font/state audit remain open.


### Market/job photo recovery — 22 October 2026

Creation and image-edit dialogs now keep a route-owned upload session: completed photos are remembered individually and a failed upload retries the same owner-scoped Storage path. Database retries preserve photo order without uploading completed files again. Account/disposal checks stop later uploads and listing writes after the editor becomes inactive. JPEG MIME is corrected and common PNG/JPEG/WebP signatures are recognized. Upload errors now explain that drafts/photos are retained; image-edit feedback stays visible above Save/Cancel while photos scroll.

The full suite passed 1176 cases before the final feedback/footer refinements; the final 79 affected editor/detail/locale checks passed afterward and analysis is clean. Fifteen native cases plus six final footer follow-ups passed per platform. Sixteen final captures were reviewed; eight earlier edit captures record the hidden-feedback bug and are superseded. Both normal debug apps were rebuilt, installed and launched. Auth, uploads and listing mutations are mocked in these checks. Repository owner-scoped Storage upsert policies support the path structure; deployed Storage/RLS, abandoned-upload cleanup and live publication still require staging verification. Session caching ends when the editor closes. Whole-app font/state review and final production artifacts remain incomplete.


### Bottom navigation — 22 October 2026

The six-destination bar now uses consistent icon slots, a native burgundy-tinted selected indicator, a quiet rounded surface, readable 11px minimum labels and a centered row on wide screens. Concise Kurdish labels and English Profile keep destinations on one line. Native safe areas, focus/selection semantics, localized tooltips and reduced-motion animation are retained.

Final full suite: **1194 passed**; analysis clean. Thirty-five navigation/shell/locale checks include actual bundled-font measurements at 320/390/900px, large text, RTL/LTR, light/dark, bottom insets, minimum 48px target widths and selected screen-reader semantics. The actual shell still exercises all six destinations. Six final native cases passed per platform; four final Arabic-light/Kurdish-dark captures were reviewed. Earlier Kurdish captures exposed wrapping and are superseded by the label revision. Both normal debug apps were rebuilt, installed and launched, and their Home screenshots were visually accepted. Whole-app final font/state review and production gates remain open.


### Car requests and safe retry — 22 October 2026

Request and seller-offer cards now use primary USD and secondary IQD, and user-entered titles/descriptions follow their content direction. Request/offer errors and progress remain beside the dialog actions while long forms scroll.

Each request editor keeps a UUID across retries. A duplicate response is reconciled only by that ID and original buyer, with saved fields compared before success. Changed drafts explain that an earlier version was published. Account changes refresh scoped reads, discard late results from another account, and guard create/offer/decision acknowledgments and success messages.

Final full suite: **1202 passed**; 53 affected request/locale checks passed and analysis is clean. Eighteen current-font layout and seven recovery/session cases passed per platform. All sixteen final captures were reviewed, including error footers above Android/iOS keyboards. Initial price captures are superseded. Normal debug apps were rebuilt, installed and launched. Backend auth/writes remain mocked; deployed request/offer RLS and publication require staging verification. Decision-confirmation final-font visual review and remaining seller/admin/activity/wallet screen review remain open.


### Admin management and confirmations — 22 October 2026

Deletion confirmations now identify the selected ad and section, with translated copy and content-aware titles. Admin management clears cached rows on account change and rejects late access/table results from another session. Confirmations and deletion acknowledgements stay tied to the actor; public market details also guard the account around confirmation and completion. Admin cards use quiet borders, formatted USD amounts and readable text direction. Request decisions show progress only once an update starts.

Final full suite: **1218 passed**; analysis clean. Fifteen admin cases and seven final request-decision/progress cases passed per platform; twelve final captures were visually reviewed in Arabic light and Kurdish dark, including large text. Earlier request captures with pre-confirmation progress are superseded. A redundant online dependency fetch was cancelled after offline resolution proved the lockfile matched the workspace; remaining checks/builds used the cached graph. Both normal debug apps were rebuilt, installed and launched. All admin role checks/deletions and request mutations in these checks are mocked; deployed privileges, admin RPC and live moderation still require staging verification. Remaining seller/admin/activity/wallet font and state review remains active.


### Personal feeds and account changes - 22 October 2026

Six personal feeds reload on account changes and discard late responses from the previous session. Pending alert/notification opens stop after sign-out. Messages, reviews and sent offers provide empty-state refresh; cards use grouped amounts and content-aware titles. Tests caught and fixed Future-returning refresh callbacks.

Final full suite: **1235 passed**; analysis clean. Final session/locale subset: 29 passed. Each platform passed 36 layout and 17 final session/refresh cases; all 24 populated captures reviewed. Original refresh failures are superseded. Auth/data operations are mocked. Child chat/seller routes, deployed RLS and remaining screen/state acceptance remain open. Current-font targets were reconciled against all 38 entries; the previous list was not exhaustive.

Final normal Android and iOS debug apps were rebuilt, installed and launched after fixture verification.


### Comparison and Favorites - 22 October 2026

Comparison titles and specification values now follow their content direction, improving mixed Arabic/English data. Favorites reloads on account changes and rejects old-session results before secondary reads or image precaching. Signed-out guidance takes precedence over cached rows; empty Favorites offers Refresh.

Final full suite: **1256 passed**; 75 targeted checks passed; analysis clean. Each native platform passed 42 comparison/favorites cases and three Favorites session cases. The host-only wide-layout assertion passed on host and is skipped natively. All twelve populated current-font captures were visually reviewed. Initial fixture recovery failures were corrected by using a terminal mock error and scrolling the large-text action into view. Auth/backend calls are mocked; this revision covers saved-car grid, empty/error recovery, comparison actions and account changes. Mixed market-item Favorites, deployed RLS and remaining screen/state acceptance remain open.

Both normal debug apps were rebuilt, installed and launched after these native checks.


### Seller profiles, ratings and conversations - 22 October 2026

Seller profiles reload on account changes and clear personal draft/busy state. Owner offer decisions scope updates to the seller and pending status, require a matching row acknowledgement and ignore late responses from another session. Review dialogs and completion feedback remain tied to their initiating account. Reviews and received-offer text follow content direction; amounts are grouped.

Chat clears private messages/drafts when the account changes, suspends polling/composer access outside the route account and ignores late reads, sends and response-tracking continuations. Long titles ellipsize safely. Send is disabled for blank drafts and uses a readable active icon. Focused floating labels now meet 4.5:1 contrast checks in light/dark error and focus states.

Final full suite: **1269 passed**; 72 affected checks passed; analysis clean. Each platform passed 39 seller/Favorites cases, seven final profile/rating/mixed-grid followups and 19 final chat cases. Twenty-eight final captures were reviewed, including native keyboards and decoded photos. Twenty initial captures are superseded: they exposed dark-label contrast, incorrect forced keyboard insets, an offer scroll target below the card and photos still loading. Native fixtures now preserve actual keyboard metrics; host tests simulate insets. Chat interaction tests pump the draft change before tapping Send so requests are actually exercised.

Auth, review/offer/message writes and response tracking are mocked; only public photos are fetched. Deployed RLS/triggers, live contact handoff and real-account navigation remain staging/device checks. Mixed Favorites grid/detail navigation now closes the prior revision's visual gap. Chat draft direction still follows interface locale; automatic editing direction remains part of the remaining form review. Whole-app acceptance and production verification remain active.

Final normal Android and iOS debug apps were rebuilt, installed and launched after these fixtures.


### Account, settings and support - 22 October 2026

Settings waits for stored preferences before enabling edits, disables only the preference being saved and restores its previous value when persistence fails. User-profile reads follow account epochs; sign-out cannot navigate or show stale feedback for another account. Support cards use quieter borders and shared heading typography. Notification choices remain local preferences, as explained in the UI.

Full suite: **1274 passed**; 142 affected checks passed; analysis clean. Android completed 110 scoped account/settings/history/fines/support/legal/profile cases plus six focused-editor followups. iOS completed 104 non-keyboard cases across resumed runs; six final OTP/report keyboard checks remain unverified after the simulator restarted. Earlier Arabic/Kurdish OTP cases passed before restart. Sixty final captures were reviewed; no final iOS focused-editor acceptance is claimed.

Both device runs were interrupted by device shutdown/disconnection. Completed cases were retained and only unfinished work resumed. A newly active API35 emulator lacked installation space; no user data was deleted. The original API31 AVD was restarted and completed Android verification. The rebooted iOS device continued reporting zero software-keyboard height despite focused fields, explicit keyboard requests and Device Hub software-keyboard actions. Positive keyboard assertions remain intact. Geometry checks run before Verify can dismiss the keyboard, and final Android captures scroll the actual editors above pinned actions.

[Apple Device Hub input reference](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub) informed the input-control inspection; it does not prove the cause of the local keyboard problem. Native email/SMS, deployed auth/RLS, actual contact/report handoffs and policy/production configuration still require staging or real-device verification. All auth/backend/share calls in these fixtures are mocked. Auth label ellipsis at large text and content-aware editing direction remain explicit form-polish work. Whole-app acceptance remains active.

Both normal debug apps were rebuilt, installed and launched after fixture testing; cleanup analysis is clean.

### Auth labels and editing direction — 22 October 2026

Auth fields now keep compact labels visible and put the full identifier/username guidance in wrapping helper text. Name, chat and report drafts follow their first strong character without replacing the controller, cursor selection or IME composition; identifiers retain LTR.

Full suite: **1280 passed**; 117 affected checks passed; analysis clean. Android and iOS each passed 32 native cases (18 account, 11 chat, 3 report), and all 24 captures were reviewed. The isolated iPhone 17 Pro iOS26.5 QA simulator passed all six OTP/report keyboard cases with actual native keyboard insets. This supersedes the prior unverified input acceptance for these cases, while the original simulator’s keyboard environment remains unresolved. Backend/auth/support mutations remain mocked.

Normal Android and iOS debug apps were rebuilt, installed and launched on the original devices; the QA simulator was also restored. Both original Home captures were reviewed, including bottom navigation spacing, selection and safe areas. Whole-app polish and staging/production verification remain active.

### Unique bottom destinations — 22 October 2026

Market now opens its dedicated marketplace page instead of showing Home and scrolling it. Cars and Market have separate page keys; tapping the selected tab leaves the current page instance intact. All six destinations retain their existing order. Forty-one focused host tests, native navigation checks on Android and iOS, and static analysis passed. Normal debug apps were rebuilt, installed and launched after native fixtures.

### Marketplace state review — 22 October 2026

Market has a specific empty message, and its compact titles and list descriptions follow content direction. Six ar/ku/en light/dark large-text cases per platform cover pending loading, empty response, failure/retry and populated grid. All 16 native captures were reviewed; placeholder photos are intentional. Legacy tests requiring Market to display Home were replaced with unique-destination assertions. Full suite: **1286 passed**; 41 affected checks passed; analysis clean. Normal Android and iOS apps rebuilt, installed and launched after fixtures. Backend fixtures remain mocked and whole-app/production acceptance remains incomplete.

### Wallet session recovery - 22 October 2026

Wallet drafts now follow account epochs. Account changes clear amount/receipt/submitted state, reject late picker/settings results, stop a late upload from starting a transaction and suppress stale submit/admin feedback. Tests include signing out and returning to the same account while picker/upload/insert is pending. An insert already sent before sign-out can still reach the server; client guards do not replace server acknowledgement/idempotency or RLS.

Full suite: **1289 passed**; 35 affected checks passed; analysis clean. Each platform passed 23 wallet/payment native cases; eight current-font captures were reviewed. RTL amount chips currently render IQD before the number: tracked as a remaining visual followup. Normal Android and iOS debug apps rebuilt, installed and launched after fixtures. Backend/auth/storage/RPC operations are mocked. Whole-app and production acceptance remain incomplete.

### Wallet currency direction - 22 October 2026

Preset amount chips now use the shared isolated IQD formatter and explicit LTR text direction. Thirty-five affected host checks and analysis pass; six native large-text light/dark layout cases pass per platform, with four final captures reviewed. This closes the prior RTL amount-order followup. Normal Android and iOS builds restored after fixtures. The prior full suite remains 1289 passed; this narrow change received focused coverage. Whole-app and staging/production acceptance remain open.

### Car detail session and typography - 22 October 2026

Car-detail admin permission reads and deletion confirmations now follow account epochs. A late permission result cannot restore delete access after logout; returning to the same account cannot authorize a confirmation from its earlier session. Full suite: **1291 passed**; 54 affected checks passed; analysis clean. Android and iOS each passed 12 active/sold large-text detail cases and two session regressions. Eight typography captures reviewed for price hierarchy, contrast and wrapping/specs. Photos are placeholders: decoded gallery evidence and the separate green offer CTA/tight panel spacing remain explicit followups. Auth/admin RPC operations are mocked. Normal builds restored on Android and both iOS simulators. Whole-app and production acceptance remain incomplete.

### Branded car offer action - 22 October 2026

The offer button now uses theme primary/onPrimary colors, with 16px after the market-estimate panel and 12px between owner actions. Thirty-one affected checks passed; analysis clean. Each platform passed six active-detail native cases, with eight final captures reviewed. The earlier spacing test initially scrolled the lazy estimate panel offscreen; aligning the action at the viewport bottom measures both adjacent elements. Normal Android and iOS builds restored. Decoded gallery verification remains open; the previous full-suite result is 1291, not rerun for this focused visual change.

### Home shortcut chip fonts - 22 October 2026

The chip theme now explicitly inherits the app font families: Inter with Cairo Arabic/Noto Sans Arabic Kurdish fallback, semibold and zero extra tracking. This fixes the system-script appearance of Cars/Market/Business shortcut labels. Fifty focused checks and nine filter regressions passed; analysis clean. Each renderer passed six Home and six shared-wallet-chip cases; eight fixture captures reviewed. The Home fixture overrides ThemeData.platform to iOS; separately reviewed normal Android Home confirms default-platform rendering. Normal Android/iOS builds installed and launched, with both Home captures reviewed. Whole-app and production acceptance remain open.

### Decoded car gallery verification - 22 October 2026

Actual detail-photo tap opens the real gallery with a decoded public car image. Six native cases per platform verify paging controls, RTL/LTR swipe, pinch zoom/pan without page changes, reset and dismissal in ar/ku/en, light/dark and large text. Eight captures reviewed; 21 existing gallery/localization host checks pass and analysis is clean. The fixture repeats one public image across three slots, so distinct-angle loading is not claimed. Initial failures came from a counter finder also matching the underlying detail page; final assertions scope to the dialog. No application change was needed. Backend/analytics mocked; only the public photo is fetched. Normal apps restored and launched; whole-app and production acceptance remain incomplete.

### Wallet administration session recovery and confirmation - 22 October 2026

Private wallet review rows and pending controls clear when accounts change. Reads and async receipt/decision continuations follow account epochs; old confirmations cannot authorize a new session, even when the same account returns. Final dialogs separate localized prompt, IQD amount, content-directed requester name and ID. Earlier inline-sentence captures are superseded: visual review showed isolation alone did not make long mixed-language confirmations easy to read.

Final full suite: **1296 passed, six native-only gallery cases skipped**; 34 final affected checks pass; analysis clean. Each platform completed 22 distinct wallet-review cases, with six final structured-dialog layout followups after an intermediate six-case bidi pass. Eight final captures reviewed and accepted; initial/intermediate captures superseded. Normal Android/iOS builds rebuilt, installed and launched after fixtures. Auth, wallet rows, receipt signing and decision RPCs are mocked. Already-dispatched decisions cannot be undone by client guards; successful external receipt launch, deployed authorization/RLS and actual balance changes remain staging/device checks. Whole-app acceptance remains incomplete.

### Reports dashboard session recovery - 23 October 2026

Report reads, moderation/verification confirmations, updates and reported-listing navigation now follow account epochs. Account changes clear private rows and busy state. Old confirmations cannot authorize a replacement session; late writes cannot announce success or refresh old data, and late listing reads cannot navigate after logout. Report descriptions follow their content direction.

Final suite: **1303 passed, six native-only gallery cases skipped**; 40 affected checks passed; analysis clean. Each platform passed 28 reports cases. Twelve captures reviewed for current-font Arabic light/Kurdish dark report cards, status confirmation and seller-verification confirmation at large text. Normal Android/iOS builds rebuilt, installed and launched after fixtures. Backend/auth/verification writes remain mocked; already-dispatched requests cannot be canceled by client guards. Actual moderation authorization and identity verification require staging checks. Business moderation and remaining seller/business screens remain pending.

### Business moderation and private previews - 23 October 2026

Business moderation now scopes reads, package lookup, confirmations and update feedback to account epochs. Account changes clear ads/busy state and reset the status filter. Names follow content direction and confirmations identify the ad. AccountScopedView hides business and reported-car admin previews when the opening session changes; signing back in requires opening a fresh preview. Existing approval behavior still confirms payment and starts the package period, as its confirmation explains.

Final full suite: **1316 passed, six native-only gallery cases skipped**; 40 business and 43 reports/localization affected checks passed. Analysis clean. Each platform passed 28 business-moderation and three reported-preview cases. Sixteen current-font captures reviewed for lists, approval/payment dialogs and expired previews. Normal Android/iOS builds rebuilt, installed and launched after fixtures. Logs retained under tool/ui_review_artifacts/business_moderation_final_full.txt and sibling verification logs. Backend/auth/payment/package/analytics operations are mocked; deployed authorization and actual financial/moderation effects remain staging checks. The six remaining screen font targets and request/search chip-font native followups remain open.


### Request and search chip typography - 23 October 2026

Reviewed current fonts in request open/mine tabs and active search criteria. Fixed the Clear filters label overflowing on narrow screens at enlarged text by allowing it to wrap within the available width. The new populated-filter matrix exposed the issue in all three languages.

78 affected checks pass; full suite **1322 passed, six native-only gallery tests skipped**. Analysis clean in the ASCII validation copy (the original Unicode workspace path crashed the analyzer protocol parser). Twelve native cases per platform pass across ar/ku/en, light/dark and text scale 1.6; twelve Arabic-light/Kurdish-dark captures inspected. Normal Android/iOS debug builds rebuilt and restored. Evidence: tool/ui_review_artifacts/request_search_chip_fonts_{android,ios}.json and request_search_chip_full.txt. This closes the shared-chip followup; the six remaining screen targets, broader state reconciliation and staging/production limits remain open.


### Business discovery and detail typography - 23 October 2026

Business card names, locations and descriptions follow their content direction; blank detail names use the same localized fallback as cards. Current Cairo/Inter/Noto typography reviewed for initial loading, initial error/retry, empty, populated, photo detail and contact controls.

48 affected checks pass; full suite **1347 passed, six native-only gallery tests skipped**; analysis clean. Thirty native cases/platform pass across ar/ku/en, light/dark and text scale1.6;24 Arabic-light/Kurdish-dark captures inspected. Native photo uses a known public image; backend/analytics mocked. Normal debug apps rebuilt and restored after fixtures. Evidence: tool/ui_review_artifacts/business_current_fonts_{android,ios}.json and business_current_font_full.txt. Four current-font screen targets remain: Add Car, My Ads, business creation and market detail. Business pagination/retained-data refresh-error current-font native followup, broader screen-state reconciliation and staging/production checks remain open.


### My Ads session recovery and typography review - 23 October 2026

My Ads reloads and clears private listing data on account changes, discards prior-session responses and protects already-open previews/edit/delete dialogs through AccountScopedView. Returning to the same account requires reopening the route. Old modal completion cannot refresh or clear mutation state in a replacement session.

101 affected checks pass; full suite **1375 passed, six native-only gallery cases skipped**; analysis clean.34 native cases/platform pass across ar/ku/en, light/dark and scale1.6;32 captures inspected.28 list/recovery/expired-route captures accepted. Four editor captures remain flagged: prose fields inherit interface direction and enlarged labels/actions need a density pass. Normal debug apps rebuilt and restored after fixtures. Backend/auth/write fixtures mocked; deployed RLS and real owner actions remain staging checks. Three main screen font targets remain (Add Car, business creation, market detail), alongside the explicit owned-editor followup and broader state/production audit. Evidence: tool/ui_review_artifacts/my_ads_current_{android,ios}.json and my_ads_current_full.txt.


### Owned editor direction and density - 23 October 2026

OwnedVehicleDialog prose fields now follow typed content direction with editing values/composing ranges preserved. Numeric and phone identifiers stay LTR. Labels, title and action typography are more compact while retaining accessibility scaling; dropdown values follow their content direction. This resolves the four editor captures flagged by the preceding My Ads review.

Full suite **1384 passed, six native-only gallery tests skipped** on final product source. Final97 affected checks pass after strengthening native keyboard attachment/draft-persistence assertions; analysis clean. Nine distinct native cases/platform passed (six direction/theme matrices plus three real-keyboard cases);12 executions/platform include the superseded initial keyboard checks.12 accepted captures inspected: eight top/bottom and four final keyboard captures. Draft persistence, keyboard height and action clearance asserted. Normal Android/iOS debug apps rebuilt and restored. Backend/mutations mocked; staging RLS/owner writes and original iOS keyboard environment remain unverified. Three main screen font targets and broader state/production reconciliation remain open.


### Bottom navigation palette feedback - 23 October 2026

Replaced the selected bottom-tab pink/muted-maroon combination with brand burgundy and a white icon. Selected labels use near-white in dark mode and burgundy in light mode; inactive destinations remain neutral.30 navigation/localization checks pass across widths320/390/900 and text scale2. Six native cases/platform pass; four final captures inspected. Full suite **1396 passed, six native-only gallery cases skipped**; analysis clean. Normal Android/iOS apps rebuilt and restored. Evidence: tool/ui_review_artifacts/navigation_burgundy_{android,ios}.json.

Business creation preparation also passed55 affected checks: content-aware draft/review text direction and package loading/error/retry/empty matrices. Native form/recovery review remains pending; this preparation does not close the business creation current-font target.


### Business creation and market detail review - 23 October 2026

Business creation fields and review text follow typed content direction; package placements now separate their translated heading from individually directed values. Reviewed form/media/confirmation, partial-order recovery and package loading/error/retry/empty states with current fonts.18 native cases per platform passed;32 baseline captures inspected. Final package followup:6 cases per platform and4 captures inspected. Market detail:6 current-theme native cases per platform and8 captures inspected.

77 affected tests passed; full suite **1402 passed, six native-only gallery tests skipped**; analysis clean. Normal Android and iOS debug apps rebuilt, installed and launched after fixtures. Evidence: tool/ui_review_artifacts/business_create_fonts_{android,ios}.json, business_package_placements_{android,ios}.json, market_detail_current_fonts_{android,ios}.json and business_placement_full.txt.

Add Car remains the main current-font screen target. Its prose fields still inherit interface direction and need followup. Locked business media removal appearance, business pagination/retained-data refresh-error and the broader screen/state audit remain open. All backend mutations were mocked; OS picker/storage/RLS/payment/moderation and production readiness require their recorded staging/device checks.


### Advertise with us visual redesign - 23 October 2026

Replaced the bulky inline-label form with four grouped cards, persistent external labels, neutral text, soft filled inputs and smaller monochrome section icons. Description uses three lines; redundant input icons and pink section badges removed. Selected packages use neutral outlines/radios; submit remains burgundy. Locked photo-removal controls reflect their disabled state. Field direction, validation, draft persistence and submission recovery remain intact.

Final full suite **1402 passed, six native-only gallery tests skipped**; analysis clean.38 form/locale checks passed after updating the existing draft-retention test to target the stable field key. Final native review:12 cases per platform (six enlarged, six regular),24 captures inspected including Arabic dark mode matching the reported page. Initial floating-label card iteration is superseded. Normal debug apps rebuilt, installed and launched on Android and both iOS simulators. Evidence: business_form_redesign_{final,regular}_{android,ios}.json, business_form_redesign_full.txt and business_form_redesign_analysis.txt under tool/ui_review_artifacts/.

Backend mutations remain mocked. Add Car, business pagination/retained-data refresh-error, dedicated locked-media capture and broader state/staging/production reconciliation remain open.


### Add Car and retained business-list states - 23 October 2026

Add Car prose fields now follow the typed script, preserving selection/composing values. Numbers and phones remain LTR. External13px labels,14px fields, soft neutral fills and quiet15px headings align with the business editor. The city-location action is centered on the input and has an explicit48px target; the new geometry check exposed its previous40px default.

58 affected host checks passed before the final city followup; six city geometry checks and six business retained-state checks passed afterward. Final full suite **1414 passed, six native-only gallery cases skipped**; analysis clean. Add Car: six baseline native cases/platform plus six final city cases/platform,16 captures reviewed. Business pagination loading/error/manual same-offset retry and retained-data refresh failure/retry: six native cases/platform,12 captures reviewed. Earlier Add Car city-region captures are superseded by the aligned48px followup; all other baseline form/photo/recovery evidence remains scoped. Normal debug builds rebuilt, installed and launched on Android and both iOS simulators. Source/font build manifest matches final worktree.

Evidence: tool/ui_review_artifacts/addcar_current_fonts_{android,ios}.json, addcar_city_alignment_{android,ios}.json, business_retained_current_{android,ios}.json, addcar_final_full.txt and addcar_final_analysis.txt. All auth/backend writes/analytics mocked; native photos use a known public image. Main current-font screen targets and business retained-state followup are closed. Dedicated locked-business-media capture, broad screen/state coherence and native-media/staging/production reconciliation remain open; original iOS keyboard environment remains unverified.


### Filter draft direction and locked business media — 23 October 2026

Search filter brand, model and city fields now follow the typed script while preserving the original controller, selection and composing range. Numeric criteria stay LTR.27 focused search/locale checks passed; six new locale/theme cases verify opposite-script input and normalized-year application. Six native cases per platform passed; four Arabic-light/Kurdish-dark captures above real keyboards were inspected. Full suite **1426 passed, six native-gallery-only skips**; analysis clean. Evidence: `tool/ui_review_artifacts/search_filter_direction_{android,ios}.json`.

Dedicated locked-business-media review is closed within the mocked partial-order recovery scope: two native cases/platform,12 captures inspected. Disabled removal controls are muted and tapping them retains the photos and original upload/ad/order counts. See `tool/ui_review_artifacts/business_locked_media_visual_review.json`.

The normal-app AddCar OS picker also passed updated Android/iOS selection, decode, cancellation-retention and removal checks. Initial/add-more controls now expose labelled button semantics. No upload/publication/payment was performed. Broader screen/modal reconciliation, other native picker entry points and deployed Storage/RLS/payment/moderation checks remain open; the whole-app goal remains active.


### Language sheet accessibility — 23 October 2026

Reproduced bottom overflow across all locales/themes on a568x320 viewport at200% text (Arabic:138px). Language content now scrolls inside the existing safe area, keeping every choice reachable. The initial native dark capture also exposed a low-contrast burgundy selected radio; it now uses a light neutral in dark mode and burgundy in light mode, with a3:1 selected-control contrast check.

Twelve new portrait/short-height locale/theme cases verify selection, cancellation, scrolling and contrast.21 focused language/filter checks passed before the final color refinement; all12 language cases pass afterward. Final full suite **1438 passed, six native-gallery-only skips**; analysis clean. Six final native cases/platform passed; four final captures inspected. Initial dark captures are superseded. Normal debug builds succeeded for both platforms. Evidence: `tool/ui_review_artifacts/language_sheet_final_{android,ios}.json`.

The audit now lists all13 named supplementary surfaces, including VehicleReportDialog and VehicleSaleDialog omitted from the previous overlay list. Inventory inclusion alone is not acceptance. Wider overlay/state reconciliation and the recorded native-picker/staging/production limits remain open.


### Vehicle report and sale dialogs — 23 October 2026

Fixed a reproduced stale-session issue: signing out and back into the same account could confirm an old pending sale/report or leave the original dialog usable. Both dialogs now capture the account epoch, show localized expiry guidance, disable submission/reason changes and reject late success/duplicate acknowledgements. Reopen the action to use the new session. Report radio selection also uses a visible neutral in dark mode and burgundy in light mode.

32 focused decision cases passed, including four new idle/pending same-UID return regressions. Final full suite **1442 passed, six native-gallery-only skips**; analysis clean.16 native cases per platform passed;12 enlarged Arabic-light/Kurdish-dark failure/expiry captures inspected. Evidence: `tool/ui_review_artifacts/vehicle_dialog_current_{android,ios}.json`. Normal debug rebuild/restoration follows fixture review.

Auth and writes remain mocked. An already-sent backend request cannot be retracted locally; deployed report INSERT RLS and owner sold-status authorization remain staging checks. Wider screen/modal and other media verification remain open.


### Username editor recovery — 23 October 2026

The account username editor now keeps its route and draft until saving succeeds. Server failures show inline feedback and permit editing/retry; pending saves disable duplicate calls and dismissal. A captured account epoch rejects stale success after logout/login. The identifier stays LTR, typography is compact, and the username rules wrap without a fixed line limit. The repository RPC returns void; its existing success contract remains intact.

Nine focused username checks passed before adding focused-cancel and pending-disposal cases. Final full suite **1451 passed, six native-gallery-only skips**; analysis clean. Seven native cases/platform passed; four enlarged Arabic-light/Kurdish-dark captures inspected. Evidence: `tool/ui_review_artifacts/username_editor_{android,ios}.json`. A final brace-only lint correction does not alter reviewed behavior/layout. Normal debug rebuild/restoration follows fixture review.

Auth/RPC writes remain mocked; deployed username uniqueness/authorization remain staging checks. The account message destination sheet delayed-count/double-tap scenario and wider overlay/state/media reconciliation remain open.


### Message destination sheet — 23 October 2026

Fixed a reproduced delay where Messages was unavailable while its optional unread count loaded. The extracted MessageHubSheet opens immediately; notification count loading, failure, manual retry and ready states do not block either destination. Root opening/page guards and one-time sheet selection prevent stacked routes. The count query captures its original account and both sheet content and navigation use session epochs; returning to the same account requires reopening.

Nine focused host cases passed, including all locale/theme recovery states, repeated opening during a gated read, navigation before the count resolves, expired count suppression/reopen and the existing count-failure flow. Final full suite **1459 passed, six native-gallery-only skips**; analysis clean. Nine native cases per platform passed;12 enlarged Arabic-light/Kurdish-dark captures reviewed. Initial iOS module-precompile failure is preserved; the unchanged verbose retry built/launched and passed with exit0, without cache/settings changes. Evidence: `message_hub_current_android.json` and `message_hub_ios_diagnostic_retry.json` under `tool/ui_review_artifacts/`.

All auth/read data remains mocked. Deployed notification authorization/count correctness and broader screen/modal/media/staging reconciliation remain open. The active inventory now contains50 Dart sources,38 screen/startup entries,15 named supplementary surfaces and26 modal calls. Normal app restoration follows fixture review.


### Overlay evidence reconciliation — 23 October 2026

Reconciled PhotoGallery, OwnedVehicleDialog and SellerRatingDialog against their actual assertions, accepted native reports and12 re-inspected zoom/keyboard captures. All three component hashes and bundled font hashes match their native evidence.117 current gallery/owned-editor/seller-profile/locale checks passed. Product source is unchanged and the installed normal-build source/font manifest still matches. Native executions were reused rather than rerun; this revision makes no new device-run claim. Exact scope and limitations: `tool/ui_review_artifacts/overlay_evidence_crosswalk.json`.

VehicleOfferDialog remains open: prose still follows interface direction, and its old direct native reports do not match its current component. A hash match in unrelated native reports is insufficient to accept that surface. Remaining screen/modal/media and production/staging limits stay active.


### Offer form direction and current-font review — 23 October 2026

VehicleOfferDialog message text now follows its typed script while preserving selection/composing values; amounts remain LTR. Compact external labels, fields and title match the newer editors. Account epochs disable the old dialog after session changes and reject late acknowledgements on same-account return. Requests have a30-second bound; stable draft IDs and retained failure recovery remain.

22 focused offer checks passed. Full suite **1467 passed, six native-gallery-only skips**; analysis clean. Eight direct native cases/platform passed; eight draft/recovery captures inspected in Arabic light and Kurdish dark, including native keyboards. The body/title scroll under constrained height; caret and actions remain available, and the error footer retains the draft. Evidence: `tool/ui_review_artifacts/offer_current_{android,ios}.json`. These direct reports supersede the previous offer-specific acceptance gap.

Auth and offer mutations remain mocked. Deployed RLS/cross-account behavior and the broader screen/modal/media/staging audit remain open. Normal-app rebuild/restoration follows fixture review.


### Request and market/job editor consistency — 23 October 2026

CarRequestEditorDialog and GenericAdEditorDialog prose now follows typed script with the shared controller-preserving direction builder. Numeric fields stay LTR.13px external labels,14px inputs/dropdown values and20px bold titles align with the newer editors. Existing publication/recovery behavior remains covered by host fixtures.

116 affected checks passed before final title refinements; final product full suite **1479 passed, six native-gallery-only skips**; analysis clean.54 request checks passed after a fixture-only IME timing correction.24 direct native cases/platform passed, with16 draft-layout captures inspected. The initial Android composition test competed with the active IME; the final fixture unfocuses before injecting its synthetic composing range and retains exact assertions. The original focused-range request fixture passed on iOS. Product source is unchanged by that fixture correction. Reports: `remaining_editor_direction_final_android.json` and `remaining_editor_direction_ios.json` under `tool/ui_review_artifacts/`.

OTP overlay evidence was also reconciled against its current component/font hashes and four re-inspected native captures: keyboard/cancel geometry and invalid-code blocking are verified within the existing mocked-provider scope. No new OTP device run or real delivery is claimed.

Auth/uploads/publication remain mocked. Real picker entry points, deployed Storage/RLS and broader screen/modal-state reconciliation remain open. Body/title scrolling under constrained height is preserved; action footers remain separate. Normal rebuild/restoration follows fixture review.


### Market gallery and image editor — 23 October 2026

Fixed a confirmed RTL gallery defect: manually swapping chevrons combined with Flutter mirroring made the previous arrow point the wrong way. Base chevrons now mirror once, and48px targets align at image center. The image editor has a compact20px bold title.

Final56 focused gallery/editor/locale checks and full **1485 tests passed, six native-gallery-only skips**; analysis clean. Per platform: six corrected gallery cases and six image-editor partial-upload/database-retry cases passed (18 native executions including the superseded initial gallery run).16 accepted gallery/fullscreen/recovery captures inspected. Editor retries preserve completed uploads, reuse the failed object's path and keep the matching update payload.

The original gallery captures are retained as reversed-arrow defect evidence; final `market_gallery_direction_final_{android,ios}.json` supersedes them. Editor evidence in `market_overlay_current_{android,ios}.json` remains current because its component is unchanged by the arrow correction. Gallery scale1.6; recovery capture scale1.4 with separate1.6 host layout coverage. One known public photo is repeated across slots; download/decode is real, auth/uploads/database writes mocked.

All15 named supplementary surfaces now have revision-scoped review entries. This does not close the full screen/state completion audit or prove deployed Storage/RLS, other OS picker entry points or production publication. Normal app rebuild/restoration follows fixtures.


### Discovery completion-audit refresh — 23 October 2026

Verification-only refresh: application source and cached normal-build source/font manifest are unchanged.72 focused Home/car-grid/search/locale checks passed. Full suite **1490 passed, six native-gallery-only skips**; the final error→empty→populated-search sequence passed six additional strengthened fixture checks; analysis clean.

Per platform:8 Home recovery,12 car-grid and6 search error/empty cases passed, followed by6 populated-result recovery cases.24 enlarged Arabic-light/Kurdish-dark captures inspected. Reports: `discovery_completion_{android,ios}.json` and `discovery_populated_final_{android,ios}.json` under `tool/ui_review_artifacts/`. Backend responses are mocked; grid/result media placeholders are intentional. Real photo/carousel evidence remains separately scoped.

Updated stale top-level inventory/test totals and discovery acceptance entries. Current inventory:50 active Dart sources,38 screen/startup classes,15 named supplementary surfaces,26 modal invocations. This does not prove the full per-state/anonymous-modal completion audit or deployed services. Normal cached apps are restored after fixtures; no rebuild is needed for unchanged application source.

### Support and history modal audit refresh (2026-10-23)

Verification-only pass: all 26 imperative modal call sites are mapped in `tool/ui_modal_flow_crosswalk.json`. The shared `confirmAdminDeleteAd` helper is correctly identified as top-level rather than owned by the offer chat page.

72 focused support/history/locale checks passed. Fresh Android API31 and iOS26.5 QA runs passed 8 cases each (6 support contact/report, 2 history confirmation); 12 Arabic-light/Kurdish-dark enlarged-text captures were reviewed. Report editors used real native keyboard insets and remained above the keyboard. External sharing/contact services were mocked and history preferences isolated. These fixtures do not verify external-app delivery. Reports: `tool/ui_review_artifacts/modal_current_review_{android,ios}.json`.

Application source was unchanged; the source/font manifest matched the protected normal builds, which were restored and launched on Android and both iOS simulators after the fixtures. The broader per-screen/state completion audit remains open.

### Showroom form consistency refresh (2026-10-23)

Showroom setup now uses two quiet section cards, persistent13px labels,14px fields and neutral section icons, matching the business editor. Prose follows the entered script without replacing controllers; phone remains LTR. Existing save validation, draft retention, failed acknowledgement and retry behavior are preserved.

53 focused checks passed. Full suite:1493 passed,6 native-only gallery skips; analysis clean. Six enlarged-text showroom layout/recovery cases passed on each platform and eight Arabic-light/Kurdish-dark captures were reviewed. Evidence: `tool/ui_review_artifacts/showroom_compact_current_{android,ios}.json`, `showroom_compact_full.txt`, `showroom_compact_analysis.txt`. Auth/read/write remain mocked; deployed seller-showroom permissions and save behavior require staging.

Normal Android and iOS simulator builds succeeded and were installed/launched on Android API31 and both iOS26.5 devices. The source/font manifest and protected build cache were refreshed. Whole-app completion remains under audit.

### Account/admin loading-state verification (2026-10-23)

Ten list routes now have explicit delayed-read tests: My Ads, Messages, Sent Offers, Reviews, Reports dashboard, Business moderation, Activity, Alerts, Follows and Wallet review. Each asserts progress while the read is blocked, absence of premature empty/error feedback, then completed empty feedback with progress removed. These replace source-review-only loading evidence.

35 focused state/locale checks passed; analysis is clean. Ten cases passed on Android and ten on iOS. One representative Kurdish-dark loading capture per platform was reviewed; individual route assertions do not imply ten separate visual captures or a new large-text matrix. Reports: `tool/ui_review_artifacts/list_loading_current_{android,ios}.json`. All reads use isolated fixtures. App source is unchanged from the1493-test full-suite pass; normal builds were verified against source/font hashes, restored and launched afterward. Full screen-state reconciliation remains active.

### Market detail session fix (2026-10-23)

Market admin lookups and delete continuations now use account epochs. An old permission result or delete acknowledgement cannot affect a replacement session even when the same user signs back in. Controls clear and permissions are rechecked. The private image editor expires on session change, and its parent ignores obsolete results.

Three regressions passed on both native platforms: stale admin lookup, late delete completion and private editor expiry after same-user return. Full suite:1506 passed,6 native-only gallery skips. Analysis required explicit mounted checks duplicating the account-epoch helper's mounted predicate; final analysis is clean and all three affected regressions passed afterward. Both final normal builds succeeded. Evidence: `tool/ui_review_artifacts/market_session_current_{android,ios}.json`, `market_session_full.txt`, `market_session_analysis.txt`, `market_session_mounted_followup.txt`. Roles, RPCs and image writes remain mocked; deployed authorization needs staging. No new visual-capture claim is made.

### Complete page-state applicability inventory (2026-10-23)

All 38 active screens now have explicit loading/empty/error/populated applicability, distinguishing asynchronous page states from local draft forms, supplied listing models, static documents and inline/action/media/session states. Read the [screen-state table](tool/ui_screen_state_matrix.md); machine-readable source/hash/evidence locators are in `tool/ui_screen_state_matrix.json`. This closes the applicability inventory gap, not the remaining per-state acceptance audit. No application source changed; the current normal-build manifest still matches every source/font hash.

### Profile/settings/history state crosswalk (2026-10-23)

The screen-state matrix now links direct assertions for profile loading/error/loaded content, settings loading/read/write recovery, and history loading/error/populated/cleared-empty states. Twelve new profile/history delayed-read cases cover ar/ku/en and both themes. Light cases resolve successfully; dark cases fail then retry.120 account/settings/history/locale checks passed; analysis clean.

Six profile and six corrected history cases passed on each native platform. Eight Arabic-light/Kurdish-dark loading captures were reviewed. Initial history fixture error completion crossed native test zones; the corrected loader throws after a void gate, and both reruns passed. Initial failures are retained and superseded for history only. Reports: `tool/ui_review_artifacts/profile_history_current_{android,ios}.json` (profile scope) and `profile_history_final_{android,ios}.json` (corrected history scope). No new error-transition screenshot coverage is claimed.

No app source changed. Protected normal builds matched the source/font manifest and were restored/launched on Android and both iOS devices. Deployed profile permissions and broader state acceptance remain separate audit items.

### Seven-feed populated native refresh (2026-10-23)

Fresh populated captures replace historical component-identity evidence for Activity, Sent Offers, Reviews, Messages, Follows, Alerts and the Reports dashboard.14 native cases passed on Android and14 on iOS;28 Arabic-light/Kurdish-dark enlarged-text captures were reviewed. Long names/comments wrapped, ratings stayed separate, amounts remained readable and actions reachable. Reports confirmation flows ran with isolated mocks; no new confirmation screenshots are claimed.

Reports and durable logs: `tool/ui_review_artifacts/feed_populated_current_{android,ios}.json`. Current component/font hashes match, as did the root/ASCII source and fixtures before launch. The251-check host crosswalk remains the all-locale/theme reference. This closes the specific seven-screen populated refresh queue, not every screen-state or deployed-service requirement. No app source changed; normal apps matched the protected build manifest and were restored/launched on Android and both iOS devices.

### Initial seller/chat/admin loading verification (2026-10-23)

Direct delayed-read tests now cover initial seller profile, offer chat and admin listing access. Each displays progress before its response and resolves to the expected profile/messages/listing; premature empty/error/access denial is checked where relevant.99 seller/chat/admin/locale checks passed and analysis is clean. Three Arabic-light cases passed per native platform; six loading captures were reviewed. Evidence: `tool/ui_review_artifacts/initial_loading_current_{android,ios}.json`, `initial_loading_host.txt`, `initial_loading_analysis.txt`.

The state matrix also records direct discovery error/empty/result assertions without treating delayed query races as proof of loading UI. Existing all-locale/theme populated/recovery matrices retain their own scope. No app source changed; source/font manifest matched protected normal builds, restored and launched on Android and both iOS devices. Deployed network/auth/admin permissions remain staging checks.

### Discovery loading feedback (2026-10-23)

Home's required-car skeleton now has a visible progress bar and localized live-region label, with placeholder image announcements excluded. Selected-market and Search loading states have direct blocked-read assertions: pending requests show progress without premature empty/error feedback; completed empty responses remove loading and show the correct empty text.

55 focused checks passed. Full suite:1533 passed,6 native-only gallery skips; analysis clean. Twelve Home/Search delayed-read cases passed per native platform across ar/ku/en and both themes at1.6 scale. Twelve Arabic-light/Kurdish-dark captures were reviewed. Reports: `tool/ui_review_artifacts/discovery_loading_current_{android,ios}.json`; durable full/analysis logs: `discovery_loading_full.txt`, `discovery_loading_analysis.txt`. Reads/consent are isolated fixtures; no deployed latency/backend guarantee is claimed.

Both normal debug builds succeeded, protected build caches/source-font manifest were refreshed, and apps installed/launched on Android API31 and both iOS26.5 devices. Broader per-screen state and production-limit reconciliation remains active.

### Remaining screen assertion reconciliation (2026-10-23)

All 38 active screen entries now have direct assertion locators. A focused named-file follow-up for startup, requests, details and showroom passed94 checks; the product full-suite reference remains1533 passed with 6 native-only gallery skips. Referenced tests match the ASCII validation copy; product source/font hashes match installed normal builds. No app source changed. The [direct-state gap table](tool/ui_state_acceptance_gaps.md) lists8 still-unreconciled page states across7 screens. This queue does not replace the broader visual/action/staging completion audit.

### Direct page-state assertion queue closed (2026-10-23)

All8 previously unresolved page-state assertions across7 screens are now directly checked: requests loading/empty, Favorites/showroom loading, empty chat/admin lists, wallet configuration loading and business-package loading. Seven native cases passed per platform and16 Arabic-light captures were reviewed. Full suite:1540 passed,6 native-only gallery skips; analysis clean. Reports/logs: `tool/ui_review_artifacts/eight_state_current_{android,ios}.json`, `eight_state_full.txt`, `eight_state_analysis.txt`.

All38 screen entries and applicable page states have direct assertion references. This closes the specific assertion queue, while broader native visual/dependency and staging-limit reconciliation remains active. Fixtures are isolated; no deployed authorization/storage/payment claim is made. Product source is unchanged and normal apps were restored/launched on Android and both iOS devices after source/font manifest verification.

### Comparison/account/static current visual review (2026-10-23)

Fresh comparison, account login/signup/signed-in, About, privacy, terms and fines checks passed20 native cases per platform. Review exposed account display names inheriting interface direction; the name now follows entered content. Six follow-up cases per platform verify long Latin/Arabic names in all three interface locales.40 final captures were accepted across the two stages;8 earlier signed-in name captures are superseded. Scope details and durable logs: `tool/ui_review_artifacts/completion_visual_refresh_{android,ios}.json` and `account_name_current_{android,ios}.json`.

Full suite:1546 passed,6 native-only gallery skips; analysis clean. Both current normal debug builds succeeded and were installed/launched on Android and both iOS devices after protected-cache/manifest refresh. English and Arabic README summaries now distinguish current evidence from historical release artifacts and unverified deployed/store steps. The broader completion audit remains active.
