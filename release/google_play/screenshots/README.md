# Localized phone screenshots

24 selected PNGs: eight distinct full-page views for each supported language, organized in ar/, en/ and ku/. All are 1080 × 1920 pixels.

Each language contains the same sequence:

1. Home with loaded carousel listing.
2. Car listings with loaded photos.
3. Comparison of two real public cars.
4. Populated search results.
5. Support center.
6. About the app.
7. Settings.
8. Account and data deletion information.

No image viewer, modal, dialog or pop-up is included. Long pages naturally continue below the viewport. All 24 captures were refreshed and visually reviewed for version 1.0.1+5, with advertising and its settings controls removed. Visual review is recorded in review-manifest.json.

Captured on an isolated Android 15/API 35 emulator using the actual app UI through a debug integration-test entrypoint, PLAY_STORE_BUILD=true, no debug banner and reduced motion to pause the carousel. Public live listings are used without mocked content; comparison uses two of those actual listing records. Listing content such as brand/model names and location names retains its original language.

The native integration capture journey passed. Before every capture it waits for visible loading indicators to clear, all visible images to decode, and listing photos to render, and checks for widget exceptions. See artifacts/evidence/expanded-screenshot-test.txt and the per-language contact sheets for evidence. review-manifest.json records image hashes and dimensions.

These replace the previous mixed-language set; old captures are retained only under artifacts/evidence/previous-screenshot-selection. The rejected car-detail date-formatting and search-filter hint issues remain documented in evidence and are not represented as fixed. The selected set now corresponds to the version-code-5 ad-free source. Older evidence and builds do not describe its current UI.

Public listing photos remain subject to their owners' rights/consent. Obtain permission before store publication. The production blockers in the Play Console checklist still apply.
